# Claude Code statusline renderer (Windows / PowerShell port).
# Reads the JSON piped by Claude Code on stdin and prints two lines:
#   line 1: model | folder - branch
#   line 2: usage stats (5h / 7d) | context window
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $data = $raw | ConvertFrom-Json } catch { exit 0 }

# --- model ---
$model = $data.model.display_name
if (-not $model) { $model = '' }

# --- reasoning effort ---
# models with "1M context" -> "(1M - <effort>)", others -> "(<effort>)"
$effort = $data.effort.level
if ($effort) {
    if ($model -like '*1M context*') {
        $model = $model -replace '1M context', "1M - $effort"
    } else {
        $model = "$model ($effort)"
    }
}

# --- folder ---
$dir = $data.workspace.current_dir
if (-not $dir) { $dir = $data.cwd }
if (-not $dir) { $dir = '' }
$dirName = if ($dir) { Split-Path -Leaf $dir } else { '' }

# --- git branch ---
$branch = ''
if ($dir -and (Get-Command git -ErrorAction SilentlyContinue)) {
    $branch = (git -C "$dir" symbolic-ref --short HEAD 2>$null)
    if (-not $branch) { $branch = (git -C "$dir" rev-parse --short HEAD 2>$null) }
    if ($branch) { $branch = $branch.Trim() }
}

# --- usage stats (5h / 7d) from cache ---
$CacheFile = Join-Path $env:TEMP '.claude_usage_cache'
$fiveH = ''; $sevenD = ''; $fiveReset = ''; $sevenReset = ''

if (Test-Path $CacheFile) {
    $lines = @(Get-Content -LiteralPath $CacheFile)
    if ($lines.Count -ge 1) { $fiveH      = $lines[0] }
    if ($lines.Count -ge 2) { $sevenD     = $lines[1] }
    if ($lines.Count -ge 3) { $fiveReset  = $lines[2] }
    if ($lines.Count -ge 4) { $sevenReset = $lines[3] }
} else {
    # kick off a background fetch so the cache populates for next render
    $fetch = Join-Path $env:USERPROFILE '.claude\fetch-usage.ps1'
    if (Test-Path $fetch) {
        Start-Process -FilePath 'powershell' `
            -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$fetch `
            -WindowStyle Hidden | Out-Null
    }
}

# --- compute_delta: given a raw ISO timestamp, returns human-readable time until reset ---
function Get-Delta($iso) {
    if ([string]::IsNullOrWhiteSpace($iso)) { return $null }
    try {
        $reset = [DateTimeOffset]::Parse(
            $iso,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal)
    } catch { return $null }
    $diff = $reset - [DateTimeOffset]::UtcNow
    if ($diff.TotalSeconds -le 0) { return 'now' }
    $days    = [int][math]::Floor($diff.TotalDays)
    $hours   = $diff.Hours
    $minutes = $diff.Minutes
    if ($days -gt 0)      { return "${days}d ${hours}h" }
    elseif ($hours -gt 0) { return "${hours}h ${minutes}m" }
    else                  { return "${minutes}m" }
}

# --- context window ---
$used = $data.context_window.used_percentage
$ctxStr = ''; $ctxTokensStr = ''
if (($null -ne $used) -and ("$used" -ne '')) {
    $usedInt = [int][math]::Round([double]$used, [MidpointRounding]::AwayFromZero)
    $ctxStr = "$usedInt%"
    $cu       = $data.context_window.current_usage
    $ctxTotal = $data.context_window.context_window_size
    if ($cu -and $ctxTotal) {
        $ctxUsed = [int64]$cu.cache_read_input_tokens +
                   [int64]$cu.cache_creation_input_tokens +
                   [int64]$cu.input_tokens +
                   [int64]$cu.output_tokens
        $ctxUsedK  = [int64]($ctxUsed  / 1000)
        $ctxTotalK = [int64]([int64]$ctxTotal / 1000)
        $ctxTokensStr = "${ctxUsedK}k/${ctxTotalK}k"
    }
}

# --- assemble output ---
$E   = [char]27
$SEP = "$E[90m $([char]0x2022) $E[0m"   # gray bullet separator
$sb  = New-Object System.Text.StringBuilder

# line 1: model | folder - branch
[void]$sb.Append("$E[38;5;208m$E[1m$model$E[22m$E[0m")
[void]$sb.Append("$E[90m | $E[0m")
[void]$sb.Append("$E[1m$E[38;2;76;208;222m$dirName$E[22m$E[0m")
if ($branch) {
    [void]$sb.Append($SEP)
    [void]$sb.Append("$E[1m$E[38;2;192;103;222m$branch$E[22m$E[0m")
}

# line 2: usage | ctx
[void]$sb.Append("`n")
if ($fiveH) {
    [void]$sb.Append("$E[38;2;156;162;175m5h $fiveH%$E[0m")
    $delta = Get-Delta $fiveReset
    if ($delta) { [void]$sb.Append("$E[2m$E[38;2;156;162;175m ($delta)$E[0m") }
}
if ($sevenD) {
    if ($fiveH) { [void]$sb.Append($SEP) }
    [void]$sb.Append("$E[38;2;156;162;175m7d $sevenD%$E[0m")
    $delta = Get-Delta $sevenReset
    if ($delta) { [void]$sb.Append("$E[2m$E[38;2;156;162;175m ($delta)$E[0m") }
}
if ($ctxStr) {
    [void]$sb.Append("$E[90m | $E[0m")
    [void]$sb.Append("$E[38;2;156;162;175mctx $ctxStr$E[0m")
    if ($ctxTokensStr) { [void]$sb.Append("$E[2m$E[38;2;156;162;175m ($ctxTokensStr)$E[0m") }
}

[Console]::Out.Write($sb.ToString())
