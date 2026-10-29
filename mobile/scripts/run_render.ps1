# Lance Fast-Cash Android contre l'API Render.
# Usage :
#   1. Écrire l'URL HTTPS (sans slash final) dans mobile/api_base.local
#      ou : $env:FASTCASH_API_BASE = "https://xxx.onrender.com"
#   2. .\scripts\run_render.ps1
#   3. Optionnel : .\scripts\run_render.ps1 -Device emulator-5554

param(
  [string]$Device = ""
)

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

Write-Host "API_BASE=$api"
if ($Device) {
  & flutter run -d $Device --dart-define="API_BASE=$api"
} else {
  & flutter run --dart-define="API_BASE=$api"
}
