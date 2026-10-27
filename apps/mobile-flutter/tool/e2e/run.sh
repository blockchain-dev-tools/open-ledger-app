#!/usr/bin/env bash
# Open Ledger App 真机 E2E harness runner（attach + VM Service evaluate，零重建）。
#
# 与 integration_test/run.sh 的区别：那套是 Flutter 官方入口，每个场景要重新构建安装；
# 本 harness 复用已装的 debug 包，通过 flutter attach + evaluate 驱动，秒级起停。
#
# 用法：
#   ./tool/e2e/run.sh                # 跑全部用例
#   ./tool/e2e/run.sh sign           # 只跑文件名含 "sign" 的用例
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
export PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}"

FILTER="${1:-}"
# 不用 `mapfile`：macOS 自带的 bash 3.2 没有这个内建命令。
FILES=()
while IFS= read -r line; do
  if [[ -n "$line" ]]; then
    FILES+=("$line")
  fi
done < <(ls tests/*.py 2>/dev/null | grep -vE '/_' || true)
if [[ -n "$FILTER" && ${#FILES[@]} -gt 0 ]]; then
  MATCHED=()
  for file in "${FILES[@]}"; do
    if [[ "$file" == *"$FILTER"* ]]; then
      MATCHED+=("$file")
    fi
  done
  if [[ ${#MATCHED[@]} -gt 0 ]]; then
    FILES=("${MATCHED[@]}")
  else
    FILES=()
  fi
fi
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "没有匹配的用例（filter='${FILTER}'）。" >&2
  exit 1
fi

echo "用例: ${#FILES[@]} 个"
printf '  - %s\n' "${FILES[@]}"

FAILED=()
for file in "${FILES[@]}"; do
  echo
  echo "── 跑 $file ──────────────────────────────────────────"
  if python3 -u "$file"; then
    echo "✓ PASS $file"
  else
    echo "✗ FAIL $file"
    FAILED+=("$file")
  fi
done

echo
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "全部通过（${#FILES[@]} 个用例）。"
else
  echo "失败 ${#FAILED[@]}/${#FILES[@]}："
  printf '  - %s\n' "${FAILED[@]}"
  exit 1
fi
