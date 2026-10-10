<picture>
  <source media="(prefers-color-scheme: dark)" srcset="branding/openledger-community-dark.svg">
  <img alt="OpenLedger" src="branding/openledger-community-light.svg" width="450">
</picture>

# Open Ledger App

[English](README.md) · [构建说明](BUILDING.md) · [安全说明](SECURITY.md)

Open Ledger App 将 Android 手机作为签名设备，实现 Ledger Nano X 风格的 BLE GATT 和 APDU 接口。Flutter 提供账户与确认界面，Rust SDK 在设备端派生密钥、解析签名内容并执行密码学操作。

本仓库仅包含设备 App 与 Rust SDK。网站和 debugger 独立维护。本次公开迁移保留经过筛选的源码快照，重新建立公开 Git 历史，不包含原仓库的开发过程记录。

## 当前状态

Android 是当前开发目标。iOS 有实验性集成工程，但模拟器和端到端兼容性尚未确认。ETH、Solana、Bitcoin、Tron、Sui 有协议与密码学实现；实际主机钱包和具体操作的兼容性需要逐项验证，参见[测试矩阵](docs/testing/ble-wallets.md)。

代码未经独立安全审计。当前仍使用 SharedPreferences 存储；提取存储文件后可离线猜测六位 PIN；后台自动锁逻辑尚未接入 App 生命周期；旧备份路由仍允许复制助记词；Android release 配置仍使用 debug 签名。使用钱包数据前请先阅读 [SECURITY.md](SECURITY.md)。开发验证应使用公开测试向量和可丢弃的测试钱包。

## 目录

```text
apps/mobile-flutter/    Flutter UI、Android/iOS 工程、测试与工具
crates/                Rust 密码学、链业务与 C FFI 工作区
spec/apdu/             APDU 指令覆盖表与一致性测试向量
docs/                  产品契约、协议和测试说明
```

保留目录结构是为了维持脚本与测试数据的相对路径。设备运行时密码学来自 Rust；根目录 Node 依赖仅供主机侧 E2E 独立验签。

## 构建与验证

需要兼容 Dart `^3.12.0` 的 Flutter SDK、Rust stable、Java 17、Android SDK/NDK。完整步骤、FFI 打包及发布限制见 [BUILDING.md](BUILDING.md)。

仓库根目录：

```bash
cargo test --locked --manifest-path crates/Cargo.toml
make build ARGS="--no-pull"
```

在 `apps/mobile-flutter/` 中：

```bash
flutter --no-version-check --suppress-analytics pub get
flutter --no-version-check --suppress-analytics analyze
flutter --no-version-check --suppress-analytics test
```

[设计画廊](apps/mobile-flutter/tool/gallery/main.dart)通过 mock 数据运行在 Flutter web；设备 App 入口依赖原生 FFI 和 BLE。

## 说明与贡献

[产品契约](docs/product/contract.md)、[存储模型](docs/reference/storage-state.md)、[BLE 协议](docs/reference/ble.md)、[暗语派生](docs/reference/enigma.md)、[状态机](docs/reference/state-machines.md)、[真机 E2E](apps/mobile-flutter/tool/e2e/README.md)、[贡献说明](CONTRIBUTING.md)、[架构规则](AGENTS.md)。

项目代码采用 [MIT](LICENSE) 许可证。字体、资源和依赖保留各自条款，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。Ledger 名称用于描述协议兼容性；本项目并非 Ledger 官方产品，普通手机不具备 Ledger 专用硬件的安全边界。
