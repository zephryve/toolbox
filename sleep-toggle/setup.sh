#!/bin/bash
set -e

APP_NAME="SleepToggle"
APP_PATH="/Applications/$APP_NAME.app"
BUNDLE_ID="com.zephryve.sleeptoggle"
SUDOERS_FILE="/etc/sudoers.d/sleeptoggle"
PLIST_PATH="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
USERNAME=$(whoami)
TMPDIR_BUILD=$(mktemp -d)

echo "========================================="
echo "  SleepToggle 一键安装"
echo "========================================="
echo ""

# 1. 检查 swiftc
if ! command -v swiftc &>/dev/null; then
    echo "未找到 swiftc，请先安装 Xcode Command Line Tools："
    echo "  xcode-select --install"
    exit 1
fi

# 2. 写入 Swift 源码（主程序）
cat > "$TMPDIR_BUILD/$APP_NAME.swift" << 'SWIFT_SOURCE'
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var sleepDisabled = false
    var toggleMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        sleepDisabled = readCurrentState()
        updateIcon()
        setupMenu()
    }

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
        } catch {}
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
        let tooltip = sleepDisabled ? "强力模式：睡眠已禁止" : "正常模式：睡眠正常"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let configured = image.withSymbolConfiguration(config)!
            configured.isTemplate = !sleepDisabled
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
                showAlert("切换失败", message: "pmset 返回错误码 \(process.terminationStatus)，请检查 sudo 免密配置是否正确。\n\n重新运行 setup.sh 可自动修复。")
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
            } catch {}
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
SWIFT_SOURCE

# 3. 写入图标生成脚本
cat > "$TMPDIR_BUILD/GenerateIcon.swift" << 'ICON_SOURCE'
import AppKit

let outputDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

let iconsetPath = outputDir.appendingPathComponent("AppIcon.iconset")
let icnsPath = outputDir.appendingPathComponent("AppIcon.icns")

let fm = FileManager.default
try? fm.removeItem(at: iconsetPath)
try fm.createDirectory(at: iconsetPath, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16",       16),
    ("icon_16x16@2x",    32),
    ("icon_32x32",       32),
    ("icon_32x32@2x",    64),
    ("icon_128x128",     128),
    ("icon_128x128@2x",  256),
    ("icon_256x256",     256),
    ("icon_256x256@2x",  512),
    ("icon_512x512",     512),
    ("icon_512x512@2x",  1024),
]

let bgColor = NSColor(red: 0x1a/255.0, green: 0x1a/255.0, blue: 0x1a/255.0, alpha: 1.0)
let borderColor = NSColor(red: 0x55/255.0, green: 0x55/255.0, blue: 0x55/255.0, alpha: 1.0)
let boltColor = NSColor(red: 0xFF/255.0, green: 0xD7/255.0, blue: 0x00/255.0, alpha: 1.0)
let boltStrokeColor = NSColor(red: 0x00/255.0, green: 0x00/255.0, blue: 0x00/255.0, alpha: 0.8)

for (name, px) in sizes {
    let size = NSSize(width: px, height: px)
    let image = NSImage(size: size, flipped: false) { rect in
        let padding = px * 0.09
        let contentRect = rect.insetBy(dx: padding, dy: padding)
        let cornerRadius = contentRect.width * 0.22
        let path = NSBezierPath(roundedRect: contentRect, xRadius: cornerRadius, yRadius: cornerRadius)
        bgColor.setFill()
        path.fill()

        let borderWidth = max(1.0, px / 128.0)
        let bInset = borderWidth / 2.0
        let borderRect = contentRect.insetBy(dx: bInset, dy: bInset)
        let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: cornerRadius - bInset, yRadius: cornerRadius - bInset)
        borderPath.lineWidth = borderWidth
        borderColor.setStroke()
        borderPath.stroke()

        let symbolSize = px * 0.6
        let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .bold)
        if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let tinted = NSImage(size: bolt.size, flipped: false) { tintRect in
                bolt.draw(in: tintRect)
                boltColor.set()
                tintRect.fill(using: .sourceAtop)
                return true
            }
            let x = (px - tinted.size.width) / 2.0
            let y = (px - tinted.size.height) / 2.0
            tinted.draw(in: NSRect(x: x, y: y, width: tinted.size.width, height: tinted.size.height))
        }
        return true
    }

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: iconsetPath.appendingPathComponent("\(name).png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath.path, "-o", icnsPath.path]
try process.run()
process.waitUntilExit()

// 清理 iconset 目录
try? fm.removeItem(at: iconsetPath)
ICON_SOURCE

# 4. 生成图标
echo "生成 app 图标..."
swiftc "$TMPDIR_BUILD/GenerateIcon.swift" -o "$TMPDIR_BUILD/generate-icon" -framework AppKit
"$TMPDIR_BUILD/generate-icon" "$TMPDIR_BUILD"
echo "  图标生成完成"
echo ""

# 5. 编译主程序
echo "编译 SleepToggle..."
APP_BUILD="$TMPDIR_BUILD/$APP_NAME.app"
mkdir -p "$APP_BUILD/Contents/MacOS"
mkdir -p "$APP_BUILD/Contents/Resources"
swiftc "$TMPDIR_BUILD/$APP_NAME.swift" -o "$APP_BUILD/Contents/MacOS/$APP_NAME" -framework Cocoa

# 放入图标
cp "$TMPDIR_BUILD/AppIcon.icns" "$APP_BUILD/Contents/Resources/AppIcon.icns"

# Info.plist（包含图标引用）
cat > "$APP_BUILD/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>SleepToggle</string>
    <key>CFBundleIdentifier</key>
    <string>com.zephryve.sleeptoggle</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleExecutable</key>
    <string>SleepToggle</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF
echo "  编译完成"
echo ""

# 6. 安装到 /Applications
echo "安装到 /Applications..."
if [ -d "$APP_PATH" ]; then
    rm -rf "$APP_PATH"
fi
cp -R "$APP_BUILD" "$APP_PATH"
echo "  安装完成"
echo ""

# 7. 配置 sudo 免密（仅 pmset）
echo "配置 sudo 免密权限（仅限 pmset 命令）..."
echo "  需要输入一次管理员密码："
sudo tee "$SUDOERS_FILE" > /dev/null <<SUDOERS
$USERNAME ALL=(ALL) NOPASSWD: /usr/bin/pmset
SUDOERS
sudo chmod 0440 "$SUDOERS_FILE"
echo "  免密配置完成"
echo ""

# 8. 配置开机自启
echo "配置开机自启..."
mkdir -p "$HOME/Library/LaunchAgents"
if launchctl list "$BUNDLE_ID" &>/dev/null; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>$APP_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST

launchctl load "$PLIST_PATH"
echo "  开机自启已配置"
echo ""

# 9. 清理临时文件并启动
rm -rf "$TMPDIR_BUILD"
echo "启动 SleepToggle..."
open "$APP_PATH"
echo ""
echo "========================================="
echo "  安装完成！"
echo ""
echo "  app 位置: /Applications/SleepToggle.app"
echo "  Spotlight 搜索 SleepToggle 即可启动"
echo ""
echo "  空心闪电 = 正常模式（可睡眠）"
echo "  实心橙色闪电 = 强力模式（禁止睡眠）"
echo ""
echo "  点击图标 -> 切换模式"
echo "  退出时自动恢复正常睡眠"
echo "========================================="
