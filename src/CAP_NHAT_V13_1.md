# FixPrinter v13.1 — Ghi chú cập nhật (07/11/2026)

Các mục mới được bổ sung sau khi rà soát tài liệu Microsoft hiện hành, baseline
bảo mật Windows 11 26H2 và các lỗi in ấn được ghi nhận trong năm 2026. Mỗi mục
đều theo nguyên tắc cũ: kiểm tra trạng thái thật trước, chỉ sửa khi đúng bệnh,
sửa xong đọc lại xác nhận.

## 1. Spooler lỗi 1068 — dependency chết (menu 25, và tự chạy trong menu 3)

Phần mềm/driver máy in của hãng thứ ba (điển hình: Lexmark `LexBceS`, Ricoh
`RProcessWatcher`) đăng ký service của chúng làm dependency của Print Spooler.
Khi gỡ phần mềm, service biến mất nhưng dòng dependency còn lại → Spooler báo
1068 "The dependency service or group failed to start" và không start được dù
reset bao nhiêu lần. Tool đọc `DependOnService`, đối chiếu từng mục với
registry Services, chỉ khi thấy dependency **đã bị xoá khỏi máy** mới đề nghị
reset về mặc định `RPCSS/HTTP` bằng `sc config`, rồi đọc lại xác nhận.
Nguồn: Winhelponline / Microsoft Q&A về error 1068.

## 2. Lỗi 1219 + kết nối/credential cũ (menu 22)

1219 = "Multiple connections to a server by the same user using more than one
user name are not allowed". Nguyên nhân thường gặp ở tiệm: máy con từng kết nối
tới máy chủ bằng tài khoản A (hoặc guest), giờ kết nối bằng tài khoản B.
Tool cho xoá có chọn lọc: kết nối máy in share đã lưu trong
`HKCU\Printers\Connections`, credential SMB đã lưu khớp tên máy chủ (cmdkey),
và (chỉ khi xác nhận) toàn bộ phiên `net use`. Kết nối ở menu 7 nay cũng dịch
mã 1219 ra hướng xử lý này.

## 3. Windows Ready Print driver ranking (menu 23)

Từ 01/07/2026, khi cài **mới** máy in hỗ trợ IPP (qua USB hoặc tìm thấy trong
mạng), Windows ưu tiên **Microsoft IPP Class Driver** thay cho driver hãng —
máy in mất khay giấy phụ, finisher, in bảo mật, mã kế toán... mà không hề báo
lỗi. Bản 26H2 security baseline của Microsoft còn khuyến nghị *khoá bật* chính
sách này. Tool đọc/ghi policy chính thức:
`HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers`,
DWORD `ConfigureWindowsReadyPrintDriverRanking` (1 = ưu tiên IPP, 0 = tắt ưu
tiên — theo Microsoft Learn, *Printers Policy CSP*, áp dụng từ 24H2
KB5095093 / 25H2 / 26H2). Diagnose cũng in trạng thái này kèm FLAG khi có máy
in đang chạy driver IPP. Lưu ý: chỉ ảnh hưởng lần cài mới; máy đã bị gắn driver
IPP phải gỡ cài lại (menu 18).

## 4. Máy in USB đa chức năng mất scan/fax — KB5079473 (menu 24)

Microsoft xác nhận: từ bản cập nhật 10/03/2026 (KB5079473), một số máy in USB
dùng IPP-over-USB bị mất phần scan/fax (Windows đặt chúng ở trạng thái ngắt
kết nối, driver scan không cài được). Tính đến 07/2026 **chưa có bản vá triệt
để**; workaround của Microsoft là gỡ máy in, rút USB, cắm lại. Tool kiểm tra
KB này trong danh sách HotFix, đảm bảo dịch vụ WIA (stisvc) ở Automatic +
Running, liệt kê máy in USB và in hướng dẫn từng bước. Triệu chứng anh em —
in ra trang chứa "POST /ipp/print HTTP/1.1" (lỗi IPP-over-USB cũ) — đã được
Microsoft vá từ KB5053657 (03/2025), nên gặp ca này thì ưu tiên Windows Update.

## 5. Nhóm lỗi kết nối do driver hỏng: 0x2 / 0x57 / 0x5b3 ở máy con, 0x7e ở máy chủ (menu 26)

- `0x00000002` (ERROR_FILE_NOT_FOUND), `0x00000057`, `0x000005b3`: bản sao
  driver trên **máy con** bị hỏng/nửa vời. Quy trình: gỡ kết nối cũ → gỡ sạch
  driver đó → restart Spooler → kết nối lại để tải bản mới.
- `0x0000007e` (ERROR_MOD_NOT_FOUND): thường do driver trên **máy chủ** khai
  báo mục `CopyFiles` (ICM/BIDI — điển hình HP Universal) trỏ tới file máy con
  không lấy được. Tool (chạy trên máy chủ) liệt kê driver, export backup key
  driver trước, rồi xoá đúng mục `CopyFiles` của driver đó trong
  `HKLM\SYSTEM\CurrentControlSet\Control\Print\Environments\...\Drivers\Version-3/4`.

## 6. Diagnose mở rộng

Thêm: DependOnService của Spooler + cảnh báo dependency chết; đếm số lần
Spooler sập (Event 7031/7034) và 5 lỗi PrintService/Admin gần nhất trong 7
ngày (giúp kết luận "driver nào vừa cài làm sập spooler"); danh sách kết nối
share đã lưu; trạng thái Ready Print ranking; trạng thái WIA + máy in USB;
6 bản HotFix gần nhất để đối chiếu thời điểm phát sinh lỗi. Về ký SMB ở 24H2:
bản v13.1 này ban đầu ghi "mọi edition" theo ghi chú của OKI, nhưng đối chiếu
lại tài liệu Microsoft Learn (*Control SMB signing behavior*, rà soát
19/10/2026) thì chính xác là: bắt buộc ký áp dụng cho **Pro / Enterprise /
Education** (cả chiều ra và vào), Windows Server 2025 chỉ bắt buộc chiều ra,
còn **Home không bị ép**. Diagnose của v13.2 đã sửa lại đúng như vậy. Phần fix
ở menu 5 không đổi vì đã xử lý đúng cả hai lớp (guest + RequireSecuritySignature)
cho các edition bị ảnh hưởng.
