# SleepToggle ⚡

一个极简的 macOS 菜单栏工具，一键切换系统睡眠开关。

## 功能

- **正常模式**：空心闪电 ⚡（灰色）— 系统正常睡眠
- **强力模式**：实心闪电 ⚡（橙色）— 禁止一切睡眠（合盖、按电源键、自动睡眠全部失效）
- 点击菜单栏图标 → "切换模式" 即可切换
- 退出时自动恢复正常睡眠，不用担心忘记关
- 开机自启，常驻菜单栏

## 安装

```bash
# 一键安装（编译 + 配置免密 + 开机自启）
bash setup.sh
```

安装过程需要输入一次管理员密码，用于配置 `pmset` 命令的 sudo 免密权限。

## 手动编译

```bash
bash build.sh
open SleepToggle.app
```

需要自行配置 sudo 免密：
```bash
sudo visudo
# 添加：你的用户名 ALL=(ALL) NOPASSWD: /usr/bin/pmset
```

## 卸载

```bash
# 移除开机自启
launchctl unload ~/Library/LaunchAgents/com.zephryve.sleeptoggle.plist
rm ~/Library/LaunchAgents/com.zephryve.sleeptoggle.plist

# 移除 sudo 免密配置
sudo rm /etc/sudoers.d/sleeptoggle

# 删除 app
rm -rf SleepToggle.app
```

## 要求

- macOS（Apple Silicon 或 Intel）
- Xcode Command Line Tools（`xcode-select --install`）

## 原理

底层就是 `sudo pmset -a disablesleep 1/0`，这个工具只是给它加了一个菜单栏图标，省得每次开终端敲命令。
