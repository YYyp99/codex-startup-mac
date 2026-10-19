# Codex Startup for Mac

一个非官方的 macOS Codex 动画启动器：播放动画时在后台启动并隐藏 Codex，动画结束或跳过后显示 Codex。

## 下载使用

到本仓库的 **Releases** 下载 `Codex-Startup-Mac.zip`。解压后只有一个 `Codex Startup.app`：

1. 先安装并登录官方 Codex 桌面应用。
2. 把启动器放进「应用程序」，打开一次并填入姓名、三位编号。
3. 将启动器放到 Dock，以后从这个入口启动。

姓名和编号只保存在当前 Mac 当前用户的偏好设置中，之后自动沿用，安装包不会带走你的资料。升级自旧版时会保留姓名，若缺少编号会补问一次。

窗口可以移动、调整大小，不强制全屏，不遮黑副屏。前两步点击按钮或按 Enter/空格继续；Esc、SKIP 或 Command+O 跳过并显示 Codex。Command+Q 退出启动器，Command+, 显示动画设置。

## 身份卡

- 自选三位编号，例如 `007`，显示为 `CX-007`。
- 编号逐字出现；权限从 `LEVEL 01` 递增到 `LEVEL 09 · 最高权限`。
- 点亮绿色 `● 已认证 · VERIFIED` 标记。
- 权限和认证只是动画效果，不改变 Codex 账号权限。

## 平台与签名

启动器构建为 Apple Silicon / Intel 通用二进制，部署目标 macOS 12；仍需满足官方 Codex 自身的系统要求。已在 Apple Silicon Mac 验证，Intel 未实机验证。

目前是临时签名的内部测试构建，尚未做 Developer ID 签名或 Apple 公证。另一台 Mac 首次打开可能被 Gatekeeper 阻止；它不是可以保证免提示安装的正式发行包。无需、也不应关闭系统安全保护。

## 从源码构建

需要 macOS、Xcode Command Line Tools、Python 3，以及首次下载音频时的网络连接。无需 npm install。

```sh
./scripts/build.sh
```

输出：`build/Codex Startup.app` 和 `build/Codex-Startup-Mac.zip`。音频来源固定到上游提交，并逐一校验 SHA-256。构建缓存、应用包、音频、日志和个人偏好设置不提交到 Git。

运行继承自上游的浏览器运行时冒烟检查（需要 Node.js 20+）：

```sh
npm test
```

## 实现与范围

`native/Launcher.swift` 用 AppKit 和 WKWebView 包装动画，使用 `NSWorkspace` 查找应用标识 `com.openai.codex`。这不是修改官方应用的插件。直接点击官方应用图标仍然直接启动，不播放动画。

`lib/` 是改造后的动画运行时与样式；`web/index.html` 是源页面；`scripts/` 负责验证资源、生成离线 HTML、编译和打包。姓名和编号通过 JSON 安全传给网页，存于本机 UserDefaults。

本机验证过已运行 Codex 的隐藏、完整动画和跳过后恢复。未退出当前工作应用做独立冷启动测试；系统报告应用启动完成不等于页面全部渲染完成。

## 来源与许可

基于 [6shenhonghong9/dsh-startup-screen](https://github.com/6shenhonghong9/dsh-startup-screen) 改造，保留原动画序列、交互和原始音频。原创代码遵循 MIT；第三方录音不在该 MIT 授权范围内，见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) 和 [上游说明](docs/UPSTREAM-README.md)。
