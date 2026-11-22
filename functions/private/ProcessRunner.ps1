$script:activeChildProcess   = $null
$script:activeChildProcesses = [System.Collections.Generic.List[object]]::new()
$script:isWindowClosing      = $false
$script:lastCliRun           = $null

function Stop-ChildProcessTree {
    param([object]$Proc)
    if ($null -eq $Proc) { return }
    try {
        $hasExited = try { $Proc.HasExited } catch { $true }
        if (-not $hasExited) {
            $pidToKill = try { $Proc.Id } catch { 0 }
            if ($pidToKill -gt 0) {
                $tkProc = $null
                try {
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = "taskkill.exe"
                    $psi.Arguments = "/F /T /PID $pidToKill"
                    $psi.CreateNoWindow = $true
                    $psi.UseShellExecute = $false
                    $tkProc = [System.Diagnostics.Process]::Start($psi)
                    if ($tkProc -and -not $tkProc.WaitForExit(3000)) {
                        try { $tkProc.Kill() } catch {}
                    }
                } catch {} finally {
                    if ($tkProc) { try { $tkProc.Dispose() } catch {} }
                }
            }
            try { $Proc.Kill() } catch {}
        }
    } catch {}
}

function Stop-ActiveChildProcess {
    try {
        $targets = [System.Collections.Generic.List[object]]::new()
        if ($null -ne $script:activeChildProcesses) {
            foreach ($proc in @($script:activeChildProcesses)) {
                if ($null -ne $proc -and -not $targets.Contains($proc)) {
                    $targets.Add($proc)
                }
            }
        }
        if ($null -ne $script:activeChildProcess -and -not $targets.Contains($script:activeChildProcess)) {
            $targets.Add($script:activeChildProcess)
        }
        foreach ($t in $targets) {
            Stop-ChildProcessTree $t
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
    $trimmed = $trimmed.Replace("[SUCC]", "[OK]").Replace("[SUCC - ", "[OK - ").Replace("[SUC]", "[OK]").Replace("[SUC - ", "[OK - ")
    $trimmed = $trimmed.Replace("[❌]", "[ERR]").Replace("[❌ ", "[ERR - ").Replace("❌", "ERR")
    $trimmed = $trimmed.Replace("[ERR - LỖI]", "[ERR]").Replace("[ERR - LỖI ", "[ERR - ").Replace("[ER]", "[ERR]").Replace("[ER - ", "[ERR - ")
    $trimmed = $trimmed.Replace("[⚠️]", "[WARN]").Replace("[⚠️ ", "[WARN - ").Replace("⚠️", "WARN")
    $trimmed = $trimmed.Replace("[🔍]", "[SCAN]").Replace("🔍 ", "").Replace("🔍", "")
    $trimmed = $trimmed.Replace("[↗]", "[WEB]").Replace("↗", "->")
    $trimmed = $trimmed.Replace("🟢 ", "").Replace("🔴 ", "").Replace("🚀 ", "").Replace("⚡ ", "").Replace("🗑️ ", "")
    $trimmed = $trimmed.Replace("•", "-").Replace("─", "-")

    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $color = [System.ConsoleColor]::Gray

    if ($trimmed -match '^={4,}|^-{4,}|^\s*-{4,}') {
        $color = [System.ConsoleColor]::DarkCyan
    } elseif ($trimmed -match '\[SUCC|\[OK|HOÀN THÀNH|THÀNH CÔNG') {
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
    <#
    .SYNOPSIS
        Execute an external command without blocking the WPF Dispatcher, streaming UTF-8 output live while capturing it and guarding against hangs.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        [Parameter(Mandatory = $false)]
        [Alias("Args")]
        [string]$Arguments = "",
        [switch]$IsolateStdin,
        [switch]$AllowCancel,
        [switch]$CaptureOutput,
        [switch]$ReturnResult,
        [int]$TimeoutSeconds = 360,
        [int]$IdleTimeoutSeconds = 180
    )

    $script:lastCliRun = [PSCustomObject]@{
        FileName  = $FileName
        Arguments = $Arguments
        ExitCode  = -1
        StdOut    = ""
        StdErr    = ""
        TimedOut  = $false
    }

    if ($script:isWindowClosing) {
        if ($ReturnResult) { return $script:lastCliRun }
        return -1
    }
    if ($AllowCancel -and $script:cancelRequested) {
        $script:lastCliRun.ExitCode = -2
        if ($ReturnResult) { return $script:lastCliRun }
        return -2
    }

    try {
        $timestamp = (Get-Date).ToString("HH:mm:ss")
        try {
            Write-Host "[$timestamp] > $FileName $Arguments" -ForegroundColor DarkGray
        } catch {}

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $FileName
        $pinfo.Arguments = $Arguments
        $pinfo.UseShellExecute = $false
        if ($CaptureOutput) {
            $pinfo.CreateNoWindow = $true
            $pinfo.RedirectStandardOutput = $true
            $pinfo.RedirectStandardError = $true
            $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $pinfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        } else {
            $pinfo.CreateNoWindow = $false
            $pinfo.RedirectStandardOutput = $false
            $pinfo.RedirectStandardError = $false
        }
        if ($IsolateStdin) {
            $pinfo.RedirectStandardInput = $true
        }

        $p = [System.Diagnostics.Process]::Start($pinfo)
        if ($null -eq $p) {
            Log-Text "[!] Không thể khởi động tiến trình: $FileName"
            if ($ReturnResult) { return $script:lastCliRun }
            return -1
        }
        if ($IsolateStdin) {
            try { $p.StandardInput.Close() } catch {}
        }

        $pump = $null
        $readTask = $null
        $errTask = $null
        if ($CaptureOutput) {
            if ("DuckUtil.ProcessOutputPump" -as [type]) {
                $pump = [DuckUtil.ProcessOutputPump]::new($p)
            } else {
                $readTask = $p.StandardOutput.ReadToEndAsync()
                $errTask = $p.StandardError.ReadToEndAsync()
            }
        }

        $effTimeout = if ($TimeoutSeconds -gt 0) { [double]$TimeoutSeconds } else { 3600.0 }
        $effIdle = if ($CaptureOutput -and $null -ne $pump -and $IdleTimeoutSeconds -gt 0) { [double]$IdleTimeoutSeconds } else { 0.0 }
        $cliSw = [System.Diagnostics.Stopwatch]::StartNew()
        $timedOutState = @{ TimedOut = $false; Reason = "" }

        $drainPumpLive = {
            if ($null -eq $pump) { return }
            $lines = $pump.DrainLiveLines(32)
            foreach ($ln in $lines) {
                if (-not [string]::IsNullOrWhiteSpace($ln)) {
                    Log-Text "   $ln"
                }
            }
        }.GetNewClosure()

        $prevActiveChild = $script:activeChildProcess
        $script:activeChildProcesses.Add($p) | Out-Null
        $script:activeChildProcess = $p
        try {
            $deepEngType = "DuckUtil.DeepUninstallerEngine" -as [type]
            $canAsyncWait = ($null -ne $deepEngType -and
                $null -ne $deepEngType.GetMethod("WaitForProcessExitAsync") -and
                $null -ne (Get-Command "Wait-TaskNonBlocking" -ErrorAction SilentlyContinue) -and
                $null -ne $window -and $null -ne $window.Dispatcher -and $window.Dispatcher.CheckAccess())

            if ($canAsyncWait) {
                $exitTask = $deepEngType::WaitForProcessExitAsync($p)
                $cancelVarRef = Get-Variable -Name cancelRequested -Scope Script -ErrorAction SilentlyContinue
                $closingVarRef = Get-Variable -Name isWindowClosing -Scope Script -ErrorAction SilentlyContinue
                $cancelOrHangCb = {
                    if ($null -ne $closingVarRef -and [bool]$closingVarRef.Value) { return $true }
                    if ($AllowCancel -and $null -ne $cancelVarRef -and [bool]$cancelVarRef.Value) { return $true }
                    if ($cliSw.Elapsed.TotalSeconds -ge $effTimeout) {
                        $timedOutState.TimedOut = $true
                        $timedOutState.Reason = "tổng thời gian vượt quá $([int]$effTimeout)s"
                        return $true
                    }
                    if ($effIdle -gt 0 -and $null -ne $pump -and $pump.IdleSeconds -ge $effIdle) {
                        $timedOutState.TimedOut = $true
                        $timedOutState.Reason = "không có phản hồi quá $([int]$effIdle)s"
                        return $true
                    }
                    return $false
                }.GetNewClosure()
                [void](Wait-TaskNonBlocking -Task $exitTask -TimeoutSeconds ($effTimeout + 2.0) -CancelCheck $cancelOrHangCb -OnTick $drainPumpLive)
                & $drainPumpLive

                if ($script:isWindowClosing -or ($AllowCancel -and $script:cancelRequested) -or $timedOutState.TimedOut) {
                    Stop-ChildProcessTree $p
                } elseif ($CaptureOutput -and $null -ne $pump) {
                    [void](Wait-TaskNonBlocking -Task $pump.ReadersTask -TimeoutSeconds 1.2 -CancelCheck $cancelOrHangCb -OnTick $drainPumpLive)
                    & $drainPumpLive
                } elseif ($CaptureOutput -and $null -ne $readTask -and $null -ne $errTask) {
                    $flushTask = [System.Threading.Tasks.Task]::WhenAll([System.Threading.Tasks.Task[]]@($readTask, $errTask))
                    [void](Wait-TaskNonBlocking -Task $flushTask -TimeoutSeconds 2.0 -CancelCheck $cancelOrHangCb)
                }
            } else {
                while ($true) {
                    & $drainPumpLive
                    $stillRunning = try { -not $p.HasExited } catch { $false }
                    if (-not $stillRunning) { break }
                    if ($script:isWindowClosing -or ($AllowCancel -and $script:cancelRequested)) {
                        Stop-ChildProcessTree $p
                        break
                    }
                    if ($cliSw.Elapsed.TotalSeconds -ge $effTimeout) {
                        $timedOutState.TimedOut = $true
                        $timedOutState.Reason = "tổng thời gian vượt quá $([int]$effTimeout)s"
                        Stop-ChildProcessTree $p
                        break
                    }
                    if ($effIdle -gt 0 -and $null -ne $pump -and $pump.IdleSeconds -ge $effIdle) {
                        $timedOutState.TimedOut = $true
                        $timedOutState.Reason = "không có phản hồi quá $([int]$effIdle)s"
                        Stop-ChildProcessTree $p
                        break
                    }
                    try { [System.Windows.Forms.Application]::DoEvents() } catch {}
                    Start-Sleep -Milliseconds 30
                }
                & $drainPumpLive
                if ($CaptureOutput -and -not $script:isWindowClosing -and -not ($AllowCancel -and $script:cancelRequested) -and -not $timedOutState.TimedOut) {
                    if ($null -ne $pump) {
                        $flushSw = [System.Diagnostics.Stopwatch]::StartNew()
                        while (-not $pump.ReadersTask.IsCompleted -and $flushSw.ElapsedMilliseconds -lt 1200) {
                            & $drainPumpLive
                            try { [System.Windows.Forms.Application]::DoEvents() } catch {}
                            Start-Sleep -Milliseconds 20
                        }
                        & $drainPumpLive
                    } elseif ($null -ne $readTask -and $null -ne $errTask) {
                        $flushSw = [System.Diagnostics.Stopwatch]::StartNew()
                        while ((-not $readTask.IsCompleted -or -not $errTask.IsCompleted) -and $flushSw.ElapsedMilliseconds -lt 1500) {
                            try { [System.Windows.Forms.Application]::DoEvents() } catch {}
                            Start-Sleep -Milliseconds 20
                        }
                    }
                }
            }

            if ($AllowCancel -and $script:cancelRequested) {
                $script:lastCliRun.ExitCode = -2
                if ($null -ne $pump) {
                    $script:lastCliRun.StdOut = $pump.GetStdOut()
                    $script:lastCliRun.StdErr = $pump.GetStdErr()
                }
                if ($ReturnResult) { return $script:lastCliRun }
                return -2
            }

            if ($timedOutState.TimedOut) {
                Log-Text "[WARN] Tiến trình '$FileName' bị treo ($($timedOutState.Reason)) - đã tự động dừng để tránh kẹt!"
                $script:lastCliRun = [PSCustomObject]@{
                    FileName  = $FileName
                    Arguments = $Arguments
                    ExitCode  = -3
                    StdOut    = if ($null -ne $pump) { $pump.GetStdOut() } else { "" }
                    StdErr    = if ($null -ne $pump) { $pump.GetStdErr() } else { "" }
                    TimedOut  = $true
                }
                if ($ReturnResult) { return $script:lastCliRun }
                return -3
            }

            if (-not $script:isWindowClosing) {
                try { [void]$p.WaitForExit(3000) } catch {}
                try { [System.Windows.Forms.Application]::DoEvents() } catch {}
            }
            $exitCode = try {
                if ($p.HasExited) { $p.ExitCode } else { -1 }
            } catch { -1 }

            $stdOutText = ""
            $stdErrText = ""
            if ($CaptureOutput) {
                if ($null -ne $pump) {
                    & $drainPumpLive
                    $stdOutText = $pump.GetStdOut()
                    $stdErrText = $pump.GetStdErr()
                } else {
                    if ($null -ne $readTask -and $readTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                        $stdOutText = [string]$readTask.Result
                    }
                    if ($null -ne $errTask -and $errTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                        $stdErrText = [string]$errTask.Result
                    }
                    if (-not [string]::IsNullOrWhiteSpace($stdOutText)) {
                        foreach ($rawOutLine in ($stdOutText -split "`n")) {
                            $cleanLine = ($rawOutLine -replace '\x1B\[[0-9;?]*[A-Za-z]', '')
                            if ($cleanLine.Contains("`r")) { $cleanLine = ($cleanLine -split "`r")[-1] }
                            $cleanLine = $cleanLine.Trim()
                            if ([string]::IsNullOrWhiteSpace($cleanLine)) { continue }
                            if ($cleanLine -match '^[-\\|/]+$' -or $cleanLine -match '^\s*\d+(\.\d+)?\s*(KB|MB|GB)\s*/\s*\d+') { continue }
                            Log-Text "   $cleanLine"
                        }
                    }
                    if (-not [string]::IsNullOrWhiteSpace($stdErrText)) {
                        foreach ($rawErrLine in ($stdErrText -split "`n")) {
                            $cleanErr = ($rawErrLine -replace '\x1B\[[0-9;?]*[A-Za-z]', '').Trim()
                            if (-not [string]::IsNullOrWhiteSpace($cleanErr)) {
                                Log-Text "   [stderr] $cleanErr"
                            }
                        }
                    }
                }
            }

            $script:lastCliRun = [PSCustomObject]@{
                FileName  = $FileName
                Arguments = $Arguments
                ExitCode  = $exitCode
                StdOut    = $stdOutText
                StdErr    = $stdErrText
                TimedOut  = $false
            }
            if ($ReturnResult) { return $script:lastCliRun }
            return $exitCode
        } finally {
            try { [void]$script:activeChildProcesses.Remove($p) } catch {}
            $restored = $null
            if ($null -ne $prevActiveChild) {
                $prevAlive = try { $script:activeChildProcesses.Contains($prevActiveChild) -or (-not $prevActiveChild.HasExited) } catch { $false }
                if ($prevAlive) { $restored = $prevActiveChild }
            }
            if ($null -eq $restored -and $script:activeChildProcesses.Count -gt 0) {
                $restored = $script:activeChildProcesses[$script:activeChildProcesses.Count - 1]
            }
            $script:activeChildProcess = $restored
            try { $p.Dispose() } catch {}
            if ("DuckUtil.ConsoleHelper" -as [type]) {
                try { [DuckUtil.ConsoleHelper]::DisableQuickEdit() } catch {}
            }
        }
    } catch {
        Log-Text "[!] Lỗi khi thực thi lệnh [$FileName $Arguments]: $($_.Exception.Message)"
        if ($ReturnResult) { return $script:lastCliRun }
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
