# Enable Dropbox upload for vision_monitor on this Windows PC.
# Run in PowerShell from anywhere:
#   powershell -ExecutionPolicy Bypass -File C:\DriftPro\DRIIIII\services\vision_monitor\ENABLE_DROPBOX.ps1

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
Write-Host "(Reveal service_role → kopier. IKKE anon-nøkkelen.)"
Write-Host ""
$key = Read-Host "Lim inn SUPABASE_SERVICE_ROLE_KEY"

if ([string]::IsNullOrWhiteSpace($key)) {
  throw "Tom nøkkel — avbryter"
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
  Write-Host "CAMERA_PASSWORD mangler/tom — sett passordet i .env (se JOBB_PC.md)" -ForegroundColor Yellow
}
$envText = Set-EnvLine $envText "EVENT_TYPE" "sorting_clip"
$envText = Set-EnvLine $envText "CLIP_SECONDS_BEFORE" "120"
$envText = Set-EnvLine $envText "CLIP_SECONDS_AFTER" "120"
$envText = Set-EnvLine $envText "CLIP_FPS" "2"

Set-Content -Path ".env" -Value $envText -Encoding UTF8
Write-Host ""
Write-Host "OK — .env oppdatert for Dropbox-opplasting." -ForegroundColor Green
Write-Host "  LOCAL_DEV=false"
Write-Host "  CLIP_SECONDS_BEFORE/AFTER=120 (2+2 min video)"
Write-Host "  COMPANY_ID=$companyId"
Write-Host ""
Write-Host "Start på nytt: dobbeltklikk START_WINDOWS.bat" -ForegroundColor Cyan
Write-Host "Dashboard: http://127.0.0.1:8090"
Write-Host "Ved avvik: MP4 2+2 min → Dropbox + rad i vision_events"
Write-Host ""
Write-Host "Trykk Enter for å starte START_WINDOWS.bat..."
Read-Host | Out-Null
& ".\START_WINDOWS.bat"