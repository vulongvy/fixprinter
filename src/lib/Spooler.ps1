# FixPrinter v13 - Spooler.ps1
# Spooler repair done right: set Automatic, configure service recovery ONCE
# (sc.exe failure actions), stop, clear the print queue folder, start, verify.
# No per-minute scheduled task like v12's Spooler Guard - the recovery config
# already restarts a crashed spooler, without 1440 hidden PowerShell runs/day.

function FP-RemoveOldGuard {
    # v12 left a scheduled task that relaunches PowerShell every 1 minute.
    $rc = FP-Run 'schtasks.exe' '/Query /TN "LAN_Printer_Spooler_Guard"' -Quiet
    if ($rc -eq 0) {
        $rc2 = FP-Run 'schtasks.exe' '/Delete /TN "LAN_Printer_Spooler_Guard" /F'
        if ($rc2 -eq 0) { FP-OK 'Go task Spooler Guard cua v12' 'task chay moi 1 phut da bi xoa; co che recovery cua Windows thay the' ; return $true }
        FP-FAIL 'Go task Spooler Guard cua v12' "schtasks delete tra ve $rc2"; return $false
    }
    FP-SKIP 'Go task Spooler Guard cua v12' 'khong thay task nay tren may'
    return 'skip'
}

function FP-FixSpooler {
    # FP-RemoveOldGuard tu bao PASS/FAIL/SKIP nen goi truc tiep, khong boc FP-Step
    [void](FP-RemoveOldGuard)

    # Dependency chet (LexBce cua Lexmark, RProcessWatcher cua Ricoh...) la
    # nguyen nhan loi 1068 - Spooler khong start duoc du reset bao nhieu lan.
    FP-FixSpoolerDeps -Auto

    FP-Step 'Spooler: dat Automatic' {
        $rc = FP-Run 'sc.exe' 'config Spooler start= auto'
        if ($rc -ne 0) { return $false }
        $v = FP-RegGet 'HKLM:\SYSTEM\CurrentControlSet\Services\Spooler' 'Start'
        return ($v -eq 2)
    }

    FP-Step 'Spooler: cau hinh tu khoi dong lai khi sap (sc failure)' {
        $rc = FP-Run 'sc.exe' 'failure Spooler reset= 60 actions= restart/60000/restart/60000/restart/60000'
        return ($rc -eq 0)
    }

    FP-Step 'Spooler: dung service' {
        try { Stop-Service -Name Spooler -Force -ErrorAction Stop } catch {
            $rc = FP-Run 'net.exe' 'stop spooler /y'
            if ($rc -ne 0) { return $false }
        }
        Start-Sleep -Seconds 1
        $s = Get-Service -Name Spooler
        return ($s.Status -eq 'Stopped')
    }

    FP-Step 'Spooler: xoa hang doi in bi ket (spool\PRINTERS)' {
        $dir = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'
        if (-not (Test-Path $dir)) { FP-SKIP 'Spooler: xoa hang doi in' "khong thay thu muc $dir"; return 'skip' }
        $files = @(Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue)
        if ($files.Count -eq 0) { FP-Log '    Hang doi dang rong, khong co file ket.' 'INFO'; return $true }
        $deleted = 0; $locked = @()
        foreach ($f in $files) {
            try { Remove-Item -Path $f.FullName -Force -ErrorAction Stop; $deleted++ }
            catch { $locked += $f.Name }
        }
        FP-Log "    Da xoa $deleted/$($files.Count) file trong $dir" 'INFO'
        if ($locked.Count -gt 0) { FP-Warn ("File bi khoa chua xoa duoc: " + ($locked -join ', ')) }
        return ($deleted -gt 0 -or $locked.Count -eq 0)
    }

    FP-Step 'Spooler: khoi dong lai va kiem tra' {
        try { Start-Service -Name Spooler -ErrorAction Stop } catch {
            $rc = FP-Run 'net.exe' 'start spooler'
            if ($rc -ne 0) { return $false }
        }
        Start-Sleep -Seconds 1
        $s = Get-Service -Name Spooler
        if ($s.Status -eq 'Running') { return $true }
        FP-FAIL 'Spooler: khoi dong lai' "trang thai sau khoi dong = $($s.Status)"
        return $false
    }
}
