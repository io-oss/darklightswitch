#!/usr/bin/env bash
# 真机往返冒烟测试：在真实 Plasma 会话中验证「切换确实改变了系统主题」。
# 模拟测试（test_toggle.py）只能验证脚本逻辑，验证不了 plasma-apply-lookandfeel
# 的参数是否正确、主题是否真的生效。此脚本补上这一环，并自动恢复原状。
set -euo pipefail

HELPER="${HOME}/.local/bin/darklight-toggle"
command -v kreadconfig6 >/dev/null 2>&1 || { echo "需要 kreadconfig6"; exit 1; }
command -v kwriteconfig6 >/dev/null 2>&1 || { echo "需要 kwriteconfig6"; exit 1; }
[[ -x "$HELPER" ]] || { echo "找不到 $HELPER，请先 ./install.sh"; exit 1; }

read_key() { kreadconfig6 --file kdeglobals --group "$1" --key "$2" 2>/dev/null || true; }
scheme() { read_key General ColorScheme; }
lookfeel() { read_key KDE LookAndFeelPackage; }

GTK_SETTINGS="$HOME/.config/gtk-3.0/settings.ini"
gtk_prefer_dark() {
    [[ -f "$GTK_SETTINGS" ]] || return 0
    awk -F= '/^gtk-application-prefer-dark-theme/ {gsub(/[ \t\r]/, "", $2); print $2}' "$GTK_SETTINGS" | tail -1
}

# 补发通知只在 GTK 通道对齐后发出，这里验证真实环境里它确实会在几秒内对齐。
check_gtk_settled() {
    local out="$1" want ok=0
    want="false"
    [[ "$out" == "dark" ]] && want="true"
    for _ in $(seq 1 30); do
        if [[ "$(gtk_prefer_dark)" == "$want" ]]; then ok=1; break; fi
        sleep 0.1
    done
    if [[ "$ok" -eq 1 ]]; then
        echo "[PASS] GTK 通道已在 3 秒内对齐（prefer-dark=$want）"
    else
        echo "[FAIL] GTK 通道未在 3 秒内对齐（期望 prefer-dark=$want，实际 $(gtk_prefer_dark)）"
        return 1
    fi
}

# 保存原状，任何退出路径都恢复。
ORIG_SCHEME="$(scheme)"
ORIG_LOOKFEEL="$(lookfeel)"
ORIG_HASH="$(read_key General ColorSchemeHash)"
restore() {
    kwriteconfig6 --file kdeglobals --group General --key ColorScheme "$ORIG_SCHEME" >/dev/null 2>&1 || true
    kwriteconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage "$ORIG_LOOKFEEL" >/dev/null 2>&1 || true
    if [[ -n "$ORIG_HASH" ]]; then
        kwriteconfig6 --file kdeglobals --group General --key ColorSchemeHash "$ORIG_HASH" >/dev/null 2>&1 || true
    fi
    echo "已恢复原状：$ORIG_LOOKFEEL / $ORIG_SCHEME"
}
trap restore EXIT

echo "原始状态：$ORIG_LOOKFEEL / $ORIG_SCHEME"
fail=0

# toggle 应让 ColorScheme 真正变化，并与脚本输出的新模式对应。
before="$(scheme)"
started="$(date +%s%N)"
out="$("$HELPER" toggle)"
elapsed_ms=$(( ($(date +%s%N) - started) / 1000000 ))
after="$(scheme)"
echo "toggle #1: 输出=$out, ColorScheme $before -> $after, 耗时 ${elapsed_ms}ms"
if [[ "$before" == "$after" ]]; then
    echo "[FAIL] toggle 后 ColorScheme 没有变化"; fail=1
elif [[ "$out" == "light" && "$after" != *"Light"* && "$after" != *"light"* ]]; then
    echo "[FAIL] 输出 light 但配色不是浅色"; fail=1
elif [[ "$out" == "dark" && "$after" != *"Dark"* && "$after" != *"dark"* ]]; then
    echo "[FAIL] 输出 dark 但配色不是深色"; fail=1
else
    echo "[PASS] 第一次切换生效"
fi

if ! check_gtk_settled "$out"; then fail=1; fi

# 再 toggle 一次必须切回另一种模式（防「点第二次还是深色」回归）。
before2="$(scheme)"
out2="$("$HELPER" toggle)"
after2="$(scheme)"
echo "toggle #2: 输出=$out2, ColorScheme $before2 -> $after2"
if [[ "$before2" == "$after2" ]]; then
    echo "[FAIL] 第二次 toggle 后 ColorScheme 没有变化"; fail=1
elif [[ "$out2" == "$out" ]]; then
    echo "[FAIL] 两次 toggle 输出相同，没有来回切换"; fail=1
else
    echo "[PASS] 第二次切换生效且方向相反"
fi

# 关闭补发（--nudge=never）时，切换本身仍必须照常生效。
before3="$(scheme)"
out3="$("$HELPER" toggle --nudge=never)"
after3="$(scheme)"
echo "toggle #3 (--nudge=never): 输出=$out3, ColorScheme $before3 -> $after3"
if [[ "$before3" == "$after3" ]]; then
    echo "[FAIL] --nudge=never 时切换没有生效"; fail=1
elif [[ "$out3" != "$out2" ]]; then
    echo "[PASS] --nudge=never 时切换照常生效"
else
    echo "[FAIL] --nudge=never 时方向不对"; fail=1
fi

exit "$fail"
