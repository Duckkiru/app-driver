# ── FUNCTION: THỰC THI TIẾN TRÌNH & STREAM LOG VÀO TERMINAL ──

function Update-WpfUi {
    <#
    .SYNOPSIS
        Bơm thông điệp WPF Dispatcher để giao diện mượt mà 60fps, không bao giờ giật lag hay treo đơ.
    #>
    if ([System.Windows.Threading.Dispatcher]::CurrentDispatcher -ne $null) {
        try {
            [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
        } catch {}
    }
}

function Log-Text {
    param([string]$text)
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $logBox = if ($txtLog) { $txtLog } elseif ($txtTerminal) { $txtTerminal } else { $null }
    if ($logBox) {
        $timestamp = (Get-Date).ToString("HH:mm:ss")
        $trimmed = $text.TrimEnd("`r", "`n")
        $logBox.AppendText("[$timestamp] $trimmed`r`n")
        $logBox.ScrollToEnd()
    }
    Update-WpfUi
}

function Run-CliStream {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        [Parameter(Mandatory = $false)]
        [string]$Args = ""
    )

    try {
        $targetCmd = if (Get-Command $FileName -ErrorAction SilentlyContinue) {
            (Get-Command $FileName -ErrorAction SilentlyContinue).Source
        } else {
            $FileName
        }

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $targetCmd
        $pinfo.Arguments = $Args
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardInput = $true
        $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $pinfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true

        $p = [System.Diagnostics.Process]::Start($pinfo)
        if ($null -eq $p) {
            Log-Text "[!] Không thể khởi động tiến trình: $FileName"
            return -1
        }

        # Đóng ngay stdin để chống mọi tiến trình chờ nhập dữ liệu dòng lệnh (chống treo chết)
        try { $p.StandardInput.Close() } catch {}

        $outBuf = New-Object char[] 2048
        $errBuf = New-Object char[] 2048
        $outTask = $p.StandardOutput.ReadAsync($outBuf, 0, $outBuf.Length)
        $errTask = $p.StandardError.ReadAsync($errBuf, 0, $errBuf.Length)

        $outAcc = New-Object System.Text.StringBuilder
        $errAcc = New-Object System.Text.StringBuilder
        $flushTimer = [System.Diagnostics.Stopwatch]::StartNew()

        while ($true) {
            $hasData = $false

            if ($outTask -ne $null -and $outTask.IsCompleted) {
                try {
                    $count = $outTask.Result
                    if ($count -gt 0) {
                        $hasData = $true
                        [void]$outAcc.Append($outBuf, 0, $count)
                        $outTask = $p.StandardOutput.ReadAsync($outBuf, 0, $outBuf.Length)
                    } else {
                        $outTask = $null
                    }
                } catch {
                    $outTask = $null
                }
            }

            if ($errTask -ne $null -and $errTask.IsCompleted) {
                try {
                    $count = $errTask.Result
                    if ($count -gt 0) {
                        $hasData = $true
                        [void]$errAcc.Append($errBuf, 0, $count)
                        $errTask = $p.StandardError.ReadAsync($errBuf, 0, $errBuf.Length)
                    } else {
                        $errTask = $null
                    }
                } catch {
                    $errTask = $null
                }
            }

            # Xử lý stdout: bắt và phân tách cả \n lẫn \r (tiến trình tải winget/sfc/dism)
            if ($outAcc.Length -gt 0) {
                $content = $outAcc.ToString()
                $parts = $content -split "[\r\n]+"
                if ($parts.Count -gt 1) {
                    for ($k = 0; $k -lt ($parts.Count - 1); $k++) {
                        $line = $parts[$k].Trim()
                        if (-not [string]::IsNullOrWhiteSpace($line)) {
                            Log-Text $line
                        }
                    }
                    [void]$outAcc.Clear()
                    [void]$outAcc.Append($parts[$parts.Count - 1])
                } elseif ($flushTimer.ElapsedMilliseconds -gt 350) {
                    $line = $content.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($line)) {
                        Log-Text $line
                    }
                    [void]$outAcc.Clear()
                    $flushTimer.Restart()
                }
            }

            # Xử lý stderr
            if ($errAcc.Length -gt 0) {
                $errContent = $errAcc.ToString()
                $errParts = $errContent -split "[\r\n]+"
                if ($errParts.Count -gt 1) {
                    for ($k = 0; $k -lt ($errParts.Count - 1); $k++) {
                        $line = $errParts[$k].Trim()
                        if (-not [string]::IsNullOrWhiteSpace($line)) {
                            Log-Text "[stderr] $line"
                        }
                    }
                    [void]$errAcc.Clear()
                    [void]$errAcc.Append($errParts[$errParts.Count - 1])
                }
            }

            if ($p.HasExited -and $outTask -eq $null -and $errTask -eq $null) {
                break
            }

            Update-WpfUi

            if (-not $hasData) {
                Start-Sleep -Milliseconds 20
            }
        }

        # Flush buffer còn lại
        if ($outAcc.Length -gt 0) {
            $rem = $outAcc.ToString().Trim()
            if (-not [string]::IsNullOrWhiteSpace($rem)) { Log-Text $rem }
        }
        if ($errAcc.Length -gt 0) {
            $rem = $errAcc.ToString().Trim()
            if (-not [string]::IsNullOrWhiteSpace($rem)) { Log-Text "[stderr] $rem" }
        }

        $p.WaitForExit()
        Update-WpfUi
        return $p.ExitCode
    } catch {
        Log-Text "[!] Lỗi khi thực thi lệnh [$FileName $Args]: $($_.Exception.Message)"
        return -1
    }
}
