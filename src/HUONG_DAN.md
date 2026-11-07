# FixPrinter v13.4 — Hướng dẫn dùng

Bản viết lại từ v12.0.3. Nguyên tắc của bản này: **backup trước — sửa xong đọc
lại trạng thái thật để xác nhận — báo PASS/FAIL/SKIP từng bước**. Không còn
chuyện "báo completed mà không đổi gì".

## Chạy tool

1. Giải nén nguyên thư mục `FixPrinter_v13_4` (để ở đâu cũng được, tool tự tìm đường).
2. Bấm đúp **`FIX_ALL_PRINTER_MANG_LAN.bat`** → bấm Yes khi Windows hỏi quyền
   Administrator → **xong, không phải bấm gì nữa**. Tool tự quét (KB gây lỗi,
   trùng SID, Spooler vs antivirus) rồi sửa toàn bộ: Spooler, LAN/SMB, RPC,
   Point and Print, máy in mặc định, offline, WIA-USB — có backup trước.
3. Chạy xong thì **khởi động lại máy rồi thử in**.
4. Chỉ khi 1-click chưa xử lý được ca khó mới cần mở `CHAY_FIXPRINTER.bat`
   (menu đầy đủ: Diagnose chi tiết, UNDO khôi phục, xử lý riêng từng mã lỗi,
   xoá kết nối cũ 1219, gỡ KB/provider có duyệt tay...).

Mọi thao tác sửa đều tự backup registry vào `backup\<thời-gian>\` kèm snapshot
danh sách máy in/driver và file PrintBrm (nếu máy có). Muốn hoàn tác: menu **[21] UNDO**.

## Tra nhanh theo mã lỗi / triệu chứng

| Triệu chứng | Chạy ở đâu | Menu |
|---|---|---|
| Chưa rõ lỗi, muốn sửa tổng lực | Máy đang lỗi | [1] AUTO FIX ALL |
| Ping được IP nhưng gõ `\\IP` không vào, lỗi 0x80070035 (Win11 24H2) | Máy con | [5] SMB client (guest + ký SMB) |
| Máy khác không thấy máy này / không thấy máy in share trong Network | Cả hai máy | [4] Discovery (Private + dịch vụ + firewall) |
| Máy này gắn máy in USB, muốn chia sẻ cho cả phòng | Máy chủ | [6] SMB host + chia sẻ máy in |
| Kết nối tới máy in share của máy khác | Máy con | [7] Connect `\\MAYCHU\share` |
| Máy in có IP riêng (in qua mạng LAN/WiFi) | Máy con | [8] Add printer by IP |
| 0x0000011b khi kết nối máy in share | **Máy chủ** | [9] (sau đó khởi động lại/kết nối lại ở máy con) |
| 0x00000bc4 "No printers were found" (Win11 22H2+) | Máy con (+ máy chủ nếu cũng 22H2+) | [10] RPC named pipes |
| 0x00000709 khi đặt mặc định / khi kết nối | Máy con | [10] + [11] |
| Không đặt được máy in mặc định | Máy con | [11] |
| 0x00000bcb (cài driver qua share bị chặn) | Máy con | [14], hoặc cài driver trước bằng [18] rồi kết nối lại |
| Máy in báo Offline dù đang bật (cổng WSD/SNMP) | Máy con | [15] (cần biết IP thật của máy in để chuyển cổng) |
| Máy in biến mất sau khi bật Protected Print (24H2) | Máy con | [16] kiểm tra WPP |
| Kẹt hàng đợi in, spooler tự tắt | Máy đang lỗi | [3] Spooler |
| Test xem cổng nào tới máy in/máy chủ đang mở | Máy con | [17] |
| Thiếu driver, cài driver từ thư mục, backup driver, gỡ máy in sạch | — | [18] |
| Mạng chập chờn sau khi nghịch cấu hình | — | [19] Reset stack (phải khởi động lại) |
| Lỗi 1219 (một máy chủ, hai tài khoản), kết nối share cũ bị kẹt, sai mật khẩu đã lưu | Máy con | [22] Xoá kết nối + credential cũ |
| Cài lại máy in thì mất khay giấy phụ/finisher/in bảo mật, driver biến thành "Microsoft IPP Class Driver" | Máy con | [23] Tắt ưu tiên Ready Print rồi cài lại driver hãng |
| Máy in USB in được nhưng mất scan/fax sau khi update Windows (KB5079473) | Máy con | [24] Trợ lý USB MFP + gỡ/cắm lại theo hướng dẫn |
| In ra trang toàn chữ "POST /ipp/print HTTP/1.1" qua USB | Máy con | [24] + chạy Windows Update (đã vá từ KB5053657) |
| Spooler không start, lỗi 1068 "dependency service failed to start" | Máy đang lỗi | [3] (tự gồm) hoặc [25] riêng |
| 0x00000002 / 0x00000057 / 0x000005b3 khi kết nối máy in share | Máy con | [26] Gỡ sạch driver hỏng rồi kết nối lại |
| 0x0000007e khi kết nối (driver HP Universal...) | **Máy chủ** | [26] chọn vai trò máy chủ — xoá CopyFiles của driver |
| Spooler tự sập liên tục | Máy đang lỗi | [2] Diagnose xem số lần sập 7 ngày + log PrintService, nghi driver vừa cài → [18] |
| Vừa update Windows xong thì in/share chết | Máy đang lỗi | [27] Đối chiếu KB + áp lại cấu hình + kiểm tra trùng SID + (cuối cùng) gỡ KB |
| Nhiều máy nhân bản (clone) từ một bản cài: in share/RDP chết 0xc000006d sau update 09/2025 | Các máy clone | [27] mục kiểm tra SID — gốc là trùng SID, xử lý đúng là sysprep; KIR/gỡ KB chỉ tạm thời |
| Spooler bị tắt hoài, bật lại vài hôm lại tắt | Máy đang lỗi | [2] xem Event 7040 (ai/cái gì đổi kiểu khởi động) + [28] |
| Máy này in cục bộ được nhưng máy khác không in vào share của nó được | Máy chủ | [28] kiểm tra hardening PrintNightmare (RegisterSpoolerRemoteRpcEndPoint=2) |
| Nghi antivirus xung đột với spooler / spoolsv.exe bị cách ly | Máy đang lỗi | [28] kiểm tra chữ ký spoolsv.exe + log Defender |

## Cập nhật v13.4 (07/11/2026) — 1-click FIX ALL PRINTER - MẠNG LAN

- Trải nghiệm chính giờ là **một cú bấm đúp** vào `FIX_ALL_PRINTER_MANG_LAN.bat`:
  tự xin quyền admin, chạy thẳng toàn bộ AUTO FIX ALL, không menu, không câu
  hỏi (mục tương tác 1219 tự bỏ qua), dừng một lần ở cuối để đọc kết quả.
- Menu 28 mục vẫn giữ nguyên trong `CHAY_FIXPRINTER.bat` cho ca khó — nhưng
  là đồ nghề của thợ, không phải thứ khách phải đọc.

## Cập nhật v13.3 (07/11/2026) — AUTO FIX ALL dồn tất cả fix vào menu 1

- **[1] AUTO FIX ALL viết lại thành 10 bước:** bước 0 quét chỉ báo cáo (đối
  chiếu KB gây lỗi, kiểm tra trùng SID, chữ ký spoolsv.exe, log Defender,
  Print Provider lạ, file lạ trong hàng đợi, trạng thái WPP/Ready Print) →
  backup → 7 bước sửa như trước (Spooler đã gồm fix 1068) → WIA cho máy in
  USB → mục tương tác xoá kết nối/credential cũ (1219) ở cuối, Enter là bỏ qua.
- Các mục phá huỷ/cần nhập liệu/cần duyệt bảo mật vẫn ở menu riêng theo chủ
  đích (danh sách in ngay khi AUTO chạy xong) — AUTO không tự gỡ KB, không tự
  gỡ hardening/provider, không tự bật bản COMPAT kém an toàn.

## Cập nhật v13.2 (07/11/2026) — bản vá Windows + Spooler vs Antivirus

- **[27] Khôi phục sau update Windows:** kho dữ liệu các KB từng phá in/LAN
  (từ đợt PrintNightmare 2021 tới KB5065426/KB5079473) được đối chiếu tự động
  với máy đang chạy; gói áp lại cấu hình hay bị update reset (Private +
  discovery + SMB + PnP SAFE); kiểm tra dấu hiệu **trùng SID** ở máy clone;
  gỡ KB bằng wusa như phương án cuối (phải gõ chữ xác nhận).
- **[28] Spooler vs antivirus/hardening:** phân biệt spooler bị *tắt bởi kiểm
  soát bảo mật* với spooler bị *bệnh/tấn công* — kiểm tra chữ ký spoolsv.exe,
  log Defender chạm spool/print, hardening `RegisterSpoolerRemoteRpcEndPoint`,
  Print Provider lạ của phần mềm in cũ, file thực thi lạ trong hàng đợi.
- **Diagnose:** thêm đối chiếu KB, danh sách AV đang cài, Event 7040 (lịch sử
  thay đổi kiểu khởi động của Spooler — truy thủ phạm tắt spooler), trạng thái
  hardening PrintNightmare, Print Provider. Sửa lại mô tả ký SMB 24H2 cho đúng
  tài liệu Microsoft: bắt buộc ở Pro/Enterprise/Education, Home không bị ép.
- Tài liệu phân tích đầy đủ: `PHAN_TICH_KB_VA_SPOOLER.md`.

## Cập nhật v13.1 (07/11/2026) — từ nghiên cứu lỗi thực tế mới

- **[25] Spooler 1068:** phần mềm máy in cũ (Lexmark LexBce, Ricoh...) khi gỡ ra
  vẫn để lại "dependency chết" khiến Spooler không bao giờ start được. Menu [3]
  giờ tự kiểm tra và reset dependency về RPCSS/HTTP.
- **[22] Lỗi 1219 + credential cũ:** liệt kê/xoá kết nối máy in share đã lưu
  (HKCU), credential SMB đã lưu theo từng máy chủ (cmdkey) và phiên net use.
- **[23] Windows Ready Print ranking:** từ 07/2026 Windows mặc định ưu tiên
  driver IPP của Microsoft khi cài máy in mới (mất tính năng hãng). Menu này
  đọc/ghi policy `ConfigureWindowsReadyPrintDriverRanking` để tắt/bật có chủ đích.
- **[24] USB MFP mất scan/fax:** KB5079473 (03/2026) — Microsoft đã xác nhận,
  chưa có vá triệt để; tool kiểm tra KB, ép dịch vụ WIA và hướng dẫn gỡ/cắm lại đúng cách.
- **[26] Nhóm lỗi driver hỏng 0x2/0x57/0x5b3 (máy con) và 0x7e (máy chủ):**
  gỡ sạch driver trên máy con rồi kết nối lại; phía máy chủ xoá mục CopyFiles
  (ICM/BIDI) của driver sau khi đã export backup.
- **Diagnose thêm 5 mục:** dependency của Spooler, số lần Spooler sập + lỗi
  PrintService trong 7 ngày (Event Log), danh sách kết nối share đã lưu,
  trạng thái Ready Print ranking, trạng thái WIA + danh sách update gần đây
  (để đối chiếu "hỏng ngay sau khi update").

## Điểm khác biệt cốt lõi so với v12

- Fix LAN/SMB xử lý **cả hai lớp của 24H2**: bật guest **và** tắt bắt buộc ký SMB
  (`RequireSecuritySignature`), có đọc lại `Get-SmbClientConfiguration` xác nhận.
- Fix RPC ghi **đúng key policy** `Policies\...\Printers\RPC` (v12 ghi sai chỗ).
- Đặt máy in mặc định bằng **CIM SetDefaultPrinter** (v12 dùng tham số không tồn tại).
- Tắt SNMP bằng **`-SNMPEnabled $false`** và **chuyển thật cổng WSD → TCP/IP** (v12 chỉ liệt kê).
- AUTO FIX dùng Point & Print **SAFE**; bản COMPAT (kém an toàn) phải gõ `COMPAT` mới áp.
- Không còn task chạy mỗi phút: thay bằng cấu hình tự khởi động lại của service Spooler.
  Nếu máy từng chạy v12, v13 tự gỡ task `LAN_Printer_Spooler_Guard` khi sửa Spooler.
- Thêm hẳn các chức năng v12 không có: chuyển mạng sang Private, chia sẻ máy in
  từ máy chủ, kết nối máy in share, thêm máy in theo IP, kiểm tra WPP, gỡ máy in + driver sạch, UNDO.
- Bỏ Fix Microsoft Store và Fix Realtek Audio (ngoài phạm vi máy in).

## Lưu ý an toàn (đọc trước khi đưa khách dùng)

- Menu [5] và [13] **làm giảm bảo mật có chủ đích** để tương thích LAN cũ
  (guest SMB, tắt bắt buộc ký, user thường tự cài driver). Chỉ dùng trong mạng
  tin cậy; tuyệt đối không mở cổng 445 ra Internet. Sau khi nối được máy in,
  cân nhắc chạy lại [12] SAFE để siết lại Point & Print.
- Fix 0x0000011b (menu [9]) hạ một lớp bảo vệ RPC **trên máy chủ** — là đường
  vòng tương thích, cách đúng lâu dài là cập nhật Windows cả hai máy.
- Mọi thay đổi đều có backup: nếu sửa xong tệ hơn, chạy [21] UNDO và khởi động lại.

## File trong gói

- `FIX_ALL_PRINTER_MANG_LAN.bat` — **file chính: bấm đúp 1 cái là sửa tất cả** (tự nâng quyền, chạy thẳng AUTO không hỏi)
- `CHAY_FIXPRINTER.bat` — launcher menu đầy đủ (tự nâng quyền, có log riêng `launcher_log.txt`) — chỉ dùng khi cần xử lý riêng/UNDO
- `FixPrinter.ps1` — chương trình chính + menu
- `lib\` — 9 module: Core (log/backup/kiểm tra), Diagnose, Spooler, LanPrint
  (LAN/SMB/share/kết nối/thêm máy in IP), PrintFixes (các mã lỗi), Drivers,
  SystemTools, ExtraFixes (menu 22–26), UpdateFixes (kho KB + menu 27–28)
- `BAO_CAO_LOI_V12.md` — báo cáo audit chi tiết vì sao v12 hết tác dụng
- `CAP_NHAT_V13_1.md`, `PHAN_TICH_KB_VA_SPOOLER.md` — ghi chú cập nhật và phân tích tổng hợp
- Log chạy: `fixprinter_v13_log.txt`; báo cáo chẩn đoán: `diagnose_report_v13.txt`
- Tham số dòng lệnh: `FixPrinter.ps1 --diagnose` (chẩn đoán rồi thoát), `--version`

*Yêu cầu: Windows 10/11, PowerShell 5.1 (có sẵn trong Windows), quyền Administrator.*
