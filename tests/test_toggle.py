#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用临时配置和模拟命令测试 darklight-toggle 的核心逻辑。"""

from __future__ import annotations

import configparser
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "src" / "package" / "contents" / "code" / "darklight-toggle"

FAKE_LOOKANDFEEL = '''#!/usr/bin/env python3
import configparser
import os
import sys
from pathlib import Path

configdir = Path(os.environ["XDG_CONFIG_HOME"])
calls_log = configdir / "apply-calls.log"

args = sys.argv[1:]
if args and args[0] in ("--list", "-l"):
    if os.environ.get("FAKE_LIST_EMPTY") == "1":
        sys.exit(0)
    print("自定义 浅色")
    print("自定义 深色")
    print("org.kde.breeze.desktop")
    print("org.kde.breezedark.desktop")
    sys.exit(0)

if len(args) == 2 and args[0] == "--apply":
    theme = args[1]
    previous = 0
    if calls_log.exists():
        previous = len([line for line in calls_log.read_text(encoding="utf-8").splitlines() if line.strip()])
    with calls_log.open("a", encoding="utf-8") as handle:
        handle.write(theme + "\\n")

    # 模拟「补发那一次失败」：由测试指定第几次调用失败（1 基）。
    fail_at = os.environ.get("FAKE_FAIL_CALL_INDEX", "")
    if fail_at.isdigit() and previous + 1 == int(fail_at):
        print("模拟第 %s 次应用失败" % fail_at, file=sys.stderr)
        sys.exit(3)

    path = configdir / "kdeglobals"
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    if path.exists():
        parser.read(path)
    for section in ("KDE", "General"):
        if not parser.has_section(section):
            parser.add_section(section)
    parser.set("KDE", "LookAndFeelPackage", theme)
    dark = "dark" in theme.lower() or "深色" in theme
    scheme = "BreezeDark" if dark else "BreezeLight"
    parser.set("General", "ColorScheme", scheme)
    with path.open("w", encoding="utf-8") as handle:
        parser.write(handle)

    # 模拟 kde-gtk-config 的 GTK 通道：1 = 跟随目标，stuck = 永远停在浅色。
    sync = os.environ.get("FAKE_GTK_SYNC", "")
    if sync:
        gtkdir = configdir / "gtk-3.0"
        gtkdir.mkdir(parents=True, exist_ok=True)
        prefer = dark if sync == "1" else False
        (gtkdir / "settings.ini").write_text(
            "[Settings]\\ngtk-application-prefer-dark-theme=%s\\n" % ("true" if prefer else "false"),
            encoding="utf-8",
        )
    print("ok")
    sys.exit(0)

print("unexpected arguments: " + repr(args), file=sys.stderr)
sys.exit(2)
'''

FAKE_DBUS = '''#!/bin/sh
# 默认模拟 D-Bus 不可用，让脚本回退到 kdeglobals 判断；
# 设置 FAKE_PORTAL=1/2 可模拟门户报告深色/浅色。
if [ -n "${FAKE_PORTAL:-}" ]; then
    printf '   variant       uint32 %s\\n' "$FAKE_PORTAL"
    exit 0
fi
exit 1
'''


def run(env: dict[str, str], *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(HELPER), *args],
        env=env,
        capture_output=True,
        text=True,
        timeout=20,
    )


def read_theme(configdir: Path) -> str:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str.lower
    parser.read(configdir / "kdeglobals", encoding="utf-8")
    return parser.get("KDE", "lookandfeelpackage", fallback="")


def read_calls(configdir: Path) -> list[str]:
    path = configdir / "apply-calls.log"
    if not path.exists():
        return []
    return [line for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write_state(
    configdir: Path,
    theme: str,
    scheme: str,
    preset_dark: str = "",
    preset_light: str = "",
) -> None:
    lines = ["[KDE]", f"LookAndFeelPackage={theme}"]
    if preset_dark:
        lines.append(f"DefaultDarkLookAndFeel={preset_dark}")
    if preset_light:
        lines.append(f"DefaultLightLookAndFeel={preset_light}")
    lines.extend(["", "[General]", f"ColorScheme={scheme}", ""])
    (configdir / "kdeglobals").write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    with tempfile.TemporaryDirectory() as temporary:
        base = Path(temporary)
        bindir = base / "bin"
        configdir = base / "config"
        datadir = base / "data"
        for directory in (bindir, configdir, datadir):
            directory.mkdir()

        for name, content in (
            ("plasma-apply-lookandfeel", FAKE_LOOKANDFEEL),
            ("dbus-send", FAKE_DBUS),
        ):
            path = bindir / name
            path.write_text(content, encoding="utf-8")
            path.chmod(0o755)

        env = os.environ.copy()
        env.update(
            {
                "XDG_CONFIG_HOME": str(configdir),
                "XDG_DATA_HOME": str(datadir),
                "XDG_DATA_DIRS": "",
                "PATH": str(bindir) + os.pathsep + env.get("PATH", ""),
            }
        )

        checks: list[tuple[str, bool, subprocess.CompletedProcess[str] | None]] = []

        # 场景一：系统自带 Breeze 主题配对
        write_state(configdir, "org.kde.breeze.desktop", "BreezeLight")
        result = run(env, "status")
        checks.append(("初始状态应为 light", result.stdout.strip() == "light", result))

        result = run(env, "toggle")
        checks.append(("toggle 应切到 dark", result.stdout.strip() == "dark", result))
        checks.append(
            (
                "应应用系统深色全局主题",
                read_theme(configdir) == "org.kde.breezedark.desktop",
                result,
            )
        )

        result = run(env, "status")
        checks.append(("切换后状态应为 dark", result.stdout.strip() == "dark", result))

        result = run(env, "toggle")
        checks.append(("再次 toggle 应回到 light", result.stdout.strip() == "light", result))
        checks.append(
            (
                "应恢复系统浅色全局主题",
                read_theme(configdir) == "org.kde.breeze.desktop",
                result,
            )
        )

        # 场景二：用户自建中文主题配对（本机实际场景）
        write_state(configdir, "自定义 浅色", "BreezeLight")
        result = run(env, "toggle")
        checks.append(("中文主题 toggle 应切到 dark", result.stdout.strip() == "dark", result))
        checks.append(
            (
                "应应用用户自建的深色主题",
                read_theme(configdir) == "自定义 深色",
                result,
            )
        )

        result = run(env, "toggle")
        checks.append(("中文主题再次 toggle 应回到 light", result.stdout.strip() == "light", result))
        checks.append(
            (
                "应恢复用户自建的浅色主题",
                read_theme(configdir) == "自定义 浅色",
                result,
            )
        )

        # 场景三：存在系统预设时，必须用预设主题，而不是按名称推导。
        # 当前主题是 Breeze，按名称推导 dark 会得到 org.kde.breezedark.desktop；
        # 但预设指向「自定义 深色」，应优先采用预设值。
        write_state(
            configdir,
            "org.kde.breeze.desktop",
            "BreezeLight",
            preset_dark="自定义 深色",
            preset_light="自定义 浅色",
        )
        result = run(env, "toggle")
        checks.append(("有预设时 toggle 应切到 dark", result.stdout.strip() == "dark", result))
        checks.append(
            (
                "应优先应用预设的深色主题，而非按名称推导",
                read_theme(configdir) == "自定义 深色",
                result,
            )
        )

        result = run(env, "toggle")
        checks.append(("有预设时再次 toggle 应回到 light", result.stdout.strip() == "light", result))
        checks.append(
            (
                "应优先应用预设的浅色主题，而非按名称推导",
                read_theme(configdir) == "自定义 浅色",
                result,
            )
        )

        result = run(env, "dark")
        checks.append(("显式 dark 子命令", result.stdout.strip() == "dark", result))
        result = run(env, "light")
        checks.append(("显式 light 子命令", result.stdout.strip() == "light", result))

        # 场景四：默认切换后补发一次同值通知（修 Chromium/Electron 系错后一代）。
        write_state(configdir, "自定义 浅色", "BreezeLight")
        calls_before = len(read_calls(configdir))
        result = run(env, "light")
        calls = read_calls(configdir)[calls_before:]
        checks.append(
            ("默认切换应补发一次同值通知", calls == ["自定义 浅色", "自定义 浅色"], result)
        )

        # 场景五：--nudge=never 只应用一次。
        calls_before = len(read_calls(configdir))
        result = run(env, "dark", "--nudge=never")
        calls = read_calls(configdir)[calls_before:]
        checks.append(("--nudge=never 应只应用一次", calls == ["自定义 深色"], result))

        # 场景六：DARKLIGHT_NUDGE=0 同样只应用一次。
        env_no_nudge = dict(env, DARKLIGHT_NUDGE="0")
        calls_before = len(read_calls(configdir))
        result = run(env_no_nudge, "light")
        calls = read_calls(configdir)[calls_before:]
        checks.append(("DARKLIGHT_NUDGE=0 应只应用一次", calls == ["自定义 浅色"], result))

        # 场景七：补发失败不影响切换结果（主题已生效，只降级为警告）。
        calls_before = len(read_calls(configdir))
        env_fail = dict(env, FAKE_FAIL_CALL_INDEX=str(calls_before + 2))
        result = run(env_fail, "dark")
        checks.append(
            (
                "补发失败仍应成功退出并输出 dark",
                result.returncode == 0 and result.stdout.strip() == "dark",
                result,
            )
        )
        checks.append(("补发失败应给出警告", "补发通知失败" in result.stderr, result))
        checks.append(("补发失败后主题仍已应用", read_theme(configdir) == "自定义 深色", result))

        # 场景八：GTK 通道很快对齐时，应正常补发且不告警、不空等。
        env_gtk = dict(env, FAKE_GTK_SYNC="1", DARKLIGHT_SETTLE_TIMEOUT="0.3", DARKLIGHT_NUDGE_DELAY="0.05")
        started = time.monotonic()
        result = run(env_gtk, "light")
        elapsed = time.monotonic() - started
        checks.append(
            (
                "GTK 已同步时补发成功且无警告",
                result.returncode == 0 and "警告" not in result.stderr,
                result,
            )
        )
        checks.append(("GTK 已同步后不应空等", elapsed < 2.0, result))

        # 场景九：GTK 一直不同步时，超时后仍要补发并告警，不能无限等待。
        env_stuck = dict(env, FAKE_GTK_SYNC="stuck", DARKLIGHT_SETTLE_TIMEOUT="0.3", DARKLIGHT_NUDGE_DELAY="0.05")
        started = time.monotonic()
        result = run(env_stuck, "dark")
        elapsed = time.monotonic() - started
        checks.append(
            (
                "GTK 不同步时应超时后继续补发",
                result.returncode == 0 and result.stdout.strip() == "dark",
                result,
            )
        )
        checks.append(("GTK 不同步时应给出超时警告", "未在超时内同步" in result.stderr, result))
        checks.append(("GTK 不同步时应快速返回", elapsed < 3.0, result))

        # 场景十：补发前的静默期可配置，且确实生效（紧接第一批通知补发会读到旧值）。
        env_delay = dict(env, DARKLIGHT_SETTLE_TIMEOUT="0.05", DARKLIGHT_NUDGE_DELAY="0.4")
        started = time.monotonic()
        result = run(env_delay, "light")
        elapsed = time.monotonic() - started
        checks.append(("补发前应等待配置的静默期", elapsed >= 0.4, result))

        # 场景十一：门户值滞后（切换刚结束时门户可能还停在上一代）。
        # toggle 的方向必须以配置为准，否则会「点了等于没点」。
        write_state(configdir, "自定义 浅色", "BreezeLight")
        env_stale = dict(env, FAKE_PORTAL="1", DARKLIGHT_NUDGE_DELAY="0")
        calls_before = len(read_calls(configdir))
        result = run(env_stale, "toggle")
        calls = read_calls(configdir)[calls_before:]
        checks.append(
            (
                "门户滞后时 toggle 仍按配置切到深色",
                result.stdout.strip() == "dark" and calls[:1] == ["自定义 深色"],
                result,
            )
        )

        # 场景十二：未命中预设时要提示用户（按名称推断）。
        write_state(configdir, "自定义 浅色", "BreezeLight")
        result = run(env, "light", "--nudge=never")
        checks.append(
            (
                "未配置预设想推断时应提示",
                "未配置深浅主题预设" in result.stderr and "按名称推断" in result.stderr,
                result,
            )
        )
        checks.append(("提示里应带上实际主题名", "自定义 浅色" in result.stderr, result))
        checks.append(("提示不应影响正常输出", result.stdout.strip() == "light", result))

        # 命中预设时不应打扰用户。
        write_state(
            configdir,
            "自定义 浅色",
            "BreezeLight",
            preset_dark="自定义 深色",
            preset_light="自定义 浅色",
        )
        result = run(env, "light", "--nudge=never")
        checks.append(("命中预设时不应提示", "未配置深浅主题预设" not in result.stderr, result))

        # 一个可用主题都没有时走兜底默认，同样要提示。
        env_empty = dict(env, FAKE_LIST_EMPTY="1")
        write_state(configdir, "自定义 浅色", "BreezeLight")
        result = run(env_empty, "dark", "--nudge=never")
        checks.append(("无可用主题时应提示走兜底", "使用兜底默认" in result.stderr, result))

        # status 只读状态，不应该弹提示。
        result = run(env, "status")
        checks.append(("status 不应输出提示", "未配置深浅主题预设" not in result.stderr, result))

        # 状态显示仍以门户为准（应用实际看到的值）。
        result = run(env_stale, "status")
        checks.append(("status 仍优先采用门户值", result.stdout.strip() == "dark", result))

        config_files = [
            ROOT / "src" / "package" / "contents" / "config" / "config.qml",
            ROOT / "src" / "package" / "contents" / "config" / "main.xml",
            ROOT / "src" / "package" / "contents" / "ui" / "configGeneral.qml",
        ]
        checks.append(
            (
                "小部件内不应存在主题配置界面",
                not any(path.exists() for path in config_files),
                None,
            )
        )

        failed = False
        for label, passed, result in checks:
            print(f"[{'PASS' if passed else 'FAIL'}] {label}")
            if not passed:
                failed = True
                if result is not None:
                    print(f"  stdout={result.stdout!r} stderr={result.stderr!r} code={result.returncode}")

        return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
