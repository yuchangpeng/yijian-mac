# 译键 YiJian

> Type in your language, hit `⌥⌘T`, and your text is translated **in place** — in any app, fully offline, powered by Apple's on-device translation. Plus a `⌥⌘V` clipboard history with one-key translate.

macOS 菜单栏翻译工具:在**任何 App** 的输入框输完文字,按 `⌥⌘T`,光标旁弹出液态玻璃浮窗显示译文——**回车替换原文**,Esc 取消,Tab 换目标语言。定位是"帮你写外语",搭配任何输入法使用。

- 翻译引擎:macOS 自带 Apple Translation 框架 —— **本地、离线、免费、隐私零上传**
- 自动判方向:中文 → 目标语;检测到外语 → 自动译回母语
- **剪贴板历史**:`⌥⌘V` 弹出最近复制的内容,↑↓/数字键选择、回车粘贴,Tab 直接翻译选中条目
- 菜单栏常驻,无 Dock 图标,空闲零占用
- 浮窗材质三选(设置 → 外观):液态玻璃透明(默认)/ 液态玻璃标准 / 磨砂玻璃;柔和入场动画,自动记住上次使用的目标语言

## 构建与运行

本项目以"自己构建"的方式分发(无公证签名,直接下载的 .app 会被 Gatekeeper 拦截;本机构建则完全没有这个问题)。

要求:**macOS 26+**、**Xcode 26**(用其命令行工具链构建,零第三方依赖)。

```bash
git clone <repo-url> && cd 输入法
make run
```

即完成 编译 → 本机生成定版启动器 → 组装 `dist/YiJian.app` → 启动。其他命令:`make logs` 看运行日志,`make clean` 清理(不影响授权),`make reset-ax` 重置辅助功能授权。

## 首次使用

1. **辅助功能权限**:第一次按 `⌥⌘T` 会弹系统提示,到 系统设置 → 隐私与安全性 → 辅助功能 勾选「译键」(取词和回填替换需要)。
2. **语言包**:菜单栏图标 → 设置… → 语言包,下载需要的语言(如英语);之后完全离线可用。

## 权限为什么不会掉:稳定启动器架构(无需证书)

辅助功能授权绑定的是**主可执行文件的哈希**。本项目把 App 拆成两部分:

- `Support/YiJianLauncher`:定版启动器二进制(几十 KB),**首次构建时在你的机器上自动生成**(不入 git 仓库),唯一职责是 dlopen 动态库并调用入口。打包永远用这份定版文件,哈希永不变化 → 授权一次永久有效,`make clean`、升级 Xcode 都不影响
- `libYiJianCore.dylib`:全部应用逻辑,日常改代码只重新编译它

注意事项:

- 不要改 `Sources/YiJianLauncher/main.swift`;真要改,改完跑 `make regen-launcher` 更新定版,然后重新授权一次
- 授权异常时的急救命令:`make reset-ax`(重置本 App 的辅助功能记录),再触发一次授权;若系统设置列表里有残留的「译键」旧条目,先用 − 号删掉
- 不要手动对 `dist/YiJian.app` 整包 codesign——重签会把资源封条写进主执行文件,哈希就变了

## 使用细节

翻译(⌥⌘T):

- **选中了文字 → 只翻译替换选中部分;没选中 → 整个输入框全部翻译替换**
- 辅助功能读不到内容的 App(微信、部分 Electron 应用)会自动用 ⌘A/⌘C 模拟抓取兜底,行为一致
- 浮窗内:`⏎` 替换 / `⇥` 在 目标语 → 备选一 → 备选二 → 母语 间循环 / `esc` 取消 / `⌘C` 只复制不替换
- 菜单栏 → 还原上次替换:翻错了可一键还原
- 安全护栏:密码框一律拒绝;终端(Terminal/iTerm/Warp)和 Finder 不做全选抓取;超 3000 字要求手动选中;兜底全选后按 Esc 取消会自动收起选区,不会误覆盖
- 替换通过剪贴板粘贴完成,原剪贴板内容会自动恢复,且写入带 transient 标记(剪贴板管理器不会记录)

剪贴板历史(⌥⌘V):

- 自动记录复制过的文本(最多 50 条),存在 `~/Library/Application Support/YiJian/clipboard.json`
- 面板内:`↑↓` 选择 / `⏎` 粘贴 / `1-9` 快选 / `⇥` 翻译选中条目 / `⌘⌫` 删除 / `esc` 关闭
- 选中粘贴的条目会成为当前剪贴板内容(剪贴板管理器惯例)
- 隐私:密码管理器等标记为 concealed/transient 的内容一律不记录;可在设置里整体关闭或清空
- 注:`⌥⌘V` 会全局抢占同快捷键(如 Finder 的"移动项目到这里"),自定义快捷键在路线图中

## 架构速览

```
YiJianLauncher        定版启动器(权限锚点,永不变化,dlopen 核心库)
Entry.swift           动态库入口 → NSApplication(accessory,无 Dock)
AppDelegate           菜单栏 + TranslateCoordinator(主流程)
HotKeyManager         Carbon 全局热键 ⌥⌘T
TextGrabber           AX 取词(选中/整框)+ 光标定位 + 剪贴板兜底
PanelController       GlassPanelController 基类(磨砂面板、定位链、入场动画)+ 翻译浮窗
ClipboardStore/Panel  剪贴板历史采集、持久化 + 历史列表浮窗
PanelView/ViewModel   SwiftUI 浮窗内容 + 状态机
TranslationService    TranslationEngine 协议 + Apple 本地引擎(直接实例化 session)
Paster/Pasteboard     ⌘V 回填、剪贴板快照恢复、还原上次替换
SettingsView          设置窗口;语言包下载页是全项目唯一 .translationTask 处
```

## 已知限制

- 仅支持 macOS 26+(依赖可直接实例化的 TranslationSession 与新版系统材质)
- 快捷键暂不可自定义;`⌥⌘V` 会全局抢占同快捷键(如 Finder 的"移动项目到这里")
- 整段抓取上限 3000 字,更长请选中后翻译
- 语言范围 = 系统本地翻译引擎支持的约 20 种
- 个别辅助功能实现差的 App 中,取词走剪贴板模拟兜底,首次触发可能需要多按一次

## 路线图(v2)

- LLM 引擎(Claude/DeepL)+ 语气润色:正式 / 口语 / 简洁
- 多语言并列面板,按数字键选择
- 自定义快捷键
- 真输入法模式(打字时候选栏直接出译文)

## 许可

[MIT](LICENSE)
