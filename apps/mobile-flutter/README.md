# Flutter device app

This directory contains the Open Ledger App device app. Read the repository [README](../../README.md), [build instructions](../../BUILDING.md), [security policy](../../SECURITY.md) and [product contract](../../docs/product/contract.md).

Run Flutter commands here, and Rust/Makefile commands at the repository root. Android packaging requires the Rust shared library; Flutter-only APK construction does not create it. The web entry point is `tool/gallery/main.dart` with mock data, not `lib/main.dart`.
