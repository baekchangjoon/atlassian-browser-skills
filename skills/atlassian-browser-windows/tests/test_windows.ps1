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
# IMPORTANT: keep this 'Continue', not 'Stop'. Under PS 5.1, ANY stderr written
# by the child PowerShell host is promoted to a terminating NativeCommandError
# when ErrorActionPreference is 'Stop', which would abort the harness and mask
# the child's real stdout/exit code. We capture the child's stderr explicitly
# with 2>&1 instead.
$ErrorActionPreference = 'Continue'
$fail = 0
function Pass($m) { Write-Host "  [PASS] $m" }
function Bad($m)  { Write-Host "  [FAIL] $m"; $script:fail = 1 }

# Run a script under the target PowerShell host as a separate process; return
# stdout only ([Console]::Out), with the child's stderr surfaced for diagnostics.
function Invoke-Child {
  param([string[]]$ScriptArgs)
  $tmpOut = (New-TemporaryFile).FullName
  $tmpErr = (New-TemporaryFile).FullName
  $p = Start-Process -FilePath $PsHost -NoNewWindow -Wait -PassThru `
        -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File') + $ScriptArgs) `
        -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
  $stdout = (Get-Content -Raw -ErrorAction SilentlyContinue $tmpOut)
  $stderr = (Get-Content -Raw -ErrorAction SilentlyContinue $tmpErr)
  Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
  [pscustomobject]@{ Code = $p.ExitCode; Out = ($stdout  -as [string]); Err = ($stderr -as [string]) }
}

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
$r = Invoke-Child @($cdp, '-Method', 'GET', '-Path', '/rest/api/3/myself')
Write-Host "    exit=$($r.Code)  stdout=$($r.Out)"
if ($r.Err) { Write-Host "    stderr=$($r.Err)" }
$json = $null
try { $json = $r.Out | ConvertFrom-Json } catch {}
if ($r.Code -eq 1 -and $json -and $json.ok -eq $false -and $json.status -eq 0 -and $json.error -like '*debug port*') {
  Pass "no Chrome → JSON error, exit 1"
} else {
  Bad "no-Chrome path wrong (exit $($r.Code))"
}

# 3. parameter validation: invalid -Method rejected before any network call
Write-Host "3. parameter validation"
$r = Invoke-Child @($cdp, '-Method', 'INVALID', '-Path', '/rest/api/3/myself')
if ($r.Code -ne 0) { Pass "invalid -Method rejected (exit $($r.Code))" }
else { Bad "invalid -Method was not rejected (exit 0)" }

Write-Host ""
if ($fail -ne 0) { Write-Host "FAILED"; exit 1 }
Write-Host "ALL PASSED"
exit 0
