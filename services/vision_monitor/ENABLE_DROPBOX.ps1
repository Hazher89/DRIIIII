# Enable Dropbox upload for vision_monitor on this Windows PC.
# Run:
#   powershell -ExecutionPolicy Bypass -File .\ENABLE_DROPBOX.ps1

$ErrorActionPreference = "Stop"
$VisionDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $VisionDir

Write-Host "Mappe: $VisionDir" -ForegroundColor Cyan

if (-not (Test-Path ".env")) {
  if (Test-Path ".env.example") {
    Copy-Item ".env.example" ".env"
    Write-Host "Opprettet .env fra .env.example"
  } else {
    throw "Mangler .env og .env.example"
  }
}

Write-Host ""
Write-Host "Hent service_role her:" -ForegroundColor Cyan
Write-Host "https://supabase.com/dashboard/project/ksnnyccthotjbrmgjgdc/settings/api"
Write-Host "(Reveal service_role, kopier. IKKE anon-nokkelen.)"
Write-Host ""
$key = Read-Host "Lim inn SUPABASE_SERVICE_ROLE_KEY"

if ([string]::IsNullOrWhiteSpace($key)) {
  throw "Tom nokkel - avbryter"
}

$companyId = "00000000-0000-0000-0000-000000000000"
$supabaseUrl = "https://ksnnyccthotjbrmgjgdc.supabase.co"

function Set-EnvLine([string]$content, [string]$name, [string]$value) {
  $line = "$name=$value"
  if ($content -match "(?m)^#?\s*$([regex]::Escape($name))\s*=") {
    return [regex]::Replace($content, "(?m)^#?\s*$([regex]::Escape($name))\s*=.*$", $line)
  }
  return $content.TrimEnd() + "`r`n" + $line + "`r`n"
}

$envText = Get-Content -Raw ".env"
$envText = Set-EnvLine $envText "LOCAL_DEV" "false"
$envText = Set-EnvLine $envText "SUPABASE_URL" $supabaseUrl
$envText = Set-EnvLine $envText "SUPABASE_SERVICE_ROLE_KEY" $key.Trim()
$envText = Set-EnvLine $envText "COMPANY_ID" $companyId
$envText = Set-EnvLine $envText "CAMERA_HOST" "192.168.39.190"
$envText = Set-EnvLine $envText "CAMERA_USER" "admin"
if ($envText -notmatch "(?m)^CAMERA_PASSWORD=.+") {
  Write-Host "CAMERA_PASSWORD mangler/tom - sett passordet i .env (se JOBB_PC.md)" -ForegroundColor Yellow
}
$envText = Set-EnvLine $envText "EVENT_TYPE" "sorting_clip"
$envText = Set-EnvLine $envText "CLIP_SECONDS_BEFORE" "120"
$envText = Set-EnvLine $envText "CLIP_SECONDS_AFTER" "120"
$envText = Set-EnvLine $envText "CLIP_FPS" "2"

# UTF8 no BOM - safer for Python dotenv on Windows
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText((Join-Path $VisionDir ".env"), $envText, $utf8NoBom)

Write-Host ""
Write-Host "OK - .env oppdatert for Dropbox-opplasting." -ForegroundColor Green
Write-Host "  LOCAL_DEV=false"
Write-Host "  CLIP_SECONDS_BEFORE/AFTER=120 (2 min + 2 min video)"
Write-Host "  COMPANY_ID=$companyId"
Write-Host ""
Write-Host "Start pa nytt: dobbeltklikk START_WINDOWS.bat" -ForegroundColor Cyan
Write-Host "Dashboard: http://127.0.0.1:8090"
Write-Host "Ved avvik: MP4 2+2 min til Dropbox + rad i vision_events"
Write-Host ""
Write-Host "Trykk Enter for aa starte START_WINDOWS.bat..."
Read-Host | Out-Null
& ".\START_WINDOWS.bat"
