<#
  Zad X Guard installer (run in an *Administrator* PowerShell on the child's PC).

    powershell -ExecutionPolicy Bypass -File install.ps1 -PairingCode 123456

  Before running: build with
    dotnet publish -c Release
  and place this script next to the published ZadXGuard.exe + appsettings.json.
  For the store-ready version, wrap this in a signed MSI/MSIX installer.
#>
param(
  [Parameter(Mandatory = $true)][string]$PairingCode
)

$ErrorActionPreference = 'Stop'
$installDir = Join-Path $env:ProgramFiles 'ZadX Guard'
$dataDir    = Join-Path $env:ProgramData 'ZadX'
$exe        = Join-Path $installDir 'ZadXGuard.exe'

# 1. Copy files
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'ZadXGuard.exe'), (Join-Path $PSScriptRoot 'appsettings.json') -Destination $installDir -Force

# 2. Lock down the data folder: SYSTEM + Administrators only (child accounts must be Standard users)
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
icacls $dataDir /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' | Out-Null

# 3. Pair this PC with the family
& $exe pair $PairingCode
if ($LASTEXITCODE -ne 0) { throw 'Pairing failed — create a new code in Zad X (Parent → Link devices → Windows PC).' }

# 4. Register the service (LocalSystem, auto start, restart on failure)
if (Get-Service -Name 'ZadXGuard' -ErrorAction SilentlyContinue) {
  Stop-Service ZadXGuard -Force
  sc.exe delete ZadXGuard | Out-Null
  Start-Sleep -Seconds 2
}
New-Service -Name 'ZadXGuard' -BinaryPathName "`"$exe`"" -DisplayName 'Zad X Guard' `
  -Description 'Locks games until tasks and prayer are done (Zad X).' -StartupType Automatic | Out-Null
sc.exe failure ZadXGuard reset= 0 actions= restart/5000/restart/5000/restart/5000 | Out-Null
Start-Service ZadXGuard

Write-Host 'Zad X Guard is installed and running.' -ForegroundColor Green
Write-Host 'Important: make sure the child uses a Standard (non-administrator) Windows account.'
