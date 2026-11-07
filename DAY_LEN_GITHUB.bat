@echo off
setlocal
cd /d "%~dp0"
set "LOG=%~dp0phat_hanh_log.txt"
set "REPO=vulongvy/FixPrinter"
title FixPrinter - Build va phat hanh GitHub
echo [%date% %time%] ===== RELEASE START ===== >> "%LOG%"
echo ============================================================
echo   FixPrinter - BUILD + DAY GITHUB + TAO RELEASE (1 lan bam)
echo ============================================================

rem ---------- STEP 0: read version ----------
if not exist "%~dp0VERSION.txt" goto :fail_version
set /p VER=<"%~dp0VERSION.txt"
if "%VER%"=="" goto :fail_version
echo [OK] Phien ban: %VER%
echo [%date% %time%] Version: %VER% >> "%LOG%"

rem ---------- STEP 1: git ----------
set "GITEXE=git"
where git >nul 2>&1
if %errorlevel% equ 0 goto :git_ok
if exist "C:\Program Files\Git\cmd\git.exe" set "GITEXE=C:\Program Files\Git\cmd\git.exe"
if exist "C:\Program Files\Git\cmd\git.exe" goto :git_ok
echo [..] Chua co Git - dang cai bang winget...
winget install -e --id Git.Git --accept-source-agreements --accept-package-agreements
if exist "C:\Program Files\Git\cmd\git.exe" set "GITEXE=C:\Program Files\Git\cmd\git.exe"
if exist "C:\Program Files\Git\cmd\git.exe" goto :git_ok
goto :fail_git
:git_ok
echo [OK] Git: %GITEXE%
echo [%date% %time%] Git OK: %GITEXE% >> "%LOG%"

rem ---------- STEP 2: GitHub CLI + login ----------
set "GHEXE=gh"
where gh >nul 2>&1
if %errorlevel% equ 0 goto :gh_found
if exist "C:\Program Files\GitHub CLI\gh.exe" set "GHEXE=C:\Program Files\GitHub CLI\gh.exe"
if exist "C:\Program Files\GitHub CLI\gh.exe" goto :gh_found
echo [..] Chua co GitHub CLI - dang cai bang winget...
winget install -e --id GitHub.cli --accept-source-agreements --accept-package-agreements
if exist "C:\Program Files\GitHub CLI\gh.exe" set "GHEXE=C:\Program Files\GitHub CLI\gh.exe"
if exist "C:\Program Files\GitHub CLI\gh.exe" goto :gh_found
goto :fail_gh
:gh_found
"%GHEXE%" auth status >nul 2>&1
if %errorlevel% equ 0 goto :gh_ok
echo [..] Chua dang nhap GitHub - lam theo huong dan dang nhap (chi 1 lan duy nhat)...
"%GHEXE%" auth login
"%GHEXE%" auth status >nul 2>&1
if %errorlevel% neq 0 goto :fail_auth
:gh_ok
echo [OK] GitHub CLI da dang nhap
echo [%date% %time%] gh auth OK >> "%LOG%"

rem ---------- STEP 3: Inno Setup compiler (do tim moi vi tri cai dat) ----------
set "ISCCEXE="
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tim_iscc.ps1" > "%~dp0iscc_path.txt" 2>nul
if exist "%~dp0iscc_path.txt" set /p ISCCEXE=<"%~dp0iscc_path.txt"
if not "%ISCCEXE%"=="" goto :iscc_ok
echo [..] Chua thay Inno Setup 6 - dang cai bang winget...
winget install -e --id JRSoftware.InnoSetup --accept-source-agreements --accept-package-agreements
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tim_iscc.ps1" > "%~dp0iscc_path.txt" 2>nul
set "ISCCEXE="
if exist "%~dp0iscc_path.txt" set /p ISCCEXE=<"%~dp0iscc_path.txt"
if "%ISCCEXE%"=="" goto :fail_iscc
:iscc_ok
echo [OK] Inno Setup: %ISCCEXE%
echo [%date% %time%] ISCC OK >> "%LOG%"

rem ---------- STEP 4: build installer ----------
echo [..] Dang build bo cai FixPrinter-Setup-%VER%.exe ...
"%ISCCEXE%" /DAppVersion=%VER% "%~dp0FixPrinter.iss" >> "%LOG%" 2>&1
if %errorlevel% neq 0 goto :fail_build
if not exist "%~dp0dist\FixPrinter-Setup-%VER%.exe" goto :fail_build
echo [OK] Build xong: dist\FixPrinter-Setup-%VER%.exe
echo [%date% %time%] Build OK >> "%LOG%"

rem ---------- STEP 5: SHA-256 + render winget manifests ----------
powershell -NoProfile -Command "(Get-FileHash '%~dp0dist\FixPrinter-Setup-%VER%.exe' -Algorithm SHA256).Hash" > "%~dp0hash.txt"
set /p HASH=<"%~dp0hash.txt"
if "%HASH%"=="" goto :fail_hash
echo [OK] SHA-256: %HASH%
echo [%date% %time%] SHA256: %HASH% >> "%LOG%"
if not exist "%~dp0winget" mkdir "%~dp0winget"
if not exist "%~dp0winget\templates" goto :tpl_ok
if exist "%~dp0winget-templates" goto :tpl_ok
move "%~dp0winget\templates" "%~dp0winget-templates" >nul 2>&1
echo [OK] Da dua thu muc templates ra khoi winget\ (de winget validate khong bi nhiu)
:tpl_ok
powershell -NoProfile -Command "$v='%VER%'; $h='%HASH%'; Get-ChildItem '%~dp0winget-templates\*.yaml' | ForEach-Object { ((Get-Content $_.FullName -Raw) -replace '__VERSION__', $v -replace '__SHA256__', $h) | Set-Content (Join-Path '%~dp0winget' $_.Name) -Encoding UTF8 }"
if %errorlevel% neq 0 goto :fail_render
echo [OK] Da sinh manifest winget vao thu muc winget\

rem ---------- STEP 6: git init / remote ----------
if exist "%~dp0.git" goto :git_ready
"%GITEXE%" init -b main >> "%LOG%" 2>&1
if %errorlevel% neq 0 goto :fail_git
:git_ready
"%GITEXE%" config user.email >nul 2>&1
if %errorlevel% equ 0 goto :identity_ok
"%GITEXE%" config user.name "vulongvy"
"%GITEXE%" config user.email "vulongvy@users.noreply.github.com"
echo [OK] Da dat danh tinh git mac dinh (vulongvy)
:identity_ok
"%GITEXE%" remote get-url origin >nul 2>&1
if %errorlevel% equ 0 goto :remote_ok
echo [..] Chua co remote - dang tao repo %REPO% tren GitHub...
"%GHEXE%" repo create %REPO% --public --source . --remote origin >> "%LOG%" 2>&1
"%GITEXE%" remote get-url origin >nul 2>&1
if %errorlevel% equ 0 goto :remote_ok
"%GITEXE%" remote add origin https://github.com/%REPO%.git
"%GITEXE%" remote get-url origin >nul 2>&1
if %errorlevel% neq 0 goto :fail_remote
:remote_ok
echo [OK] Remote: https://github.com/%REPO%
echo [%date% %time%] Remote OK >> "%LOG%"

rem ---------- STEP 6b: adopt existing remote history (repo tao tu truoc) ----------
"%GITEXE%" fetch origin >> "%LOG%" 2>&1
"%GITEXE%" rev-parse --verify origin/main >nul 2>&1
if %errorlevel% neq 0 goto :no_remote_main
echo [..] Repo tren GitHub da co san lich su - dang ghep code moi len tren do...
"%GITEXE%" reset --soft origin/main >> "%LOG%" 2>&1
if %errorlevel% neq 0 goto :fail_adopt
echo [OK] Da ghep vao lich su repo cu
:no_remote_main

rem ---------- STEP 7: commit + push ----------
"%GITEXE%" add -A
"%GITEXE%" status --porcelain > "%~dp0status.txt"
for %%A in ("%~dp0status.txt") do if %%~zA gtr 0 goto :do_commit
echo [OK] Khong co thay doi moi - bo qua commit
goto :push_main
:do_commit
"%GITEXE%" commit -m "FixPrinter v%VER%" >> "%LOG%" 2>&1
if %errorlevel% neq 0 goto :fail_commit
echo [OK] Da commit
:push_main
"%GITEXE%" push -u origin main >> "%LOG%" 2>&1
if %errorlevel% neq 0 goto :fail_push
echo [OK] Da day code len GitHub
echo [%date% %time%] Push OK >> "%LOG%"

rem ---------- STEP 8: tag + release ----------
"%GITEXE%" tag v%VER% >> "%LOG%" 2>&1
"%GITEXE%" push origin v%VER% >> "%LOG%" 2>&1
"%GHEXE%" release view v%VER% >nul 2>&1
if %errorlevel% equ 0 goto :release_upload
"%GHEXE%" release create v%VER% "%~dp0dist\FixPrinter-Setup-%VER%.exe" --title "FixPrinter v%VER%" --generate-notes >> "%LOG%" 2>&1
if %errorlevel% neq 0 goto :fail_release
echo [OK] Da tao Release v%VER%
goto :release_done
:release_upload
"%GHEXE%" release upload v%VER% "%~dp0dist\FixPrinter-Setup-%VER%.exe" --clobber >> "%LOG%" 2>&1
if %errorlevel% neq 0 goto :fail_release
echo [OK] Da cap nhat lai file cai trong Release v%VER%
:release_done
echo [%date% %time%] Release OK >> "%LOG%"

rem ---------- STEP 9: optional local winget validate ----------
where winget >nul 2>&1
if %errorlevel% neq 0 goto :skip_validate
winget validate --manifest "%~dp0winget" 2>&1 | findstr /C:"Manifest" 
echo [..] Ket qua validate chi tiet: chay tay lenh  winget validate --manifest winget
:skip_validate

echo.
echo ============================================================
echo   XONG PHAN GITHUB!
echo   Repo   : https://github.com/%REPO%
echo   Release: https://github.com/%REPO%/releases/tag/v%VER%
echo   File   : https://github.com/%REPO%/releases/download/v%VER%/FixPrinter-Setup-%VER%.exe
echo   SHA256 : %HASH%
echo ============================================================
echo   NOP WINGET (lan dau tien lam tay 1 lan - xem HUONG_DAN_PHAT_HANH.md):
echo   Cach nhanh: winget install wingetcreate, roi chay:
echo     wingetcreate new https://github.com/%REPO%/releases/download/v%VER%/FixPrinter-Setup-%VER%.exe --token ^<PAT^>
echo   Cac ban sau: chi sua VERSION.txt + version trong src\FixPrinter.ps1,
echo   chay lai file .bat nay, roi wingetcreate update tu dong lo phan con lai.
echo ============================================================
echo [%date% %time%] ===== RELEASE DONE ===== >> "%LOG%"
pause
exit /b 0

:fail_version
echo [LOI] Khong doc duoc VERSION.txt canh file .bat nay.
goto :fail_end
:fail_adopt
echo [LOI] Khong ghep duoc vao lich su repo cu tren GitHub - xem phat_hanh_log.txt.
goto :fail_end
:fail_git
echo [LOI] Khong co Git va cai tu dong that bai. Cai Git thu cong: https://git-scm.com/download/win roi chay lai.
goto :fail_end
:fail_gh
echo [LOI] Khong co GitHub CLI va cai tu dong that bai. Cai thu cong: https://cli.github.com roi chay lai.
goto :fail_end
:fail_auth
echo [LOI] Dang nhap GitHub chua xong. Chay lai file nay va dang nhap cho xong.
goto :fail_end
:fail_iscc
echo [LOI] Khong tim thay ISCC.exe cua Inno Setup 6 o bat ky vi tri nao (da do ca registry).
echo       Neu may co Inno Setup ban cu/bi loi: go no trong Settings - Apps, roi chay lai file nay,
echo       hoac cai thu cong Inno Setup 6: https://jrsoftware.org/isdl.php roi chay lai.
goto :fail_end
:fail_build
echo [LOI] Build bo cai that bai - xem phat_hanh_log.txt de biet dong loi cua Inno.
goto :fail_end
:fail_hash
echo [LOI] Khong tinh duoc SHA-256 cua file cai.
goto :fail_end
:fail_render
echo [LOI] Khong sinh duoc manifest winget tu templates.
goto :fail_end
:fail_remote
echo [LOI] Khong tao/gan duoc repo %REPO%. Kiem tra ten tai khoan GitHub trong bien REPO o dau file .bat nay.
goto :fail_end
:fail_commit
echo [LOI] Git commit that bai - xem phat_hanh_log.txt.
goto :fail_end
:fail_push
echo [LOI] Git push that bai - xem phat_hanh_log.txt (thuong la mang hoac quyen truy cap).
goto :fail_end
:fail_release
echo [LOI] Tao Release that bai - xem phat_hanh_log.txt.
goto :fail_end
:fail_end
echo [%date% %time%] FAIL - xem ghi chu tren >> "%LOG%"
pause
exit /b 1
