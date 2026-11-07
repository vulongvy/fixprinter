# Hướng dẫn phát hành FixPrinter — GitHub + winget

## Đường chính: 1 lần bấm

Bấm đúp **`DAY_LEN_GITHUB.bat`**. Nó tự làm hết, theo đúng thứ tự:

1. Đọc phiên bản từ `VERSION.txt`.
2. Thiếu Git / GitHub CLI / Inno Setup → tự cài bằng winget.
3. Chưa đăng nhập GitHub → mở `gh auth login` cho đăng nhập 1 lần duy nhất.
4. Build bộ cài `dist\FixPrinter-Setup-<version>.exe` bằng Inno Setup.
5. Tính SHA-256, sinh manifest winget vào thư mục `winget\`.
6. Chưa có repo → tự tạo `vulongvy/FixPrinter` (public) trên GitHub.
7. Commit + push code, gắn tag `v<version>`.
8. Tạo GitHub Release và đính kèm file cài.

Mọi bước đều ghi vào `phat_hanh_log.txt`; bước nào chết, cửa sổ dừng lại và
nói rõ chết ở đâu. Muốn đổi tài khoản/repo: sửa biến `REPO` ở đầu file .bat.

## Nộp winget — lần đầu phải làm tay 1 lần

winget (microsoft/winget-pkgs) chỉ chứa manifest, không chứa file cài — file
cài nằm ở GitHub Release của mình, manifest trỏ link + SHA-256 về đó. Lần đầu
nộp package mới có 3 cách:

**Cách 0 — `NOP_WINGET.bat` (KHUYÊN DÙNG, 1 lần bấm):** dùng sẵn đăng nhập
`gh` đã có trên máy — tự fork winget-pkgs, render manifest từ
`winget-templates\` bằng đúng SHA-256 của file cài trên Release, tự
`winget validate`, đẩy 4 file lên nhánh riêng trên fork và mở PR.
**Không cần PAT, không phải trả lời câu hỏi.** Kẹt bước nào xem
`nop_winget_log.txt`.

**Cách A — wingetcreate (nhanh):**

```powershell
winget install wingetcreate
wingetcreate new https://github.com/vulongvy/FixPrinter/releases/download/v13.4.0/FixPrinter-Setup-13.4.0.exe --token <PAT>
```

PAT: GitHub → Settings → Developer settings → Personal access tokens (classic)
→ scope **`repo`**. Lần đầu nộp cũng phải ký CLA (bot tự hiện link trên PR).

**Cách B — fork thủ công:** fork `microsoft/winget-pkgs`, chép 4 file trong
thư mục `winget\` của repo này vào
`manifests\v\vulongvy\FixPrinter\13.4.0\`, mở Pull Request.

Trước khi nộp, tự kiểm tra trên máy mình:

```powershell
winget validate --manifest winget
```

**Các lần sau** (đã có package): chỉ cần
`wingetcreate update vulongvy.FixPrinter --urls <link file cài bản mới> --version <bản mới> --token <PAT>`
— tool tự tính lại hash và mở PR. Hoặc dùng đường CI ở dưới.

## Rủi ro kiểm duyệt winget — biết trước để khỏi bất ngờ

- Pipeline của Microsoft quét file cài qua nhiều antivirus + Defender và cài
  thử trong sandbox. Tool sửa hệ thống mức thấp (registry/service) **có thể bị
  gắn cờ PUA dù lành** — chính tài liệu Microsoft thừa nhận nhóm này có thể bị
  từ chối. Nếu bị flag oan: gửi file cho Microsoft Defender phân tích lại
  (microsoft.com/wdsi/filesubmission) rồi mới nộp lại.
- Bộ cài **chưa có chữ ký số** → người dùng tải về sẽ gặp SmartScreen "chưa rõ
  nguồn gốc" thời gian đầu; bấm More info → Run anyway là chạy. Chữ ký số
  (code signing certificate) mua riêng mới hết hẳn — chưa bắt buộc.
- Điều kiện cứng đã lo sẵn trong bộ này: installer dạng exe/Inno (không phải
  script), cài silent được (`/VERYSILENT`), gỡ sạch (mục `[UninstallDelete]`
  dọn cả thư mục backup/log do tool sinh ra), URL là link HTTPS trực tiếp của
  chính repo phát hành, hash khớp tuyệt đối.

## Phát hành bản mới (việc lặp lại mỗi lần)

1. Sửa `VERSION.txt` → số bản mới (ví dụ `13.5.0`).
2. Sửa `$FPVersion` trong `src\FixPrinter.ps1` cho khớp.
3. Bấm đúp `DAY_LEN_GITHUB.bat` → xong phần GitHub.
4. Nộp winget bản mới bằng `wingetcreate update` (ở trên) — hoặc dùng CI:

**Đường CI (tự động hẳn):** vào repo → Settings → Secrets → Actions → tạo
secret `WINGET_TOKEN` (PAT classic scope `repo`). Từ đó mỗi lần
`git tag v<bản mới>` + `git push origin v<bản mới>`, GitHub Actions tự build
bộ cài, tạo Release và chạy luôn `wingetcreate update`.
Workflow nằm ở `.github/workflows/release.yml`.

## Cấu trúc bộ phát hành

| File/thư mục | Vai trò |
|---|---|
| `src\` | Mã nguồn tool (PowerShell) — cũng là nội dung được cài vào máy |
| `FixPrinter.iss` | Script Inno Setup đóng bộ cài |
| `VERSION.txt` | Nguồn sự thật về phiên bản khi build local |
| `DAY_LEN_GITHUB.bat` | 1-click: build + push + release |
| `winget-templates\` | Mẫu manifest, chứa `__VERSION__` / `__SHA256__` |
| `winget\` | Manifest đã sinh cho bản hiện tại (để nộp winget-pkgs) |
| `.github\workflows\release.yml` | CI: tag → build → release → winget |
