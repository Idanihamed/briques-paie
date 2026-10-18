@echo off
rem Demarre le serveur (API) independamment de VS Code. Journal : api.log
cd /d "%~dp0"
node src/server.js >> api.log 2>&1
