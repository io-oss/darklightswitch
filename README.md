# Kubuntu 深浅模式切换小部件

适用于 **KDE Plasma 6（API ≥ 6.0）** 的 Plasma 面板小部件（在 Kubuntu 26.04 上验证）：单击图标即可切换深色 / 浅色模式。

小部件内**没有主题配置界面**，你也不需要给它传任何主题参数。它直接读取「系统设置 → 外观 → 全局主题」里预设的浅色 / 深色主题（对应 `kdeglobals` 的 `DefaultLightLookAndFeel` / `DefaultDarkLookAndFeel`），在两者之间切换。只有在系统没有配置这对预设时，才会按当前主题名推导配对主题作为回退。

> Plasma 没有「切换深浅模式」的单一命令，系统设置里的深浅切换本质上也是应用两个不同的全局主题。所以脚本内部调用 `plasma-apply-lookandfeel --apply <主题名>` 时必须带主题名，但这个主题名是脚本自动从系统预设中读取的，不是你要提供的，也不是写死在小部件里的。

## 功能

- 面板上一键切换，图标（太阳 / 月亮）实时反映当前模式；内置 Breeze symbolic 单色描边图标，风格与 KDE 面板统一，且随面板文字颜色自动反色。图标随项目分发，不依赖系统是否安装某个图标主题
- **优先读取系统设置里预设的深浅主题**（`DefaultDarkLookAndFeel` / `DefaultLightLookAndFeel`），不写死主题名；未设置时才按当前主题名推导配对作为回退
- 状态判断依次尝试 freedesktop portal 的 `color-scheme`、`kdeglobals` 里的配色方案名 / 全局主题名，最后回退到调色板亮度
- 每 30 秒同步一次状态，系统设置或定时任务改主题后图标仍保持正确
- 附带命令行工具，可绑定到全局快捷键

## 环境要求

- KDE Plasma 6（API ≥ 6.0），已在 Kubuntu 26.04 上验证
- `python3`
- `plasma-workspace`：提供 `plasma-apply-lookandfeel`
- `kpackagetool6`：独立软件包，用于安装 / 卸载小部件
- `libkf6config-bin`：提供 `kreadconfig6`，用于读取当前配置
- `dbus-send`（可选，通常由系统预装）：用于准确读取当前明暗

如缺少命令，可先安装：

```bash
sudo apt update
sudo apt install plasma-workspace kpackagetool6 libkf6config-bin
```

## 安装

```bash
git clone https://github.com/io-oss/darklightswitch.git
cd darklightswitch
chmod +x install.sh uninstall.sh
./install.sh
```

已克隆过的项目直接 `cd` 到项目目录即可。

安装脚本会：

1. 移除同 ID 的旧版本后重新安装 `io.github.io-oss.darklightswitch`，确保升级时不残留旧文件；
2. 把命令行脚本安装到 `~/.local/bin/darklight-toggle`。

如果小部件没有立即出现在列表里，运行 `plasmashell --replace` 或注销后重新登录。

## 使用

- **添加**：面板空白处右键 → 添加小部件 → 搜索「深浅模式切换」→ 拖到面板。
- **切换**：左键单击小部件图标。
- **配置主题**：在「系统设置 → 外观 → 全局主题」中配置你的浅色 / 深色主题。小部件直接读取这两个预设（`DefaultLightLookAndFeel` / `DefaultDarkLookAndFeel`），只负责在两者之间切换，不提供额外设置项。

### 命令行

```bash
darklight-toggle status   # 输出 light 或 dark
darklight-toggle toggle   # 切换到另一种模式，并输出新模式
darklight-toggle light    # 强制切到浅色全局主题
darklight-toggle dark     # 强制切到深色全局主题
```

可以在「系统设置 → 快捷键 → 自定义快捷键」中把 `darklight-toggle toggle` 绑定为全局快捷键。

## 验证

两层测试都要跑：

```bash
python3 tests/test_toggle.py   # 模拟测试：验证脚本逻辑与主题配对
./tests/smoke_real.sh          # 真机测试：真实切换两次并自动恢复原状
```

`smoke_real.sh` 会在真实 Plasma 会话里执行 toggle，检查 `ColorScheme` 是否真的改变、两次切换方向是否相反 —— 这是模拟测试覆盖不到的部分（模拟测试无法验证系统命令的参数是否正确、调用是否真的生效）。脚本用 `trap` 保证无论成功失败都恢复你原来的主题。

## 卸载

```bash
./uninstall.sh
```

## 目录结构

```text
.
├── .gitignore
├── install.sh
├── uninstall.sh
├── README.md
├── src/
│   └── package/
│       ├── metadata.json
│       └── contents/
│           ├── code/darklight-toggle      # 核心切换脚本
│           └── ui/
│               ├── main.qml               # 小部件界面
│               └── icons/                 # 内置 Breeze symbolic 单色图标（随项目分发）
│                   ├── sun.svg
│                   └── moon.svg
└── tests/
    ├── test_toggle.py                     # 模拟测试
    └── smoke_real.sh                      # 真机往返冒烟测试（自动恢复原状）
```

## 故障排查

- **点击后没有变化**：确认 `plasma-apply-lookandfeel --list` 能列出浅色和深色全局主题（注意是 `--list`，不是 `--list-themes`）。
- **提示找不到配对主题**：确认「系统设置 → 外观」里配置了浅色和深色全局主题（对应 `DefaultLightLookAndFeel` / `DefaultDarkLookAndFeel`）。只有未配置预设时才会按主题名称推导，此时需要一对名称里带 `dark`/`light` 或 `深色`/`浅色` 的主题。
- **图标状态不对**：状态判断依次尝试 portal 的明暗值、`kdeglobals` 里的配色方案名 / 全局主题名、调色板亮度；D-Bus 不可用时会自动走后面的回退。
- **GTK 应用颜色不同步**：本小部件只切换 Plasma 的全局主题，不负责 GTK 应用的配色。GTK 应用需另行在系统设置中配置 GTK 样式，或安装 `breeze-gtk-theme`。
