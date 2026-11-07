# FixPrinter v13.2 - UpdateFixes.ps1
# Two field problems this module covers:
#  1) Windows updates (KB) that break printing / LAN sharing. A small built-in
#     KB knowledge base is matched against the updates actually installed on
#     the machine (Get-HotFix), a post-update recovery bundle re-applies the
#     settings updates commonly reset, duplicate-SID breakage from
#     KB5064081/KB5065426 (cloned PCs) is detected from event logs, and a
#     guarded wusa uninstall is offered as a last resort.
#  2) Print Spooler vs security software. The spooler is a historic attack
#     surface (PrintNightmare CVE-2021-34527 runs as SYSTEM), so AV/Defender,
#     GPO hardening and debloat tools often disable it, block its remote RPC
#     endpoint, or quarantine its files - and printing dies as a side effect.
#     This module separates "spooler attacked/sick" from "spooler switched
#     off by a security control" using signatures and event logs.

# ---------------- KB knowledge base ------------------------------------------
# Fields: KB, When, Scope, Symptom, Menu (where to fix), Uninstall guidance.
$script:FPKbDb = @(
    @{ KB = 'KB5004945'; When = '07/2021 (ban khan cap ngoai lich)'; Scope = 'Win10/Win11/Server'; Symptom = 'Va PrintNightmare CVE-2021-34527. Ban than no khong pha in, nhung cac thay doi cung hoa di kem sau do thi co.'; Menu = 'Thong tin - khong can go'; Uninstall = 'Khong go' },
    @{ KB = 'KB5005652'; When = '08/2021'; Scope = 'Win10/Win11/Server'; Symptom = 'CVE-2021-34481: Point and Print mac dinh chi cho admin cai driver -> user thuong ket noi may in share bi doi quyen admin / loi cai driver.'; Menu = '12 (SAFE) hoac 13 (COMPAT)'; Uninstall = 'Khong go - day la mac dinh bao mat vinh vien' },
    @{ KB = 'KB5005565'; When = '09/2021'; Scope = 'Win10 (cac ban anh em: KB5005566/68/69/73 theo phien ban)'; Symptom = 'Bat buoc RpcAuthnLevelPrivacyEnabled (CVE-2021-1678) -> song loi 0x0000011b khi ket noi may in share giua cac may lech muc update.'; Menu = '9 (tren may chu) + cap nhat ca 2 may'; Uninstall = 'Khong go duoc tren may da cap nhat tich luy moi' },
    @{ KB = 'KB5006670'; When = '10/2021'; Scope = 'Win10 (Win11: KB5006674)'; Symptom = 'Known issue chinh thuc cua Microsoft: ket noi may in share loi 0x0000007c / 0x00000709 / 0x000006e4.'; Menu = 'Da va boi KB5007253 (11/2021) - chi can cap nhat moi'; Uninstall = 'Khong go - da bi thay the boi ban tich luy moi' },
    @{ KB = 'KB5007186'; When = '11/2021'; Scope = 'Win10'; Symptom = 'Tiep tuc gay 0x00000709/0x0000007c tren mot so may chua len ban va thang 11.'; Menu = 'Cap nhat len ban tich luy moi nhat'; Uninstall = 'Khong go - da bi thay the' },
    @{ KB = 'KB5034510'; When = '11-12/2023'; Scope = 'Win10/Win11/Server'; Symptom = 'Metadata HP loi: moi may in bi doi ten thanh "HP LaserJet M101-M106", app HP Smart tu cai. In van chay, chi sai ten/icon. Microsoft co Printer Metadata Troubleshooter rieng (KB5034510).'; Menu = 'Thong tin - tai troubleshooter cua Microsoft'; Uninstall = 'Khong ap dung' },
    @{ KB = 'KB5050092'; When = '01/2025 (preview)'; Scope = 'Win11 22H2/23H2'; Symptom = 'May in USB dual-mode in ra trang rac bat dau bang "POST /ipp/print HTTP/1.1".'; Menu = '24 - va da co tu KB5053657 (03/2025)'; Uninstall = 'Khong go - cap nhat tiep la du' },
    @{ KB = 'KB5064081'; When = '08/2025 (preview)'; Scope = 'Win11 24H2/25H2, Server 2025'; Symptom = 'Cung hoa xac thuc may: PC CLONE TRUNG SID bi chan RDP/SMB/in share qua lai (0xc000006d, LsaSrv Event 6167). Xem muc kiem tra SID o menu 27.'; Menu = '27'; Uninstall = 'Go duoc nhung chi tam thoi - goc la trung SID' },
    @{ KB = 'KB5065426'; When = '09/2025'; Scope = 'Win11 24H2/25H2, Server 2025'; Symptom = 'Ban chinh thuc cua thay doi tren: may clone trung SID chet RDP/SMB/in share; cong dong bao them profile mang bi lat ve Public, discovery/share bi tat.'; Menu = '27 (KIR cua Microsoft / go KB / xu ly SID)'; Uninstall = 'Go duoc nhung chi tam thoi - goc la trung SID' },
    @{ KB = 'KB5079473'; When = '03/2026'; Scope = 'Win11 24H2/25H2/26H2'; Symptom = 'May in USB IPP da chuc nang mat scan/fax, driver scan khong cai duoc. Microsoft xac nhan, chua va triet de.'; Menu = '24'; Uninstall = 'Microsoft khong khuyen nghi go' },
    @{ KB = 'KB5083769'; When = '04/2026'; Scope = 'Win11 + Universal Print (doanh nghiep)'; Symptom = 'Hang doi Universal Print dang ky dang system-wide bi hong sau update: loi 0x80004005, nut in bi mo, test page 0x000003e3. Chi anh huong may dung Universal Print cloud, khong anh huong share LAN thuong.'; Menu = 'Thong tin - go queue roi cai lai thu cong theo Microsoft'; Uninstall = 'Khong ap dung' }
)

function FP-KbScanLines {
    # Returns formatted lines for every DB entry whose KB is installed here.
    $installed = @()
    try { $installed = @(Get-HotFix | Select-Object -ExpandProperty HotFixID) } catch {}
    $lines = New-Object System.Collections.Generic.List[string]
    $script:FPKbMatches = @()
    foreach ($e in $script:FPKbDb) {
        if ($installed -contains $e.KB) {
            $script:FPKbMatches += $e
            $lines.Add(("[{0}] {1} | {2}" -f $e.KB, $e.When, $e.Scope))
            $lines.Add(("    Trieu chung: " + $e.Symptom))
            $lines.Add(("    Xu ly: " + $e.Menu + " | Go KB: " + $e.Uninstall))
        }
    }
    return $lines.ToArray()
}

# ---------------- Duplicate SID check (KB5064081/KB5065426) -------------------

function FP-CheckDupSid {
    $machineSid = ''
    try {
        $acct = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True" -ErrorAction Stop | Select-Object -First 1
        if ($acct) { $machineSid = ($acct.SID -replace '-\d+$', '') }
    } catch {}
    if ($machineSid) { FP-Log "    Machine SID cua may nay: $machineSid" 'INFO' }
    FP-Info 'Luu y: kiem tra trung SID phai so SID giua CAC may voi nhau - mot may khong tu biet duoc may khac co trung hay khong. Dau hieu nhan biet tren may: log LsaSrv 6167 va loi dang nhap 0xc000006d.'
    $hits6167 = 0; $hits4625 = 0
    try {
        $since = (Get-Date).AddDays(-14)
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'LsaSrv'; Id = 6167; StartTime = $since } -ErrorAction Stop)
        $hits6167 = $ev.Count
    } catch {}
    try {
        $since = (Get-Date).AddDays(-14)
        $ev2 = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625; StartTime = $since } -MaxEvents 500 -ErrorAction Stop | Where-Object { $_.Message -match '0xc000006d' })
        $hits4625 = $ev2.Count
    } catch {}
    FP-Log "    14 ngay qua: LsaSrv 6167 = $hits6167 lan, Security 4625/0xc000006d = $hits4625 lan" 'INFO'
    if ($hits6167 -gt 0 -or $hits4625 -gt 0) {
        FP-Warn 'CO dau hieu trung SID / lech machine ID giua cac may clone (dung co che KB5065426 chan). Cach xu ly dung: moi may phai co SID rieng (sysprep /generalize khi nhan ban tu mot anh goc). Tam thoi: cai KIR (Known Issue Rollback) cua Microsoft cho KB5065426, hoac go KB5065426/KB5064081 o muc duoi - deu chi la cau gio, thang sau update lai bi lai.'
        return $true
    }
    FP-OK 'Kiem tra dau hieu trung SID' 'khong thay LsaSrv 6167 / 4625-0xc000006d trong 14 ngay'
    return $false
}

# ---------------- Menu 27: post-update recovery ------------------------------

function FP-PostUpdateRecovery {
    Write-Host 'Muc nay dung khi: hom qua in/share binh thuong, Windows update xong thi hong. Thu tu: doi chieu KB -> ap lai cau hinh hay bi update reset -> kiem tra trung SID -> cuoi cung moi can nhac go KB.'

    FP-Step 'Doi chieu KB gay loi da biet voi may nay' {
        $lines = FP-KbScanLines
        if ($lines.Count -eq 0) { FP-Log '    Khong khop KB nao trong kho du lieu (luu y: Get-HotFix khong liet ke moi ban tich luy cu).' 'INFO'; return $true }
        foreach ($l in $lines) { FP-Log $l 'INFO' }
        return $true
    }

    if (FP-Confirm 'Ap lai goi cau hinh sau update (Private + discovery + SMB client + PnP SAFE)?') {
        Write-Host '--- Ap lai: Discovery (profile Private, dich vu, firewall) ---'
        FP-FixDiscovery
        Write-Host '--- Ap lai: SMB client (guest + ky SMB) ---'
        FP-FixSmbClient
        Write-Host '--- Ap lai: Point and Print SAFE ---'
        FP-PnPSafe
    } else { FP-SKIP 'Ap lai cau hinh sau update' 'nguoi dung bo qua' }

    [void](FP-CheckDupSid)

    FP-Step 'Mo trang Windows Update (kiem tra ban dang cho / vua cai)' {
        try { Start-Process 'ms-settings:windowsupdate' -ErrorAction Stop; return $true } catch { return $false }
    }

    Write-Host ''
    FP-Warn 'GO KB la phuong an CUOI CUNG: ban tich luy chua ca va bao mat cua thang, go ra la ho bao mat; va thang sau no tu cai lai. Chi go khi KB scan khop + trieu chung khop.'
    $kbNum = Read-Host 'Nhap so KB muon go (chi nhap so, vd 5065426 - Enter de bo qua)'
    if ($kbNum -match '^\d{7}$') {
        if (FP-ConfirmTyped "Go KB$kbNum khoi may nay" 'GO') {
            FP-Step "Go KB$kbNum bang wusa (khong tu khoi dong lai)" {
                $rc = FP-Run 'wusa.exe' "/uninstall /kb:$kbNum /quiet /norestart"
                if ($rc -eq 0) { FP-Log '    Da go xong.' 'INFO'; return $true }
                if ($rc -eq 3010) { FP-Log '    Da go xong - CAN KHOI DONG LAI de hoan tat.' 'INFO'; return $true }
                FP-Log "    wusa tra ve ma $rc (2359303 = KB khong cai rieng le / da bi thay the, khong go duoc)." 'INFO'
                return $false
            }
            FP-Warn 'Nho tam dung update (Settings > Windows Update > Pause) neu chua muon KB nay cai lai ngay.'
        } else { FP-SKIP 'Go KB' 'khong go dung chu GO' }
    } else { FP-SKIP 'Go KB' 'khong nhap KB hop le' }
}

# ---------------- Menu 28: Spooler vs antivirus / hardening ------------------

function FP-SpoolerAvCheck {
    Write-Host 'Muc nay tra loi cau hoi: Spooler bi TAT/CHAN boi phan mem bao mat, hay Spooler dang bi benh/tan cong?'

    # 1) Which AV is on this machine
    try {
        $avs = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop)
        if ($avs.Count -eq 0) { FP-SKIP 'Liet ke antivirus' 'SecurityCenter2 khong tra ve san pham nao' }
        else {
            foreach ($a in $avs) { FP-Log "    AV: $($a.displayName) (productState=$($a.productState))" 'INFO' }
            FP-OK 'Liet ke antivirus' "$($avs.Count) san pham dang dang ky"
        }
    } catch { FP-SKIP 'Liet ke antivirus' $_.Exception.Message }

    # 2) spoolsv.exe: right file, right signature
    FP-Step 'Kiem tra spoolsv.exe (dung duong dan + chu ky Microsoft)' {
        $img = FP-RegGet 'HKLM:\SYSTEM\CurrentControlSet\Services\Spooler' 'ImagePath'
        $path = Join-Path $env:SystemRoot 'System32\spoolsv.exe'
        FP-Log "    ImagePath dang khai: $img" 'INFO'
        if (-not (Test-Path $path)) { FP-Log '    spoolsv.exe KHONG con trong System32 - rat co the bi AV cach ly/xoa hoac bi malware pha. Chay menu 20 (DISM+SFC) de phuc hoi file he thong.' 'INFO'; return $false }
        $sig = Get-AuthenticodeSignature $path
        FP-Log "    Chu ky so: Status=$($sig.Status) Signer=$($sig.SignerCertificate.Subject)" 'INFO'
        return ($sig.Status -eq 'Valid')
    }

    # 3) Defender detections touching spool/print in the last 14 days
    FP-Step 'Quet log Defender: phat hien lien quan spool/print (14 ngay)' {
        try {
            $since = (Get-Date).AddDays(-14)
            $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1116, 1117; StartTime = $since } -ErrorAction Stop | Where-Object { $_.Message -match 'spool|print' })
            if ($ev.Count -eq 0) { FP-Log '    Khong co phat hien Defender nao cham vao spool/print.' 'INFO'; return $true }
            foreach ($e in ($ev | Select-Object -First 5)) { FP-Log ("    - {0} Id={1}: {2}" -f $e.TimeCreated, $e.Id, (($e.Message -split "`r?`n")[0])) 'INFO' }
            FP-Log '    Co phat hien Defender cham vao spool/print: mo Windows Security > Protection history de xem file nao bi cach ly - neu la file driver in that thi do la xung dot AV, neu la file la trong spool\PRINTERS thi may co the da bi tan cong qua spooler.' 'INFO'
            return $true
        } catch { FP-Log '    Khong doc duoc log Defender (may dung AV hang khac?).' 'INFO'; return $true }
    }

    # 4) PrintNightmare-era hardening that blocks this PC from HOSTING printers
    $rsr = FP-RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers' 'RegisterSpoolerRemoteRpcEndPoint'
    FP-Log "    RegisterSpoolerRemoteRpcEndPoint = $rsr (2 = Spooler TU CHOI ket noi in tu xa - hardening PrintNightmare; in cuc bo van chay, nhung may nay khong lam may chu share duoc)" 'INFO'
    if ($rsr -eq 2) {
        FP-Warn 'May nay dang bi hardening PrintNightmare chan in tu xa. Neu may nay can share may in cho LAN thi phai go gia tri nay (doi lai: may lai mo duong RPC ma PrintNightmare khai thac - chi lam khi may da cap nhat day du va o LAN tin cay).'
        if (FP-Confirm 'Go RegisterSpoolerRemoteRpcEndPoint de may nay share may in duoc?') {
            FP-Step 'Go RegisterSpoolerRemoteRpcEndPoint + restart Spooler' {
                $okDel = FP-RegDeleteValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers' 'RegisterSpoolerRemoteRpcEndPoint'
                $okSp = FP-RestartSpooler
                return ($okDel -and $okSp)
            }
        } else { FP-SKIP 'Go RegisterSpoolerRemoteRpcEndPoint' 'nguoi dung giu hardening' }
    } else { FP-OK 'Hardening PrintNightmare (remote RPC)' 'khong bi khoa o muc 2' }

    # 5) Non-default print providers (classic spooler crasher)
    FP-Step 'Liet ke Print Providers (chi mac dinh moi nen giu)' {
        $provKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Providers'
        $provs = @((Get-ChildItem $provKey -ErrorAction Stop).PSChildName)
        foreach ($pv in $provs) { FP-Log "    Provider: $pv" 'INFO' }
        $script:fpExtraProviders = @($provs | Where-Object { $_ -notin @('LanMan Print Services', 'Internet Print Provider') })
        return $true
    }
    if ($script:fpExtraProviders -and $script:fpExtraProviders.Count -gt 0) {
        FP-Warn ("Co provider ben thu ba: " + ($script:fpExtraProviders -join ', ') + ' - phan mem in cu de lai, la thu pham lam Spooler sap/tat lien tuc.')
        foreach ($pv in $script:fpExtraProviders) {
            if (FP-Confirm "Go provider '$pv' (da co backup registry truoc)?") {
                FP-Step "Go Print Provider '$pv'" {
                    Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Providers\$pv" -Recurse -Force -ErrorAction Stop
                    return (-not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Providers\$pv"))
                }
            } else { FP-SKIP "Go Print Provider '$pv'" 'nguoi dung huy' }
        }
        FP-Step 'Khoi dong lai Spooler sau khi go provider' { return (FP-RestartSpooler) }
    }

    # 6) Executable files sitting in the spool queue folder
    FP-Step 'Quet thu muc hang doi spool\PRINTERS tim file thuc thi la' {
        $dir = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'
        if (-not (Test-Path $dir)) { return $true }
        $bad = @(Get-ChildItem $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.exe', '.dll', '.bat', '.cmd', '.ps1', '.vbs', '.js', '.scr') })
        if ($bad.Count -eq 0) { FP-Log '    Chi co file viec in binh thuong (.SPL/.SHD).' 'INFO'; return $true }
        foreach ($b in $bad) { FP-Log "    FILE LA: $($b.FullName)" 'INFO' }
        FP-Log '    File thuc thi trong hang doi in la dau hieu bat thuong (khai thac spooler hoac malware) - quet virus toan may truoc khi sua tiep.' 'INFO'
        return $false
    }

    FP-Info 'Ket luan nhanh: Spooler StartType=Disabled ma khong ai tat -> nghi GPO/debloat/AV (xem Diagnose muc thay doi dich vu Event 7040). Spooler chay roi sap lien tuc -> nghi driver/provider (menu 3 + muc provider o tren). Defender co phat hien spool -> xem muc 3 o tren.'
}

# ---------------------------------------------------------------------------
# v13.3: AUTO helpers - read-only scans + USB/WIA, used by FP-AutoFixAll.
# Everything here only REPORTS (PASS/FAIL/SKIP + warnings). Removals and
# policy flips stay in menus 27/28 where a human approves each one.
# ---------------------------------------------------------------------------
function FP-AutoSecurityScan {
    FP-Step 'Chu ky so cua spoolsv.exe (file Microsoft nguyen ban?)' {
        try {
            $svc = Get-CimInstance Win32_Service -Filter "Name='Spooler'" -ErrorAction Stop
            $exe = [Environment]::ExpandEnvironmentVariables(($svc.PathName -replace '"', '').Trim())
            if (-not (Test-Path $exe)) { FP-Warn "Khong thay file $exe - chay menu 20 (DISM/SFC)."; return $false }
            $sig = Get-AuthenticodeSignature $exe -ErrorAction Stop
            Write-Host "    spoolsv.exe: $($sig.Status) - $($sig.SignerCertificate.Subject)"
            if ($sig.Status -ne 'Valid') { FP-Warn 'spoolsv.exe KHONG dung chu ky Microsoft: nghi bi va/nhiem - quet virus truoc, sua in sau.'; return $false }
            return $true
        } catch { FP-SKIP 'Chu ky so cua spoolsv.exe' 'khong doc duoc chu ky (thieu cmdlet)'; return 'skip' }
    }
    FP-Step 'Windows Defender co cham vao spool/print gan day khong' {
        try {
            $since = (Get-Date).AddDays(-14)
            $hits = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1116, 1117; StartTime = $since } -ErrorAction Stop | Where-Object { $_.Message -match 'spool|print' })
            Write-Host "    Phat hanh dong Defender lien quan spool/print (14 ngay): $($hits.Count)"
            if ($hits.Count -gt 0) { FP-Warn 'Defender tung xu ly file lien quan in an - xem chi tiet o menu 28 (co the la AV xung dot, cung co the la malware that).' }
            return $true
        } catch { FP-SKIP 'Log Windows Defender' 'khong doc duoc log Defender'; return 'skip' }
    }
    FP-Step 'Trang thai hardening PrintNightmare (chan in tu xa)' {
        $v = FP-RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers' 'RegisterSpoolerRemoteRpcEndPoint'
        Write-Host "    RegisterSpoolerRemoteRpcEndPoint = $v"
        if ($v -eq 2) { FP-Warn 'Hardening dang BAT: may nay khong nhan in tu may khac qua share. Neu day la MAY CHU in: go o menu 28 (co canh bao).' }
        return $true
    }
    FP-Step 'Print Provider ben thu ba (nguyen nhan Spooler sap/tat)' {
        try {
            $provs = @((Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Providers' -ErrorAction Stop).PSChildName)
            $extra = @($provs | Where-Object { $_ -notin @('LanMan Print Services', 'Internet Print Provider') })
            if ($extra.Count -gt 0) { FP-Warn ("Provider la: " + ($extra -join ', ') + ' - phan mem in cu de lai; go o menu 28 neu Spooler hay sap.') }
            else { Write-Host '    Chi co 2 provider mac dinh cua Microsoft.' }
            return $true
        } catch { FP-SKIP 'Print Provider ben thu ba' 'khong doc duoc registry Providers'; return 'skip' }
    }
    FP-Step 'File thuc thi la trong hang doi spool\PRINTERS' {
        if (-not $env:SystemRoot) { FP-SKIP 'File thuc thi la trong hang doi' 'khong xac dinh duoc SystemRoot'; return 'skip' }
        $spoolDir = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'
        if (-not (Test-Path $spoolDir)) { FP-SKIP 'File thuc thi la trong hang doi' "khong thay $spoolDir"; return 'skip' }
        $bad = @(Get-ChildItem $spoolDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.exe', '.dll', '.bat', '.cmd', '.ps1', '.vbs', '.js', '.scr' })
        if ($bad.Count -gt 0) { FP-Warn ("File la: " + (($bad | ForEach-Object Name) -join ', ') + ' - dau hieu khai tac spooler/malware: QUET VIRUS truoc.'); return $false }
        return $true
    }
    FP-Step 'Trang thai Windows Protected Print Mode + Ready Print' {
        $wppMode = FP-RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP' 'WindowsProtectedPrintMode'
        $rpRank = FP-RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers' 'ConfigureWindowsReadyPrintDriverRanking'
        Write-Host "    WindowsProtectedPrintMode (policy) = $wppMode (1 = WPP dang BAT) ; Ready Print ranking = $rpRank"
        if ($wppMode -eq 1) { FP-Warn 'WPP dang BAT qua policy: moi driver ben thu ba bi chan - cac fix driver vo hieu cho den khi xu ly o menu 19.' }
        return $true
    }
}

function FP-AutoUsbWia {
    try { $usb = @(Get-Printer -ErrorAction Stop | Where-Object { $_.PortName -like 'USB*' }) } catch { $usb = @() }
    if ($usb.Count -eq 0) { Write-Host '    (khong co may in USB - bo qua muc WIA)'; return }
    Write-Host "    May in USB: $(($usb | ForEach-Object Name) -join ', ')"
    FP-ServiceEnsure 'stisvc'
    Write-Host '    Neu may da chuc nang mat scan/fax sau update (KB5079473): lam them tay theo menu 24 (go may in, rut cap, cai lai).'
}
