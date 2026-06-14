# Superpowers for ZCode 测试入口（Windows）
# 策略：核心逻辑由 verify_logic.ps1 覆盖（不需网络）；
#       端到端 install/uninstall 需要网络 clone，标为 E2E（CI 跑）。

$ErrorActionPreference = "Continue"
$REPO = Split-Path $PSScriptRoot -Parent

$pass = 0; $fail = 0; $skip = 0
function Check($n, $c) {
    if ($c) { Write-Host "  [PASS] $n" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  [FAIL] $n" -ForegroundColor Red; $script:fail++ }
}
function Skip($n, $reason) {
    Write-Host "  [SKIP] $n ($reason)" -ForegroundColor Yellow
    $script:skip++
}

Write-Host "=== A. 核心逻辑验证（verify_logic.ps1）===" -ForegroundColor Cyan
$vl = Join-Path $PSScriptRoot "verify_logic.ps1"
if (Test-Path $vl) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $vl
    if ($LASTEXITCODE -eq 0) {
        $pass++
        Write-Host "  [PASS] verify_logic.ps1 全部通过" -ForegroundColor Green
    } else {
        $fail++
        Write-Host "  [FAIL] verify_logic.ps1 有失败" -ForegroundColor Red
    }
} else {
    Skip "verify_logic.ps1 not found" "file missing"
}

Write-Host ""
Write-Host "=== B. T8: 未安装时卸载（不需网络）===" -ForegroundColor Cyan
$th = Join-Path $env:TEMP ("sp4z-t8-" + [Guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $th -Force | Out-Null
$env:USERPROFILE = $th
$env:HOME = $th
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $REPO "uninstall.ps1") 2>&1 | Out-Null
$code = $LASTEXITCODE
Check "T8 uninstall-on-empty exit 0" ($code -eq 0)
$agentsExist = Test-Path (Join-Path $th ".agents")
Check "T8 no side effects" (-not $agentsExist)
Remove-Item $th -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== C. 端到端 install/uninstall（需要网络）===" -ForegroundColor Cyan
# 探测网络：尝试 ls-remote 上游
$netOk = & git ls-remote --heads "https://github.com/obra/superpowers" "v5.1.0" 2>$null
if ($LASTEXITCODE -eq 0 -and $netOk) {
    Write-Host "  网络可达，跑端到端..." -ForegroundColor Yellow
    # T1: 安装
    $th1 = Join-Path $env:TEMP ("sp4z-t1-" + [Guid]::NewGuid().ToString("N").Substring(0,8))
    New-Item -ItemType Directory -Path $th1 -Force | Out-Null
    $env:USERPROFILE = $th1; $env:HOME = $th1
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $REPO "install.ps1") 2>&1 | Out-Null
    Check "T1 install exit 0" ($LASTEXITCODE -eq 0)
    Check "T1 skills installed" ((Get-ChildItem (Join-Path $th1 ".agents\skills") -Directory -ErrorAction SilentlyContinue).Count -gt 0)
    Check "T1 manifest exists" (Test-Path (Join-Path $th1 ".agents\.superpowers-for-zcode.manifest.json"))
    # T6: 卸载
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $REPO "uninstall.ps1") 2>&1 | Out-Null
    Check "T6 uninstall exit 0" ($LASTEXITCODE -eq 0)
    Remove-Item $th1 -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Skip "T1/T6 端到端" "网络不可达（github.com），请在有网环境或 CI 跑"
}

Write-Host ""
$col = if ($fail -eq 0) { "Green" } else { "Red" }
Write-Host "================================" -ForegroundColor $col
Write-Host ("PASS: " + $pass + "  FAIL: " + $fail + "  SKIP: " + $skip) -ForegroundColor $col
Write-Host "================================" -ForegroundColor $col
if ($fail -gt 0) { exit 1 } else { exit 0 }
