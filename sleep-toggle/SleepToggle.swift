import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var sleepDisabled = false
    var toggleMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 启动时读取系统实际状态，避免 app 重启后状态不一致
        sleepDisabled = readCurrentState()
        updateIcon()
        setupMenu()
    }

    /// 读取 pmset -g 输出，判断当前 disablesleep 的实际状态
    func readCurrentState() -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.contains("SleepDisabled") && output.contains("1")
            }
        } catch {
            // 读取失败默认当作正常模式
        }
        return false
    }

    func setupMenu() {
        let menu = NSMenu()
        toggleMenuItem = NSMenuItem(title: menuTitle(), action: #selector(toggleSleep), keyEquivalent: "t")
        menu.addItem(toggleMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 SleepToggle", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuTitle() -> String {
        return sleepDisabled ? "切换到正常模式：可以睡眠" : "切换到强力模式：保持唤醒"
    }

    func updateIcon() {
        guard let button = statusItem.button else { return }

        let symbolName = sleepDisabled ? "bolt.circle.fill" : "bolt.circle"
        let description = sleepDisabled ? "强力模式" : "正常模式"
        let tooltip = sleepDisabled ? "强力模式：保持唤醒" : "正常模式：可以睡眠"

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let configured = image.withSymbolConfiguration(config)!
            configured.isTemplate = !sleepDisabled  // 强力模式关掉模板，让橙色生效
            button.image = configured
            button.contentTintColor = sleepDisabled ? NSColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0) : nil
        }
        button.toolTip = tooltip
        toggleMenuItem?.title = menuTitle()
    }

    @objc func toggleSleep() {
        let newValue = !sleepDisabled
        let flag = newValue ? "1" : "0"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["pmset", "-a", "disablesleep", flag]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                sleepDisabled = newValue
                updateIcon()
            } else {
                showAlert("切换失败", message: "pmset 返回错误码 \(process.terminationStatus)，请检查 sudo 免密配置是否正确。\n\n运行 setup.sh 可自动修复。")
            }
        } catch {
            showAlert("切换失败", message: "无法执行 pmset：\(error.localizedDescription)")
        }
    }

    @objc func quitApp() {
        if sleepDisabled {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["pmset", "-a", "disablesleep", "0"]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // 退出时尽力恢复，失败也不阻塞退出
            }
        }
        NSApp.terminate(nil)
    }

    func showAlert(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
