@echo off
rem Lance build-apk.ps1 en priorite basse, independamment de VS Code. Journal : build-detached.log
cd /d "%~dp0"
if exist build-detached.log del build-detached.log
start "" /belownormal /wait powershell -NoProfile -ExecutionPolicy Bypass -Command "& { .\build-apk.ps1 *>&1 | Out-File -FilePath build-detached.log -Encoding utf8; if ($LASTEXITCODE -eq 0 -and (Test-Path Briques-Paie-test.apk)) { 'RESULTAT: OK' | Add-Content build-detached.log } else { 'RESULTAT: ECHEC' | Add-Content build-detached.log }; 'FIN' | Add-Content build-detached.log }"
