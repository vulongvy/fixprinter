# BÁO CÁO AUDIT FixPrinter v12.0.3 — vì sao "không còn tác dụng"

Đã bung gói cài đặt (Inno Setup 6.7.0) và dịch ngược toàn bộ `Fixprinter.dll`
(40 KB IL, 1 file Program.cs, .NET 8) để đối chiếu từng lệnh. Kết luận dưới đây
là từ code thật, không phải đoán theo giao diện.

## A. Ba lỗi CHẾT khiến các fix quan trọng nhất không hề chạy

1. **Mục 12 "Đặt máy in mặc định" không bao giờ chạy được.**
   Code dùng `Set-Printer -Name '...' -IsDefault $true`. Cmdlet `Set-Printer`
   của Windows **không có tham số `-IsDefault`** → PowerShell báo lỗi binding
   mỗi lần chạy. Đặt mặc định đúng cách phải qua CIM `Win32_Printer.SetDefaultPrinter()`
   hoặc `printui /y`. → v13 menu 11 dùng CIM + đọc lại cờ Default để xác nhận.

2. **Mục 14 "tắt SNMP" là lệnh sai tham số, lỗi bị nuốt.**
   Code chạy `Set-PrinterPort -SNMP 0` trong `try { } catch { }`. Tham số đúng
   là `-SNMPEnabled $false`. Lệnh chết lặng, tool vẫn in "repair completed".
   Phần WSD thì chỉ **liệt kê** cổng WSD ra màn hình, không chuyển cổng nào cả —
   trong khi chuyển WSD → TCP/IP mới là cách trị offline giả. → v13 menu 15 làm thật cả hai.

3. **Fix 0x00000bc4 ghi registry SAI CHỖ.**
   Từ Windows 11 22H2, cấu hình RPC cho in ấn nằm ở
   `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC`
   (`RpcUseNamedPipeProtocol`, `RpcProtocols`). v12 ghi hai giá trị này vào
   `HKLM\SYSTEM\CurrentControlSet\Control\Print` — nơi Windows không đọc cho
   mục đích này — và mục 10 (0x00000bc4) thậm chí không ghi RPC ở key nào cả.
   → Trên Win11 22H2/23H2/24H2, fix 0x00000bc4 và nhánh RPC của 0x00000709
   **không có tác dụng**. v13 menu 10 ghi đúng key policy + dọn giá trị sai chỗ của bản cũ.

## B. Lỗi THIẾU NỬA BÀI TOÁN — nguyên nhân lớn nhất trên máy mới (Win11 24H2)

4. **Fix LAN/SMB chỉ làm 1/2.** v12 bật guest (`AllowInsecureGuestAuth` +
   `EnableInsecureGuestLogons`) nhưng **không đụng tới `RequireSecuritySignature`**.
   Từ 24H2, bản Pro/Enterprise/Education **bắt buộc ký SMB** mặc định; phiên guest
   không có credential nên **không ký được** → vẫn lỗi 0x80070035 / "security
   policies block unauthenticated guest access" dù guest đã bật. Chính Diagnose
   của v12 có đọc trường này nhưng Fix thì không sửa. → v13 menu 5 xử lý cả hai
   lớp bằng `Set-SmbClientConfiguration` và **đọc lại trạng thái hiệu lực** để xác nhận.

## C. Những thứ v12 KHÔNG HỀ CÓ (đã kiểm tra toàn bộ IL)

- Không chuyển **Network Profile Public → Private** (Public chặn toàn bộ discovery/share — ca LAN phổ biến nhất).
- Không có chức năng **chia sẻ máy in từ máy chủ** (bật share, đặt share name) và không có chức năng **kết nối tới máy in share** (`Add-Printer -ConnectionName`) hay **thêm máy in theo IP** (`Add-PrinterPort`/`Add-Printer`) — ba thao tác thợ dùng nhiều nhất.
- Không phát hiện **Windows Protected Print Mode** (24H2): mục 19 chỉ mở trang Settings. Máy nào bật WPP sẽ bị gỡ máy in dùng driver hãng — v12 không nhận biết được.
- Không gỡ driver/máy in hỏng tận gốc (`Remove-PrinterDriver`), không xử lý credential cũ (lỗi 1219), không mDNS.
- Fix 0x000006ba chỉ sửa spooler **tại máy đang chạy tool**, trong khi lỗi này thường do spooler của **máy chủ** chết — tool không có khái niệm kiểm tra máy đích.

## D. Lỗi thiết kế / rủi ro

- **AUTO FIX ALL áp sẵn chế độ Point & Print KÉM AN TOÀN** (`RestrictDriverInstallationToAdministrators=0`) làm mặc định cho mọi máy — mở lại bề mặt PrintNightmare mà không cảnh báo. v13 AUTO dùng bản SAFE; COMPAT phải gõ chữ xác nhận.
- **Clean Policy xoá nguyên cả key** PointAndPrint + PackagePointAndPrint + RPC policy + DeviceInstall Restrictions — xoá cả cấu hình đúng của người khác, lại chạy ngay trước Fix0011B trong Auto (tự mâu thuẫn).
- **Backup ghi đè chính nó:** mọi lần chạy đều export vào cùng thư mục `backup\` với `/y` → lần chạy thứ hai, "bản gốc" bị thay bằng trạng thái đã sửa. v13 backup theo timestamp, không bao giờ ghi đè, có thêm PrintBrm + snapshot máy in, và có menu UNDO (21).
- **Spooler Guard = scheduled task mỗi 1 phút** chạy PowerShell ẩn (1.440 lần/ngày) chỉ để giữ spooler sống — cơ chế `sc failure` của Windows làm việc này tốt hơn nhiều. v13 cấu hình recovery 1 lần và **tự gỡ task Guard của v12** khi gặp.
- Ép service **Browser** sang Automatic — service này đã bị gỡ khỏi Windows 11 cùng SMB1, lệnh chỉ sinh lỗi.
- "Fix Office/PDF" thực chất chỉ restart spooler + 1 giá trị default printer.
- Mọi fix đều **không xác nhận kết quả**: set xong không đọc lại. Lệnh hỏng → vẫn in completed (trừ khi exit code khác 0 ở tầng ngoài). v13: mỗi bước PASS/FAIL/SKIP kèm đọc lại giá trị hiệu lực, cuối mỗi mục có tổng kết.
- Menu lẫn **Fix Microsoft Store** và **Fix Realtek Audio** — ngoài phạm vi máy in, làm tool phình và khó bảo trì. v13 bỏ hẳn hai mục này (nếu cần, làm tool riêng).

## E. Phần v12 làm ĐÚNG (v13 giữ lại)

- Giá trị Point & Print SAFE/COMPAT đúng chuẩn sau PrintNightmare.
- `RpcAuthnLevelPrivacyEnabled=0` đúng key (phía máy chủ) cho 0x0000011b.
- Spooler: stop → xoá file trong `spool\PRINTERS` → start (đúng bài trị kẹt hàng đợi).
- `LegacyDefaultPrinterMode=1` cho nhánh default-printer của 0x00000709.
- Bật firewall group File and Printer Sharing / Network Discovery, discovery services.
- pnputil add-driver/export-driver + báo cáo Hardware ID.
- Có log file và có ý tưởng backup registry trước khi sửa.

---
*Phương pháp: bung Inno bằng innoextract 1.13, bung .NET single-file bundle
(171 file), dịch ngược IL của Fixprinter.dll và đối chiếu từng lệnh với tài
liệu Microsoft hiện hành (SMB signing 24H2, RPC over named pipes 22H2+,
Windows Protected Print Mode, PrintNightmare Point & Print).*
