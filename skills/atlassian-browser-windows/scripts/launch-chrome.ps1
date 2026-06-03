<#
  launch-chrome.ps1 — start Chrome with the DevTools remote debugging port so
  atl_cdp.ps1 / atl_cdp.py can attach.

  Uses a DEDICATED profile dir so it never disturbs the user's main Chrome and
  the debug flag is honored (Chrome ignores --remote-debugging-port if an
  instance with the same profile is already running). You log into Atlassian
  once in this window; cookies persist in the dedicated profile.

  usage:
    powershell -ExecutionPolicy Bypass -File launch-chrome.ps1
    powershell -ExecutionPolicy Bypass -File launch-chrome.ps1 -Port 9222 -Url https://your.atlassian.net
#>
param(
  [int]$Port = 9222,
  [string]$Url = '',
  [string]$ProfileDir = "$env:LOCALAPPDATA\atl-cdp-profile"
)

$candidates = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
  # Edge works too (Chromium-based, same CDP):
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
)
$exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { Write-Error 'Chrome/Edge not found in the usual locations.'; exit 1 }

$chromeArgs = @(
  "--remote-debugging-port=$Port",
  '--remote-allow-origins=*',
  "--user-data-dir=$ProfileDir",
  '--no-first-run',
  '--no-default-browser-check'
)
if ($Url) { $chromeArgs += $Url }

Write-Host "Launching: $exe"
Write-Host "  port=$Port  profile=$ProfileDir"
Write-Host 'Log into your Atlassian site in this window (first time only).'
Start-Process -FilePath $exe -ArgumentList $chromeArgs
