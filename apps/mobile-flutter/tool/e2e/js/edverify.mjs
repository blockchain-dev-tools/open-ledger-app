// 独立的 Ed25519（SLIP-10 派生 + 验签）工具（离线，用仓库根 node_modules）。
//
// 从 stdin 读一个 JSON，输出 JSON：
//   {"op":"derive","mnemonic":"...","path":"m/44'/501'/0'/0'"}
//     → {"publicKey":"<hex32>"}
//   {"op":"verify","publicKey":"<hex32>","message":"<hex>","signature":"<hex64>"}
//     → {"ok":true}（失败则抛错）
//
// 派生用 HMAC-SHA512 手写 SLIP-10，验签用 @noble/curves 的 ed25519，
// 与设备侧 Rust（ed25519-dalek + 自家 SLIP-10）是两套代码。

import { mnemonicToSeedSync } from '@scure/bip39';
import { hmac } from '@noble/hashes/hmac.js';
import { sha512 } from '@noble/hashes/sha2.js';
import { ed25519 } from '@noble/curves/ed25519.js';

const hex = (u8) => Buffer.from(u8).toString('hex');
const unhex = (s) => Uint8Array.from(Buffer.from(s.replace(/^0x/, ''), 'hex'));

function slip10PrivateKey(seed, path) {
  let I = hmac(sha512, new TextEncoder().encode('ed25519 seed'), seed);
  let kl = I.slice(0, 32);
  let kr = I.slice(32);
  for (const segment of path.split('/').slice(1)) {
    if (!segment.endsWith("'")) {
      throw new Error(`SLIP-10 Ed25519 requires hardened components: ${segment}`);
    }
    const index = (parseInt(segment.slice(0, -1), 10) | 0x80000000) >>> 0;
    const data = new Uint8Array(37);
    data[0] = 0;
    data.set(kl, 1);
    data[33] = (index >>> 24) & 0xff;
    data[34] = (index >>> 16) & 0xff;
    data[35] = (index >>> 8) & 0xff;
    data[36] = index & 0xff;
    I = hmac(sha512, kr, data);
    kl = I.slice(0, 32);
    kr = I.slice(32);
  }
  return kl;
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

if (input.op === 'derive') {
  const seed = mnemonicToSeedSync(input.mnemonic, '');
  const privateKey = slip10PrivateKey(seed, input.path);
  out = { publicKey: hex(ed25519.getPublicKey(privateKey)) };
} else if (input.op === 'verify') {
  const ok = ed25519.verify(unhex(input.signature), unhex(input.message), unhex(input.publicKey));
  if (!ok) throw new Error('ed25519 signature does not verify');
  out = { ok: true };
} else {
  throw new Error('unknown op: ' + input.op);
}

process.stdout.write(JSON.stringify(out));
