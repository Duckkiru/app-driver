$script:activeChildProcess = $null
$script:isWindowClosing    = $false

function Stop-ActiveChildProcess {
    try {
        if ($script:activeChildProcess -and -not $script:activeChildProcess.HasExited) {
            $pidToKill = $script:activeChildProcess.Id
            try {
                Start-Process "taskkill.exe" -ArgumentList "/F /T /PID $pidToKill" -NoNewWindow -Wait -ErrorAction SilentlyContinue
            } catch {}
            try {
                $script:activeChildProcess.Kill()
            } catch {}
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
                try { [System.Windows.Forms.Application]::DoEvents() } catch {}
                Start-Sleep -Milliseconds 25
            }

            try { [void]$p.WaitForExit(1000) } catch {}
            try { [System.Windows.Forms.Application]::DoEvents() } catch {}
            $exitCode = try { $p.ExitCode } catch { -1 }
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

function Split-CommandLineExecutableAndArgs {
    param([string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) {
        return [PSCustomObject]@{ Exe = ""; Args = "" }
    }

    $expanded = [System.Environment]::ExpandEnvironmentVariables($CommandLine).Trim()
    if ($expanded.StartsWith('"')) {
        $qIdx = $expanded.IndexOf('"', 1)
        if ($qIdx -gt 1) {
            return [PSCustomObject]@{
                Exe  = $expanded.Substring(1, $qIdx - 1).Trim()
                Args = $expanded.Substring($qIdx + 1).Trim()
            }
        }
        return [PSCustomObject]@{ Exe = $expanded.Trim('"'); Args = "" }
    }

    if ($expanded.StartsWith("'")) {
        $sqIdx = $expanded.IndexOf("'", 1)
        if ($sqIdx -gt 1) {
            return [PSCustomObject]@{
                Exe  = $expanded.Substring(1, $sqIdx - 1).Trim()
                Args = $expanded.Substring($sqIdx + 1).Trim()
            }
        }
        return [PSCustomObject]@{ Exe = $expanded.Trim("'"); Args = "" }
    }

    $extMatches = [System.Text.RegularExpressions.Regex]::Matches($expanded, '\.(?:exe|com|cmd|bat)(?=\s|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($extMatches.Count -gt 0) {
        $firstCand = $null
        foreach ($em in $extMatches) {
            $splitPos = $em.Index + $em.Length
            $candExe  = $expanded.Substring(0, $splitPos).Trim()
            $candArgs = $expanded.Substring($splitPos).Trim()
            if ($null -eq $firstCand) {
                $firstCand = [PSCustomObject]@{ Exe = $candExe; Args = $candArgs }
            }
            try {
                if ([System.IO.File]::Exists($candExe)) {
                    return [PSCustomObject]@{ Exe = $candExe; Args = $candArgs }
                }
            } catch {}
        }
        return $firstCand
    }

    $parts = $expanded -split '\s+', 2
    return [PSCustomObject]@{
        Exe  = $parts[0]
        Args = if ($parts.Count -gt 1) { $parts[1] } else { "" }
    }
}

function Get-MsiProductCodeFromCommand {
    param(
        [string]$UninstallCommand,
        [string]$FallbackId = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($UninstallCommand)) {
        $m = [System.Text.RegularExpressions.Regex]::Match($UninstallCommand, '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}')
        if ($m.Success) { return $m.Value }
        $mLoose = [System.Text.RegularExpressions.Regex]::Match($UninstallCommand, '\{[0-9A-Fa-f\-]{32,38}\}')
        if ($mLoose.Success) { return $mLoose.Value }
    }
    if (-not [string]::IsNullOrWhiteSpace($FallbackId)) {
        $fb = $FallbackId.Trim()
        if ($fb -match '^\{[0-9A-Fa-f\-]{32,38}\}$') { return $fb }
        return $fb
    }
    return ""
}
