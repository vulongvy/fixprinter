@echo off
title NOP WINGET - FixPrinter len microsoft/winget-pkgs
cd /d "%~dp0"
echo ============================================================
echo   NOP WINGET - FixPrinter -^> microsoft/winget-pkgs
echo   Dung dang nhap gh san co - KHONG can token PAT.
echo ============================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0nop_winget.ps1"
echo.
echo === Ket thuc. Chi tiet nam trong nop_winget_log.txt ===
pause
