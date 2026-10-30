#!/usr/bin/env bash
# 打印 regtest 状态：高度、钱包、余额。未运行时返回非 0。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
MONO_ROOT="${BTC_MONO_ROOT:-$(cd "$REPO_ROOT/../.." && pwd)}"
DATADIR="${BTC_REGTEST_DATADIR:-$REPO_ROOT/tmp/regtest}"
RPC_PORT="${BTC_RPC_PORT:-18443}"
BITCOIN_CLI="${BITCOIN_CLI_BIN:-$(ls -d "$MONO_ROOT"/tmp/bitcoin/bitcoin-*/bin/bitcoin-cli \
  "$HOME"/bitcoin/bitcoin-*/bin/bitcoin-cli 2>/dev/null | tail -1 || true)}"

if [[ ! -x "${BITCOIN_CLI:-}" ]]; then
  echo "[FAIL] 找不到 bitcoin-cli" >&2
  exit 1
fi

CLI=("$BITCOIN_CLI" -regtest -datadir="$DATADIR" -rpcport="$RPC_PORT")
if ! "${CLI[@]}" getblockcount >/dev/null 2>&1; then
  echo "[FAIL] regtest 未运行（datadir=$DATADIR）" >&2
  exit 1
fi

echo "height=$("${CLI[@]}" getblockcount)"
echo "wallets=$("${CLI[@]}" listwallets)"
echo "miner balance=$("${CLI[@]}" -rpcwallet=miner getbalance 2>/dev/null || echo n/a)"
