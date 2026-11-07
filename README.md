# FixPrinter — FIX ALL PRINTER · MẠNG LAN

Công cụ sửa lỗi máy in và in qua mạng LAN trên Windows 10/11 bằng **1 cú bấm
đúp**, viết bằng PowerShell 5.1 (có sẵn trong Windows), mã nguồn mở hoàn toàn
trong thư mục [`src/`](src/).

*English summary: FixPrinter is an open-source, one-click repair tool for
Windows printer and LAN-printing problems (Print Spooler failures, SMB printer
sharing, common error codes such as 0x0000011b / 0x0000007c / 0x00000709 /
0x80070035). It is plain PowerShell — every change it makes is readable in
`src/` before you run it.*

## Cách dùng (người dùng cuối)

1. Tải `FixPrinter-Setup-<version>.exe` ở mục **Releases** và cài đặt.
2. Bấm đúp biểu tượng **FIX ALL PRINTER - MANG LAN** trên Desktop.
3. Bấm **Yes** khi Windows hỏi quyền Administrator → tool tự sửa → khởi động
   lại máy rồi thử in.

Không muốn cài đặt? Tải mã nguồn, giải nén thư mục `src` và bấm đúp
`FIX_ALL_PRINTER_MANG_LAN.bat` — chạy y hệt.

## Tool sửa những gì

- Print Spooler: kẹt hàng đợi, service sập, lỗi 1068 (dependency chết), cấu
  hình tự phục hồi thay cho việc tắt/bật tay.
- Mạng LAN: chuyển profile sang Private, bật Network Discovery + File and
  Printer Sharing (firewall + services).
- SMB trên Windows 11 24H2: guest access + `RequireSecuritySignature` — nguyên
  nhân kinh điển của lỗi 0x80070035 khi vào máy chủ in/NAS cũ.
- Các mã lỗi in share: 0x0000011b, 0x00000bc4, 0x00000709, 0x0000007c,
  0x00000002/0x57/0x7e, 1219; Point and Print bản SAFE; máy in mặc định;
  máy in báo offline/SNMP; cổng WSD.
- Quét báo cáo (chỉ đọc): đối chiếu các bản cập nhật Windows từng gây lỗi in
  ấn (kho dữ liệu KB), dấu hiệu trùng SID trên máy clone, xung đột giữa
  Spooler và antivirus/hardening (chữ ký `spoolsv.exe`, log Defender, Print
  Provider của bên thứ ba).

## Minh bạch thay đổi hệ thống

Tool cần quyền Administrator và có thay đổi registry/dịch vụ — toàn bộ đều
nằm trong mã nguồn PowerShell dễ đọc. Trước **mỗi** lần sửa, tool tự backup
registry vào thư mục `backup\<thời-gian>` và có chức năng **UNDO** (menu 21
trong bản menu đầy đủ `CHAY_FIXPRINTER.bat`) để khôi phục. Phần lớn thay đổi
gồm: khóa `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC`,
cấu hình LanmanWorkstation (SMB client), Point and Print, dịch vụ Spooler /
FDResPub / SSDPSRV / upnphost, và rule firewall có sẵn của Windows.

## Cho nhà phát triển

- `src/` — mã nguồn tool (PowerShell module hoá).
- `FixPrinter.iss` — script Inno Setup đóng bộ cài.
- `DAY_LEN_GITHUB.bat` — build bộ cài + đẩy GitHub + tạo Release trong 1 lần
  bấm (xem `HUONG_DAN_PHAT_HANH.md`).
- `.github/workflows/release.yml` — đẩy tag `v*` lên là CI tự build bộ cài và
  tạo Release.
- `winget/` — manifest winget của package `vulongvy.FixPrinter` (sinh từ
  `winget-templates/` mỗi lần phát hành).

## Giấy phép

MIT — xem [LICENSE](LICENSE).
