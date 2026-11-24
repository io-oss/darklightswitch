#!/usr/bin/env bash
# 真机回归：验证「补发通知」能让 Chromium 系（Electron）应用与系统明暗保持一致。
#
# 背景：KDE 上 Electron 应用（VS Code / Trae / DSH Desktop 等）的 nativeTheme
# 会把一次切换的通知错后一代处理，表现为首次切换不生效、之后反相。
# 本测试启动一个隐藏窗口的 Electron 探针，连续切换并比对「应用判定的明暗」
# 与「门户报告的明暗」；随后关闭补发做一次对照，仅记录现象、不计失败。
#
# 依赖：node/npm（首次运行会联网安装 electron 到用户缓存目录）、Plasma 会话。
# 会真实切换你的主题若干次，结束时自动恢复原状。
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
HELPER="$ROOT/src/package/contents/code/darklight-toggle"

skip() { echo "[SKIP] $1"; exit 0; }

command -v node >/dev/null 2>&1 || skip "未安装 node"
command -v npm >/dev/null 2>&1 || skip "未安装 npm"
command -v plasma-apply-lookandfeel >/dev/null 2>&1 || skip "不在 Plasma 会话中（缺少 plasma-apply-lookandfeel）"
[[ -x "$HELPER" ]] || skip "找不到可执行的 $HELPER"

WORK="${XDG_CACHE_HOME:-$HOME/.cache}/darklightswitch/electron-probe"
mkdir -p "$WORK"
ELECTRON_BIN="$WORK/node_modules/electron/dist/electron"

download_electron() {
    [[ -f "$WORK/package.json" ]] || printf '{"name":"darklight-probe","private":true,"version":"0.0.0"}\n' > "$WORK/package.json"
    (
        cd "$WORK" || exit 1
        ELECTRON_MIRROR="${ELECTRON_MIRROR:-https://npmmirror.com/mirrors/electron/}" \
            npm install electron@44 --no-audit --no-fund --loglevel=error
    )
}

if [[ ! -x "$ELECTRON_BIN" ]]; then
    echo "首次运行：安装 electron 到 $WORK（需要网络）..."
    download_electron || skip "无法安装 electron（无网络或镜像不可用）"
    if [[ ! -x "$ELECTRON_BIN" ]]; then
        ( cd "$WORK" && ELECTRON_MIRROR="${ELECTRON_MIRROR:-https://npmmirror.com/mirrors/electron/}" node node_modules/electron/install.js ) \
            || skip "electron 二进制下载失败"
    fi
fi
[[ -x "$ELECTRON_BIN" ]] || skip "electron 二进制缺失：$ELECTRON_BIN"

LOG="$WORK/probe.log"
: > "$LOG"
PROBE_PID=""
# 按配置里的主题名恢复，而不是按门户值：门户在切换刚结束时可能还是上一代，
# 用它会恢复成错误的那一个模式。
ORIG_THEME="$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage 2>/dev/null || true)"

cleanup() {
    if [[ -n "$PROBE_PID" ]] && kill -0 "$PROBE_PID" 2>/dev/null; then
        kill "$PROBE_PID" 2>/dev/null
        wait "$PROBE_PID" 2>/dev/null
    fi
    if [[ -n "$ORIG_THEME" ]]; then
        plasma-apply-lookandfeel --apply "$ORIG_THEME" >/dev/null 2>&1 || true
        echo "已恢复原状：$ORIG_THEME"
    fi
}
trap cleanup EXIT

"$ELECTRON_BIN" "$HERE/main.js" --no-sandbox >>"$LOG" 2>&1 &
PROBE_PID=$!
for _ in $(seq 1 60); do
    grep -q ' READY ' "$LOG" && break
    kill -0 "$PROBE_PID" 2>/dev/null || skip "electron 启动失败，日志见 $LOG"
    sleep 0.25
done
grep -q ' READY ' "$LOG" || skip "electron 探针未在 15 秒内就绪，日志见 $LOG"

last_state() {
    grep -E '^[0-9]+ STATE (dark|light)$' "$LOG" | tail -1 | awk '{print $3}'
}

compare_once() {
    local label="$1" app portal
    sleep 2
    portal="$("$HELPER" status)"
    app="$(last_state)"
    if [[ "$app" == "$portal" ]]; then
        echo "[PASS] $label：应用=$app 系统=$portal"
        return 0
    fi
    echo "[FAIL] $label：应用=$app 系统=$portal"
    return 1
}

echo "探针：$(grep -m1 ' READY ' "$LOG" | sed 's/^[0-9]* //')"
echo "当前系统模式：$("$HELPER" status)（原始主题：${ORIG_THEME:-未读取到}）"
fail=0

for i in 1 2 3; do
    if ! out="$("$HELPER" toggle)"; then
        echo "[FAIL] 第 $i 次切换命令失败"
        fail=1
        continue
    fi
    compare_once "补发通知 第 $i 次（系统切到 $out）" || fail=1
done

# 对照：关闭补发时的现象，仅作记录。
"$HELPER" toggle --nudge=never >/dev/null 2>&1
sleep 2
portal="$("$HELPER" status)"
app="$(last_state)"
if [[ "$app" == "$portal" ]]; then
    echo "[INFO] --nudge=never 时也一致（应用=$app 系统=$portal）"
else
    echo "[INFO] --nudge=never 时不一致（应用=$app 系统=$portal）——内核错后一代的现象"
fi

exit "$fail"
