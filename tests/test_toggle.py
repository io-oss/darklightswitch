#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用临时配置和模拟命令测试 darklight-toggle 的核心逻辑。"""

from __future__ import annotations

import configparser
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "src" / "package" / "contents" / "code" / "darklight-toggle"

FAKE_LOOKANDFEEL = '''#!/usr/bin/env python3
import configparser
import os
import sys
from pathlib import Path

args = sys.argv[1:]
if args and args[0] in ("--list", "-l"):
    print("自定义 浅色")
    print("自定义 深色")
    print("org.kde.breeze.desktop")
    print("org.kde.breezedark.desktop")
    sys.exit(0)

if len(args) == 2 and args[0] == "--apply":
    theme = args[1]
    path = Path(os.environ["XDG_CONFIG_HOME"]) / "kdeglobals"
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    if path.exists():
        parser.read(path)
    for section in ("KDE", "General"):
        if not parser.has_section(section):
            parser.add_section(section)
    parser.set("KDE", "LookAndFeelPackage", theme)
    scheme = "BreezeDark" if ("dark" in theme.lower() or "深色" in theme) else "BreezeLight"
    parser.set("General", "ColorScheme", scheme)
    with path.open("w", encoding="utf-8") as handle:
        parser.write(handle)
    print("ok")
    sys.exit(0)

print("unexpected arguments: " + repr(args), file=sys.stderr)
sys.exit(2)
'''

FAKE_DBUS = '''#!/bin/sh
# 测试环境中模拟 D-Bus 不可用，让脚本回退到 kdeglobals 判断。
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
