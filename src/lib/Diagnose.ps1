# FixPrinter v13 - Diagnose.ps1
# Read-only report. Reads EFFECTIVE state (cmdlets), not just registry wishes.
# Every red flag is printed as [FLAG] so a tech can act on it directly.

function FP-Diagnose {
    $report = Join-Path $script:FPRoot 'diagnose_report_v13.txt'
    $out = New-Object System.Collections.Generic.List[string]
    $flags = New-Object System.Collections.Generic.List[string]
    function Add { param([string]$s) $out.Add($s); Write-Host $s }
    function Flag { param([string]$s) $flags.Add($s); Add "[FLAG] $s" }

    Add '============================================================'
    Add '  FIXPRINTER v13.2 - DIAGNOSE REPORT'
    Add ('  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "  |  Computer: $env:COMPUTERNAME  |  User: $env:USERNAME")
    Add '============================================================'

    # ---- OS ----
    $osName = FP-RegGet 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'ProductName'
    $build = FP-RegGet 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'CurrentBuildNumber'
    $ubr = FP-RegGet 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'UBR'
    Add ''
    Add "=== OS ==="
    Add "ProductName: $osName  Build: $build.$ubr"
    if ([int]$build -ge 26100) { Add 'Windows 11 24H2+ : SMB signing mac dinh BAT o Pro/Enterprise/Education (Home KHONG bi ep), guest SMB bi chan o Pro/Ent/Edu, co Windows Protected Print Mode va Windows Ready Print ranking.' }
    elseif ([int]$build -ge 22000) { Add 'Windows 11 (truoc 24H2).' }
    elseif ($osName -match 'Windows 10') { Flag 'Windows 10 da het ho tro tu 14/10/2025 - khong con ban va bao mat cho Print Spooler/SMB.' }

    # ---- Spooler ----
    Add ''
    Add '=== Print Spooler ==='
    $sp = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if ($sp) { Add "Spooler: Status=$($sp.Status) StartType=$($sp.StartType)" ; if ($sp.Status -ne 'Running') { Flag 'Spooler khong chay - khong in duoc bat ky may in nao.' } }
    else { Flag 'Khong thay service Spooler.' }
    $spStart = FP-RegGet 'HKLM:\SYSTEM\CurrentControlSet\Services\Spooler' 'Start'
    Add "Spooler registry Start=$spStart (2=Automatic)"

    # ---- Printers / Ports / Drivers ----
    Add ''
    Add '=== Printers ==='
    $printers = @()
    try { $printers = @(Get-Printer) } catch {}
    if ($printers.Count -eq 0) { Add '(khong co may in nao)' }
    foreach ($p in $printers) {
        Add ("- {0} | driver={1} | port={2} | status={3} | shared={4}" -f $p.Name, $p.DriverName, $p.PortName, $p.PrinterStatus, $p.Shared)
        if ($p.PortName -like 'WSD*') { Flag "May in '$($p.Name)' dang dung cong WSD ($($p.PortName)) - WSD rat hay offline/gia chet, nen chuyen sang cong TCP/IP theo IP (menu 15)." }
        if ($p.DriverName -eq 'Microsoft IPP Class Driver') { Add "    (driver IPP co san cua Microsoft - it tinh nang hon driver hang)" }
    }
    Add ''
    Add '=== Ports (SNMP bat = de bao offline gia) ==='
    try {
        foreach ($port in @(Get-PrinterPort)) {
            Add ("- {0} | host={1} | SNMPEnabled={2} | monitor={3}" -f $port.Name, $port.PrinterHostAddress, $port.SNMPEnabled, $port.PortMonitor)
            if ($port.SNMPEnabled -eq $true) { Flag "Cong '$($port.Name)' dang bat SNMP - may in khong tra loi SNMP se bi bao Offline du van in duoc. Tat SNMP o menu 15." }
        }
    } catch { Add '(khong doc duoc danh sach cong)' }

    Add ''
    Add '=== Drivers ==='
    try { foreach ($d in @(Get-PrinterDriver)) { Add ("- {0} | {1}" -f $d.Name, $d.Manufacturer) } } catch {}

    # ---- Print policy state ----
    Add ''
    Add '=== Print policy / RPC (hieu luc thuc te) ==='
    $rpcNamed = FP-RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC' 'RpcUseNamedPipeProtocol'
    $rpcProtos = FP-RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC' 'RpcProtocols'
    Add "Policy RPC: RpcUseNamedPipeProtocol=$rpcNamed (1=named pipes, trong=RPC over TCP)  RpcProtocols=$rpcProtos"
    if ([int]$build -ge 22621 -and $rpcNamed -ne 1) { Flag 'Win11 22H2+ dang dung RPC over TCP - gap loi 0x00000bc4/0x00000709 khi noi may in share thi chay menu 10.' }
    $wrongPlace = FP-RegGet 'HKLM:\SYSTEM\CurrentControlSet\Control\Print' 'RpcUseNamedPipeProtocol'
    if ($null -ne $wrongPlace) { Flag 'Phat hien RpcUseNamedPipeProtocol nam o Control\Print (vi tri vo tac dung, di san cua tool cu) - gia tri dung phai o Policies\...\Printers\RPC.' }
    $privacy = FP-RegGet 'HKLM:\SYSTEM\CurrentControlSet\Control\Print' 'RpcAuthnLevelPrivacyEnabled'
    Add "RpcAuthnLevelPrivacyEnabled (Control\Print) = $privacy (0=dang ha de tuong thich 0x0000011b, trong/1=mac dinh bao mat)"
    $restrict = FP-RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint' 'RestrictDriverInstallationToAdministrators'
    Add "RestrictDriverInstallationToAdministrators = $restrict (1=chi admin cai driver qua share - mac dinh an toan; 0=de cai, kem an toan)"

    # ---- WPP ----
    Add ''
    Add '=== Windows Protected Print Mode (Win11 24H2+) ==='
    $wpp = FP-RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP' 'WindowsProtectedPrintMode'
    Add "Policy WindowsProtectedPrintMode = $wpp (1=BAT qua policy)"
    if ($wpp -eq 1) { Flag 'WPP dang BAT bang policy - driver hang bi chan/go. Xem menu 16.' }

    # ---- SMB effective config ----
    Add ''
    Add '=== SMB Client (hieu luc thuc te) ==='
    try {
        $smbC = Get-SmbClientConfiguration
        Add ("EnableInsecureGuestLogons={0}  RequireSecuritySignature={1}  EnableSecuritySignature={2}" -f $smbC.EnableInsecureGuestLogons, $smbC.RequireSecuritySignature, $smbC.EnableSecuritySignature)
        if ([int]$build -ge 26100 -and $smbC.RequireSecuritySignature -eq $true) {
            Flag '24H2 dang BAT buoc ky SMB (RequireSecuritySignature=True). Share guest/NAS cu/may chu khong ky duoc se vao khong duoc (0x80070035) du da bat guest. Menu 5 xu ly ca 2 lop.'
        }
        if ($smbC.EnableInsecureGuestLogons -eq $false) { Add 'Guest SMB dang TAT (mac dinh an toan). Chi can bat khi noi share khong mat khau.' }
    } catch { Add '(khong doc duoc SmbClientConfiguration)' }
    Add ''
    Add '=== SMB Server (may nay co lam may chu share khong) ==='
    try {
        $smbS = Get-SmbServerConfiguration
        Add ("EnableSMB1Protocol={0}  EnableSMB2Protocol={1}  RequireSecuritySignature={2}" -f $smbS.EnableSMB1Protocol, $smbS.EnableSMB2Protocol, $smbS.RequireSecuritySignature)
    } catch { Add '(khong doc duoc SmbServerConfiguration)' }
    try {
        $shares = @(Get-SmbShare | Where-Object { $_.Name -notmatch '^(ADMIN\$|C\$|IPC\$)' })
        foreach ($s in $shares) { Add ("- Share: {0} -> {1}" -f $s.Name, $s.Path) }
    } catch {}

    # ---- Network profile + discovery ----
    Add ''
    Add '=== Network profile / Discovery ==='
    try {
        foreach ($prof in @(Get-NetConnectionProfile)) {
            Add ("- {0} | Interface={1} | Category={2}" -f $prof.Name, $prof.InterfaceAlias, $prof.NetworkCategory)
            if ($prof.NetworkCategory -eq 'Public') { Flag "Mang '$($prof.Name)' dang o Public - Windows chan tim thay may in/share trong LAN. Chuyen Private o menu 4." }
        }
    } catch { Add '(khong doc duoc NetConnectionProfile)' }
    foreach ($svcName in @('FDResPub','fdPHost','SSDPSRV','upnphost','LanmanWorkstation','LanmanServer','Dnscache')) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) { Add ("- Service {0}: {1} / {2}" -f $svcName, $svc.Status, $svc.StartType) }
        else { Add "- Service $svcName : (khong ton tai)" }
    }
    $discSvc = Get-Service -Name FDResPub -ErrorAction SilentlyContinue
    if ($discSvc -and $discSvc.Status -ne 'Running') { Flag 'FDResPub khong chay - may khac kho thay may nay trong Network.' }

    # ---- Default printer ----
    Add ''
    Add '=== Default printer ==='
    $legacy = FP-RegGet 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' 'LegacyDefaultPrinterMode'
    Add "LegacyDefaultPrinterMode=$legacy (1=tat che do Windows tu quan ly may in mac dinh)"
    try {
        $def = Get-CimInstance Win32_Printer -ErrorAction Stop | Where-Object { $_.Default -eq $true }
        if ($def) { Add "Default hien tai: $($def.Name)" } else { Add '(chua co may in mac dinh)' }
    } catch {}

    # ---- Problem devices ----
    Add ''
    Add '=== Problem devices ==='
    try {
        $bad = @(Get-PnpDevice | Where-Object { $_.Status -ne 'OK' })
        if ($bad.Count -eq 0) { Add '(khong co thiet bi loi)' }
        foreach ($d in $bad) { Add ("- {0} | {1} | {2}" -f $d.Status, $d.Class, $d.FriendlyName) }
    } catch { Add '(khong doc duoc PnP)' }

    # ---- Spooler dependencies + crash history (v13.1) ----
    Add ''
    Add '=== Spooler dependencies / lich su sap (v13.1) ==='
    try {
        $deps = @((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Spooler' -Name DependOnService -ErrorAction Stop).DependOnService)
        Add ("DependOnService: " + ($deps -join ', '))
        foreach ($d in $deps) {
            if ($d -in @('RPCSS', 'HTTP')) { continue }
            if (-not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\$d")) {
                Flag "Dependency '$d' cua Spooler da bi go khoi may nhung van con trong danh sach -> loi 1068, Spooler khong start duoc. Menu 3 (hoac 25) se reset ve RPCSS/HTTP."
            }
        }
    } catch { Add '(khong doc duoc DependOnService)' }
    try {
        $since = (Get-Date).AddDays(-7)
        $crashes = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 7031, 7034; StartTime = $since } -ErrorAction Stop | Where-Object { $_.Message -match 'Print Spooler|spooler' })
        Add "So lan Spooler sap trong 7 ngay: $($crashes.Count)"
        if ($crashes.Count -ge 3) { Flag "Spooler sap $($crashes.Count) lan trong 7 ngay - thu pham thuong la 1 driver in hong. Xem muc Drivers trong bao cao nay, go driver vua cai gan nhat (menu 18)." }
    } catch { Add '(khong doc duoc Event Log System)' }
    try {
        $since = (Get-Date).AddDays(-7)
        $perr = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-PrintService/Admin'; Level = 2; StartTime = $since } -ErrorAction Stop)
        Add "Loi PrintService/Admin trong 7 ngay: $($perr.Count)"
        foreach ($e in ($perr | Select-Object -First 5)) { Add ("  - {0} Id={1}: {2}" -f $e.TimeCreated, $e.Id, (($e.Message -split "`r?`n")[0])) }
    } catch { Add '(khong co/khong doc duoc log PrintService/Admin)' }

    # ---- Saved printer connections (v13.1) ----
    Add ''
    Add '=== Ket noi may in share da luu (HKCU) ==='
    $connKey = 'HKCU:\Printers\Connections'
    if (Test-Path $connKey) {
        $subs = @(Get-ChildItem $connKey -ErrorAction SilentlyContinue)
        if ($subs.Count -eq 0) { Add '(khong co ket noi share nao)' }
        foreach ($s in $subs) { Add ("- " + (($s.PSChildName -replace '^,,', '\\') -replace ',', '\')) }
    } else { Add '(khong co key Connections)' }

    # ---- Windows Ready Print ranking (v13.1) ----
    Add ''
    Add '=== Windows Ready Print driver ranking (Win11) ==='
    $wrp = FP-RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers' 'ConfigureWindowsReadyPrintDriverRanking'
    Add "Policy ConfigureWindowsReadyPrintDriverRanking = $wrp (trong = mac dinh BAT tu 07/2026; 1 = uu tien driver IPP cua Microsoft; 0 = tat uu tien)"
    $ippNow = @($printers | Where-Object { $_.DriverName -eq 'Microsoft IPP Class Driver' })
    if ($ippNow.Count -gt 0 -and $wrp -ne 0) {
        Flag "Co $($ippNow.Count) may in dang chay driver Microsoft IPP Class Driver. Neu may in bi mat khay phu/finisher/in bao mat sau khi cai lai, do la Ready Print ranking chon driver IPP thay driver hang - tat uu tien o menu 23 roi cai lai driver hang."
    }

    # ---- WIA / USB printers (v13.1) ----
    Add ''
    Add '=== WIA (scan) + may in USB ==='
    $wia = Get-Service -Name stisvc -ErrorAction SilentlyContinue
    if ($wia) { Add "WIA (stisvc): $($wia.Status) / $($wia.StartType)"; if ($wia.Status -ne 'Running') { Flag 'WIA khong chay - phan scan cua may in da chuc nang se khong hoat dong. Menu 24 xu ly.' } }
    else { Add '(khong co service WIA)' }
    foreach ($p in $printers) { if ($p.PortName -like 'USB*') { Add ("- USB: {0} | driver={1} | port={2}" -f $p.Name, $p.DriverName, $p.PortName) } }

    # ---- Recent updates (v13.1) ----
    Add ''
    Add '=== Windows Update gan day (doi chieu khi loi xuat hien sau update) ==='
    try {
        $hfs = @(Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 6)
        foreach ($h in $hfs) { Add ("- {0} | {1} | {2}" -f $h.HotFixID, $h.InstalledOn, $h.Description) }
        if ($hfs | Where-Object { $_.HotFixID -eq 'KB5079473' }) {
            Flag 'Co KB5079473 (03/2026): Microsoft xac nhan ban nay lam may in USB IPP mat scan/fax, chua co va triet de. Neu dung trieu chung: menu 24.'
        }
    } catch { Add '(khong doc duoc danh sach HotFix)' }

    # ---- KB knowledge base match (v13.2) ----
    Add ''
    Add '=== KB gay loi in/LAN da biet - doi chieu may nay (v13.2) ==='
    try {
        $kbLines = FP-KbScanLines
        if ($kbLines.Count -eq 0) { Add '(khong khop KB nao trong kho du lieu - Get-HotFix khong liet ke moi ban tich luy cu nen day khong phai bang chung sach se)' }
        foreach ($l in $kbLines) { Add $l }
        if ($script:FPKbMatches -and $script:FPKbMatches.Count -gt 0) {
            Flag "May dang cai $($script:FPKbMatches.Count) KB nam trong danh sach gay loi in/LAN da biet - xem chi tiet ngay tren va menu 27."
        }
    } catch { Add '(khong chay duoc doi chieu KB)' }

    # ---- Antivirus + spooler security state (v13.2) ----
    Add ''
    Add '=== Antivirus + trang thai bao mat Spooler (v13.2) ==='
    try {
        $avs = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop)
        foreach ($a in $avs) { Add ("- AV: {0} (productState={1})" -f $a.displayName, $a.productState) }
        if ($avs.Count -eq 0) { Add '(SecurityCenter2 khong co AV nao dang ky)' }
    } catch { Add '(khong doc duoc danh sach AV)' }
    $rsr = FP-RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers' 'RegisterSpoolerRemoteRpcEndPoint'
    Add "RegisterSpoolerRemoteRpcEndPoint = $rsr (2 = hardening PrintNightmare dang chan in tu xa ve may nay)"
    if ($rsr -eq 2) { Flag 'Hardening PrintNightmare (RegisterSpoolerRemoteRpcEndPoint=2) dang bat: may nay in cuc bo duoc nhung KHONG nhan in tu may khac qua share. Neu may nay la may chu in: menu 28.' }
    try {
        $since = (Get-Date).AddDays(-30)
        $chg = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Id = 7040; StartTime = $since } -ErrorAction Stop | Where-Object { $_.Message -match 'Print Spooler' })
        Add "So lan kieu khoi dong cua Spooler bi THAY DOI trong 30 ngay (Event 7040): $($chg.Count)"
        foreach ($e in ($chg | Select-Object -First 3)) { Add ("  - {0}: {1}" -f $e.TimeCreated, (($e.Message -split "`r?`n")[0])) }
        if ($chg.Count -gt 0 -and $sp -and $sp.StartType -eq 'Disabled') { Flag 'Spooler dang Disabled VA co dau vet bi thay doi kieu khoi dong gan day - thu pham thuong la GPO hardening, tool debloat/toi uu, hoac AV. Bat lai o menu 3; neu bi tat lai thi truy theo Event 7040.' }
    } catch { Add '(khong doc duoc Event 7040)' }
    try {
        $provs = @((Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Providers' -ErrorAction Stop).PSChildName)
        $extraP = @($provs | Where-Object { $_ -notin @('LanMan Print Services', 'Internet Print Provider') })
        Add ("Print Providers: " + ($provs -join ', '))
        if ($extraP.Count -gt 0) { Flag ("Co Print Provider ben thu ba: " + ($extraP -join ', ') + ' - phan mem in cu de lai, lam Spooler sap/tat lien tuc. Xu ly o menu 28.') }
    } catch {}

    Add ''
    Add '============================================================'
    if ($flags.Count -eq 0) { Add 'TONG KET: khong phat hien FLAG nao.' }
    else {
        Add "TONG KET: $($flags.Count) FLAG can chu y:"
        foreach ($f in $flags) { Add "  * $f" }
    }
    Add '============================================================'

    try { $out | Set-Content -Path $report -Encoding UTF8; FP-OK 'Diagnose report' "da ghi $report" }
    catch { FP-FAIL 'Diagnose report' $_.Exception.Message }
}
