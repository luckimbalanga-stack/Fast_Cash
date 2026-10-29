# Build APK release pointant vers l'API Render.
# Usage : même config que run_render.ps1 (api_base.local ou FASTCASH_API_BASE)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$api = $env:FASTCASH_API_BASE
if (-not $api) {
  $localFile = Join-Path $root "api_base.local"
  if (Test-Path $localFile) {
    $api = (Get-Content $localFile -Raw).Trim()
  }
}

if (-not $api) {
  Write-Error "Définis FASTCASH_API_BASE ou crée mobile/api_base.local (voir api_base.local.example)."
}

if ($api.EndsWith("/")) {
  $api = $api.TrimEnd("/")
}

if ($api -notmatch "^https://") {
  Write-Error "API_BASE doit être en HTTPS (ex. https://fast-cash-xxxx.onrender.com)."
}

Write-Host "Build APK avec API_BASE=$api"
& flutter build apk --dart-define="API_BASE=$api"
Write-Host "APK : $root\build\app\outputs\flutter-apk\app-release.apk"
