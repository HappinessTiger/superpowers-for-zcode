<#
.SYNOPSIS
  安装 Superpowers for ZCode（Windows）
.DESCRIPTION
  git clone 上游 obra/superpowers -> 复制 skills 到 ~/.agents/skills/ ->
  渲染 AGENTS.md -> 写 manifest。
  失败时回滚到安装前状态。
.PARAMETER AgentsMdPath
  AGENTS.md 落地路径，默认 $HOME\AGENTS.md。
  也可用环境变量 $env:SP4Z_AGENTS_MD_PATH 覆盖。
.EXAMPLE
  .\install.ps1
#>
[CmdletBinding()]
param(
    [string]$AgentsMdPath
)

$ErrorActionPreference = "Stop"

# 用户主目录解析：优先用可重定向的环境变量（$env:USERPROFILE 在 Windows、$env:HOME 在 Unix），
# 回退到 PowerShell 只读自动变量 $HOME。
# 这样测试可以通过设置 $env:USERPROFILE / $env:HOME 重定向，生产环境不受影响。
$UserHome = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $HOME }

# ===== 常量 =====
$SCRIPT:TOOL_VERSION   = "1.0.0"
$SCRIPT:UPSTREAM_URL   = "https://github.com/obra/superpowers"
$SCRIPT:SKILLS_DIR     = Join-Path $UserHome ".agents\skills"
$SCRIPT:MANIFEST_PATH  = Join-Path $UserHome ".agents\.superpowers-for-zcode.manifest.json"
$SCRIPT:TEMPLATE_PATH  = Join-Path $PSScriptRoot "templates\AGENTS.md.template"
$SCRIPT:VERSION_FILE   = Join-Path $PSScriptRoot "VERSION"

# AGENTS.md 落地路径：参数 > 环境变量 > 默认
if (-not $AgentsMdPath) {
    $AgentsMdPath = $env:SP4Z_AGENTS_MD_PATH
}
if (-not $AgentsMdPath) {
    $AgentsMdPath = Join-Path $UserHome "AGENTS.md"
}
$SCRIPT:AGENTS_MD_PATH = $AgentsMdPath

# ===== 工具函数 =====
function Write-Info($msg)  { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Exit-WithCode($code, $msg) {
    if ($msg) { Write-Err $msg }
    exit $code
}

function Get-FileSha256($path) {
    return (Get-FileHash $path -Algorithm SHA256).Hash.ToLower()
}

function Get-IsoTimestamp {
    return (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
}

# 解析 SKILL.md frontmatter，返回 name/description 字典
function Parse-SkillFrontmatter($skillMdPath) {
    $content = Get-Content $skillMdPath -Raw -Encoding UTF8
    if ($content -match '(?s)^---\s*\r?\n(.*?)\r?\n---') {
        $fm = $matches[1]
        $name = if ($fm -match 'name:\s*(.+)') { $matches[1].Trim().Trim('"') } else { $null }
        $desc = if ($fm -match 'description:\s*(.+?)(?:\r?\n[a-zA-Z_-]+:|\z)') { $matches[1].Trim().Trim('"') } else { '' }
        return @{ Name = $name; Description = $desc }
    }
    return $null
}

# 清理临时目录（幂等）
function Cleanup-Temp {
    if ($SCRIPT:TEMP_DIR -and (Test-Path $SCRIPT:TEMP_DIR)) {
        Remove-Item $SCRIPT:TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 回滚已复制的 skills（错误码 5 用）
$SCRIPT:COPIED_SKILLS = [System.Collections.ArrayList]::new()
function Rollback-CopiedSkills {
    foreach ($name in $SCRIPT:COPIED_SKILLS) {
        $p = Join-Path $SKILLS_DIR $name
        if (Test-Path $p) {
            Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ===== 阶段 0：前置检查 =====
Write-Info "阶段 0/5：前置检查"

# 0a. git 是否安装
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Exit-WithCode 1 "未检测到 git，请先安装 git 并加入 PATH。"
}

# 0b. manifest 是否已存在（已装）
if (Test-Path $MANIFEST_PATH) {
    Exit-WithCode 3 "已检测到安装记录 ($MANIFEST_PATH)。请先运行 .\uninstall.ps1 卸载后再安装。"
}

Write-Ok "前置检查通过"

# ===== 阶段 1：准备目标目录 =====
Write-Info "阶段 1/5：准备目标目录"

if (-not (Test-Path $SKILLS_DIR)) {
    New-Item -ItemType Directory -Path $SKILLS_DIR -Force | Out-Null
    Write-Info "创建 skills 目录：$SKILLS_DIR"
} else {
    Write-Info "skills 目录已存在：$SKILLS_DIR"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tempDir = Join-Path $env:TEMP "superpowers-install-$timestamp"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$SCRIPT:TEMP_DIR = $tempDir
Write-Info "临时目录：$tempDir"

# ===== 阶段 2：clone 上游 =====
Write-Info "阶段 2/5：clone 上游"

$versionTag = (Get-Content $VERSION_FILE -Raw -Encoding UTF8).Trim()
Write-Info "目标版本：$versionTag"

$cloneTarget = Join-Path $tempDir "superpowers"
Write-Info "git clone --depth 1 --branch $versionTag $UPSTREAM_URL"

# 注意：git 会把 "Cloning into '...'"（正常进度）写到 stderr，
# 而本脚本顶部设置了 $ErrorActionPreference = "Stop"，PowerShell 会把
# 任何 stderr 当成终止错误（误判为 clone 失败）。
# -ErrorAction 是 PowerShell 通用参数，对 native command（git.exe）无效，
# 反而会被当成参数传给 git 导致 "unknown switch" 错误。
# 因此：临时切到 Continue，调完 git 立即恢复，并缓存 $LASTEXITCODE。
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$cloneLog = & git clone --depth 1 --branch $versionTag $UPSTREAM_URL $cloneTarget 2>&1
$cloneExit = $LASTEXITCODE
$ErrorActionPreference = $prevEAP
if ($cloneExit -ne 0) {
    Cleanup-Temp
    $detail = ($cloneLog | Out-String).Trim()
    if ($detail) {
        Write-Err "git clone 详细输出："
        Write-Host $detail -ForegroundColor DarkGray
    }
    Exit-WithCode 2 "git clone 失败（退出码 $cloneExit）。请检查网络/代理，或确认版本 tag '$versionTag' 是否存在。"
}

# 校验 skills 目录
$clonedSkillsDir = Join-Path $cloneTarget "skills"
if (-not (Test-Path $clonedSkillsDir)) {
    Cleanup-Temp
    Exit-WithCode 4 "clone 成功但未找到 skills 目录，上游结构异常。"
}

$skillDirs = Get-ChildItem $clonedSkillsDir -Directory
if ($skillDirs.Count -eq 0) {
    Cleanup-Temp
    Exit-WithCode 4 "clone 成功但 skills 目录为空。"
}

Write-Ok "clone 完成，发现 $($skillDirs.Count) 个技能"

# ===== 阶段 3：复制 skills =====
Write-Info "阶段 3/5：复制 skills"

$installedSkills = [System.Collections.ArrayList]::new()
$failedCopy = $false

foreach ($skillDir in $skillDirs) {
    $skillName = $skillDir.Name
    $skillMd = Join-Path $skillDir.FullName "SKILL.md"
    if (-not (Test-Path $skillMd)) {
        Write-Warn "跳过（无 SKILL.md）：$skillName"
        continue
    }

    $dest = Join-Path $SKILLS_DIR $skillName
    try {
        Copy-Item -Path $skillDir.FullName -Destination $dest -Recurse -Force
        # 完整性自检
        if (-not (Test-Path (Join-Path $dest "SKILL.md"))) {
            throw "复制后 SKILL.md 不存在"
        }
        $null = $SCRIPT:COPIED_SKILLS.Add($skillName)
        $null = $installedSkills.Add($skillName)
        Write-Info "已安装：$skillName"
    } catch {
        Write-Err "复制 $skillName 失败：$_"
        $failedCopy = $true
        break
    }
}

if ($failedCopy -or $installedSkills.Count -eq 0) {
    Rollback-CopiedSkills
    Cleanup-Temp
    Exit-WithCode 5 "复制 skills 失败，已回滚。"
}

Write-Ok "已复制 $($installedSkills.Count) 个技能"

# ===== 阶段 4：渲染 AGENTS.md =====
Write-Info "阶段 4/5：渲染 AGENTS.md"

# 读模板
if (-not (Test-Path $TEMPLATE_PATH)) {
    Rollback-CopiedSkills
    Cleanup-Temp
    Exit-WithCode 5 "模板文件不存在：$TEMPLATE_PATH"
}
$template = Get-Content $TEMPLATE_PATH -Raw -Encoding UTF8

# 生成 SKILLS_LIST 表格（扫描已安装技能，按 name 字母序）
$skillRows = @()
foreach ($skillName in ($installedSkills | Sort-Object)) {
    $skillMd = Join-Path $SKILLS_DIR "$skillName\SKILL.md"
    $fm = Parse-SkillFrontmatter $skillMd
    if ($fm) {
        $desc = $fm.Description
        if ($desc.Length -gt 80) { $desc = $desc.Substring(0, 80) + "..." }
        $skillRows += "| ``$skillName`` | $desc |"
    } else {
        $skillRows += "| ``$skillName`` | (无描述) |"
    }
}
$skillsTable = "| 技能名 | 描述 |`r`n|--------|------|`r`n" + ($skillRows -join "`r`n")

# 渲染占位符
# 注意：用 .NET String.Replace 而非 PowerShell -replace 运算符
# 因为 SKILLS_LIST 表格含 | ` 等 -replace 的正则特殊字符，会引发替换错误
$rendered = $template.
    Replace('{{SKILLS_LIST}}', $skillsTable).
    Replace('{{VERSION}}', $versionTag).
    Replace('{{DATE}}', (Get-IsoTimestamp))

# 写入
try {
    [System.IO.File]::WriteAllText($AGENTS_MD_PATH, $rendered, [System.Text.UTF8Encoding]::new($false))
} catch {
    Rollback-CopiedSkills
    Cleanup-Temp
    Exit-WithCode 5 "写入 AGENTS.md 失败：$_"
}

$agentsMdHash = Get-FileSha256 $AGENTS_MD_PATH
Write-Ok "AGENTS.md 已生成：$AGENTS_MD_PATH"

# ===== 阶段 5：写 manifest + 清理 =====
Write-Info "阶段 5/5：写 manifest + 清理"

$manifest = [ordered]@{
    tool            = "superpowers-for-zcode"
    toolVersion     = $TOOL_VERSION
    upstreamVersion = $versionTag
    upstreamUrl     = $UPSTREAM_URL
    installDate     = Get-IsoTimestamp
    installPath     = $SKILLS_DIR
    agentsMdPath    = $AGENTS_MD_PATH
    agentsMdSha256  = $agentsMdHash
    installedSkills = $installedSkills
}

$manifestJson = $manifest | ConvertTo-Json -Depth 10

try {
    # 确保 ~/.agents/ 存在
    $agentsDir = Split-Path $MANIFEST_PATH -Parent
    if (-not (Test-Path $agentsDir)) {
        New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($MANIFEST_PATH, $manifestJson, [System.Text.UTF8Encoding]::new($false))
} catch {
    Rollback-CopiedSkills
    Remove-Item $AGENTS_MD_PATH -Force -ErrorAction SilentlyContinue
    Cleanup-Temp
    Exit-WithCode 5 "写 manifest 失败，已回滚：$_"
}

Cleanup-Temp

# ===== 输出摘要 =====
Write-Host ""
Write-Host "✅ Superpowers for ZCode 安装成功！" -ForegroundColor Green
Write-Host ""
Write-Host "   上游版本：$versionTag"
Write-Host "   安装位置：$SKILLS_DIR\"
Write-Host "   AGENTS.md：$AGENTS_MD_PATH"
Write-Host "   已安装 $($installedSkills.Count) 个技能：$($installedSkills -join ', ')"
Write-Host ""
Write-Host "👉 验证方法：重启 ZCode 开新会话，系统提示里应出现 brainstorming 等技能。"
Write-Host "   或直接说 ``/brainstorming`` 测试。"
Write-Host ""
Write-Host "   如需卸载：.\uninstall.ps1"
exit 0
