#!/usr/bin/env bash
# ─── open-ledger-app: git pull → Rust SDK(iOS) → Flutter iOS 构建 → 设备预检 → 安装 ──
# iOS 侧流水线，与 Android 的 build_and_install.sh 平行。
# 单一可信来源（single source of truth）；根目录 Makefile 仅做入口转发，不重复内联流水线。
# 本脚本不含任何机器/设备特定标识：目标设备 UDID 自动探测（或用 --device 指定），
# 签名团队取自 Xcode 工程配置，Flutter / CocoaPods 一律从 PATH 解析。
# 用法: ./scripts/build_and_install_ios.sh [选项]     （--help 查看全部选项）
# ────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ─── 路径解析（稳健，不假设 .git 在 apps/mobile-flutter 内）────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

REPO_ROOT="$(git -C "$FLUTTER_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  # 回退：向上逐级查找 .git 目录
  local_dir="$FLUTTER_DIR"
  while [[ "$local_dir" != "/" ]]; do
    if [[ -d "$local_dir/.git" ]]; then
      REPO_ROOT="$local_dir"
      break
    fi
    local_dir="$(dirname "$local_dir")"
  done
fi
REPO_ROOT="${REPO_ROOT:-$FLUTTER_DIR}"

cd "$FLUTTER_DIR"

# ─── 颜色输出 ───────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()      { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()        { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()      { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail_echo() { echo -e "${RED}[FAIL]${NC}  $*"; }
fail()      { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# Flutter 调用统一加 --no-version-check --suppress-analytics：
# 前者避免 flutter 因自身 SDK 的 git fetch --tags 长时间挂起。
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

flutter_cmd() {
  "$FLUTTER_BIN" --no-version-check --suppress-analytics "$@"
}

# 设备预检时收集 flutter devices 的 stderr，供失败诊断；进程退出时清理临时文件。
DEVICES_STDERR_FILE=""
cleanup_devices_stderr() { rm -f "${DEVICES_STDERR_FILE:-}"; }
trap cleanup_devices_stderr EXIT

# ─── 默认值 ─────────────────────────────────────────────────────────────────
BRANCH=""
NO_PULL=false
SKIP_RUST=false
DEVICE=""
MODE_EXPLICIT=""   # release | debug | ""（未显式指定时按运行模式取默认）
RUN_ATTACHED=false
BUILD_ONLY=false
CHECK_ONLY=false

usage() {
  cat <<'EOF'
用法: build_and_install_ios.sh [选项]

选项:
  --branch <name>   要拉取的分支（默认：当前分支，detached 时回退 main）
  --no-pull         跳过 git pull 步骤
  --skip-rust       跳过 Rust 交叉编译（要求 libopen_ledger_crypto.a 已存在）
  --device <udid>   目标 iPhone UDID（默认自动选择唯一连接的 iOS 真机）
  --release         构建 release（默认）
  --debug           构建 debug（iOS 14+ 下装完不能从桌面图标启动，仅配合 --run 调试用）
  --run             安装并附加调试会话（flutter run，支持热重载；未指定模式时按 debug 构建）
  --build-only      仅拉取 + 构建，不安装、不执行设备预检
  --check-only      仅执行设备/工具链预检并退出（0=通过，非 0=失败）
  --help            显示本帮助

默认 release：iOS 14+ 只允许由 Flutter 工具链 / Xcode 拉起 debug 版 Flutter App，
debug 包装到真机后从桌面点不开，故默认产出可直接启动的 release 包。

安装: 构建后用 ios-deploy 原地覆盖安装（不先卸载旧 App），以保留 iPhone 上的开发者信任设置。

环境变量:
  FLUTTER_BIN               flutter 可执行文件（默认从 PATH 解析 "flutter"）
  FLUTTER_STORAGE_BASE_URL  可选的 engine 产物镜像（网络受限时设置）

签名: DEVELOPMENT_TEAM 由 ios/Runner.xcodeproj 工程配置决定，本脚本不写入任何团队 ID。
EOF
}

# ─── 参数解析（顺序无关）────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)      BRANCH="$2"; shift 2 ;;
    --no-pull)     NO_PULL=true; shift ;;
    --skip-rust)   SKIP_RUST=true; shift ;;
    --device)      DEVICE="$2"; shift 2 ;;
    --release)     MODE_EXPLICIT="release"; shift ;;
    --debug)       MODE_EXPLICIT="debug"; shift ;;
    --run)         RUN_ATTACHED=true; shift ;;
    --build-only)  BUILD_ONLY=true; shift ;;
    --check-only)  CHECK_ONLY=true; shift ;;
    --help)        usage; exit 0 ;;
    *)             fail_echo "未知参数: $1"; usage >&2; exit 1 ;;
  esac
done

# ─── 默认分支：当前分支，detached 时回退 main ───────────────────────────────
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git -C "$REPO_ROOT" symbolic-ref --short HEAD 2>/dev/null || true)"
  BRANCH="${BRANCH:-main}"
fi

# ─── 判定运行模式（互斥）────────────────────────────────────────────────────
MODE_FLAGS=0
[[ "$BUILD_ONLY" == true ]] && MODE_FLAGS=$((MODE_FLAGS+1))
[[ "$CHECK_ONLY" == true ]] && MODE_FLAGS=$((MODE_FLAGS+1))
[[ "$RUN_ATTACHED" == true ]] && MODE_FLAGS=$((MODE_FLAGS+1))
if [[ "$MODE_FLAGS" -gt 1 ]]; then
  fail "互斥的模式标志只能同时使用一个（--run / --build-only / --check-only）。"
fi

MODE="full"
if [[ "$BUILD_ONLY" == true ]]; then MODE="build-only"; fi
if [[ "$CHECK_ONLY" == true ]]; then MODE="check-only"; fi
if [[ "$RUN_ATTACHED" == true ]]; then MODE="run"; fi

# ─── 构建模式（debug / release）─────────────────────────────────────────────
# 默认 release：iOS 14+ 禁止独立启动 debug 版 Flutter App，debug 包装到真机后
# 从桌面点不开（只显示 Flutter 的说明文案），故默认产出可直接启动的包。
# 例外：`--run` 的热重载只在 debug 下可用，未显式指定模式时按 debug 构建。
if [[ -n "$MODE_EXPLICIT" ]]; then
  BUILD_MODE="$MODE_EXPLICIT"
elif [[ "$MODE" == "run" ]]; then
  BUILD_MODE="debug"
else
  BUILD_MODE="release"
fi

# ─── 派生步骤开关 ───────────────────────────────────────────────────────────
DO_PULL=false; DO_RUST=false; DO_PUB=false; DO_POD=false
DO_BUILD=false; DO_INSTALL=false; DO_RUN=false; DO_PREFLIGHT=false
case "$MODE" in
  full)       DO_PULL=true; DO_RUST=true; DO_PUB=true; DO_POD=true; DO_INSTALL=true; DO_PREFLIGHT=true ;;
  run)        DO_PULL=true; DO_RUST=true; DO_PUB=true; DO_POD=true; DO_RUN=true; DO_PREFLIGHT=true ;;
  build-only) DO_PULL=true; DO_RUST=true; DO_PUB=true; DO_POD=true; DO_BUILD=true ;;
  check-only) DO_PREFLIGHT=true ;;
esac

if [[ "$NO_PULL" == true ]]; then DO_PULL=false; fi
if [[ "$SKIP_RUST" == true ]]; then
  if [[ "$MODE" == full || "$MODE" == run || "$MODE" == build-only ]]; then
    DO_RUST=false
  fi
fi

# ─── 前置工具检查（按当前模式需要什么查什么）────────────────────────────────
check_prereqs() {
  command -v "$FLUTTER_BIN" >/dev/null 2>&1 \
    || fail "flutter 未安装或在 PATH 中找不到（可用 FLUTTER_BIN 指定可执行文件路径）"

  if [[ "$DO_BUILD" == true || "$DO_INSTALL" == true || "$DO_RUN" == true ]]; then
    command -v xcodebuild >/dev/null 2>&1 \
      || fail "xcodebuild 未找到。请安装 Xcode，并执行: xcode-select --install"
    command -v pod >/dev/null 2>&1 \
      || fail "CocoaPods (pod) 未找到。若用 gem 安装到用户目录，请把 \"\$(gem env gemdir)/bin\" 加入 PATH。"
    command -v python3 >/dev/null 2>&1 \
      || fail "python3 未找到（用于解析 flutter devices 输出）"
  fi

  if [[ "$DO_PREFLIGHT" == true ]]; then
    command -v python3 >/dev/null 2>&1 \
      || fail "python3 未找到（用于解析 flutter devices 输出）"
  fi

  if [[ "$DO_INSTALL" == true ]]; then
    command -v ios-deploy >/dev/null 2>&1 \
      || fail "ios-deploy 未找到（iOS 覆盖安装需要它）。安装: brew install ios-deploy"
  fi

  if [[ "$DO_RUST" == true ]]; then
    command -v cargo >/dev/null 2>&1 || fail "cargo 未安装"
    local sysroot
    sysroot="$(rustc --print sysroot 2>/dev/null || true)"
    [[ -n "$sysroot" && -d "$sysroot/lib/rustlib/aarch64-apple-ios" ]] \
      || fail "Rust target 'aarch64-apple-ios' 未安装。运行: rustup target add aarch64-apple-ios"
  fi
  ok "前置工具检查通过"
}

# ─── git pull ────────────────────────────────────────────────────────────────
do_pull() {
  if [[ "$NO_PULL" == true ]]; then
    warn "跳过 git pull (--no-pull)"
    return 0
  fi
  info "拉取最新代码 (branch: $BRANCH)..."
  if git -C "$REPO_ROOT" pull --ff-only origin "$BRANCH"; then
    ok "代码已更新"
  else
    warn "git pull 失败（离线 / 无远程 / 分支分叉），继续使用当前工作区代码构建。"
  fi
}

# ─── Rust 交叉编译（aarch64-apple-ios 静态库）────────────────────────────────
do_rust() {
  info "编译 Rust SDK (aarch64-apple-ios)..."
  cargo build --locked --manifest-path "$REPO_ROOT/crates/Cargo.toml" \
    --target aarch64-apple-ios --release \
    || fail "Rust 编译失败"

  local a_src="$REPO_ROOT/crates/target/aarch64-apple-ios/release/libopen_ledger_crypto.a"
  local a_dst="$FLUTTER_DIR/ios/libopen_ledger_crypto.a"
  [[ -f "$a_src" ]] || fail "未找到静态库: $a_src"
  cp "$a_src" "$a_dst"
  ok "Rust SDK 编译完成，libopen_ledger_crypto.a 已复制到 ios/"
}

# ─── Flutter 依赖与 CocoaPods ───────────────────────────────────────────────
do_pub() {
  info "获取 Flutter 依赖 (flutter pub get)..."
  flutter_cmd pub get || fail "flutter pub get 失败"
  ok "Flutter 依赖就绪"
}

do_pod() {
  info "安装 CocoaPods 依赖 (pod install)..."
  [[ -f "$FLUTTER_DIR/ios/libopen_ledger_crypto.a" ]] \
    || fail "ios/libopen_ledger_crypto.a 缺失（iOS 脚手架需要它）。请勿使用 --skip-rust，或先构建 Rust SDK。"

  # CocoaPods 对 locale 编码敏感：当前已是 UTF-8 就沿用；否则才回退到 en_US.UTF-8。
  local -a pod_env=(COCOAPODS_DISABLE_STATS=true)
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*) ;; # 已是 UTF-8，不动
    *)
      warn "当前 locale 非 UTF-8 (${LC_ALL:-${LC_CTYPE:-${LANG:-未设置}}}), pod install 临时使用 en_US.UTF-8。"
      pod_env+=(LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8)
      ;;
  esac

  ( cd "$FLUTTER_DIR/ios" && env "${pod_env[@]}" pod install ) || fail "pod install 失败"
  ok "CocoaPods 依赖就绪"
}

# ─── 构建 ────────────────────────────────────────────────────────────────────
do_build() {
  info "构建 iOS 应用 ($BUILD_MODE)..."
  flutter_cmd build ios "--$BUILD_MODE" || fail "Flutter iOS 构建失败"
  ok "构建成功: $FLUTTER_DIR/build/ios/iphoneos/Runner.app"
}

# ─── 安装（构建 + 覆盖安装，不附加调试）──────────────────────────────────────
# 刻意不用 `flutter install`：它会先卸载旧 App（flutter_tools 的 installApp 默认
# uninstall: true），而 iPhone 上「信任开发者」条目源自 App 内嵌的描述文件，
# 一卸载就消失，导致下次重装又弹「未受信任的开发者」。
#
# 用 ios-deploy 走 installation_proxy 原地覆盖安装。不用 `xcrun devicectl`：devicectl
# 依赖 CoreDevice，只支持 iOS 17+，在 iOS 16 设备上会报 CoreDeviceError 1000 (device not found)。
do_install() {
  do_build
  local app="$FLUTTER_DIR/build/ios/iphoneos/Runner.app"
  [[ -d "$app" ]] || fail "未找到构建产物: $app"

  info "覆盖安装到设备 ($SELECTED_DEV)..."
  ios-deploy --id "$SELECTED_DEV" --bundle "$app" --no-wifi \
    || fail "安装到设备 $SELECTED_DEV 失败"
  ok "已安装到 ${SELECTED_DEV}（原地覆盖，未卸载旧版本，信任设置保留）"
}

# ─── 附加调试运行（构建 + 安装 + 启动 + 热重载）──────────────────────────────
do_run() {
  info "构建、安装并附加调试会话 ($SELECTED_DEV)..."
  flutter_cmd run -d "$SELECTED_DEV" "--$BUILD_MODE"
}

# ─── iOS 设备枚举（仅真机；输出 id<TAB>name<TAB>sdk）────────────────────────
# flutter 的 stderr 不丢弃，改写到 ${DEVICES_STDERR_FILE}，供预检失败时诊断。
list_ios_devices() {
  flutter_cmd devices --machine 2>"${DEVICES_STDERR_FILE:-/dev/null}" | python3 -c '
import json, sys
try:
    devices = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for d in devices:
    if d.get("targetPlatform") == "ios" and not d.get("emulator"):
        print("%s\t%s\t%s" % (d.get("id", ""), d.get("name", ""), d.get("sdk", "")))
'
}

# ─── 设备预检 ────────────────────────────────────────────────────────────────
# 全局结果：SELECTED_DEV、SELECTED_NAME
# flutter devices 自身的报错回显出来，避免一律归因于「没插线」而误判。
report_devices_stderr() {
  [[ -n "$DEVICES_STDERR_FILE" && -s "$DEVICES_STDERR_FILE" ]] || return 0
  warn "flutter devices stderr:"
  local line
  while IFS= read -r line; do warn "  $line"; done < "$DEVICES_STDERR_FILE"
}

preflight_device() {
  info "iOS 设备预检中..."

  rm -f "$DEVICES_STDERR_FILE"
  DEVICES_STDERR_FILE="$(mktemp -t openledger-devices-err)"

  local raw
  raw="$(list_ios_devices || true)"

  local ids=() names=() id name sdk
  while IFS=$'\t' read -r id name sdk; do
    [[ -z "$id" ]] && continue
    ids+=("$id"); names+=("$name")
  done <<< "$raw"

  if [[ -n "$DEVICE" ]]; then
    local found=0
    for id in "${ids[@]:-}"; do
      [[ "$id" == "$DEVICE" ]] && found=1 && break
    done
    if [[ "$found" -eq 1 ]]; then
      SELECTED_DEV="$DEVICE"
      SELECTED_NAME=""
      for i in "${!ids[@]}"; do
        [[ "${ids[$i]}" == "$DEVICE" ]] && SELECTED_NAME="${names[$i]}"
      done
    else
      report_devices_stderr
      fail "指定的设备 $DEVICE 未连接。请确认 iPhone 已通过 USB 连接并已信任本机。"
    fi
  elif [[ "${#ids[@]}" -eq 1 ]]; then
    SELECTED_DEV="${ids[0]}"
    SELECTED_NAME="${names[0]}"
  elif [[ "${#ids[@]}" -gt 1 ]]; then
    local list=""
    local i
    for i in "${!ids[@]}"; do
      list+="${ids[$i]}(${names[$i]}) "
    done
    fail "检测到多个 iOS 真机：${list}。请用 --device <udid> 指定目标设备。"
  else
    fail_echo "未检测到任何 iOS 真机。请依次排查："
    fail_echo "  1. iPhone 用数据线连接本机（仅充电线不具备数据能力）"
    fail_echo "  2. iPhone 上点击「信任此电脑」，并保持解锁"
    fail_echo "  3. 若首次连接：设置 → 隐私与安全性 → 开发者模式，开启后重启手机"
    report_devices_stderr
    # 必须在此退出：否则会继续往下读取未赋值的 SELECTED_DEV（set -u 下报 unbound variable）
    fail "设备预检未通过。"
  fi

  ok "已选择设备: ${SELECTED_NAME:-$SELECTED_DEV} ($SELECTED_DEV)"
  DEVICE="$SELECTED_DEV"
}

# ─── 打印横幅与汇总 ─────────────────────────────────────────────────────────
print_banner() {
  case "$MODE" in
    full)       info "模式：完整部署（pull → rust → pub get → pod install → 构建 + 安装）" ;;
    run)        info "模式：附加调试（pull → rust → pub get → pod install → flutter run）" ;;
    build-only) info "模式：仅构建（pull → rust → pub get → pod install → build）" ;;
    check-only) info "模式：仅设备/工具链预检" ;;
  esac
  info "构建模式: $BUILD_MODE"
}

print_summary() {
  echo ""
  ok "✅ 全部完成！"
  case "$MODE" in
    full|run)   info "设备: $SELECTED_DEV" ;;
    build-only) info "产物: $FLUTTER_DIR/build/ios/iphoneos/Runner.app" ;;
    check-only) info "设备: ${SELECTED_NAME:-$SELECTED_DEV} ($SELECTED_DEV)" ;;
  esac
  info "模式: $MODE ($BUILD_MODE)"
}

# ─── 主流程 ──────────────────────────────────────────────────────────────────
print_banner
check_prereqs

if [[ "$DO_PULL" == true ]]; then do_pull; fi

# full / run 模式：构建前先预检（在耗时数分钟的构建前快速失败）
if [[ "$MODE" == full || "$MODE" == run ]]; then preflight_device; fi

if [[ "$DO_RUST" == true ]]; then do_rust; fi
if [[ "$DO_PUB" == true ]]; then do_pub; fi
if [[ "$DO_POD" == true ]]; then do_pod; fi
if [[ "$DO_BUILD" == true ]]; then do_build; fi

case "$MODE" in
  full)
    preflight_device   # 安装前二次预检
    do_install
    ;;
  run)
    do_run
    ;;
  check-only)
    preflight_device
    ;;
esac

print_summary
