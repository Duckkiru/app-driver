$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

$isInsideWT = -not [string]::IsNullOrWhiteSpace($env:WT_SESSION)
$script:IsInsideWindowsTerminal = $isInsideWT

if (-not $isAdmin) {
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

    if ($isWebSource) {
        $psArgs = "-NoProfile -Sta -ExecutionPolicy Bypass -Command `"Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/Duckkiru/app-driver/main/App-Driver.ps1' | Invoke-Expression`""
    } else {
        $scriptTarget = (Resolve-Path -LiteralPath $PSCommandPath).Path
        $psArgs = "-NoProfile -Sta -ExecutionPolicy Bypass -File `"$scriptTarget`""
        if ($args -and $args.Count -gt 0) {
            $forwarded = foreach ($arg in $args) {
                $argStr = "$arg"
                if ($argStr -match '[\s"]') {
                    '`"' + ($argStr -replace '"', '\"') + '`"'
                } else {
                    $argStr
                }
            }
            $psArgs += " " + ($forwarded -join " ")
        }
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
        $wtArgs = "-d `"$safeWorkDir`" $psExe $wtPsArgs"

        try {
            Start-Process -FilePath $targetWt -ArgumentList $wtArgs -Verb RunAs -ErrorAction Stop
            $elevationSuccess = $true
            [Environment]::Exit(0)
        } catch {
            if (Test-UacCancelled $_) {
                Write-Host "`n[!] Bạn đã từ chối cấp quyền Administrator (UAC)." -ForegroundColor Yellow
                Write-Host "[*] App-Driver cần quyền Administrator để thực hiện sửa lỗi hệ thống và quản lý Driver.`n" -ForegroundColor DarkGray
                exit
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
            [Environment]::Exit(0)
        } catch {
            if (Test-UacCancelled $_) {
                Write-Host "`n[!] Bạn đã từ chối cấp quyền Administrator (UAC)." -ForegroundColor Yellow
                Write-Host "[*] App-Driver cần quyền Administrator để thực hiện sửa lỗi hệ thống và quản lý Driver.`n" -ForegroundColor DarkGray
                exit
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
                    [Environment]::Exit(0)
                } catch {
                    if (Test-UacCancelled $_) {
                        Write-Host "`n[!] Bạn đã từ chối cấp quyền Administrator (UAC)." -ForegroundColor Yellow
                        Write-Host "[*] App-Driver cần quyền Administrator để thực hiện sửa lỗi hệ thống và quản lý Driver.`n" -ForegroundColor DarkGray
                        exit
                    }
                    Write-Host "`n[x] Lỗi khởi chạy quyền Administrator: $($_.Exception.Message)" -ForegroundColor Red
                    exit
                }
            } else {
                Write-Host "`n[x] Lỗi khởi chạy quyền Administrator: $($_.Exception.Message)" -ForegroundColor Red
                exit
            }
        }
    }
    exit
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
