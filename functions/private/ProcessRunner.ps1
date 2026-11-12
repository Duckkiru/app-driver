# ── FUNCTION: THỰC THI TIẾN TRÌNH & STREAM LOG VÀO TERMINAL ──

function Log-Text {
    param([string]$text)
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $logBox = if ($txtLog) { $txtLog } elseif ($txtTerminal) { $txtTerminal } else { $null }
    if ($logBox) {
        # Loại bỏ các mã màu ANSI escape code nếu có
        $clean = $text -replace '\x1B\[[0-9;]*[a-zA-Z]', ''
        # Xử lý ký tự carriage return (\r) trên các thanh tiến trình CLI
        if ($clean.Contains("`r")) {
            $parts = $clean -split "`r"
            $clean = $parts[-1]
        }
        $trimmed = $clean.TrimEnd("`r", "`n")
        if ([string]::IsNullOrWhiteSpace($trimmed)) { return }

        # Giới hạn kích thước log để bảo vệ bộ nhớ và chống giật lag UI khi chạy lâu
        if ($logBox.LineCount -gt 1500) {
            $allLines = $logBox.Text -split "`r?`n"
            if ($allLines.Count -gt 600) {
                $logBox.Text = ($allLines[($allLines.Count - 600)..($allLines.Count - 1)] -join "`r`n") + "`r`n"
            }
        }

        $timestamp = (Get-Date).ToString("HH:mm:ss")
        $logBox.AppendText("[$timestamp] $trimmed`r`n")
        $logBox.ScrollToEnd()
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
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $FileName
        $pinfo.Arguments = $Args
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true

        # Nhận diện bảng mã luồng phù hợp cho từng công cụ để chống lỗi font (mojibake)
        # sfc.exe xuất Unicode (UTF-16LE), winget xuất UTF-8, các lệnh hệ thống khác dùng Console OEM/Default
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName).ToLowerInvariant()
        $streamEncoding = switch ($baseName) {
            "sfc"    { [System.Text.Encoding]::Unicode }
            "winget" { [System.Text.Encoding]::UTF8 }
            default  {
                if ([System.Console]::OutputEncoding) {
                    [System.Console]::OutputEncoding
                } else {
                    [System.Text.Encoding]::Default
                }
            }
        }

        $pinfo.StandardOutputEncoding = $streamEncoding
        $pinfo.StandardErrorEncoding  = $streamEncoding
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true

        $p = [System.Diagnostics.Process]::Start($pinfo)
        if ($null -eq $p) {
            Log-Text "[!] Không thể khởi động tiến trình: $FileName"
            return -1
        }

        # Đọc bất đồng bộ đồng thời 2 luồng stdout và stderr để triệt tiêu nguy cơ treo luồng (deadlock)
        $outTask = $p.StandardOutput.ReadLineAsync()
        $errTask = $p.StandardError.ReadLineAsync()
        $lastEventTime = [System.DateTime]::UtcNow
        $exitWaitStart = $null

        while ($true) {
            $hasData = $false

            if ($outTask -ne $null -and $outTask.IsCompleted) {
                $line = $outTask.Result
                if ($line -ne $null) {
                    Log-Text $line
                    $outTask = $p.StandardOutput.ReadLineAsync()
                    $hasData = $true
                } else {
                    $outTask = $null
                }
            }

            if ($errTask -ne $null -and $errTask.IsCompleted) {
                $errLine = $errTask.Result
                if ($errLine -ne $null) {
                    Log-Text $errLine
                    $errTask = $p.StandardError.ReadLineAsync()
                    $hasData = $true
                } else {
                    $errTask = $null
                }
            }

            if ($p.HasExited) {
                if ($outTask -eq $null -and $errTask -eq $null) {
                    break
                }
                # Tránh deadlock vĩnh viễn nếu tiến trình con phân nhánh giữ handle pipe mở
                if ($null -eq $exitWaitStart) {
                    $exitWaitStart = [System.DateTime]::UtcNow
                } elseif (([System.DateTime]::UtcNow - $exitWaitStart).TotalSeconds -ge 5) {
                    break
                }
            }

            # Bơm thông điệp giao diện WPF/WinForms có điều tiết (throttling) để tối ưu hiệu năng render
            $now = [System.DateTime]::UtcNow
            if (($now - $lastEventTime).TotalMilliseconds -ge 25 -or $hasData) {
                [System.Windows.Forms.Application]::DoEvents()
                $lastEventTime = $now
            }

            if (-not $hasData) {
                Start-Sleep -Milliseconds 20
            }
        }

        $p.WaitForExit()
        [System.Windows.Forms.Application]::DoEvents()
        return $p.ExitCode
    } catch {
        Log-Text "[!] Lỗi khi thực thi lệnh [$FileName $Args]: $($_.Exception.Message)"
        return -1
    }
}
