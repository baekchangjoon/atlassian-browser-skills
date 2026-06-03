<#
  test_windows.ps1 — CI-safe tests for the Windows Chrome DevTools Protocol
  transport. No Chrome / debug port / login needed, so it runs anywhere.

  Covers what is reachable without a running browser:
    1. atl_cdp.ps1 / launch-chrome.ps1 parse cleanly (current host's parser)
    2. error path: no Chrome → well-formed JSON error, exit code 1
    3. parameter validation: invalid -Method is rejected before any network call

  Driving Chrome itself is NOT tested — it needs a logged-in debug tab, which CI
  does not have.

  Re-runs atl_cdp.ps1 as a child of -PsHost so the script is exercised under the
  intended PowerShell host (powershell = PS 5.1, pwsh = PS 7+).

  usage:
    powershell -ExecutionPolicy Bypass -File tests\test_windows.ps1 -PsHost powershell
    pwsh       -ExecutionPolicy Bypass -File tests\test_windows.ps1 -PsHost pwsh
#>
param(
  [string]$ScriptsDir = (Join-Path $PSScriptRoot '..\scripts'),
  [string]$PsHost = 'powershell'
)
$ErrorActionPreference = 'Stop'
$fail = 0
function Pass($m) { Write-Host "  [PASS] $m" }
function Bad($m)  { Write-Host "  [FAIL] $m"; $script:fail = 1 }

$cdp    = Join-Path $ScriptsDir 'atl_cdp.ps1'
$launch = Join-Path $ScriptsDir 'launch-chrome.ps1'
Write-Host "host: $PsHost ($($PSVersionTable.PSVersion))"

# 1. parse check (uses the current host's parser)
Write-Host "1. parse"
foreach ($f in @($cdp, $launch)) {
  $name = [IO.Path]::GetFileName($f)
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errors)
  if ($errors.Count -gt 0) { Bad "$name parse errors: $($errors | Out-String)" }
  else { Pass "$name parses" }
}

# 2. error path: no Chrome on the debug port → JSON {ok:false,status:0}, exit 1
Write-Host "2. error path (no Chrome)"
$out = & $PsHost -NoProfile -ExecutionPolicy Bypass -File $cdp -Method GET -Path /rest/api/3/myself 2>$null
$code = $LASTEXITCODE
$good = $true
if ($code -ne 1) { $good = $false }
try { $r = $out | ConvertFrom-Json } catch { $good = $false; $r = $null }
if ($good -and ($r.ok -ne $false -or $r.status -ne 0 -or $r.error -notlike '*debug port*')) { $good = $false }
if ($good) { Pass "no Chrome → JSON error, exit 1" }
else { Bad "no-Chrome path wrong (exit $code): $out" }

# 3. parameter validation: invalid -Method rejected before any network call
Write-Host "3. parameter validation"
& $PsHost -NoProfile -ExecutionPolicy Bypass -File $cdp -Method INVALID -Path /rest/api/3/myself 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Pass "invalid -Method rejected (exit $LASTEXITCODE)" }
else { Bad "invalid -Method was not rejected" }

Write-Host ""
if ($fail -ne 0) { Write-Host "FAILED"; exit 1 }
Write-Host "ALL PASSED"
exit 0
