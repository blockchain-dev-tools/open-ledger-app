// M5 互操作：用官方 `@ledgerhq/hw-app-btc` 驱动真机签 PSBT。
//
// 这个脚本只做两件事：把官方 Transport 的 `exchange()` 转发到本机 TCP
// （由 `harness/apdu_bridge.py` 接到 BLE），以及调用官方 `signPsbtBuffer`。
// 所有 PSBT/Merkle/客户端命令逻辑都在官方库里，不在我们自己的 harness 里。
//
// 用法：node official_btc_sign.mjs <port> <psbt-hex> <account-path> <address-format>
// 输出：{"tx":"<hex>","psbt":"<hex>"} 或 {"error":"..."}
import net from 'node:net';
import { createRequire } from 'node:module';

// `@ledgerhq/hw-transport` 的 ESM 构建在 Node 下缺少扩展名（lib-es 里 import
// './errors'），直接 import 会 ERR_MODULE_NOT_FOUND；CJS 构建是完整的。
const require = createRequire(import.meta.url);
const Transport = require('@ledgerhq/hw-transport').default;
const Btc = require('@ledgerhq/hw-app-btc').default;

const [port, psbtHex, accountPath, addressFormat] = process.argv.slice(2);
if (!port || !psbtHex || !accountPath || !addressFormat) {
  console.error('usage: node official_btc_sign.mjs <port> <psbt-hex> <account-path> <bech32|bech32m|legacy|p2sh>');
  process.exit(2);
}

class TcpTransport extends Transport {
  constructor(socket) {
    super();
    this.socket = socket;
    this.buffer = '';
    this.waiting = [];
    socket.setEncoding('utf8');
    socket.on('data', (chunk) => {
      this.buffer += chunk;
      let index;
      while ((index = this.buffer.indexOf('\n')) >= 0) {
        const line = this.buffer.slice(0, index);
        this.buffer = this.buffer.slice(index + 1);
        const resolve = this.waiting.shift();
        if (resolve) resolve(JSON.parse(line));
      }
    });
  }

  async exchange(apdu) {
    const reply = await new Promise((resolve, reject) => {
      this.waiting.push(resolve);
      this.socket.write(`${JSON.stringify({ apdu: apdu.toString('hex') })}\n`, (error) => {
        if (error) reject(error);
      });
    });
    if (reply.error) throw new Error(reply.error);
    return Buffer.from(reply.response, 'hex');
  }

  async close() {
    this.socket.end();
  }
}

const socket = net.createConnection({ host: '127.0.0.1', port: Number(port) });
await new Promise((resolve, reject) => {
  socket.once('connect', resolve);
  socket.once('error', reject);
});

try {
  const transport = new TcpTransport(socket);
  const app = new Btc({ transport, currency: 'bitcoin_regtest' });
  const result = await app.signPsbtBuffer(Buffer.from(psbtHex, 'hex'), {
    finalizePsbt: true,
    accountPath,
    addressFormat,
    knownAddressDerivations: new Map(),
  });
  process.stdout.write(`${JSON.stringify({
    tx: result.tx,
    psbt: result.psbt ? result.psbt.toString('hex') : null,
  })}\n`);
  await transport.close();
} catch (error) {
  process.stdout.write(`${JSON.stringify({ error: String(error && error.stack || error) })}\n`);
  process.exitCode = 1;
} finally {
  socket.end();
}
