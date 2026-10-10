#!/usr/bin/env bash
# ─── open-ledger: Android NDK 环境注入（Rust 交叉编译用）─────────────────────
# 用法:  source scripts/android-env.sh   （在 build_and_install.sh 内部或手动）
# 作用:  自动发现 Android NDK，注入 CARGO_TARGET_*_LINKER / _AR 环境变量，
#        取代旧的 crates/.cargo/config.toml 里机器相关的硬编码路径。
# ────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# 可选覆盖：API level（默认 26，与历史构建保持一致）
API_LEVEL="${ANDROID_NDK_API_LEVEL:-26}"

# ─── 1. 发现 NDK 根目录 ──────────────────────────────────────────────────────
NDK=""

# 显式指定优先
if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "$ANDROID_NDK_HOME" ]; then
  NDK="$ANDROID_NDK_HOME"
elif [ -n "${ANDROID_NDK_ROOT:-}" ] && [ -d "$ANDROID_NDK_ROOT" ]; then
  NDK="$ANDROID_NDK_ROOT"
else
  # 从 SDK 目录下选版本号最大的 NDK
  SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [ -n "$SDK_ROOT" ] && [ -d "$SDK_ROOT/ndk" ]; then
    NDK="$(find "$SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n 1)"
  fi
fi

if [ -z "$NDK" ] || [ ! -d "$NDK/toolchains/llvm/prebuilt" ]; then
  echo "❌ 找不到 Android NDK。请设置 ANDROID_NDK_HOME 或 ANDROID_HOME。" >&2
  exit 1
fi

# ─── 2. 检测构建主机 tag ────────────────────────────────────────────────────
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  HOST=linux-x86_64 ;;
  Linux-aarch64) HOST=linux-aarch64 ;;
  Darwin-x86_64) HOST=darwin-x86_64 ;;
  Darwin-arm64)  HOST=darwin-arm64 ;;
  *) echo "❌ 不支持的构建主机: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

TOOL="$NDK/toolchains/llvm/prebuilt/$HOST/bin"

# ─── 3. 注入三套 ABI 的 linker / ar（供 cargo 交叉编译拾取）────────────────
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$TOOL/aarch64-linux-android${API_LEVEL}-clang"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_AR="$TOOL/llvm-ar"
export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$TOOL/armv7a-linux-androideabi${API_LEVEL}-clang"
export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_AR="$TOOL/llvm-ar"
export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$TOOL/x86_64-linux-android${API_LEVEL}-clang"
export CARGO_TARGET_X86_64_LINUX_ANDROID_AR="$TOOL/llvm-ar"

# 供调用方（build_and_install.sh）打印使用
export OPEN_LEDGER_NDK="$NDK"
export OPEN_LEDGER_NDK_API="$API_LEVEL"