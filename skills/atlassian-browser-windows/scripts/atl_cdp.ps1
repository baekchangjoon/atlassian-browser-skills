<#
  atl_cdp.ps1 — run an authenticated Atlassian REST call inside a Chrome tab via
  the Chrome DevTools Protocol (remote debugging port). No API token, no MCP, no
  pip install: pure Windows PowerShell (5.1+, preinstalled). Uses the browser's
  existing session cookie via a same-origin fetch().

  Prereq: launch Chrome with the debug port (see launch-chrome.ps1), e.g.
    chrome.exe --remote-debugging-port=9222 --remote-allow-origins=* `
               --user-data-dir="$env:LOCALAPPDATA\atl-cdp-profile"
  then log into your Atlassian site in that window (once; cookies persist).

  usage:
    atl_cdp.ps1 -Method GET  -Path /rest/api/3/myself
    atl_cdp.ps1 -Method POST -Path /rest/api/3/search/jql -Body '{"jql":"project=ABC","maxResults":5}'
    atl_cdp.ps1 -Method PUT  -Path /rest/api/3/issue/ABC-1 -Body '{"fields":{"summary":"new"}}'
    '{"jql":"project=ABC"}' | atl_cdp.ps1 -Method POST -Path /rest/api/3/search/jql

  Prints {"status":..,"ok":..,"data":..} JSON on stdout.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('GET','POST','PUT','DELETE','PATCH')][string]$Method,
  [Parameter(Mandatory=$true)][string]$Path,
  [Parameter(ValueFromPipeline=$true)][string]$Body,
  [string]$HostFilter = 'atlassian',
  [int]$Port = 9222,
  [int]$TimeoutMs = 30000
)

$ErrorActionPreference = 'Stop'

function Fail($msg) {
  [Console]::Out.Write((@{ status = 0; ok = $false; error = $msg } | ConvertTo-Json -Compress))
  exit 1
}

# 1) Discover the target tab's WebSocket debugger URL.
try {
  $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json" -TimeoutSec 5
} catch {
  Fail "cannot reach Chrome debug port $Port — launch Chrome with --remote-debugging-port=$Port (see launch-chrome.ps1). $($_.Exception.Message)"
}

$tab = $targets | Where-Object { $_.type -eq 'page' -and $_.url -like "*$HostFilter*" } | Select-Object -First 1
if (-not $tab) {
  Fail "no Chrome tab whose URL contains '$HostFilter' — open your Atlassian site in the debug Chrome window first"
}
$wsUrl = $tab.webSocketDebuggerUrl

# 2) Build the JS expression. It is an async IIFE returning a Promise; CDP
#    awaitPromise+returnByValue resolves it to plain JSON for us.
$methodJs = $Method | ConvertTo-Json          # -> "GET" (quoted JS string)
$pathJs   = $Path   | ConvertTo-Json
$bodyJs   = if ([string]::IsNullOrWhiteSpace($Body)) { 'null' } else { $Body }  # raw JSON == valid JS literal

$expr = @"
(async () => {
  const opts = { method: $methodJs, credentials: 'include', headers: { 'Accept': 'application/json' } };
  const __b = $bodyJs;
  if (__b !== null) { opts.headers['Content-Type']='application/json'; opts.headers['X-Atlassian-Token']='no-check'; opts.body=JSON.stringify(__b); }
  try {
    const r = await fetch(location.origin + $pathJs, opts);
    const t = await r.text();
    let d; try { d = JSON.parse(t); } catch (e) { d = t; }
    return { status: r.status, ok: r.ok, data: d };
  } catch (e) { return { status: 0, ok: false, error: String(e) }; }
})()
"@

$msg = @{
  id     = 1
  method = 'Runtime.evaluate'
  params = @{ expression = $expr; awaitPromise = $true; returnByValue = $true }
} | ConvertTo-Json -Depth 10 -Compress

# 3) Open WebSocket, send, read frames until we get the id:1 response.
Add-Type -AssemblyName System.Net.WebSockets.Client -ErrorAction SilentlyContinue
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
try {
  $ws.ConnectAsync([Uri]$wsUrl, $ct).Wait()
} catch {
  Fail "websocket connect failed (did you launch Chrome with --remote-allow-origins=*?): $($_.Exception.InnerException.Message)"
}

$bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
$seg   = New-Object System.ArraySegment[byte] (,$bytes)
$ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

function Receive-Message($socket, $ct) {
  $buffer = New-Object byte[] 65536
  $sb = New-Object System.Text.StringBuilder
  do {
    $rseg = New-Object System.ArraySegment[byte] (,$buffer)
    $res  = $socket.ReceiveAsync($rseg, $ct).Result
    [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $res.Count))
  } while (-not $res.EndOfMessage)
  return $sb.ToString()
}

$deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
$result = $null
while ([DateTime]::UtcNow -lt $deadline) {
  $raw = Receive-Message $ws $ct
  $obj = $raw | ConvertFrom-Json
  if ($obj.id -eq 1) {
    if ($obj.result.exceptionDetails) {
      $result = @{ status = 0; ok = $false; error = "JS exception: $($obj.result.exceptionDetails.text) $($obj.result.exceptionDetails.exception.description)" }
    } else {
      $result = $obj.result.result.value
    }
    break
  }
}

try { $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, '', $ct).Wait() } catch {}

if ($null -eq $result) { Fail "timeout after ${TimeoutMs}ms waiting for CDP response" }
[Console]::Out.Write(($result | ConvertTo-Json -Depth 30 -Compress))
