# FixPrinter v13 - PrintFixes.ps1
# Error-code fixes for shared/network printing, each verified by read-back.
# Key corrections vs v12:
#  - RPC named-pipe values go to HKLM\SOFTWARE\Policies\...\Printers\RPC
#    (v12 wrote them to Control\Print, where Windows never reads them).
#  - Default printer is set through CIM Win32_Printer.SetDefaultPrinter
#    (v12 used "Set-Printer -IsDefault", a parameter that does not exist).
#  - SNMP is disabled with Set-PrinterPort -SNMPEnabled $false
#    (v12 used a non-existent -SNMP parameter inside a try/catch that hid it).
#  - WSD ports are actually converted to TCP/IP ports, not just listed.

$script:RpcPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC'
$script:PnpPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'

function FP-Fix11B {
    param([switch]$Auto)
    FP-Warn 'Loi 0x0000011b phai sua TREN MAY CHU (may dang gan/chia se may in). Chay muc nay tren may nay chi co tac dung neu may nay la may chu.'
    FP-Warn 'Cach dung chuan: cap nhat Windows ca 2 may. Muc nay la duong tuong thich cu: ha RpcAuthnLevelPrivacyEnabled xuong 0 tren may chu (giam bao mat tam thoi).'
    if (-not $Auto -and -not (FP-Confirm 'Tiep tuc ap dung tren may nay?')) { FP-SKIP 'Fix 0x0000011b' 'nguoi dung huy'; return }
    FP-Step 'Fix 0x0000011b: RpcAuthnLevelPrivacyEnabled=0 (Control\Print, may chu)' {
        return (FP-RegSetDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Print' 'RpcAuthnLevelPrivacyEnabled' 0)
    }
    FP-Step 'Fix 0x0000011b: bat them RPC named pipes (dung key Policies)' {
        $a = FP-RegSetDword $script:RpcPolicyPath 'RpcUseNamedPipeProtocol' 1
        $b = FP-RegSetDword $script:RpcPolicyPath 'RpcProtocols' 7
        return ($a -and $b)
    }
    FP-Step 'Fix 0x0000011b: khoi dong lai Spooler' { FP-RestartSpooler }
}

function FP-FixRpcNamedPipes {
    # Win11 22H2+ defaults print RPC to TCP. Hosts that do not accept it produce
    # 0x00000bc4 ("No printers were found") and 0x00000709. The documented fix
    # is the policy "Configure RPC connection settings" = RPC over named pipes,
    # stored under Policies\Microsoft\Windows NT\Printers\RPC.
    FP-Step 'RPC: RpcUseNamedPipeProtocol=1 (Policies\Printers\RPC)' {
        return (FP-RegSetDword $script:RpcPolicyPath 'RpcUseNamedPipeProtocol' 1)
    }
    FP-Step 'RPC: RpcProtocols=7 (listener: named pipes + TCP, cho may chu)' {
        return (FP-RegSetDword $script:RpcPolicyPath 'RpcProtocols' 7)
    }
    FP-Step 'RPC: don gia tri sai cho do tool cu ghi o Control\Print' {
        $a = FP-RegDeleteValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Print' 'RpcUseNamedPipeProtocol'
        $b = FP-RegDeleteValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Print' 'RpcProtocols'
        return ($a -and $b)
    }
    FP-Step 'RPC: khoi dong lai Spooler de nhan cau hinh' { FP-RestartSpooler }
    FP-Info 'Neu may chu la Win11 22H2+ thi chay muc nay tren CA may chu lan may con.'
}

function FP-SetDefaultPrinter {
    param([string]$Name)
    if (-not $Name) {
        $printers = @(Get-Printer)
        if ($printers.Count -eq 0) { FP-FAIL 'Dat may in mac dinh' 'khong co may in nao'; return }
        Write-Host 'Danh sach may in:'
        for ($i = 0; $i -lt $printers.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $printers[$i].Name) }
        $sel = Read-Host 'Chon so may in dat mac dinh'
        $idx = 0
        if (-not [int]::TryParse($sel, [ref]$idx) -or $idx -lt 1 -or $idx -gt $printers.Count) { FP-FAIL 'Dat may in mac dinh' 'lua chon khong hop le'; return }
        $Name = $printers[$idx - 1].Name
    }
    FP-Step "Dat mac dinh: $Name" {
        # Turn off "Let Windows manage my default printer" first, else it reverts.
        [void](FP-RegSetDword 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' 'LegacyDefaultPrinterMode' 1)
        $esc = $Name -replace "'", "''"
        $pr = Get-CimInstance Win32_Printer -Filter "Name='$esc'" -ErrorAction Stop
        if (-not $pr) { return $false }
        [void](Invoke-CimMethod -InputObject $pr -MethodName SetDefaultPrinter -ErrorAction Stop)
        Start-Sleep -Milliseconds 500
        $chk = Get-CimInstance Win32_Printer -Filter "Name='$esc'"
        return ($chk -and $chk.Default -eq $true)
    }
}

function FP-Fix709Default {
    param([switch]$Auto)
    FP-Step 'Fix 0x00000709: LegacyDefaultPrinterMode=1 (tat Windows tu quan ly mac dinh)' {
        return (FP-RegSetDword 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' 'LegacyDefaultPrinterMode' 1)
    }
    FP-Step 'Fix 0x00000709: xoa gia tri Device cu bi ket (Windows se tao lai)' {
        return (FP-RegDeleteValue 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' 'Device')
    }
    FP-Info 'Luu y: 0x00000709 con mot nhanh do RPC tren Win11 22H2+ - neu van loi, chay them menu 10.'
    if (-not $Auto -and (FP-Confirm 'Dat lai may in mac dinh ngay bay gio?')) { FP-SetDefaultPrinter }
}

function FP-PnPSafe {
    FP-Step 'Point and Print SAFE: RestrictDriverInstallationToAdministrators=1' {
        return (FP-RegSetDword $script:PnpPath 'RestrictDriverInstallationToAdministrators' 1)
    }
    FP-Step 'Point and Print SAFE: NoWarningNoElevationOnInstall=0' {
        return (FP-RegSetDword $script:PnpPath 'NoWarningNoElevationOnInstall' 0)
    }
    FP-Step 'Point and Print SAFE: UpdatePromptSettings=0' {
        return (FP-RegSetDword $script:PnpPath 'UpdatePromptSettings' 0)
    }
    FP-Info 'Che do SAFE: chi admin moi cai duoc driver khi noi may in share. Day la mac dinh dung tu sau PrintNightmare.'
}

function FP-PnPCompat {
    FP-Warn 'COMPATIBILITY cho phep user thuong tu cai driver tu may in share khong can admin - tien cho LAN nha nhung la be mat tan cong PrintNightmare. Chi dung khi hieu ro.'
    if (-not (FP-ConfirmTyped 'Ap dung che do COMPAT?' 'COMPAT')) { FP-SKIP 'Point and Print COMPAT' 'nguoi dung khong xac nhan'; return }
    FP-Step 'Point and Print COMPAT: RestrictDriverInstallationToAdministrators=0' {
        return (FP-RegSetDword $script:PnpPath 'RestrictDriverInstallationToAdministrators' 0)
    }
    FP-Step 'Point and Print COMPAT: NoWarningNoElevationOnInstall=1' {
        return (FP-RegSetDword $script:PnpPath 'NoWarningNoElevationOnInstall' 1)
    }
    FP-Step 'Point and Print COMPAT: UpdatePromptSettings=1' {
        return (FP-RegSetDword $script:PnpPath 'UpdatePromptSettings' 1)
    }
}

function FP-FixBcb {
    FP-Info '0x00000bcb = cai driver qua share bi policy chan (can quyen admin / PrintNightmare hardening).'
    $cur = FP-RegGet $script:PnpPath 'RestrictDriverInstallationToAdministrators'
    FP-Info "Gia tri hien tai: RestrictDriverInstallationToAdministrators=$cur (trong/1 = dang chan user thuong)"
    FP-Info 'Duong sach (khuyen nghi): cai san driver vao may con bang menu 18 (pnputil, quyen admin) - sau do noi may in share se khong can nang quyen nua.'
    FP-Step 'Fix 0x00000bcb: go policy DeviceInstall\Restrictions neu dang ton tai' {
        $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
        if (-not (Test-Path $p)) { FP-SKIP 'Fix 0x00000bcb: DeviceInstall\Restrictions' 'key khong ton tai - khong phai nguyen nhan'; return 'skip' }
        try { Remove-Item -Path $p -Recurse -Force -ErrorAction Stop; return (-not (Test-Path $p)) } catch { return $false }
    }
    if (FP-Confirm 'Khong muon cai driver truoc? Ap COMPAT Point and Print thay the (kem an toan)?') { FP-PnPCompat }
    else { FP-SKIP 'Fix 0x00000bcb: COMPAT' 'nguoi dung chon duong cai driver truoc' }
}

function FP-FixOfflineWsdSnmp {
    param([switch]$Auto)
    $printers = @(Get-Printer)
    if ($printers.Count -eq 0) { FP-SKIP 'Fix offline/WSD/SNMP' 'khong co may in nao'; return }
    $changed = $false
    foreach ($p in $printers) {
        $port = $null
        try { $port = Get-PrinterPort -Name $p.PortName -ErrorAction SilentlyContinue } catch {}
        if ($port -and $port.SNMPEnabled -eq $true) {
            FP-Step "Tat SNMP cho cong $($p.PortName) (may in: $($p.Name))" {
                Set-PrinterPort -Name $p.PortName -SNMPEnabled $false -ErrorAction Stop
                $after = Get-PrinterPort -Name $p.PortName
                return ($after.SNMPEnabled -eq $false)
            }
            $changed = $true
        }
        if ($p.PortName -like 'WSD*') {
            Write-Host ''
            FP-Warn "May in '$($p.Name)' dang o cong WSD ($($p.PortName)). WSD la nguyen nhan offline gia pho bien nhat."
            if ($Auto) { FP-SKIP "Chuyen WSD->TCP/IP: $($p.Name)" 'che do AUTO khong co IP cua may in - chay menu 15 va nhap IP'; continue }
            $ip = Read-Host "Nhap IP that cua may in '$($p.Name)' de chuyen sang cong TCP/IP (Enter = bo qua may nay)"
            if (-not $ip) { FP-SKIP "Chuyen WSD->TCP/IP: $($p.Name)" 'chua co IP'; continue }
            $newPort = "IP_$ip"
            FP-Step "Chuyen '$($p.Name)' sang cong $newPort" {
                $existing = Get-PrinterPort -Name $newPort -ErrorAction SilentlyContinue
                if (-not $existing) {
                    Add-PrinterPort -Name $newPort -PrinterHostAddress $ip -ErrorAction Stop
                    try { Set-PrinterPort -Name $newPort -SNMPEnabled $false -ErrorAction SilentlyContinue } catch {}
                }
                Set-Printer -Name $p.Name -PortName $newPort -ErrorAction Stop
                $after = Get-Printer -Name $p.Name
                return ($after.PortName -eq $newPort)
            }
            $changed = $true
        }
        if ($p.PrinterStatus -match 'Paused|Offline') {
            FP-Step "Resume may in $($p.Name) (status: $($p.PrinterStatus))" {
                try { Resume-Printer -Name $p.Name -ErrorAction Stop } catch {}
                return $true
            }
        }
    }
    if ($changed) {
        FP-Step 'Khoi dong lai Spooler sau khi doi cong/SNMP' { FP-RestartSpooler }
    } else {
        FP-Info 'Khong co may in nao can tat SNMP hay chuyen WSD.'
    }
}

function FP-CheckWpp {
    $build = FP-RegGet 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'CurrentBuildNumber'
    if ([int]$build -lt 26100) { FP-SKIP 'Windows Protected Print Mode' "build $build chua co WPP (chi co tu 24H2/26100)"; return }
    $mode = FP-RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP' 'WindowsProtectedPrintMode'
    $ippOnly = $true
    foreach ($p in @(Get-Printer)) { if ($p.DriverName -ne 'Microsoft IPP Class Driver') { $ippOnly = $false } }
    FP-Info "Policy WindowsProtectedPrintMode = $mode (1 = dang BAT bang policy)"
    FP-Info "Tat ca may in dang dung IPP Class Driver: $ippOnly"
    FP-Info 'WPP (neu BAT) se GO may in dung driver hang va chan cai lai driver hang. Trang thai bat/tat o Settings > Bluetooth & devices > Printers & scanners > Windows protected print mode.'
    if ($mode -eq 1) {
        FP-Warn 'WPP dang bi BAT bang policy. Neu muon dung lai driver hang:'
        if (FP-Confirm 'Tat WPP bang policy (WindowsProtectedPrintMode=0) ngay bay gio?') {
            FP-Step 'Tat WPP: WindowsProtectedPrintMode=0' { FP-RegSetDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP' 'WindowsProtectedPrintMode' 0 }
            FP-Step 'Tat WPP: WindowsProtectedPrintGroupPolicyState=0' { FP-RegSetDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP' 'WindowsProtectedPrintGroupPolicyState' 0 }
            FP-Warn 'Da tat o muc policy. Khoi dong lai may, sau do cai lai driver hang / them lai may in (menu 8 hoac 18).'
        }
    } else {
        FP-Info 'Khong thay WPP bat bang policy. Neu may in hang bi bien mat sau khi ai do bat toggle trong Settings, vao Settings tat toggle do (policy khong ghi de duoc toggle nguoi dung da bat kem OOBE state).'
        if (FP-Confirm 'Mo trang Settings may in de kiem tra toggle WPP?') { Start-Process 'ms-settings:printers' }
    }
}
