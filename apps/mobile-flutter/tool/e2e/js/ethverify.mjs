// 独立的 ETH 地址派生 / 签名恢复工具（离线，用仓库根 node_modules 的 @noble/@scure）。
//
// 从 stdin 读一个 JSON，输出 JSON：
//   {"op":"derive","mnemonic":"...","path":"m/44'/60'/0'/0/0"}
//     → {"address":"0x...","publicKey":"04..."}
//   {"op":"recover","kind":"personal"|"raw","data":"<hex>","r":"<hex32>","s":"<hex32>","v":27|28|0|1}
//     → {"address":"0x..."}
//
// personal = EIP-191（"\x19Ethereum Signed Message:\n"+len+msg），raw = keccak256(data)。
import { mnemonicToSeedSync } from '@scure/bip39';
import { wordlist } from '@scure/bip39/wordlists/english.js';
import { HDKey } from '@scure/bip32';
import { secp256k1 } from '@noble/curves/secp256k1.js';
import { keccak_256 } from '@noble/hashes/sha3.js';

const hex = (u8) => Buffer.from(u8).toString('hex');
const unhex = (s) => Uint8Array.from(Buffer.from(s.replace(/^0x/, ''), 'hex'));

function toChecksum(addrLowerNoPrefix) {
  const h = keccak_256(Buffer.from(addrLowerNoPrefix, 'ascii'));
  let out = '';
  for (let i = 0; i < addrLowerNoPrefix.length; i++) {
    const c = addrLowerNoPrefix[i];
    if (!/[a-f]/.test(c)) { out += c; continue; }
    const nibble = i % 2 === 0 ? h[i >> 1] >> 4 : h[i >> 1] & 0x0f;
    out += nibble >= 8 ? c.toUpperCase() : c;
  }
  return '0x' + out;
}

function addressOf(pub65) {
  return toChecksum(hex(keccak_256(pub65.slice(1))).slice(-40));
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
  const hd = HDKey.fromMasterSeed(seed).derive(input.path);
  const pub = secp256k1.getPublicKey(hd.privateKey, false);
  out = { address: addressOf(pub), publicKey: hex(pub) };
} else if (input.op === 'recover') {
  const data = unhex(input.data || '');
  let hash;
  if (input.kind === 'personal') {
    const prefix = Buffer.from(`\x19Ethereum Signed Message:\n${data.length}`, 'utf8');
    hash = keccak_256(Buffer.concat([prefix, Buffer.from(data)]));
  } else {
    hash = keccak_256(data);
  }
  const v = Number(input.v);
  const recid = v >= 27 ? v - 27 : v;
  const sig = secp256k1.Signature
    .fromBytes(Buffer.concat([unhex(input.r), unhex(input.s)]), 'compact')
    .addRecoveryBit(recid);
  const pub = sig.recoverPublicKey(hash).toBytes(false);
  out = { address: addressOf(pub) };
} else {
  throw new Error('unknown op: ' + input.op);
}

process.stdout.write(JSON.stringify(out));
