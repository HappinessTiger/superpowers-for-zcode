<#
.SYNOPSIS
  卸载 Superpowers for ZCode（Windows）
.DESCRIPTION
  读 manifest -> 精确删除 skills -> 处理 AGENTS.md（带 hash 保护）-> 删 manifest。
.PARAMETER Force
  跳过 AGENTS.md 修改确认，强制删除。
.EXAMPLE
  .\uninstall.ps1
  .\uninstall.ps1 -Force
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# 用户主目录解析：优先用可重定向的环境变量，回退到只读自动变量 $HOME。
$UserHome = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $HOME }

$SCRIPT:MANIFEST_PATH = Join-Path $UserHome ".agents\.superpowers-for-zcode.manifest.json"
$SCRIPT:SKILLS_DIR    = Join-Path $UserHome ".agents\skills"

function Write-Info($msg)  { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Get-FileSha256($path) {
    return (Get-FileHash $path -Algorithm SHA256).Hash.ToLower()
}

# ===== 阶段 0：定位 manifest =====
Write-Info "阶段 0/2：定位 manifest"

if (-not (Test-Path $MANIFEST_PATH)) {
    Write-Info "未检测到安装记录，无需卸载。"
    Write-Info "（manifest 不存在：$MANIFEST_PATH）"
    exit 0
}

try {
    $manifest = Get-Content $MANIFEST_PATH -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Err "manifest 文件损坏，无法解析：$_"
    Write-Err "请手动检查：$MANIFEST_PATH"
    exit 6
}

Write-Ok "已加载 manifest（上游版本：$($manifest.upstreamVersion)）"

# ===== 阶段 1：删除 skills =====
Write-Info "阶段 1/2：删除 skills"

$deletedCount = 0
$skippedCount = 0
foreach ($skillName in $manifest.installedSkills) {
    $skillPath = Join-Path $SKILLS_DIR $skillName
    if (Test-Path $skillPath) {
        Remove-Item $skillPath -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $skillPath)) {
            $deletedCount++
            Write-Info "已删除：$skillName"
        } else {
            Write-Warn "删除失败：$skillName"
        }
    } else {
        $skippedCount++
        Write-Warn "不存在，跳过：$skillName"
    }
}
Write-Ok "已删除 $deletedCount 个，跳过 $skippedCount 个"

# ===== 阶段 2：处理 AGENTS.md + 删 manifest =====
Write-Info "阶段 2/2：处理 AGENTS.md"

$agentsMdPath = $manifest.agentsMdPath
$agentsMdDeleted = $false
if ($agentsMdPath -and (Test-Path $agentsMdPath)) {
    $currentHash = Get-FileSha256 $agentsMdPath
    if ($currentHash -eq $manifest.agentsMdSha256) {
        Remove-Item $agentsMdPath -Force
        $agentsMdDeleted = $true
        Write-Ok "AGENTS.md 已删除（未被修改过）"
    } else {
        Write-Warn "AGENTS.md 已被修改（hash 不匹配）"
        if ($Force) {
            Remove-Item $agentsMdPath -Force
            $agentsMdDeleted = $true
            Write-Ok "因 -Force 已强制删除 AGENTS.md"
        } else {
            $answer = Read-Host "是否强制删除已修改的 AGENTS.md？[y/N]"
            if ($answer -match '^[yY]') {
                Remove-Item $agentsMdPath -Force
                $agentsMdDeleted = $true
                Write-Ok "已强制删除 AGENTS.md"
            } else {
                Write-Warn "保留 AGENTS.md（用户选择不删除）"
            }
        }
    }
} else {
    Write-Warn "AGENTS.md 不存在，跳过"
}

# 删 manifest
Remove-Item $MANIFEST_PATH -Force
Write-Ok "manifest 已删除"

# ===== 摘要 =====
Write-Host ""
Write-Host "✅ Superpowers for ZCode 已卸载。" -ForegroundColor Green
Write-Host ""
Write-Host "   已删除 $deletedCount 个技能。"
Write-Host "   AGENTS.md：$(if($agentsMdDeleted){'已删除'}else{'已保留（用户修改过）'})"
Write-Host "   manifest：已删除"
Write-Host ""
Write-Host "👉 重启 ZCode 使变更生效。"
exit 0
