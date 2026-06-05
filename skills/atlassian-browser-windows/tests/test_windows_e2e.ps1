<#
  test_windows_e2e.ps1 - UTF-8 end-to-end test for the Windows CDP transport,
  designed for CI (GitHub windows-latest): launches a REAL headless Chrome on a
  debug port plus a local Python echo server, then round-trips Korean text
  through atl_cdp.ps1 and atl_cdp.py. No Atlassian / no login needed.

  Covers:
    1. non-ASCII (Korean) body -> fetch -> echo -> response, byte-faithful
    2. large (>64KB UTF-8) body, so multibyte chars straddle the 64KB WebSocket
       read boundary (regression test for per-chunk UTF8.GetString decoding)
    3. the same small round-trip through the pure-stdlib Python client

  usage:
    powershell -ExecutionPolicy Bypass -File tests\test_windows_e2e.ps1 -PsHost powershell
    pwsh       -ExecutionPolicy Bypass -File tests\test_windows_e2e.ps1 -PsHost pwsh
#>
param(
  [string]$ScriptsDir = (Join-Path $PSScriptRoot '..\scripts'),
  [string]$PsHost = 'powershell',
  [int]$EchoPort = 8765,
  [int]$DebugPort = 9223
)
$ErrorActionPreference = 'Continue'
# Decode child stdout / encode pipes as UTF-8 regardless of console codepage.
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONUTF8 = '1'

$fail = 0
function Pass($m) { Write-Host "  [PASS] $m" }
function Bad($m)  { Write-Host "  [FAIL] $m"; $script:fail = 1 }

# Korean test strings are built from codepoints so this file itself stays
# ASCII-only (PS 5.1 misreads BOM-less non-ASCII source as ANSI).
$kor = -join [char[]](0xD55C,0xAE00,0x20,0xBCF8,0xBB38,0x20,0xD14C,0xC2A4,0xD2B8) # "한글 본문 테스트"
$korToken = -join [char[]](0xD55C,0xAE00)                                          # "한글" (6 UTF-8 bytes)

$cdp   = Join-Path $ScriptsDir 'atl_cdp.ps1'
$cdpPy = Join-Path $ScriptsDir 'atl_cdp.py'
$echoSrv = Join-Path $PSScriptRoot 'echo_server.py'
Write-Host "host: $PsHost ($($PSVersionTable.PSVersion))  echo:$EchoPort  cdp:$DebugPort"

# Run the transport client under the target PowerShell host, feeding the body
# from a file via stdin (arg passing would mangle quotes and hit length limits).
function Invoke-Cdp([string]$BodyFile, [string]$Path) {
  $cmd = "Get-Content -Raw -Encoding UTF8 '$BodyFile' | & '$cdp' -Method POST -Path $Path -HostFilter 127.0.0.1 -Port $DebugPort"
  $out = & $PsHost -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>$null | Out-String
  return $out
}

function Write-Utf8([string]$File, [string]$Text) {
  [IO.File]::WriteAllText($File, $Text, (New-Object System.Text.UTF8Encoding $false))
}

$chrome = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { Bad "Chrome not found"; Write-Host "FAILED"; exit 1 }

$srvProc = $null; $chromeProc = $null
try {
  # 1) echo server
  $srvProc = Start-Process python -ArgumentList @($echoSrv, $EchoPort) -NoNewWindow -PassThru
  $up = $false
  foreach ($i in 1..50) {
    try { if ((Invoke-RestMethod "http://127.0.0.1:$EchoPort/" -TimeoutSec 2).ok) { $up = $true; break } } catch { Start-Sleep -Milliseconds 200 }
  }
  if (-not $up) { Bad "echo server did not come up"; throw 'setup' }
  Pass "echo server up on $EchoPort"

  # 2) headless Chrome with the page open on the echo origin
  $profile = Join-Path $env:TEMP "atl-e2e-profile-$PID"
  $chromeProc = Start-Process $chrome -PassThru -ArgumentList @(
    '--headless', "--remote-debugging-port=$DebugPort", '--remote-allow-origins=*',
    "--user-data-dir=$profile", '--no-first-run', '--disable-gpu',
    "http://127.0.0.1:$EchoPort/"
  )
  $tab = $null
  foreach ($i in 1..100) {
    try {
      $tab = (Invoke-RestMethod "http://127.0.0.1:$DebugPort/json" -TimeoutSec 2) |
        Where-Object { $_.type -eq 'page' -and $_.url -like "*127.0.0.1*" } | Select-Object -First 1
      if ($tab) { break }
    } catch {}
    Start-Sleep -Milliseconds 300
  }
  if (-not $tab) { Bad "Chrome debug tab did not appear"; throw 'setup' }
  Pass "Chrome headless up, tab: $($tab.url)"

  # 3) small Korean body round-trip (atl_cdp.ps1)
  Write-Host "1. Korean round-trip (atl_cdp.ps1)"
  $bodyFile = Join-Path $env:TEMP "atl-e2e-body-$PID.json"
  Write-Utf8 $bodyFile ('{"text":"' + $kor + '"}')
  $r = $null; try { $r = (Invoke-Cdp $bodyFile '/echo') | ConvertFrom-Json } catch {}
  if ($r -and $r.ok -and ($r.data.text -ceq $kor)) {
    Pass "small body round-tripped byte-faithfully"
  } else {
    Bad "small body mismatch: got '$($r.data.text)' want '$kor' (status=$($r.status))"
  }

  # 4) large body (>64KB UTF-8) — multibyte chars straddle the 64KB read boundary
  Write-Host "2. >64KB Korean round-trip (atl_cdp.ps1, chunk-boundary regression)"
  $big = $korToken * 60000   # 120k chars = 360KB UTF-8 -> ~6 chunk boundaries
  Write-Utf8 $bodyFile ('{"text":"' + $big + '"}')
  $r = $null; try { $r = (Invoke-Cdp $bodyFile '/echo') | ConvertFrom-Json } catch {}
  if ($r -and $r.ok -and ($r.data.text -ceq $big)) {
    Pass "large body round-tripped byte-faithfully ($([System.Text.Encoding]::UTF8.GetByteCount($big)) bytes)"
  } else {
    $got = if ($r) { "len=$($r.data.text.Length), replacement-chars=$([regex]::Matches([string]$r.data.text, [char]0xFFFD).Count)" } else { 'no parseable output' }
    Bad "large body mismatch: $got"
  }

  # 5) small Korean body round-trip (atl_cdp.py, stdlib client)
  Write-Host "3. Korean round-trip (atl_cdp.py)"
  Write-Utf8 $bodyFile ('{"text":"' + $kor + '"}')
  $env:ATL_HOST = '127.0.0.1'; $env:ATL_PORT = "$DebugPort"
  $out = Get-Content -Raw -Encoding UTF8 $bodyFile | & python $cdpPy POST /echo - 2>$null | Out-String
  $r = $null; try { $r = $out | ConvertFrom-Json } catch {}
  if ($r -and $r.ok -and ($r.data.text -ceq $kor)) {
    Pass "python client round-tripped byte-faithfully"
  } else {
    Bad "python client mismatch: got '$($r.data.text)' want '$kor'"
  }
} catch {
  if ("$_" -ne 'setup') { Bad "unexpected error: $_" }
} finally {
  if ($chromeProc) { try { Stop-Process -Id $chromeProc.Id -Force -ErrorAction SilentlyContinue } catch {} }
  if ($srvProc)    { try { Stop-Process -Id $srvProc.Id    -Force -ErrorAction SilentlyContinue } catch {} }
}

Write-Host ""
if ($fail -ne 0) { Write-Host "FAILED"; exit 1 }
Write-Host "ALL PASSED"
exit 0
