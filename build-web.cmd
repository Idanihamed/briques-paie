@echo off
rem Construit l'application web (servie par l'API, meme adresse) et la copie dans backend\public. Journal : build-web.log
cd /d "%~dp0"
if exist build-web.log del build-web.log
start "" /belownormal /wait powershell -NoProfile -ExecutionPolicy Bypass -Command "& { flutter build web --release --dart-define=API_URL=same-origin *>&1 | Out-File -FilePath build-web.log -Encoding utf8; if ($LASTEXITCODE -eq 0) { if (Test-Path backend\public) { Remove-Item -Recurse -Force backend\public }; Copy-Item -Recurse build\web backend\public; 'RESULTAT: OK' | Add-Content build-web.log } else { 'RESULTAT: ECHEC' | Add-Content build-web.log }; 'FIN' | Add-Content build-web.log }"
