@echo off
rem ===============================================
rem  Anh 7 cho Windows - Giao dien W12 - Trinh cai dat
rem  Phien ban Windows cua Anh 7 (hoaibao411) - Ma nguon mo EPL-2.0
rem  Bam dup file nay de mo trinh cai dat.
rem ===============================================
cd /d "%~dp0"
if not exist "%~dp0setup.ps1" (
  echo Khong tim thay setup.ps1. Hay giai nen toan bo file zip truoc khi chay.
  pause
  exit /b 1
)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0setup.ps1"
