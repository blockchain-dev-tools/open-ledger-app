#!/usr/bin/env bash
# ─── open-ledger-app: git pull → Rust SDK → Flutter APK → 设备预检 → 安装 ──
# 单一可信来源（single source of truth）构建/安装流水线。
# 根目录 Makefile 仅做入口转发，不重复内联流水线。
# 用法: ./scripts/build_and_install.sh [选项]     （--help 查看全部选项）
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

# 安全读取 sysfs 文件（不存在/不可读时返回空，绝不触发 set -e）
read_sysfs() { cat "$1" 2>/dev/null || true; }

# ─── 默认值 ─────────────────────────────────────────────────────────────────
BRANCH=""
NO_PULL=false
SKIP_RUST=false
DEVICE=""
RELEASE=false
BUILD_ONLY=false
INSTALL_ONLY=false
CHECK_ONLY=false
LAUNCH=false

usage() {
  cat <<'EOF'
用法: build_and_install.sh [选项]

选项:
  --branch <name>   要拉取的分支（默认：当前分支，detached 时回退 main）
  --no-pull         跳过 git pull 步骤
  --skip-rust       跳过 Rust 交叉编译（full/build 模式的修饰符）
  --device <id>     目标设备 adb serial（默认自动选择唯一的 device）
  --release         构建 release APK（默认 debug）
  --build-only      仅拉取 + 构建，不安装、不执行设备预检
  --install-only    仅安装已存在的 APK（执行设备预检），不构建
  --check-only      仅执行设备预检并退出（0=通过，非 0=失败）
  --launch          安装后 force-stop 并冷启动应用
  --help            显示本帮助
EOF
}

# ─── 参数解析（顺序无关）────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)      BRANCH="$2"; shift 2 ;;
    --no-pull)     NO_PULL=true; shift ;;
    --skip-rust)   SKIP_RUST=true; shift ;;
    --device)      DEVICE="$2"; shift 2 ;;
    --release)     RELEASE=true; shift ;;
    --build-only)  BUILD_ONLY=true; shift ;;
    --install-only) INSTALL_ONLY=true; shift ;;
    --check-only)  CHECK_ONLY=true; shift ;;
    --launch)      LAUNCH=true; shift ;;
    --help)        usage; exit 0 ;;
    *)             fail_echo "未知参数: $1"; usage >&2; exit 1 ;;
  esac
done

# ─── 默认分支：当前分支，detached 时回退 main ───────────────────────────────
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git -C "$REPO_ROOT" symbolic-ref --short HEAD 2>/dev/null || true)"
  BRANCH="${BRANCH:-main}"
fi

# ─── 构建模式（debug / release）与 APK 路径 ────────────────────────────────
BUILD_MODE="debug"
APK_PATH="$FLUTTER_DIR/build/app/outputs/flutter-apk/app-debug.apk"
if [[ "$RELEASE" == true ]]; then
  BUILD_MODE="release"
  APK_PATH="$FLUTTER_DIR/build/app/outputs/flutter-apk/app-release.apk"
fi

# ─── 判定运行模式（互斥）────────────────────────────────────────────────────
MODE_FLAGS=0
[[ "$BUILD_ONLY" == true ]] && MODE_FLAGS=$((MODE_FLAGS+1))
[[ "$INSTALL_ONLY" == true ]] && MODE_FLAGS=$((MODE_FLAGS+1))
[[ "$CHECK_ONLY" == true ]] && MODE_FLAGS=$((MODE_FLAGS+1))

if [[ "$MODE_FLAGS" -gt 1 ]]; then
  fail "互斥的模式标志只能同时使用一个（--build-only / --install-only / --check-only）。"
fi

MODE="full"
if [[ "$BUILD_ONLY" == true ]]; then MODE="build-only"; fi
if [[ "$INSTALL_ONLY" == true ]]; then MODE="install-only"; fi
if [[ "$CHECK_ONLY" == true ]]; then MODE="check-only"; fi

# ─── 派生步骤开关 ───────────────────────────────────────────────────────────
DO_PULL=false; DO_RUST=false; DO_APK=false; DO_INSTALL=false; DO_PREFLIGHT=false
case "$MODE" in
  full)         DO_PULL=true; DO_RUST=true; DO_APK=true; DO_INSTALL=true; DO_PREFLIGHT=true ;;
  build-only)   DO_PULL=true; DO_RUST=true; DO_APK=true ;;
  install-only) DO_INSTALL=true; DO_PREFLIGHT=true ;;
  check-only)   DO_PREFLIGHT=true ;;
esac

if [[ "$NO_PULL" == true ]]; then DO_PULL=false; fi
if [[ "$SKIP_RUST" == true ]]; then
  if [[ "$MODE" == full || "$MODE" == build-only ]]; then
    DO_RUST=false
  fi
fi

# ─── 前置工具检查（按当前模式需要什么查什么）────────────────────────────────
check_prereqs() {
  case "$MODE" in
    full|build-only)
      command -v git >/dev/null 2>&1 || fail "git 未安装"
      command -v flutter >/dev/null 2>&1 || fail "flutter 未安装或在 PATH 中找不到"
      command -v cargo >/dev/null 2>&1 || fail "cargo 未安装"
      ;;
  esac
  if [[ "$DO_RUST" == true ]]; then
    rustup target list --installed 2>/dev/null \
      | grep -q "aarch64-linux-android" \
      || fail "Rust target 'aarch64-linux-android' 未安装。运行: rustup target add aarch64-linux-android"
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

# ─── Rust 交叉编译 ──────────────────────────────────────────────────────────
do_rust() {
  info "编译 Rust SDK (aarch64-linux-android)..."
  # 注入 NDK linker/ar 环境变量（自动发现 NDK）
  source "$FLUTTER_DIR/scripts/android-env.sh"
  info "NDK: ${OPEN_LEDGER_NDK}"

  cargo build --manifest-path "$REPO_ROOT/crates/Cargo.toml" \
    --target aarch64-linux-android --release \
    || fail "Rust 编译失败，请检查 NDK 配置"

  local so_src="$REPO_ROOT/crates/target/aarch64-linux-android/release/libopen_ledger_crypto.so"
  local so_dst="$FLUTTER_DIR/android/app/src/main/jniLibs/arm64-v8a"
  mkdir -p "$so_dst"
  cp "$so_src" "$so_dst/"
  ok "Rust SDK 编译完成，.so 已复制到 jniLibs/arm64-v8a/"
}

# ─── Flutter APK 构建 ───────────────────────────────────────────────────────
do_apk() {
  info "构建 Flutter APK ($BUILD_MODE)..."
  # --no-version-check 为必需：否则 flutter 会因自身 SDK 的 gitee git fetch --tags 永久挂起
  flutter --no-version-check --suppress-analytics pub get \
    || fail "flutter pub get 失败"
  if [[ "$RELEASE" == true ]]; then
    flutter --no-version-check --suppress-analytics build apk --release \
      || fail "Flutter release 构建失败"
  else
    flutter --no-version-check --suppress-analytics build apk --debug \
      || fail "Flutter debug 构建失败"
  fi
  ok "APK 构建成功: $APK_PATH"
}

# ─── 安装 ────────────────────────────────────────────────────────────────────
do_install() {
  [[ -f "$APK_PATH" ]] || fail "APK 不存在: $APK_PATH（请先构建，或确认 --release 标志一致）"
  info "安装 APK 到设备 ($SELECTED_DEV)..."
  adb -s "$SELECTED_DEV" install -r "$APK_PATH" \
    || fail "安装到设备 $SELECTED_DEV 失败"
  # install -r 不会重启正在运行的 app，必须 force-stop
  adb -s "$SELECTED_DEV" shell am force-stop app.openledger.mobile
  if [[ "$LAUNCH" == true ]]; then
    if adb -s "$SELECTED_DEV" shell monkey -p app.openledger.mobile \
      -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; then
      ok "已冷启动应用 app.openledger.mobile"
    else
      warn "冷启动失败（应用已安装，可手动启动）"
    fi
  fi
  ok "已安装到 $SELECTED_DEV"
}

# ─── 设备预检 ────────────────────────────────────────────────────────────────
# 全局结果：SELECTED_DEV（选中的设备 serial）、OK_LIST、PROBLEM_LIST

print_udev_fix() {
  local vid="${1:-22d9}"
  fail_echo "永久方案：添加 udev 规则（以 root 执行，vid=${vid}，示例设备为 realme）："
  fail_echo "  echo 'SUBSYSTEM==\"usb\", ATTR{idVendor}==\"${vid}\", MODE=\"0666\", GROUP=\"plugdev\"' | sudo tee /etc/udev/rules.d/51-android.rules"
  fail_echo "  sudo udevadm control --reload-rules && sudo udevadm trigger"
  fail_echo "  adb kill-server && adb start-server && adb devices"
}

# no permissions 的针对性诊断（按 serial 在 sysfs 定位，绝不硬编码 VID/PID）
diagnose_no_permissions() {
  local serial="$1"
  local devnode="" d s
  for d in /sys/bus/usb/devices/*/; do
    s="$(read_sysfs "${d}serial")"
    if [[ -n "$s" && "$s" == "$serial" ]]; then
      devnode="$d"
      break
    fi
  done

  local has_mtp=0 has_adb=0 vid=""
  if [[ -n "$devnode" ]]; then
    vid="$(read_sysfs "${devnode}idVendor")"
    local iface cls sub proto
    for iface in "$devnode"*:*; do
      [[ -e "$iface/bInterfaceClass" ]] || continue
      cls="$(read_sysfs "$iface/bInterfaceClass")"
      sub="$(read_sysfs "$iface/bInterfaceSubClass")"
      proto="$(read_sysfs "$iface/bInterfaceProtocol")"
      if [[ "$cls" == "06" && "$sub" == "01" && "$proto" == "01" ]]; then has_mtp=1; fi
      if [[ "$cls" == "ff" && "$sub" == "42" && "$proto" == "01" ]]; then has_adb=1; fi
    done
  fi

  if [[ -z "$devnode" ]]; then
    fail_echo "设备 $serial 无权限：adb 无法访问该设备。请检查 USB 调试授权，并按下方 udev 规则修复。"
  elif [[ "$has_adb" -eq 1 && "$has_mtp" -eq 0 ]]; then
    fail_echo "设备 $serial 已被识别，但当前 USB 模式不含 MTP/PTP。本机 adb 授权依赖 systemd 的 70-uaccess.rules（只对 060101 MTP 接口生效），所以被拒绝。"
    fail_echo "  修复一（临时）：在手机通知栏把「USB 用途」切到「传输文件 / MTP」。"
    fail_echo "  修复二（永久）：添加下方 udev 规则。"
  elif [[ "$has_adb" -eq 0 ]]; then
    fail_echo "设备 $serial 未检测到 ADB 接口：手机上的『USB 调试』很可能未开启。"
    fail_echo "  请在开发者选项中开启「USB 调试」，并确认「USB 用途」不是「仅充电」。"
  else
    fail_echo "设备 $serial 无权限：设备已正确配置（MTP + ADB），但 adb 仍被拒绝。请添加下方 udev 规则，或把用户加入 plugdev 组。"
  fi

  print_udev_fix "$vid"
}

emit_diagnosis() {
  local kind="$1" serial="$2" rawstate="$3"
  case "$kind" in
    no_permissions) diagnose_no_permissions "$serial" ;;
    unauthorized)
      fail_echo "设备 $serial 状态 unauthorized：请在手机上确认「允许 USB 调试」弹窗；若没有弹窗，请撤销 USB 调试授权后重新插拔数据线。" ;;
    offline)
      fail_echo "设备 $serial 状态 offline：连接异常。请重新插拔数据线，或执行 adb kill-server && adb start-server 后重试。" ;;
    unknown)
      fail_echo "设备 $serial 状态未知：$rawstate" ;;
  esac
}

emit_all_diagnoses() {
  local entry kind serial state
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    IFS='|' read -r kind serial state <<< "$entry" || continue
    emit_diagnosis "$kind" "$serial" "$state"
  done <<< "$PROBLEM_LIST"
}

emit_diagnosis_for_serial() {
  local target="$1" entry kind serial state found=0
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    IFS='|' read -r kind serial state <<< "$entry" || continue
    if [[ "$serial" == "$target" ]]; then
      emit_diagnosis "$kind" "$serial" "$state"
      found=1
    fi
  done <<< "$PROBLEM_LIST"
  if [[ "$found" -eq 0 ]]; then
    fail_echo "在 adb devices 输出中未找到序列号 $target 的设备。"
  fi
}

check_usb_mode() {
  local dev="$1" mode
  # 模拟器没有 USB 接口，sys.usb.config 恒为空，跳过（示例见 README: --device emulator-5554）
  if [[ "$dev" == emulator-* ]]; then
    info "设备 $dev 为模拟器，跳过 USB 模式校验"
    return 0
  fi
  mode="$(adb -s "$dev" shell getprop sys.usb.config 2>/dev/null || true)"
  mode="${mode//$'\r'/}"
  if [[ -z "$mode" ]]; then
    warn "无法读取设备 $dev 的 sys.usb.config，跳过 USB 模式校验。"
    return 0
  fi
  info "设备 $dev USB 模式: $mode"
  if [[ "$mode" != *adb* ]]; then
    fail "设备 $dev 的 USB 配置不含 adb：当前 sys.usb.config=$mode。请在手机上开启「USB 调试」（或切换 USB 用途）后重试。"
  fi
  if [[ "$mode" != *mtp* && "$mode" != *ptp* ]]; then
    warn "当前 adb 可用，但 USB 模式不含 mtp/ptp。本机权限依赖 MTP（70-uaccess.rules），建议保持「传输文件」模式，或添加 udev 规则。"
  fi
}

preflight_device() {
  info "设备预检中..."
  command -v adb >/dev/null 2>&1 \
    || fail "adb 未安装。请安装 Android SDK Platform-Tools 并把 adb 加入 PATH。例如：export PATH=\"\$PATH:\${ANDROID_HOME:-~/Android/Sdk}/platform-tools\""

  # 启动 adb server（静默）
  adb start-server >/dev/null 2>&1 || true

  local raw line serial state
  raw="$(adb devices 2>/dev/null || true)"

  OK_LIST=""
  PROBLEM_LIST=""
  local ok_count=0 first=1
  while IFS= read -r line; do
    if [[ "$first" -eq 1 ]]; then first=0; continue; fi
    line="${line//$'\r'/}"
    [[ -z "$line" ]] && continue
    read -r serial state <<< "$line" || continue
    [[ -z "$serial" ]] && continue
    case "$state" in
      device)          OK_LIST+="$serial"$'\n'; ok_count=$((ok_count+1)) ;;
      "no permissions"*) PROBLEM_LIST+="no_permissions|$serial|$state"$'\n' ;;
      unauthorized)    PROBLEM_LIST+="unauthorized|$serial|$state"$'\n' ;;
      offline)         PROBLEM_LIST+="offline|$serial|$state"$'\n' ;;
      *)               PROBLEM_LIST+="unknown|$serial|$state"$'\n' ;;
    esac
  done <<< "$raw"

  OK_LIST="${OK_LIST%$'\n'}"
  PROBLEM_LIST="${PROBLEM_LIST%$'\n'}"

  # 设备选择
  if [[ -n "$DEVICE" ]]; then
    if printf '%s\n' "$OK_LIST" | grep -qx "$DEVICE"; then
      SELECTED_DEV="$DEVICE"
    else
      emit_diagnosis_for_serial "$DEVICE"
      fail "指定设备 $DEVICE 不处于 device 状态。"
    fi
  elif [[ "$ok_count" -eq 1 ]]; then
    SELECTED_DEV="$OK_LIST"
  elif [[ "$ok_count" -gt 1 ]]; then
    local list
    list="$(printf '%s\n' "$OK_LIST" | paste -sd' ' - || true)"
    fail "检测到多个处于 device 状态的设备：$list 。请用 --device <serial> 指定目标设备。"
  else
    if [[ -z "$PROBLEM_LIST" ]]; then
      fail "未检测到任何 Android 设备。可能原因：数据线仅支持充电（请换一根数据线）、手机未开启 USB 调试、或当前 USB 模式未暴露 ADB。"
    fi
    emit_all_diagnoses
    fail "没有任何设备处于 device 状态（详见上方诊断）。"
  fi

  ok "已选择设备: $SELECTED_DEV"
  # 固定选择结果，后续（full 模式二次预检）复用同一设备
  DEVICE="$SELECTED_DEV"

  check_usb_mode "$SELECTED_DEV"
}

# ─── 打印横幅与汇总 ─────────────────────────────────────────────────────────
print_banner() {
  case "$MODE" in
    full)         info "模式：完整部署（pull → rust → apk → 预检 → 安装）" ;;
    build-only)   info "模式：仅构建（pull → rust → apk）" ;;
    install-only) info "模式：仅安装（预检 → 安装现有 APK）" ;;
    check-only)   info "模式：仅设备预检" ;;
  esac
}

print_summary() {
  echo ""
  ok "✅ 全部完成！"
  case "$MODE" in
    full|install-only) info "设备: $SELECTED_DEV"; info "APK: $APK_PATH" ;;
    build-only) info "APK: $APK_PATH" ;;
    check-only) info "设备: $SELECTED_DEV" ;;
  esac
  info "模式: $MODE ($BUILD_MODE)"
}

# ─── 主流程 ──────────────────────────────────────────────────────────────────
print_banner
check_prereqs

if [[ "$DO_PULL" == true ]]; then do_pull; fi

# full 模式：构建前先预检（在耗时数分钟的构建前快速失败）
if [[ "$MODE" == full ]]; then preflight_device; fi

if [[ "$DO_RUST" == true ]]; then do_rust; fi
if [[ "$DO_APK" == true ]]; then do_apk; fi

case "$MODE" in
  full|install-only)
    preflight_device   # full 模式安装前二次预检；install-only 唯一一次预检
    do_install
    ;;
  check-only)
    preflight_device
    ;;
esac

print_summary
