"""APDU 构造与解析（与 `protocols/apdu/apdu_constants.dart` 对齐）。

线格式：请求 `[CLA][INS][P1][P2]([LC][data])`；响应 `[data...][SW1][SW2]`。
"""
from __future__ import annotations

CLA_OS = 0xE0
CLA_BTC = 0xE1
CLA_SUI = 0x07
INS_OPEN_APP = 0xD8
INS_GET_PUBLIC_KEY = 0x02
INS_SIGN_ETH_TX = 0x04
INS_GET_APP_CONFIG = 0x06
INS_SIGN_PERSONAL = 0x08
INS_SIGN_EIP712 = 0x0C
INS_BTC_GET_PUBLIC_KEY = 0x40
INS_BTC_SIGN_TX = 0x44
INS_SOL_VERSION = 0x04
INS_SOL_GET_ADDR = 0x05
INS_SOL_SIGN = 0x06
INS_SUI_GET_PUBLIC_KEY = 0x02
INS_SUI_SIGN_TX = 0x04
INS_TRON_GET_ADDRESS = 0x02
INS_TRON_SIGN_TX = 0x04
INS_TRON_CONFIG = 0x06

SW_SUCCESS = 0x9000

ETH_PATH = "m/44'/60'/0'/0/0"
BTC_PATH = "m/84'/0'/0'/0/0"
SOL_PATH = "m/44'/501'/0'/0'"
SUI_PATH = "m/44'/784'/0'/0'/0'"
TRON_PATH = "m/44'/195'/0'/0/0"

# 固定测试钱包（abandon ×11 + about）在 ETH_PATH 上的地址（EIP-55）
TEST_ETH_ADDRESS = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"


def encode_path(path: str) -> bytes:
    """`m/44'/60'/0'/0/0` → `[depth(1B)][component(4B BE)]*`（无 0x00 前缀）。"""
    comps = [c for c in path.split("/")[1:] if c]
    out = bytearray([len(comps)])
    for c in comps:
        hardened = c[-1] in "'hH"
        value = int(c.rstrip("'hH"))
        if hardened:
            value |= 0x80000000
        out += value.to_bytes(4, "big")
    return bytes(out)


def apdu(cla: int, ins: int, p1: int, p2: int, data: bytes = b"") -> bytes:
    head = bytes([cla, ins, p1, p2])
    return head + bytes([len(data)]) + data if data else head


def open_app(name: str = "Ethereum") -> bytes:
    return apdu(CLA_OS, INS_OPEN_APP, 0x00, 0x00, name.encode())


def get_public_key(path: str = ETH_PATH, p1: int = 0x00, p2: int = 0x00) -> bytes:
    """P1=0x00 不确认（P1=0x01 会触发地址确认 UI）。"""
    return apdu(CLA_OS, INS_GET_PUBLIC_KEY, p1, p2, encode_path(path))


def sign_personal_message(message: bytes, path: str = ETH_PATH) -> bytes:
    """EIP-191 消息签名。整条消息必须放在单个 APDU 内（≤ 255B）。"""
    data = encode_path(path) + len(message).to_bytes(4, "big") + message
    return apdu(CLA_OS, INS_SIGN_PERSONAL, 0x00, 0x00, data)


def sign_eth_transaction(rlp: bytes, path: str = ETH_PATH) -> list[bytes]:
    """返回按 255B 分块的 APDU 列表：首块 P1=0x00（带 path），续块 P1=0x80。"""
    head = encode_path(path) + rlp
    first_cap = 255
    chunks = [head[:first_cap]]
    rest = head[first_cap:]
    while rest:
        chunks.append(rest[:255])
        rest = rest[255:]
    out = [apdu(CLA_OS, INS_SIGN_ETH_TX, 0x00, 0x00, chunks[0])]
    for c in chunks[1:]:
        out.append(apdu(CLA_OS, INS_SIGN_ETH_TX, 0x80, 0x00, c))
    return out


def sign_eip712(domain_hash: bytes, struct_hash: bytes, path: str = ETH_PATH) -> bytes:
    """EIP-712 V0 单步：`[path][domainHash(32)][structHash(32)]`，P1=0x00/P2=0x00。"""
    if len(domain_hash) != 32 or len(struct_hash) != 32:
        raise ValueError("domain_hash / struct_hash 必须是 32 字节")
    return apdu(CLA_OS, INS_SIGN_EIP712, 0x00, 0x00,
                encode_path(path) + domain_hash + struct_hash)


def btc_get_public_key(path: str = BTC_PATH) -> bytes:
    """BTC GET_WALLET_PUBLIC_KEY：返回 P2WPKH 地址（ASCII）。"""
    return apdu(CLA_BTC, INS_BTC_GET_PUBLIC_KEY, 0x00, 0x00, encode_path(path))


def btc_sign(sighashes: list[bytes], path: str = BTC_PATH) -> bytes:
    """多输入签名：`[path][count][sighash(32)]*count`。"""
    if not sighashes or len(sighashes) > 16:
        raise ValueError("sighashes 数量必须在 1..=16")
    for sighash in sighashes:
        if len(sighash) != 32:
            raise ValueError("每个 sighash 必须是 32 字节")
    data = encode_path(path) + bytes([len(sighashes)]) + b"".join(sighashes)
    return apdu(CLA_BTC, INS_BTC_SIGN_TX, 0x00, 0x00, data)


def parse_response(resp: bytes) -> tuple[bytes, int]:
    """返回 (data, sw)。"""
    if len(resp) < 2:
        raise ValueError(f"响应过短: {resp.hex()}")
    return resp[:-2], (resp[-2] << 8) | resp[-1]


def parse_signature(data: bytes) -> tuple[int, bytes, bytes]:
    """签名响应 `v(1)+r(32)+s(32)` → (v, r, s)。"""
    if len(data) != 65:
        raise ValueError(f"签名数据长度应为 65，实际 {len(data)}: {data.hex()}")
    return data[0], data[1:33], data[33:65]


def parse_eth_address(data: bytes) -> str:
    """地址响应 `0x41 + pub(65) + 0x28 + ascii(40)` → '0x...'（无 EIP-55 大小写）。"""
    if len(data) < 1 + 65 + 1:
        raise ValueError(f"地址响应过短: {data.hex()}")
    pub_len = data[0]
    pub = data[1:1 + pub_len]
    addr_len = data[1 + pub_len]
    ascii_addr = data[2 + pub_len:2 + pub_len + addr_len].decode("ascii")
    return "0x" + ascii_addr, pub


# ── Solana（CLA 0xE0，按 OPEN_APP 选择 INS 表） ──────────────────────

def sol_get_version() -> bytes:
    return apdu(CLA_OS, INS_SOL_VERSION, 0x00, 0x00)


def sol_get_address(path: str = SOL_PATH, confirm: bool = False) -> bytes:
    return apdu(CLA_OS, INS_SOL_GET_ADDR, 0x01 if confirm else 0x00, 0x00,
                encode_path(path))


def sol_sign(message: bytes, path: str = SOL_PATH) -> bytes:
    """单块签名：`[path][message]`。"""
    return apdu(CLA_OS, INS_SOL_SIGN, 0x00, 0x00, encode_path(path) + message)


# ── Sui（CLA 0x07） ──────────────────────────────────────────────────

def sui_get_public_key(path: str = SUI_PATH) -> bytes:
    return apdu(CLA_SUI, INS_SUI_GET_PUBLIC_KEY, 0x00, 0x00, encode_path(path))


def sui_sign(message: bytes, path: str = SUI_PATH) -> bytes:
    return apdu(CLA_SUI, INS_SUI_SIGN_TX, 0x00, 0x00, encode_path(path) + message)


# ── Tron（CLA 0xE0，按 OPEN_APP 选择 INS 表） ────────────────────────

def tron_get_address(path: str = TRON_PATH) -> bytes:
    return apdu(CLA_OS, INS_TRON_GET_ADDRESS, 0x00, 0x00, encode_path(path))


def tron_get_version() -> bytes:
    return apdu(CLA_OS, INS_TRON_CONFIG, 0x00, 0x00)


def tron_sign_tx(payload: bytes, path: str = TRON_PATH) -> bytes:
    """单块签名：P1=0x10（官方 hw-app-trx 单块即签）。"""
    return apdu(CLA_OS, INS_TRON_SIGN_TX, 0x10, 0x00, encode_path(path) + payload)


def parse_tron_address(data: bytes) -> tuple[bytes, str]:
    """`[pub_len][65B pub][addr_len][ascii]` → (pubkey, address)。"""
    if len(data) < 1 + 65 + 1:
        raise ValueError(f"Tron 地址响应过短: {data.hex()}")
    pub_len = data[0]
    pub = data[1:1 + pub_len]
    addr_len = data[1 + pub_len]
    address = data[2 + pub_len:2 + pub_len + addr_len].decode("ascii")
    return pub, address
