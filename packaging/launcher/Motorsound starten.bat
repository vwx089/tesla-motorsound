@echo off
chcp 65001 >nul
cd /d "%~dp0"
runtime\node.exe app\start.mjs %*
pause
