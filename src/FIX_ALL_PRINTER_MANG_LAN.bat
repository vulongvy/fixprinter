@echo off
setlocal
cd /d "%~dp0"
set "LOG=%~dp0launcher_log.txt"
echo [%date% %time%] 1CLICK STEP 1: launcher started >> "%LOG%"
title FIX ALL PRINTER - MANG LAN
echo ============================================================
echo   FIX ALL PRINTER - MANG LAN
echo   Bam dup 1 cai - tool tu sua TAT CA loi may in va mang LAN. Dung tat cua so khi dang chay.
echo ============================================================

net session >nul 2>&1
if %errorlevel% equ 0 goto :is_admin
echo [%date% %time%] 1CLICK STEP 2: not admin, relaunching as admin >> "%LOG%"
echo Dang xin quyen Administrator (bam Yes neu Windows hoi)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
if %errorlevel% neq 0 goto :fail_elevate
exit /b 0

:is_admin
echo [%date% %time%] 1CLICK STEP 2: admin OK >> "%LOG%"
if not exist "%~dp0FixPrinter.ps1" goto :fail_missing

echo [%date% %time%] 1CLICK STEP 3: running FixPrinter.ps1 --auto >> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FixPrinter.ps1" --auto
set "RC=%errorlevel%"
echo [%date% %time%] 1CLICK STEP 4: FixPrinter.ps1 exited with code %RC% >> "%LOG%"
echo.
echo Da xong (ma %RC%). Khoi dong lai may roi thu in.
echo Chi tiet: fixprinter_v13_log.txt
pause
exit /b %RC%

:fail_elevate
echo Khong nang duoc quyen admin. Hay chuot phai file nay -^> Run as administrator.
echo [%date% %time%] 1CLICK FAIL: cannot elevate >> "%LOG%"
pause
exit /b 1

:fail_missing
echo Khong thay FixPrinter.ps1 canh file .bat nay. Giai nen nguyen thu muc roi chay lai.
echo [%date% %time%] 1CLICK FAIL: FixPrinter.ps1 missing >> "%LOG%"
pause
exit /b 1
