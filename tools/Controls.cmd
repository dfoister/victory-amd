@echo off
rem Vertex native controls editor (GTA V Enhanced style): edits data\native-keys.txt; a running game uses changes at once.
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Controls.ps1"
