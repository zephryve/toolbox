# SleepToggle PRD

## 背景

macOS 合盖/按电源键后系统进入睡眠，WiFi 断开，后台任务中断。对于需要合盖跑长时间任务（下载、同步、编译、远程连接）的场景，需要一种方式禁止系统睡眠。

底层命令 `sudo pmset -a disablesleep 1/0` 可以实现，但每次开终端敲命令不方便，且容易忘记恢复。

## 目标用户

自用为主，可分享给朋友。要求零依赖，双击即用。

## 核心需求

### 必须有

1. **菜单栏常驻图标**：不显示 Dock 图标，只在菜单栏显示
2. **一键切换**：点击菜单栏图标 → 下拉菜单 → "切换模式"
3. **两种状态**：
   - 正常模式：空心闪电（bolt），系统默认颜色，系统可正常睡眠
   - 强力模式：实心闪电（bolt.fill），橙色，禁止一切睡眠（合盖、电源键、自动睡眠均失效）
4. **退出自动恢复**：退出 app 时自动执行 `disablesleep 0`，防止忘记
5. **开机自启**：通过 LaunchAgent 实现登录后自动启动

### 不做

- 温度监控 / CPU 监控（原参考项目有，砍掉）
- 定时自动恢复
- 通知提醒
- 多语言

## 技术方案

| 项目 | 选择 | 理由 |
|------|------|------|
| 语言 | Swift | 零依赖，编译成原生 .app，体积小，可直接分享 |
| 菜单栏 | NSStatusBar + NSMenu | macOS 原生 API，不需要第三方库 |
| 图标 | SF Symbols（bolt / bolt.fill） | 系统内置矢量图标，不需要图片资源 |
| 睡眠控制 | `sudo pmset -a disablesleep 1/0` | macOS 标准电源管理命令 |
| 免密 | `/etc/sudoers.d/sleeptoggle` | 仅对 pmset 命令免密，安全可控 |
| 开机自启 | LaunchAgent plist | macOS 标准方式 |
| 打包 | swiftc 直接编译 + 手动组装 .app bundle | 不需要 Xcode 项目，build.sh 搞定 |

### 曾考虑但排除的方案

- **Python + rumps**：需要 Python 运行时，打包体积大（几十 MB），分享不便
- **Shell alias**：没有图标状态反馈，不直观
- **AppleScript**：语法差，sudo 支持差，代码量不比 Swift 少
- **快捷指令**：sudo 支持差，无法实时显示状态图标

## 文件结构

```
sleep-toggle/
├── SleepToggle.swift    # 主程序源码
├── build.sh             # 编译脚本，生成 SleepToggle.app
├── setup.sh             # 一键安装（免密 + 编译 + 开机自启 + 启动）
├── README.md            # 使用说明
└── PRD.md               # 本文档
```

## 安装流程

1. 用户下载项目文件
2. 终端执行 `bash setup.sh`
3. 输入一次管理员密码（配置 pmset 免密）
4. 自动编译、配置开机自启、启动 app
5. 菜单栏出现闪电图标，完成
