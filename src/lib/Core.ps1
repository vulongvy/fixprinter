# FixPrinter v13 - Core.ps1
# Logging, step tracking (PASS/FAIL/SKIP), native command runner with exit-code
# checks, registry helpers with read-back verification, timestamped backups.
# PowerShell 5.1 compatible. ASCII only.

$script:FPPass = 0
$script:FPFail = 0
$script:FPSkip = 0

function FP-InitPaths {
    # $PSScriptRoot inside this function = the lib folder where Core.ps1 lives,
    # so the tool root is one level up. Works no matter where the tool is copied.
    $script:FPRoot = Split-Path -Parent $PSScriptRoot
    if (-not $script:FPRoot) { $script:FPRoot = (Get-Location).Path }
    $script:FPLog = Join-Path $script:FPRoot 'fixprinter_v13_log.txt'
    $script:FPBackupRoot = Join-Path $script:FPRoot 'backup'
}

function FP-Log {
    param([string]$Msg, [string]$Kind = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts][$Kind] $Msg"
    try { Add-Content -Path $script:FPLog -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
    switch ($Kind) {
        'OK'   { Write-Host $Msg -ForegroundColor Green }
        'FAIL' { Write-Host $Msg -ForegroundColor Red }
        'SKIP' { Write-Host $Msg -ForegroundColor DarkYellow }
        'WARN' { Write-Host $Msg -ForegroundColor Yellow }
        'RUN'  { Write-Host $Msg -ForegroundColor DarkGray }
        default { Write-Host $Msg }
    }
}

function FP-Info { param([string]$Msg) FP-Log $Msg 'INFO' }
function FP-Warn { param([string]$Msg) FP-Log $Msg 'WARN' }

function FP-OK {
    param([string]$Name, [string]$Detail = '')
    $script:FPPass++
    if ($Detail) { FP-Log "[OK] $Name -- $Detail" 'OK' } else { FP-Log "[OK] $Name" 'OK' }
}
function FP-FAIL {
    param([string]$Name, [string]$Detail = '')
    $script:FPFail++
    if ($Detail) { FP-Log "[FAIL] $Name -- $Detail" 'FAIL' } else { FP-Log "[FAIL] $Name" 'FAIL' }
}
function FP-SKIP {
    param([string]$Name, [string]$Reason = '')
    $script:FPSkip++
    if ($Reason) { FP-Log "[SKIP] $Name -- $Reason" 'SKIP' } else { FP-Log "[SKIP] $Name" 'SKIP' }
}

function FP-BeginAction {
    param([string]$Title)
    $script:FPPass = 0; $script:FPFail = 0; $script:FPSkip = 0
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    FP-Log "=== ACTION: $Title ===" 'INFO'
}

function FP-Summary {
    FP-Log ("=== SUMMARY: PASS={0} FAIL={1} SKIP={2} ===" -f $script:FPPass, $script:FPFail, $script:FPSkip) 'INFO'
    Write-Host ("Ket qua: PASS={0}  FAIL={1}  SKIP={2}" -f $script:FPPass, $script:FPFail, $script:FPSkip) -ForegroundColor Cyan
    if ($script:FPFail -gt 0) {
        Write-Host 'Co muc FAIL - xem chi tiet trong fixprinter_v13_log.txt' -ForegroundColor Yellow
    }
}

# Run a native command with a single argument string (same model as reg.exe /
# sc.exe / netsh style tools). Captures output into the log, returns exit code.
function FP-Run {
    param([string]$File, [string]$Arguments = '', [switch]$Quiet)
    if (-not $Quiet) { FP-Log "> $File $Arguments" 'RUN' }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $File
        $psi.Arguments = $Arguments
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        if ($out.Trim()) { foreach ($l in ($out -split "`r?`n")) { if ($l.Trim()) { FP-Log "    $l" 'RUN' } } }
        if ($err.Trim()) { foreach ($l in ($err -split "`r?`n")) { if ($l.Trim()) { FP-Log "    ERR: $l" 'RUN' } } }
        return $p.ExitCode
    } catch {
        FP-Log "    Cannot start $File : $($_.Exception.Message)" 'RUN'
        return -1
    }
}

# Run one named step. The body must return $true (done) or $false (failed).
# A body may call FP-SKIP itself and return 'skip'.
function FP-Step {
    param([string]$Name, [scriptblock]$Body)
    try {
        $r = & $Body
        # Strict string check first: in PowerShell, $true -eq 'skip' is $true
        # (non-empty string converts to bool), so a loose comparison would
        # silently swallow every passing step.
        if ($r -is [string] -and $r -eq 'skip') { return }
        if ($r -eq $false) { FP-FAIL $Name 'step returned false' }
        else { FP-OK $Name }
    } catch {
        FP-FAIL $Name $_.Exception.Message
    }
}

function FP-Confirm {
    param([string]$Prompt)
    $a = Read-Host "$Prompt [y/N]"
    return ($a -eq 'y' -or $a -eq 'Y')
}

function FP-ConfirmTyped {
    param([string]$Prompt, [string]$Word)
    $a = Read-Host "$Prompt (go dung chu: $Word)"
    return ($a -eq $Word)
}

# ---------------- Registry helpers (PS paths: HKLM:\... HKCU:\...) -----------

function FP-RegGet {
    param([string]$Path, [string]$Name)
    try {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    } catch { return $null }
}

function FP-RegSetDword {
    param([string]$Path, [string]$Name, [int]$Value)
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
        $after = FP-RegGet $Path $Name
        return ($after -eq $Value)
    } catch { return $false }
}

function FP-RegDeleteValue {
    param([string]$Path, [string]$Name)
    try {
        if (Test-Path $Path) {
            $cur = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $cur) { Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop }
        }
        return $true
    } catch { return $false }
}

# ---------------- Service helper ---------------------------------------------

# Ensures a service is Automatic (and Running unless -NoStart).
# Reports its own PASS/FAIL/SKIP line - call it directly, do NOT wrap in FP-Step.
function FP-ServiceEnsure {
    param([string]$Name, [switch]$NoStart)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        FP-SKIP "Service $Name" 'service khong ton tai tren may nay'
        return
    }
    try { Set-Service -Name $Name -StartupType Automatic -ErrorAction Stop } catch {
        FP-FAIL "Service $Name" "khong set duoc Automatic: $($_.Exception.Message)"; return
    }
    if (-not $NoStart) {
        try { Start-Service -Name $Name -ErrorAction SilentlyContinue } catch {}
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { FP-OK "Service $Name" 'Automatic + Running'; return }
        FP-FAIL "Service $Name" "da set Automatic nhung trang thai = $($svc.Status)"
        return
    }
    FP-OK "Service $Name" 'Automatic'
}

function FP-RestartSpooler {
    try {
        Restart-Service -Name Spooler -Force -ErrorAction Stop
        Start-Sleep -Seconds 1
        $s = Get-Service -Name Spooler
        return ($s.Status -eq 'Running')
    } catch { return $false }
}

# ---------------- Backup ------------------------------------------------------

function FP-BackupAll {
    param([switch]$Quiet)
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir = Join-Path $script:FPBackupRoot $stamp
    try { New-Item -ItemType Directory -Path $dir -Force | Out-Null } catch {
        FP-FAIL 'Backup registry' "khong tao duoc thu muc $dir"; return $null
    }
    $keys = @(
        @('HKLM\SYSTEM\CurrentControlSet\Control\Print', 'Control_Print.reg'),
        @('HKLM\SYSTEM\CurrentControlSet\Services\Spooler', 'Service_Spooler.reg'),
        @('HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers', 'Printer_Policies.reg'),
        @('HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows', 'Default_Printer_HKCU.reg'),
        @('HKCU\Printers', 'Printers_HKCU.reg'),
        @('HKLM\SYSTEM\CurrentControlSet\Services\NetBT', 'NetBT.reg'),
        @('HKLM\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation', 'LanmanWorkstation_Policy.reg'),
        @('HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation', 'Service_LanmanWorkstation.reg'),
        @('HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer', 'Service_LanmanServer.reg')
    )
    $okCount = 0
    foreach ($k in $keys) {
        $target = Join-Path $dir $k[1]
        $rc = FP-Run 'reg.exe' ("export `"{0}`" `"{1}`" /y" -f $k[0], $target) -Quiet
        if ($rc -eq 0) { $okCount++ }
    }
    # Snapshot of printers / ports / drivers as plain text for reference
    try {
        $txt = Join-Path $dir 'printers_snapshot.txt'
        $lines = @()
        $lines += '=== Get-Printer ==='
        $lines += (Get-Printer | Format-Table Name, DriverName, PortName, Shared, ShareName -AutoSize | Out-String)
        $lines += '=== Get-PrinterPort ==='
        $lines += (Get-PrinterPort | Format-Table Name, PrinterHostAddress, SNMPEnabled -AutoSize | Out-String)
        $lines += '=== Get-PrinterDriver ==='
        $lines += (Get-PrinterDriver | Format-Table Name, Manufacturer -AutoSize | Out-String)
        $lines | Set-Content -Path $txt -Encoding UTF8
    } catch {}
    # Full printer migration backup when PrintBrm is available (Pro and up)
    $brm = Join-Path $env:SystemRoot 'System32\spool\tools\PrintBrm.exe'
    if (Test-Path $brm) {
        $rc = FP-Run $brm ("-B -F `"{0}`"" -f (Join-Path $dir 'printers.printerExport')) -Quiet
        if ($rc -ne 0) { FP-Log 'PrintBrm export that bai (bo qua, da co .reg + snapshot)' 'RUN' }
    }
    if (-not $Quiet) { FP-OK 'Backup truoc khi sua' "$okCount/$($keys.Count) key da export vao backup\$stamp" }
    FP-Log "Backup dir: $dir" 'INFO'
    return $dir
}

function FP-TestAdmin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}
