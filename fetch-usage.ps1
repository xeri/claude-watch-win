# Fetches Claude API usage stats and writes them to %TEMP%\.claude_usage_cache.
# Line 1: five_hour.utilization  (integer %)
# Line 2: seven_day.utilization  (integer %)
# Line 3: five_hour.resets_at     (raw ISO string, e.g. 2026-02-26T12:59:59.997656+00:00)
# Line 4: seven_day.resets_at     (raw ISO string)
# All output is suppressed; meant to be run in the background.

$ErrorActionPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$CacheFile  = Join-Path $env:TEMP '.claude_usage_cache'
$TokenCache = Join-Path $env:TEMP '.claude_token_cache'
$TokenTtl   = 900  # 15 minutes
$CredsFile  = Join-Path $env:USERPROFILE '.claude\.credentials.json'

# --- read a fresh access token from the Claude Code credentials file ---
function Get-TokenFromCredentials {
    if (-not (Test-Path $CredsFile)) { return $null }
    try {
        $creds = Get-Content -Raw -LiteralPath $CredsFile | ConvertFrom-Json
    } catch { return $null }
    $tok = $creds.claudeAiOauth.accessToken
    if ([string]::IsNullOrEmpty($tok)) { return $null }
    Set-Content -LiteralPath $TokenCache -Value $tok -NoNewline -Encoding ascii
    return $tok
}

# --- call the usage endpoint; returns @{ ok = $bool; data = <obj>; status = <int> } ---
function Invoke-Usage($token) {
    $headers = @{
        'accept'         = 'application/json'
        'anthropic-beta' = 'oauth-2025-04-20'
        'authorization'  = "Bearer $token"
        'user-agent'     = 'claude-code/2.1.11'
    }
    try {
        $resp = Invoke-RestMethod -Uri 'https://api.anthropic.com/oauth/usage' `
            -Headers $headers -TimeoutSec 3 -Method Get
        return @{ ok = $true; data = $resp }
    } catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        return @{ ok = $false; status = $status }
    }
}

# --- get token (with 15-min cache to avoid repeated credential reads) ---
$token = $null
if (Test-Path $TokenCache) {
    $age = ((Get-Date) - (Get-Item $TokenCache).LastWriteTime).TotalSeconds
    if ($age -lt $TokenTtl) { $token = (Get-Content -Raw -LiteralPath $TokenCache).Trim() }
}
if (-not $token) { $token = Get-TokenFromCredentials }
if (-not $token) { exit 0 }

$result = Invoke-Usage $token

# The cached token may be stale (Claude Code rotates the OAuth token). If it was
# rejected, drop the cache, re-read fresh credentials and retry once.
if ((-not $result.ok) -and ($result.status -eq 401 -or $result.status -eq 403)) {
    Remove-Item -LiteralPath $TokenCache -ErrorAction SilentlyContinue
    $token = Get-TokenFromCredentials
    if (-not $token) { exit 0 }
    $result = Invoke-Usage $token
}

if (-not $result.ok) { exit 0 }

$usage      = $result.data
$fiveHRaw   = $usage.five_hour.utilization
$sevenDRaw  = $usage.seven_day.utilization
$fiveReset  = $usage.five_hour.resets_at
$sevenReset = $usage.seven_day.resets_at

if (($null -ne $fiveHRaw) -and ($null -ne $sevenDRaw)) {
    $fiveH  = [int][math]::Round([double]$fiveHRaw,  [MidpointRounding]::AwayFromZero)
    $sevenD = [int][math]::Round([double]$sevenDRaw, [MidpointRounding]::AwayFromZero)
    $out = "$fiveH`n$sevenD`n$fiveReset`n$sevenReset`n"
    Set-Content -LiteralPath $CacheFile -Value $out -NoNewline -Encoding ascii
}
