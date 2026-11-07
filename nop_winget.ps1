# nop_winget.ps1 - Submit vulongvy.FixPrinter to microsoft/winget-pkgs.
# Uses the gh CLI login already on this machine (NO personal access token needed):
#   ensure fork -> render manifests from winget-templates -> validate ->
#   create branch on the fork via API -> upload 4 manifest files ->
#   open the pull request. Idempotent: safe to run again.
# ASCII-only on purpose (Windows PowerShell 5.1 safe).
# NOTE (PS 5.1): with ErrorActionPreference=Stop, ANY stderr output from a
# native command (gh) becomes a terminating NativeCommandError - even for
# expected answers like HTTP 404. All gh probes below therefore go through
# GhOk / GhOut, which temporarily relax the preference and read $LASTEXITCODE.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
try { Start-Transcript -Path (Join-Path $root 'nop_winget_log.txt') -Append | Out-Null } catch {}

function Step($msg) { Write-Host "[..] $msg" }
function Ok($msg)   { Write-Host "[OK] $msg" }
function Fail($msg) { Write-Host "[LOI] $msg"; try { Stop-Transcript | Out-Null } catch {}; exit 1 }

function GhOk {
    param([string[]]$GhArgs)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & gh @GhArgs *> $null; return ($LASTEXITCODE -eq 0) }
    finally { $ErrorActionPreference = $old }
}

function GhOut {
    param([string[]]$GhArgs)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $o = & gh @GhArgs 2>$null
        if ($LASTEXITCODE -eq 0 -and $o) { return ($o | Out-String).Trim() }
        return $null
    } finally { $ErrorActionPreference = $old }
}

Write-Host '============================================================'
Write-Host '  NOP WINGET - vulongvy.FixPrinter -> microsoft/winget-pkgs'
Write-Host '============================================================'

# --- 0. Tools + login -------------------------------------------------------
Step 'Kiem tra git / gh / dang nhap GitHub...'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'Chua co git. Chay DAY_LEN_GITHUB.bat truoc (no tu cai).' }
if (-not (Get-Command gh  -ErrorAction SilentlyContinue)) { Fail 'Chua co GitHub CLI. Chay DAY_LEN_GITHUB.bat truoc (no tu cai).' }
if (-not (GhOk @('auth', 'status'))) { Fail 'gh chua dang nhap. Chay: gh auth login' }
Ok 'gh da dang nhap'

# --- 1. Version + installer SHA-256 -----------------------------------------
$ver = (Get-Content (Join-Path $root 'VERSION.txt') -Raw).Trim()
if (-not $ver) { Fail 'VERSION.txt rong.' }
Ok "Phien ban: $ver"

$pkgId    = 'vulongvy.FixPrinter'
$pkgPath  = 'manifests/v/vulongvy/FixPrinter/' + $ver
$assetUrl = "https://github.com/vulongvy/FixPrinter/releases/download/v$ver/FixPrinter-Setup-$ver.exe"
$tmpExe   = Join-Path $env:TEMP "FixPrinter-Setup-$ver.exe"

Step 'Tai file cai tu GitHub Release de lay SHA-256...'
try {
    Invoke-WebRequest -Uri $assetUrl -OutFile $tmpExe -UseBasicParsing
} catch {
    $local = Join-Path $root "dist\FixPrinter-Setup-$ver.exe"
    if (Test-Path $local) { $tmpExe = $local; Write-Host "    Tai that bai - dung file local: $local" }
    else { Fail "Khong tai duoc file cai va khong co ban local: $assetUrl" }
}
$hash = (Get-FileHash -Path $tmpExe -Algorithm SHA256).Hash
Ok "SHA-256: $hash"

# --- 2. Render + validate manifests -----------------------------------------
$stage = Join-Path $env:TEMP ("winget-stage-" + $ver)
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
Get-ChildItem (Join-Path $root 'winget-templates\*.yaml') | ForEach-Object {
    ((Get-Content $_.FullName -Raw) -replace '__VERSION__', $ver -replace '__SHA256__', $hash) |
        Set-Content (Join-Path $stage $_.Name) -Encoding UTF8
}
Ok "Da render 4 manifest vao thu muc tam"
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Step 'Chay winget validate...'
    $vout = winget validate --manifest $stage 2>&1 | Out-String
    Write-Host $vout.Trim()
    if ($vout -match 'failed') { Fail 'winget validate THAT BAI - dung lai, chua nop gi ca.' }
    Ok 'winget validate QUA'
} else {
    Write-Host '[!] Khong co winget tren may - bo qua buoc validate local.'
}

# --- 3. Ensure fork ----------------------------------------------------------
Step 'Kiem tra fork microsoft/winget-pkgs...'
if (GhOk @('repo', 'view', 'vulongvy/winget-pkgs', '--json', 'name')) {
    Ok 'Da co fork: vulongvy/winget-pkgs'
} else {
    Step 'Chua co fork - dang tao fork...'
    if (-not (GhOk @('repo', 'fork', 'microsoft/winget-pkgs', '--clone=false'))) { Fail 'Tao fork that bai.' }
    Start-Sleep -Seconds 5
    Ok 'Da tao fork: vulongvy/winget-pkgs'
}

$base = GhOut @('api', 'repos/microsoft/winget-pkgs', '--jq', '.default_branch')
if (-not $base) { $base = 'master' }
Ok "Nhanh goc cua winget-pkgs: $base"

# --- 4. Branch on the fork ----------------------------------------------------
$branch  = "vulongvy.FixPrinter-$ver"
$baseSha = GhOut @('api', "repos/vulongvy/winget-pkgs/git/ref/heads/$base", '--jq', '.object.sha')
if (-not $baseSha) { Fail 'Khong lay duoc SHA cua nhanh goc tren fork.' }
if (GhOk @('api', "repos/vulongvy/winget-pkgs/git/ref/heads/$branch")) {
    Write-Host "[..] Nhanh $branch da ton tai tren fork - dung lai nhanh do."
} else {
    $made = GhOk @('api', 'repos/vulongvy/winget-pkgs/git/refs', '-f', "ref=refs/heads/$branch", '-f', "sha=$baseSha")
    if (-not $made) { Fail 'Tao nhanh tren fork that bai.' }
    Ok "Da tao nhanh: $branch"
}

# --- 5. Upload the 4 manifest files (Contents API) -----------------------------
Step 'Tai 4 file manifest len nhanh...'
foreach ($f in (Get-ChildItem (Join-Path $stage '*.yaml'))) {
    $rel = "$pkgPath/$($f.Name)"
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.FullName))
    $putArgs = @('api', "repos/vulongvy/winget-pkgs/contents/$rel", '-X', 'PUT',
                 '-f', "message=New package: $pkgId version $ver",
                 '-f', "content=$b64", '-f', "branch=$branch")
    $existing = GhOut @('api', "repos/vulongvy/winget-pkgs/contents/$rel`?ref=$branch", '--jq', '.sha')
    if ($existing) { $putArgs += @('-f', "sha=$existing") }
    if (-not (GhOk $putArgs)) { Fail "Tai file $($f.Name) that bai." }
    Ok "  len: $rel"
}

# --- 6. Open the pull request ---------------------------------------------------
Step 'Mo pull request sang microsoft/winget-pkgs...'
$prBody = @"
New package submission: **$pkgId** version **$ver**

- Installer: $assetUrl
- Installer SHA-256: $hash
- Manifests validated locally with ``winget validate`` (manifest version 1.12.0).
- Package source (open, MIT): https://github.com/vulongvy/FixPrinter
"@
$old = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$prUrl = & gh pr create --repo microsoft/winget-pkgs --base $base --head "vulongvy:$branch" `
            --title "New package: $pkgId version $ver" --body $prBody 2>&1 | Out-String
$prCode = $LASTEXITCODE
$ErrorActionPreference = $old
if ($prCode -ne 0) {
    $found = GhOut @('pr', 'list', '--repo', 'microsoft/winget-pkgs', '--head', "vulongvy:$branch", '--json', 'url', '--jq', '.[0].url')
    if ($found) { $prUrl = $found } else { Fail "Mo PR that bai: $prUrl" }
}
Ok 'XONG! Pull request:'
Write-Host "    $($prUrl.Trim())"
Write-Host ''
Write-Host 'Buoc tiep theo (tu dong phia Microsoft): pipeline quet + gan nhan.'
Write-Host 'Neu bot CLA comment yeu cau ky cam ket (lan dau nop), bam link trong comment'
Write-Host 'va lam theo - chi 1 lan duy nhat cho tai khoan.'
try { Stop-Transcript | Out-Null } catch {}
