# Construit l'APK HORS de VS Code (le build consomme presque toute la memoire de la machine).
# Mode d'emploi : fermez le navigateur et les applications lourdes, ouvrez un PowerShell NORMAL
# (pas le terminal de VS Code), puis :   cd <ce dossier> ; .\build-apk.ps1
# Compter 10 a 15 minutes. Le resultat est copie dans Briques-Paie-test.apk.

param(
  [string]$ApiUrl = 'http://192.168.100.79:3000',   # adresse de l'ordinateur qui fait tourner l'API
  [switch]$Cleartext = $true                        # http:// (test). Pour une API en https : -Cleartext:$false
)

Set-Location $PSScriptRoot

# Libere la memoire : arrete les restes de builds precedents.
Get-Process java, dart, dartvm, dartaotruntime -ErrorAction SilentlyContinue | Stop-Process -Force
& "$PSScriptRoot\android\gradlew.bat" --stop 2>$null | Out-Null

$free = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
Write-Host "Memoire libre : $free Go (il en faut au moins 3 pour un build fiable)"
if ($free -lt 3) { Write-Warning 'Peu de memoire libre : fermez le navigateur / VS Code avant de continuer.' }

$env:ALLOW_CLEARTEXT = if ($Cleartext) { 'true' } else { 'false' }
flutter build apk --release --target-platform android-arm64 --dart-define=API_URL=$ApiUrl *>&1 | Tee-Object -FilePath build-apk.log
if ($LASTEXITCODE -ne 0) { Write-Error 'Build echoue.'; exit 1 }

Copy-Item build\app\outputs\flutter-apk\app-release.apk Briques-Paie-test.apk -Force
Write-Host "OK : $PSScriptRoot\Briques-Paie-test.apk"
