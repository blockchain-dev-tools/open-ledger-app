SHELL := /bin/bash
.DEFAULT_GOAL := deploy

SCRIPT := apps/mobile-flutter/scripts/build_and_install.sh
IOS_SCRIPT := apps/mobile-flutter/scripts/build_and_install_ios.sh
# 透传参数：make deploy ARGS="--device xxx --release"
ARGS ?=

.PHONY: help deploy build install check ios ios-run ios-build ios-check

help: ## 显示所有可用命令
	@grep -E '^[a-zA-Z0-9._-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
		awk -F':.*?## ' '{printf "  \033[0;32m%-24s\033[0m %s\n", $$1, $$2}'

deploy: ## 拉取最新代码 + 编译 Rust + 构建 APK + 设备预检 + 安装（默认）
	@bash $(SCRIPT) $(ARGS)

build: ## 只构建（Rust + APK），不安装
	@bash $(SCRIPT) --build-only $(ARGS)

install: ## 只安装已构建的 APK（含设备预检）
	@bash $(SCRIPT) --install-only $(ARGS)

check: ## 只做设备连接/模式/权限预检
	@bash $(SCRIPT) --check-only $(ARGS)

ios: ## iOS：构建并安装到 iPhone（默认 release；调试用 ARGS="--debug"）
	@bash $(IOS_SCRIPT) $(ARGS)

ios-run: ## iOS：构建 + 安装 + 附加调试会话（热重载，默认 debug）
	@bash $(IOS_SCRIPT) --run $(ARGS)

ios-build: ## iOS：只构建 Runner.app，不安装
	@bash $(IOS_SCRIPT) --build-only $(ARGS)

ios-check: ## iOS：设备/工具链预检（不构建）
	@bash $(IOS_SCRIPT) --check-only $(ARGS)
