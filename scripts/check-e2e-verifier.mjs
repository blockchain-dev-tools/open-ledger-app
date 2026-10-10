// Public BIP-39 vector only. Never send funds to this predictable wallet.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../apps/mobile-flutter/tool/e2e/js/ethverify.mjs', import.meta.url));
const result = JSON.parse(execFileSync(process.execPath, [script], {
  input: JSON.stringify({
    op: 'derive',
    mnemonic: [...Array(11).fill('abandon'), 'about'].join(' '),
    path: "m/44'/60'/0'/0/0",
  }),
  encoding: 'utf8',
}));
assert.equal(result.address, '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
assert.match(result.publicKey, /^04[0-9a-f]{128}$/);
console.log('Independent E2E verifier loaded and public-vector address matched.');
