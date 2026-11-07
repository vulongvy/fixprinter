# FixPrinter v13.1 - ExtraFixes.ps1
# Fixes added in v13.1 from field research (Nov 2026):
#  - Spooler error 1068: dead third-party dependencies (LexBce etc.) left in
#    DependOnService after the vendor software was uninstalled.
#  - Error 1219 + stale cached credentials: old printer connections and saved
#    SMB credentials pointing at the same print host with another account.
#  - Windows Ready Print driver ranking (Win11, default ON since Jul 2026):
#    new installs silently get Microsoft IPP Class Driver instead of the
#    vendor driver, losing trays/finishing/secure print. Policy value
#    ConfigureWindowsReadyPrintDriverRanking (DWORD, 1=prefer IPP, 0=off)
#    under HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers
#    (Microsoft Learn, Printers Policy CSP; applies 24H2 KB5095093+ / 25H2 / 26H2).
#  - USB multifunction printers losing scanner/fax after KB5079473
#    (Mar 2026, IPP-over-USB, Microsoft-confirmed, no full fix yet) and the
#    older "POST /ipp/print" garbage-print bug (fixed by KB5053657+).
#  - Connect errors 0x00000002 / 0x00000057 / 0x000005b3 (damaged driver copy
#    on the client) and 0x0000007e on the HOST (driver CopyFiles\ICM|BIDI).

# ---------------- Spooler 1068: dependency audit ----------------------------

function FP-FixSpoolerDeps {
    param([switch]$Auto)
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\Spooler'
    $deps = @()
    try { $deps = @((Get-ItemProperty -Path $key -Name DependOnService -ErrorAction Stop).DependOnService) } catch {}
    if ($deps.Count -eq 0) {
        FP-OK 'Spooler dependencies' 'khong khai bao dependency nao (khac thuong, nhung RPCSS van duoc dung mac dinh)'
        return
    }
    $dead = @()
    foreach ($d in $deps) {
        if ($d -in @('RPCSS', 'HTTP')) { continue }
        $exists = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\$d"
        if (-not $exists) { $dead += $d }
    }
    FP-Log ("    DependOnService hien tai: " + ($deps -join ', ')) 'INFO'
    if ($dead.Count -eq 0) {
        FP-OK 'Spooler dependencies' 'khong co dependency chet'
        return
    }
    FP-Warn ("Phat hien dependency CHET (service da bi go nhung van nam trong danh sach): " + ($dead -join ', ') + ' -> day la nguyen nhan loi 1068, Spooler khong start duoc.')
    $do = $Auto
    if (-not $Auto) { $do = FP-Confirm 'Dat lai dependency cua Spooler ve mac dinh RPCSS/HTTP?' }
    if (-not $do) { FP-SKIP 'Reset Spooler dependency' 'nguoi dung huy - loi 1068 se con neu Spooler khong start'; return }
    FP-Step 'Spooler: reset dependency ve RPCSS/HTTP (sc config)' {
        $rc = FP-Run 'sc.exe' 'config Spooler depend= RPCSS/HTTP'
        if ($rc -ne 0) { return $false }
        $after = @((Get-ItemProperty -Path $key -Name DependOnService -ErrorAction Stop).DependOnService)
        foreach ($d in $dead) { if ($after -contains $d) { return $false } }
        return $true
    }
}

# ---------------- 1219 + stale connections / credentials --------------------

function FP-ClearStaleConnections {
    Write-Host 'Muc nay xu ly: loi 1219 (mot may chu, hai tai khoan), ket noi may in share cu bi ket, credential SMB cu sai mat khau.'
    $server = Read-Host 'Nhap ten/IP may chu muon lam sach (Enter = xem tat ca)'

    # A) Printer connections (per-user)
    $connKey = 'HKCU:\Printers\Connections'
    $subs = @()
    if (Test-Path $connKey) { $subs = @(Get-ChildItem $connKey -ErrorAction SilentlyContinue) }
    if ($subs.Count -eq 0) { FP-SKIP 'Ket noi may in share da luu' 'khong co ket noi nao trong HKCU\Printers\Connections' }
    else {
        Write-Host 'Ket noi may in share dang luu:'
        $names = @()
        for ($i = 0; $i -lt $subs.Count; $i++) {
            $raw = $subs[$i].PSChildName
            $friendly = ($raw -replace '^,,', '\\') -replace ',', '\'
            $names += $friendly
            Write-Host ("  [{0}] {1}" -f ($i + 1), $friendly)
        }
        $pick = Read-Host 'Nhap so can xoa, cach nhau bang dau phay, hoac go "all" (Enter = bo qua muc nay)'
        if ($pick) {
            $idxs = @()
            if ($pick.Trim().ToLower() -eq 'all') { $idxs = 1..$subs.Count }
            else { foreach ($t in ($pick -split ',')) { $n = 0; if ([int]::TryParse($t.Trim(), [ref]$n)) { $idxs += $n } } }
            $removed = 0; $needRestart = $false
            foreach ($n in $idxs) {
                if ($n -lt 1 -or $n -gt $subs.Count) { continue }
                $friendly = $names[$n - 1]
                try { Remove-Printer -Name $friendly -ErrorAction Stop } catch {}
                $still = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $friendly })
                if ($still.Count -gt 0) {
                    try { Remove-Item -Path $subs[$n - 1].PSPath -Recurse -Force -ErrorAction Stop; $needRestart = $true } catch {}
                    $still = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $friendly })
                }
                if ($still.Count -eq 0) { $removed++; FP-Log "    Da xoa ket noi: $friendly" 'INFO' }
                else { FP-Warn "    Chua xoa duoc ket noi: $friendly" }
            }
            if ($needRestart) { [void](FP-RestartSpooler) }
            if ($removed -gt 0) { FP-OK 'Xoa ket noi may in share cu' "da xoa $removed ket noi" } else { FP-FAIL 'Xoa ket noi may in share cu' 'khong xoa duoc ket noi nao da chon' }
        } else { FP-SKIP 'Xoa ket noi may in share cu' 'nguoi dung bo qua' }
    }

    # B) Cached SMB credentials (cmdkey)
    $targets = @()
    try {
        $lines = & cmdkey.exe /list 2>$null
        foreach ($l in $lines) { if ($l -match 'Target:\s*(.+)$') { $targets += $Matches[1].Trim() } }
    } catch {}
    if ($targets.Count -eq 0) { FP-SKIP 'Credential SMB da luu (cmdkey)' 'khong co credential nao dang luu' }
    else {
        FP-Log ("    Credential dang luu: " + ($targets -join ' | ')) 'INFO'
        if (-not $server) { FP-SKIP 'Xoa credential cu' 'chua nhap ten may chu - chi liet ke, khong xoa (tranh xoa nham credential khac)' }
        else {
            $hits = @($targets | Where-Object { $_ -match [regex]::Escape($server) })
            if ($hits.Count -eq 0) { FP-SKIP 'Xoa credential cu' "khong co credential nao khop voi may chu $server" }
            elseif (FP-Confirm "Xoa $($hits.Count) credential cua may $server ?") {
                foreach ($t in $hits) { [void](FP-Run 'cmdkey.exe' "/delete:$t") }
                FP-OK 'Xoa credential cu' "da xoa $($hits.Count) muc cua $server - ket noi lai se hoi/mat khau dung"
            } else { FP-SKIP 'Xoa credential cu' 'nguoi dung huy' }
        }
    }

    # C) net use sessions
    FP-Step 'Liet ke phien net use hien tai' { $rc = FP-Run 'net.exe' 'use'; return ($rc -eq 0) }
    if (FP-Confirm 'Xoa TOAN BO phien net use (ke ca o dia mang dang map)? Chi lam khi dang bi 1219') {
        FP-Step 'net use * /delete /y' { $rc = FP-Run 'net.exe' 'use * /delete /y'; return ($rc -eq 0) }
    } else { FP-SKIP 'Xoa phien net use' 'nguoi dung huy' }
}

# ---------------- Windows Ready Print driver ranking ------------------------

function FP-FixReadyPrint {
    $polKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers'
    $cur = FP-RegGet $polKey 'ConfigureWindowsReadyPrintDriverRanking'
    $ippCount = 0
    try { $ippCount = @(Get-Printer | Where-Object { $_.DriverName -eq 'Microsoft IPP Class Driver' }).Count } catch {}
    FP-Log "    Policy ConfigureWindowsReadyPrintDriverRanking = $cur (trong = khong khoa, Windows tu mac dinh BAT tu 07/2026; 1 = uu tien IPP; 0 = tat uu tien)" 'INFO'
    FP-Log "    So may in dang chay driver Microsoft IPP Class Driver: $ippCount" 'INFO'
    FP-Warn 'Tu 01/07/2026, khi CAI MOI may in co IPP (qua USB hoac tim thay trong mang), Windows uu tien driver Microsoft IPP thay vi driver hang -> mat khay giay phu, finisher, in bao mat, ma ke toan. May in da cai san khong bi doi.'
    Write-Host '  [1] TAT uu tien IPP (policy=0) - cai moi se lay driver hang neu co'
    Write-Host '  [2] BAT uu tien IPP (policy=1) - khoa theo huong bao mat cua Microsoft'
    Write-Host '  [0] Thoat, khong doi'
    $c = Read-Host 'Chon'
    if ($c -eq '1') {
        FP-Step 'Ready Print: tat uu tien IPP (ConfigureWindowsReadyPrintDriverRanking=0)' {
            return (FP-RegSetDword $polKey 'ConfigureWindowsReadyPrintDriverRanking' 0)
        }
        FP-Info 'Luu y: chi co tac dung voi may in cai TU BAY GIO. May in nao da bi gan driver IPP thi go ra cai lai (menu 18) hoac doi driver trong Printer properties.'
    } elseif ($c -eq '2') {
        FP-Step 'Ready Print: bat uu tien IPP (ConfigureWindowsReadyPrintDriverRanking=1)' {
            return (FP-RegSetDword $polKey 'ConfigureWindowsReadyPrintDriverRanking' 1)
        }
    } else { FP-SKIP 'Ready Print ranking' 'nguoi dung khong doi' }
}

# ---------------- USB multifunction (scan/fax) assistant -------------------

function FP-FixUsbMfp {
    FP-Info 'Trieu chung muc nay xu ly: may in USB da chuc nang in duoc nhung MAT scan/fax, hoac in ra trang chua chu "POST /ipp/print HTTP/1.1".'
    $kb = $null
    try { $kb = Get-HotFix -Id 'KB5079473' -ErrorAction Stop } catch {}
    if ($kb) {
        FP-Warn 'May nay co KB5079473 (03/2026) - Microsoft da xac nhan ban nay lam mot so may in USB IPP mat scan/fax va driver scan khong cai duoc. Tinh den 07/2026 Microsoft CHUA co ban va triet de; workaround chinh thuc: go may in khoi Settings, rut cap USB, cam lai (co may phai lam 2-3 lan).'
    } else {
        FP-Info 'Khong thay KB5079473 trong danh sach update (ban sau co the da gom no - van ap dung cac buoc duoi neu dung trieu chung).'
    }
    FP-ServiceEnsure 'stisvc'
    $usbPrinters = @()
    try { $usbPrinters = @(Get-Printer | Where-Object { $_.PortName -like 'USB*' }) } catch {}
    if ($usbPrinters.Count -eq 0) { FP-SKIP 'Liet ke may in USB' 'khong co may in nao o cong USB' }
    else {
        foreach ($p in $usbPrinters) { FP-Log "    USB: $($p.Name) | driver=$($p.DriverName) | port=$($p.PortName)" 'INFO' }
        FP-OK 'Liet ke may in USB' "$($usbPrinters.Count) may in USB"
    }
    FP-Info 'Cac buoc tay nen lam theo thu tu: 1) Settings > Printers: Remove may in. 2) Rut cap USB, doi 10 giay, cam sang cong USB KHAC (sau lung may). 3) Mo lai may in, Windows tu nhan lai. 4) Van in ra chu POST/ipp: chay Windows Update len ban moi nhat (loi nay da va tu KB5053657 - 03/2025) hoac tat IPP trong trang web cua may in (mat AirPrint).'
}

# ---------------- Connect errors 0x2 / 0x57 / 0x5b3 (client) + 0x7e (host) ---

function FP-FixConnectErrors {
    Write-Host 'Muc nay xu ly: 0x00000002 / 0x00000057 / 0x000005b3 khi ket noi may in share (ban sao driver tren MAY CON bi hong), va 0x0000007e phia MAY CHU (driver khai bao CopyFiles lac).'
    $role = Read-Host 'May nay la may CON dang ket noi (go 1) hay may CHU dang share may in (go 2)?'
    if ($role -eq '2') { FP-Fix7eHost; return }
    if ($role -ne '1') { FP-SKIP 'Fix loi ket noi 0x2/0x7e' 'chua chon vai tro may'; return }

    $conn = Read-Host 'Nhap duong dan may in share dang loi (dang \\MAYCHU\TenShare)'
    if (-not $conn) { FP-FAIL 'Fix loi ket noi 0x2/0x7e' 'chua nhap duong dan share'; return }

    $script:fpConnErr = $null
    $errMsg = ''
    FP-Step "Thu ket noi $conn (lan 1)" {
        try { Add-Printer -ConnectionName $conn -ErrorAction Stop }
        catch { $script:fpConnErr = $_.Exception.Message; throw }
        $found = @(Get-Printer | Where-Object { $_.Name -eq $conn })
        return ($found.Count -gt 0)
    }
    if ($script:FPPass -gt 0) { FP-Info 'Ket noi duoc ngay - khong can sua tiep.'; return }
    $errMsg = $script:fpConnErr
    $script:fpConnErr = $null
    FP-Log "    Loi goc: $errMsg" 'INFO'

    if ($errMsg -match '0x0000011b') { FP-Warn 'Day la 0x0000011b - sua tren MAY CHU bang menu 9, khong phai o may nay.'; return }
    if ($errMsg -match '0x00000bc4') { FP-Warn 'Day la 0x00000bc4 - chay menu 10 tren may nay roi thu lai.'; return }
    if ($errMsg -match '0x00000709') { FP-Warn 'Day la 0x00000709 - chay menu 10 + 11 roi thu lai.'; return }
    if ($errMsg -match '0x00000bcb') { FP-Warn 'Day la 0x00000bcb - xem menu 14 hoac cai san driver bang menu 18.'; return }
    if ($errMsg -notmatch '0x00000002|0x0000007e|0x000005b3|0x00000057|0x80070705') {
        FP-Warn 'Ma loi nay khong nam trong nhom driver hong (0x2/0x7e/0x57/0x5b3). Xem lai Diagnose (menu 2) va log PrintService trong Event Viewer.'
        return
    }

    FP-Warn 'Dung nhom loi driver hong tren may con: can GO SACH driver cua may in nay roi ket noi lai de Windows tai ban moi.'
    FP-Step "Go ket noi cu $conn (neu con sot)" {
        try { Remove-Printer -Name $conn -ErrorAction Stop } catch {}
        $still = @(Get-Printer | Where-Object { $_.Name -eq $conn })
        return ($still.Count -eq 0)
    }
    $drivers = @(Get-PrinterDriver | Select-Object -ExpandProperty Name)
    if ($drivers.Count -eq 0) { FP-SKIP 'Go driver hong' 'may chua co driver nao'; return }
    Write-Host 'Driver dang co tren may con - chon dung driver cua may in dang loi:'
    for ($i = 0; $i -lt $drivers.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $drivers[$i]) }
    $sel = Read-Host 'Chon so driver can go sach (Enter = bo qua)'
    if (-not $sel) { FP-SKIP 'Go driver hong' 'nguoi dung bo qua'; return }
    $di = 0
    if (-not [int]::TryParse($sel, [ref]$di) -or $di -lt 1 -or $di -gt $drivers.Count) { FP-FAIL 'Go driver hong' 'chon khong hop le'; return }
    $drv = $drivers[$di - 1]
    FP-Step "Go driver '$drv' khoi may con" {
        Remove-PrinterDriver -Name $drv -ErrorAction Stop
        $still = @(Get-PrinterDriver | Where-Object { $_.Name -eq $drv })
        return ($still.Count -eq 0)
    }
    FP-Step 'Khoi dong lai Spooler sau khi go driver' { return (FP-RestartSpooler) }
    FP-Step "Ket noi lai $conn (lan 2)" {
        try { Add-Printer -ConnectionName $conn -ErrorAction Stop }
        catch { FP-Log "    Loi lan 2: $($_.Exception.Message)" 'INFO'; throw }
        $found = @(Get-Printer | Where-Object { $_.Name -eq $conn })
        return ($found.Count -gt 0)
    }
}

function FP-Fix7eHost {
    FP-Warn '0x0000007e phia may chu: driver khai bao muc CopyFiles (ICM/BIDI) tro toi file may con khong lay duoc. Cach tri pho bien (dac biet HP Universal): xoa muc CopyFiles trong registry cua driver TREN MAY CHU. Da co backup truoc trong thu muc backup cua tool.'
    $drivers = @(Get-PrinterDriver | Select-Object -ExpandProperty Name)
    if ($drivers.Count -eq 0) { FP-SKIP 'Fix 0x7e phia may chu' 'may nay chua co driver nao'; return }
    Write-Host 'Driver tren may chu:'
    for ($i = 0; $i -lt $drivers.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $drivers[$i]) }
    $sel = Read-Host 'Chon driver cua may in dang share gay loi 0x7e (Enter = huy)'
    if (-not $sel) { FP-SKIP 'Fix 0x7e phia may chu' 'nguoi dung huy'; return }
    $di = 0
    if (-not [int]::TryParse($sel, [ref]$di) -or $di -lt 1 -or $di -gt $drivers.Count) { FP-FAIL 'Fix 0x7e phia may chu' 'chon khong hop le'; return }
    $drv = $drivers[$di - 1]
    $bd = FP-BackupAll -Quiet
    $touched = 0
    foreach ($env in @('Windows x64', 'Windows NT x86')) {
        foreach ($ver in @('Version-3', 'Version-4')) {
            $drvKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\$env\Drivers\$ver\$drv"
            $cfKey = Join-Path $drvKey 'CopyFiles'
            if (-not (Test-Path $cfKey)) { continue }
            $subNames = @((Get-ChildItem $cfKey -ErrorAction SilentlyContinue).PSChildName)
            FP-Log "    Tim thay $cfKey (muc con: $($subNames -join ', '))" 'INFO'
            if (FP-Confirm "Xoa muc CopyFiles cua driver '$drv' ($env\$ver)?") {
                if ($bd) {
                    $safe = ($drv -replace '[\\/:*?"<>|]', '_')
                    [void](FP-Run 'reg.exe' ("export `"{0}`" `"{1}`" /y" -f ($drvKey -replace '^HKLM:', 'HKLM'), (Join-Path $bd "driver_$safe.reg")) -Quiet)
                }
                FP-Step "Xoa CopyFiles ($env\$ver) cua '$drv'" {
                    Remove-Item -Path $cfKey -Recurse -Force -ErrorAction Stop
                    return (-not (Test-Path $cfKey))
                }
                $touched++
            } else { FP-SKIP "Xoa CopyFiles ($env\$ver)" 'nguoi dung huy' }
        }
    }
    if ($touched -eq 0) { FP-SKIP 'Fix 0x7e phia may chu' "driver '$drv' khong co muc CopyFiles nao bi xoa - loi 0x7e o may nay co the do nguyen nhan khac (thieu file driver, sai kien truc 32/64)" }
    else {
        FP-Step 'Khoi dong lai Spooler phia may chu' { return (FP-RestartSpooler) }
        FP-Info 'Xong phia may chu. Sang may con: go ket noi cu (menu 22 neu bi ket) roi ket noi lai.'
    }
}
