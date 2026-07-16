# claude-watch-win

> **Windows fork.** This is a Windows port of [claude-watch](https://github.com/xleddyl/claude-watch) — the shell scripts have been
> rewritten in native PowerShell so they run on the Claude Code CLI under Windows with no extra
> dependencies (no `jq`, `curl`, or macOS keychain required).

![my-minimal-claude-code-statusline-config-v0-bw0th9wf90mg1](https://github.com/user-attachments/assets/05edca4f-749a-433b-b4da-262f840e0a1c)

## Installation
```
git clone https://github.com/xeri/claude-watch-win.git
cd claude-watch-win
```

**1. Copy the scripts**

```powershell
Copy-Item fetch-usage.ps1        "$env:USERPROFILE\.claude\fetch-usage.ps1"
Copy-Item statusline-command.ps1 "$env:USERPROFILE\.claude\statusline-command.ps1"
```

**2. Merge `settings.json` into `%USERPROFILE%\.claude\settings.json`**

Add the `statusLine` and `hooks` blocks from `settings.json` into your existing
`%USERPROFILE%\.claude\settings.json`. If you don't have one yet, copy it directly:

```powershell
Copy-Item settings.json "$env:USERPROFILE\.claude\settings.json"
```

**3. Trigger an initial fetch (optional)**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\fetch-usage.ps1"
```

The usage cache will otherwise populate automatically on the next tool call or Claude response.

**4. Restart Claude Code**

Claude Code does **not** hot-reload `statusLine` changes — fully quit and relaunch it (close the app / exit the CLI) before the bar appears.

## A note on the paths in `settings.json`

Claude Code on Windows runs `statusLine` and hook commands through its bundled **Git Bash**, not `cmd.exe` or PowerShell. That's why the commands use bash's **`$HOME`** to locate the scripts — cmd's `%USERPROFILE%` and PowerShell's `$env:USERPROFILE` are **not** expanded in that context and will leave the bar blank.

If your setup doesn't run commands through bash (or `$HOME` isn't set), replace `$HOME/.claude/...` with an absolute path using forward slashes, e.g. `C:/Users/<you>/.claude/statusline-command.ps1`.

## Troubleshooting

- **Bar is completely blank** — first, **restart Claude Code** (step 4); `statusLine` is only read at startup. If it's still blank, the script path isn't resolving — swap `$HOME/.claude/...` in `settings.json` for your absolute path (see the note above). Test the command by hand from **Git Bash**:
  ```sh
  echo '{}' | powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/statusline-command.ps1"
  ```
- **Line 1 shows but usage (line 2) is missing** — the cache hasn't been written yet. Run the fetch manually (step 3) and check `%TEMP%\.claude_usage_cache` has four lines. An empty result usually means the OAuth token couldn't be read from `%USERPROFILE%\.claude\.credentials.json`.
- **Colors show as raw `[38;5;208m` codes** — your terminal isn't rendering ANSI. Use Windows Terminal.

## How it works

- **`statusline-command.ps1`** — reads the JSON piped by Claude Code and renders two lines: model/folder/branch, then usage stats and context window.
- **`fetch-usage.ps1`** — reads the OAuth token from `%USERPROFILE%\.claude\.credentials.json`, caches it in `%TEMP%\.claude_token_cache` for 15 minutes, hits the `/oauth/usage` endpoint (3s timeout), and writes results to `%TEMP%\.claude_usage_cache`. On failure the stale cache is preserved.
- **`settings.json`** — wires up the statusline command and triggers `fetch-usage.ps1` in the background on `PreToolUse` and `Stop` hooks.

## Dependencies

- **Windows PowerShell 5.1+** (built into Windows) or PowerShell 7 — used for JSON parsing (`ConvertFrom-Json`) and the HTTP request (`Invoke-RestMethod`), so no `jq`/`curl` needed.
- `git` (optional, for branch display).
- A terminal that supports ANSI colors (Windows Terminal, or the Claude Code CLI). If colors show as raw escape codes in `cmd.exe`, use Windows Terminal.
