import AppKit
import WebKit
import QuartzCore

final class AnimationWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class Launcher: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var displayName = ""
    var identityCode = "001"
    let codeKey = "profile.identityCode"
    let nameKey = "profile.displayName"
    var window: NSWindow!
    var web: WKWebView!
    var visibilityObservers: [NSObjectProtocol] = []
    var restoreOnCancel = false
    var handoffTimer: Timer?
    var revealing = false
    func log(_ text: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("codex-startup-launcher-diagnostic.log")
        let line = "\(Date()) \(text)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
        } else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }
    var launching = false
    var quitting = false
    var warmupStarted = false
    var warmupComplete = false
    var watchdog: Timer?
    let targetID = "com.openai.codex"

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard loadProfile() else { NSApp.terminate(nil); return }
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "立即打开 Codex / 跳过动画", action: #selector(skip), keyEquivalent: "o").target = self
        appMenu.addItem(withTitle: "显示／隐藏动画设置", action: #selector(toggleSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出启动器", action: #selector(quit), keyEquivalent: "q").target = self
        NSApp.mainMenu = menu
        restoreOnCancel = NSRunningApplication.runningApplications(withBundleIdentifier: targetID).contains { !$0.isTerminated && !$0.isHidden }
        watchCodexVisibility()
        showAnimation()
        prepareCodex()
    }

    func loadProfile() -> Bool {
        let saved = (UserDefaults.standard.string(forKey: nameKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let savedCode = UserDefaults.standard.string(forKey: codeKey) ?? ""
        func validCode(_ code: String) -> Bool {
            code.utf8.count == 3 && code.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
        }
        if !saved.isEmpty && validCode(savedCode) {
            displayName = saved
            identityCode = savedCode
            log("profile loaded from local preferences")
            return true
        }
        NSApp.activate(ignoringOtherApps: true)
        let prompt = NSAlert()
        prompt.messageText = "欢迎使用 Codex"
        prompt.informativeText = "填写姓名和三位编号，建立你的身份档案。资料只保存在本机，以后自动沿用。"
        let panel = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 90))
        let nameLabel = NSTextField(labelWithString: "姓名")
        nameLabel.frame = NSRect(x: 0, y: 56, width: 70, height: 24)
        panel.addSubview(nameLabel)
        let field = NSTextField(frame: NSRect(x: 85, y: 55, width: 260, height: 26))
        field.stringValue = saved
        field.placeholderString = "请输入姓名"
        field.setAccessibilityLabel("姓名")
        panel.addSubview(field)
        let codeLabel = NSTextField(labelWithString: "编号 CX-")
        codeLabel.frame = NSRect(x: 0, y: 16, width: 80, height: 24)
        panel.addSubview(codeLabel)
        let codeField = NSTextField(frame: NSRect(x: 85, y: 15, width: 260, height: 26))
        codeField.placeholderString = "三位数字，例如 001"
        codeField.stringValue = validCode(savedCode) ? savedCode : "001"
        codeField.setAccessibilityLabel("三位编号")
        panel.addSubview(codeField)
        field.nextKeyView = codeField
        prompt.accessoryView = panel
        prompt.addButton(withTitle: "保存并开始")
        prompt.addButton(withTitle: "取消")
        prompt.window.initialFirstResponder = field
        while true {
            let response = prompt.runModal()
            guard response == .alertFirstButtonReturn else { return false }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let code = codeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let valid = !name.isEmpty && name.count <= 40 && name.rangeOfCharacter(from: .controlCharacters) == nil
            guard valid && validCode(code) else {
                prompt.informativeText = "姓名需为 1–40 个字符；编号必须为三位数字（000–999），例如 007。"
                continue
            }
            displayName = name
            identityCode = code
            UserDefaults.standard.set(name, forKey: nameKey)
            UserDefaults.standard.set(code, forKey: codeKey)
            log("profile saved locally")
            return true
        }
    }

    func showAnimation() {
        guard let html = Bundle.main.url(forResource: "startup", withExtension: "html") else {
            showError("找不到启动动画资源。可点击确定直接打开 Codex。", thenLaunch: true); return
        }
        log("starting animation")
        let content = WKUserContentController()
        content.add(self, name: "codexLauncher")
        let nameData = try! JSONSerialization.data(withJSONObject: displayName, options: [.fragmentsAllowed])
        let nameJSON = String(data: nameData, encoding: .utf8)!
        let codeData = try! JSONSerialization.data(withJSONObject: identityCode, options: [.fragmentsAllowed])
        let codeJSON = String(data: codeData, encoding: .utf8)!
        let bridge = """
        window.__CODEX_PROFILE_ID__ = \(codeJSON);
        window.__CODEX_PROFILE_NAME__ = \(nameJSON);
        window.__CODEX_NATIVE_HANDOFF__ = true;
        window.addEventListener('codex-startup:handoff', function () {
          window.webkit.messageHandlers.codexLauncher.postMessage('launch');
        });
        window.addEventListener('dsh-startup:done', function () {
          window.webkit.messageHandlers.codexLauncher.postMessage('launch');
        });
        window.addEventListener('DOMContentLoaded', function () {
          ['fIdentity', 'sIdentity'].forEach(function (id) {
            var field = document.getElementById(id);
            if (field) field.value = window.__CODEX_PROFILE_NAME__;
          });
          ['fId', 'sId'].forEach(function (id) {
            var field = document.getElementById(id);
            if (field) field.value = window.__CODEX_PROFILE_ID__;
          });
          window.webkit.messageHandlers.codexLauncher.postMessage('ready');
        });
        """
        content.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let config = WKWebViewConfiguration()
        config.userContentController = content
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = []
        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        let bounds = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = NSSize(width: min(1100, bounds.width * 0.85), height: min(760, bounds.height * 0.85))
        window = AnimationWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Codex"
        window.minSize = NSSize(width: 700, height: 520)
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.contentView = web
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        watchdog = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.log("startup watchdog fired"); self?.launchCodex()
        }
        web.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
    }

    func hideDuringAnimation(_ target: NSRunningApplication) {
        guard !launching && !quitting && target.bundleIdentifier == targetID else { return }
        if !target.isHidden {
            let accepted = target.hide()
            log("hide Codex during animation: accepted=\(accepted), hidden=\(target.isHidden), policy=\(target.activationPolicy.rawValue), name=\(target.localizedName ?? "unknown")")
        }
    }
    func watchCodexVisibility() {
        let center = NSWorkspace.shared.notificationCenter
        for event in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            visibilityObservers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] note in
                guard let target = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.hideDuringAnimation(target)
            })
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        visibilityObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        log("message: \(message.body) frame=\(message.frameInfo.isMainFrame) url=\(String(describing: message.frameInfo.request.url)) web=\(String(describing: web.url))")
        guard message.frameInfo.isMainFrame, web.url?.isFileURL == true else { return }
        if message.body as? String == "ready" {
            watchdog?.invalidate()
            // The original runtime owns animation timing; only check that initialization succeeded.
            web.evaluateJavaScript("!!window.__DSH_STARTUP_API__") { [weak self] result, error in
                self?.log("runtime ready: \(String(describing: result)), error=\(String(describing: error))")
                if error != nil || (result as? Bool) != true { self?.launchCodex() }
            }
        } else if message.body as? String == "launch" { launchCodex() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let local = navigationAction.request.url?.isFileURL == true
        decisionHandler(local ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { launchCodex() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { launchCodex() }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { launchCodex() }

    @objc func skip() { launchCodex() }
    @objc func toggleSettings() {
        web?.evaluateJavaScript("document.getElementById('console').classList.toggle('launcher-show-settings')", completionHandler: nil)
    }
    @objc func quit() {
        quitting = true
        if restoreOnCancel {
            NSRunningApplication.runningApplications(withBundleIdentifier: targetID).forEach { $0.unhide() }
        }
        NSApp.terminate(nil)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !quitting { launchCodex(); return false }
        return true
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil); return true
    }
    func showError(_ text: String, thenLaunch: Bool = false) {
        let alert = NSAlert(); alert.messageText = "Codex 启动器"; alert.informativeText = text
        alert.addButton(withTitle: "确定")
        alert.window.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        if thenLaunch { launchCodex() }
    }
    // Start loading Codex while the animation owns the foreground.
    // Codex windows stay hidden until the user completes or skips the animation.
    func prepareCodex() {
        guard !warmupStarted && !quitting else { return }
        warmupStarted = true
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: targetID).first(where: { !$0.isTerminated }) {
            hideDuringAnimation(existing)
            log("Codex already running; requesting hidden launch through LaunchServices")
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetID) else {
            warmupComplete = true
            log("background warmup: Codex not found")
            if launching { activateCodex() }
            return
        }
        let options = NSWorkspace.OpenConfiguration()
        options.activates = false
        options.hides = true
        log("starting Codex in background during animation")
        NSWorkspace.shared.openApplication(at: appURL, configuration: options) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self = self, !self.quitting else { return }
                self.warmupComplete = true
                if let error = error { self.log("background warmup failed: \(error.localizedDescription)") }
                else {
                    if let app = app { self.hideDuringAnimation(app) }
                    self.log("background launch completed; hidden=\(app?.isHidden ?? false)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self = self, !self.launching, !self.quitting, let app = app else { return }
                        self.hideDuringAnimation(app)
                        self.log("hidden-state verification: \(app.isHidden)")
                    }
                }
                if self.launching { self.activateCodex() }
            }
        }
    }
    func launchCodex() {
        guard !launching && !quitting else { return }
        log("animation handoff requested"); watchdog?.invalidate(); launching = true
        // Early skipping joins the existing launch, rather than starting a duplicate.
        if !warmupStarted { prepareCodex() }
        else if warmupComplete { activateCodex() }
        else { window?.title = "Codex 正在启动…" }
    }
    func activateCodex() {
        guard !quitting else { return }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetID) else {
            launching = false
            showError("未找到已安装的 Codex（com.openai.codex）。请先安装或打开官方应用后重试。")
            return
        }
        let options = NSWorkspace.OpenConfiguration()
        options.activates = true
        // Raise only this small window during the final fade; never cover other displays.
        window?.level = .floating
        log("showing and activating hidden Codex after animation")
        NSWorkspace.shared.openApplication(at: appURL, configuration: options) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.launching = false; self.showError("打开 Codex 失败：\(error.localizedDescription)")
                } else {
                    self.log("Codex activation returned; waiting for foreground")
                    self.waitForForeground(app)
                }
            }
        }
    }
    func waitForForeground(_ target: NSRunningApplication?) {
        var ticks = 0
        handoffTimer?.invalidate()
        handoffTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self, !self.quitting else { timer.invalidate(); return }
            ticks += 1
            if let target = target, !target.isTerminated, target.isFinishedLaunching, target.isActive, ticks >= 4 {
                timer.invalidate(); self.revealCodex(); return
            }
            if ticks >= 100 {
                timer.invalidate(); self.launching = false
                self.log("foreground not confirmed; retaining animation window")
                self.showError("Codex 尚未进入前台。请按 Command+O 重试，或 Command+Q 退出启动器。")
            }
        }
    }
    func revealCodex() {
        guard !revealing else { return }
        revealing = true
        log("Codex active; fading animation window")
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.window?.animator().alphaValue = 0

        }, completionHandler: {
            self.log("seamless handoff complete")
            self.quitting = true
            NSApp.terminate(nil)
        })
    }

}
let app = NSApplication.shared
let delegate = Launcher()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
