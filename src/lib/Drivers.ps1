# FixPrinter v13 - Drivers.ps1
# Driver work: hardware-ID report for problem devices, install from a folder
# with pnputil, export all installed drivers, and full printer+driver removal.

function FP-DriverMenu {
    Write-Host ''
    Write-Host '  DRIVERS'
    Write-Host '  [1] Quet thiet bi loi va xuat bao cao Hardware ID'
    Write-Host '  [2] Cai driver tu thu muc (pnputil /add-driver *.inf /subdirs /install)'
    Write-Host '  [3] Backup toan bo driver da cai (pnputil /export-driver)'
    Write-Host '  [4] Go mot may in + driver cua no (sach)'
    Write-Host '  [0] Quay lai'
    $c = Read-Host 'Chon'
    switch ($c) {
        '1' { FP-DriverHwIdReport }
        '2' { FP-DriverInstallFolder }
        '3' { FP-DriverExport }
        '4' { FP-RemovePrinterFull }
    }
}

function FP-DriverHwIdReport {
    FP-Step 'Xuat bao cao Hardware ID' {
        $report = Join-Path $script:FPRoot 'driver_hardware_id_report.txt'
        $devs = @(Get-PnpDevice | Where-Object { $_.Status -ne 'OK' -or $_.Problem -ne 0 })
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("Hardware ID report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $env:COMPUTERNAME")
        [void]$sb.AppendLine("Thiet bi loi/thieu driver: $($devs.Count)")
        foreach ($d in $devs) {
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('====')
            [void]$sb.AppendLine("Status=$($d.Status) Class=$($d.Class) Name=$($d.FriendlyName) InstanceId=$($d.InstanceId) Problem=$($d.Problem)")
            try {
                $ids = Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction Stop
                foreach ($id in @($ids.Data)) { [void]$sb.AppendLine("  HWID: $id") }
            } catch { [void]$sb.AppendLine('  HWID: (khong doc duoc)') }
        }
        $sb.ToString() | Set-Content -Path $report -Encoding UTF8
        FP-Log "    Bao cao: $report ($($devs.Count) thiet bi loi)" 'INFO'
        if ($devs.Count -eq 0) { FP-Log '    Khong co thiet bi loi - may sach driver.' 'INFO' }
        return (Test-Path $report)
    }
}

function FP-DriverInstallFolder {
    $folder = Read-Host 'Nhap duong dan thu muc chua driver (.inf)'
    if (-not $folder -or -not (Test-Path $folder)) { FP-FAIL 'Cai driver tu thu muc' "thu muc khong ton tai: $folder"; return }
    $infs = @(Get-ChildItem -Path $folder -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue)
    if ($infs.Count -eq 0) { FP-FAIL 'Cai driver tu thu muc' "khong thay file .inf nao trong $folder"; return }
    FP-Log "Tim thay $($infs.Count) file .inf. Dang cai bang pnputil..." 'INFO'
    FP-Step "pnputil /add-driver ($($infs.Count) inf)" {
        $rc = FP-Run 'pnputil.exe' ("/add-driver `"{0}\*.inf`" /subdirs /install" -f $folder)
        return ($rc -eq 0)
    }
}

function FP-DriverExport {
    FP-Step 'Export toan bo driver' {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $dest = Join-Path $script:FPBackupRoot "drivers_$stamp"
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        $rc = FP-Run 'pnputil.exe' ("/export-driver * `"{0}`"" -f $dest)
        if ($rc -eq 0) { FP-Log "    Driver da export vao: $dest" 'INFO' }
        return ($rc -eq 0)
    }
}

function FP-RemovePrinterFull {
    $printers = @(Get-Printer)
    if ($printers.Count -eq 0) { FP-FAIL 'Go may in' 'khong co may in nao'; return }
    Write-Host 'Danh sach may in:'
    for ($i = 0; $i -lt $printers.Count; $i++) { Write-Host ("  [{0}] {1} (driver: {2})" -f ($i + 1), $printers[$i].Name, $printers[$i].DriverName) }
    $sel = Read-Host 'Chon so may in muon GO'
    $idx = 0
    if (-not [int]::TryParse($sel, [ref]$idx) -or $idx -lt 1 -or $idx -gt $printers.Count) { FP-FAIL 'Go may in' 'lua chon khong hop le'; return }
    $p = $printers[$idx - 1]
    $driverName = $p.DriverName
    FP-Step "Remove-Printer: $($p.Name)" {
        Remove-Printer -Name $p.Name -ErrorAction Stop
        $after = Get-Printer -Name $p.Name -ErrorAction SilentlyContinue
        return ($null -eq $after)
    }
    $others = @(Get-Printer | Where-Object { $_.DriverName -eq $driverName })
    if ($others.Count -eq 0) {
        if (FP-Confirm "Khong con may in nao dung driver '$driverName'. Go ca driver khoi driver store?") {
            FP-Step "Remove-PrinterDriver: $driverName" {
                Remove-PrinterDriver -Name $driverName -ErrorAction Stop
                $after = Get-PrinterDriver -Name $driverName -ErrorAction SilentlyContinue
                return ($null -eq $after)
            }
        }
    } else {
        FP-SKIP "Remove-PrinterDriver: $driverName" "con $($others.Count) may in khac dang dung driver nay"
    }
    FP-Info 'Neu driver van con trong pnputil store va can go tan goc, dung Device Manager hoac: pnputil /enum-drivers roi /delete-driver oemXX.inf (can than: chi khi chac chan).'
}
