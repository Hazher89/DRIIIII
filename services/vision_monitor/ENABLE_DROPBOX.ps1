# Enable Dropbox upload for vision_monitor on this Windows PC.
# Run:
#   powershell -ExecutionPolicy Bypass -File .\ENABLE_DROPBOX.ps1

$ErrorActionPreference = "Stop"
$VisionDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $VisionDir

Write-Host "Mappe: $VisionDir" -ForegroundColor Cyan

$envPath = Join-Path $VisionDir ".env"
$bakPath = "C:\DriftPro\vision_monitor.env.bak"
$oldEnv = "C:\DriftPro\DRIIIII_old\services\vision_monitor\.env"

if (-not (Test-Path $envPath)) {
  if (Test-Path $bakPath) {
    Copy-Item $bakPath $envPath
    Write-Host "Gjenopprettet .env fra backup"
  } elseif (Test-Path $oldEnv) {
    Copy-Item $oldEnv $envPath
    Write-Host "Gjenopprettet .env fra DRIIIII_old"
  } elseif (Test-Path ".env.example") {
    Copy-Item ".env.example" $envPath
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

$envText = Get-Content -Raw -Path $envPath
if ([string]::IsNullOrWhiteSpace($envText)) {
  throw ".env er tom - gjenopprett fra backup forst"
}

$envText = Set-EnvLine $envText "LOCAL_DEV" "false"
$envText = Set-EnvLine $envText "SUPABASE_URL" $supabaseUrl
$envText = Set-EnvLine $envText "SUPABASE_SERVICE_ROLE_KEY" $key.Trim()
$envText = Set-EnvLine $envText "COMPANY_ID" $companyId
$envText = Set-EnvLine $envText "CAMERA_HOST" "192.168.39.190"
$envText = Set-EnvLine $envText "CAMERA_USER" "admin"
$envText = Set-EnvLine $envText "EVENT_TYPE" "sorting_clip"
$envText = Set-EnvLine $envText "CLIP_SECONDS_BEFORE" "60"
$envText = Set-EnvLine $envText "CLIP_SECONDS_AFTER" "120"
$envText = Set-EnvLine $envText "CLIP_FPS" "2"
$envText = Set-EnvLine $envText "LOCAL_SERVER" "true"

if ($envText -notmatch "(?m)^CAMERA_PASSWORD=.+") {
  Write-Host "ADVARSEL: CAMERA_PASSWORD mangler - sett i .env" -ForegroundColor Yellow
}

# Write without BOM (ASCII-safe for Python dotenv)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($envPath, $envText, $utf8NoBom)

if (-not (Test-Path $envPath)) {
  throw "Klarte ikke a skrive .env"
}

Write-Host ""
Write-Host "OK - .env lagret: $envPath" -ForegroundColor Green
Write-Host "  LOCAL_DEV=false"
Write-Host "  CLIP: 60s for person + 120s etter avgang (kun feilkasting)"
Write-Host "  COMPANY_ID=$companyId"
Get-Item $envPath | Format-List FullName, Length, LastWriteTime
Write-Host ""
Write-Host "Start worker med:" -ForegroundColor Cyan
Write-Host "  .\START_WINDOWS.bat"
Write-Host ""
Write-Host "Trykk Enter for aa starte na..."
Read-Host | Out-Null
& "$VisionDir\START_WINDOWS.bat"
