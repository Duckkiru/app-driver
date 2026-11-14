$isCompanion = ($env:APP_DRIVER_COMPANION -eq '1') -or ($args -and $args -contains '--companion')
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

$isInsideWT = -not [string]::IsNullOrWhiteSpace($env:WT_SESSION)
$script:IsInsideWindowsTerminal = $isInsideWT

if (-not $isCompanion -or -not $isAdmin) {
    $psExe = if ($PSVersionTable.PSEdition -eq 'Core' -or (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue)) {
        "pwsh.exe"
    } else {
        "powershell.exe"
    }

    $isWebSource = [string]::IsNullOrWhiteSpace($PSCommandPath) -or -not (Test-Path -LiteralPath $PSCommandPath)
    $workDir = if (-not $isWebSource) {
        Split-Path -Parent (Resolve-Path -LiteralPath $PSCommandPath).Path
    } else {
        if ($PWD -and $PWD.Path -and (Test-Path -LiteralPath $PWD.Path)) { $PWD.Path } else { [Environment]::GetFolderPath('UserProfile') }
    }

    $scriptTarget = $null
    if ($isWebSource) {
        $sbStr = if ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.ScriptBlock) {
            $MyInvocation.MyCommand.ScriptBlock.ToString()
        } else { "" }

        if (-not [string]::IsNullOrWhiteSpace($sbStr) -and $sbStr.Length -gt 1000) {
            $cacheScript = Join-Path $env:TEMP "App-Driver-Session.ps1"
            try {
                [System.IO.File]::WriteAllText($cacheScript, $sbStr, [System.Text.UTF8Encoding]::new($false))
                $scriptTarget = $cacheScript
            } catch {}
        }
    } else {
        $scriptTarget = (Resolve-Path -LiteralPath $PSCommandPath).Path
    }

    if ($scriptTarget) {
        $psArgs = "-NoProfile -Sta -ExecutionPolicy Bypass -File `"$scriptTarget`" --companion"
        if ($args -and $args.Count -gt 0) {
            $forwarded = foreach ($arg in $args) {
                if ($arg -eq '--companion') { continue }
                $argStr = "$arg"
                if ($argStr -match '[\s"]') {
                    '`"' + ($argStr -replace '"', '\"') + '`"'
                } else {
                    $argStr
                }
            }
            if ($forwarded) {
                $psArgs += " " + ($forwarded -join " ")
            }
        }
    } else {
        $psArgs = "-NoProfile -Sta -ExecutionPolicy Bypass -Command `"`$env:APP_DRIVER_COMPANION='1'; Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/Duckkiru/app-driver/main/App-Driver.ps1' | Invoke-Expression`""
    }

    function Get-WindowsTerminalPath {
        foreach ($bin in @('wt.exe', 'wtd.exe', 'wt')) {
            $cmd = Get-Command -Name $bin -CommandType Application -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
                return $cmd.Source
            }
        }

        $aliasCandidates = @(
            (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\Microsoft.WindowsTerminalCanary_8wekyb3d8bbwe\wt.exe"),
            (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\wt.exe"),
            (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\Microsoft.WindowsTerminal_8wekyb3d8bbwe\wt.exe"),
            (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\wt.exe"),
            (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\wtd.exe")
        )
        foreach ($candidate in $aliasCandidates) {
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
                return $candidate
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($env:WT_SESSION)) {
            return "wt.exe"
        }

        return $null
    }

    function Test-UacCancelled ($errorRecord) {
        if (-not $errorRecord) { return $false }
        $currEx = $errorRecord.Exception
        while ($currEx) {
            if ($currEx -is [System.ComponentModel.Win32Exception] -and $currEx.NativeErrorCode -eq 1223) {
                return $true
            }
            if ($currEx.Message -match "canceled by the user|cancelled by the user") {
                return $true
            }
            $currEx = $currEx.InnerException
        }
        return $false
    }

    $wtExe = Get-WindowsTerminalPath
    $elevationSuccess = $false

    if ($isInsideWT -or $wtExe) {
        $targetWt = if ($wtExe) { $wtExe } else { "wt.exe" }

        $safeWorkDir = $workDir.TrimEnd('\')
        if ($safeWorkDir -match '^[a-zA-Z]:$') {
            $safeWorkDir += '\\'
        }

        $wtPsArgs = $psArgs -replace '(?<!\\);', '\;'
        $wtArgs = "-w new -d `"$safeWorkDir`" $psExe $wtPsArgs"

        try {
            Start-Process -FilePath $targetWt -ArgumentList $wtArgs -Verb RunAs -ErrorAction Stop
            $elevationSuccess = $true
            Write-Host "`n[OK] $([char]0x0110)$([char]0x00E3) tri$([char]0x1EC7)u h$([char]0x1ED3)i App-Driver trong c$([char]0x1EED)a s$([char]0x1ED5) ri$([char]0x00EA)ng." -ForegroundColor Green
            Write-Host "[*] C$([char]0x1EED)a s$([char]0x1ED5) PowerShell n$([char]0x00E0)y v$([char]0x1EAB)n m$([char]0x1EDF) $([char]0x0111)$([char]0x1EC3) b$([char]0x1EA1)n ti$([char]0x1EBF)p t$([char]0x1EE5)c nh$([char]0x1EAD)p l$([char]0x1EC7)nh.`n" -ForegroundColor DarkGray
            return
        } catch {
            if (Test-UacCancelled $_) {
                Write-Host "`n[!] B$([char]0x1EA1)n $([char]0x0111)$([char]0x00E3) t$([char]0x1EEB) ch$([char]0x1ED1)i c$([char]0x1EA5)p quy$([char]0x1EC1)n Administrator (UAC)." -ForegroundColor Yellow
                Write-Host "[*] App-Driver c$([char]0x1EA7)n quy$([char]0x1EC1)n Administrator $([char]0x0111)$([char]0x1EC3) th$([char]0x1EF1)c hi$([char]0x1EC7)n s$([char]0x1EED)a l$([char]0x1ED7)i h$([char]0x1EC7) th$([char]0x1ED1)ng v$([char]0x00E0) qu$([char]0x1EA3)n l$([char]0x00FD) Driver.`n" -ForegroundColor DarkGray
                return
            }
        }
    }

    if (-not $elevationSuccess) {
        try {
            $startParams = @{
                FilePath     = $psExe
                ArgumentList = $psArgs
                Verb         = "RunAs"
                ErrorAction  = "Stop"
            }
            if (Test-Path -LiteralPath $workDir) {
                $startParams["WorkingDirectory"] = $workDir
            }
            Start-Process @startParams
            $elevationSuccess = $true
            Write-Host "`n[OK] $([char]0x0110)$([char]0x00E3) tri$([char]0x1EC7)u h$([char]0x1ED3)i App-Driver trong c$([char]0x1EED)a s$([char]0x1ED5) ri$([char]0x00EA)ng." -ForegroundColor Green
            Write-Host "[*] C$([char]0x1EED)a s$([char]0x1ED5) PowerShell n$([char]0x00E0)y v$([char]0x1EAB)n m$([char]0x1EDF) $([char]0x0111)$([char]0x1EC3) b$([char]0x1EA1)n ti$([char]0x1EBF)p t$([char]0x1EE5)c nh$([char]0x1EAD)p l$([char]0x1EC7)nh.`n" -ForegroundColor DarkGray
            return
        } catch {
            if (Test-UacCancelled $_) {
                Write-Host "`n[!] B$([char]0x1EA1)n $([char]0x0111)$([char]0x00E3) t$([char]0x1EEB) ch$([char]0x1ED1)i c$([char]0x1EA5)p quy$([char]0x1EC1)n Administrator (UAC)." -ForegroundColor Yellow
                Write-Host "[*] App-Driver c$([char]0x1EA7)n quy$([char]0x1EC1)n Administrator $([char]0x0111)$([char]0x1EC3) th$([char]0x1EF1)c hi$([char]0x1EC7)n s$([char]0x1EED)a l$([char]0x1ED7)i h$([char]0x1EC7) th$([char]0x1ED1)ng v$([char]0x00E0) qu$([char]0x1EA3)n l$([char]0x00FD) Driver.`n" -ForegroundColor DarkGray
                return
            }

            if ($psExe -ne "powershell.exe" -and (Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue)) {
                try {
                    $fallbackParams = @{
                        FilePath     = "powershell.exe"
                        ArgumentList = $psArgs
                        Verb         = "RunAs"
                        ErrorAction  = "Stop"
                    }
                    if (Test-Path -LiteralPath $workDir) {
                        $fallbackParams["WorkingDirectory"] = $workDir
                    }
                    Start-Process @fallbackParams
                    $elevationSuccess = $true
                    Write-Host "`n[OK] $([char]0x0110)$([char]0x00E3) tri$([char]0x1EC7)u h$([char]0x1ED3)i App-Driver trong c$([char]0x1EED)a s$([char]0x1ED5) ri$([char]0x00EA)ng." -ForegroundColor Green
                    Write-Host "[*] C$([char]0x1EED)a s$([char]0x1ED5) PowerShell n$([char]0x00E0)y v$([char]0x1EAB)n m$([char]0x1EDF) $([char]0x0111)$([char]0x1EC3) b$([char]0x1EA1)n ti$([char]0x1EBF)p t$([char]0x1EE5)c nh$([char]0x1EAD)p l$([char]0x1EC7)nh.`n" -ForegroundColor DarkGray
                    return
                } catch {
                    if (Test-UacCancelled $_) {
                        Write-Host "`n[!] B$([char]0x1EA1)n $([char]0x0111)$([char]0x00E3) t$([char]0x1EEB) ch$([char]0x1ED1)i c$([char]0x1EA5)p quy$([char]0x1EC1)n Administrator (UAC)." -ForegroundColor Yellow
                        Write-Host "[*] App-Driver c$([char]0x1EA7)n quy$([char]0x1EC1)n Administrator $([char]0x0111)$([char]0x1EC3) th$([char]0x1EF1)c hi$([char]0x1EC7)n s$([char]0x1EED)a l$([char]0x1ED7)i h$([char]0x1EC7) th$([char]0x1ED1)ng v$([char]0x00E0) qu$([char]0x1EA3)n l$([char]0x00FD) Driver.`n" -ForegroundColor DarkGray
                        return
                    }
                    Write-Host "`n[x] L$([char]0x1ED7)i kh$([char]0x1EDF)i ch$([char]0x1EA1)y quy$([char]0x1EC1)n Administrator: $($_.Exception.Message)" -ForegroundColor Red
                    return
                }
            } else {
                Write-Host "`n[x] L$([char]0x1ED7)i kh$([char]0x1EDF)i ch$([char]0x1EA1)y quy$([char]0x1EC1)n Administrator: $($_.Exception.Message)" -ForegroundColor Red
                return
            }
        }
    }
    return
}

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
}

if ($Host -and $Host.UI -and $Host.UI.RawUI) {
    try {
        $Host.UI.RawUI.WindowTitle = "App-Driver - Terminal Console"
    } catch {
    }
}

try { Clear-Host } catch {}
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "   ___                ____       _                " -ForegroundColor Cyan
Write-Host "  / _ | ___  ___ ____/ __ \____ (_)  _____ ____   " -ForegroundColor Cyan
Write-Host " / __ |/ _ \/ _ \___/ /_/ / __/ / | / / -_) __/   " -ForegroundColor Cyan
Write-Host "/_/ |_/ .__/ .__/  /_____/_/ /_/|___/\__/_/      " -ForegroundColor Cyan
Write-Host "     /_/  /_/      Windows Software & Driver Suite" -ForegroundColor DarkCyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "[!] Vui lòng KHÔNG đóng cửa sổ Terminal này khi đang sử dụng giao diện App-Driver.`n" -ForegroundColor Yellow

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
