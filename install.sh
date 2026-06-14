#!/usr/bin/env bash
# Superpowers for ZCode installer (macOS/Linux)
# Usage: ./install.sh

set -euo pipefail

# ===== 常量 =====
TOOL_VERSION="1.0.0"
UPSTREAM_URL="https://github.com/obra/superpowers"
UPSTREAM_REPO="obra/superpowers"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.agents/skills"
AGENTS_DIR="$HOME/.agents"
MANIFEST_PATH="$AGENTS_DIR/.superpowers-for-zcode.manifest.json"
TEMPLATE_PATH="$SCRIPT_DIR/templates/AGENTS.md.template"
VERSION_FILE="$SCRIPT_DIR/VERSION"

# AGENTS.md 落地路径：环境变量 > 默认
AGENTS_MD_PATH="${SP4Z_AGENTS_MD_PATH:-$HOME/AGENTS.md}"

# ===== 工具函数 =====
info()  { printf '[INFO]  %s\n' "$1"; }
ok()    { printf '[OK]    %s\n' "$1"; }
warn()  { printf '[WARN]  %s\n' "$1"; }
err()   { printf '[ERROR] %s\n' "$1" >&2; }

cleanup_temp() {
    if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR:-}" ]]; then
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
}

rollback_copied_skills() {
    for name in "${COPIED_SKILLS[@]:-}"; do
        [[ -z "$name" ]] && continue
        rm -rf "$SKILLS_DIR/$name" 2>/dev/null || true
    done
}

iso_timestamp() {
    date +"%Y-%m-%dT%H:%M:%S%z"
}

file_sha256() {
    if command -v shasum &>/dev/null; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

# 解析 SKILL.md frontmatter 的 name 字段
parse_skill_name() {
    local f="$1"
    awk '/^---$/{n++; next} n==1 && /^name:/{gsub(/^name:[[:space:]]*/,""); gsub(/["\047]/,""); print; exit}' "$f"
}
parse_skill_desc() {
    local f="$1"
    awk '/^---$/{n++; next} n==1 && /^description:/{gsub(/^description:[[:space:]]*/,""); gsub(/["\047]/,""); print; exit}' "$f"
}

# ===== 阶段 0：前置检查 =====
info "阶段 0/5：前置检查"

if ! command -v git &>/dev/null; then
    err "未检测到 git，请先安装 git。"
    exit 1
fi

if [[ -f "$MANIFEST_PATH" ]]; then
    err "已检测到安装记录 ($MANIFEST_PATH)。请先运行 ./uninstall.sh 卸载后再安装。"
    exit 3
fi
ok "前置检查通过"

# ===== 阶段 1：准备目录 =====
info "阶段 1/5：准备目标目录"
mkdir -p "$SKILLS_DIR"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/superpowers-install-XXXXXX")"
info "临时目录：$TEMP_DIR"

# ===== 阶段 2：clone =====
info "阶段 2/5：clone 上游"
VERSION_TAG="$(tr -d '[:space:]' < "$VERSION_FILE")"
info "目标版本：$VERSION_TAG"

CLONE_TARGET="$TEMP_DIR/superpowers"
if ! git clone --depth 1 --branch "$VERSION_TAG" "$UPSTREAM_URL" "$CLONE_TARGET" >/dev/null 2>&1; then
    cleanup_temp
    err "git clone 失败。请检查网络，或确认 tag '$VERSION_TAG' 是否存在。"
    exit 2
fi

CLONED_SKILLS_DIR="$CLONE_TARGET/skills"
if [[ ! -d "$CLONED_SKILLS_DIR" ]] || [[ -z "$(ls -A "$CLONED_SKILLS_DIR" 2>/dev/null)" ]]; then
    cleanup_temp
    err "clone 成功但 skills 目录为空或不存在。"
    exit 4
fi
SKILL_DIRS=( "$CLONED_SKILLS_DIR"/*/ )
ok "clone 完成"

# ===== 阶段 3：复制 skills =====
info "阶段 3/5：复制 skills"
COPIED_SKILLS=()
INSTALLED_SKILLS=()

for d in "${SKILL_DIRS[@]}"; do
    [[ ! -d "$d" ]] && continue
    skill_name="$(basename "$d")"
    if [[ ! -f "$d/SKILL.md" ]]; then
        warn "跳过（无 SKILL.md）：$skill_name"
        continue
    fi
    if cp -R "$d" "$SKILLS_DIR/" 2>/dev/null; then
        if [[ -f "$SKILLS_DIR/$skill_name/SKILL.md" ]]; then
            COPIED_SKILLS+=("$skill_name")
            INSTALLED_SKILLS+=("$skill_name")
            info "已安装：$skill_name"
        else
            err "复制后 SKILL.md 不存在：$skill_name"
            rollback_copied_skills
            cleanup_temp
            exit 5
        fi
    else
        err "复制失败：$skill_name"
        rollback_copied_skills
        cleanup_temp
        exit 5
    fi
done

if [[ ${#INSTALLED_SKILLS[@]} -eq 0 ]]; then
    cleanup_temp
    err "没有技能被复制。"
    exit 5
fi
ok "已复制 ${#INSTALLED_SKILLS[@]} 个技能"

# ===== 阶段 4：渲染 AGENTS.md =====
info "阶段 4/5：渲染 AGENTS.md"
if [[ ! -f "$TEMPLATE_PATH" ]]; then
    rollback_copied_skills
    cleanup_temp
    err "模板文件不存在：$TEMPLATE_PATH"
    exit 5
fi

# 生成 SKILLS_LIST 表格
SKILLS_TABLE="| 技能名 | 描述 |"$'\n'"|--------|------|"$'\n'
IFS=$'\n' sorted=($(sort <<<"${INSTALLED_SKILLS[*]}")); unset IFS
for name in "${sorted[@]}"; do
    desc="$(parse_skill_desc "$SKILLS_DIR/$name/SKILL.md")"
    if [[ ${#desc} -gt 80 ]]; then desc="${desc:0:80}..."; fi
    [[ -z "$desc" ]] && desc="(无描述)"
    SKILLS_TABLE+="| \`$name\` | $desc |"$'\n'
done

# 渲染占位符（用 awk，避免 sed 对表格内特殊字符的处理问题）
awk -v table="$SKILLS_TABLE" -v ver="$VERSION_TAG" -v date="$(iso_timestamp)" '
    {gsub(/\{\{SKILLS_LIST\}\}/, table); gsub(/\{\{VERSION\}\}/, ver); gsub(/\{\{DATE\}\}/, date); print}
' "$TEMPLATE_PATH" > "$AGENTS_MD_PATH" || {
    rollback_copied_skills
    cleanup_temp
    err "渲染 AGENTS.md 失败。"
    exit 5
}

AGENTS_MD_HASH="$(file_sha256 "$AGENTS_MD_PATH")"
ok "AGENTS.md 已生成：$AGENTS_MD_PATH"

# ===== 阶段 5：写 manifest + 清理 =====
info "阶段 5/5：写 manifest + 清理"
mkdir -p "$AGENTS_DIR"

# JSON 数组转义
SKILLS_JSON=$(printf ',"%s"' "${INSTALLED_SKILLS[@]}")
SKILLS_JSON="[${SKILLS_JSON:1}]"

MANIFEST_BODY="{
  \"tool\": \"superpowers-for-zcode\",
  \"toolVersion\": \"$TOOL_VERSION\",
  \"upstreamVersion\": \"$VERSION_TAG\",
  \"upstreamUrl\": \"$UPSTREAM_URL\",
  \"installDate\": \"$(iso_timestamp)\",
  \"installPath\": \"$SKILLS_DIR\",
  \"agentsMdPath\": \"$AGENTS_MD_PATH\",
  \"agentsMdSha256\": \"$AGENTS_MD_HASH\",
  \"installedSkills\": $SKILLS_JSON
}"

if ! printf '%s\n' "$MANIFEST_BODY" > "$MANIFEST_PATH"; then
    rollback_copied_skills
    rm -f "$AGENTS_MD_PATH"
    cleanup_temp
    err "写 manifest 失败。"
    exit 5
fi

cleanup_temp

# ===== 摘要 =====
echo ""
echo "✅ Superpowers for ZCode 安装成功！"
echo ""
echo "   上游版本：$VERSION_TAG"
echo "   安装位置：$SKILLS_DIR/"
echo "   AGENTS.md：$AGENTS_MD_PATH"
echo "   已安装 ${#INSTALLED_SKILLS[@]} 个技能：${INSTALLED_SKILLS[*]}"
echo ""
echo "👉 验证方法：重启 ZCode 开新会话，系统提示里应出现 brainstorming 等技能。"
echo "   如需卸载：./uninstall.sh"
exit 0
