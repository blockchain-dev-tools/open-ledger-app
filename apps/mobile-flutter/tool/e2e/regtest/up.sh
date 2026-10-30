#!/usr/bin/env bash
# 启动本机 Bitcoin Core regtest 节点（ADR-020）。
#
# 幂等：节点已在运行则直接返回 0。数据目录在仓库忽略的 `tmp/regtest`，
# 由 down.sh 清掉，因此重复执行不残留。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
# 规划工作区根（mono）：Bitcoin Core 解压到 mono/tmp/bitcoin/，不污染任何仓库。
MONO_ROOT="${BTC_MONO_ROOT:-$(cd "$REPO_ROOT/../.." && pwd)}"
DATADIR="${BTC_REGTEST_DATADIR:-$REPO_ROOT/tmp/regtest}"
RPC_PORT="${BTC_RPC_PORT:-18443}"
BITCOIND="${BITCOIND_BIN:-$(ls -d "$MONO_ROOT"/tmp/bitcoin/bitcoin-*/bin/bitcoind \
  "$HOME"/bitcoin/bitcoin-*/bin/bitcoind 2>/dev/null | tail -1 || true)}"
BITCOIN_CLI="${BITCOIN_CLI_BIN:-$(dirname "${BITCOIND:-/nonexistent}")/bitcoin-cli}"

if [[ ! -x "${BITCOIND:-}" ]]; then
  echo "[FAIL] 找不到 bitcoind。装到 mono/tmp/bitcoin/bitcoin-<version>/bin/ 或设置 BITCOIND_BIN。" >&2
  exit 1
fi

cli() { "$BITCOIN_CLI" -regtest -datadir="$DATADIR" -rpcport="$RPC_PORT" "$@"; }

if cli getblockcount >/dev/null 2>&1; then
  echo "[OK] regtest 已在运行，高度 $(cli getblockcount)"
  exit 0
fi

mkdir -p "$DATADIR"
"$BITCOIND" -regtest -txindex -fallbackfee=0.0001 \
  -datadir="$DATADIR" -rpcport="$RPC_PORT" -daemon >/dev/null

for _ in $(seq 1 60); do
  if cli getblockcount >/dev/null 2>&1; then break; fi
  sleep 0.5
done
if ! cli getblockcount >/dev/null 2>&1; then
  echo "[FAIL] bitcoind 启动后 30s 内 RPC 不可用，看 $DATADIR/regtest/debug.log" >&2
  exit 1
fi

# 出块钱包：资金全部来自挖矿，不依赖任何 faucet。
cli createwallet miner >/dev/null 2>&1 || true
MINER_ADDR="$(cli -rpcwallet=miner getnewaddress '' bech32)"
cli generatetoaddress 101 "$MINER_ADDR" >/dev/null

echo "[OK] regtest 已启动"
echo "     datadir=$DATADIR"
echo "     rpc=127.0.0.1:$RPC_PORT  height=$(cli getblockcount)  miner=$MINER_ADDR"
