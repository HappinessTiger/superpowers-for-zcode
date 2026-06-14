# 验证 install 阶段 3-5 逻辑（跳过 clone，用本地副本）
$ErrorActionPreference = "Stop"

$REPO = "D:\workShop\githubProjects\superpowersforzcode"
$LOCAL = "D:\workShop\githubProjects\superpowers-main"
$TH = Join-Path $env:TEMP ("sp4z-l-" + [Guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $TH -Force | Out-Null
$SD = Join-Path $TH ".agents\skills"
$MP = Join-Path $TH ".agents\.superpowers-for-zcode.manifest.json"
$TP = Join-Path $REPO "templates\AGENTS.md.template"
$AM = Join-Path $TH "AGENTS.md"
New-Item -ItemType Directory -Path $SD -Force | Out-Null

$pass = 0; $fail = 0
function Check($n, $c) {
    if ($c) { Write-Host "  [PASS] $n" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  [FAIL] $n" -ForegroundColor Red; $script:fail++ }
}

Write-Host ("TEST_HOME: " + $TH)

# 阶段 3：复制 skills
Write-Host "=== phase 3: copy skills ===" -ForegroundColor Cyan
$skillDirs = Get-ChildItem (Join-Path $LOCAL "skills") -Directory
$list = [System.Collections.ArrayList]::new()
foreach ($d in $skillDirs) {
    if (Test-Path (Join-Path $d.FullName "SKILL.md")) {
        Copy-Item $d.FullName (Join-Path $SD $d.Name) -Recurse -Force
        $null = $list.Add($d.Name)
    }
}
Check "skills copied (>=10)" ($list.Count -ge 10)

# 阶段 4：渲染 AGENTS.md
Write-Host "=== phase 4: render AGENTS.md ===" -ForegroundColor Cyan
$tpl = Get-Content $TP -Raw -Encoding UTF8
$rows = @()
foreach ($n in ($list | Sort-Object)) {
    $rows += ("| " + $n + " | desc |")
}
$table = "| name | desc |`r`n|---|---|`r`n" + ($rows -join "`r`n")
$r = $tpl.Replace("{{SKILLS_LIST}}", $table).Replace("{{VERSION}}", "v5.1.0").Replace("{{DATE}}", (Get-Date -Format "o"))
[System.IO.File]::WriteAllText($AM, $r, [System.Text.UTF8Encoding]::new($false))
$h = (Get-FileHash $AM -Algorithm SHA256).Hash.ToLower()
Check "AGENTS.md generated" (Test-Path $AM)
Check "AGENTS.md size ok (>=3000)" ((Get-Item $AM).Length -ge 3000)
Check "SKILLS_LIST replaced" (-not $r.Contains("{{SKILLS_LIST}}"))
Check "VERSION replaced" (-not $r.Contains("{{VERSION}}"))
Check "DATE replaced" (-not $r.Contains("{{DATE}}"))

# 阶段 5：写 manifest
Write-Host "=== phase 5: write manifest ===" -ForegroundColor Cyan
$man = [ordered]@{
    tool = "sp4z"; toolVersion = "1.0.0"; upstreamVersion = "v5.1.0"
    agentsMdSha256 = $h; installedSkills = $list
}
$mj = $man | ConvertTo-Json -Depth 10
$ad = Split-Path $MP -Parent
if (-not (Test-Path $ad)) { New-Item -ItemType Directory -Path $ad -Force | Out-Null }
[System.IO.File]::WriteAllText($MP, $mj, [System.Text.UTF8Encoding]::new($false))
$m = Get-Content $MP -Raw -Encoding UTF8 | ConvertFrom-Json
Check "manifest generated" (Test-Path $MP)
Check "manifest skills count match" ($m.installedSkills.Count -eq $list.Count)
Check "manifest has sha256" ($m.agentsMdSha256.Length -gt 0)

# 模拟卸载
Write-Host "=== simulate uninstall ===" -ForegroundColor Cyan
$del = 0
foreach ($n in $m.installedSkills) {
    $p = Join-Path $SD $n
    if (Test-Path $p) { Remove-Item $p -Recurse -Force; $del++ }
}
Check "uninstall deletes all" ($del -eq $list.Count)
$remain = @(Get-ChildItem $SD -Directory -ErrorAction SilentlyContinue).Count
Check "skills dir empty after uninstall" ($remain -eq 0)

# hash 保护
Write-Host "=== hash protection ===" -ForegroundColor Cyan
$ch2 = (Get-FileHash $AM -Algorithm SHA256).Hash.ToLower()
Check "hash unchanged when not edited" ($ch2 -eq $h)
Add-Content $AM "# change" -Encoding UTF8
$ch3 = (Get-FileHash $AM -Algorithm SHA256).Hash.ToLower()
Check "hash changed after edit" ($ch3 -ne $h)

Remove-Item $TH -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
$col = if ($fail -eq 0) { "Green" } else { "Red" }
Write-Host "================================" -ForegroundColor $col
Write-Host ("PASS: " + $pass + "  FAIL: " + $fail) -ForegroundColor $col
Write-Host "================================" -ForegroundColor $col
if ($fail -gt 0) { exit 1 } else { exit 0 }
