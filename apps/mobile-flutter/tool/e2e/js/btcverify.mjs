// 独立的 BTC 地址派生 / Schnorr 验签（离线，用仓库根 node_modules 的 @noble/@scure）。
//
// 从 stdin 读一个 JSON，输出 JSON：
//   {"op":"address","mnemonic":"...","path":"m/84'/0'/0'/0/0","type":"p2wpkh"}
//     → {"address":"bc1q…","publicKey":"02…"}
//   {"op":"schnorr-verify","sighash":"<hex32>","hashType":0,"signature":"<hex64>",
//    "mnemonic":"...","path":"m/86'/0'/0'/0/0"}
//     → {"ok":true,"outputKey":"<hex32>"}
//
// 与设备侧的 Rust 实现（k256 + 自写 bech32/base58check）完全独立：这里用
// @noble/curves 与 @noble/hashes，编码在 harness/btcaddr.py 里另行实现。
import { mnemonicToSeedSync } from '@scure/bip39';
import { HDKey } from '@scure/bip32';
import { secp256k1, schnorr } from '@noble/curves/secp256k1.js';
import { sha256 } from '@noble/hashes/sha2.js';
import { ripemd160 } from '@noble/hashes/legacy.js';

const hex = (u8) => Buffer.from(u8).toString('hex');
const unhex = (s) => Uint8Array.from(Buffer.from(s.replace(/^0x/, ''), 'hex'));

function hash160(bytes) {
  return ripemd160(sha256(bytes));
}

/** Taproot key-path only 的输出公钥（x-only，32B），BIP-341。 */
function taprootOutputKey(compressedPubkey) {
  const internal = compressedPubkey.slice(1);
  const point = schnorr.utils.lift_x(BigInt('0x' + hex(internal)));
  const tweak = schnorr.utils.taggedHash('TapTweak', internal);
  const tweakScalar = secp256k1.Point.Fn.fromBytes(tweak);
  const output = point.add(secp256k1.Point.BASE.multiply(tweakScalar));
  return schnorr.utils.pointToBytes(output);
}

function addressFor(type, pub) {
  const h160 = hash160(pub);
  switch (type) {
    case 'p2pkh':
      return { prefix: 0x00, payload: h160 };
    case 'p2sh-p2wpkh': {
      const script = Uint8Array.from([0x00, 0x14, ...h160]);
      return { prefix: 0x05, payload: hash160(script) };
    }
    case 'p2wpkh':
      return { witnessVersion: 0, program: h160 };
    case 'p2tr':
      return { witnessVersion: 1, program: taprootOutputKey(pub) };
    default:
      throw new Error(`unknown address type ${type}`);
  }
}

function readStdin() {
  return new Promise((resolve) => {
    let buf = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (d) => (buf += d));
    process.stdin.on('end', () => resolve(buf));
  });
}

const input = JSON.parse((await readStdin()) || '{}');
let out;

if (input.op === 'address') {
  const seed = mnemonicToSeedSync(input.mnemonic, '');
  const node = HDKey.fromMasterSeed(seed).derive(input.path);
  const pub = secp256k1.getPublicKey(node.privateKey, true);
  const encoding = addressFor(input.type, pub);
  out = { publicKey: hex(pub) };
  // 字节数组统一转成十六进制字符串，Python 侧再拼出地址文本。
  if (encoding.program) {
    out.encoding = { witnessVersion: encoding.witnessVersion, program: hex(encoding.program) };
  } else {
    out.encoding = { prefix: encoding.prefix, payload: hex(encoding.payload) };
  }
} else if (input.op === 'schnorr-verify') {
  const seed = mnemonicToSeedSync(input.mnemonic, '');
  const node = HDKey.fromMasterSeed(seed).derive(input.path);
  const pub = secp256k1.getPublicKey(node.privateKey, true);
  const outputKey = taprootOutputKey(pub);
  let message = unhex(input.sighash);
  if (input.hashType) message = Uint8Array.from([...message, input.hashType]);
  out = {
    ok: schnorr.verify(unhex(input.signature), message, outputKey),
    outputKey: hex(outputKey),
  };
} else {
  throw new Error(`unknown op ${input.op}`);
}

process.stdout.write(JSON.stringify(out));
