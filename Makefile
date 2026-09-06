APP_NAME = YiJian
BUNDLE_ID = dev.chendi.yijian
CONFIG ?= debug
DIST = dist/$(APP_NAME).app

.PHONY: build bundle run logs clean reset-ax

build:
	swift build -c $(CONFIG)

# 定版启动器:首次构建时在本机自动生成(不入 git 仓库,每台机器一份自己的)。
# 辅助功能授权绑定它的哈希,之后重新构建/make clean/升级工具链都不会让授权失效。
Support/YiJianLauncher:
	swift build -c $(CONFIG)
	cp .build/$(CONFIG)/$(APP_NAME) $@

# 注意:不对 .app 整包 codesign——手动重签会把资源封条写进主执行文件、改变哈希。
bundle: build Support/YiJianLauncher
	rm -rf $(DIST)
	mkdir -p $(DIST)/Contents/MacOS $(DIST)/Contents/Frameworks
	cp Support/Info.plist $(DIST)/Contents/Info.plist
	cp Support/YiJianLauncher $(DIST)/Contents/MacOS/$(APP_NAME)
	cp .build/$(CONFIG)/libYiJianCore.dylib $(DIST)/Contents/Frameworks/

# 仅在修改了启动器源码时使用;定版更新后需要重新授予一次辅助功能权限
regen-launcher: build
	cp .build/$(CONFIG)/$(APP_NAME) Support/YiJianLauncher

.PHONY: regen-launcher

run: bundle
	open $(DIST)

logs:
	log stream --predicate 'subsystem == "$(BUNDLE_ID)"' --level debug --style compact

reset-ax:
	tccutil reset Accessibility $(BUNDLE_ID)

clean:
	rm -rf .build dist
