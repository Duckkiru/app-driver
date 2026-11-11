# ── FUNCTION: THỰC THI TIẾN TRÌNH & STREAM LOG VÀO TERMINAL ──

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
        $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $pinfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true

        $p = [System.Diagnostics.Process]::Start($pinfo)
        if ($null -eq $p) {
            Log-Text "[!] Không thể khởi động tiến trình: $FileName"
            return -1
        }

        # Đọc bất đồng bộ hai luồng stdout và stderr để chống nghẽn (deadlock) và không khóa giao diện
        $outTask = $p.StandardOutput.ReadLineAsync()
        $errTask = $p.StandardError.ReadLineAsync()

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

            if ($p.HasExited -and $outTask -eq $null -and $errTask -eq $null) {
                break
            }

            # Duy trì thông điệp giao diện WPF/WinForms luôn phản hồi tức thì
            [System.Windows.Forms.Application]::DoEvents()

            if (-not $hasData) {
                Start-Sleep -Milliseconds 25
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
