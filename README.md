# Kubuntu 深浅模式切换小部件

适用于 **KDE Plasma 6（API ≥ 6.0）** 的 Plasma 面板小部件（在 Kubuntu 26.04 上验证）：单击图标即可切换深色 / 浅色模式。

小部件内**没有主题配置界面**，你也不需要给它传任何主题参数。它直接读取「系统设置 → 外观 → 全局主题」里预设的浅色 / 深色主题（对应 `kdeglobals` 的 `DefaultLightLookAndFeel` / `DefaultDarkLookAndFeel`），在两者之间切换。只有在系统没有配置这对预设时，才会按当前主题名推导配对主题作为回退。

> Plasma 没有「切换深浅模式」的单一命令，系统设置里的深浅切换本质上也是应用两个不同的全局主题。所以脚本内部调用 `plasma-apply-lookandfeel --apply <主题名>` 时必须带主题名，但这个主题名是脚本自动从系统预设中读取的，不是你要提供的，也不是写死在小部件里的。

切换完成后，脚本会等门户与 GTK 两条通道都对齐，再**补发一次同值通知**（把同一个全局主题再应用一次）。这一步是为 Chromium 系应用（Electron：Trae、VS Code、DSH Desktop 等）准备的：在 KDE 上这类应用会把一次 `color-scheme` 通知错后一代处理，表现是「启动后第一次切换不生效、之后再切就是反相」。补发一次通知可让它前进一代并与系统对齐；主题值不变，视觉上没有差异。可用 `--nudge=never` 或 `DARKLIGHT_NUDGE=0` 关掉。

## 功能

- 面板上一键切换，图标（太阳 / 月亮）实时反映当前模式；内置 Breeze symbolic 单色描边图标，风格与 KDE 面板统一，且随面板文字颜色自动反色。图标随项目分发，不依赖系统是否安装某个图标主题
- **优先读取系统设置里预设的深浅主题**（`DefaultDarkLookAndFeel` / `DefaultLightLookAndFeel`），不写死主题名；未设置时才按当前主题名推导配对作为回退
- 状态判断依次尝试 freedesktop portal 的 `color-scheme`、`kdeglobals` 里的配色方案名 / 全局主题名，最后回退到调色板亮度
- 每 30 秒同步一次状态，系统设置或定时任务改主题后图标仍保持正确
- 切换后等系统各通道对齐再补发一次同值通知，修 Chromium 系（Electron）应用「错后一代」的深浅不一致
- 没命中「系统设置里预设的那对深浅主题」时，弹一条带「打开外观设置」按钮的系统通知，说明本次用的是推断/兜底主题（每个会话最多一次）
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

darklight-toggle toggle --nudge=never   # 关闭切换后的补发通知（快约 1 秒）
```

可以在「系统设置 → 快捷键 → 自定义快捷键」中把 `darklight-toggle toggle` 绑定为全局快捷键。

补发相关参数（一般不用改）：

| 变量 | 默认 | 作用 |
| --- | --- | --- |
| `--nudge=always\|never` | `always` | 是否在切换后补发一次同值通知 |
| `DARKLIGHT_NUDGE` | `always` | 同 `--nudge`，`0` / `no` / `never` 表示关闭 |
| `DARKLIGHT_NUDGE_DELAY` | `0.6` | 对齐后到补发前的静默期（秒）；太短会读到旧值 |
| `DARKLIGHT_SETTLE_TIMEOUT` | `1.6` | 等待门户 / GTK 通道对齐的上限（秒） |
| `DARKLIGHT_DEBUG` | 未设置 | 设置后向 stderr 打印对齐与补发的耗时 |

## 验证

三层测试都要跑：

```bash
python3 tests/test_toggle.py                  # 模拟测试：脚本逻辑、主题配对、补发与开关
./tests/smoke_real.sh                         # 真机测试：真实切换，验证主题与 GTK 通道
./tests/electron_native_theme/run.sh          # 真机回归：Electron 应用的明暗是否跟随系统
```

- `smoke_real.sh` 在真实 Plasma 会话里执行 toggle，检查 `ColorScheme` 是否真的改变、两次切换方向是否相反、GTK 侧的 `prefer-dark` 是否在 3 秒内对齐，并验证 `--nudge=never` 时切换照常生效。模拟测试覆盖不到这些（系统命令的参数是否正确、调用是否真的生效）。脚本用 `trap` 保证无论成功失败都恢复你原来的主题。
- `electron_native_theme/run.sh` 启动一个隐藏窗口的 Electron 探针，连续切换 3 次并比对「应用判定的明暗」与「门户报告的明暗」，最后关闭补发做一次对照（只记录现象，不计失败）。它需要 node/npm，首次运行会联网把 electron 装到用户缓存目录；装不上会以 `[SKIP]` 退出。

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
│               ├── PresetNotice.qml       # 未命中预设时的系统通知（带打开设置按钮）
│               └── icons/                 # 内置 Breeze symbolic 单色图标（随项目分发）
│                   ├── sun.svg
│                   └── moon.svg
└── tests/
    ├── test_toggle.py                     # 模拟测试
    ├── smoke_real.sh                      # 真机往返冒烟测试（自动恢复原状）
    └── electron_native_theme/
        ├── main.js                        # Electron 明暗探针（隐藏窗口）
        └── run.sh                         # 真机回归：Electron 应用是否跟随系统
```

## 故障排查

- **点击后没有变化**：确认 `plasma-apply-lookandfeel --list` 能列出浅色和深色全局主题（注意是 `--list`，不是 `--list-themes`）。
- **提示找不到配对主题**：确认「系统设置 → 外观」里配置了浅色和深色全局主题（对应 `DefaultLightLookAndFeel` / `DefaultDarkLookAndFeel`）。只有未配置预设时才会按主题名称推导，此时需要一对名称里带 `dark`/`light` 或 `深色`/`浅色` 的主题。
- **图标状态不对**：状态判断依次尝试 portal 的明暗值、`kdeglobals` 里的配色方案名 / 全局主题名、调色板亮度；D-Bus 不可用时会自动走后面的回退。
- **GTK 应用颜色不同步**：本小部件只切换 Plasma 的全局主题，不负责 GTK 应用的配色。GTK 应用需另行在系统设置中配置 GTK 样式，或安装 `breeze-gtk-theme`。
- **Electron 应用（Trae、VS Code、DSH Desktop 等）切了但不一致**：这是 Chromium 系内核在 KDE 上读取系统明暗的老问题 —— 它把一次 `color-scheme` 通知错后一代处理，于是首次切换不生效、之后与系统反相，偶尔又多前进一代才对上。小部件默认用「对齐后补发一次同值通知」修掉它，所以请**不要**用 `--nudge=never` 长期运行。如果补发后仍偶发不一致，可用 `DARKLIGHT_DEBUG=1 darklight-toggle toggle` 看对齐与补发耗时，并适当调大 `DARKLIGHT_NUDGE_DELAY`（例如 `1.0`）。
- **弹出了「未配置深浅主题预设」通知**：说明当前主题不是从系统预设里那对主题取的，而是按名称推断或用了 Breeze 兜底，效果可能不是你想要的。点通知里的「打开外观设置」（或「系统设置 → 外观 → 全局主题」底部的浅色/深色下拉）指定一对主题后，通知就不再出现。通知依赖 Plasma 自带的 `org.kde.notification`，缺失时只会少这条提示，小部件照常工作。
- **Chromium 与应用的版本差异**：新版 Chromium（如 Chrome 158+）已能正确跟随；受影响的是 Electron 39 / 44（Chrome 142 / 152）这类稍旧的内核，应用侧升级后问题也会自然消失。
