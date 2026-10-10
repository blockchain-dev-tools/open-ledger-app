SHELL := /bin/bash
.DEFAULT_GOAL := deploy

SCRIPT := apps/mobile-flutter/scripts/build_and_install.sh
# 透传参数：make deploy ARGS="--device xxx --release"
ARGS ?=

.PHONY: help deploy build install check

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
