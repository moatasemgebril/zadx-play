<#
  Zad X: lock Windows Settings and Control Panel for the CHILD's Standard account only.
  (Owner decision 2026-11-21 "Settings for the parent only"; docs/decisions/DEVICE-PROTECTION.md)

  Run in an *Administrator* PowerShell, while the child is signed out:
    powershell -ExecutionPolicy Bypass -File child_settings_lock.ps1 -ChildAccount "Kid"
  Undo:
    powershell -ExecutionPolicy Bypass -File child_settings_lock.ps1 -ChildAccount "Kid" -Unlock

  It sets the per-user policy "Prohibit access to Control Panel and PC settings" (NoControlPanel=1) in
  the child's own registry hive. It does not change the parent/administrator accounts, and quick
  settings on the taskbar (Wi-Fi, volume, brightness) and emergency/accessibility shortcuts keep working.
  Refuses to run against an administrator account (that would lock the parent out).
#>
param(
  [Parameter(Mandatory = $true)][string]$ChildAccount,
  [switch]$Unlock
)

$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run this in an Administrator PowerShell.'
}

$user = Get-LocalUser -Name $ChildAccount -ErrorAction SilentlyContinue
if (-not $user) { throw "No local account named '$ChildAccount'. (Microsoft accounts: use the local name shown by 'Get-LocalUser'.)" }
$sid = $user.SID.Value

$admins = Get-LocalGroupMember -SID 'S-1-5-32-544' | ForEach-Object { $_.SID.Value }
if ($admins -contains $sid) { throw "'$ChildAccount' is an administrator. Make it a Standard account first; Zad X never locks an administrator." }

$profilePath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction SilentlyContinue).ProfileImagePath
if (-not $profilePath) { throw "'$ChildAccount' has never signed in on this PC. Sign in once as the child, sign out, then run this again." }

# Use the live hive if the child is signed in, otherwise load NTUSER.DAT under a temporary key.
$loaded = $false
if (Test-Path "Registry::HKEY_USERS\$sid") {
  $root = "Registry::HKEY_USERS\$sid"
} else {
  & reg.exe load 'HKU\ZadXChild' (Join-Path $profilePath 'NTUSER.DAT') | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Could not open the child profile. Make sure the child is signed out.' }
  $root = 'Registry::HKEY_USERS\ZadXChild'
  $loaded = $true
}

try {
  $key = "$root\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
  if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
  if ($Unlock) {
    Remove-ItemProperty -Path $key -Name 'NoControlPanel' -ErrorAction SilentlyContinue
    Write-Host "Windows Settings unlocked for '$ChildAccount'." -ForegroundColor Green
  } else {
    New-ItemProperty -Path $key -Name 'NoControlPanel' -PropertyType DWord -Value 1 -Force | Out-Null
    Write-Host "Windows Settings and Control Panel are now locked for '$ChildAccount'." -ForegroundColor Green
    Write-Host 'Use your own (administrator) account to change settings. Undo with -Unlock.'
  }
} finally {
  if ($loaded) {
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    & reg.exe unload 'HKU\ZadXChild' | Out-Null
  }
}
