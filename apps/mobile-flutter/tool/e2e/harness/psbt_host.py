"""`E1 04 SIGN_PSBT` 的主机侧：Merkle 树 + PSBTv2 构造 + `0xE000` 应答器。

设备只拿得到 Merkle 化的摘要，所有字段都要反过来向主机要。这个模块就是
「主机」那一半，与设备侧 `crates/chain-app-bitcoin/src/psbt.rs` / `flow.rs`
是两套代码：树、序列化、策略哈希都在这里独立实现。

三块：

1. **左完全树 Merkle**（官方 `merkle.md`）：`leaf = sha256(0x00 ‖ element)`，
   `node = sha256(0x01 ‖ left ‖ right)`，左子树取 `< n` 的最大 2 的幂。
2. **PSBTv2 构造**：把 global / 每个输入 / 每个输出的 map 变成
   `varint(size) ‖ keys_root ‖ vals_root`，再按 `E1 04` 的头格式拼出来。
3. **ClientCommandInterpreter**：回答设备发起的 `GET_PREIMAGE` /
   `GET_MERKLE_LEAF_PROOF` / `GET_MORE_ELEMENTS` / `YIELD`。

用法：

    host = PsbtHost()
    wallet_id = host.wallet_policy("wpkh(@0/**)", key_info)
    header = host.header(global_map, input_maps, output_maps, wallet_id)
    ...
    data = host.answer(request)   # request 是 0xE000 响应里去掉 SW 的部分
"""
from __future__ import annotations

import asyncio
import hashlib

from . import apdu
from .btc_tx import Tx, varint

# ── 左完全树 Merkle（与官方 merkle.md 一致） ───────────────────────────


def sha256(data: bytes) -> bytes:
    return hashlib.sha256(data).digest()


def element_hash(element: bytes) -> bytes:
    """叶子哈希：`sha256(0x00 ‖ element)`。"""
    return sha256(b"\x00" + element)


def combine(left: bytes, right: bytes) -> bytes:
    return sha256(b"\x01" + left + right)


def _largest_power_of_two_less_than(n: int) -> int:
    if n & (n - 1) == 0:
        return n // 2
    return 1 << (n.bit_length() - 1)


def root_of(leaves: list[bytes], begin: int, size: int) -> bytes:
    if size == 1:
        return leaves[begin]
    left = _largest_power_of_two_less_than(size)
    return combine(
        root_of(leaves, begin, left),
        root_of(leaves, begin + left, size - left),
    )


def proof_of(leaves: list[bytes], begin: int, size: int, index: int) -> list[bytes]:
    """证明自底向上排列（最深层在前），与设备的 `verify_leaf` 一致。"""
    if size == 1:
        return []
    left = _largest_power_of_two_less_than(size)
    if index < left:
        proof = proof_of(leaves, begin, left, index)
        proof.append(root_of(leaves, begin + left, size - left))
        return proof
    proof = proof_of(leaves, begin + left, size - left, index - left)
    proof.append(root_of(leaves, begin, left))
    return proof


# ── PSBTv2 map ─────────────────────────────────────────────────────────


class MapBuilder:
    """一个 PSBT map。序列化时按 key 字节升序（官方客户端的行为）。"""

    def __init__(self) -> None:
        self._entries: list[tuple[bytes, bytes]] = []

    def put(self, key: bytes, value: bytes) -> "MapBuilder":
        self._entries.append((key, value))
        return self

    def sorted_entries(self) -> list[tuple[bytes, bytes]]:
        return sorted(self._entries, key=lambda entry: entry[0])

    def __len__(self) -> int:
        return len(self._entries)


# PSBTv2 的 key type（BIP-370）。
GLOBAL_TX_VERSION = 0x02
GLOBAL_FALLBACK_LOCKTIME = 0x03
GLOBAL_INPUT_COUNT = 0x04
GLOBAL_OUTPUT_COUNT = 0x05
GLOBAL_VERSION = 0xFB

IN_NON_WITNESS_UTXO = 0x00
IN_WITNESS_UTXO = 0x01
IN_SIGHASH_TYPE = 0x03
IN_BIP32_DERIVATION = 0x06
IN_PREVIOUS_TXID = 0x0E
IN_OUTPUT_INDEX = 0x0F
IN_SEQUENCE = 0x10

OUT_BIP32_DERIVATION = 0x02
OUT_AMOUNT = 0x03
OUT_SCRIPT = 0x04

SIGHASH_DEFAULT = 0x00
SIGHASH_ALL = 0x01

# 默认钱包的 `wallet_hmac` 必须是 32 个零字节。
DEFAULT_WALLET_HMAC = bytes(32)


def read_varint(data: bytes, offset: int) -> tuple[int, int]:
    """返回 (value, new_offset)。"""
    first = data[offset]
    offset += 1
    if first < 0xFD:
        return first, offset
    if first == 0xFD:
        return int.from_bytes(data[offset:offset + 2], "little"), offset + 2
    if first == 0xFE:
        return int.from_bytes(data[offset:offset + 4], "little"), offset + 4
    return int.from_bytes(data[offset:offset + 8], "little"), offset + 8


# ── 主机 ───────────────────────────────────────────────────────────────


class PsbtHost:
    """保存所有预映像与树，并按客户端命令回答设备。"""

    def __init__(self) -> None:
        self._preimages: dict[bytes, bytes] = {}
        self._trees: dict[bytes, list[bytes]] = {}
        self._queue: list[bytes] = []
        self.requests = 0
        self.log: list[bytes] = []
        self.yields: list[bytes] = []

    @property
    def preimage_count(self) -> int:
        return len(self._preimages)

    # ── 注册 ──────────────────────────────────────────────────────────

    def add_preimage(self, preimage: bytes) -> bytes:
        """登记一份预映像，返回 `sha256(preimage)`。"""
        digest = sha256(preimage)
        self._preimages[digest] = preimage
        return digest

    def add_list(self, elements: list[bytes]) -> bytes:
        """把一串元素建成树并登记叶子预映像（`0x00 ‖ element`），返回根。"""
        if not elements:
            raise ValueError("空列表没有 Merkle 根")
        for element in elements:
            self.add_preimage(b"\x00" + element)
        leaves = [element_hash(element) for element in elements]
        root = root_of(leaves, 0, len(leaves))
        self._trees[root] = leaves
        return root

    def add_map(self, builder: MapBuilder) -> bytes:
        """返回 `varint(size) ‖ keys_root ‖ vals_root` 作为 map 的承诺。"""
        entries = builder.sorted_entries()
        keys_root = self.add_list([key for key, _ in entries])
        vals_root = self.add_list([value for _, value in entries])
        return varint(len(entries)) + keys_root + vals_root

    def wallet_policy(self, template: str, key_info: str) -> bytes:
        """默认单密钥钱包的策略哈希（`wallet_id`），并登记模板预映像。

        `key_info` 是 `[fingerprint/purpose'/coin'/account']xpub…`。设备解析出
        purpose / coin / account 后按脚本核对派生公钥，xpub 文本本身不参与校验。
        """
        template_bytes = template.encode()
        self.add_preimage(template_bytes)
        keys_root = self.add_list([key_info.encode()])
        # 设备侧 `parse_policy_header` 的布局：版本 2、空名字、模板长度与哈希、
        # 一个密钥、keys 树根。
        policy = (
            b"\x02"
            + bytes([0])
            + varint(len(template_bytes))
            + sha256(template_bytes)
            + varint(1)
            + keys_root
        )
        return self.add_preimage(policy)

    def header(
        self,
        global_map: MapBuilder,
        input_maps: list[MapBuilder],
        output_maps: list[MapBuilder],
        wallet_id: bytes,
    ) -> bytes:
        """拼出 `E1 04` 的数据：global 承诺 + 计数 + 输入/输出树根 + 钱包。"""
        global_commitment = self.add_map(global_map)
        inputs_root = self.add_list([self.add_map(m) for m in input_maps])
        outputs_root = self.add_list([self.add_map(m) for m in output_maps])
        return (
            global_commitment
            + varint(len(input_maps))
            + inputs_root
            + varint(len(output_maps))
            + outputs_root
            + wallet_id
            + DEFAULT_WALLET_HMAC
        )

    # ── 应答 ──────────────────────────────────────────────────────────

    def answer(self, request: bytes) -> bytes:
        """回答一条 `0xE000` 请求，返回 `F8 01` 的数据部分。"""
        if not request:
            raise ValueError("空的 client command")
        self.requests += 1
        self.log.append(request)
        code = request[0]

        if code == 0x40:  # GET_PREIMAGE
            digest = request[2:34]
            preimage = self._preimages.get(digest)
            if preimage is None:
                raise RuntimeError(f"主机没有预映像 {digest.hex()}")
            prefix = varint(len(preimage))
            sent = min(len(preimage), 255 - len(prefix) - 1)
            self._queue = [bytes([byte]) for byte in preimage[sent:]]
            return prefix + bytes([sent]) + preimage[:sent]

        if code == 0x41:  # GET_MERKLE_LEAF_PROOF
            root = request[1:33]
            size, offset = read_varint(request, 33)
            index, _ = read_varint(request, offset)
            leaves = self._trees.get(root)
            if leaves is None:
                raise RuntimeError(f"主机没有这棵树 {root.hex()}")
            if len(leaves) != size:
                raise RuntimeError(f"树大小不符：{len(leaves)} != {size}")
            proof = proof_of(leaves, 0, size, index)
            if 32 + 2 + 32 * len(proof) > 255:
                raise RuntimeError("证明太长，单帧装不下（需要分片，本期未用）")
            return (
                leaves[index]
                + bytes([len(proof), len(proof)])
                + b"".join(proof)
            )

        if code == 0x42:  # GET_MERKLE_LEAF_INDEX（本期设备不发）
            root = request[1:33]
            leaf = request[33:65]
            leaves = self._trees.get(root)
            if leaves is None:
                raise RuntimeError(f"主机没有这棵树 {root.hex()}")
            found = leaves.index(leaf) if leaf in leaves else 0
            return bytes([1 if leaf in leaves else 0]) + varint(found)

        if code == 0xA0:  # GET_MORE_ELEMENTS
            element_len = len(self._queue[0]) if self._queue else 0
            body = bytearray([0, element_len])
            count = 0
            while self._queue and len(body) + element_len <= 253:
                body += self._queue.pop(0)
                count += 1
            body[0] = count
            return bytes(body)

        if code == 0x10:  # YIELD
            self.yields.append(request[1:])
            return b""

        raise RuntimeError(f"未实现的 client command 0x{code:02x}")


def parse_yield(payload: bytes) -> tuple[int, bytes, bytes]:
    """`varint(input_index) ‖ pubkey_len:1 ‖ pubkey ‖ signature`。"""
    index, offset = read_varint(payload, 0)
    pubkey_len = payload[offset]
    offset += 1
    pubkey = payload[offset:offset + pubkey_len]
    signature = payload[offset + pubkey_len:]
    if len(pubkey) != pubkey_len or not signature:
        raise ValueError(f"YIELD 结构与声明不符：{payload.hex()}")
    return index, pubkey, signature


# ── 高层：构造一笔钱包交易 + 真机交互 ─────────────────────────────────


def path_components(path: str) -> list[int]:
    out = []
    for component in path.split("/")[1:]:
        value = int(component.rstrip("'h"))
        if component[-1] in "'h":
            value |= 0x80000000
        out.append(value)
    return out


def derivation_value(fingerprint: str, path: str) -> bytes:
    """PSBT 的 `bip32_derivation` 值：`fingerprint(4) ‖ path(4B LE)×n`（BIP-174）。"""
    return bytes.fromhex(fingerprint) + b"".join(
        component.to_bytes(4, "little") for component in path_components(path)
    )


def build_psbt(
    host: PsbtHost,
    *,
    template: str,
    key_info: str,
    tx: Tx,
    prevouts: list[tuple[int, bytes]],
    input_paths: dict[int, tuple[str, bytes]],
    output_paths: dict[int, tuple[str, bytes]],
    as_bytes: bool = False,
) -> bytes:
    """把交易骨架写成 PSBTv2。

    `as_bytes=False`（默认）返回 `E1 04` 的 Merkleized 头；`as_bytes=True`
    返回完整 PSBTv2 字节串（官方客户端库要的是这个）。两者用同一组 map。
    """
    if key_info[0] != "[" or len(key_info) < 9:
        raise ValueError("key_info 必须形如 `[fingerprint/path]xpub…`")
    fingerprint = key_info[1:9]

    global_map = (
        MapBuilder()
        .put(bytes([GLOBAL_VERSION]), (2).to_bytes(4, "little"))
        .put(bytes([GLOBAL_TX_VERSION]),
             tx.version.to_bytes(4, "little", signed=True))
        .put(bytes([GLOBAL_FALLBACK_LOCKTIME]), tx.locktime.to_bytes(4, "little"))
        .put(bytes([GLOBAL_INPUT_COUNT]), varint(len(tx.inputs)))
        .put(bytes([GLOBAL_OUTPUT_COUNT]), varint(len(tx.outputs)))
    )

    input_maps = []
    for index, txin in enumerate(tx.inputs):
        value, script = prevouts[index]
        builder = (
            MapBuilder()
            # PSBTv2 的 txid 用交易的内部字节序（与 outpoint 一致）。
            .put(bytes([IN_PREVIOUS_TXID]), bytes.fromhex(txin.txid)[::-1])
            .put(bytes([IN_OUTPUT_INDEX]), txin.vout.to_bytes(4, "little"))
            .put(bytes([IN_SEQUENCE]), txin.sequence.to_bytes(4, "little"))
            .put(bytes([IN_WITNESS_UTXO]),
                 value.to_bytes(8, "little") + varint(len(script)) + script)
        )
        if index in input_paths:
            path, pubkey = input_paths[index]
            builder.put(bytes([IN_BIP32_DERIVATION]) + pubkey,
                        derivation_value(fingerprint, path))
        input_maps.append(builder)

    output_maps = []
    for index, txout in enumerate(tx.outputs):
        builder = (
            MapBuilder()
            .put(bytes([OUT_AMOUNT]), txout.value.to_bytes(8, "little"))
            .put(bytes([OUT_SCRIPT]), txout.script)
        )
        if index in output_paths:
            path, pubkey = output_paths[index]
            builder.put(bytes([OUT_BIP32_DERIVATION]) + pubkey,
                        derivation_value(fingerprint, path))
        output_maps.append(builder)

    if as_bytes:
        return psbt_bytes(global_map, input_maps, output_maps)
    wallet_id = host.wallet_policy(template, key_info)
    return host.header(global_map, input_maps, output_maps, wallet_id)


def psbt_bytes(
    global_map: MapBuilder,
    input_maps: list[MapBuilder],
    output_maps: list[MapBuilder],
) -> bytes:
    """完整 PSBTv2 字节串：魔数 + 每个 map 以 0x00 结尾，条目按 key 升序。"""
    out = bytearray(b"psbt\xff")
    for mapping in [global_map, *input_maps, *output_maps]:
        for key, value in mapping.sorted_entries():
            out += varint(len(key)) + key + varint(len(value)) + value
        out.append(0)
    return bytes(out)


async def sign_with_device(
    sess,
    ble,
    host: PsbtHost,
    header: bytes,
    *,
    expect_texts: tuple[str, ...] = (),
    decision: str = "approve",
    timeout_wait: float = 0.0,
    recv_timeout: float = 8.0,
) -> tuple[int, bytes, int]:
    """发 `E1 04`，按设备的 `0xE000` 逐条回答，直到拿到最终状态字。

    返回 `(轮数, 最终数据, 最终 SW)`。审阅页出现时先核对 `expect_texts`
    （每项都是「页面文本包含」），再按 `decision` 点 Approve / Reject，或
    `timeout` 干等 `timeout_wait` 秒让确认页超时。签名负载在 `host.yields`。
    """
    if decision not in ("approve", "reject", "timeout"):
        raise ValueError(f"未知 decision: {decision}")

    ble.send(apdu.btc_sign_psbt(header))
    rounds = 0
    while True:
        try:
            raw = ble.recv(timeout=recv_timeout)
        except RuntimeError:
            # 没有响应 = 设备停在审阅页等用户。
            screens = await sess.app.wait_for_screen(
                {"TransactionScreen"}, timeout=2.0)
            if "TransactionScreen" not in screens:
                raise RuntimeError(f"既没有协议响应也没有确认页：{screens}")
            await sess.app.settle(0.8)
            for needle in expect_texts:
                if not await sess.app.has_text(needle):
                    raise RuntimeError(f"审阅页缺少 {needle!r}")
            if decision == "timeout":
                await asyncio.sleep(timeout_wait)
            else:
                key = "sign-approve" if decision == "approve" else "sign-reject"
                hit = await sess.app.tap_key(key)
                if not hit.startswith("TAPPED"):
                    raise RuntimeError(f"点不到 {key}：{hit!r}")
            raw = ble.recv(timeout=30)

        data, sw = apdu.parse_response(raw)
        if sw == 0xE000:
            if not data:
                raise RuntimeError("0xE000 响应里没有 client command")
            rounds += 1
            ble.send(apdu.btc_continue(host.answer(data)))
            continue
        return rounds, data, sw
