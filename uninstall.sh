#!/usr/bin/env bash
# Superpowers for ZCode uninstaller (macOS/Linux)
# Usage: ./uninstall.sh [--force]

set -euo pipefail

MANIFEST_PATH="$HOME/.agents/.superpowers-for-zcode.manifest.json"
SKILLS_DIR="$HOME/.agents/skills"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

info()  { printf '[INFO]  %s\n' "$1"; }
ok()    { printf '[OK]    %s\n' "$1"; }
warn()  { printf '[WARN]  %s\n' "$1"; }
err()   { printf '[ERROR] %s\n' "$1" >&2; }

file_sha256() {
    if command -v shasum &>/dev/null; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

# ===== 阶段 0：定位 manifest =====
info "阶段 0/2：定位 manifest"
if [[ ! -f "$MANIFEST_PATH" ]]; then
    info "未检测到安装记录，无需卸载。"
    exit 0
fi

if ! manifest_json=$(cat "$MANIFEST_PATH" 2>/dev/null); then
    err "manifest 文件读取失败：$MANIFEST_PATH"
    exit 6
fi

# 用 python3 解析 JSON（macOS/Linux 普遍有）
if ! command -v python3 &>/dev/null; then
    err "需要 python3 来解析 manifest。请安装 python3 或手动删除：$MANIFEST_PATH"
    exit 6
fi

read_manifest_field() {
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2],''))" "$MANIFEST_PATH" "$1"
}

UPSTREAM_VER="$(read_manifest_field upstreamVersion)"
AGENTS_MD_PATH="$(read_manifest_field agentsMdPath)"
AGENTS_MD_HASH="$(read_manifest_field agentsMdSha256)"
INSTALLED_SKILLS_STR="$(python3 -c "import json; d=json.load(open('$MANIFEST_PATH')); print('\n'.join(d.get('installedSkills',[])))" 2>/dev/null || echo "")"

ok "已加载 manifest（上游版本：$UPSTREAM_VER）"

# ===== 阶段 1：删除 skills =====
info "阶段 1/2：删除 skills"
deleted=0
skipped=0
while IFS= read -r skill_name; do
    [[ -z "$skill_name" ]] && continue
    skill_path="$SKILLS_DIR/$skill_name"
    if [[ -d "$skill_path" ]]; then
        if rm -rf "$skill_path" 2>/dev/null; then
            deleted=$((deleted+1))
            info "已删除：$skill_name"
        else
            warn "删除失败：$skill_name"
        fi
    else
        skipped=$((skipped+1))
        warn "不存在，跳过：$skill_name"
    fi
done <<< "$INSTALLED_SKILLS_STR"
ok "已删除 $deleted 个，跳过 $skipped 个"

# ===== 阶段 2：处理 AGENTS.md =====
info "阶段 2/2：处理 AGENTS.md"
agents_md_deleted=0
if [[ -n "$AGENTS_MD_PATH" && -f "$AGENTS_MD_PATH" ]]; then
    current_hash="$(file_sha256 "$AGENTS_MD_PATH")"
    if [[ "$current_hash" == "$AGENTS_MD_HASH" ]]; then
        rm -f "$AGENTS_MD_PATH"
        agents_md_deleted=1
        ok "AGENTS.md 已删除（未被修改过）"
    else
        warn "AGENTS.md 已被修改（hash 不匹配）"
        if [[ $FORCE -eq 1 ]]; then
            rm -f "$AGENTS_MD_PATH"
            agents_md_deleted=1
            ok "因 --force 已强制删除 AGENTS.md"
        else
            read -p "是否强制删除已修改的 AGENTS.md？[y/N] " answer
            if [[ "$answer" =~ ^[yY] ]]; then
                rm -f "$AGENTS_MD_PATH"
                agents_md_deleted=1
                ok "已强制删除 AGENTS.md"
            else
                warn "保留 AGENTS.md（用户选择不删除）"
            fi
        fi
    fi
else
    warn "AGENTS.md 不存在，跳过"
fi

rm -f "$MANIFEST_PATH"
ok "manifest 已删除"

echo ""
echo "✅ Superpowers for ZCode 已卸载。"
echo ""
echo "   已删除 $deleted 个技能。"
if [[ $agents_md_deleted -eq 1 ]]; then
    echo "   AGENTS.md：已删除"
else
    echo "   AGENTS.md：已保留（用户修改过）"
fi
echo "   manifest：已删除"
echo ""
echo "👉 重启 ZCode 使变更生效。"
exit 0
