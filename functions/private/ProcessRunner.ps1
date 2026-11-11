# ── FUNCTION: THỰC THI TIẾN TRÌNH & STREAM LOG VÀO TERMINAL ──
function Log-Text {
    param([string]$text)
    if ($txtTerminal) {
        $timestamp = (Get-Date).ToString("HH:mm:ss")
        $txtTerminal.AppendText("[$timestamp] $text`r`n")
        $txtTerminal.ScrollToEnd()
    }
}

function Run-CliStream {
    param([string]$FileName, [string]$Args)
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $FileName
    $pinfo.Arguments = $Args
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true

    $p = [System.Diagnostics.Process]::Start($pinfo)
    while (-not $p.HasExited) {
        $line = $p.StandardOutput.ReadLine()
        if ($line) { Log-Text $line }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 40
    }
    $remOut = $p.StandardOutput.ReadToEnd()
    if ($remOut) { Log-Text $remOut }
    $remErr = $p.StandardError.ReadToEnd()
    if ($remErr) { Log-Text $remErr }
    return $p.ExitCode
}
