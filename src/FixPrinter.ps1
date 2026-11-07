# FixPrinter v13.4 - cong cu sua may in + mang LAN cho Windows 10/11
# Ban viet lai tu v12.0.3: moi fix deu co backup truoc, lam xong doc lai trang
# thai hieu luc de xac nhan, bao PASS/FAIL/SKIP tung muc.
# v13.1 (07/11/2026): them menu 22-26 - xoa ket noi/credential cu (1219),
# Windows Ready Print ranking, may in USB mat scan (KB5079473), dependency
# Spooler chet (1068), loi ket noi 0x2/0x57/0x7e; Diagnose them 5 muc moi.
# v13.2 (07/11/2026): them menu 27-28 - kho du lieu KB gay loi in/LAN doi chieu
# may that, khoi phuc sau update, kiem tra trung SID (KB5065426), go KB bang
# wusa; va Spooler vs antivirus/hardening (chu ky spoolsv, log Defender,
# RegisterSpoolerRemoteRpcEndPoint, Print Provider ben thu ba).
# v13.3 (07/11/2026): AUTO FIX ALL don TAT CA fix vao menu 1 - buoc 0 quet
# chi bao cao (KB + trung SID + bao mat spooler + WPP/ReadyPrint), 7 buoc sua
# cu, WIA cho may in USB, va muc tuong tac xoa ket noi cu (1219) o cuoi. Cac
# muc pha huy/can dau vao/can duyet bao mat van o menu rieng va duoc liet ke
# ro trong thong bao cuoi AUTO.
# v13.4 (07/11/2026): che do 1-click la chinh - file FIX_ALL_PRINTER_MANG_LAN.bat
# bam dup la chay thang AUTO (tham so --auto, FP-AutoFixAll -OneClick: bo qua
# muc tuong tac 1219, khong hoi gi, dung 1 lan o cuoi). Menu day du van con
# trong CHAY_FIXPRINTER.bat cho truong hop can xu ly rieng.
# PowerShell 5.1 compatible. ASCII only (text tieng Viet khong dau).
#
# Cach chay: bam dup CHAY_FIXPRINTER.bat (tu nang quyen admin)
# Tham so:  FixPrinter.ps1 --diagnose   (chi chan doan, ghi bao cao, thoat)
#           FixPrinter.ps1 --version

# No param() block on purpose: free-form switches like --diagnose / --version
# land in $args, which is what the non-interactive check below reads.

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$LibDir = Join-Path $PSScriptRoot 'lib'
. (Join-Path $LibDir 'Core.ps1')
FP-InitPaths
. (Join-Path $LibDir 'Diagnose.ps1')
. (Join-Path $LibDir 'Spooler.ps1')
. (Join-Path $LibDir 'LanPrint.ps1')
. (Join-Path $LibDir 'PrintFixes.ps1')
. (Join-Path $LibDir 'Drivers.ps1')
. (Join-Path $LibDir 'SystemTools.ps1')
. (Join-Path $LibDir 'ExtraFixes.ps1')
. (Join-Path $LibDir 'UpdateFixes.ps1')

$FPVersion = '13.4.0'

function FP-Header {
    Clear-Host
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host "   FIXPRINTER v13.4 - SUA MAY IN + MANG LAN (Win10/Win11)" -ForegroundColor Cyan
    Write-Host "   May: $env:COMPUTERNAME   User: $env:USERNAME" -ForegroundColor DarkGray
    Write-Host '============================================================' -ForegroundColor Cyan
}

function FP-Pause { Write-Host ''; [void](Read-Host 'Nhan Enter de tiep tuc') }

function FP-AutoFixAll {
    param([switch]$OneClick)
    FP-BeginAction 'AUTO FIX ALL (tat ca fix - co backup - bao cao day du)'
    [void](FP-BackupAll)
    Write-Host '--- BUOC 0: Quet nhanh CHI BAO CAO (khong sua): KB gay loi / trung SID / Spooler vs AV ---'
    FP-Step 'Doi chieu KB gay loi in/LAN voi may nay' {
        $kbLines = FP-KbScanLines
        foreach ($l in $kbLines) { Write-Host "    $l" }
        if ($script:FPKbMatches -and $script:FPKbMatches.Count -gt 0) { FP-Warn 'Co KB gay loi da biet tren may - chi tiet o tren; xu ly sau update o menu 27.' }
        else { Write-Host '    Khong khop KB nao trong kho du lieu.' }
        return $true
    }
    [void](FP-CheckDupSid)
    FP-AutoSecurityScan
    Write-Host '--- 1/9 Spooler (kem fix dependency 1068 + xoa hang doi + tu phuc hoi) ---'
    FP-FixSpooler
    Write-Host '--- 2/9 LAN discovery (Private + dich vu + firewall) ---'
    FP-FixDiscovery
    Write-Host '--- 3/9 SMB client (guest + ky SMB - bai toan 24H2) ---'
    FP-FixSmbClient
    Write-Host '--- 4/9 RPC named pipes (0x00000bc4 / 0x00000709) ---'
    FP-FixRpcNamedPipes
    Write-Host '--- 5/9 Tuong thich 0x0000011b phia may chu ---'
    FP-Fix11B -Auto
    Write-Host '--- 6/9 Point and Print SAFE + may in mac dinh ---'
    FP-PnPSafe
    FP-Fix709Default -Auto
    Write-Host '--- 7/9 Offline / SNMP (WSD can nhap IP nen de menu 15) ---'
    FP-FixOfflineWsdSnmp -Auto
    Write-Host '--- 8/9 WIA cho may in USB da chuc nang (neu co) ---'
    FP-AutoUsbWia
    if ($OneClick) {
        Write-Host '--- 9/9 Xoa ket noi/credential cu (1219): BO QUA o che do 1-Click vi muc nay can nguoi chon tay ---'
    } else {
        Write-Host '--- 9/9 (TUONG TAC - nhan Enter de bo qua): xoa ket noi/credential cu gay loi 1219 ---'
        FP-ClearStaleConnections
    }
    FP-Summary
    if ($OneClick) {
        FP-Warn 'XONG. Khoi dong lai may roi thu in. Neu van loi, mo CHAY_FIXPRINTER.bat chay Diagnose (menu 2) va gui file diagnose_report_v13.txt.'
    } else {
        FP-Warn 'XONG AUTO. Cac muc sau CO Y khong tu dong hoa (vao menu rieng khi can): [13] PnP COMPAT (kem an toan, phai go COMPAT), [15] WSD->IP (can IP may in), [7]/[16] ket noi/them may in (can duong dan), [10] chia se tu may chu, [18] go may in+driver (pha huy), [17]/[20] DISM/SFC va khoi phuc (nang), go KB o [27], go provider/hardening o [28] (can nguoi duyet vi danh doi bao mat).'
        FP-Warn 'Neu van chua in duoc: KHOI DONG LAI MAY roi chay Diagnose (menu 2) gui file diagnose_report_v13.txt de xem FLAG con lai.'
    }
}

function FP-RunAction {
    param([string]$Title, [scriptblock]$Body, [switch]$NoBackup)
    FP-BeginAction $Title
    if (-not $NoBackup) { [void](FP-BackupAll -Quiet) }
    & $Body
    FP-Summary
    FP-Pause
}

# ---- non-interactive args ----
$argLine = ($args -join ' ')
if ($argLine -match '--version') { Write-Host "FixPrinter $FPVersion"; return }
if ($argLine -match '--diagnose') {
    FP-BeginAction 'DIAGNOSE (chi doc)'
    FP-Diagnose
    FP-Summary
    return
}

# ---- admin gate ----
if (-not (FP-TestAdmin)) {
    Write-Host 'FixPrinter can quyen Administrator de sua. Dang mo lai voi quyen admin...' -ForegroundColor Yellow
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $argSuffix = ''
        if ($argLine) { $argSuffix = " $argLine" }
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"$argSuffix"
        $psi.Verb = 'runas'
        [void][System.Diagnostics.Process]::Start($psi)
    } catch { Write-Host 'Khong mo duoc quyen admin. Hay chuot phai -> Run as administrator.' -ForegroundColor Red; FP-Pause }
    return
}

# ---- 1-click mode: run AUTO, no menu, no questions (except final pause) ----
if ($argLine -match '--auto') {
    Clear-Host
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host '   FIX ALL PRINTER - MANG LAN: dang sua tat ca...' -ForegroundColor Cyan
    Write-Host '   Dung tat cua so nay khi dang chay.' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    FP-AutoFixAll -OneClick
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host '   DA XONG. KHOI DONG LAI MAY ROI THU IN.' -ForegroundColor Green
    Write-Host '   Chi tiet tung buoc: fixprinter_v13_log.txt' -ForegroundColor DarkGray
    Write-Host '============================================================' -ForegroundColor Green
    FP-Pause
    return
}

# ---- menu ----
while ($true) {
    FP-Header
    Write-Host ''
    Write-Host '  [1]  AUTO FIX ALL - TAT CA fix: quet KB/SID/AV + sua toan dien + muc tuong tac o cuoi'
    Write-Host '  [2]  DIAGNOSE - bao cao chan doan (chi doc, khong sua)'
    Write-Host '  [3]  Sua Print Spooler (ket hang doi, service sap)'
    Write-Host '  [4]  Sua tim thay may trong LAN (Private + discovery + firewall)'
    Write-Host '  [5]  Sua LAN/SMB may con: guest + ky SMB (loi 0x80070035 tren Win11 24H2)'
    Write-Host '  [6]  May nay lam MAY CHU: bat share + chia se may in'
    Write-Host '  [7]  Ket noi toi may in share cua may khac (\\MAYCHU\mayin)'
    Write-Host '  [8]  Them may in mang theo IP (TCP/IP / IPP)'
    Write-Host '  [9]  Fix 0x0000011b (chay tren MAY CHU)'
    Write-Host '  [10] Fix 0x00000bc4 / 0x00000709 - RPC named pipes (Win11 22H2+)'
    Write-Host '  [11] Fix 0x00000709 may in mac dinh + dat may in mac dinh'
    Write-Host '  [12] Point and Print: che do SAFE'
    Write-Host '  [13] Point and Print: che do COMPAT (de cai driver, kem an toan)'
    Write-Host '  [14] Fix 0x00000bcb (cai driver qua share bi chan)'
    Write-Host '  [15] Fix may in Offline / cong WSD / SNMP'
    Write-Host '  [16] Kiem tra Windows Protected Print Mode (Win11 24H2)'
    Write-Host '  [17] Test cac cong 135/139/445/515/631/9100 toi mot IP'
    Write-Host '  [18] DRIVER: Hardware ID / cai tu thu muc / backup / go sach'
    Write-Host '  [19] Reset network stack (winsock + TCP/IP) - can khoi dong lai'
    Write-Host '  [20] DISM + SFC (sua file he thong, chay lau)'
    Write-Host '  [21] UNDO - khoi phuc registry tu mot ban backup'
    Write-Host '  [22] Xoa ket noi share + credential cu (loi 1219, ket noi bi ket/sai pass)'
    Write-Host '  [23] Windows Ready Print: tat/bat uu tien driver IPP (mat tinh nang hang)'
    Write-Host '  [24] May in USB da chuc nang mat scan/fax, in ra chu POST/ipp (KB5079473)'
    Write-Host '  [25] Spooler loi 1068: dependency chet (LexBce/Ricoh...)'
    Write-Host '  [26] Fix 0x00000002 / 0x00000057 / 0x0000007e khi ket noi may in share'
    Write-Host '  [27] SAU KHI UPDATE WINDOWS bi hong in/LAN: doi chieu KB + ap lai cau hinh + go KB'
    Write-Host '  [28] Spooler bi antivirus/hardening tat-chan? (Defender, PrintNightmare, provider la)'
    Write-Host '  [L]  Mo file log'
    Write-Host '  [0]  Thoat'
    Write-Host ''
    $choice = Read-Host 'Chon'
    switch -Regex ($choice) {
        '^1$'  { FP-AutoFixAll; FP-Pause }
        '^2$'  { FP-RunAction 'DIAGNOSE REPORT' { FP-Diagnose } -NoBackup }
        '^3$'  { FP-RunAction 'FIX PRINT SPOOLER' { FP-FixSpooler } }
        '^4$'  { FP-RunAction 'FIX LAN DISCOVERY' { FP-FixDiscovery } }
        '^5$'  { FP-RunAction 'FIX SMB CLIENT (GUEST + SIGNING)' { FP-FixSmbClient } }
        '^6$'  { FP-RunAction 'SMB HOST / SHARE PRINTER' { FP-FixSmbHost } }
        '^7$'  { FP-RunAction 'CONNECT SHARED PRINTER' { FP-ConnectSharedPrinter } -NoBackup }
        '^8$'  { FP-RunAction 'ADD PRINTER BY IP' { FP-AddIpPrinter } -NoBackup }
        '^9$'  { FP-RunAction 'FIX 0x0000011b (HOST)' { FP-Fix11B } }
        '^10$' { FP-RunAction 'FIX RPC NAMED PIPES (0x00000bc4/0x00000709)' { FP-FixRpcNamedPipes } }
        '^11$' { FP-RunAction 'FIX DEFAULT PRINTER (0x00000709)' { FP-Fix709Default } }
        '^12$' { FP-RunAction 'POINT AND PRINT - SAFE' { FP-PnPSafe } }
        '^13$' { FP-RunAction 'POINT AND PRINT - COMPAT' { FP-PnPCompat } }
        '^14$' { FP-RunAction 'FIX 0x00000bcb' { FP-FixBcb } }
        '^15$' { FP-RunAction 'FIX OFFLINE / WSD / SNMP' { FP-FixOfflineWsdSnmp } }
        '^16$' { FP-RunAction 'WINDOWS PROTECTED PRINT MODE' { FP-CheckWpp } -NoBackup }
        '^17$' { FP-RunAction 'TEST PORTS' { FP-TestPorts } -NoBackup }
        '^18$' { FP-RunAction 'DRIVERS' { FP-DriverMenu } -NoBackup }
        '^19$' { FP-RunAction 'RESET NETWORK STACK' { FP-StackReset } }
        '^20$' { FP-RunAction 'DISM + SFC' { FP-DismSfc } -NoBackup }
        '^21$' { FP-RunAction 'UNDO / RESTORE BACKUP' { FP-UndoRestore } -NoBackup }
        '^22$' { FP-RunAction 'CLEAR STALE CONNECTIONS + CREDENTIALS (1219)' { FP-ClearStaleConnections } }
        '^23$' { FP-RunAction 'WINDOWS READY PRINT DRIVER RANKING' { FP-FixReadyPrint } }
        '^24$' { FP-RunAction 'USB MFP SCAN/FAX ASSISTANT' { FP-FixUsbMfp } -NoBackup }
        '^25$' { FP-RunAction 'FIX SPOOLER 1068 DEPENDENCIES' { FP-FixSpoolerDeps } }
        '^26$' { FP-RunAction 'FIX CONNECT ERRORS 0x2/0x57/0x7e' { FP-FixConnectErrors } }
        '^27$' { FP-RunAction 'POST-UPDATE RECOVERY (KB)' { FP-PostUpdateRecovery } }
        '^28$' { FP-RunAction 'SPOOLER VS ANTIVIRUS / HARDENING' { FP-SpoolerAvCheck } }
        '^[Ll]$' {
            if (Test-Path $script:FPLog) { Start-Process notepad.exe $script:FPLog } else { Write-Host 'Chua co log.' }
            FP-Pause
        }
        '^0$'  { return }
        default { Write-Host 'Lua chon khong hop le.' -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
    }
}
