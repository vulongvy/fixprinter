# PHÂN TÍCH TỔNG HỢP: Bản vá Windows phá in ấn/LAN + Spooler vs Antivirus

Tài liệu tổng hợp cho FixPrinter v13.2 (07/11/2026). Hai vấn đề được thợ gặp
liên tục ngoài hiện trường: (1) khách vừa update Windows xong là in/share chết,
không rõ bản nào phá; (2) Print Spooler cứ tự tắt — lúc do driver, lúc do phần
mềm bảo mật cố tình tắt vì spooler chính là cửa ngõ tấn công nổi tiếng nhất
của Windows.

---

## PHẦN 1 — Các bản vá phá in ấn / LAN, theo thời gian

| Thời điểm | KB / sự kiện | Nó thay đổi cái gì | Triệu chứng ở hiện trường |
|---|---|---|---|
| 01/2021 | CVE-2021-1678 (KB4599464 mô tả) | Nâng mức xác thực RPC của spooler (`RpcAuthnLevelPrivacyEnabled`) | Tiền thân của lỗi 0x0000011b |
| 06–07/2021 | **PrintNightmare** CVE-2021-34527, vá khẩn KB5004945 | Lỗ hổng cho phép user thường nạp DLL tùy ý chạy quyền SYSTEM qua spooler | Cú sốc khiến Microsoft siết toàn bộ hệ in ấn từ đây |
| 10/08/2021 | KB5005652 (CVE-2021-34481) | Point and Print: mặc định **chỉ admin mới cài được driver** qua share | User thường kết nối máy in share bị đòi quyền admin |
| 14/09/2021 | KB5005565 + anh em theo phiên bản | Bắt buộc thực thi mức xác thực RPC mới | **Sóng 0x0000011b** giữa các máy lệch mức update |
| 12/10/2021 | KB5006670 (Win10) / KB5006674 (Win11) | Lỗi known-issue chính thức của Microsoft | **0x0000007c / 0x00000709 / 0x000006e4** khi kết nối máy in share; vá bởi KB5007253/KB5007262 (22/11/2021) |
| 09/11/2021 | KB5007186 | Tiếp nối đợt trên | 0x00000709/0x7c dai dẳng ở máy chưa lên bản vá tháng 11 |
| 11–12/2023 | Metadata HP lỗi (troubleshooter KB5034510) | Không phải KB phá — metadata qua Windows Update bị sai | Mọi máy in bị **đổi tên thành "HP LaserJet M101-M106"**, HP Smart tự cài; in vẫn chạy |
| 10/2024 | Lên **24H2** (thay đổi tính năng, không phải KB đơn lẻ) | Bắt buộc **ký SMB** (Pro/Ent/Edu), **chặn guest SMB** ở Pro, firewall bỏ rule NetBIOS 137–139, thêm WPP | Share/NAS cũ chết **0x80070035**, scan-to-folder chết — "hỏng sau khi lên bản lớn" |
| 01/2025 | KB5050092 (preview) | Lỗi IPP-over-USB | Máy in USB in ra trang rác **"POST /ipp/print HTTP/1.1"**; vá ở KB5053657 (03/2025) |
| 08–09/2025 | KB5064081 (preview) / **KB5065426** | Siết xác thực máy: **PC clone trùng SID bị chặn** Kerberos/NTLM qua lại; cộng đồng ghi nhận thêm profile mạng bị lật về Public, discovery/share bị tắt | Máy nhân bản từ một ảnh gốc: RDP/SMB/**in share chết 0xc000006d**, LsaSrv Event 6167. Microsoft phát hành **KIR** riêng cho vụ này |
| 15/01/2026 & 01/07/2026 | Lộ trình driver (không phải KB) | Ngừng nhận driver hãng mới qua Windows Update; sau đó **Windows Ready Print** ưu tiên driver IPP của Microsoft | Cài lại máy in thì mất tính năng hãng (menu 23 của tool) |
| 03/2026 | KB5079473 | Lỗi IPP-over-USB phía scan | Máy in USB đa chức năng **mất scan/fax**; Microsoft xác nhận, chưa vá triệt để (menu 24) |
| 04/2026 | KB5083769 | Lỗi đăng ký hàng đợi Universal Print dạng system-wide | Chỉ môi trường **Universal Print cloud** (doanh nghiệp): 0x80004005, test page 0x000003e3 — LAN thường không dính |

### 5 cơ chế phá — nhớ cơ chế, không cần nhớ số KB

1. **Đổi mặc định bảo mật** (đợt 2021, 24H2, KB5065426): update không "làm hỏng"
   mà *siết luật* — máy nào đang sống nhờ cấu hình lỏng (guest, không ký, user
   tự cài driver, SID trùng) sẽ chết ngay sau update. Cách xử lý đúng là cấu
   hình lại theo luật mới hoặc nới có chủ đích (menu 5, 9, 12/13, 27).
2. **Hai máy lệch mức update** (0x0000011b kinh điển): máy chủ đã siết, máy con
   chưa (hoặc ngược lại) → bắt tay RPC thất bại. Thuốc đặc trị rẻ nhất: **cập
   nhật cả hai máy** trước khi nghịch registry.
3. **Update reset cấu hình** (KB5065426 lật profile, feature update): mạng về
   Public, discovery/share tắt, máy in mặc định đổi. → Gói "áp lại cấu hình"
   ở menu 27 xử lý đúng nhóm này.
4. **Thay tầng driver** (Ready Print 07/2026, WPP): máy in không chết mà bị
   *đổi tài xế* — mất tính năng. Nhận biết: DriverName biến thành
   "Microsoft IPP Class Driver".
5. **Bug thật trong bản vá** (KB5006670 năm 2021, KB5050092, KB5079473): ít gặp
   nhất nhưng có thật. Dấu hiệu: triệu chứng khop known-issue Microsoft đã
   công bố. Xử lý: chờ bản vá tiếp theo/KIR, gỡ KB chỉ là cầu giờ cuối cùng.

> Bài học rút ra cho thợ: "hỏng sau update" **đa số không phải bug** mà là cơ
> chế 1–3. Gỡ KB bừa vừa hở bảo mật vừa vô ích (tháng sau nó cài lại). Đối
> chiếu KB + triệu chứng trước, sửa theo cơ chế — đó là cách menu 27 làm.

---

## PHẦN 2 — Print Spooler: vì sao antivirus/Defender "ghét" nó

### Spooler là bề mặt tấn công hạng nặng

- `spoolsv.exe` chạy quyền **SYSTEM**, mặc định bật trên mọi máy Windows, nghe
  RPC từ mạng.
- PrintNightmare (CVE-2021-34527, đi cùng CVE-2021-1675): bất kỳ user đã xác
  thực nào cũng gọi được `RpcAddPrinterDriverEx` để spooler nạp một DLL tùy ý
  như thể driver in → **chiếm SYSTEM từ xa**, từng bị ransomware khai thác
  (Vice Society...). Trước/sau đó là cả dãy CVE spooler khác: PrintDemon
  (CVE-2020-1048), CVE-2021-34481, CVE-2021-36958, SpoolFool
  (CVE-2022-21999), CVE-2022-38028 (bị khai thác thực tế)...
- Vì vậy lập trường chính thức của giới bảo mật: **máy không in thì tắt hẳn
  spooler**; domain controller tuyệt đối tắt (Microsoft Defender for Identity
  còn gắn cờ DC nào để spooler chạy). Đây là lý do spooler "tự nhiên bị tắt"
  trên nhiều máy: *có người/công cụ đã cố tình tắt nó*.

### 4 thủ phạm tắt/chặn spooler hay gặp ngoài hiện trường

1. **GPO hardening sau PrintNightmare** (môi trường công ty/trường học): policy
   tắt service, hoặc `RegisterSpoolerRemoteRpcEndPoint = 2` — spooler chạy, in
   cục bộ được, nhưng **từ chối in từ xa** → máy đó không làm máy chủ share
   được. Nhận biết: Diagnose của tool đọc thẳng giá trị này.
2. **Tool debloat/"tối ưu Windows"** của khách: Print Spooler nằm trong danh
   sách "service thừa nên tắt" của gần như mọi script debloat → StartType bị
   đặt **Disabled**. Nhận biết: Event **7040** (Service Control Manager) ghi
   lại đúng thời điểm kiểu khởi động của Spooler bị đổi — Diagnose v13.2 đếm
   và trích 3 lần gần nhất trong 30 ngày.
3. **Antivirus xung đột thật**: AV cách ly/xóa nhầm file driver in hoặc chính
   `spoolsv.exe` (đã có ca ghi nhận), HIPS chặn spooler nạp DLL driver, quét
   thời gian thực khóa file trong `spool\PRINTERS` làm spooler sập. Chiều
   ngược lại cũng có thật: `spoolsv.exe` **bị vá bởi malware** (Win32/Patched)
   thì AV bắt là đúng. Phân biệt bằng **chữ ký số**: menu 28 kiểm tra
   spoolsv.exe còn đúng file Microsoft ký hay không + quét log Defender
   (Event 1116/1117) xem nó đã chạm vào cái gì liên quan spool/print.
4. **Không phải AV mà là driver/provider chết**: driver in bên thứ ba nạp DLL
   vào tiến trình spooler — DLL lỗi là spooler sập theo (Event 7031/7034, xem
   ở Diagnose). Thủ phạm kinh điển nữa: **Print Provider lạ** do phần mềm in
   cũ để lại trong `Control\Print\Providers` (chỉ 2 provider mặc định của
   Microsoft là chuẩn) — menu 28 liệt kê và cho gỡ có backup.

### Quy tắc xử lý của tool (và của thợ)

- Spooler bị tắt: **đừng chỉ bật lại** — truy nguyên nhân trước (7040, policy,
  AV). Bật lại mà thủ phạm còn đó thì vài hôm sau nó tắt tiếp, khách lại gọi.
- Máy khách là máy chủ in LAN: hardening PrintNightmare (mục 1) và nhu cầu
  share **xung đột trực tiếp** với nhau. Gỡ hardening (menu 28) chỉ khi: máy
  đã vá đầy đủ, ở LAN tin cậy, và chủ máy chấp nhận đánh đổi — tool luôn cảnh
  báo trước khi gỡ.
- File thực thi lạ (.exe/.dll/.bat...) nằm trong `spool\PRINTERS`: dấu hiệu
  khai thác spooler/malware — **quét virus trước, sửa in sau**. Menu 28 tự
  động quét mục này.

---

## PHẦN 3 — v13.2 làm gì với hai vấn đề này

- **Menu 27 (Sau update Windows):** đối chiếu kho KB ở Phần 1 với máy thật →
  áp lại gói cấu hình hay bị reset → kiểm tra dấu hiệu **trùng SID**
  (LsaSrv 6167, Security 4625/0xc000006d trong 14 ngày + in Machine SID để so
  giữa các máy) → gỡ KB bằng `wusa` như phương án cuối, phải gõ chữ xác nhận.
- **Menu 28 (Spooler vs AV/hardening):** liệt kê AV đang cài → kiểm tra chữ ký
  spoolsv.exe → log Defender chạm spool/print → trạng thái
  RegisterSpoolerRemoteRpcEndPoint (gỡ có cảnh báo) → Print Provider lạ →
  file thực thi lạ trong hàng đợi.
- **Diagnose:** thêm đối chiếu KB, danh sách AV, hardening PrintNightmare,
  Event 7040 của Spooler, Print Provider — để gửi file báo cáo là thấy được
  cả "bản vá nào" lẫn "ai tắt spooler".

*Nguồn chính: Microsoft Learn/Q&A và support articles (known issue của
KB5006670, duplicate SID KB5065426 + KIR, SMB signing control), Citrix
CTX695388, Windows release health, báo cáo cộng đồng đã đối chiếu chéo
(uGetFix, Winhelponline, CheckYourLogs). Mục KB5083769 dựa trên thông tin báo
chí chuyên ngành tại thời điểm viết, phạm vi Universal Print doanh nghiệp.*
