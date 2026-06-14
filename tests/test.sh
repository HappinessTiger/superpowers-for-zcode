#!/usr/bin/env bash
# Superpowers for ZCode 测试脚本（macOS/Linux）
# 在隔离的临时 HOME 里跑 T1/T2/T6/T7/T8。需要联网。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO_ROOT/install.sh"
UNINSTALL="$REPO_ROOT/uninstall.sh"

PASS=0
FAIL=0
FAILED_TESTS=()

new_test_home() {
    local h
    h="$(mktemp -d "${TMPDIR:-/tmp}/sp4z-test-XXXXXX")"
    echo "$h"
}

# 在临时 HOME 里跑脚本，返回退出码
invoke_in_home() {
    local home="$1"; shift
    local script="$1"; shift
    HOME="$home" USERPROFILE="$home" bash "$script" "$@" >/tmp/sp4z-out.$$ 2>&1
    local code=$?
    cat /tmp/sp4z-out.$$
    rm -f /tmp/sp4z-out.$$
    return $code
}

assert_true() {
    local name="$1"; shift
    local cond="$1"; shift
    local detail="${1:-}"
    if [[ "$cond" == "1" || "$cond" == "true" ]]; then
        printf '  [PASS] %s\n' "$name"
        PASS=$((PASS+1))
    else
        printf '  [FAIL] %s %s\n' "$name" "$detail" >&2
        FAIL=$((FAIL+1))
        FAILED_TESTS+=("$name")
    fi
}

# ===== T8: 未安装时卸载 =====
printf '\n\033[36m=== T8: 未安装时卸载 ===\033[0m\n'
H="$(new_test_home)"
invoke_in_home "$H" "$UNINSTALL"
CODE=$?
assert_true "退出码 0" "$([[ $CODE -eq 0 ]] && echo 1 || echo 0)" "实际: $CODE"
assert_true "无副作用" "$([[ ! -d "$H/.agents" ]] && echo 1 || echo 0)"
rm -rf "$H"

# ===== T1: 干净环境安装 =====
printf '\n\033[36m=== T1: 干净环境安装 ===\033[0m\n'
H="$(new_test_home)"
invoke_in_home "$H" "$INSTALL"
CODE=$?
SKILLS_DIR="$H/.agents/skills"
AGENTS_MD="$H/AGENTS.md"
MANIFEST="$H/.agents/.superpowers-for-zcode.manifest.json"
assert_true "退出码 0" "$([[ $CODE -eq 0 ]] && echo 1 || echo 0)" "实际: $CODE"
SKILL_COUNT=0
[[ -d "$SKILLS_DIR" ]] && SKILL_COUNT=$(find "$SKILLS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
assert_true "skills 目录有技能（>10）" "$([[ $SKILL_COUNT -gt 10 ]] && echo 1 || echo 0)" "实际: $SKILL_COUNT"
assert_true "AGENTS.md 已生成" "$([[ -f "$AGENTS_MD" ]] && echo 1 || echo 0)"
assert_true "manifest 已生成" "$([[ -f "$MANIFEST" ]] && echo 1 || echo 0)"

# ===== T2: 重复安装被拦截 =====
printf '\n\033[36m=== T2: 重复安装被拦截 ===\033[0m\n'
invoke_in_home "$H" "$INSTALL"
CODE=$?
assert_true "退出码 3" "$([[ $CODE -eq 3 ]] && echo 1 || echo 0)" "实际: $CODE"

# ===== T6: 干净卸载 =====
printf '\n\033[36m=== T6: 干净卸载 ===\033[0m\n'
invoke_in_home "$H" "$UNINSTALL"
CODE=$?
AFTER=0
[[ -d "$SKILLS_DIR" ]] && AFTER=$(find "$SKILLS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
assert_true "退出码 0" "$([[ $CODE -eq 0 ]] && echo 1 || echo 0)" "实际: $CODE"
assert_true "skills 已清空" "$([[ $AFTER -eq 0 ]] && echo 1 || echo 0)" "剩余: $AFTER"
assert_true "AGENTS.md 已删除" "$([[ ! -f "$AGENTS_MD" ]] && echo 1 || echo 0)"
assert_true "manifest 已删除" "$([[ ! -f "$MANIFEST" ]] && echo 1 || echo 0)"
rm -rf "$H"

# ===== T7: AGENTS.md 被改过 + force 卸载 =====
printf '\n\033[36m=== T7: AGENTS.md 被改过 + force 卸载 ===\033[0m\n'
H="$(new_test_home)"
invoke_in_home "$H" "$INSTALL"
CODE=$?
if [[ $CODE -ne 0 ]]; then
    printf '  \033[33m[SKIP] T7 依赖 T1 成功\033[0m\n'
else
    [[ -f "$H/AGENTS.md" ]] && printf '\n# 用户手改的内容\n' >> "$H/AGENTS.md"
    invoke_in_home "$H" "$UNINSTALL" --force
    CODE=$?
    assert_true "force 卸载退出码 0" "$([[ $CODE -eq 0 ]] && echo 1 || echo 0)" "实际: $CODE"
    assert_true "AGENTS.md 被强删" "$([[ ! -f "$H/AGENTS.md" ]] && echo 1 || echo 0)"
fi
rm -rf "$H"

# ===== 汇总 =====
printf '\n\033[36m================================\033[0m\n'
printf 'PASS: %s  FAIL: %s\n' "$PASS" "$FAIL"
if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
    printf 'Failed: %s\n' "${FAILED_TESTS[*]}"
fi
printf '\033[36m================================\033[0m\n\n'

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
