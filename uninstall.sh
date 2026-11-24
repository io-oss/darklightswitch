#!/usr/bin/env bash
set -euo pipefail

PLASMOID_ID="io.github.io-oss.darklightswitch"
CLI_TARGET="$HOME/.local/bin/darklight-toggle"

if command -v kpackagetool6 >/dev/null 2>&1; then
    if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -Fxq "$PLASMOID_ID"; then
        echo "正在移除小部件..."
        kpackagetool6 --type Plasma/Applet --remove "$PLASMOID_ID"
    fi
fi

if [[ -f "$CLI_TARGET" ]]; then
    echo "正在移除命令行脚本：$CLI_TARGET"
    rm -f "$CLI_TARGET"
fi

echo "卸载完成。若面板上仍有残留图标，右键将其移除即可。"
