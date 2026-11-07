@echo off
setlocal
cd /d "%~dp0"
set "LOG=%~dp0launcher_log.txt"
echo [%date% %time%] STEP 1: launcher started >> "%LOG%"
title FixPrinter v13
echo ============================================================
echo   FixPrinter v13 - dang khoi dong...
echo ============================================================

net session >nul 2>&1
if %errorlevel% equ 0 goto :is_admin
echo [%date% %time%] STEP 2: not admin, relaunching as admin >> "%LOG%"
echo Dang xin quyen Administrator...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
if %errorlevel% neq 0 goto :fail_elevate
exit /b 0

:is_admin
echo [%date% %time%] STEP 2: admin OK >> "%LOG%"
if not exist "%~dp0FixPrinter.ps1" goto :fail_missing

echo [%date% %time%] STEP 3: running FixPrinter.ps1 >> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FixPrinter.ps1" %*
set "RC=%errorlevel%"
echo [%date% %time%] STEP 4: FixPrinter.ps1 exited with code %RC% >> "%LOG%"
echo.
echo FixPrinter da thoat (ma %RC%). Log: fixprinter_v13_log.txt
pause
exit /b %RC%

:fail_elevate
echo Khong nang duoc quyen admin. Hay chuot phai file nay -^> Run as administrator.
echo [%date% %time%] FAIL: cannot elevate >> "%LOG%"
pause
exit /b 1

:fail_missing
echo Khong thay FixPrinter.ps1 canh file .bat nay. Giai nen nguyen thu muc FixPrinter_v13 roi chay lai.
echo [%date% %time%] FAIL: FixPrinter.ps1 missing >> "%LOG%"
pause
exit /b 1
