# Install-Apps.ps1 - manual recovery install from your GitHub winget lists
# Run in an ELEVATED PowerShell prompt, in the same window (not with "powershell -File"):
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   & "$env:TEMP\Install-Apps.ps1"                                  # baseline list only
#   & "$env:TEMP\Install-Apps.ps1" -Lists 'winget-baseline.json','winget-gaming.json'
#   & "$env:TEMP\Install-Apps.ps1" -All                             # every list
param(
    [string[]]$Lists = @('winget-baseline.json'),
    [switch]$All,
    [string]$Base = 'https://raw.githubusercontent.com/Vinniesmom/windows-setup/main'
)

$allLists = 'winget-baseline.json','winget-creative.json','winget-dev.json',
            'winget-extras.json','winget-gaming.json','winget-hardware-maker.json'
if ($All) { $Lists = $allLists }

# Accept comma-separated text as well as a real array, and tidy spaces
$Lists = $Lists | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }

$work = Join-Path $env:TEMP 'Rebuild'
New-Item -ItemType Directory -Force -Path $work | Out-Null
Start-Transcript -Path (Join-Path $work 'install-apps.log') -Append | Out-Null
"Base: $Base"
"Lists: $($Lists -join ', ')"

# Make sure winget is available (try to register App Installer once if it is not)
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe; Start-Sleep -Seconds 10 }
    catch { "Could not register App Installer: $_" }
}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Stop-Transcript | Out-Null
    throw 'winget was not found. Install or repair App Installer, then run this script again.'
}

winget source update

# Download each list; remember any that fail instead of pretending they worked
$ok = @(); $failed = @()
foreach ($l in $Lists) {
    $file = Join-Path $work $l
    try {
        Invoke-WebRequest -Uri "$Base/$l" -OutFile $file -UseBasicParsing -ErrorAction Stop
        $null = Get-Content $file -Raw | ConvertFrom-Json   # make sure it is valid JSON
        $ok += $l
    } catch {
        "Could not download or read ${l}: $($_.Exception.Message)"
        $failed += $l
    }
}

foreach ($l in $ok) {
    $file = Join-Path $work $l
    foreach ($pass in 1..2) {   # winget skips anything already installed
        "== $l (pass $pass) =="
        winget import -i $file --accept-package-agreements --accept-source-agreements --ignore-unavailable --disable-interactivity
    }
}

# Summary: lists that failed to download, and packages that are still not installed
$missing = foreach ($l in $ok) {
    $ids = (Get-Content (Join-Path $work $l) -Raw | ConvertFrom-Json).Sources.Packages.PackageIdentifier
    foreach ($id in $ids) {
        winget list --id $id --exact --accept-source-agreements *> $null
        if ($LASTEXITCODE -ne 0) { $id }
    }
}

"`n==== Summary ===="
if ($failed)  { "Lists that could not be downloaded: $($failed -join ', ')" }
if ($missing) {
    "Not installed:"; $missing
    "If one says it cannot run as administrator, install it from a normal (non-elevated) prompt: winget install <id>"
}
if (-not $failed -and -not $missing) { "All packages from the selected lists are installed." }
Stop-Transcript | Out-Null
