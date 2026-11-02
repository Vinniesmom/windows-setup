# Install-Apps.ps1 - manual recovery install from your GitHub winget lists
# Run in an elevated PowerShell prompt:
#   powershell -ExecutionPolicy Bypass -File .\Install-Apps.ps1 -Lists 'winget-baseline.json','winget-gaming.json'
param(
    [string[]]$Lists = @('winget-baseline.json', 'winget-creative.json', 'winget-dev.json', 'winget-extras.json', 'winget-gaming.json','winget-hardware-maker.json'),
    [string]$Base    = 'https://raw.githubusercontent.com/Vinniesmom/windows-setup/main'
)
 
$work = Join-Path $env:TEMP 'Rebuild'
New-Item -ItemType Directory -Force -Path $work | Out-Null
Start-Transcript -Path (Join-Path $work 'install-apps.log') -Append | Out-Null
 
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
 
foreach ($l in $Lists) {
    $file = Join-Path $work $l
    Invoke-WebRequest -Uri "$Base/$l" -OutFile $file -UseBasicParsing
    foreach ($pass in 1..2) {   # winget skips anything already installed
        "== $l (pass $pass) =="
        winget import -i $file --accept-package-agreements --accept-source-agreements --ignore-unavailable --disable-interactivity
    }
}
 
# Summary: list anything from the chosen lists that still is not installed
$missing = foreach ($l in $Lists) {
    $ids = (Get-Content (Join-Path $work $l) -Raw | ConvertFrom-Json).Sources.Packages.PackageIdentifier
    foreach ($id in $ids) {
        winget list --id $id --exact --accept-source-agreements *> $null
        if ($LASTEXITCODE -ne 0) { $id }
    }
}
if ($missing) {
    "`nNot installed:"
    $missing
    "`nIf one says it cannot run as administrator, install it from a normal (non-elevated) prompt: winget install <id>"
} else {
    "`nAll packages from the selected lists are installed."
}
Stop-Transcript | Out-Null
 
