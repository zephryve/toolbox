#!/usr/bin/swift
// generate-icon.swift
// 生成 SleepToggle 的 macOS app icon (.icns)
// 深色背景 + 橙色闪电符号

import AppKit

let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let iconsetPath = outputDir.appendingPathComponent("AppIcon.iconset")
let icnsPath = outputDir.appendingPathComponent("AppIcon.icns")

// 创建 iconset 目录
let fm = FileManager.default
try? fm.removeItem(at: iconsetPath)
try fm.createDirectory(at: iconsetPath, withIntermediateDirectories: true)

// macOS icon 所需尺寸：(文件名后缀, 像素尺寸)
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

for (name, px) in sizes {
    let size = NSSize(width: px, height: px)
    let image = NSImage(size: size, flipped: false) { rect in
        // macOS 图标规范：内容区约占画布 80%，居中，边缘留透明
        let padding = px * 0.09
        let contentRect = rect.insetBy(dx: padding, dy: padding)
        let cornerRadius = contentRect.width * 0.22
        let path = NSBezierPath(roundedRect: contentRect, xRadius: cornerRadius, yRadius: cornerRadius)
        bgColor.setFill()
        path.fill()

        // 细描边
        let borderWidth = max(1.0, px / 128.0)
        let bInset = borderWidth / 2.0
        let borderRect = contentRect.insetBy(dx: bInset, dy: bInset)
        let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: cornerRadius - bInset, yRadius: cornerRadius - bInset)
        borderPath.lineWidth = borderWidth
        borderColor.setStroke()
        borderPath.stroke()

        // 闪电符号
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

    // 保存为 PNG
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(name)")
        continue
    }
    let filePath = iconsetPath.appendingPathComponent("\(name).png")
    try png.write(to: filePath)
    print("Generated \(name).png (\(Int(px))x\(Int(px)))")
}

// 用 iconutil 转换为 .icns
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath.path, "-o", icnsPath.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Successfully created \(icnsPath.path)")
} else {
    print("iconutil failed with status \(process.terminationStatus)")
}
