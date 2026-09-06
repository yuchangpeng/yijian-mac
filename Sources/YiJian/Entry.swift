import AppKit

/// 动态库入口,由稳定启动器 dlopen 后调用
@_cdecl("yijian_main")
public func yijianMain() {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
