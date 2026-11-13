$script:activeChildProcess = $null
$script:isWindowClosing    = $false

function Stop-ActiveChildProcess {
    try {
        if ($script:activeChildProcess -and -not $script:activeChildProcess.HasExited) {
            $script:activeChildProcess.Kill()
        }
    } catch {}
}

function Log-Text {
    param([string]$text)
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    $clean = $text -replace '\x1B\[[0-9;]*[a-zA-Z]', ''
    if ($clean.Contains("`r")) {
        $parts = $clean -split "`r"
        $clean = $parts[-1]
    }
    $trimmed = $clean.TrimEnd("`r", "`n")
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return }

    $trimmed = $trimmed.Replace("[✓]", "[OK]").Replace("[✓ ", "[OK - ").Replace("✓", "OK")
    $trimmed = $trimmed.Replace("[❌]", "[ERR]").Replace("[❌ ", "[ERR - ").Replace("❌", "ERR")
    $trimmed = $trimmed.Replace("[⚠️]", "[WARN]").Replace("[⚠️ ", "[WARN - ").Replace("⚠️", "WARN")
    $trimmed = $trimmed.Replace("[🔍]", "[SCAN]").Replace("🔍 ", "").Replace("🔍", "")
    $trimmed = $trimmed.Replace("[↗]", "[WEB]").Replace("↗", "->")
    $trimmed = $trimmed.Replace("🟢 ", "").Replace("🔴 ", "").Replace("🚀 ", "").Replace("⚡ ", "").Replace("🗑️ ", "")
    $trimmed = $trimmed.Replace("•", "-").Replace("─", "-")

    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $color = [System.ConsoleColor]::Gray

    if ($trimmed -match '^={4,}|^-{4,}|^\s*-{4,}') {
        $color = [System.ConsoleColor]::DarkCyan
    } elseif ($trimmed -match '\[OK|HOÀN THÀNH|THÀNH CÔNG') {
        $color = [System.ConsoleColor]::Green
    } elseif ($trimmed -match '\[ERR|\[x\]|LỖI') {
        $color = [System.ConsoleColor]::Red
    } elseif ($trimmed -match '\[!\]|\[WARN|\[LOCK\]') {
        $color = [System.ConsoleColor]::Yellow
    } elseif ($trimmed -match '\[SCAN\]|BẮT ĐẦU|ĐANG QUÉT') {
        $color = [System.ConsoleColor]::Cyan
    } elseif ($trimmed -match '\[CLEAN\]') {
        $color = [System.ConsoleColor]::Magenta
    } elseif ($trimmed -match '^\[\d+/\d+\]') {
        $color = [System.ConsoleColor]::White
    }

    try {
        Write-Host "[$timestamp] $trimmed" -ForegroundColor $color
    } catch {
        [Console]::WriteLine("[$timestamp] $trimmed")
    }
}

function Run-CliStream {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        [Parameter(Mandatory = $false)]
        [string]$Args = ""
    )

    try {
        $timestamp = (Get-Date).ToString("HH:mm:ss")
        try {
            Write-Host "[$timestamp] > $FileName $Args" -ForegroundColor DarkGray
        } catch {}

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $FileName
        $pinfo.Arguments = $Args
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $false
        $pinfo.RedirectStandardOutput = $false
        $pinfo.RedirectStandardError = $false

        $p = [System.Diagnostics.Process]::Start($pinfo)
        if ($null -eq $p) {
            Log-Text "[!] Không thể khởi động tiến trình: $FileName"
            return -1
        }

        $script:activeChildProcess = $p
        try {
            while (-not $p.HasExited) {
                if ($script:isWindowClosing) {
                    Stop-ActiveChildProcess
                    break
                }
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 25
            }

            try { [void]$p.WaitForExit(1000) } catch {}
            [System.Windows.Forms.Application]::DoEvents()
            $exitCode = $p.ExitCode
            return $exitCode
        } finally {
            $script:activeChildProcess = $null
            try { $p.Dispose() } catch {}
        }
    } catch {
        Log-Text "[!] Lỗi khi thực thi lệnh [$FileName $Args]: $($_.Exception.Message)"
        return -1
    }
}
