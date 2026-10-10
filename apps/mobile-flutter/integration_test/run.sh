#!/usr/bin/env bash
# 真机端到端测试 runner —— 原生 integration_test（非 Maestro）。
#
# 用法：
#   ./integration_test/run.sh                      # 自动选唯一在线设备，跑全部场景
#   ./integration_test/run.sh -d <device-id>           # 指定设备
#   ./integration_test/run.sh lockout              # 只跑文件名匹配 "lockout" 的场景
#
# 注意：每个场景文件都是独立入口，会各自触发一次 Gradle 构建 + 安装；
#      首次或改了 Dart 代码后较慢，之后是增量构建。
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIR"

DEVICE=""
FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device) DEVICE="${2:?--device 需要参数}"; shift 2 ;;
    -h|--help)   sed -n '2,12p' "$0"; exit 0 ;;
    *)           FILTER="$1"; shift ;;
  esac
done

if [[ -z "$DEVICE" ]]; then
  DEVICE="$(adb devices | awk '$2 == "device" { print $1; exit }')"
fi
if [[ -z "$DEVICE" ]]; then
  echo "找不到处于 device 状态的设备。先运行 'make check' 排查（USB 需为 MTP 模式）。" >&2
  exit 1
fi

mapfile -t FILES < <(ls integration_test/*_test.dart 2>/dev/null || true)
if [[ -n "$FILTER" ]]; then
  mapfile -t FILES < <(printf '%s\n' "${FILES[@]}" | grep -- "$FILTER" || true)
fi
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "没有匹配的场景文件（filter='${FILTER}'）。" >&2
  exit 1
fi

echo "设备: $DEVICE"
echo "场景: ${#FILES[@]} 个"
printf '  - %s\n' "${FILES[@]}"

FAILED=()
for file in "${FILES[@]}"; do
  echo
  echo "── 跑 $file ──────────────────────────────────────────"
  if flutter --no-version-check --suppress-analytics test "$file" -d "$DEVICE"; then
    echo "✓ PASS $file"
  else
    echo "✗ FAIL $file"
    FAILED+=("$file")
  fi
done

echo
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "全部通过（${#FILES[@]} 个场景）。"
else
  echo "失败 ${#FAILED[@]}/${#FILES[@]}："
  printf '  - %s\n' "${FAILED[@]}"
  exit 1
fi
