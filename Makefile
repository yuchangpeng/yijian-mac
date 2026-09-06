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
	mkdir -p $(DIST)/Contents/MacOS $(DIST)/Contents/Frameworks $(DIST)/Contents/Resources
	cp Support/Info.plist $(DIST)/Contents/Info.plist
	cp Support/YiJianLauncher $(DIST)/Contents/MacOS/$(APP_NAME)
	cp .build/$(CONFIG)/libYiJianCore.dylib $(DIST)/Contents/Frameworks/
	cp Support/AppIcon.icns $(DIST)/Contents/Resources/AppIcon.icns

# 重新生成 App 图标(改了 Tools/make-icon.swift 后用)
icon:
	swift Tools/make-icon.swift Support
	rm -rf .build/AppIcon.iconset && mkdir -p .build/AppIcon.iconset
	for sz in 16 32 128 256 512; do sips -z $$sz $$sz Support/AppIcon-1024.png --out .build/AppIcon.iconset/icon_$${sz}x$${sz}.png >/dev/null; done
	for sz in 16 32 128 256; do dbl=$$((sz*2)); sips -z $$dbl $$dbl Support/AppIcon-1024.png --out .build/AppIcon.iconset/icon_$${sz}x$${sz}@2x.png >/dev/null; done
	cp Support/AppIcon-1024.png .build/AppIcon.iconset/icon_512x512@2x.png
	iconutil -c icns .build/AppIcon.iconset -o Support/AppIcon.icns

.PHONY: icon

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
