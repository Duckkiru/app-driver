# ==============================================================================
#                     DUCK UTIL - CYBER OBSIDIAN SUITE
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
        $psArgs = "-NoProfile -Sta -ExecutionPolicy Bypass -Command `"Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/Duckkiru/app-driver/main/DuckUtil.ps1' | Invoke-Expression`""
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
            exit
        } catch {
            if (Test-UacCancelled $_) {
                Write-Host "`n[!] Bạn đã từ chối cấp quyền Administrator (UAC)." -ForegroundColor Yellow
                Write-Host "[*] DuckUtil cần quyền Administrator để thực hiện sửa lỗi hệ thống và quản lý Driver.`n" -ForegroundColor DarkGray
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
            exit
        } catch {
            if (Test-UacCancelled $_) {
                Write-Host "`n[!] Bạn đã từ chối cấp quyền Administrator (UAC)." -ForegroundColor Yellow
                Write-Host "[*] DuckUtil cần quyền Administrator để thực hiện sửa lỗi hệ thống và quản lý Driver.`n" -ForegroundColor DarkGray
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
                    exit
                } catch {
                    if (Test-UacCancelled $_) {
                        Write-Host "`n[!] Bạn đã từ chối cấp quyền Administrator (UAC)." -ForegroundColor Yellow
                        Write-Host "[*] DuckUtil cần quyền Administrator để thực hiện sửa lỗi hệ thống và quản lý Driver.`n" -ForegroundColor DarkGray
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
        $Host.UI.RawUI.WindowTitle = "DuckUtil - Cyber Obsidian Suite"
    } catch {
        # Bỏ qua nếu host không hỗ trợ đổi tiêu đề
    }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# 3. KHO DỮ LIỆU ỨNG DỤNG (NHẬN TỪ CONFIG/APPS.JSON)
$appsRawJson = @'
[
    {
        "ID": "Google.Chrome",
        "Name": "Google Chrome",
        "Domain": "google.com/chrome",
        "Aliases": [
            "Google Chrome",
            "Google.Chrome"
        ],
        "Category": "Web Browsers",
        "IDn": 1,
        "Url": "https://www.google.com/chrome/",
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/google-chrome.png"
    },
    {
        "ID": "Mozilla.Firefox",
        "Name": "Mozilla Firefox",
        "Domain": "firefox.com",
        "Aliases": [
            "Mozilla Firefox",
            "Firefox",
            "Mozilla.Firefox"
        ],
        "Category": "Web Browsers",
        "IDn": 2,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/firefox.png"
    },
    {
        "ID": "Brave.Brave",
        "Name": "Brave Browser",
        "Domain": "brave.com",
        "Aliases": [
            "Brave",
            "BraveSoftware",
            "Brave.Brave",
            "Brave Browser"
        ],
        "Category": "Web Browsers",
        "IDn": 3,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/brave.png"
    },
    {
        "ID": "LibreWolf.LibreWolf",
        "Name": "LibreWolf",
        "Domain": "librewolf.net",
        "Aliases": [
            "LibreWolf",
            "LibreWolf.LibreWolf"
        ],
        "Category": "Web Browsers",
        "IDn": 4,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/librewolf.png"
    },
    {
        "ID": "Vivaldi.Vivaldi",
        "Name": "Vivaldi",
        "Domain": "vivaldi.com",
        "Aliases": [
            "Vivaldi",
            "Vivaldi.Vivaldi"
        ],
        "Category": "Web Browsers",
        "IDn": 5,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/vivaldi.png"
    },
    {
        "ID": "TorProject.TorBrowser",
        "Name": "Tor Browser",
        "Domain": "torproject.org",
        "Aliases": [
            "Tor Browser",
            "TorProject.TorBrowser"
        ],
        "Category": "Web Browsers",
        "IDn": 6
    },
    {
        "ID": "Opera.OperaGX",
        "Name": "Opera GX",
        "Domain": "opera.com/gx",
        "Aliases": [
            "Opera GX",
            "OperaGX",
            "Opera.OperaGX"
        ],
        "Category": "Web Browsers",
        "IDn": 7,
        "Url": "https://www.opera.com/gx",
        "IconUrl": "https://img.icons8.com/fluency/96/opera-gx.png"
    },
    {
        "ID": "Discord.Discord",
        "Name": "Discord",
        "Domain": "discord.com",
        "Aliases": [
            "Discord",
            "Discord.Discord"
        ],
        "Category": "Communication",
        "IDn": 8,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/discord.png"
    },
    {
        "ID": "Telegram.TelegramDesktop",
        "Name": "Telegram",
        "Domain": "telegram.org",
        "Aliases": [
            "Telegram Desktop",
            "Telegram",
            "TelegramDesktop",
            "Telegram.TelegramDesktop"
        ],
        "Category": "Communication",
        "IDn": 9,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/telegram.png"
    },
    {
        "ID": "OpenWhisperSystems.Signal",
        "Name": "Signal",
        "Domain": "signal.org",
        "Aliases": [
            "Signal",
            "OpenWhisperSystems.Signal"
        ],
        "Category": "Communication",
        "IDn": 10,
        "IconUrl": "https://img.icons8.com/fluency/96/signal-app.png"
    },
    {
        "ID": "VNGCorp.Zalo",
        "Name": "Zalo",
        "Domain": "zalo.me",
        "Aliases": [
            "Zalo",
            "VNGCorp.Zalo"
        ],
        "Category": "Communication",
        "IDn": 11,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/zalo.png"
    },
    {
        "ID": "Zoom.Zoom",
        "Name": "Zoom Workplace",
        "Domain": "zoom.us",
        "Aliases": [
            "Zoom Workplace",
            "Zoom",
            "Zoom.Zoom"
        ],
        "Category": "Communication",
        "IDn": 12,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/zoom.png"
    },
    {
        "ID": "SlackTechnologies.Slack",
        "Name": "Slack",
        "Domain": "slack.com",
        "Aliases": [
            "Slack",
            "SlackTechnologies.Slack"
        ],
        "Category": "Communication",
        "IDn": 13,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/slack.png"
    },
    {
        "ID": "9NKSQGP7F2NH",
        "Name": "WhatsApp",
        "Domain": "whatsapp.com",
        "Aliases": [
            "WhatsApp",
            "WhatsApp.WhatsApp",
            "9NKSQGP7F2NH"
        ],
        "Category": "Communication",
        "IDn": 14,
        "Source": "msstore",
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/whatsapp.png"
    },
    {
        "ID": "Microsoft.Teams",
        "Name": "Microsoft Teams",
        "Domain": "teams.microsoft.com",
        "Aliases": [
            "Microsoft Teams",
            "Microsoft Teams (work or school)",
            "MSTeams",
            "Microsoft.Teams"
        ],
        "Category": "Communication",
        "IDn": 15,
        "Url": "https://www.microsoft.com/en-us/microsoft-teams/download-app",
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/microsoft-teams.png"
    },
    {
        "ID": "RustDesk.RustDesk",
        "Name": "RustDesk",
        "Domain": "rustdesk.com",
        "Aliases": [
            "RustDesk",
            "RustDesk.RustDesk"
        ],
        "Category": "Remote Desktop",
        "IDn": 16,
        "GitHubRepo": "rustdesk/rustdesk",
        "AssetRegex": "x86_64\\.msi$",
        "FallbackUrl": "https://github.com/rustdesk/rustdesk/releases/latest",
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/rustdesk.png"
    },
    {
        "ID": "AnyDesk.AnyDesk",
        "Name": "AnyDesk",
        "Domain": "anydesk.com",
        "Aliases": [
            "AnyDesk",
            "AnyDesk.AnyDesk"
        ],
        "Category": "Remote Desktop",
        "IDn": 17,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/anydesk.png"
    },
    {
        "ID": "DucFabulous.UltraViewer",
        "Name": "UltraViewer",
        "Domain": "ultraviewer.net",
        "Aliases": [
            "UltraViewer",
            "DucFabulous.UltraViewer"
        ],
        "Category": "Remote Desktop",
        "IDn": 18
    },
    {
        "ID": "TeamViewer.TeamViewer",
        "Name": "TeamViewer",
        "Domain": "teamviewer.com",
        "Aliases": [
            "TeamViewer",
            "TeamViewer.TeamViewer"
        ],
        "Category": "Remote Desktop",
        "IDn": 19,
        "IconUrl": "https://www.google.com/s2/favicons?domain=teamviewer.com&sz=128"
    },
    {
        "ID": "Microsoft.VisualStudioCode",
        "Name": "VS Code",
        "Domain": "code.visualstudio.com",
        "Aliases": [
            "Visual Studio Code",
            "VS Code",
            "VSCode",
            "Microsoft.VisualStudioCode"
        ],
        "Category": "Development",
        "IDn": 20,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/vscode.png"
    },
    {
        "ID": "Git.Git",
        "Name": "Git",
        "Domain": "git-scm.com",
        "Aliases": [
            "Git",
            "Git.Git"
        ],
        "Category": "Development",
        "IDn": 21,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/git.png"
    },
    {
        "ID": "Microsoft.WindowsTerminal",
        "Name": "Windows Terminal",
        "Domain": "microsoft.com",
        "Aliases": [
            "Windows Terminal",
            "Bảng điều khiển Windows",
            "Microsoft.WindowsTerminal"
        ],
        "IconUrl": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/windows-terminal.png",
        "Category": "Development",
        "IDn": 22,
        "Url": "https://learn.microsoft.com/en-us/windows/terminal/"
    },
    {
        "ID": "Microsoft.WindowsTerminal.Preview",
        "Name": "Windows Terminal Preview",
        "Domain": "microsoft.com",
        "Aliases": [
            "Windows Terminal Preview",
            "Microsoft.WindowsTerminal.Preview"
        ],
        "IconUrl": "https://raw.githubusercontent.com/microsoft/terminal/main/res/terminal/images-Pre/Square44x44Logo.targetsize-64.png",
        "Category": "Development",
        "IDn": 23,
        "Url": "https://learn.microsoft.com/en-us/windows/terminal/"
    },
    {
        "ID": "Python.Python.3.13",
        "Name": "Python 3.13",
        "Domain": "python.org",
        "Aliases": [
            "Python 3.13",
            "Python.Python.3.13"
        ],
        "Category": "Development",
        "IDn": 24,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/python.png"
    },
    {
        "ID": "OpenJS.NodeJS.LTS",
        "Name": "Node.js LTS",
        "Domain": "nodejs.org",
        "Aliases": [
            "Node.js",
            "NodeJS",
            "OpenJS.NodeJS.LTS"
        ],
        "Category": "Development",
        "IDn": 25,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/nodejs.png"
    },
    {
        "ID": "Docker.DockerDesktop",
        "Name": "Docker Desktop",
        "Domain": "docker.com",
        "Aliases": [
            "Docker Desktop",
            "Docker",
            "Docker.DockerDesktop"
        ],
        "Category": "Development",
        "IDn": 26,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/docker.png"
    },
    {
        "ID": "Notepad++.Notepad++",
        "Name": "Notepad++",
        "Domain": "notepad-plus-plus.org",
        "Aliases": [
            "Notepad++",
            "NotepadPlusPlus",
            "Notepad++.Notepad++"
        ],
        "Category": "Development",
        "IDn": 27,
        "IconUrl": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/notepad-plus-plus.png"
    },
    {
        "ID": "Postman.Postman",
        "Name": "Postman",
        "Domain": "postman.com",
        "Aliases": [
            "Postman",
            "Postman.Postman"
        ],
        "Category": "Development",
        "IDn": 28,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/postman.png"
    },
    {
        "ID": "DBeaver.DBeaver.Community",
        "Name": "DBeaver CE",
        "Domain": "dbeaver.io",
        "Aliases": [
            "DBeaver",
            "DBeaver CE",
            "DBeaver Community",
            "DBeaver.DBeaver.Community"
        ],
        "Category": "Development",
        "IDn": 29,
        "IconUrl": "https://raw.githubusercontent.com/dbeaver/dbeaver/devel/plugins/org.jkiss.dbeaver.ui.app.standalone/icons/dbeaver256.png"
    },
    {
        "ID": "GoLang.Go",
        "Name": "Go",
        "Domain": "go.dev",
        "Aliases": [
            "Go Programming Language",
            "GoLang",
            "GoLang.Go"
        ],
        "Category": "Development",
        "IDn": 30,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/go.png"
    },
    {
        "ID": "Rustlang.Rustup",
        "Name": "Rust (rustup)",
        "Domain": "rust-lang.org",
        "Aliases": [
            "Rustup",
            "Rustup: the Rust toolchain installer",
            "Rustlang.Rustup"
        ],
        "Category": "Development",
        "IDn": 31,
        "IconUrl": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/rust-light.png"
    },
    {
        "ID": "Microsoft.DotNet.Framework.Runtime",
        "Name": ".NET Framework 4.8.1",
        "Domain": "dotnet.microsoft.com",
        "Aliases": [
            "Microsoft .NET Framework 4.8.1 Runtime",
            "Microsoft .NET Framework Runtime",
            "Microsoft.DotNet.Framework.Runtime"
        ],
        "Category": ".NET Runtimes",
        "IDn": 32,
        "Url": "https://dotnet.microsoft.com/en-us/download/dotnet",
        "IconUrl": "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png"
    },
    {
        "ID": "Microsoft.DotNet.DesktopRuntime.3_1",
        "Name": ".NET Desktop Runtime 3.1",
        "Domain": "dotnet.microsoft.com",
        "Aliases": [
            "Microsoft .NET Windows Desktop Runtime 3.1",
            "DesktopRuntime.3_1",
            "Microsoft.DotNet.DesktopRuntime.3_1"
        ],
        "Category": ".NET Runtimes",
        "IDn": 33,
        "Url": "https://dotnet.microsoft.com/en-us/download/dotnet",
        "IconUrl": "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png"
    },
    {
        "ID": "Microsoft.DotNet.DesktopRuntime.5",
        "Name": ".NET Desktop Runtime 5.0",
        "Domain": "dotnet.microsoft.com",
        "Aliases": [
            "Microsoft .NET Windows Desktop Runtime 5.0",
            "DesktopRuntime.5",
            "Microsoft.DotNet.DesktopRuntime.5"
        ],
        "Category": ".NET Runtimes",
        "IDn": 34,
        "Url": "https://dotnet.microsoft.com/en-us/download/dotnet",
        "IconUrl": "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png"
    },
    {
        "ID": "Microsoft.DotNet.DesktopRuntime.6",
        "Name": ".NET Desktop Runtime 6 (LTS)",
        "Domain": "dotnet.microsoft.com",
        "Aliases": [
            "Microsoft .NET Windows Desktop Runtime 6.0",
            "DesktopRuntime.6",
            "Microsoft.DotNet.DesktopRuntime.6"
        ],
        "Category": ".NET Runtimes",
        "IDn": 35,
        "Url": "https://dotnet.microsoft.com/en-us/download/dotnet",
        "IconUrl": "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png"
    },
    {
        "ID": "Microsoft.DotNet.DesktopRuntime.6.x86",
        "Name": ".NET Desktop Runtime 6 (x86)",
        "Domain": "dotnet.microsoft.com",
        "Aliases": [
            "Microsoft .NET Windows Desktop Runtime 6.0 (x86)",
            "Microsoft.DotNet.DesktopRuntime.6.x86"
        ],
        "Category": ".NET Runtimes",
        "IDn": 36,
        "Url": "https://dotnet.microsoft.com/en-us/download/dotnet",
        "IconUrl": "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png"
    },
    {
        "ID": "Microsoft.DotNet.DesktopRuntime.7",
        "Name": ".NET Desktop Runtime 7",
        "Domain": "dotnet.microsoft.com",
        "Aliases": [
            "Microsoft .NET Windows Desktop Runtime 7.0",
            "DesktopRuntime.7",
            "Microsoft.DotNet.DesktopRuntime.7"
        ],
        "Category": ".NET Runtimes",
        "IDn": 37,
        "Url": "https://dotnet.microsoft.com/en-us/download/dotnet",
        "IconUrl": "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png"
    },
    {
        "ID": "Microsoft.DotNet.DesktopRuntime.7.x86",
        "Name": ".NET Desktop Runtime 7 (x86)",
        "Domain": "dotnet.microsoft.com",
        "Aliases": [
            "Microsoft .NET Windows Desktop Runtime 7.0 (x86)",
            "Microsoft.DotNet.DesktopRuntime.7.x86"
        ],
        "Category": ".NET Runtimes",
        "IDn": 38,
        "Url": "https://dotnet.microsoft.com/en-us/download/dotnet",
        "IconUrl": "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png"
    },
    {
        "ID": "Microsoft.DotNet.DesktopRuntime.8",
        "Name": ".NET Desktop Runtime 8 (LTS)",
        "Domain": "dotnet.microsoft.com",
        "Aliases": [
            "Microsoft .NET Windows Desktop Runtime 8.0",
            "DesktopRuntime.8",
            "Microsoft.DotNet.DesktopRuntime.8"
        ],
        "Category": ".NET Runtimes",
        "IDn": 39,
        "Url": "https://dotnet.microsoft.com/en-us/download/dotnet",
        "IconUrl": "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png"
    },
    {
        "ID": "Microsoft.DotNet.DesktopRuntime.8.x86",
        "Name": ".NET Desktop Runtime 8 (x86)",
        "Domain": "dotnet.microsoft.com",
        "Aliases": [
            "Microsoft .NET Windows Desktop Runtime 8.0 (x86)",
            "Microsoft.DotNet.DesktopRuntime.8.x86"
        ],
        "Category": ".NET Runtimes",
        "IDn": 40,
        "Url": "https://dotnet.microsoft.com/en-us/download/dotnet",
        "IconUrl": "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png"
    },
    {
        "ID": "Microsoft.DotNet.DesktopRuntime.9",
        "Name": ".NET Desktop Runtime 9",
        "Domain": "dotnet.microsoft.com",
        "Aliases": [
            "Microsoft .NET Windows Desktop Runtime 9.0",
            "DesktopRuntime.9",
            "Microsoft.DotNet.DesktopRuntime.9"
        ],
        "Category": ".NET Runtimes",
        "IDn": 41,
        "Url": "https://dotnet.microsoft.com/en-us/download/dotnet",
        "IconUrl": "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png"
    },
    {
        "ID": "Microsoft.DotNet.DesktopRuntime.10",
        "Name": ".NET Desktop Runtime 10",
        "Domain": "dotnet.microsoft.com",
        "Aliases": [
            "Microsoft .NET Windows Desktop Runtime 10.0",
            "DesktopRuntime.10",
            "Microsoft.DotNet.DesktopRuntime.10"
        ],
        "Category": ".NET Runtimes",
        "IDn": 42,
        "Url": "https://dotnet.microsoft.com/en-us/download/dotnet",
        "IconUrl": "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png"
    },
    {
        "ID": "Microsoft.DotNet.DesktopRuntime.Preview",
        "Name": ".NET Desktop Runtime 11 Preview",
        "Domain": "dotnet.microsoft.com",
        "Aliases": [
            "Microsoft .NET Windows Desktop Runtime 11.0 Preview",
            "Microsoft.DotNet.DesktopRuntime.Preview"
        ],
        "Category": ".NET Runtimes",
        "IDn": 43,
        "Url": "https://dotnet.microsoft.com/en-us/download/dotnet",
        "IconUrl": "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.8.JRE",
        "Name": "Java 8 JRE (LTS)",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JRE with Hotspot 8",
            "Temurin 8 JRE",
            "EclipseAdoptium.Temurin.8.JRE"
        ],
        "Category": "Java Runtimes",
        "IDn": 44,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.8.JDK",
        "Name": "Java 8 JDK (LTS)",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JDK with Hotspot 8",
            "Temurin 8",
            "OpenJDK 8",
            "EclipseAdoptium.Temurin.8.JDK"
        ],
        "Category": "Java Runtimes",
        "IDn": 45,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.11.JRE",
        "Name": "Java 11 JRE (LTS)",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JRE with Hotspot 11",
            "Temurin 11 JRE",
            "EclipseAdoptium.Temurin.11.JRE"
        ],
        "Category": "Java Runtimes",
        "IDn": 46,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.11.JDK",
        "Name": "Java 11 JDK (LTS)",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JDK with Hotspot 11",
            "Temurin 11",
            "OpenJDK 11",
            "EclipseAdoptium.Temurin.11.JDK"
        ],
        "Category": "Java Runtimes",
        "IDn": 47,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.16.JDK",
        "Name": "Java 16 JDK",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JDK with Hotspot 16",
            "Temurin 16",
            "EclipseAdoptium.Temurin.16.JDK"
        ],
        "Category": "Java Runtimes",
        "IDn": 48,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.17.JRE",
        "Name": "Java 17 JRE (LTS)",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JRE with Hotspot 17",
            "Temurin 17 JRE",
            "EclipseAdoptium.Temurin.17.JRE"
        ],
        "Category": "Java Runtimes",
        "IDn": 49,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.17.JDK",
        "Name": "Java 17 JDK (LTS)",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JDK with Hotspot 17",
            "Temurin 17",
            "OpenJDK 17",
            "EclipseAdoptium.Temurin.17.JDK"
        ],
        "Category": "Java Runtimes",
        "IDn": 50,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.18.JDK",
        "Name": "Java 18 JDK",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JDK with Hotspot 18",
            "Temurin 18",
            "EclipseAdoptium.Temurin.18.JDK"
        ],
        "Category": "Java Runtimes",
        "IDn": 51,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.19.JDK",
        "Name": "Java 19 JDK",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JDK with Hotspot 19",
            "Temurin 19",
            "EclipseAdoptium.Temurin.19.JDK"
        ],
        "Category": "Java Runtimes",
        "IDn": 52,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.20.JDK",
        "Name": "Java 20 JDK",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JDK with Hotspot 20",
            "Temurin 20",
            "EclipseAdoptium.Temurin.20.JDK"
        ],
        "Category": "Java Runtimes",
        "IDn": 53,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.21.JRE",
        "Name": "Java 21 JRE (LTS)",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JRE with Hotspot 21",
            "Temurin 21 JRE",
            "EclipseAdoptium.Temurin.21.JRE"
        ],
        "Category": "Java Runtimes",
        "IDn": 54,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.21.JDK",
        "Name": "Java 21 JDK (LTS)",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JDK with Hotspot 21",
            "Temurin 21",
            "OpenJDK 21",
            "EclipseAdoptium.Temurin.21.JDK"
        ],
        "Category": "Java Runtimes",
        "IDn": 55,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.22.JDK",
        "Name": "Java 22 JDK",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JDK with Hotspot 22",
            "Temurin 22",
            "EclipseAdoptium.Temurin.22.JDK"
        ],
        "Category": "Java Runtimes",
        "IDn": 56,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.23.JDK",
        "Name": "Java 23 JDK",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JDK with Hotspot 23",
            "Temurin 23",
            "EclipseAdoptium.Temurin.23.JDK"
        ],
        "Category": "Java Runtimes",
        "IDn": 57,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.24.JDK",
        "Name": "Java 24 JDK",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JDK with Hotspot 24",
            "Temurin 24",
            "EclipseAdoptium.Temurin.24.JDK"
        ],
        "Category": "Java Runtimes",
        "IDn": 58,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "EclipseAdoptium.Temurin.25.JDK",
        "Name": "Java 25 JDK",
        "Domain": "adoptium.net",
        "Aliases": [
            "Eclipse Temurin JDK with Hotspot 25",
            "Temurin 25",
            "EclipseAdoptium.Temurin.25.JDK"
        ],
        "Category": "Java Runtimes",
        "IDn": 59,
        "Url": "https://adoptium.net/temurin/releases/",
        "IconUrl": "https://img.icons8.com/ios-filled/96/FFA726/java-coffee-cup-logo.png"
    },
    {
        "ID": "Microsoft.VCRedist.2005.x64",
        "Name": "VC++ 2005 (x64)",
        "Domain": "visualstudio.microsoft.com",
        "Aliases": [
            "Microsoft Visual C++ 2005 Redistributable (x64)",
            "Microsoft Visual C++ 2005 Redistributable - x64",
            "Microsoft.VCRedist.2005.x64"
        ],
        "Category": "C++ & System Runtimes",
        "IDn": 60,
        "Url": "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
        "IconUrl": "https://img.icons8.com/fluency/96/visual-studio.png"
    },
    {
        "ID": "Microsoft.VCRedist.2005.x86",
        "Name": "VC++ 2005 (x86)",
        "Domain": "visualstudio.microsoft.com",
        "Aliases": [
            "Microsoft Visual C++ 2005 Redistributable (x86)",
            "Microsoft Visual C++ 2005 Redistributable - x86",
            "Microsoft.VCRedist.2005.x86"
        ],
        "Category": "C++ & System Runtimes",
        "IDn": 61,
        "Url": "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
        "IconUrl": "https://img.icons8.com/fluency/96/visual-studio.png"
    },
    {
        "ID": "Microsoft.VCRedist.2008.x64",
        "Name": "VC++ 2008 (x64)",
        "Domain": "visualstudio.microsoft.com",
        "Aliases": [
            "Microsoft Visual C++ 2008 Redistributable - x64",
            "Microsoft Visual C++ 2008 Redistributable (x64)",
            "Microsoft.VCRedist.2008.x64"
        ],
        "Category": "C++ & System Runtimes",
        "IDn": 62,
        "Url": "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
        "IconUrl": "https://img.icons8.com/fluency/96/visual-studio.png"
    },
    {
        "ID": "Microsoft.VCRedist.2008.x86",
        "Name": "VC++ 2008 (x86)",
        "Domain": "visualstudio.microsoft.com",
        "Aliases": [
            "Microsoft Visual C++ 2008 Redistributable - x86",
            "Microsoft Visual C++ 2008 Redistributable (x86)",
            "Microsoft.VCRedist.2008.x86"
        ],
        "Category": "C++ & System Runtimes",
        "IDn": 63,
        "Url": "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
        "IconUrl": "https://img.icons8.com/fluency/96/visual-studio.png"
    },
    {
        "ID": "Microsoft.VCRedist.2010.x64",
        "Name": "VC++ 2010 (x64)",
        "Domain": "visualstudio.microsoft.com",
        "Aliases": [
            "Microsoft Visual C++ 2010 x64 Redistributable",
            "Microsoft Visual C++ 2010 Redistributable - x64",
            "Microsoft Visual C++ 2010 Redistributable (x64)",
            "Microsoft.VCRedist.2010.x64"
        ],
        "Category": "C++ & System Runtimes",
        "IDn": 64,
        "Url": "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
        "IconUrl": "https://img.icons8.com/fluency/96/visual-studio.png"
    },
    {
        "ID": "Microsoft.VCRedist.2010.x86",
        "Name": "VC++ 2010 (x86)",
        "Domain": "visualstudio.microsoft.com",
        "Aliases": [
            "Microsoft Visual C++ 2010 x86 Redistributable",
            "Microsoft Visual C++ 2010 Redistributable - x86",
            "Microsoft Visual C++ 2010 Redistributable (x86)",
            "Microsoft.VCRedist.2010.x86"
        ],
        "Category": "C++ & System Runtimes",
        "IDn": 65,
        "Url": "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
        "IconUrl": "https://img.icons8.com/fluency/96/visual-studio.png"
    },
    {
        "ID": "Microsoft.VCRedist.2012.x64",
        "Name": "VC++ 2012 (x64)",
        "Domain": "visualstudio.microsoft.com",
        "Aliases": [
            "Microsoft Visual C++ 2012 Redistributable (x64)",
            "Microsoft Visual C++ 2012 Redistributable - x64",
            "Microsoft.VCRedist.2012.x64"
        ],
        "Category": "C++ & System Runtimes",
        "IDn": 66,
        "Url": "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
        "IconUrl": "https://img.icons8.com/fluency/96/visual-studio.png"
    },
    {
        "ID": "Microsoft.VCRedist.2012.x86",
        "Name": "VC++ 2012 (x86)",
        "Domain": "visualstudio.microsoft.com",
        "Aliases": [
            "Microsoft Visual C++ 2012 Redistributable (x86)",
            "Microsoft Visual C++ 2012 Redistributable - x86",
            "Microsoft.VCRedist.2012.x86"
        ],
        "Category": "C++ & System Runtimes",
        "IDn": 67,
        "Url": "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
        "IconUrl": "https://img.icons8.com/fluency/96/visual-studio.png"
    },
    {
        "ID": "Microsoft.VCRedist.2013.x64",
        "Name": "VC++ 2013 (x64)",
        "Domain": "visualstudio.microsoft.com",
        "Aliases": [
            "Microsoft Visual C++ 2013 Redistributable (x64)",
            "Microsoft Visual C++ 2013 Redistributable - x64",
            "Microsoft.VCRedist.2013.x64"
        ],
        "Category": "C++ & System Runtimes",
        "IDn": 68,
        "Url": "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
        "IconUrl": "https://img.icons8.com/fluency/96/visual-studio.png"
    },
    {
        "ID": "Microsoft.VCRedist.2013.x86",
        "Name": "VC++ 2013 (x86)",
        "Domain": "visualstudio.microsoft.com",
        "Aliases": [
            "Microsoft Visual C++ 2013 Redistributable (x86)",
            "Microsoft Visual C++ 2013 Redistributable - x86",
            "Microsoft.VCRedist.2013.x86"
        ],
        "Category": "C++ & System Runtimes",
        "IDn": 69,
        "Url": "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
        "IconUrl": "https://img.icons8.com/fluency/96/visual-studio.png"
    },
    {
        "ID": "Microsoft.VCRedist.2015+.x64",
        "Name": "VC++ 2015-2026 (x64)",
        "Domain": "visualstudio.microsoft.com",
        "Aliases": [
            "Microsoft Visual C++ v14 Redistributable (x64)",
            "Microsoft Visual C++ 2015-2022 Redistributable (x64)",
            "Microsoft.VCRedist.2015+.x64"
        ],
        "Category": "C++ & System Runtimes",
        "IDn": 70,
        "Url": "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
        "IconUrl": "https://img.icons8.com/fluency/96/visual-studio.png"
    },
    {
        "ID": "Microsoft.VCRedist.2015+.x86",
        "Name": "VC++ 2015-2026 (x86)",
        "Domain": "visualstudio.microsoft.com",
        "Aliases": [
            "Microsoft Visual C++ v14 Redistributable (x86)",
            "Microsoft Visual C++ 2015-2022 Redistributable (x86)",
            "Microsoft.VCRedist.2015+.x86"
        ],
        "Category": "C++ & System Runtimes",
        "IDn": 71,
        "Url": "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
        "IconUrl": "https://img.icons8.com/fluency/96/visual-studio.png"
    },
    {
        "ID": "Microsoft.DirectX",
        "Name": "DirectX End-User",
        "Domain": "microsoft.com",
        "Aliases": [
            "DirectX",
            "Microsoft DirectX",
            "DirectX End-User Runtimes",
            "Microsoft.DirectX"
        ],
        "Category": "C++ & System Runtimes",
        "IDn": 72,
        "Url": "https://www.microsoft.com/en-us/download/details.aspx?id=35"
    },
    {
        "ID": "7zip.7zip",
        "Name": "7-Zip",
        "Domain": "7-zip.org",
        "Aliases": [
            "7-Zip",
            "7zip.7zip"
        ],
        "Category": "System Utilities",
        "IDn": 73,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/7zip.png"
    },
    {
        "ID": "RARLab.WinRAR",
        "Name": "WinRAR",
        "Domain": "win-rar.com",
        "Aliases": [
            "WinRAR",
            "RARLab.WinRAR"
        ],
        "Category": "System Utilities",
        "IDn": 74,
        "IconUrl": "https://www.google.com/s2/favicons?domain=win-rar.com&sz=128"
    },
    {
        "ID": "voidtools.Everything",
        "Name": "Everything",
        "Domain": "voidtools.com",
        "Aliases": [
            "Everything",
            "voidtools.Everything"
        ],
        "Category": "System Utilities",
        "IDn": 75
    },
    {
        "ID": "Microsoft.PowerToys",
        "Name": "PowerToys",
        "Domain": "learn.microsoft.com",
        "Aliases": [
            "PowerToys",
            "Microsoft PowerToys",
            "Microsoft.PowerToys"
        ],
        "IconUrl": "https://raw.githubusercontent.com/microsoft/PowerToys/main/src/settings-ui/Settings.UI/Assets/Settings/logo44.png",
        "Category": "System Utilities",
        "IDn": 76,
        "Url": "https://learn.microsoft.com/en-us/windows/powertoys/"
    },
    {
        "ID": "Flow-Launcher.Flow-Launcher",
        "Name": "Flow Launcher",
        "Domain": "flowlauncher.com",
        "Aliases": [
            "Flow Launcher",
            "Flow-Launcher.Flow-Launcher"
        ],
        "Category": "System Utilities",
        "IDn": 77,
        "IconUrl": "https://raw.githubusercontent.com/Flow-Launcher/Flow.Launcher/dev/Flow.Launcher/Images/app.png"
    },
    {
        "ID": "RevoUninstaller.RevoUninstaller",
        "Name": "Revo Uninstaller",
        "Domain": "revouninstaller.com",
        "Aliases": [
            "Revo Uninstaller",
            "Revo Uninstaller Free",
            "RevoUninstaller.RevoUninstaller"
        ],
        "Category": "System Utilities",
        "IDn": 78,
        "Url": "https://www.revouninstaller.com/products/revo-uninstaller-free/"
    },
    {
        "ID": "JAMSoftware.TreeSize.Free",
        "Name": "TreeSize Free",
        "Domain": "jam-software.com",
        "Aliases": [
            "TreeSize Free",
            "JAMSoftware.TreeSize.Free"
        ],
        "Category": "System Utilities",
        "IDn": 79,
        "Url": "https://www.jam-software.com/treesize-free",
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/treesize.png"
    },
    {
        "ID": "BleachBit.BleachBit",
        "Name": "BleachBit",
        "Domain": "bleachbit.org",
        "Aliases": [
            "BleachBit",
            "BleachBit.BleachBit"
        ],
        "Category": "System Utilities",
        "IDn": 80
    },
    {
        "ID": "Guru3D.Afterburner",
        "Name": "MSI Afterburner",
        "Domain": "msi.com",
        "Aliases": [
            "MSI Afterburner",
            "Afterburner",
            "Guru3D.Afterburner"
        ],
        "Category": "Hardware & Monitoring",
        "IDn": 81,
        "Url": "https://www.msi.com/Landing/afterburner/graphics-cards",
        "IconUrl": "https://img.icons8.com/fluency/96/msi-afterburner.png"
    },
    {
        "ID": "Rem0o.FanControl",
        "Name": "FanControl",
        "Domain": "getfancontrol.com",
        "Aliases": [
            "FanControl",
            "Fan Control",
            "Rem0o.FanControl"
        ],
        "Category": "Hardware & Monitoring",
        "IDn": 82
    },
    {
        "ID": "CPUID.CPU-Z",
        "Name": "CPU-Z",
        "Domain": "cpuid.com",
        "Aliases": [
            "CPUID CPU-Z",
            "CPU-Z",
            "CPUID.CPU-Z"
        ],
        "Category": "Hardware & Monitoring",
        "IDn": 83,
        "Url": "https://www.cpuid.com/softwares/cpu-z.html",
        "IconUrl": "https://www.cpuid.com/medias/images/softwares/cpu-z.png"
    },
    {
        "ID": "CPUID.HWMonitor",
        "Name": "HWMonitor",
        "Domain": "cpuid.com",
        "Aliases": [
            "CPUID HWMonitor",
            "HWMonitor",
            "CPUID.HWMonitor"
        ],
        "Category": "Hardware & Monitoring",
        "IDn": 84,
        "Url": "https://www.cpuid.com/softwares/hwmonitor.html",
        "IconUrl": "https://www.cpuid.com/medias/images/softwares/hwmonitor.png"
    },
    {
        "ID": "Bitwarden.Bitwarden",
        "Name": "Bitwarden",
        "Domain": "bitwarden.com",
        "Aliases": [
            "Bitwarden",
            "Bitwarden.Bitwarden"
        ],
        "Category": "Security & Network",
        "IDn": 85,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/bitwarden.png"
    },
    {
        "ID": "KeePassXCTeam.KeePassXC",
        "Name": "KeePassXC",
        "Domain": "keepassxc.org",
        "Aliases": [
            "KeePassXC",
            "KeePassXCTeam.KeePassXC"
        ],
        "Category": "Security & Network",
        "IDn": 86,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/keepassxc.png"
    },
    {
        "ID": "Cryptomator.Cryptomator",
        "Name": "Cryptomator",
        "Domain": "cryptomator.org",
        "Aliases": [
            "Cryptomator",
            "Cryptomator.Cryptomator"
        ],
        "Category": "Security & Network",
        "IDn": 87,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/cryptomator.png"
    },
    {
        "ID": "Proton.ProtonVPN",
        "Name": "Proton VPN",
        "Domain": "protonvpn.com",
        "Aliases": [
            "Proton VPN",
            "ProtonVPN",
            "Proton.ProtonVPN"
        ],
        "Category": "Security & Network",
        "IDn": 88,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/proton-vpn.png"
    },
    {
        "ID": "WiresharkFoundation.Wireshark",
        "Name": "Wireshark",
        "Domain": "wireshark.org",
        "Aliases": [
            "Wireshark",
            "WiresharkFoundation.Wireshark"
        ],
        "Category": "Security & Network",
        "IDn": 89,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/wireshark.png"
    },
    {
        "ID": "VideoLAN.VLC",
        "Name": "VLC media player",
        "Domain": "videolan.org",
        "Aliases": [
            "VLC media player",
            "VLC",
            "VideoLAN.VLC"
        ],
        "Category": "Audio & Video",
        "IDn": 90,
        "Url": "https://www.videolan.org/vlc/",
        "IconUrl": "https://raw.githubusercontent.com/videolan/vlc/master/share/icons/128x128/vlc.png"
    },
    {
        "ID": "OBSProject.OBSStudio",
        "Name": "OBS Studio",
        "Domain": "obsproject.com",
        "Aliases": [
            "OBS Studio",
            "OBS",
            "OBSProject.OBSStudio"
        ],
        "Category": "Audio & Video",
        "IDn": 91,
        "IconUrl": "https://img.icons8.com/fluency/96/obs-studio.png"
    },
    {
        "ID": "Spotify.Spotify",
        "Name": "Spotify",
        "Domain": "spotify.com",
        "Aliases": [
            "Spotify",
            "Spotify.Spotify"
        ],
        "Category": "Audio & Video",
        "IDn": 92,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/spotify.png"
    },
    {
        "ID": "Audacity.Audacity",
        "Name": "Audacity",
        "Domain": "audacityteam.org",
        "Aliases": [
            "Audacity",
            "Audacity.Audacity"
        ],
        "Category": "Audio & Video",
        "IDn": 93,
        "IconUrl": "https://img.icons8.com/fluency/96/audacity.png"
    },
    {
        "ID": "HandBrake.HandBrake",
        "Name": "HandBrake",
        "Domain": "handbrake.fr",
        "Aliases": [
            "HandBrake",
            "HandBrake.HandBrake"
        ],
        "Category": "Audio & Video",
        "IDn": 94,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/handbrake.png"
    },
    {
        "ID": "CodecGuide.K-LiteCodecPack.Mega",
        "Name": "K-Lite Codec Pack Mega",
        "Domain": "codecguide.com",
        "Aliases": [
            "K-Lite Mega Codec Pack",
            "K-Lite Codec Pack",
            "K-Lite Codec Pack Mega",
            "CodecGuide.K-LiteCodecPack.Mega"
        ],
        "Category": "Audio & Video",
        "IDn": 95,
        "IconUrl": "https://icons.duckduckgo.com/ip3/codecguide.com.ico",
        "Url": "https://codecguide.com/download_k-lite_codec_pack_mega.htm"
    },
    {
        "ID": "ShareX.ShareX",
        "Name": "ShareX",
        "Domain": "getsharex.com",
        "Aliases": [
            "ShareX",
            "ShareX.ShareX"
        ],
        "Category": "Graphics & Design",
        "IDn": 96,
        "IconUrl": "https://raw.githubusercontent.com/ShareX/ShareX/master/ShareX.HelpersLib/Resources/ShareX_Logo.png"
    },
    {
        "ID": "GIMP.GIMP",
        "Name": "GIMP",
        "Domain": "gimp.org",
        "Aliases": [
            "GIMP",
            "GNU Image Manipulation Program",
            "GIMP.GIMP"
        ],
        "Category": "Graphics & Design",
        "IDn": 97,
        "IconUrl": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/gimp.png"
    },
    {
        "ID": "KDE.Krita",
        "Name": "Krita",
        "Domain": "krita.org",
        "Aliases": [
            "Krita",
            "KDE.Krita"
        ],
        "Category": "Graphics & Design",
        "IDn": 98,
        "IconUrl": "https://img.icons8.com/color/96/krita.png"
    },
    {
        "ID": "BlenderFoundation.Blender",
        "Name": "Blender",
        "Domain": "blender.org",
        "Aliases": [
            "Blender",
            "BlenderFoundation.Blender"
        ],
        "Category": "Graphics & Design",
        "IDn": 99,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/blender.png"
    },
    {
        "ID": "Inkscape.Inkscape",
        "Name": "Inkscape",
        "Domain": "inkscape.org",
        "Aliases": [
            "Inkscape",
            "Inkscape.Inkscape"
        ],
        "Category": "Graphics & Design",
        "IDn": 100,
        "IconUrl": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/inkscape-light.png"
    },
    {
        "ID": "TheDocumentFoundation.LibreOffice",
        "Name": "LibreOffice",
        "Domain": "libreoffice.org",
        "Aliases": [
            "LibreOffice",
            "TheDocumentFoundation.LibreOffice"
        ],
        "Category": "Documents & Office",
        "IDn": 101,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/libreoffice-colibre-text.png"
    },
    {
        "ID": "Obsidian.Obsidian",
        "Name": "Obsidian",
        "Domain": "obsidian.md",
        "Aliases": [
            "Obsidian",
            "Obsidian.Obsidian"
        ],
        "Category": "Documents & Office",
        "IDn": 102,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/obsidian.png"
    },
    {
        "ID": "Notion.Notion",
        "Name": "Notion",
        "Domain": "notion.so",
        "Aliases": [
            "Notion",
            "Notion.Notion"
        ],
        "Category": "Documents & Office",
        "IDn": 103,
        "IconUrl": "https://img.icons8.com/fluency/96/notion.png"
    },
    {
        "ID": "SumatraPDF.SumatraPDF",
        "Name": "SumatraPDF",
        "Domain": "sumatrapdfreader.org",
        "Aliases": [
            "SumatraPDF",
            "SumatraPDF.SumatraPDF"
        ],
        "Category": "Documents & Office",
        "IDn": 104,
        "Url": "https://www.sumatrapdfreader.org/free-pdf-reader"
    },
    {
        "ID": "Foxit.FoxitReader",
        "Name": "Foxit PDF Reader",
        "Domain": "foxit.com",
        "Aliases": [
            "Foxit PDF Reader",
            "Foxit Reader",
            "Foxit.FoxitReader"
        ],
        "Category": "Documents & Office",
        "IDn": 105,
        "Url": "https://www.foxit.com/pdf-reader/",
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/foxit-icon.png"
    },
    {
        "ID": "Valve.Steam",
        "Name": "Steam",
        "Domain": "store.steampowered.com",
        "Aliases": [
            "Steam",
            "Valve.Steam"
        ],
        "Category": "Game Launchers",
        "IDn": 106,
        "Url": "https://store.steampowered.com/",
        "IconUrl": "https://img.icons8.com/fluency/96/steam.png"
    },
    {
        "ID": "EpicGames.EpicGamesLauncher",
        "Name": "Epic Games Launcher",
        "Domain": "store.epicgames.com",
        "Aliases": [
            "Epic Games Launcher",
            "Epic Games",
            "EpicGames.EpicGamesLauncher"
        ],
        "Category": "Game Launchers",
        "IDn": 107,
        "IconUrl": "https://img.icons8.com/fluency/96/epic-games.png",
        "Url": "https://store.epicgames.com/"
    },
    {
        "ID": "GOG.Galaxy",
        "Name": "GOG Galaxy",
        "Domain": "gog.com",
        "Aliases": [
            "GOG Galaxy",
            "GOG.Galaxy"
        ],
        "Category": "Game Launchers",
        "IDn": 108,
        "Url": "https://www.gog.com/galaxy",
        "IconUrl": "https://img.icons8.com/fluency/96/gog-galaxy.png"
    },
    {
        "ID": "Playnite.Playnite",
        "Name": "Playnite",
        "Domain": "playnite.link",
        "Aliases": [
            "Playnite",
            "Playnite.Playnite"
        ],
        "Category": "Game Launchers",
        "IDn": 109,
        "IconUrl": "https://raw.githubusercontent.com/JosefNemec/Playnite/master/source/Playnite.DesktopApp/Themes/Desktop/Default/Images/applogo.png"
    },
    {
        "ID": "qBittorrent.qBittorrent",
        "Name": "qBittorrent",
        "Domain": "qbittorrent.org",
        "Aliases": [
            "qBittorrent",
            "qBittorrent.qBittorrent"
        ],
        "Category": "File Transfer & Cloud",
        "IDn": 110,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/qbittorrent.png"
    },
    {
        "ID": "LocalSend.LocalSend",
        "Name": "LocalSend",
        "Domain": "localsend.org",
        "Aliases": [
            "LocalSend",
            "LocalSend.LocalSend"
        ],
        "Category": "File Transfer & Cloud",
        "IDn": 111,
        "IconUrl": "https://raw.githubusercontent.com/localsend/localsend/main/app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png"
    },
    {
        "ID": "WinSCP.WinSCP",
        "Name": "WinSCP",
        "Domain": "winscp.net",
        "Aliases": [
            "WinSCP",
            "WinSCP.WinSCP"
        ],
        "Category": "File Transfer & Cloud",
        "IDn": 112
    },
    {
        "ID": "TimKosse.FileZilla.Client",
        "Name": "FileZilla",
        "Domain": "filezilla-project.org",
        "Aliases": [
            "FileZilla Client",
            "FileZilla",
            "TimKosse.FileZilla.Client"
        ],
        "Category": "File Transfer & Cloud",
        "IDn": 113,
        "FallbackUrl": "https://filezilla-project.org/download.php?platform=win64",
        "Url": "https://filezilla-project.org/download.php?platform=win64",
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/filezilla.png"
    },
    {
        "ID": "Rclone.Rclone",
        "Name": "Rclone",
        "Domain": "rclone.org",
        "Aliases": [
            "Rclone",
            "Rclone.Rclone"
        ],
        "Category": "File Transfer & Cloud",
        "IDn": 114,
        "IconUrl": "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/rclone.png"
    }
]
'@
$AppCatalog = ConvertFrom-Json $appsRawJson

# 4. GIAO DIỆN XAML WPF
[xml]$XAML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="DuckUtil — Windows Software &amp; Maintenance Suite"
    Width="1260" Height="780"
    MinWidth="980" MinHeight="620"
    WindowStartupLocation="CenterScreen"
    Background="#0C1018"
    Foreground="#E2E8F0"
    FontFamily="Segoe UI Variable Display, Segoe UI, -apple-system, sans-serif"
    TextOptions.TextFormattingMode="Display"
    TextOptions.TextRenderingMode="ClearType"
    UseLayoutRounding="True"
    SnapsToDevicePixels="True">

    <Window.Resources>
        <!-- ═══ FLUENT CHECKBOX TỐI GIẢN CHUẨN WINUTIL ═══ -->
        <Style TargetType="{x:Type CheckBox}">
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type CheckBox}">
                        <Grid Background="Transparent" Width="16" Height="16">
                            <Border x:Name="box" Width="15" Height="15" CornerRadius="4"
                                    Background="#131B29" BorderBrush="#334155" BorderThickness="1.2"
                                    HorizontalAlignment="Center" VerticalAlignment="Center">
                                <Path x:Name="checkMark" Visibility="Collapsed"
                                      Data="M 2.2,6.2 L 5.2,9.2 L 10.8,3.2"
                                      Stroke="#FFFFFF" StrokeThickness="1.8"
                                      StrokeStartLineCap="Round" StrokeEndLineCap="Round"
                                      StrokeLineJoin="Round" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="box" Property="BorderBrush" Value="#38BDF8"/>
                                <Setter TargetName="box" Property="Background" Value="#192335"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="box" Property="Background" Value="#0284C7"/>
                                <Setter TargetName="box" Property="BorderBrush" Value="#38BDF8"/>
                                <Setter TargetName="checkMark" Property="Visibility" Value="Visible"/>
                            </Trigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="IsChecked" Value="True"/>
                                    <Condition Property="IsMouseOver" Value="True"/>
                                </MultiTrigger.Conditions>
                                <Setter TargetName="box" Property="Background" Value="#0EA5E9"/>
                            </MultiTrigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="box" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ═══ THANH CUỘN (SCROLLBAR) MẢNH 7PX ═══ -->
        <Style x:Key="ModernScrollThumb" TargetType="{x:Type Thumb}">
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Setter Property="IsTabStop" Value="False"/>
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type Thumb}">
                        <Border Name="thumbBorder" Background="#253147" CornerRadius="3" Margin="2,0"/>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="thumbBorder" Property="Background" Value="#38BDF8"/>
                            </Trigger>
                            <Trigger Property="IsDragging" Value="True">
                                <Setter TargetName="thumbBorder" Property="Background" Value="#0EA5E9"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ScrollBarPageButton" TargetType="{x:Type RepeatButton}">
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Setter Property="IsTabStop" Value="False"/>
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type RepeatButton}">
                        <Border Background="Transparent"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="{x:Type ScrollBar}">
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Style.Triggers>
                <Trigger Property="Orientation" Value="Vertical">
                    <Setter Property="Width" Value="7"/>
                    <Setter Property="Height" Value="Auto"/>
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="{x:Type ScrollBar}">
                                <Grid Background="Transparent">
                                    <Track Name="PART_Track" IsDirectionReversed="True">
                                        <Track.DecreaseRepeatButton>
                                            <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="ScrollBar.PageUpCommand"/>
                                        </Track.DecreaseRepeatButton>
                                        <Track.Thumb>
                                            <Thumb Style="{StaticResource ModernScrollThumb}"/>
                                        </Track.Thumb>
                                        <Track.IncreaseRepeatButton>
                                            <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="ScrollBar.PageDownCommand"/>
                                        </Track.IncreaseRepeatButton>
                                    </Track>
                                </Grid>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                </Trigger>
                <Trigger Property="Orientation" Value="Horizontal">
                    <Setter Property="Width" Value="Auto"/>
                    <Setter Property="Height" Value="7"/>
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="{x:Type ScrollBar}">
                                <Grid Background="Transparent">
                                    <Track Name="PART_Track" IsDirectionReversed="False">
                                        <Track.DecreaseRepeatButton>
                                            <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="ScrollBar.PageLeftCommand"/>
                                        </Track.DecreaseRepeatButton>
                                        <Track.Thumb>
                                            <Thumb Style="{StaticResource ModernScrollThumb}">
                                                <Thumb.Template>
                                                    <ControlTemplate TargetType="{x:Type Thumb}">
                                                        <Border Name="hThumbBorder" Background="#253147" CornerRadius="3" Margin="0,2"/>
                                                        <ControlTemplate.Triggers>
                                                            <Trigger Property="IsMouseOver" Value="True">
                                                                <Setter TargetName="hThumbBorder" Property="Background" Value="#38BDF8"/>
                                                            </Trigger>
                                                            <Trigger Property="IsDragging" Value="True">
                                                                <Setter TargetName="hThumbBorder" Property="Background" Value="#0EA5E9"/>
                                                            </Trigger>
                                                        </ControlTemplate.Triggers>
                                                    </ControlTemplate>
                                                </Thumb.Template>
                                            </Thumb>
                                        </Track.Thumb>
                                        <Track.IncreaseRepeatButton>
                                            <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="ScrollBar.PageRightCommand"/>
                                        </Track.IncreaseRepeatButton>
                                    </Track>
                                </Grid>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Nút bấm chính (Matte Fluent Accent - Đỡ chói mắt) -->
        <Style x:Key="ActionButton" TargetType="Button">
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="14,7"/>
            <Setter Property="Margin" Value="0,0,6,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#24FFFFFF"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="btnBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}"
                                SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.90"/>
                                <Setter TargetName="btnBorder" Property="BorderBrush" Value="#55FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.72"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Nút phụ (Clean Dark Slate Flat Style chuẩn WinUtil) -->
        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="#141B29"/>
            <Setter Property="Foreground" Value="#CBD5E1"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="13,7"/>
            <Setter Property="Margin" Value="0,0,6,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderBrush" Value="#212B3F"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="HorizontalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="btnBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}"
                                SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="#1B2538"/>
                                <Setter TargetName="btnBorder" Property="BorderBrush" Value="#38BDF8"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="#161E2E"/>
                                <Setter TargetName="btnBorder" Property="BorderBrush" Value="#0EA5E9"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Nút điều hướng Tab chính (WinUtil Clean Tab Strip) -->
        <Style x:Key="NavTabButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#64748B"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="18,10"/>
            <Setter Property="Margin" Value="0,0,4,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0,0,0,2"/>
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="navBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                Padding="{TemplateBinding Padding}"
                                SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="#E2E8F0"/>
                                <Setter TargetName="navBorder" Property="Background" Value="#121825"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/> <!-- Main Nav Tab Bar -->
            <RowDefinition Height="*"/>    <!-- Main Viewport -->
            <RowDefinition Height="Auto"/> <!-- Status & Progress Bar -->
            <RowDefinition Height="Auto" Name="rowDefTerminal"/>  <!-- Terminal Log -->
        </Grid.RowDefinitions>

        <!-- ═══ 1. MAIN NAV TAB BAR ═══ -->
        <Border Grid.Row="0" Background="#0A0E15" Padding="14,0" BorderBrush="#192130" BorderThickness="0,0,0,1">
            <Grid>
                <StackPanel Orientation="Horizontal">
                    <Button Name="navBtnApps" Content="Ứng dụng (Install)" Style="{StaticResource NavTabButton}"
                            BorderBrush="#38BDF8" Foreground="#38BDF8"/>
                    <Button Name="navBtnRepair" Content="Gỡ lỗi &amp; Hệ thống" Style="{StaticResource NavTabButton}"/>
                    <Button Name="navBtnDrivers" Content="Quản lý Driver" Style="{StaticResource NavTabButton}"/>
                </StackPanel>
                <TextBlock Text="DuckUtil" HorizontalAlignment="Right" VerticalAlignment="Center"
                           Foreground="#475569" FontSize="11.5" FontWeight="SemiBold" Margin="0,0,4,0"/>
            </Grid>
        </Border>

        <!-- ═══ 2. MAIN VIEWPORT (TAB CONTROL) ═══ -->
        <TabControl Grid.Row="1" Name="MainTabControl" Background="Transparent" BorderThickness="0" Padding="0">
            <TabControl.ItemContainerStyle>
                <Style TargetType="TabItem">
                    <Setter Property="Visibility" Value="Collapsed"/>
                </Style>
            </TabControl.ItemContainerStyle>

            <!-- ── TAB 1: ỨNG DỤNG (BỐ CỤC 4 CỘT TỐI GIẢN CHUẨN WINUTIL) ── -->
            <TabItem>
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <!-- Thanh công cụ tối giản -->
                    <Border Grid.Row="0" Background="#0E131D" Padding="16,9" BorderBrush="#192130" BorderThickness="0,0,0,1">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>

                            <!-- Hàng 1: Hành động chính -->
                            <Grid Grid.Row="0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>

                                <StackPanel Grid.Column="0" Orientation="Horizontal">
                                    <Button Name="btnInstall" Content="Install Selected" Style="{StaticResource ActionButton}"
                                            Background="#059669" Padding="15,7"/>
                                    <Button Name="btnUpgradeAll" Content="Upgrade All" Style="{StaticResource SecondaryButton}"
                                            Foreground="#FBBF24" BorderBrush="#3B311B"/>
                                    <Button Name="btnUninstall" Content="Uninstall Selected" Style="{StaticResource SecondaryButton}"
                                            Foreground="#F87171" BorderBrush="#3E2027"/>
                                    <Button Name="btnScanInstalled" Content="Get Installed" Style="{StaticResource SecondaryButton}"
                                            Foreground="#38BDF8" BorderBrush="#1D3652"/>
                                </StackPanel>

                                <StackPanel Grid.Column="2" Orientation="Horizontal">
                                    <Button Name="btnSelectAll" Content="Select All" Style="{StaticResource SecondaryButton}" Margin="0,0,6,0"/>
                                    <Button Name="btnDeselectAll" Content="Clear Selection" Style="{StaticResource SecondaryButton}" Margin="0"/>
                                </StackPanel>
                            </Grid>

                            <!-- Hàng 2: Chú thích trạng thái siêu gọn (Không nhét hộp pill dày cộm) -->
                            <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="1,7,0,0" VerticalAlignment="Center">
                                <TextBlock Text="Trạng thái:" FontSize="11" Foreground="#64748B" Margin="0,0,12,0" FontWeight="SemiBold"/>
                                <StackPanel Orientation="Horizontal" Margin="0,0,14,0" VerticalAlignment="Center">
                                    <Ellipse Width="7" Height="7" Fill="#F1F5F9" Margin="0,0,5,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="Chưa cài đặt" FontSize="11" Foreground="#CBD5E1"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,14,0" VerticalAlignment="Center">
                                    <Ellipse Width="7" Height="7" Fill="#34D399" Margin="0,0,5,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="Đã cài (Mới nhất)" FontSize="11" Foreground="#34D399"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                    <Ellipse Width="7" Height="7" Fill="#F87171" Margin="0,0,5,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="Bản cũ (Có cập nhật)" FontSize="11" Foreground="#F87171"/>
                                </StackPanel>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Lưới Card 4 Cột Dọc Tự Nhiên (Masonry 4 Cột) -->
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"
                                  CanContentScroll="False" PanningMode="VerticalOnly" Padding="10,10">
                        <Grid Name="CardsContainer">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0" Name="CardsCol0" Margin="4,0"/>
                            <StackPanel Grid.Column="1" Name="CardsCol1" Margin="4,0"/>
                            <StackPanel Grid.Column="2" Name="CardsCol2" Margin="4,0"/>
                            <StackPanel Grid.Column="3" Name="CardsCol3" Margin="4,0"/>
                        </Grid>
                    </ScrollViewer>
                </Grid>
            </TabItem>

            <!-- ── TAB 2: GỠ LỖI & SỬA HỆ THỐNG ── -->
            <TabItem>
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="16,14">
                    <UniformGrid Columns="2" VerticalAlignment="Top">
                        <!-- Card 1: File Hệ Thống -->
                        <Border Background="#111722" BorderBrush="#1C2536" BorderThickness="1" CornerRadius="8" Margin="6" Padding="18">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <Border Background="#12263A" CornerRadius="4" Padding="6,2" Margin="0,0,8,0" VerticalAlignment="Center">
                                        <TextBlock Text="CORE FIX" FontSize="9.5" FontWeight="Bold" Foreground="#38BDF8"/>
                                    </Border>
                                    <TextBlock Text="Sửa chữa file hệ thống" FontWeight="SemiBold" FontSize="13.5" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Quét và tự động sửa các file hệ thống Windows bị hỏng hoặc mất qua SFC và DISM."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnSfcScan" Content="SFC Scan (sfc /scannow)" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnDismRestore" Content="DISM RestoreHealth (Phục hồi linh kiện)" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnDismCleanup" Content="Dọn Kho Linh Kiện (Component Cleanup)" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 2: Windows Update -->
                        <Border Background="#111722" BorderBrush="#1C2536" BorderThickness="1" CornerRadius="8" Margin="6" Padding="18">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <Border Background="#2A1F12" CornerRadius="4" Padding="6,2" Margin="0,0,8,0" VerticalAlignment="Center">
                                        <TextBlock Text="UPDATE" FontSize="9.5" FontWeight="Bold" Foreground="#FBBF24"/>
                                    </Border>
                                    <TextBlock Text="Gỡ lỗi Windows Update" FontWeight="SemiBold" FontSize="13.5" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Khắc phục triệt để lỗi kẹt tải 0%, mã lỗi 0x80070002, 0x8024... khi cập nhật Windows."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnFixWindowsUpdate" Content="Reset Toàn Bộ Cache Update (Triệt để)" Style="{StaticResource ActionButton}" Background="#B45309" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnRestartUpdateServices" Content="Khởi Động Lại Dịch Vụ BITS &amp; Wuauserv" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnTriggerScanUpdate" Content="Kích Hoạt Tìm Bản Cập Nhật Mới (USOClient)" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 3: Mạng & DNS -->
                        <Border Background="#111722" BorderBrush="#1C2536" BorderThickness="1" CornerRadius="8" Margin="6" Padding="18">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <Border Background="#0E2920" CornerRadius="4" Padding="6,2" Margin="0,0,8,0" VerticalAlignment="Center">
                                        <TextBlock Text="NETWORK" FontSize="9.5" FontWeight="Bold" Foreground="#34D399"/>
                                    </Border>
                                    <TextBlock Text="Sửa lỗi Mạng &amp; Kết nối" FontWeight="SemiBold" FontSize="13.5" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Khắc phục sự cố mất kết nối mạng, gián đoạn truy cập web, lỗi DNS và sự cố bộ giao thức."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnFlushDnsWinsock" Content="Flush DNS &amp; Reset Winsock (Làm mới mạng)" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnResetTcpIp" Content="Reset Toàn Bộ Ngăn Xếp TCP/IP Stack" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 4: Dọn Rác & Khôi Phục UI -->
                        <Border Background="#111722" BorderBrush="#1C2536" BorderThickness="1" CornerRadius="8" Margin="6" Padding="18">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <Border Background="#1F1936" CornerRadius="4" Padding="6,2" Margin="0,0,8,0" VerticalAlignment="Center">
                                        <TextBlock Text="MAINTAIN" FontSize="9.5" FontWeight="Bold" Foreground="#A78BFA"/>
                                    </Border>
                                    <TextBlock Text="Bảo trì &amp; Dọn dẹp hệ thống" FontWeight="SemiBold" FontSize="13.5" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Giải phóng dung lượng ổ C bị chiếm dụng bởi tệp tạm, nhật ký sự kiện và nạp lại thanh Taskbar khi bị treo."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnClearTemp" Content="Dọn Sạch Thư Mục Temp &amp; Cache Rác" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnCleanEventLogs" Content="Dọn Dẹp Windows Event Logs" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnRestartExplorer" Content="Khởi Động Lại Windows Explorer (Fix đơ taskbar)" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                            </StackPanel>
                        </Border>
                    </UniformGrid>
                </ScrollViewer>
            </TabItem>

            <!-- ── TAB 3: QUẢN LÝ & GỠ LỖI DRIVER ── -->
            <TabItem>
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="16,14">
                    <UniformGrid Columns="3" VerticalAlignment="Top">
                        <!-- Card 1: Chẩn Đoán Driver Lỗi -->
                        <Border Background="#111722" BorderBrush="#1C2536" BorderThickness="1" CornerRadius="8" Margin="6" Padding="18">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <Border Background="#2D141D" CornerRadius="4" Padding="6,2" Margin="0,0,8,0" VerticalAlignment="Center">
                                        <TextBlock Text="HARDWARE" FontSize="9.5" FontWeight="Bold" Foreground="#FB7185"/>
                                    </Border>
                                    <TextBlock Text="Chẩn đoán phần cứng" FontWeight="SemiBold" FontSize="13.5" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Rà soát các thiết bị bị chấm than vàng, thiếu driver hoặc driver bị xung đột crash."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnScanFaultyDrivers" Content="Quét Thiết Bị &amp; Driver Bị Lỗi" Style="{StaticResource ActionButton}" Background="#BE123C" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnPnpRescan" Content="Buộc Windows Quét Lại Phần Cứng (PnP Scan)" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnOpenDeviceManager" Content="Mở Trình Quản Lý Device Manager" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 2: Gỡ Lỗi Update Driver -->
                        <Border Background="#111722" BorderBrush="#1C2536" BorderThickness="1" CornerRadius="8" Margin="6" Padding="18">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <Border Background="#2A1F12" CornerRadius="4" Padding="6,2" Margin="0,0,8,0" VerticalAlignment="Center">
                                        <TextBlock Text="RESOLVE" FontSize="9.5" FontWeight="Bold" Foreground="#FBBF24"/>
                                    </Border>
                                    <TextBlock Text="Gỡ lỗi cập nhật Driver" FontWeight="SemiBold" FontSize="13.5" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Sửa lỗi Windows Update bị kẹt khi đang cài driver màn hình, âm thanh, touchpad."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnFixDriverUpdate" Content="Sửa Lỗi Kẹt Cập Nhật Driver (Xóa Queue)" Style="{StaticResource ActionButton}" Background="#B45309" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnScanWindowsUpdateDrivers" Content="Kích Hoạt Quét Driver Mới Từ Microsoft" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnCleanDriverStore" Content="Dọn Dẹp Driver Cũ Trong DriverStore" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 3: Sao Lưu Driver -->
                        <Border Background="#111722" BorderBrush="#1C2536" BorderThickness="1" CornerRadius="8" Margin="6" Padding="18">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <Border Background="#0E2920" CornerRadius="4" Padding="6,2" Margin="0,0,8,0" VerticalAlignment="Center">
                                        <TextBlock Text="BACKUP" FontSize="9.5" FontWeight="Bold" Foreground="#34D399"/>
                                    </Border>
                                    <TextBlock Text="Sao lưu &amp; Bảo vệ Driver" FontWeight="SemiBold" FontSize="13.5" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Trích xuất toàn bộ driver bên thứ ba để phòng khi cài lại Windows không sợ mất mạng/wifi."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnBackupDrivers" Content="Sao Lưu Toàn Bộ Driver (Ra C:\Backup_Drivers)" Style="{StaticResource ActionButton}" Background="#059669" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnOpenBackupFolder" Content="Mở Thư Mục Chứa Driver Đã Sao Lưu" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                            </StackPanel>
                        </Border>
                    </UniformGrid>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- ═══ 3. STATUS & PROGRESS BAR ═══ -->
        <Border Grid.Row="2" Background="#0A0E15" Padding="16,6" BorderBrush="#192130" BorderThickness="0,1,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <StackPanel Grid.Column="0" Grid.Row="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <Ellipse Fill="#10B981" Width="7" Height="7" Margin="0,0,8,0" VerticalAlignment="Center"/>
                    <TextBlock Name="txtStatus" Text="Sẵn sàng"
                               Foreground="#93C5FD" FontSize="11.5" FontWeight="SemiBold"/>
                </StackPanel>

                <TextBlock Grid.Column="1" Grid.Row="0" Name="txtSelectionCount" Text="0 app được chọn"
                           Foreground="#64748B" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>

                <ProgressBar Grid.Column="0" Grid.ColumnSpan="2" Grid.Row="1"
                             Name="progressBar" Height="2" Margin="0,5,0,1"
                             Background="#141C2B" Foreground="#0EA5E9" BorderThickness="0" Value="0"/>
            </Grid>
        </Border>

        <!-- ═══ 4. TERMINAL LOG (THU GỌN MẶC ĐỊNH) ═══ -->
        <Border Grid.Row="3" Background="#080B12" Padding="16,6" BorderBrush="#151C29" BorderThickness="0,1,0,0">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0" Margin="0">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="&gt;_" FontSize="10.5" FontWeight="Bold" Foreground="#38BDF8"
                                   FontFamily="Cascadia Mono, Consolas, monospace" Margin="0,0,7,0" VerticalAlignment="Center"/>
                        <TextBlock Text="TERMINAL LOG" FontSize="10" FontWeight="SemiBold" Foreground="#64748B"
                                   FontFamily="Cascadia Mono, Consolas, monospace" VerticalAlignment="Center"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                        <Button Name="btnToggleTerminal" Content="▲ Mở rộng"
                                Background="#111722" BorderBrush="#1F293B" BorderThickness="1"
                                Foreground="#34D399" Cursor="Hand" FontSize="11" FontWeight="SemiBold"
                                Padding="8,2" Margin="0,0,8,0" ToolTip="Ẩn / Hiện khung Terminal Log"/>
                        <Button Name="btnClearLog" Content="Xóa Log"
                                Background="Transparent" Foreground="#64748B" BorderThickness="0"
                                Cursor="Hand" FontSize="11" Padding="6,2"/>
                    </StackPanel>
                </Grid>
                <TextBox Grid.Row="1" Name="txtLog" Visibility="Collapsed" Margin="0,6,0,0" Background="Transparent" Foreground="#34D399"
                         FontFamily="Cascadia Mono, Cascadia Code, Consolas, Courier New" FontSize="11"
                         IsReadOnly="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"
                         BorderThickness="0" CaretBrush="#38BDF8"
                         Text="[DuckUtil] Khởi tạo thành công.&#x0d;&#x0a;"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# 5. MODULES & FUNCTIONS
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

# ── FUNCTION: QUÉT & PHÂN LOẠI MÀU PHIÊN BẢN (TRẮNG / XANH / ĐỎ) ──

# Bộ nhớ đệm tĩnh lưu trữ Brush của WPF giúp tối ưu render và triệt tiêu Garbage Collection
$script:brushOutdatedFg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF8, 0x71, 0x71))
$script:brushLatestFg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x34, 0xD3, 0x99))
$script:brushNoneBg     = [System.Windows.Media.Brushes]::Transparent
$script:brushNoneFg     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF1, 0xF5, 0xF9))

$script:brushOutdatedFg.Freeze()
$script:brushLatestFg.Freeze()
$script:brushNoneFg.Freeze()

function Get-CleanAppName {
    param([string]$RawName)
    if ([string]::IsNullOrWhiteSpace($RawName)) { return "" }
    # Loại bỏ thông tin đóng ngoặc nhưng KHÔNG xóa mất định danh kiến trúc (x64), (x86), (arm64)
    $clean = ($RawName -replace '\((?!x64|x86|arm64).*?\)', '').Replace('(', '').Replace(')', '').Trim().ToLowerInvariant()
    $terms = @(" browser", " desktop", " lts", " client", " free", " ce", " community", " end-user")
    foreach ($term in $terms) {
        $clean = $clean.Replace($term, "")
    }
    return $clean.Trim()
}

function Get-CharDisplayWidth {
    param([int]$Code)
    # CJK, Hangul, Kana, Fullwidth & Emoji chiếm 2 cột hiển thị trong terminal Windows/winget
    if (
        ($Code -ge 0x1100 -and $Code -le 0x115F) -or
        ($Code -eq 0x2329 -or $Code -eq 0x232A) -or
        ($Code -ge 0x2E80 -and $Code -le 0x303E) -or
        ($Code -ge 0x3041 -and $Code -le 0x33FF) -or
        ($Code -ge 0x3400 -and $Code -le 0x4DBF) -or
        ($Code -ge 0x4E00 -and $Code -le 0xA4CF) -or
        ($Code -ge 0xA960 -and $Code -le 0xA97F) -or
        ($Code -ge 0xAC00 -and $Code -le 0xD7AF) -or
        ($Code -ge 0xF900 -and $Code -le 0xFAFF) -or
        ($Code -ge 0xFE10 -and $Code -le 0xFE19) -or
        ($Code -ge 0xFE30 -and $Code -le 0xFE6F) -or
        ($Code -ge 0xFF01 -and $Code -le 0xFF60) -or
        ($Code -ge 0xFFE0 -and $Code -le 0xFFE6) -or
        ($Code -ge 0x1F300 -and $Code -le 0x1FAFF)
    ) { return 2 }
    return 1
}

function Get-SliceByDisplayWidth {
    param([string]$Line, [int[]]$Offsets)
    # Cắt chuỗi theo độ rộng cột console để các dòng tiếng Trung/Nhật/Hàn không làm lệch cột ID/Version
    $idIdx    = if ($Offsets.Count -ge 2) { $Offsets[1] } else { -1 }
    $verIdx   = if ($Offsets.Count -ge 3) { $Offsets[2] } else { -1 }
    $availIdx = if ($Offsets.Count -ge 4) { $Offsets[3] } else { -1 }
    $srcIdx   = if ($Offsets.Count -ge 5) { $Offsets[4] } else { -1 }

    $targets = @($idIdx, $verIdx, $availIdx, $srcIdx)
    $charPos = @(-1, -1, -1, -1)
    $w = 0
    for ($i = 0; $i -lt $Line.Length; $i++) {
        for ($t = 0; $t -lt 4; $t++) {
            if ($charPos[$t] -lt 0 -and $targets[$t] -ge 0 -and $w -ge $targets[$t]) {
                $charPos[$t] = $i
            }
        }
        $ch = $Line[$i]
        if ([char]::IsHighSurrogate($ch) -and ($i + 1) -lt $Line.Length -and [char]::IsLowSurrogate($Line[$i + 1])) {
            $cp = [char]::ConvertToUtf32($ch, $Line[$i + 1])
            $w += Get-CharDisplayWidth $cp
            $i++
        } else {
            $w += Get-CharDisplayWidth ([int]$ch)
        }
    }

    $cId    = $charPos[0]
    $cVer   = $charPos[1]
    $cAvail = $charPos[2]
    $cSrc   = $charPos[3]

    $appName = ""; $appId = ""; $version = ""; $avail = ""
    if ($cId -gt 0 -and $Line.Length -gt $cId) {
        $appName = $Line.Substring(0, $cId).Trim()
        if ($cVer -gt $cId -and $Line.Length -gt $cVer) {
            $appId = $Line.Substring($cId, $cVer - $cId).Trim()
            if ($cAvail -gt $cVer -and $Line.Length -gt $cAvail) {
                $version = $Line.Substring($cVer, $cAvail - $cVer).Trim()
                if ($cSrc -gt $cAvail -and $Line.Length -gt $cSrc) {
                    $avail = $Line.Substring($cAvail, $cSrc - $cAvail).Trim()
                } else {
                    $avail = $Line.Substring($cAvail).Trim()
                }
            } else {
                $version = $Line.Substring($cVer).Trim()
            }
        } else {
            $appId = $Line.Substring($cId).Trim()
        }
    }
    return @($appName, $appId, $version, $avail)
}

function Set-PreferredMapEntry {
    param($Map, [string]$Key, $Candidate)
    if ([string]::IsNullOrWhiteSpace($Key)) { return }
    if (-not $Map.ContainsKey($Key)) {
        $Map[$Key] = $Candidate
        return
    }
    $cur = $Map[$Key]
    $preferUpdate = (-not $cur.HasUpdate -and $Candidate.HasUpdate)
    $preferNativeId = ($cur.HasUpdate -eq $Candidate.HasUpdate -and $cur.ID -match '^(ARP|MSIX)\\' -and $Candidate.ID -notmatch '^(ARP|MSIX)\\')
    if ($preferUpdate -or $preferNativeId) {
        $Map[$Key] = $Candidate
    }
}

function Test-MatchCompatible {
    param($TargetApp, $Item)
    if (-not $TargetApp -or -not $Item) { return $false }

    $tName = [string]$TargetApp.Name
    $tId   = [string]$TargetApp.ID
    $iName = [string]$Item.Name
    $iId   = [string]$Item.ID

    # Chặn khớp chéo giữa bản thường và bản Preview
    $tPrev = ($tName -match 'Preview') -or ($tId -match 'Preview')
    $iPrev = ($iName -match 'Preview') -or ($iId -match 'Preview')
    if ($tPrev -ne $iPrev) { return $false }

    # Chặn gói UWP/VCLibs khớp nhầm vào Desktop Redistributable
    if (($tId -match 'VCRedist' -or $tName -match 'VC\+\+') -and ($iName -match '\bUWP\b' -or $iId -match 'VCLibs')) {
        return $false
    }

    # Kiểm tra đồng nhất kiến trúc x64 / x86 / arm64 (KHÔNG xét nhánh registry ARP\Machine\X86 vì app x64 vẫn có thể ghi khóa WOW6432Node)
    $tArch = if ($tName -match '\(x64\)|\.x64' -or $tId -match '\.x64$') { "x64" }
             elseif ($tName -match '\(x86\)|\.x86' -or $tId -match '\.x86$') { "x86" }
             elseif ($tName -match '\(arm64\)|\.arm64' -or $tId -match '\.arm64$') { "arm64" }
             else { "" }

    if ($tArch) {
        $idForArch = if ($iId -match '^(ARP|MSIX)\\') { "" } else { $iId }
        $iArch = if ($iName -match '(?<![a-zA-Z0-9])(x64|64-bit)(?![a-zA-Z0-9])' -or $idForArch -match '\.x64$') { "x64" }
                 elseif ($iName -match '(?<![a-zA-Z0-9])(x86|32-bit)(?![a-zA-Z0-9])' -or $idForArch -match '\.x86$') { "x86" }
                 elseif ($iName -match '(?<![a-zA-Z0-9])arm64(?![a-zA-Z0-9])' -or $idForArch -match '\.arm64$') { "arm64" }
                 else { "" }
        if ($iArch -and $iArch -ne $tArch) { return $false }
    }

    return $true
}

function Scan-And-ColorizeApps {
    Log-Text "[🔍] Đang chạy quét nhận diện ứng dụng & phân tích phiên bản (winget list)..."
    if ($txtStatus) { $txtStatus.Text = "Đang kiểm tra phiên bản app..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    [System.Windows.Forms.Application]::DoEvents()

    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        Log-Text "[⚠️] Máy tính của bạn chưa có WinGet (Windows Package Manager)."
        Log-Text "[*] Vui lòng cài/cập nhật gói 'App Installer' từ Microsoft Store để kích hoạt tính năng App."
        if ($txtStatus) { $txtStatus.Text = "Thiếu WinGet | Cần cài App Installer" }
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        return
    }

    $rawList = ""
    $errList = ""
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "winget"
        $pinfo.Arguments = "list --disable-interactivity --accept-source-agreements"
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $pinfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true

        $p = [System.Diagnostics.Process]::Start($pinfo)
        if ($null -eq $p) {
            throw "Không thể khởi động tiến trình winget."
        }

        # Đọc dữ liệu bất đồng bộ đồng thời cả 2 luồng stdout và stderr để tránh tràn buffer gây deadlock
        $readTask = $p.StandardOutput.ReadToEndAsync()
        $errTask  = $p.StandardError.ReadToEndAsync()
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $readTask.IsCompleted -or -not $errTask.IsCompleted) {
            if ($sw.Elapsed.TotalSeconds -gt 45) {
                try { if (-not $p.HasExited) { $p.Kill() } } catch {}
                Log-Text "[⚠️] Lệnh winget list vượt quá thời gian chờ (45s)."
                break
            }
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 30
        }
        if ($readTask.IsCompleted) { $rawList = $readTask.Result }
        if ($errTask.IsCompleted) { $errList = $errTask.Result }
        try { if (-not $p.HasExited) { $p.WaitForExit(1000) | Out-Null } } catch {}

        # Kiểm tra ExitCode của winget list
        if ($p.HasExited -and $p.ExitCode -ne 0) {
            Log-Text "[⚠️] WinGet list kết thúc với mã $($p.ExitCode)."
            if (-not [string]::IsNullOrWhiteSpace($errList)) {
                Log-Text "[stderr] $errList"
            }
            if ([string]::IsNullOrWhiteSpace($rawList)) {
                Log-Text "[!] Không nhận được dữ liệu từ WinGet. Giữ nguyên trạng thái quét hiện tại."
                if ($progressBar) { $progressBar.IsIndeterminate = $false }
                if ($txtStatus) { $txtStatus.Text = "Lỗi quét WinGet (Mã $($p.ExitCode))" }
                return
            }
        }
    } catch {
        Log-Text "[!] Lỗi khi quét danh sách ứng dụng qua WinGet: $($_.Exception.Message)"
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        return
    }

    # Chuẩn hóa từng dòng (loại bỏ \r cuối dòng \r\n, đồng thời loại bỏ thanh spinner \r trước nội dung thực)
    $rawLines = $rawList -split "`n"
    $lines = [System.Collections.Generic.List[string]]::new($rawLines.Count)
    foreach ($rl in $rawLines) {
        $cleanLine = $rl.TrimEnd("`r")
        if ($cleanLine.Contains("`r")) { $cleanLine = ($cleanLine -split "`r")[-1] }
        $lines.Add($cleanLine)
    }

    $separatorIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^---\s*---' -or $lines[$i] -match '^---+$') {
            $separatorIndex = $i
            break
        }
    }

    $idMap         = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $nameMap       = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $cleanNameMap  = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $installedList = [System.Collections.Generic.List[object]]::new()

    if ($separatorIndex -gt 0) {
        $separatorLine = $lines[$separatorIndex]
        $headerLine    = $lines[$separatorIndex - 1]

        $colOffsets = @()
        if ($separatorLine -match '---+\s+---+') {
            $dashMatches = [System.Text.RegularExpressions.Regex]::Matches($separatorLine, '-+')
            foreach ($dm in $dashMatches) { $colOffsets += $dm.Index }
        } elseif ($headerLine) {
            $headerMatches = [System.Text.RegularExpressions.Regex]::Matches($headerLine, '[^\s]+(?:\s[^\s]+)*(?=\s{2,}|\s*$)')
            foreach ($hm in $headerMatches) { $colOffsets += $hm.Index }
        }

        $idIdx    = if ($colOffsets.Count -ge 2) { $colOffsets[1] } else { -1 }
        $verIdx   = if ($colOffsets.Count -ge 3) { $colOffsets[2] } else { -1 }
        $availIdx = if ($colOffsets.Count -ge 4) { $colOffsets[3] } else { -1 }
        $srcIdx   = if ($colOffsets.Count -ge 5) { $colOffsets[4] } else { -1 }

        for ($j = $separatorIndex + 1; $j -lt $lines.Count; $j++) {
            $line = $lines[$j]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $appName = ""; $appId = ""; $version = ""; $avail = ""

            if ($idIdx -gt 0 -and $line -match '[^\x00-\xFF]') {
                $sliced = Get-SliceByDisplayWidth -Line $line -Offsets $colOffsets
                $appName = $sliced[0]; $appId = $sliced[1]; $version = $sliced[2]; $avail = $sliced[3]
            } elseif ($idIdx -gt 0 -and $line.Length -gt $idIdx) {
                $appName = $line.Substring(0, $idIdx).Trim()
                if ($verIdx -gt $idIdx -and $line.Length -gt $verIdx) {
                    $appId = $line.Substring($idIdx, $verIdx - $idIdx).Trim()
                    if ($availIdx -gt $verIdx -and $line.Length -gt $availIdx) {
                        $version = $line.Substring($verIdx, $availIdx - $verIdx).Trim()
                        if ($srcIdx -gt $availIdx -and $line.Length -gt $srcIdx) {
                            $avail = $line.Substring($availIdx, $srcIdx - $availIdx).Trim()
                        } else {
                            $avail = $line.Substring($availIdx).Trim()
                        }
                    } else {
                        $version = $line.Substring($verIdx).Trim()
                    }
                } else {
                    $appId = $line.Substring($idIdx).Trim()
                }
            } else {
                $cols = [System.Text.RegularExpressions.Regex]::Split($line.Trim(), '\s{2,}')
                if ($cols.Count -ge 2) {
                    $appName = $cols[0].Trim()
                    $appId   = $cols[1].Trim()
                    $version = if ($cols.Count -ge 3) { $cols[2].Trim() } else { "" }
                    $avail   = if ($cols.Count -ge 4) { $cols[3].Trim() } else { "" }
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($appId)) {
                $hasUpdate = (-not [string]::IsNullOrWhiteSpace($avail)) -and ($avail -ne "winget") -and ($avail -ne "msstore")
                $clean = Get-CleanAppName $appName
                $itemObj = [PSCustomObject]@{
                    Name      = $appName
                    ID        = $appId
                    Version   = $version
                    Available = $avail
                    HasUpdate = $hasUpdate
                    CleanName = $clean
                }

                $installedList.Add($itemObj)
                Set-PreferredMapEntry $idMap $appId $itemObj
                Set-PreferredMapEntry $nameMap $appName $itemObj
                if ($clean.Length -ge 3) { Set-PreferredMapEntry $cleanNameMap $clean $itemObj }
            }
        }
    } else {
        # Fallback hoàn toàn cho winget không in header tiêu chuẩn
        foreach ($line in $lines) {
            if (-not [string]::IsNullOrWhiteSpace($line) -and -not ($line -like "---*")) {
                $cols = [System.Text.RegularExpressions.Regex]::Split($line.Trim(), '\s{2,}')
                if ($cols.Count -ge 2) {
                    $appName = $cols[0].Trim()
                    $appId   = $cols[1].Trim()
                    $version = if ($cols.Count -ge 3) { $cols[2].Trim() } else { "" }
                    $avail   = if ($cols.Count -ge 4) { $cols[3].Trim() } else { "" }
                    $hasUpdate = ($cols.Count -ge 5 -or ($cols.Count -eq 4 -and $avail -ne "winget" -and $avail -ne "msstore" -and $avail -ne ""))
                    $clean = Get-CleanAppName $appName

                    $itemObj = [PSCustomObject]@{
                        Name      = $appName
                        ID        = $appId
                        Version   = $version
                        Available = $avail
                        HasUpdate = $hasUpdate
                        CleanName = $clean
                    }

                    $installedList.Add($itemObj)
                    Set-PreferredMapEntry $idMap $appId $itemObj
                    Set-PreferredMapEntry $nameMap $appName $itemObj
                    if ($clean.Length -ge 3) { Set-PreferredMapEntry $cleanNameMap $clean $itemObj }
                }
            }
        }
    }

    # Bộ nhớ đệm tra cứu đa bí danh tốc độ cao (Multi-Alias Lookup Cache)
    $lookupCache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Find-InstalledAppFast {
        param($targetApp)

        $targetId = $targetApp.ID
        $cachedMatch = $null
        if ($lookupCache.TryGetValue($targetId, [ref]$cachedMatch)) {
            return $cachedMatch
        }

        # 1. Exact ID match (O(1))
        $match = $null
        if ($idMap.TryGetValue($targetId, [ref]$match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        # 2. Exact Name match (O(1))
        if ($targetApp.Name -and $nameMap.TryGetValue($targetApp.Name, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        # 3. Tra cứu danh sách Aliases trong O(1)
        if ($targetApp.Aliases) {
            foreach ($alias in $targetApp.Aliases) {
                if ([string]::IsNullOrWhiteSpace($alias)) { continue }
                if ($idMap.TryGetValue($alias, [ref]$match)) {
                    $lookupCache[$targetId] = $match
                    return $match
                }
                if ($nameMap.TryGetValue($alias, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
                    $lookupCache[$targetId] = $match
                    return $match
                }
                $cleanAlias = Get-CleanAppName $alias
                if ($cleanAlias.Length -ge 3 -and $cleanNameMap.TryGetValue($cleanAlias, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
                    $lookupCache[$targetId] = $match
                    return $match
                }
            }
        }

        # 4. Clean Name match (O(1))
        $cleanTarget = Get-CleanAppName $targetApp.Name
        if ($cleanTarget.Length -ge 3 -and $cleanNameMap.TryGetValue($cleanTarget, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        # 5. Fuzzy / Non-Alphanumeric Boundary Matching (khớp chuẩn cả chuỗi chứa dấu +, ., (x64), (x86))
        if ($targetApp.Aliases) {
            foreach ($alias in $targetApp.Aliases) {
                if ([string]::IsNullOrWhiteSpace($alias) -or $alias.Length -lt 4) { continue }
                $pattern = "(?<![a-zA-Z0-9])" + [System.Text.RegularExpressions.Regex]::Escape($alias) + "(?![a-zA-Z0-9])"
                foreach ($item in $installedList) {
                    if (-not (Test-MatchCompatible $targetApp $item)) { continue }
                    if ($item.ID -match $pattern -or $item.Name -match $pattern) {
                        $lookupCache[$targetId] = $item
                        return $item
                    }
                }
            }
        }

        if ($cleanTarget.Length -ge 4) {
            $patternClean = "(?<![a-zA-Z0-9])" + [System.Text.RegularExpressions.Regex]::Escape($cleanTarget) + "(?![a-zA-Z0-9])"
            foreach ($item in $installedList) {
                if (-not (Test-MatchCompatible $targetApp $item)) { continue }
                if ($item.CleanName -match $patternClean) {
                    $lookupCache[$targetId] = $item
                    return $item
                }
            }
        }

        $lookupCache[$targetId] = $null
        return $null
    }

    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    $countInstalled = 0
    $countLatest = 0
    $countOutdated = 0

    foreach ($row in $allItemBorders) {
        $app = $row.Tag.App
        $grid = $row.Child
        $tb = if ($row.Tag.NameText) { $row.Tag.NameText } else { $grid.Children[2] }
        $updateBadge = $row.Tag.UpdateBadge
        $updateText  = $row.Tag.UpdateText
        $idnPrefix = if ($app.IDn) { "[#$($app.IDn)] " } else { "" }

        $info = Find-InstalledAppFast $app

        if ($info) {
            $countInstalled++
            # Lưu lại ID phát hiện thực tế để phục vụ lệnh gỡ cài đặt chính xác
            $row.Tag.DetectedId = $info.ID
            $row.Tag.InstalledVersion = $info.Version

            if ($info.HasUpdate -eq $true) {
                # ── 🔴 BẢN CŨ: Tên ĐỎ + Pill phiên bản mới gọn gàng (không cắt mất tên App) ──
                $countOutdated++
                $row.Tag.Status = "OUTDATED"
                $row.Background = $script:brushNoneBg
                $tb.Foreground = $script:brushOutdatedFg
                $tb.Text = $app.Name
                $tb.TextDecorations = $null
                if ($updateBadge -and $updateText) {
                    $updateText.Text = if ($info.Available) { "↑ $($info.Available)" } else { "↑ Mới" }
                    $updateBadge.Visibility = [System.Windows.Visibility]::Visible
                }
                $tip = "$idnPrefix$($app.Name)`nĐang cài: $($info.Version)`nCó bản mới: $($info.Available)`nID phát hiện: $($info.ID)"
                $tb.ToolTip = $tip
                $row.ToolTip = $tip
            } else {
                # ── 🟢 BẢN MỚI NHẤT: Tên XANH LÁ ──
                $countLatest++
                $row.Tag.Status = "LATEST"
                $row.Background = $script:brushNoneBg
                $tb.Foreground = $script:brushLatestFg
                $tb.Text = $app.Name
                $tb.TextDecorations = $null
                if ($updateBadge) { $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed }
                $tip = "$idnPrefix$($app.Name)`nPhiên bản: $($info.Version) (Mới nhất)`nID phát hiện: $($info.ID)"
                $tb.ToolTip = $tip
                $row.ToolTip = $tip
            }
        } else {
            # ── ⚪ CHƯA CÀI ĐẶT: Tên TRẮNG + Nền trong suốt ──
            $row.Tag.Status = "NONE"
            $row.Tag.DetectedId = $null
            $row.Tag.InstalledVersion = $null
            $row.Background = $script:brushNoneBg
            $tb.Foreground = $script:brushNoneFg
            $tb.Text = $app.Name
            $tb.TextDecorations = $null
            if ($updateBadge) { $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed }
            $tip = "$idnPrefix$($app.Name)`nTrạng thái: Chưa cài đặt`nID: $($app.ID)"
            $tb.ToolTip = $tip
            $row.ToolTip = $tip
        }
    }

    $summary = "Đã quét xong: $countInstalled app đã cài ($countLatest bản mới nhất [🟢 XANH], $countOutdated bản cũ [🔴 ĐỎ])"
    Log-Text "[✓] $summary"
    if ($txtStatus) {
        $txtStatus.Text = "$countInstalled app đã cài ($countLatest mới / $countOutdated cũ)"
    }
}

# ── FUNCTION: CÁC TIỆN ÍCH QUẢN LÝ & GỠ LỖI DRIVER ──

function Find-FaultyPnpDevices {
    <#
    .SYNOPSIS
        Quét và liệt kê tất cả các thiết bị phần cứng bị lỗi, thiếu driver hoặc chấm than vàng qua ConfigManagerErrorCode.
    #>
    try {
        return @(Get-PnpDevice -ErrorAction Stop | Where-Object {
            $_.Present -eq $true -and ($_.Status -ne 'OK' -or ($null -ne $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0))
        })
    } catch {
        Log-Text "[!] Lỗi khi quét danh sách PnpDevice: $($_.Exception.Message)"
        return @()
    }
}

function Invoke-PnpDeviceRescan {
    <#
    .SYNOPSIS
        Buộc Windows gửi tín hiệu quét lại toàn bộ phần cứng cắm trên máy.
    #>
    $code = Run-CliStream "pnputil.exe" "/scan-devices"
    if ($code -eq 0) {
        Log-Text "[✓] Quét lại thiết bị phần cứng PnP thành công (ExitCode: 0)."
    } else {
        Log-Text "[!] Quét thiết bị phần cứng PnP thất bại hoặc gặp lỗi (ExitCode: $code)."
    }
    return $code
}

function Invoke-PnpDriverStoreCleanup {
    <#
    .SYNOPSIS
        Quét và dọn dẹp các gói Driver OEM của bên thứ ba không còn được sử dụng trong DriverStore bằng pnputil.
    #>
    Log-Text "[*] Đang phân tích danh sách gói Driver OEM bên thứ ba (pnputil /enum-drivers)..."
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "pnputil.exe"
        $pinfo.Arguments = "/enum-drivers"
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($pinfo)
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()
        $raw = $outTask.Result

        # Tìm các Published Name: oemX.inf
        $matches = [System.Text.RegularExpressions.Regex]::Matches($raw, '(?i)(?:Published Name|Tên đã phát hành):\s*(oem\d+\.inf)')
        $oemList = @($matches | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } | Select-Object -Unique)

        if ($oemList.Count -eq 0) {
            Log-Text "[✓] Không tìm thấy gói driver OEM nào trong DriverStore."
            return
        }

        Log-Text "[*] Tìm thấy $($oemList.Count) gói driver OEM. Bắt đầu dọn dẹp an toàn (không xóa driver đang sử dụng)..."
        $deletedCount = 0
        $inUseCount = 0
        $errorCount = 0

        foreach ($inf in $oemList) {
            # Chạy xóa an toàn không dùng /force để Windows tự bảo vệ các driver đang được phần cứng sử dụng
            try {
                $delPinfo = New-Object System.Diagnostics.ProcessStartInfo
                $delPinfo.FileName = "pnputil.exe"
                $delPinfo.Arguments = "/delete-driver $inf"
                $delPinfo.RedirectStandardOutput = $true
                $delPinfo.RedirectStandardError = $true
                $delPinfo.UseShellExecute = $false
                $delPinfo.CreateNoWindow = $true
                $delP = [System.Diagnostics.Process]::Start($delPinfo)

                $delOutTask = $delP.StandardOutput.ReadToEndAsync()
                $delErrTask = $delP.StandardError.ReadToEndAsync()
                $delP.WaitForExit()

                $delOut = $delOutTask.Result
                $delErr = $delErrTask.Result
                $combined = ($delOut + "`n" + $delErr).Trim()

                if ($delP.ExitCode -eq 0 -or $combined -match 'deleted successfully|đã xóa thành công') {
                    $deletedCount++
                    Log-Text "   [✓ Đã dọn] $inf"
                } elseif ($combined -match 'installed using the specified INF|đang được sử dụng|in use|bị từ chối') {
                    $inUseCount++
                } else {
                    $errorCount++
                    $errDetail = ($combined -split "`r?`n" | Where-Object { $_ -match 'failed|lỗi|error' } | Select-Object -First 1)
                    if (-not $errDetail) { $errDetail = "ExitCode $($delP.ExitCode)" }
                    Log-Text "   [⚠️ Lỗi gói $inf] $errDetail"
                }
            } catch {
                $errorCount++
                Log-Text "   [!] Lỗi ngoại lệ khi xử lý ${inf}: $($_.Exception.Message)"
            }
            [System.Windows.Forms.Application]::DoEvents()
        }

        if ($deletedCount -gt 0) {
            Log-Text "[✓] Hoàn tất! Đã giải phóng $deletedCount gói driver OEM cũ không còn sử dụng ($inUseCount gói đang được phần cứng sử dụng an toàn)."
        } else {
            Log-Text "[✓] Toàn bộ $($oemList.Count) gói driver OEM đều đang được các thiết bị phần cứng sử dụng an toàn."
        }
        if ($errorCount -gt 0) {
            Log-Text "[!] Có $errorCount gói driver gặp lỗi trong quá trình xử lý."
        }
    } catch {
        Log-Text "[!] Lỗi khi dọn dẹp DriverStore: $($_.Exception.Message)"
    }
}

function Invoke-DismComponentCleanup {
    <#
    .SYNOPSIS
        Dọn dẹp và giải phóng kho linh kiện Windows qua DISM Component Cleanup.
    #>
    Log-Text "[⚠️] CẢNH BÁO: Tùy chọn /ResetBase sẽ xóa vĩnh viễn các bản cập nhật cũ đã bị thay thế trong WinSxS."
    Log-Text "[*] Sau khi hoàn tất thao tác này, bạn SẼ KHÔNG THỂ gỡ cài đặt (rollback) các bản Windows Update hiện tại."
    Log-Text "[*] Đang tiến hành dọn dẹp và nén kho linh kiện WinSxS qua DISM..."
    $code = Run-CliStream "dism.exe" "/Online /Cleanup-Image /StartComponentCleanup /ResetBase"
    if ($code -eq 0) {
        Log-Text "[✓] Dọn dẹp kho linh kiện WinSxS hoàn tất thành công (ExitCode: 0)."
    } else {
        Log-Text "[!] Dọn dẹp kho linh kiện WinSxS thất bại hoặc bị gián đoạn (ExitCode: $code)."
    }
    return $code
}

function Export-SystemDriversBackup {
    <#
    .SYNOPSIS
        Sao lưu toàn bộ Driver của máy ra thư mục chỉ định.
    #>
    param([string]$Destination = "C:\Backup_Drivers")

    if (-not (Test-Path -LiteralPath $Destination)) {
        try {
            New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop | Out-Null
        } catch {
            Log-Text "[!] Không thể tạo thư mục sao lưu '$Destination': $($_.Exception.Message)"
            return $false
        }
    }

    try {
        Export-WindowsDriver -Online -Destination $Destination -ErrorAction Stop | Out-Null
        Log-Text "[✓] Sao lưu toàn bộ driver thành công qua Export-WindowsDriver."
        return $true
    } catch {
        Log-Text "[*] Export-WindowsDriver không khả dụng hoặc bị từ chối, chuyển sang pnputil.exe..."
        $exitCode = Run-CliStream "pnputil.exe" "/export-driver * `"$Destination`""
        if ($exitCode -eq 0) {
            Log-Text "[✓] Sao lưu toàn bộ driver thành công qua pnputil.exe (ExitCode: 0)."
            return $true
        } else {
            Log-Text "[!] Sao lưu driver qua pnputil.exe thất bại (ExitCode: $exitCode)."
            return $false
        }
    }
}

# ── FUNCTION: CÁC TIỆN ÍCH SỬA LỖI HỆ THỐNG (SYSTEM REPAIRS) ──

function Reset-WindowsUpdateEngine {
    <#
    .SYNOPSIS
        Khởi tạo lại toàn bộ dịch vụ Windows Update và xóa cache bị lỗi/kẹt.
    #>
    Log-Text "[*] Đang dừng các dịch vụ Windows Update, BITS, DoSvc & TrustedInstaller..."
    $services = @("wuauserv", "bits", "cryptsvc", "dosvc", "trustedinstaller")
    foreach ($s in $services) {
        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
    }

    # Chờ tiến trình giải phóng hoàn toàn các handle tệp tin
    Start-Sleep -Milliseconds 1500

    Log-Text "[*] Đang làm mới bộ nhớ đệm SoftwareDistribution và Catroot2..."
    $sdPath = "C:\Windows\SoftwareDistribution"
    $sdRenamed = $true
    if (Test-Path -LiteralPath $sdPath) {
        $backupSD = "SoftwareDistribution.bak_$(Get-Random)"
        Rename-Item -LiteralPath $sdPath -NewName $backupSD -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $sdPath) {
            $sdRenamed = $false
            Log-Text "[⚠️] Không thể đổi tên SoftwareDistribution (tệp đang bị khóa bởi tiến trình khác)."
        }
    }

    $crPath = "C:\Windows\System32\catroot2"
    $crRenamed = $true
    if (Test-Path -LiteralPath $crPath) {
        $backupCR = "catroot2.bak_$(Get-Random)"
        Rename-Item -LiteralPath $crPath -NewName $backupCR -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $crPath) {
            $crRenamed = $false
            Log-Text "[⚠️] Không thể đổi tên catroot2 (tệp đang bị khóa)."
        }
    }

    Log-Text "[*] Khởi động lại các dịch vụ hệ thống..."
    Start-Service -Name "cryptsvc" -ErrorAction SilentlyContinue
    Start-Service -Name "bits" -ErrorAction SilentlyContinue
    Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    Start-Service -Name "dosvc" -ErrorAction SilentlyContinue

    if ($sdRenamed -and $crRenamed) {
        Log-Text "[✓] Đã khởi tạo lại dịch vụ Windows Update và xóa sạch cache thành công!"
    } else {
        Log-Text "[*] Đã đặt lại dịch vụ Windows Update (một số thư mục cache đang được hệ thống bảo vệ)."
    }
}

function Invoke-WindowsUpdateScan {
    <#
    .SYNOPSIS
        Kích hoạt quét tìm kiếm bản cập nhật Windows qua COM API chính thức và Windows Settings.
    #>
    Log-Text "[*] Đang gửi tín hiệu yêu cầu Windows tìm kiếm bản cập nhật mới..."
    try {
        $au = New-Object -ComObject Microsoft.Update.AutoUpdate
        $au.DetectNow()
        Log-Text "[✓] Đã kích hoạt Microsoft.Update.AutoUpdate.DetectNow() thành công."
    } catch {
        Log-Text "[*] COM AutoUpdate không phản hồi, mở trang cập nhật hệ thống..."
    }

    try {
        Start-Process "ms-settings:windowsupdate-action" -ErrorAction SilentlyContinue
    } catch {}
}

function Invoke-SystemFileCheck {
    <#
    .SYNOPSIS
        Chạy SFC Scan kiểm tra toàn vẹn file hệ thống.
    #>
    Log-Text "[*] Đang khởi chạy System File Checker (sfc /scannow)..."
    $code = Run-CliStream "sfc.exe" "/scannow"
    if ($code -eq 0) {
        Log-Text "[✓] SFC Scan hoàn tất: Toàn vẹn tệp hệ thống đạt chuẩn (ExitCode: 0)."
    } else {
        Log-Text "[!] SFC Scan phát hiện lỗi hoặc không thể sửa chữa toàn bộ tệp hệ thống (ExitCode: $code)."
    }
    return $code
}

function Invoke-DismRestoreHealth {
    <#
    .SYNOPSIS
        Khôi phục kho linh kiện Windows qua DISM RestoreHealth từ server Microsoft.
    #>
    Log-Text "[*] Đang khởi chạy DISM RestoreHealth khôi phục kho linh kiện hệ thống..."
    $code = Run-CliStream "dism.exe" "/Online /Cleanup-Image /RestoreHealth"
    if ($code -eq 0) {
        Log-Text "[✓] DISM RestoreHealth hoàn tất thành công (ExitCode: 0)."
    } else {
        Log-Text "[!] DISM RestoreHealth thất bại hoặc gặp sự cố (ExitCode: $code). Hãy kiểm tra kết nối mạng hoặc nguồn tệp hệ thống."
    }
    return $code
}

function Clear-DnsResolverCache {
    <#
    .SYNOPSIS
        Làm mới bộ nhớ đệm DNS.
    #>
    $code = Run-CliStream "ipconfig.exe" "/flushdns"
    if ($code -eq 0) {
        Log-Text "[✓] Làm mới bộ nhớ đệm DNS thành công (ExitCode: 0)."
    } else {
        Log-Text "[!] Làm mới bộ nhớ đệm DNS thất bại (ExitCode: $code)."
    }
    return $code
}

function Reset-NetworkInterfaceStack {
    <#
    .SYNOPSIS
        Khôi phục danh mục Winsock Catalog và TCP/IP Stack.
    #>
    $codeWinsock = Run-CliStream "netsh.exe" "winsock reset"
    $codeTcpIp = Run-CliStream "netsh.exe" "int ip reset"
    if ($codeWinsock -eq 0 -and $codeTcpIp -eq 0) {
        Log-Text "[✓] Đặt lại Winsock Catalog và TCP/IP Stack thành công (ExitCode: 0). Khuyên bạn nên khởi động lại máy."
    } else {
        Log-Text "[!] Đặt lại mạng gặp lỗi (Winsock ExitCode: $codeWinsock, TCP/IP ExitCode: $codeTcpIp)."
    }
    return ($codeWinsock -eq 0 -and $codeTcpIp -eq 0)
}

function Clear-SystemTempFiles {
    <#
    .SYNOPSIS
        Dọn dẹp tệp tạm thời trong thư mục User Temp và Windows Temp.
    #>
    $tempPaths = @($env:TEMP, "C:\Windows\Temp")
    foreach ($p in $tempPaths) {
        if (Test-Path -LiteralPath $p) {
            Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Clear-SystemEventLogs {
    <#
    .SYNOPSIS
        Xóa sạch toàn bộ nhật ký sự kiện Windows Event Logs.
    #>
    Log-Text "[*] Đang quét và dọn sạch nhật ký sự kiện Windows Event Logs..."
    Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName)
        } catch {}
    }
    Log-Text "[✓] Toàn bộ Windows Event Logs đã được làm sạch."
}

# 6. ENTRYPOINT & CONTROLLER
# ── KHỞI TẠO CÁC CONTROL TỪ XAML ──
$reader = New-Object System.Xml.XmlNodeReader $XAML
$window = [Windows.Markup.XamlReader]::Load($reader)

# Tự động co kích thước cửa sổ vừa với vùng làm việc màn hình (hỗ trợ laptop / DPI 125%-150%)
try {
    $wa = [System.Windows.SystemParameters]::WorkArea
    if ($wa.Width -gt 0 -and $window.Width -gt ($wa.Width - 24)) {
        $window.Width = [math]::Max($window.MinWidth, $wa.Width - 24)
    }
    if ($wa.Height -gt 0 -and $window.Height -gt ($wa.Height - 24)) {
        $window.Height = [math]::Max(560, $wa.Height - 24)
        $window.MinHeight = [math]::Min($window.MinHeight, $window.Height)
    }
} catch {}

# Các Control chính
$MainTabControl    = $window.FindName("MainTabControl")
$txtStatus         = $window.FindName("txtStatus")
$progressBar       = $window.FindName("progressBar")
$txtLog            = $window.FindName("txtLog")
$txtSelectionCount = $window.FindName("txtSelectionCount")
$cardsContainer    = $window.FindName("CardsContainer")
$rowDefTerminal    = $window.FindName("rowDefTerminal")
$btnToggleTerminal = $window.FindName("btnToggleTerminal")

# Bảng màu Frozen Brush tĩnh tái sử dụng tối đa, loại trừ cấp phát bộ nhớ rác (GC)
$script:brushNavActive   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushNavActive.Freeze()
$script:brushNavInactive = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x64, 0x74, 0x8B)); $script:brushNavInactive.Freeze()
$script:brushTransparent = [System.Windows.Media.Brushes]::Transparent

$script:brushCardBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x11, 0x17, 0x22)); $script:brushCardBg.Freeze()
$script:brushCardBorder  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1C, 0x25, 0x36)); $script:brushCardBorder.Freeze()
$script:brushHeaderFg    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x7D, 0xD3, 0xFC)); $script:brushHeaderFg.Freeze()
$script:brushHeaderCntBg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x16, 0x1E, 0x2E)); $script:brushHeaderCntBg.Freeze()
$script:brushHeaderCntFg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x64, 0x74, 0x8B)); $script:brushHeaderCntFg.Freeze()
$script:brushSeparator   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1A, 0x22, 0x32)); $script:brushSeparator.Freeze()

$script:brushRowHover    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x19, 0x22, 0x34)); $script:brushRowHover.Freeze()
$script:brushTextWhite   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF1, 0xF5, 0xF9)); $script:brushTextWhite.Freeze()
$script:fontSegoeEmoji   = New-Object System.Windows.Media.FontFamily("Segoe UI Emoji, Segoe UI Symbol, Arial")
$script:fontSegoeUI      = New-Object System.Windows.Media.FontFamily("Segoe UI Variable Text, Segoe UI, Arial")

# Bảng màu cho Button Link Website ngoài cùng bên phải (Tối giản chuẩn WinUtil)
$script:brushLinkBtnBg        = [System.Windows.Media.Brushes]::Transparent
$script:brushLinkBtnBorder    = [System.Windows.Media.Brushes]::Transparent
$script:brushLinkBtnFg        = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x52, 0x60, 0x76)); $script:brushLinkBtnFg.Freeze()
$script:brushLinkBtnRowHover  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x94, 0xA3, 0xB8)); $script:brushLinkBtnRowHover.Freeze()

$script:brushLinkBtnHoverBg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1E, 0x29, 0x3B)); $script:brushLinkBtnHoverBg.Freeze()
$script:brushLinkBtnHoverBdr  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushLinkBtnHoverBdr.Freeze()
$script:brushLinkBtnHoverFg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushLinkBtnHoverFg.Freeze()

# Nền icon sương mờ siêu nhẹ (~5.5% trắng, không viền) & Update Pill gọn gàng
$script:brushIconBadgeBg        = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(14, 255, 255, 255)); $script:brushIconBadgeBg.Freeze()
$script:brushIconBadgeBorder    = [System.Windows.Media.Brushes]::Transparent
$script:cornerIconBadge         = New-Object System.Windows.CornerRadius(5)
$script:brushUpdateBadgeBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(28, 0xF8, 0x71, 0x71)); $script:brushUpdateBadgeBg.Freeze()
$script:brushUpdateBadgeBorder  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(85, 0xF8, 0x71, 0x71)); $script:brushUpdateBadgeBorder.Freeze()
$script:brushUpdateBadgeFg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xFC, 0xA5, 0xA5)); $script:brushUpdateBadgeFg.Freeze()

# Cấu trúc hình học tái sử dụng (Shared Layout Geometries)
$marginCardBorder = New-Object System.Windows.Thickness(4)
$paddingCard      = New-Object System.Windows.Thickness(10, 8, 10, 10)
$marginHeaderGrid = New-Object System.Windows.Thickness(2, 0, 2, 6)
$marginSeparator  = New-Object System.Windows.Thickness(0, 1, 0, 5)
$marginRowBorder  = New-Object System.Windows.Thickness(0, 1, 0, 1)
$paddingRow       = New-Object System.Windows.Thickness(5, 0, 4, 0)
$marginIcon       = New-Object System.Windows.Thickness(7, 0, 8, 0)
$cornerCard       = New-Object System.Windows.CornerRadius(8)
$cornerRow        = New-Object System.Windows.CornerRadius(5)
$thicknessZero    = New-Object System.Windows.Thickness(0)
$thicknessOne     = New-Object System.Windows.Thickness(1)

# Thư mục lưu cache biểu tượng ứng dụng cục bộ
$iconsCacheDir = Join-Path $env:LOCALAPPDATA "DuckUtil\Icons"
if (-not (Test-Path -LiteralPath $iconsCacheDir)) {
    try { New-Item -ItemType Directory -Path $iconsCacheDir -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
} else {
    # Tự động dọn dẹp các icon cache rỗng / bị hỏng / quá nhỏ từ phiên bản cũ
    try {
        Get-ChildItem -Path $iconsCacheDir -Filter "*.png" -ErrorAction SilentlyContinue | Where-Object {
            $_.Length -le 230 -or $_.Length -eq 588
        } | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {}

    # Tự động đồng bộ cache icon dựa trên chữ ký SHA256 của toàn bộ URL biểu tượng trong catalog
    try {
        $sigSource = if ($AppCatalog) {
            ($AppCatalog | ForEach-Object { "$($_.ID)|$($_.IconUrl)|$($_.Domain)" }) -join "`n"
        } else {
            "v3.4"
        }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $sigBytes = [System.Text.Encoding]::UTF8.GetBytes($sigSource)
            $currentSig = [System.BitConverter]::ToString($sha.ComputeHash($sigBytes)).Replace("-", "")
        } finally {
            $sha.Dispose()
        }
        $sigFile = Join-Path $iconsCacheDir "cache.icons.sha256"
        $rawSig = if (Test-Path -LiteralPath $sigFile) {
            Get-Content -LiteralPath $sigFile -Raw -ErrorAction SilentlyContinue
        } else {
            $null
        }
        $savedSig = if ($null -ne $rawSig) { "$rawSig".Trim() } else { "" }
        if ($savedSig -ne $currentSig) {
            Get-ChildItem -Path $iconsCacheDir -Filter "*.png" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Set-Content -LiteralPath $sigFile -Value $currentSig -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Save-BitmapToCacheAtomic {
    param($BitmapSource, [string]$DestPath)
    if (-not $BitmapSource -or [string]::IsNullOrWhiteSpace($DestPath) -or (Test-Path -LiteralPath $DestPath)) { return }
    try {
        if ($BitmapSource.PixelWidth -le 0 -or $BitmapSource.PixelHeight -le 0) { return }
        $tmpPath = "$DestPath.$([guid]::NewGuid().ToString('N')).tmp"
        $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($BitmapSource))
        $fs = $null
        try {
            $fs = [System.IO.File]::OpenWrite($tmpPath)
            $encoder.Save($fs)
        } finally {
            if ($fs) { $fs.Dispose() }
        }
        if ((Test-Path -LiteralPath $tmpPath) -and (Get-Item -LiteralPath $tmpPath).Length -gt 64) {
            Move-Item -LiteralPath $tmpPath -Destination $DestPath -Force -ErrorAction SilentlyContinue
        } elseif (Test-Path -LiteralPath $tmpPath) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
    } catch {
        if ($tmpPath -and (Test-Path -LiteralPath $tmpPath)) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Trình khóa thực thi đơn nhất (Re-entrancy Guard) chống xung đột tiến trình
$script:isActionRunning = $false

function Invoke-GuardedAction {
    param(
        [string]$ActionName,
        [scriptblock]$Action,
        [switch]$DeferExpand
    )
    if ($script:isActionRunning) {
        Log-Text "[⚠️] Đang có một tác vụ khác đang thực thi ($ActionName). Vui lòng đợi!"
        return
    }
    if (-not $DeferExpand) {
        # Tự động mở rộng Terminal Log khi bắt đầu thực thi hành động để người dùng theo dõi tiến trình
        Expand-TerminalLog
    }
    $script:isActionRunning = $true
    try {
        & $Action
    } catch {
        Log-Text "[!] Lỗi khi thực hiện '$ActionName': $($_.Exception.Message)"
    } finally {
        $script:isActionRunning = $false
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# Hàm an toàn gắn sự kiện Click cho nút
function Register-Click {
    param([string]$ButtonName, [scriptblock]$Action)
    $btn = $window.FindName($ButtonName)
    if ($btn) {
        $btn.Add_Click($Action)
    } else {
        Write-Warning "Không tìm thấy nút trong XAML: $ButtonName"
    }
}

# ── LOGIC ĐIỀU HƯỚNG TAB CHÍNH ──
$navBtnApps    = $window.FindName("navBtnApps")
$navBtnRepair  = $window.FindName("navBtnRepair")
$navBtnDrivers = $window.FindName("navBtnDrivers")

function Set-ActiveTab {
    param([int]$index, $activeBtn)
    if ($MainTabControl) {
        $MainTabControl.SelectedIndex = $index
    }

    $buttons = @($navBtnApps, $navBtnRepair, $navBtnDrivers)
    foreach ($btn in $buttons) {
        if ($btn) {
            $btn.Foreground  = $script:brushNavInactive
            $btn.BorderBrush = $script:brushTransparent
        }
    }

    if ($activeBtn) {
        $activeBtn.Foreground  = $script:brushNavActive
        $activeBtn.BorderBrush = $script:brushNavActive
    }
}

Register-Click "navBtnApps"    { Set-ActiveTab 0 $navBtnApps }
Register-Click "navBtnRepair"  { Set-ActiveTab 1 $navBtnRepair }
Register-Click "navBtnDrivers" { Set-ActiveTab 2 $navBtnDrivers }

# Đồng bộ trạng thái tab khởi tạo ban đầu (Section 3.4)
Set-ActiveTab 0 $navBtnApps

# ── LOGIC THU GỌN / MỞ RỘNG TERMINAL LOG (MẶC ĐỊNH THU GỌN KHI KHỞI CHẠY) ──
$script:isTerminalCollapsed = $true

function Expand-TerminalLog {
    if ($script:isTerminalCollapsed -and $btnToggleTerminal -and $rowDefTerminal) {
        $rowDefTerminal.Height = New-Object System.Windows.GridLength(150, [System.Windows.GridUnitType]::Pixel)
        if ($txtLog) { $txtLog.Visibility = [System.Windows.Visibility]::Visible }
        $btnToggleTerminal.Content = "▼ Thu gọn"
        $btnToggleTerminal.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8))
        $script:isTerminalCollapsed = $false
    }
}

if ($btnToggleTerminal -and $rowDefTerminal) {
    $btnToggleTerminal.Add_Click({
        if ($script:isTerminalCollapsed) {
            # Mở rộng lại 150px
            Expand-TerminalLog
        } else {
            # Thu gọn (chỉ giữ thanh tiêu đề)
            $rowDefTerminal.Height = [System.Windows.GridLength]::Auto
            if ($txtLog) { $txtLog.Visibility = [System.Windows.Visibility]::Collapsed }
            $btnToggleTerminal.Content = "▲ Mở rộng"
            $btnToggleTerminal.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x34, 0xD3, 0x99))
            $script:isTerminalCollapsed = $true
        }
    })
}

# Hàm ánh xạ icon emoji/glyph đặc trưng cho ứng dụng và danh mục (hiển thị tức thì 0ms, không bao giờ bị khuyết icon)
function Get-AppFallbackGlyph {
    param([string]$AppName, [string]$Category)
    $nameLower = if ($AppName) { $AppName.ToLowerInvariant() } else { "" }
    if ($nameLower -match 'chrome') { return [char]::ConvertFromUtf32(0x1F310) }
    if ($nameLower -match 'firefox') { return [char]::ConvertFromUtf32(0x1F98A) }
    if ($nameLower -match 'brave') { return [char]::ConvertFromUtf32(0x1F981) }
    if ($nameLower -match 'tor') { return [char]::ConvertFromUtf32(0x1F9C5) }
    if ($nameLower -match 'opera') { return [char]::ConvertFromUtf32(0x1F534) }
    if ($nameLower -match 'vivaldi') { return [char]::ConvertFromUtf32(0x1F3AD) }
    if ($nameLower -match 'librewolf') { return [char]::ConvertFromUtf32(0x1F43A) }
    if ($nameLower -match 'discord') { return [char]::ConvertFromUtf32(0x1F4AC) }
    if ($nameLower -match 'telegram') { return [char]::ConvertFromUtf32(0x2708) }
    if ($nameLower -match 'zalo') { return [char]::ConvertFromUtf32(0x1F4AC) }
    if ($nameLower -match 'slack') { return [char]::ConvertFromUtf32(0x1F4BC) }
    if ($nameLower -match 'teams') { return [char]::ConvertFromUtf32(0x1F465) }
    if ($nameLower -match 'whatsapp') { return [char]::ConvertFromUtf32(0x1F4F1) }
    if ($nameLower -match 'zoom') { return [char]::ConvertFromUtf32(0x1F4F9) }
    if ($nameLower -match 'vs code|visual studio') { return [char]::ConvertFromUtf32(0x1F4BB) }
    if ($nameLower -match 'git') { return [char]::ConvertFromUtf32(0x1F419) }
    if ($nameLower -match 'terminal') { return [char]::ConvertFromUtf32(0x1F4DF) }
    if ($nameLower -match 'python') { return [char]::ConvertFromUtf32(0x1F40D) }
    if ($nameLower -match 'node') { return [char]::ConvertFromUtf32(0x1F7E2) }
    if ($nameLower -match 'docker') { return [char]::ConvertFromUtf32(0x1F433) }
    if ($nameLower -match 'notepad\+\+') { return [char]::ConvertFromUtf32(0x1F4DD) }
    if ($nameLower -match 'postman') { return [char]::ConvertFromUtf32(0x1F680) }
    if ($nameLower -match 'dbeaver') { return [char]::ConvertFromUtf32(0x1F9AB) }
    if ($nameLower -match 'rustup|\brust\b') { return [char]::ConvertFromUtf32(0x1F980) }
    if ($nameLower -match 'go lang|golang') { return [char]::ConvertFromUtf32(0x1F439) }
    if ($nameLower -match '7-zip') { return [char]::ConvertFromUtf32(0x1F5DC) }
    if ($nameLower -match 'winrar') { return [char]::ConvertFromUtf32(0x1F4E6) }
    if ($nameLower -match 'everything') { return [char]::ConvertFromUtf32(0x1F50D) }
    if ($nameLower -match 'powertoys') { return [char]::ConvertFromUtf32(0x26A1) }
    if ($nameLower -match 'flow launcher') { return [char]::ConvertFromUtf32(0x1F680) }
    if ($nameLower -match 'revo') { return [char]::ConvertFromUtf32(0x1F9F9) }
    if ($nameLower -match 'treesize') { return [char]::ConvertFromUtf32(0x1F4CA) }
    if ($nameLower -match 'sharex') { return [char]::ConvertFromUtf32(0x1F4F8) }
    if ($nameLower -match 'bleachbit') { return [char]::ConvertFromUtf32(0x1F9FC) }
    if ($nameLower -match 'fancontrol') { return [char]::ConvertFromUtf32(0x1F300) }
    if ($nameLower -match 'spotify') { return [char]::ConvertFromUtf32(0x1F3B5) }
    if ($nameLower -match 'vlc') { return [char]::ConvertFromUtf32(0x1F538) }
    if ($nameLower -match 'obs') { return [char]::ConvertFromUtf32(0x1F3AC) }
    if ($nameLower -match 'steam') { return [char]::ConvertFromUtf32(0x1F579) }
    if ($nameLower -match 'epic') { return [char]::ConvertFromUtf32(0x1F3AE) }
    if ($nameLower -match 'onedrive|gdrive|drive|dropbox') { return [char]::ConvertFromUtf32(0x2601) }
    if ($nameLower -match 'rustdesk|anydesk|ultraviewer|teamviewer') { return [char]::ConvertFromUtf32(0x1F5A5) }
    if ($nameLower -match 'afterburner') { return [char]::ConvertFromUtf32(0x26A1) }
    if ($nameLower -match 'gimp|krita') { return [char]::ConvertFromUtf32(0x1F3A8) }
    if ($nameLower -match 'blender') { return [char]::ConvertFromUtf32(0x1F3A8) }
    if ($nameLower -match 'inkscape') { return [char]::ConvertFromUtf32(0x2712) }
    if ($nameLower -match 'java|openjdk|temurin') { return [char]::ConvertFromUtf32(0x2615) }
    if ($nameLower -match '\.net|desktopruntime') { return [char]::ConvertFromUtf32(0x1F7E3) }
    if ($nameLower -match 'vc\+\+|visual c\+\+') { return [char]::ConvertFromUtf32(0x2699) }
    if ($nameLower -match 'directx') { return [char]::ConvertFromUtf32(0x1F3AE) }
    if ($nameLower -match 'cpu-z|hwmonitor') { return [char]::ConvertFromUtf32(0x1F39B) }

    if ($Category -match 'Web|Browser') { return [char]::ConvertFromUtf32(0x1F310) }
    if ($Category -match 'Chat|Liên|Communication') { return [char]::ConvertFromUtf32(0x1F4AC) }
    if ($Category -match 'Remote') { return [char]::ConvertFromUtf32(0x1F5A5) }
    if ($Category -match 'Dev|Triển|Development') { return [char]::ConvertFromUtf32(0x1F4BB) }
    if ($Category -match 'Java') { return [char]::ConvertFromUtf32(0x2615) }
    if ($Category -match '\.NET') { return [char]::ConvertFromUtf32(0x1F7E3) }
    if ($Category -match 'Hardware|Monitoring') { return [char]::ConvertFromUtf32(0x1F39B) }
    if ($Category -match 'C\+\+|System Runtimes') { return [char]::ConvertFromUtf32(0x2699) }
    if ($Category -match 'Tiện|Thống|Utilities|Utility') { return [char]::ConvertFromUtf32(0x1F6E0) }
    if ($Category -match 'Graphic|Design') { return [char]::ConvertFromUtf32(0x1F3A8) }
    if ($Category -match 'Audio|Video|Media') { return [char]::ConvertFromUtf32(0x1F3AC) }
    if ($Category -match 'Phòng|Liệu|Documents|Office') { return [char]::ConvertFromUtf32(0x1F4C4) }
    if ($Category -match 'Chơi|Game|Launcher') { return [char]::ConvertFromUtf32(0x1F3AE) }
    if ($Category -match 'Trữ|Tệp|Storage|File|Transfer') { return [char]::ConvertFromUtf32(0x2601) }
    if ($Category -match 'Security|Bảo Mật|Network|Mạng') { return [char]::ConvertFromUtf32(0x1F6E1) }
    if ($Category -match 'Core|Runtimes|Thư Viện') { return [char]::ConvertFromUtf32(0x2699) }

    return [char]::ConvertFromUtf32(0x1F4E6)
}

# ── MASONRY CÂN BẰNG CHIỀU CAO 4 CỘT TỰ ĐỘNG (LOẠI BỎ TRIỆT ĐỂ KHOẢNG TRỐNG) ──
$script:colHeights = @(0, 0, 0, 0)

# ── SINH CÁC CARD ỨNG DỤNG BỐ CỤC 4 CỘT HIỆU NĂNG CAO ──
$allCheckBoxes   = [System.Collections.Generic.List[object]]::new()
$allItemBorders  = [System.Collections.Generic.List[object]]::new()

$categories = $AppCatalog | Select-Object -ExpandProperty Category -Unique

$script:suppressSelectionCount = $false

function Update-SelectionCount {
    if ($script:suppressSelectionCount) { return }
    $selectedCount = 0
    foreach ($cb in $allCheckBoxes) {
        if ($cb.IsChecked -eq $true) {
            $selectedCount++
        }
    }
    if ($txtSelectionCount) {
        $txtSelectionCount.Text = "$selectedCount app được chọn"
    }
}

# 4 cột dọc phân bố đều các card danh mục (Chiều cao tự nhiên, không cố định, triệt tiêu khoảng trống thừa)
$cardCols = @(
    $window.FindName("CardsCol0"),
    $window.FindName("CardsCol1"),
    $window.FindName("CardsCol2"),
    $window.FindName("CardsCol3")
)

# Cache BitmapImage từ xa theo URL trong RAM để cắt giảm triệt để request mạng trùng lặp
$script:remoteBmpCache = [System.Collections.Generic.Dictionary[string, System.Windows.Media.Imaging.BitmapImage]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($cat in $categories) {
    $cardBorder = New-Object System.Windows.Controls.Border
    $cardBorder.Background = $script:brushCardBg
    $cardBorder.BorderBrush = $script:brushCardBorder
    $cardBorder.BorderThickness = $thicknessOne
    $cardBorder.CornerRadius = $cornerCard
    $cardBorder.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
    $cardBorder.Padding = $paddingCard
    $cardBorder.Height = [double]::NaN
    $cardBorder.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch

    $cardStack = New-Object System.Windows.Controls.StackPanel
    $appsInCat = @($AppCatalog | Where-Object { $_.Category -eq $cat })

    # Header Card (Tiêu đề bên trái + Badge đếm tối giản bên phải)
    $headerGrid = New-Object System.Windows.Controls.Grid
    $headerGrid.Margin = $marginHeaderGrid

    $headerText = New-Object System.Windows.Controls.TextBlock
    $headerText.Text = $cat
    $headerText.FontSize = 12
    $headerText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $headerText.Foreground = $script:brushHeaderFg
    $headerText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $headerText.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    $headerGrid.Children.Add($headerText) | Out-Null

    $headerCountBadge = New-Object System.Windows.Controls.Border
    $headerCountBadge.Background = $script:brushHeaderCntBg
    $headerCountBadge.CornerRadius = New-Object System.Windows.CornerRadius(4)
    $headerCountBadge.Padding = New-Object System.Windows.Thickness(6, 1, 6, 1)
    $headerCountBadge.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $headerCountBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $headerCountText = New-Object System.Windows.Controls.TextBlock
    $headerCountText.Text = "$($appsInCat.Count)"
    $headerCountText.FontSize = 10
    $headerCountText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $headerCountText.Foreground = $script:brushHeaderCntFg
    $headerCountBadge.Child = $headerCountText
    $headerGrid.Children.Add($headerCountBadge) | Out-Null

    $separator = New-Object System.Windows.Controls.Border
    $separator.Height = 1
    $separator.Background = $script:brushSeparator
    $separator.Margin = $marginSeparator

    $cardStack.Children.Add($headerGrid) | Out-Null
    $cardStack.Children.Add($separator) | Out-Null

    # Từng dòng App: CheckBox + Logo (nền mờ nhẹ) + Tên + Nút Link tối giản
    foreach ($app in $appsInCat) {
        $rowBorder = New-Object System.Windows.Controls.Border
        $rowBorder.Height = 27
        $rowBorder.CornerRadius = $cornerRow
        $rowBorder.Padding = $paddingRow
        $rowBorder.Margin = $marginRowBorder
        $rowBorder.Background = $script:brushTransparent
        $rowBorder.Cursor = [System.Windows.Input.Cursors]::Hand

        $rowBorder.Tag = @{
            App              = $app
            Status           = "NONE"
            DetectedId       = $null
            InstalledVersion = $null
            CardBorder       = $cardBorder
        }

        # Grid 4 cột cố định tỉ lệ, triệt tiêu hoàn toàn hiện tượng lệch dòng
        $rowGrid = New-Object System.Windows.Controls.Grid
        $rowGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = New-Object System.Windows.GridLength(20, [System.Windows.GridUnitType]::Pixel)
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = New-Object System.Windows.GridLength(23, [System.Windows.GridUnitType]::Pixel)
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $col3 = New-Object System.Windows.Controls.ColumnDefinition; $col3.Width = New-Object System.Windows.GridLength(22, [System.Windows.GridUnitType]::Pixel)
        $rowGrid.ColumnDefinitions.Add($col0) | Out-Null
        $rowGrid.ColumnDefinitions.Add($col1) | Out-Null
        $rowGrid.ColumnDefinitions.Add($col2) | Out-Null
        $rowGrid.ColumnDefinitions.Add($col3) | Out-Null

        # 1. CheckBox
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $cb.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $cb.Margin = New-Object System.Windows.Thickness(0)
        $cb.Tag = $rowBorder.Tag
        $cb.Add_Checked({ Update-SelectionCount })
        $cb.Add_Unchecked({ Update-SelectionCount })
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $rowGrid.Children.Add($cb) | Out-Null
        $allCheckBoxes.Add($cb)
        $rowBorder.Tag["CheckBox"] = $cb

        # 2. Khung đỡ Logo sương mờ siêu nhẹ (không viền cộm) giúp logo nổi tự nhiên
        $iconBadge = New-Object System.Windows.Controls.Border
        $iconBadge.Width = 20
        $iconBadge.Height = 20
        $iconBadge.CornerRadius = $script:cornerIconBadge
        $iconBadge.Background = $script:brushIconBadgeBg
        $iconBadge.BorderBrush = $script:brushIconBadgeBorder
        $iconBadge.BorderThickness = $thicknessZero
        $iconBadge.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $iconBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $iconInnerGrid = New-Object System.Windows.Controls.Grid
        $iconInnerGrid.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $iconInnerGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $fallbackGlyph = New-Object System.Windows.Controls.TextBlock
        $fallbackGlyph.Text = Get-AppFallbackGlyph -AppName $app.Name -Category $cat
        $fallbackGlyph.FontFamily = $script:fontSegoeEmoji
        $fallbackGlyph.FontSize = 10
        $fallbackGlyph.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $fallbackGlyph.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $iconInnerGrid.Children.Add($fallbackGlyph) | Out-Null

        $img = New-Object System.Windows.Controls.Image
        $img.Width = 17; $img.Height = 17
        $img.Stretch = [System.Windows.Media.Stretch]::Uniform
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::HighQuality)
        $img.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $img.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $img.Visibility = [System.Windows.Visibility]::Collapsed

        $iconInnerGrid.Children.Add($img) | Out-Null
        $iconBadge.Child = $iconInnerGrid

        $localIconPath = Join-Path $iconsCacheDir "$($app.ID).png"
        if (Test-Path -LiteralPath $localIconPath) {
            try {
                $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                $bmp.BeginInit()
                $bmp.UriSource = New-Object System.Uri($localIconPath, [System.UriKind]::Absolute)
                $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bmp.EndInit()
                if ($bmp.PixelWidth -gt 0) {
                    $img.Source = $bmp
                    $fallbackGlyph.Visibility = [System.Windows.Visibility]::Collapsed
                    $img.Visibility = [System.Windows.Visibility]::Visible
                }
            } catch {
                try { Remove-Item -LiteralPath $localIconPath -Force -ErrorAction SilentlyContinue } catch {}
            }
        } else {
            $remoteIconTarget = if (-not [string]::IsNullOrWhiteSpace($app.IconUrl)) {
                $app.IconUrl
            } elseif (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
                "https://www.google.com/s2/favicons?domain=$($app.Domain)&sz=128"
            } else {
                $null
            }

            if ($remoteIconTarget) {
                try {
                    $cachedBmp = $null
                    if ($script:remoteBmpCache.TryGetValue($remoteIconTarget, [ref]$cachedBmp)) {
                        $bmp = $cachedBmp
                    } else {
                        $remoteUri = New-Object System.Uri($remoteIconTarget, [System.UriKind]::Absolute)
                        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                        $bmp.BeginInit()
                        $bmp.UriSource = $remoteUri
                        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                        $bmp.EndInit()
                        $script:remoteBmpCache[$remoteIconTarget] = $bmp
                    }

                    $cacheClosure = {
                        param($sender, $e)
                        try {
                            if ($sender -and $sender.PixelWidth -gt 0) {
                                $fallbackGlyph.Visibility = [System.Windows.Visibility]::Collapsed
                                $img.Visibility = [System.Windows.Visibility]::Visible
                                Save-BitmapToCacheAtomic -BitmapSource $sender -DestPath $localIconPath
                            }
                        } catch {}
                    }.GetNewClosure()

                    if (-not $bmp.IsDownloading) {
                        if ($bmp.PixelWidth -gt 0) {
                            $fallbackGlyph.Visibility = [System.Windows.Visibility]::Collapsed
                            $img.Visibility = [System.Windows.Visibility]::Visible
                            $img.Source = $bmp
                            Save-BitmapToCacheAtomic -BitmapSource $bmp -DestPath $localIconPath
                        }
                    } else {
                        $bmp.Add_DownloadCompleted($cacheClosure)
                        $img.Source = $bmp
                    }
                } catch {}
            }
        }
        [System.Windows.Controls.Grid]::SetColumn($iconBadge, 1)
        $rowGrid.Children.Add($iconBadge) | Out-Null

        # 3. Tên ứng dụng + Badge phiên bản mới gọn gàng (tránh cắt tên App khi cột hẹp)
        $nameAreaGrid = New-Object System.Windows.Controls.Grid
        $nameCol0 = New-Object System.Windows.Controls.ColumnDefinition; $nameCol0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $nameCol1 = New-Object System.Windows.Controls.ColumnDefinition; $nameCol1.Width = [System.Windows.GridLength]::Auto
        $nameAreaGrid.ColumnDefinitions.Add($nameCol0) | Out-Null
        $nameAreaGrid.ColumnDefinitions.Add($nameCol1) | Out-Null

        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $app.Name
        $nameText.Foreground = $script:brushTextWhite
        $nameText.FontSize = 12
        $nameText.FontWeight = [System.Windows.FontWeights]::SemiBold
        $nameText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $nameText.Margin = New-Object System.Windows.Thickness(5, 0, 4, 0)
        $nameText.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $idnPrefix = if ($app.IDn) { "[#$($app.IDn)] " } else { "" }
        $nameText.ToolTip = "$idnPrefix$($app.Name)`nID: $($app.ID)"
        $rowBorder.ToolTip = $nameText.ToolTip
        [System.Windows.Controls.Grid]::SetColumn($nameText, 0)
        $nameAreaGrid.Children.Add($nameText) | Out-Null

        $updateBadge = New-Object System.Windows.Controls.Border
        $updateBadge.Background = $script:brushUpdateBadgeBg
        $updateBadge.BorderBrush = $script:brushUpdateBadgeBorder
        $updateBadge.BorderThickness = $thicknessOne
        $updateBadge.CornerRadius = $script:cornerIconBadge
        $updateBadge.Padding = New-Object System.Windows.Thickness(5, 1, 5, 1)
        $updateBadge.Margin = New-Object System.Windows.Thickness(2, 0, 4, 0)
        $updateBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed
        $updateBadge.MaxWidth = 86

        $updateText = New-Object System.Windows.Controls.TextBlock
        $updateText.FontSize = 9.5
        $updateText.FontWeight = [System.Windows.FontWeights]::Bold
        $updateText.Foreground = $script:brushUpdateBadgeFg
        $updateText.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $updateBadge.Child = $updateText
        [System.Windows.Controls.Grid]::SetColumn($updateBadge, 1)
        $nameAreaGrid.Children.Add($updateBadge) | Out-Null

        $rowBorder.Tag["NameText"]    = $nameText
        $rowBorder.Tag["UpdateBadge"] = $updateBadge
        $rowBorder.Tag["UpdateText"]  = $updateText

        [System.Windows.Controls.Grid]::SetColumn($nameAreaGrid, 2)
        $rowGrid.Children.Add($nameAreaGrid) | Out-Null

        # 4. Button Link Website ngoài cùng bên phải (Tối giản chuẩn WinUtil, chỉ sáng khi hover)
        $targetPageUrl = if (-not [string]::IsNullOrWhiteSpace($app.Url)) {
            $app.Url
        } elseif (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
            if ($app.Domain.StartsWith("http")) { $app.Domain } else { "https://$($app.Domain)" }
        } else { "" }

        $linkBtn = New-Object System.Windows.Controls.Border
        $linkBtn.Width = 20
        $linkBtn.Height = 19
        $linkBtn.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $linkBtn.Background = $script:brushLinkBtnBg
        $linkBtn.BorderBrush = $script:brushLinkBtnBorder
        $linkBtn.BorderThickness = $thicknessOne
        $linkBtn.Cursor = [System.Windows.Input.Cursors]::Hand
        $linkBtn.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
        $linkBtn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $linkBtn.Margin = New-Object System.Windows.Thickness(0)
        $linkBtn.ToolTip = "Mở trang chính thức: $targetPageUrl"
        $linkBtn.Tag = @{ Url = $targetPageUrl; Row = $rowBorder }

        $linkIcon = New-Object System.Windows.Controls.TextBlock
        $linkIcon.Text = [string][char]0x2197 # ↗ Open Link
        $linkIcon.FontFamily = $script:fontSegoeUI
        $linkIcon.FontSize = 11.5
        $linkIcon.FontWeight = [System.Windows.FontWeights]::Bold
        $linkIcon.Foreground = $script:brushLinkBtnFg
        $linkIcon.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $linkIcon.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $linkIcon.Margin = New-Object System.Windows.Thickness(0, -1, 0, 0)
        $linkBtn.Child = $linkIcon
        $rowBorder.Tag["LinkBtn"]  = $linkBtn
        $rowBorder.Tag["LinkIcon"] = $linkIcon

        $linkBtn.Add_MouseEnter({
            param($s, $e)
            $s.Background = $script:brushLinkBtnHoverBg
            $s.BorderBrush = $script:brushLinkBtnHoverBdr
            if ($s.Child) { $s.Child.Foreground = $script:brushLinkBtnHoverFg }
        })
        $linkBtn.Add_MouseLeave({
            param($s, $e)
            $s.Background = $script:brushLinkBtnBg
            $s.BorderBrush = $script:brushLinkBtnBorder
            if ($s.Child) {
                $rowHovered = ($s.Tag -and $s.Tag.Row -and $s.Tag.Row.IsMouseOver)
                $s.Child.Foreground = if ($rowHovered) { $script:brushLinkBtnRowHover } else { $script:brushLinkBtnFg }
            }
        })
        $linkBtn.Add_MouseLeftButtonUp({
            param($s, $e)
            $e.Handled = $true  # Chặn sự kiện nổi bọt để không làm toggle CheckBox
            $domain = if ($s.Tag -and $s.Tag.Url) { $s.Tag.Url } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($domain)) {
                $targetUrl = if ($domain.StartsWith("http")) { $domain } else { "https://$domain" }
                try {
                    Start-Process $targetUrl
                } catch {
                    Log-Text "[!] Không thể mở trang web: $targetUrl"
                }
            }
        })
        [System.Windows.Controls.Grid]::SetColumn($linkBtn, 3)
        $rowGrid.Children.Add($linkBtn) | Out-Null

        # Tối ưu nhấp chọn toàn dòng: Nhấp vào Tên ứng dụng hoặc khoảng trống dòng -> TỰ ĐỘNG TÍCH CHECKBOX
        $rowBorder.Add_MouseLeftButtonUp({
            param($sender, $e)
            if ($e.Handled) { return }

            $src = $e.OriginalSource
            $isCb = $false
            $node = $src
            while ($node -ne $null -and $node -ne $sender) {
                if ($node -is [System.Windows.Controls.CheckBox]) {
                    $isCb = $true
                    break
                }
                if ($node -is [System.Windows.Media.Visual]) {
                    $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
                } else {
                    break
                }
            }
            if ($isCb) { return }

            if ($sender.Tag -and $sender.Tag.CheckBox) {
                $targetCb = $sender.Tag.CheckBox
                $targetCb.IsChecked = -not $targetCb.IsChecked
            }
        })

        # Hover thanh lịch kiểu Win11 ListItem
        $rowBorder.Add_MouseEnter({
            param($sender, $e)
            $sender.Background = $script:brushRowHover
            if ($sender.Tag -and $sender.Tag.LinkIcon -and $sender.Tag.LinkBtn -and (-not $sender.Tag.LinkBtn.IsMouseOver)) {
                $sender.Tag.LinkIcon.Foreground = $script:brushLinkBtnRowHover
            }
        })
        $rowBorder.Add_MouseLeave({
            param($sender, $e)
            $sender.Background = $script:brushTransparent
            if ($sender.Tag -and $sender.Tag.LinkIcon) {
                $sender.Tag.LinkIcon.Foreground = $script:brushLinkBtnFg
            }
        })

        $rowBorder.Child = $rowGrid
        $cardStack.Children.Add($rowBorder) | Out-Null
        $allItemBorders.Add($rowBorder)
    }

    $cardBorder.Child = $cardStack

    # Trọng số chiều cao ước tính: 46px (Header card + Separator) + (Số dòng app * 29px) + 10px (Margin)
    $cardEstimatedHeight = 56 + ($appsInCat.Count * 29)

    # Tìm cột hiện có tổng chiều cao thấp nhất để rót card vào (nguyên lý bình thông nhau, triệt tiêu khoảng trống)
    $targetColIndex = 0
    $minHeight = $script:colHeights[0]
    for ($i = 1; $i -lt 4; $i++) {
        if ($script:colHeights[$i] -lt $minHeight) {
            $minHeight = $script:colHeights[$i]
            $targetColIndex = $i
        }
    }

    $targetColPanel = if ($cardCols[0] -and $cardCols[$targetColIndex]) { $cardCols[$targetColIndex] } else { $cardsContainer }
    if ($targetColPanel) {
        $targetColPanel.Children.Add($cardBorder) | Out-Null
    }

    # Cập nhật chiều cao tích lũy của cột
    $script:colHeights[$targetColIndex] += $cardEstimatedHeight
}

# ── CÁC HÀNH ĐỘNG CÀI ĐẶT / GỠ / NÂNG CẤP APP ──
Register-Click "btnScanInstalled" {
    Invoke-GuardedAction "Quét ứng dụng" {
        Scan-And-ColorizeApps
    }
}

function Clear-AllCheckBoxes {
    $script:suppressSelectionCount = $true
    try {
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -ne $false) {
                $cb.IsChecked = $false
            }
        }
    } finally {
        $script:suppressSelectionCount = $false
    }
    Update-SelectionCount
}

function Invoke-GitHubAssetInstall {
    param($App)
    try {
        Log-Text "   -> Đang tìm bản phát hành mới nhất từ GitHub ($($App.GitHubRepo))..."
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$($App.GitHubRepo)/releases/latest" -Headers @{ "User-Agent" = "DuckUtil" } -TimeoutSec 15
        $asset = $rel.assets | Where-Object { $_.name -match $App.AssetRegex } | Select-Object -First 1
        if (-not $asset) {
            Log-Text "   [!] Không tìm thấy bộ cài phù hợp trên GitHub Release."
            return -1
        }
        $dlPath = Join-Path $env:TEMP $asset.name
        Log-Text "   -> Đang tải $($asset.name)..."
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dlPath -UseBasicParsing -Headers @{ "User-Agent" = "DuckUtil" } -TimeoutSec 120
        try {
            if ($dlPath -match '\.msi$') {
                return (Run-CliStream "msiexec.exe" "/i `"$dlPath`" /qn /norestart")
            } else {
                return (Run-CliStream $dlPath "--silent-install")
            }
        } finally {
            if (Test-Path -LiteralPath $dlPath) { Remove-Item -LiteralPath $dlPath -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        Log-Text "   [!] Lỗi tải/cài từ GitHub: $($_.Exception.Message)"
        return -1
    }
}

Register-Click "btnInstall" {
    Invoke-GuardedAction "Cài đặt ứng dụng" {
        $selectedTags = [System.Collections.Generic.List[object]]::new()
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -eq $true) {
                $selectedTags.Add($cb.Tag)
            }
        }

        if ($selectedTags.Count -eq 0) {
            Log-Text "[!] Bạn chưa tick chọn ứng dụng nào để cài đặt!"
            return
        }

        $total = $selectedTags.Count
        $idx = 0
        Log-Text "=========================================================="
        Log-Text "🚀 BẮT ĐẦU CÀI ĐẶT $total ỨNG DỤNG ĐÃ ĐÁNH DẤU"
        Log-Text "=========================================================="

        foreach ($tag in $selectedTags) {
            $idx++
            $app = $tag.App
            if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }
            if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang cài đặt: $($app.Name)..." }
            Log-Text "[$idx/$total] Đang cài: $($app.Name) (ID: $($app.ID))..."

            if (-not [string]::IsNullOrWhiteSpace($app.GitHubRepo) -and -not [string]::IsNullOrWhiteSpace($app.AssetRegex)) {
                $code = Invoke-GitHubAssetInstall -App $app
            } else {
                $wgArgs = "install --id `"$($app.ID)`" --exact --silent --accept-package-agreements --accept-source-agreements"
                if ($app.Source -eq "msstore") { $wgArgs += " --source msstore" }
                $code = Run-CliStream "winget" $wgArgs
            }

            if ($code -eq 0) {
                Log-Text "   [✓ HOÀN THÀNH] $($app.Name)"
                if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
            } else {
                Log-Text "   [❌ LỖI] $($app.Name) (Exit Code: $code)"
                if (-not [string]::IsNullOrWhiteSpace($app.FallbackUrl)) {
                    Log-Text "   [↗] Gói này hiện không khả dụng tự động qua WinGet. Đang mở trang tải chính thức: $($app.FallbackUrl)"
                    try { Start-Process $app.FallbackUrl } catch {}
                }
            }
        }
        Update-SelectionCount
        if ($txtStatus) { $txtStatus.Text = "Cài đặt hoàn tất!" }
        if ($progressBar) { $progressBar.Value = 100 }
        Scan-And-ColorizeApps
    }
}

Register-Click "btnUninstall" {
    Invoke-GuardedAction "Gỡ cài đặt" -DeferExpand {
        $selectedTags = [System.Collections.Generic.List[object]]::new()
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -eq $true) {
                $selectedTags.Add($cb.Tag)
            }
        }

        if ($selectedTags.Count -eq 0) {
            Expand-TerminalLog
            Log-Text "[!] Bạn chưa chọn ứng dụng nào để gỡ cài đặt!"
            return
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Bạn có chắc chắn muốn gỡ bỏ $($selectedTags.Count) ứng dụng đã chọn?",
            "Xác nhận gỡ cài đặt",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Expand-TerminalLog
        $total = $selectedTags.Count
        $idx = 0
        Log-Text "=========================================================="
        Log-Text "🗑️ BẮT ĐẦU GỠ CÀI ĐẶT $total ỨNG DỤNG ĐÃ CHỌN"
        Log-Text "=========================================================="

        foreach ($tag in $selectedTags) {
            $idx++
            $app = $tag.App
            # Ưu tiên sử dụng DetectedId thực tế phát hiện được qua SmartMatcher
            $uninstallId = if ($tag.DetectedId) { $tag.DetectedId } else { $app.ID }

            if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }
            if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang gỡ bỏ: $($app.Name)..." }
            Log-Text "[$idx/$total] Đang gỡ: $($app.Name) (Mã gỡ: $uninstallId)..."

            $unArgs = "uninstall --id `"$uninstallId`" --silent --accept-source-agreements"
            if ($app.Source -eq "msstore" -and $uninstallId -eq $app.ID) {
                $unArgs += " --source msstore"
            }
            $code = Run-CliStream "winget" $unArgs
            if ($code -eq 0) {
                Log-Text "   [✓ ĐÃ GỠ THÀNH CÔNG] $($app.Name)"
                if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
            } else {
                Log-Text "   [❌ LỖI GỠ] $($app.Name) (Exit Code: $code)"
            }
        }
        Update-SelectionCount
        if ($txtStatus) { $txtStatus.Text = "Gỡ cài đặt hoàn tất!" }
        if ($progressBar) { $progressBar.Value = 100 }
        Scan-And-ColorizeApps
    }
}

Register-Click "btnUpgradeAll" {
    Invoke-GuardedAction "Nâng cấp toàn bộ" {
        Log-Text "=========================================================="
        Log-Text "⚡ BẮT ĐẦU NÂNG CẤP TOÀN BỘ PHẦN MỀM TRÊN MÁY"
        Log-Text "=========================================================="
        if ($txtStatus) { $txtStatus.Text = "Đang nâng cấp tất cả ứng dụng..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }

        Run-CliStream "winget" "upgrade --all --silent --accept-package-agreements --accept-source-agreements"

        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Nâng cấp hoàn tất!" }
        Log-Text "[✓] Toàn bộ ứng dụng đã được nâng cấp lên bản mới nhất."
        Scan-And-ColorizeApps
    }
}

# Chọn tất cả các dòng đang hiển thị
Register-Click "btnSelectAll" {
    $script:suppressSelectionCount = $true
    try {
        foreach ($row in $allItemBorders) {
            if ($row.Visibility -eq [System.Windows.Visibility]::Visible -and $row.Tag -and $row.Tag.CheckBox) {
                $cb = $row.Tag.CheckBox
                if ($cb.IsChecked -ne $true) {
                    $cb.IsChecked = $true
                }
            }
        }
    } finally {
        $script:suppressSelectionCount = $false
    }
    Update-SelectionCount
}

Register-Click "btnDeselectAll" {
    Clear-AllCheckBoxes
}

Register-Click "btnClearLog" {
    if ($txtLog) { $txtLog.Clear() }
}

# ── LOGIC MODULE SỬA LỖI HỆ THỐNG (SYSTEM REPAIRS) ──
Register-Click "btnSfcScan" {
    Invoke-GuardedAction "SFC Scan" {
        Log-Text "[*] Đang bắt đầu quét kiểm tra tính toàn vẹn hệ thống (sfc /scannow)..."
        if ($txtStatus) { $txtStatus.Text = "Đang chạy SFC Scan..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-SystemFileCheck
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Quét SFC hoàn tất" }
        Log-Text "[✓] Quá trình SFC đã kết thúc."
    }
}

Register-Click "btnDismRestore" {
    Invoke-GuardedAction "DISM RestoreHealth" {
        Log-Text "[*] Đang khôi phục kho ảnh hệ thống Windows qua DISM RestoreHealth..."
        if ($txtStatus) { $txtStatus.Text = "Đang chạy DISM RestoreHealth..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-DismRestoreHealth
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "DISM hoàn tất" }
        Log-Text "[✓] DISM RestoreHealth hoàn thành xuất sắc."
    }
}

Register-Click "btnDismCleanup" {
    Invoke-GuardedAction "DISM Component Cleanup" -DeferExpand {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Lệnh DISM /StartComponentCleanup /ResetBase sẽ nén kho WinSxS và KHÔNG THỂ gỡ cài đặt (rollback) các bản Windows Update hiện tại về sau.`n`nBạn có chắc chắn muốn tiếp tục?",
            "Xác nhận dọn kho linh kiện (WinSxS)",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Expand-TerminalLog
        Log-Text "[*] Đang dọn dẹp kho linh kiện hệ thống (DISM Component Cleanup)..."
        if ($txtStatus) { $txtStatus.Text = "Đang dọn kho linh kiện..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-DismComponentCleanup
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn kho linh kiện hoàn tất" }
        Log-Text "[✓] Đã giải phóng dung lượng kho linh kiện."
    }
}

Register-Click "btnFixWindowsUpdate" {
    Invoke-GuardedAction "Khởi tạo lại Windows Update" {
        Log-Text "[*] Bắt đầu khởi tạo và xóa sạch cache lỗi Windows Update..."
        if ($txtStatus) { $txtStatus.Text = "Đang sửa lỗi Windows Update..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Reset-WindowsUpdateEngine
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Đã đặt lại Windows Update" }
    }
}

Register-Click "btnRestartUpdateServices" {
    Invoke-GuardedAction "Khởi động lại Update Services" {
        Log-Text "[*] Đang khởi động lại dịch vụ Windows Update & BITS..."
        Restart-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
        Restart-Service -Name "bits" -Force -ErrorAction SilentlyContinue
        Log-Text "[✓] Đã khởi động lại dịch vụ cập nhật."
    }
}

Register-Click "btnTriggerScanUpdate" {
    Invoke-GuardedAction "Kích hoạt quét cập nhật" {
        Invoke-WindowsUpdateScan
    }
}

Register-Click "btnFlushDnsWinsock" {
    Invoke-GuardedAction "Flush DNS & Reset Winsock" {
        Log-Text "[*] Đang xóa sạch cache DNS và reset Winsock Catalog..."
        Clear-DnsResolverCache
        Run-CliStream "netsh.exe" "winsock reset"
        Log-Text "[✓] Đã làm mới mạng và DNS cache."
    }
}

Register-Click "btnResetTcpIp" {
    Invoke-GuardedAction "Reset TCP/IP Stack" {
        Log-Text "[*] Đang đặt lại toàn bộ ngăn xếp giao thức mạng TCP/IP..."
        Reset-NetworkInterfaceStack
        Log-Text "[✓] Đã reset TCP/IP Stack. Khuyên bạn nên khởi động lại máy."
    }
}

Register-Click "btnClearTemp" {
    Invoke-GuardedAction "Dọn dẹp Temp" {
        Log-Text "[*] Đang dọn dẹp các tệp tạm thời trong User Temp và Windows Temp..."
        if ($txtStatus) { $txtStatus.Text = "Đang dọn tệp rác Temp..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Clear-SystemTempFiles
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn tệp tạm hoàn tất" }
        Log-Text "[✓] Dọn dẹp bộ nhớ tạm thành công!"
    }
}

Register-Click "btnCleanEventLogs" {
    Invoke-GuardedAction "Dọn dẹp Windows Event Logs" -DeferExpand {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Hành động này sẽ xóa toàn bộ nhật ký sự kiện Windows (Application, System, Security...). Bạn có chắc chắn muốn tiếp tục?",
            "Xác nhận dọn dẹp Event Logs",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Expand-TerminalLog
        if ($txtStatus) { $txtStatus.Text = "Đang dọn Event Logs..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Clear-SystemEventLogs
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn Event Logs hoàn tất" }
    }
}

Register-Click "btnRestartExplorer" {
    Invoke-GuardedAction "Khởi động lại Windows Explorer" {
        Log-Text "[*] Đang khởi động lại tiến trình Windows Explorer (explorer.exe)..."
        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
            Start-Process "explorer.exe"
        }
        Log-Text "[✓] Đã nạp lại Windows Explorer thành công."
    }
}

# ── LOGIC MODULE QUẢN LÝ & GỠ LỖI DRIVER ──
Register-Click "btnScanFaultyDrivers" {
    Invoke-GuardedAction "Quét Driver lỗi" {
        Log-Text "=========================================================="
        Log-Text "🔍 ĐANG QUÉT TOÀN BỘ THIẾT BỊ PHẦN CỨNG & DRIVER BỊ LỖI..."
        Log-Text "=========================================================="
        if ($txtStatus) { $txtStatus.Text = "Đang quét thiết bị lỗi..." }

        $faulty = Find-FaultyPnpDevices

        if ($faulty.Count -eq 0) {
            Log-Text "[✓] Tuyệt vời! Không phát hiện thiết bị nào bị lỗi hoặc thiếu driver trên máy bạn."
            if ($txtStatus) { $txtStatus.Text = "Tất cả Driver đều hoạt động tốt" }
        } else {
            Log-Text "[⚠️] PHÁT HIỆN $($faulty.Count) THIẾT BỊ ĐANG BỊ LỖI / THIẾU DRIVER:"
            foreach ($d in $faulty) {
                Log-Text "   • Tên thiết bị: $($d.FriendlyName)"
                Log-Text "     Mã phần cứng: $($d.InstanceId)"
                Log-Text "     Trạng thái: $($d.Status) | ErrorCode: $($d.ConfigManagerErrorCode)"
                Log-Text "   ────────────────────────────────────────────────"
            }
            if ($txtStatus) { $txtStatus.Text = "Phát hiện $($faulty.Count) thiết bị lỗi" }
        }
    }
}

Register-Click "btnPnpRescan" {
    Invoke-GuardedAction "Quét lại thiết bị PnP" {
        Log-Text "[*] Đang gửi lệnh quét phần cứng Plug and Play (pnputil /scan-devices)..."
        Invoke-PnpDeviceRescan
        Log-Text "[✓] Windows đã hoàn tất quét và phát hiện lại các thiết bị phần cứng."
    }
}

Register-Click "btnOpenDeviceManager" {
    Log-Text "[*] Đang mở Trình quản lý thiết bị (devmgmt.msc)..."
    Start-Process "devmgmt.msc"
}

Register-Click "btnFixDriverUpdate" {
    Invoke-GuardedAction "Gỡ lỗi kẹt driver update" {
        Log-Text "[*] Đang giải phóng hàng đợi tải driver bị kẹt trong Windows Update..."
        if ($txtStatus) { $txtStatus.Text = "Đang sửa lỗi kẹt cập nhật driver..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }

        Reset-WindowsUpdateEngine

        Log-Text "   - Đang buộc nhận diện lại các thiết bị phần cứng..."
        Invoke-PnpDeviceRescan

        Log-Text "   - Yêu cầu Windows Update quét tìm driver thay thế mới..."
        Invoke-WindowsUpdateScan

        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Đã gỡ lỗi kẹt driver update" }
        Log-Text "[✓] Hoàn thành! Lỗi kẹt tải driver đã được dọn sạch."
    }
}

Register-Click "btnScanWindowsUpdateDrivers" {
    Invoke-GuardedAction "Quét driver từ Windows Update" {
        Invoke-WindowsUpdateScan
    }
}

Register-Click "btnCleanDriverStore" {
    Invoke-GuardedAction "Dọn dẹp DriverStore" -DeferExpand {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Hành động này sẽ xóa các gói driver OEM cũ không còn thiết bị sử dụng trong DriverStore.`nBạn có chắc chắn muốn tiếp tục?",
            "Xác nhận dọn dẹp DriverStore",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Expand-TerminalLog
        if ($txtStatus) { $txtStatus.Text = "Đang dọn dẹp DriverStore..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-PnpDriverStoreCleanup
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn dẹp DriverStore hoàn tất" }
    }
}

Register-Click "btnBackupDrivers" {
    Invoke-GuardedAction "Sao lưu Driver" {
        $dest = "C:\Backup_Drivers"
        Log-Text "[*] Đang sao lưu toàn bộ Driver của máy ra thư mục: '$dest'..."
        if ($txtStatus) { $txtStatus.Text = "Đang sao lưu driver..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }

        $res = Export-SystemDriversBackup -Destination $dest

        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($res) {
            if ($txtStatus) { $txtStatus.Text = "Sao lưu driver hoàn tất" }
            Log-Text "[✓] THÀNH CÔNG! Đã sao lưu toàn bộ driver vào: $dest"
        } else {
            if ($txtStatus) { $txtStatus.Text = "Sao lưu driver thất bại" }
            Log-Text "[❌] Lỗi trong quá trình sao lưu driver."
        }
    }
}

Register-Click "btnOpenBackupFolder" {
    $dest = "C:\Backup_Drivers"
    if (Test-Path -LiteralPath $dest) {
        Start-Process explorer.exe "`"$dest`""
    } else {
        Log-Text "[!] Thư mục $dest chưa tồn tại. Hãy bấm nút 'Sao Lưu Toàn Bộ Driver' trước."
    }
}

# ── TỰ ĐỘNG QUÉT KHI MỞ CỬA SỔ & KHỞI CHẠY GIAO DIỆN ──
$script:autoScannedOnStartup = $false
$window.Add_ContentRendered({
    if (-not $script:autoScannedOnStartup) {
        $script:autoScannedOnStartup = $true
        [System.Windows.Forms.Application]::DoEvents()
        Scan-And-ColorizeApps
    }
})

$window.ShowDialog() | Out-Null
