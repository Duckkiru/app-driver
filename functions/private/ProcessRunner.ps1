# ── FUNCTION: THỰC THI TIẾN TRÌNH & STREAM LOG TRỰC TIẾP RA CỬA SỔ TERMINAL (CHUẨN WINUTIL) ──

function Log-Text {
    param([string]$text)
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    # Loại bỏ các mã màu ANSI escape code nếu có
    $clean = $text -replace '\x1B\[[0-9;]*[a-zA-Z]', ''
    if ($clean.Contains("`r")) {
        $parts = $clean -split "`r"
        $clean = $parts[-1]
    }
    $trimmed = $clean.TrimEnd("`r", "`n")
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return }

    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $color = [System.ConsoleColor]::Gray

    if ($trimmed -match '^={4,}|^─{4,}|^\s*─{4,}') {
        $color = [System.ConsoleColor]::DarkCyan
    } elseif ($trimmed -match '\[✓|HOÀN THÀNH|THÀNH CÔNG') {
        $color = [System.ConsoleColor]::Green
    } elseif ($trimmed -match '\[❌|\[x\]|LỖI') {
        $color = [System.ConsoleColor]::Red
    } elseif ($trimmed -match '\[!\]|\[⚠️\]|\[LOCK\]') {
        $color = [System.ConsoleColor]::Yellow
    } elseif ($trimmed -match '🚀|⚡|🗑️|🔍|\[🔍\]') {
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
            Write-Host "[$timestamp] ❯ $FileName $Args" -ForegroundColor DarkGray
        } catch {}

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $FileName
        $pinfo.Arguments = $Args
        # Kế thừa trực tiếp Console Handle của cửa sổ Terminal chạy nền (như WinUtil)
        # Giúp hiển thị 100% thanh tiến trình thực (progress bar) và màu sắc gốc của WinGet / DISM / SFC
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $false
        $pinfo.RedirectStandardOutput = $false
        $pinfo.RedirectStandardError = $false

        $p = [System.Diagnostics.Process]::Start($pinfo)
        if ($null -eq $p) {
            Log-Text "[!] Không thể khởi động tiến trình: $FileName"
            return -1
        }

        while (-not $p.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 25
        }

        try { [void]$p.WaitForExit(1000) } catch {}
        [System.Windows.Forms.Application]::DoEvents()
        $exitCode = $p.ExitCode
        try { $p.Dispose() } catch {}
        return $exitCode
    } catch {
        Log-Text "[!] Lỗi khi thực thi lệnh [$FileName $Args]: $($_.Exception.Message)"
        return -1
    }
}
