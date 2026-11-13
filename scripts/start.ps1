# ==============================================================================
#                     APP-DRIVER — WINDOWS SOFTWARE & DRIVER SUITE
#       Modular Windows Package Manager & System Maintenance Architecture
# ==============================================================================

# 1. TỰ ĐỘNG CHUYỂN SANG QUYỀN ADMINISTRATOR (SELF-ELEVATION & WINDOWS TERMINAL SUPPORT)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

# Nhận diện phiên bản và môi trường Windows Terminal
$isInsideWT = -not [string]::IsNullOrWhiteSpace($env:WT_SESSION)
$script:IsInsideWindowsTerminal = $isInsideWT

if (-not $isAdmin) {
    # Chọn runtime PowerShell phù hợp nhất (PowerShell 7 Core nếu có, fallback Windows PowerShell 5.1)
    $psExe = if ($PSVersionTable.PSEdition -eq 'Core' -or (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue)) {
        "pwsh.exe"
    } else {
        "powershell.exe"
    }

    # Xác định thư mục làm việc và đường dẫn script
    $isWebSource = [string]::IsNullOrWhiteSpace($PSCommandPath) -or -not (Test-Path -LiteralPath $PSCommandPath)
    $workDir = if (-not $isWebSource) {
        Split-Path -Parent (Resolve-Path -LiteralPath $PSCommandPath).Path
    } else {
        if ($PWD -and $PWD.Path -and (Test-Path -LiteralPath $PWD.Path)) { $PWD.Path } else { [Environment]::GetFolderPath('UserProfile') }
    }

    # Xây dựng đối số thực thi cho PowerShell (Bao gồm cờ -Sta để đảm bảo môi trường STA cho WPF)
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

    # Hàm tìm kiếm thực thi Windows Terminal (Hỗ trợ WT Stable, WT Preview, WT Canary)
    function Get-WindowsTerminalPath {
        # 1. Tìm trong PATH hệ thống (wt.exe hoặc wtd.exe)
        foreach ($bin in @('wt.exe', 'wtd.exe', 'wt')) {
            $cmd = Get-Command -Name $bin -CommandType Application -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
                return $cmd.Source
            }
        }

        # 2. Tìm trong AppExecutionAliases (Canary, Preview, Stable)
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

        # 3. Nếu đang chạy trong session của Windows Terminal nhưng không tìm thấy alias
        if (-not [string]::IsNullOrWhiteSpace($env:WT_SESSION)) {
            return "wt.exe"
        }

        return $null
    }

    # Hàm kiểm tra xem người dùng có chủ động từ chối UAC hay không
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

    # Tầng 1: Tự nâng quyền qua Windows Terminal (nếu đang ở trong WT hoặc tìm thấy wt.exe)
    if ($isInsideWT -or $wtExe) {
        $targetWt = if ($wtExe) { $wtExe } else { "wt.exe" }

        # Chuẩn hóa đường dẫn: Tránh ký tự '\' cuối làm escape dấu nháy kép trong Win32 CommandLineToArgvW
        $safeWorkDir = $workDir.TrimEnd('\')
        if ($safeWorkDir -match '^[a-zA-Z]:$') {
            $safeWorkDir += '\\'
        }

        # Trong cú pháp dòng lệnh của wt.exe, dấu chấm phẩy ';' là ký tự phân tách sub-command (tab/pane mới)
        # Cần escape các dấu ';' thành '\;' để không bị chia nhỏ dòng lệnh của PowerShell
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
            # Nếu thất bại vì lỗi khởi chạy wt.exe (không phải từ chối UAC), tiếp tục fallback xuống tầng dưới
        }
    }

    # Tầng 2: Fallback nâng quyền trực tiếp bằng PowerShell runtime đã chọn ($psExe)
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

            # Tầng 3: Fallback khẩn cấp sang powershell.exe mặc định nếu pwsh.exe gặp sự cố
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

# 2. CẤU HÌNH MÔI TRƯỜNG & NẠP THƯ VIỆN WPF & WINFORMS
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
    # Không làm gián đoạn nếu host không hỗ trợ thay đổi console encoding
}

if ($Host -and $Host.UI -and $Host.UI.RawUI) {
    try {
        $Host.UI.RawUI.WindowTitle = "App-Driver - Terminal Console"
    } catch {
        # Bỏ qua nếu host không hỗ trợ đổi tiêu đề
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