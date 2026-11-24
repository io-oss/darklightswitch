#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$SCRIPT_DIR/src/package"
PLASMOID_ID="io.github.io-oss.darklightswitch"
CLI_TARGET="$HOME/.local/bin/darklight-toggle"

fail() {
    printf '错误：%s\n' "$1" >&2
    exit 1
}

command -v python3 >/dev/null 2>&1 || fail "需要 python3"
command -v kpackagetool6 >/dev/null 2>&1 || fail "需要 kpackagetool6（Kubuntu 26.04 通常由 plasma-workspace 提供）"
[[ -f "$PACKAGE_DIR/metadata.json" ]] || fail "找不到小部件包：$PACKAGE_DIR"

chmod +x "$PACKAGE_DIR/contents/code/darklight-toggle"

installed=0
if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -Fxq "$PLASMOID_ID"; then
    installed=1
elif [[ -d "$HOME/.local/share/plasma/plasmoids/$PLASMOID_ID" ]]; then
    installed=1
fi

if [[ "$installed" -eq 1 ]]; then
    echo "检测到已安装，先移除旧版本再安装（避免残留旧的配置文件）..."
    kpackagetool6 --type Plasma/Applet --remove "$PLASMOID_ID" >/dev/null 2>&1 || true
fi
echo "正在安装小部件..."
kpackagetool6 --type Plasma/Applet --install "$PACKAGE_DIR"

mkdir -p "$HOME/.local/bin"
install -m 755 "$PACKAGE_DIR/contents/code/darklight-toggle" "$CLI_TARGET"

echo
echo "安装完成。"
echo "1. 在面板空白处右键 → 添加小部件 → 搜索「深浅模式切换」，拖到面板上。"
echo "2. 左键点击小部件图标即可切换；主题由系统设置中配置的深浅色主题决定。"
echo "3. 命令行也可使用：$CLI_TARGET toggle"
echo "如果小部件没有立即出现，可运行：plasmashell --replace（或注销后重新登录）。"
