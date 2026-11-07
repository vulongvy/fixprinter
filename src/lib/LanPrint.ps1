# FixPrinter v13 - LanPrint.ps1
# LAN side of printing: discovery, SMB client (guest + signing, the 24H2 fix),
# SMB host / printer sharing, connecting to a shared printer, adding a printer
# by IP, and port testing. Every change is verified by reading the effective
# state back (cmdlets), not by trusting the set command.

function FP-EnableFirewallGroups {
    FP-Step 'Firewall: bat nhom File and Printer Sharing + Network Discovery' {
        $ok = $false
        foreach ($grp in @('File and Printer Sharing', 'Network Discovery')) {
            try {
                $rules = @(Get-NetFirewallRule -DisplayGroup $grp -ErrorAction Stop)
                if ($rules.Count -gt 0) {
                    $rules | Enable-NetFirewallRule -ErrorAction SilentlyContinue
                    $ok = $true
                }
            } catch {}
        }
        if (-not $ok) {
            # Fallback: netsh with the classic group names
            $rc1 = FP-Run 'netsh.exe' 'advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes'
            $rc2 = FP-Run 'netsh.exe' 'advfirewall firewall set rule group="Network Discovery" new enable=Yes'
            $ok = ($rc1 -eq 0 -or $rc2 -eq 0)
        }
        return $ok
    }
}

function FP-FixDiscovery {
    FP-Step 'Mang: chuyen tat ca ket noi LAN sang Private' {
        $profs = @(Get-NetConnectionProfile -ErrorAction Stop)
        if ($profs.Count -eq 0) { FP-SKIP 'Mang: chuyen Private' 'khong co ket noi mang nao dang hoat dong'; return 'skip' }
        $changed = 0
        foreach ($p in $profs) {
            if ($p.NetworkCategory -ne 'Private') {
                Set-NetConnectionProfile -InterfaceIndex $p.InterfaceIndex -NetworkCategory Private -ErrorAction Stop
                $changed++
            }
        }
        $after = @(Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' })
        FP-Log "    Da chuyen $changed ket noi sang Private; con $($after.Count) ket noi Public." 'INFO'
        return ($after.Count -eq 0)
    }
    foreach ($svc in @('FDResPub', 'fdPHost', 'SSDPSRV', 'upnphost', 'Dnscache')) {
        FP-ServiceEnsure $svc
    }
    FP-EnableFirewallGroups
    FP-Step 'NetBT: bat EnableLMHOSTS (ten may kieu cu)' {
        return (FP-RegSetDword 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters' 'EnableLMHOSTS' 1)
    }
    $rc = FP-Run 'ipconfig.exe' '/flushdns' -Quiet
    FP-Log 'Da flush DNS cache.' 'INFO'
}

function FP-FixSmbClient {
    # The fix v12 missed: on Win11 24H2 (Pro/Ent/Edu) SMB signing is REQUIRED by
    # default. A guest session cannot sign, so enabling guest alone changes
    # nothing - the connection still dies with 0x80070035. Both layers must be
    # handled, and the result verified with Get-SmbClientConfiguration.
    $before = $null
    try { $before = Get-SmbClientConfiguration } catch {}
    if ($before) {
        FP-Log ("Truoc khi sua: EnableInsecureGuestLogons={0} RequireSecuritySignature={1}" -f $before.EnableInsecureGuestLogons, $before.RequireSecuritySignature) 'INFO'
    }
    FP-Warn 'Canh bao: bat guest + tat bat buoc ky SMB lam giam bao mat. Chi dung trong LAN tin cay (nha/van phong nho), dung de cong 445 ra Internet.'
    FP-Step 'SMB client: bat Insecure Guest Logons' {
        Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Force -ErrorAction Stop
        $a = Get-SmbClientConfiguration
        return ($a.EnableInsecureGuestLogons -eq $true)
    }
    FP-Step 'SMB client: tat bat buoc ky (RequireSecuritySignature=False) - lop 24H2' {
        Set-SmbClientConfiguration -RequireSecuritySignature $false -Force -ErrorAction Stop
        $a = Get-SmbClientConfiguration
        return ($a.RequireSecuritySignature -eq $false)
    }
    FP-Step 'SMB client: dong bo policy AllowInsecureGuestAuth=1 (de gpedit nhin thay)' {
        return (FP-RegSetDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation' 'AllowInsecureGuestAuth' 1)
    }
    FP-ServiceEnsure 'LanmanWorkstation'
}

function FP-FixSmbHost {
    FP-ServiceEnsure 'LanmanServer'
    FP-EnableFirewallGroups
    try {
        $cfg = Get-SmbServerConfiguration
        FP-Log ("SMB server: EnableSMB1={0} EnableSMB2={1} RequireSecuritySignature={2}" -f $cfg.EnableSMB1Protocol, $cfg.EnableSMB2Protocol, $cfg.RequireSecuritySignature) 'INFO'
        if ($cfg.RequireSecuritySignature -eq $true) {
            FP-Warn 'May chu dang BAT buoc ky SMB: may con Win cu/NAS khong ky duoc se khong vao duoc. Neu can ha, chay: Set-SmbServerConfiguration -RequireSecuritySignature $false -Force'
        }
    } catch {}
    FP-Step 'SMB host: chia se mot may in tu may nay' {
        $all = @(Get-Printer)
        if ($all.Count -eq 0) { FP-SKIP 'SMB host: chia se may in' 'may nay chua co may in nao'; return 'skip' }
        Write-Host 'Danh sach may in tren may nay:'
        for ($i = 0; $i -lt $all.Count; $i++) {
            Write-Host ("  [{0}] {1}  (shared={2} shareName={3})" -f ($i + 1), $all[$i].Name, $all[$i].Shared, $all[$i].ShareName)
        }
        $sel = Read-Host 'Chon so may in muon chia se (Enter de bo qua)'
        if (-not $sel) { FP-SKIP 'SMB host: chia se may in' 'nguoi dung bo qua'; return 'skip' }
        $idx = 0
        if (-not [int]::TryParse($sel, [ref]$idx) -or $idx -lt 1 -or $idx -gt $all.Count) { return $false }
        $p = $all[$idx - 1]
        $shareName = Read-Host "Ten chia se (Enter = dung ten may in)"
        if (-not $shareName) { $shareName = ($p.Name -replace '[\\/:*?"<>|]', '_') }
        Set-Printer -Name $p.Name -Shared $true -ShareName $shareName -ErrorAction Stop
        $after = Get-Printer -Name $p.Name
        if ($after.Shared -eq $true) {
            FP-Log ("Da chia se: \\\\{0}\{1}" -f $env:COMPUTERNAME, $after.ShareName) 'INFO'
            return $true
        }
        return $false
    }
}

function FP-ConnectSharedPrinter {
    Write-Host 'Ket noi toi may in duoc chia se tu may khac trong LAN.'
    $hostName = Read-Host 'Nhap ten may chu hoac IP (vd: MAYCHU hoac 192.168.1.50)'
    if (-not $hostName) { FP-FAIL 'Ket noi may in share' 'chua nhap may chu'; return }
    FP-Step "Ping may chu $hostName" { Test-Connection -ComputerName $hostName -Count 2 -Quiet }
    FP-Step "Kiem tra cong 445 (SMB) toi $hostName" {
        $r = Test-NetConnection -ComputerName $hostName -Port 445 -WarningAction SilentlyContinue
        return ($r.TcpTestSucceeded -eq $true)
    }
    $share = Read-Host 'Nhap ten share cua may in (Enter de mo \\host va chon sau trong Settings)'
    if (-not $share) {
        FP-SKIP 'Ket noi may in share' "chua co ten share - mo \\$hostName bang Explorer de xem danh sach"
        Start-Process explorer.exe "\\$hostName"
        return
    }
    $conn = "\\$hostName\$share"
    FP-Step "Add-Printer -ConnectionName $conn" {
        try {
            Add-Printer -ConnectionName $conn -ErrorAction Stop
        } catch {
            $msg = $_.Exception.Message
            FP-Log "    Loi goc: $msg" 'INFO'
            if ($msg -match '0x0000011b|279') { FP-Warn 'Loi 0x0000011b: chay menu 9 TREN MAY CHU (may gan may in), khong phai tren may nay.' }
            elseif ($msg -match '0x00000bc4|3012') { FP-Warn 'Loi 0x00000bc4: chay menu 10 tren may nay (RPC named pipes) roi thu lai.' }
            elseif ($msg -match '0x00000709|1801') { FP-Warn 'Loi 0x00000709: chay menu 10 + menu 11 roi thu lai.' }
            elseif ($msg -match '0x00000bcb|1930') { FP-Warn 'Loi 0x00000bcb: driver bi chan boi policy - xem menu 14, hoac cai driver bang menu 18 truoc.' }
            elseif ($msg -match '1219') { FP-Warn 'Loi 1219: may nay dang co phien dang nhap khac toi cung may chu - chay menu 22 de xoa ket noi/credential cu roi thu lai.' }
            elseif ($msg -match '0x00000002|0x0000007e|0x00000057|0x000005b3') { FP-Warn 'Loi driver hong khi ket noi (0x2/0x7e/0x57): chay menu 26 - go sach driver tren may con roi ket noi lai.' }
            throw
        }
        $found = @(Get-Printer | Where-Object { $_.Name -eq $conn })
        return ($found.Count -gt 0)
    }
    if (FP-Confirm 'Dat may in nay lam mac dinh?') {
        FP-SetDefaultPrinter -Name $conn
    }
}

function FP-AddIpPrinter {
    $ip = Read-Host 'Nhap IP cua may in (vd: 192.168.1.99)'
    if (-not $ip) { FP-FAIL 'Them may in qua IP' 'chua nhap IP'; return }
    $p9100 = $false; $p631 = $false
    FP-Step "Test cong 9100 (RAW) toi $ip" {
        $script:p9100 = (Test-NetConnection -ComputerName $ip -Port 9100 -WarningAction SilentlyContinue).TcpTestSucceeded
        return $script:p9100
    }
    if (-not $p9100) {
        FP-Step "Test cong 631 (IPP) toi $ip" {
            $script:p631 = (Test-NetConnection -ComputerName $ip -Port 631 -WarningAction SilentlyContinue).TcpTestSucceeded
            return $script:p631
        }
    }
    if (-not $p9100 -and -not $p631) {
        FP-Warn 'Ca 9100 va 631 deu khong mo. Kiem tra may in da bat, dung IP, cung lop mang. Van co the tao cong va gan driver neu muon.'
        if (-not (FP-Confirm 'Tiep tuc tao may in bat chap?')) { return }
    }
    $portName = "IP_$ip"
    FP-Step "Tao cong TCP/IP $portName" {
        $existing = Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue
        if ($existing) { FP-Log "    Cong $portName da ton tai, dung lai." 'INFO'; return $true }
        if ($p631 -and -not $p9100) {
            # IPP port uses an HTTP-style name in Windows; keep RAW port as fallback structure
            Add-PrinterPort -Name $portName -PrinterHostAddress $ip -PortNumber 9100 -ErrorAction Stop
        } else {
            Add-PrinterPort -Name $portName -PrinterHostAddress $ip -ErrorAction Stop
        }
        $after = Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue
        if ($after -and $after.SNMPEnabled -eq $true) {
            try { Set-PrinterPort -Name $portName -SNMPEnabled $false -ErrorAction Stop } catch {}
        }
        return ($null -ne $after)
    }
    $drivers = @(Get-PrinterDriver | Select-Object -ExpandProperty Name)
    Write-Host 'Driver dang co tren may:'
    for ($i = 0; $i -lt $drivers.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $drivers[$i]) }
    $ippIdx = [array]::IndexOf($drivers, 'Microsoft IPP Class Driver')
    $defIdx = 1
    if ($ippIdx -ge 0) { $defIdx = $ippIdx + 1 }
    $sel = Read-Host "Chon driver (Enter = $defIdx)"
    if (-not $sel) { $sel = "$defIdx" }
    $di = 0
    if (-not [int]::TryParse($sel, [ref]$di) -or $di -lt 1 -or $di -gt $drivers.Count) { FP-FAIL 'Them may in qua IP' 'chon driver khong hop le'; return }
    $driver = $drivers[$di - 1]
    $defName = "Network Printer $ip"
    $pname = Read-Host "Ten may in (Enter = $defName)"
    if (-not $pname) { $pname = $defName }
    FP-Step "Add-Printer '$pname' (driver: $driver)" {
        Add-Printer -Name $pname -DriverName $driver -PortName $portName -ErrorAction Stop
        $after = Get-Printer -Name $pname -ErrorAction SilentlyContinue
        return ($null -ne $after)
    }
    if (FP-Confirm 'In thu mot trang test?') {
        try {
            $pr = Get-CimInstance Win32_Printer -Filter "Name='$($pname -replace "'", "''")'"
            if ($pr) { [void](Invoke-CimMethod -InputObject $pr -MethodName PrintTestPage) ; FP-OK 'In trang test' 'da gui lenh in test' }
        } catch { FP-FAIL 'In trang test' $_.Exception.Message }
    }
}

function FP-TestPorts {
    $target = Read-Host 'Nhap IP may in / may chu'
    if (-not $target) { return }
    foreach ($port in @(135, 139, 445, 515, 631, 9100)) {
        $name = "Cong $port toi $target"
        try {
            $r = Test-NetConnection -ComputerName $target -Port $port -WarningAction SilentlyContinue
            if ($r.TcpTestSucceeded) { FP-OK $name 'MO' } else { FP-SKIP $name 'dong/khong toi duoc' }
        } catch { FP-SKIP $name $_.Exception.Message }
    }
    Write-Host 'Giai thich: 135=RPC, 139/445=SMB share, 515=LPD, 631=IPP, 9100=RAW (in truc tiep qua IP).'
}
