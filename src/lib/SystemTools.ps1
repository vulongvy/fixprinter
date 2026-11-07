# FixPrinter v13 - SystemTools.ps1
# Heavier system tools kept apart from the print fixes: DISM/SFC, network
# stack reset, undo (restore a timestamped backup). Each is confirm-gated.

function FP-DismSfc {
    FP-Warn 'DISM + SFC co the chay 10-40 phut. Dung tat cua so nay giua chung.'
    if (-not (FP-Confirm 'Chay DISM /RestoreHealth + SFC /scannow ngay?')) { FP-SKIP 'DISM+SFC' 'nguoi dung huy'; return }
    FP-Step 'DISM /Online /Cleanup-Image /RestoreHealth' {
        $rc = FP-Run 'DISM.exe' '/Online /Cleanup-Image /RestoreHealth'
        return ($rc -eq 0)
    }
    FP-Step 'SFC /scannow' {
        $rc = FP-Run 'sfc.exe' '/scannow'
        # sfc exit codes are not a reliable verdict on their own; report honestly.
        FP-Log "    sfc exit code = $rc (0 = khong phat hien loi hoac da sua; xem log o tren)" 'INFO'
        return ($rc -eq 0)
    }
}

function FP-StackReset {
    FP-Warn 'Reset winsock + TCP/IP stack: cac cau hinh mang tuy bien (proxy phan mem, VPN ao) co the phai cai lai. PHAI khoi dong lai may sau buoc nay.'
    if (-not (FP-ConfirmTyped 'Van muon reset network stack?' 'RESET')) { FP-SKIP 'Reset network stack' 'nguoi dung khong xac nhan'; return }
    FP-Step 'netsh winsock reset' { return ((FP-Run 'netsh.exe' 'winsock reset') -eq 0) }
    FP-Step 'netsh int ip reset' { return ((FP-Run 'netsh.exe' 'int ip reset') -eq 0) }
    FP-Step 'ipconfig /release + /renew + /flushdns' {
        [void](FP-Run 'ipconfig.exe' '/release' -Quiet)
        [void](FP-Run 'ipconfig.exe' '/renew' -Quiet)
        return ((FP-Run 'ipconfig.exe' '/flushdns' -Quiet) -eq 0)
    }
    FP-Warn 'Xong. KHOI DONG LAI MAY ngay de stack moi co hieu luc, roi chay lai Diagnose (menu 2).'
}

function FP-UndoRestore {
    if (-not (Test-Path $script:FPBackupRoot)) { FP-SKIP 'Undo' 'chua co thu muc backup nao'; return }
    $dirs = @(Get-ChildItem -Path $script:FPBackupRoot -Directory | Where-Object { $_.Name -match '^\d{8}_\d{6}$' } | Sort-Object Name -Descending)
    if ($dirs.Count -eq 0) { FP-SKIP 'Undo' 'khong co ban backup nao (chi co thu muc drivers_* hoac rong)'; return }
    Write-Host 'Cac ban backup registry theo thoi gian (moi nhat truoc):'
    for ($i = 0; $i -lt $dirs.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $dirs[$i].Name) }
    $sel = Read-Host 'Chon so ban backup muon khoi phuc (Enter = huy)'
    if (-not $sel) { FP-SKIP 'Undo' 'nguoi dung huy'; return }
    $idx = 0
    if (-not [int]::TryParse($sel, [ref]$idx) -or $idx -lt 1 -or $idx -gt $dirs.Count) { FP-FAIL 'Undo' 'lua chon khong hop le'; return }
    $dir = $dirs[$idx - 1].FullName
    $regs = @(Get-ChildItem -Path $dir -Filter '*.reg')
    FP-Log "Se import $($regs.Count) file .reg tu $dir" 'INFO'
    if (-not (FP-Confirm 'Tiep tuc khoi phuc?')) { FP-SKIP 'Undo' 'nguoi dung huy'; return }
    foreach ($r in $regs) {
        FP-Step "Import $($r.Name)" {
            $rc = FP-Run 'reg.exe' ("import `"{0}`"" -f $r.FullName)
            return ($rc -eq 0)
        }
    }
    FP-Info 'Da khoi phuc registry. Voi SMB bang cmdlet (guest/signing), gia tri trong .reg cua LanmanWorkstation se ghi de o lan doc cau hinh tiep theo; chac chan nhat: KHOI DONG LAI MAY roi chay Diagnose de doi chieu.'
}
