# scripts/

构建、安装、调试等辅助脚本。

## 脚本列表

| 脚本 | 用途 |
|---|---|
| `build_and_install.sh` | Android 单一可信来源流水线：git pull → Rust SDK → Flutter APK → 设备预检 → 安装 |
| `build_and_install_ios.sh` | iOS 单一可信来源流水线：git pull → Rust SDK(iOS) → pub get → pod install → 设备预检 → 构建/安装 |
| `android-env.sh` | 自动发现 Android NDK 并注入 `CARGO_TARGET_*_LINKER`/`_AR`（Rust 交叉编译用），需 `source` |

## 前置条件

### Android

- Flutter SDK（`flutter` 命令可用）
- Android SDK + ADB（`adb` 命令可用）
- Rust 工具链 + Android target（`aarch64-linux-android`）
- Android NDK（脚本通过 `ANDROID_NDK_HOME` / `ANDROID_HOME` 自动发现，Rust 交叉编译用）
- Git 仓库已初始化（脚本用 `git rev-parse --show-toplevel` 定位仓库根，不假设 `.git` 在 apps/mobile-flutter 内）

### iOS（仅 macOS）

- Xcode（`xcodebuild` 可用）+ 命令行工具
- CocoaPods（`pod` 命令可用；若用 gem 安装到用户目录，把 `$(gem env gemdir)/bin` 加入 `PATH`）
- Flutter SDK（`flutter` 命令可用）
- Rust 工具链 + iOS target（`aarch64-apple-ios`）
- Python 3（解析 `flutter devices --json` 输出）
- 一台通过 USB 连接、已「信任此电脑」的 iPhone（首次需在手机上开启「开发者模式」）
- 签名：`DEVELOPMENT_TEAM` 取自 `ios/Runner.xcodeproj` 工程配置，脚本不写入任何团队 ID；本机需在 Xcode 中登录对应 Apple ID 并持有有效开发证书

## 使用方式

### Android

#### 完整流水线（默认）

```bash
# 默认：git pull 当前分支 + 编译 Rust + 构建 debug APK + 设备预检 + 安装
./scripts/build_and_install.sh

# 只改了 Dart 代码：跳过 Rust 编译
./scripts/build_and_install.sh --skip-rust

# 指定目标设备（serial）
./scripts/build_and_install.sh --device <device-id>

# release 模式
./scripts/build_and_install.sh --release

# 安装后冷启动应用
./scripts/build_and_install.sh --launch
```

#### 全部选项

| 选项 | 含义 |
|---|---|
| `--branch <name>` | 要拉取的分支（默认：当前分支，detached 时回退 `main`） |
| `--no-pull` | 跳过 git pull |
| `--skip-rust` | 跳过 Rust 交叉编译（full/build 模式的修饰符） |
| `--device <id>` | 目标设备 adb serial（默认自动选择唯一的 device） |
| `--release` | 构建 release APK（默认 debug） |
| `--build-only` | 仅拉取 + 构建，不安装、不执行设备预检 |
| `--install-only` | 仅安装已存在的 APK（执行设备预检），不构建 |
| `--check-only` | 仅执行设备预检并退出（0=通过，非 0=失败） |
| `--launch` | 安装后 force-stop 并冷启动应用 |
| `--help` | 显示帮助 |

#### 设备预检（核心能力）

预检会在安装前（及完整模式构建前）检查并诊断：

- `adb` 是否可用
- 设备连接状态（`device` / `no permissions` / `unauthorized` / `offline` / 未知）
- 设备选择（唯一 device 自动选中；多个 device 需 `--device` 指定）
- `no permissions` 时按 serial 在 sysfs 定位 USB 接口，给出针对性的 MTP 模式 / udev 规则修复建议
- USB 配置（`sys.usb.config`）是否包含 `adb`

### iOS

```bash
# 默认：git pull + 编译 Rust(iOS) + pub get + pod install + 构建并安装到唯一的 iPhone
./scripts/build_and_install_ios.sh

# 附加调试会话（构建 + 安装 + 启动 + 热重载）
./scripts/build_and_install_ios.sh --run

# 只改了 Dart 代码：跳过 Rust 编译（要求 ios/libopen_ledger_crypto.a 已存在）
./scripts/build_and_install_ios.sh --skip-rust

# 指定目标 iPhone UDID（多台真机并存时需要）
./scripts/build_and_install_ios.sh --device <udid>

# 只构建 Runner.app，不安装
./scripts/build_and_install_ios.sh --build-only
```

| 选项 | 含义 |
|---|---|
| `--branch <name>` | 要拉取的分支（默认：当前分支，detached 时回退 `main`） |
| `--no-pull` | 跳过 git pull |
| `--skip-rust` | 跳过 Rust 交叉编译（要求静态库已存在） |
| `--device <udid>` | 目标 iPhone UDID（默认自动选择唯一连接的 iOS 真机） |
| `--release` | 构建 release（默认 debug） |
| `--run` | 安装后附加调试会话（`flutter run`，支持热重载） |
| `--build-only` | 仅拉取 + 构建，不安装、不执行设备预检 |
| `--check-only` | 仅执行设备/工具链预检并退出（0=通过，非 0=失败） |
| `--help` | 显示帮助 |

设备预检会校验：`flutter` / `xcodebuild` / `pod` / `python3` 可用性、Rust `aarch64-apple-ios` target、以及真机连接情况（自动选中唯一 iOS 真机；多台需 `--device`）。签名团队不在此脚本内配置，取自 `ios/Runner.xcodeproj` 的 `DEVELOPMENT_TEAM`。

## Makefile 入口（仓库根目录）

所有入口只做转发（完整列表见 `make help`）：

```bash
# Android
make                       # = make deploy：完整部署（默认）
make build                 # 只构建（Rust + APK），不安装
make install               # 只安装已构建的 APK（含设备预检）
make check                 # 只做设备预检

# iOS
make ios                   # 构建并安装到 iPhone（默认 debug）
make ios-run               # 构建 + 安装 + 附加调试会话（热重载）
make ios-build             # 只构建 Runner.app，不安装
make ios-check             # 设备/工具链预检（不构建）

# 透传额外参数（跳过 Rust / 指定设备 / release）
make deploy ARGS="--skip-rust"
make deploy ARGS="--device <device-id> --release"
make ios ARGS="--device <udid>"
```
