import Foundation

// 稳定启动器:辅助功能授权绑定在这个可执行文件的哈希上,它永不重新编译。
// 全部应用逻辑在 libYiJianCore.dylib 里,重新构建只更新 dylib,授权不掉。
// ⚠️ 不要修改这个文件——一旦启动器二进制变化,辅助功能授权就要重新给一次。

let candidates = [
    // .app 内:Contents/MacOS/YiJian → Contents/Frameworks/
    Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libYiJianCore.dylib"),
    // 直接跑 .build/debug/YiJian 时:dylib 就在旁边
    URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        .deletingLastPathComponent().appendingPathComponent("libYiJianCore.dylib"),
]

var handle: UnsafeMutableRawPointer?
for url in candidates where FileManager.default.fileExists(atPath: url.path) {
    handle = dlopen(url.path, RTLD_NOW)
    if handle != nil { break }
}

guard let handle else {
    let message = dlerror().map { String(cString: $0) } ?? "libYiJianCore.dylib not found"
    FileHandle.standardError.write(Data(("YiJian launcher error: " + message + "\n").utf8))
    exit(1)
}
guard let symbol = dlsym(handle, "yijian_main") else {
    FileHandle.standardError.write(Data("YiJian launcher error: entry point yijian_main not found\n".utf8))
    exit(2)
}

typealias EntryPoint = @convention(c) () -> Void
unsafeBitCast(symbol, to: EntryPoint.self)()
