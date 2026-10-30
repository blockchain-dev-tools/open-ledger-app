#!/usr/bin/env bash
# 停止 regtest 节点并删除数据目录（ADR-020：可重复、无残留）。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
MONO_ROOT="${BTC_MONO_ROOT:-$(cd "$REPO_ROOT/../.." && pwd)}"
DATADIR="${BTC_REGTEST_DATADIR:-$REPO_ROOT/tmp/regtest}"
RPC_PORT="${BTC_RPC_PORT:-18443}"
BITCOIN_CLI="${BITCOIN_CLI_BIN:-$(ls -d "$MONO_ROOT"/tmp/bitcoin/bitcoin-*/bin/bitcoin-cli \
  "$HOME"/bitcoin/bitcoin-*/bin/bitcoin-cli 2>/dev/null | tail -1 || true)}"

if [[ -x "${BITCOIN_CLI:-}" ]]; then
  "$BITCOIN_CLI" -regtest -datadir="$DATADIR" -rpcport="$RPC_PORT" stop >/dev/null 2>&1 || true
  for _ in $(seq 1 40); do
    "$BITCOIN_CLI" -regtest -datadir="$DATADIR" -rpcport="$RPC_PORT" getblockcount \
      >/dev/null 2>&1 || break
    sleep 0.5
  done
fi

rm -rf "$DATADIR"
echo "[OK] regtest 已停止，数据目录已删除：$DATADIR"
