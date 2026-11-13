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
    "IDn": 1
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
    "IDn": 2
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
    "IDn": 3
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
    "IDn": 4
  },
  {
    "ID": "VivaldiTechnologies.Vivaldi",
    "Name": "Vivaldi",
    "Domain": "vivaldi.com",
    "Aliases": [
      "Vivaldi",
      "VivaldiTechnologies.Vivaldi"
    ],
    "Category": "Web Browsers",
    "IDn": 5
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
    "IDn": 7
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
    "IDn": 8
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
    "IDn": 9
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
    "IDn": 10
  },
  {
    "ID": "VNG.Zalo",
    "Name": "Zalo",
    "Domain": "zalo.me",
    "Aliases": [
      "Zalo",
      "VNG.Zalo"
    ],
    "Category": "Communication",
    "IDn": 11
  },
  {
    "ID": "Zoom.Zoom",
    "Name": "Zoom",
    "Domain": "zoom.us",
    "Aliases": [
      "Zoom",
      "Zoom.Zoom"
    ],
    "Category": "Communication",
    "IDn": 12
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
    "IDn": 13
  },
  {
    "ID": "WhatsApp.WhatsApp",
    "Name": "WhatsApp",
    "Domain": "whatsapp.com",
    "Aliases": [
      "WhatsApp",
      "WhatsApp.WhatsApp"
    ],
    "Category": "Communication",
    "IDn": 14
  },
  {
    "ID": "Microsoft.Teams",
    "Name": "Microsoft Teams",
    "Domain": "teams.microsoft.com",
    "Aliases": [
      "Microsoft Teams",
      "Teams",
      "Microsoft.Teams"
    ],
    "Category": "Communication",
    "IDn": 15
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
    "IDn": 16
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
    "IDn": 17
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
    "IDn": 19
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
    "IDn": 20
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
    "IDn": 21
  },
  {
    "ID": "Microsoft.WindowsTerminal",
    "Name": "Windows Terminal",
    "Domain": "microsoft.com",
    "Aliases": [
      "Windows Terminal",
      "Microsoft.WindowsTerminal"
    ],
    "IconUrl": "https://raw.githubusercontent.com/microsoft/terminal/main/res/terminal/images/Square44x44Logo.targetsize-32.png",
    "Category": "Development",
    "IDn": 22
  },
  {
    "ID": "Microsoft.WindowsTerminal.Preview",
    "Name": "Windows Terminal Preview",
    "Domain": "microsoft.com",
    "Aliases": [
      "Windows Terminal Preview",
      "Microsoft.WindowsTerminal.Preview"
    ],
    "IconUrl": "https://raw.githubusercontent.com/microsoft/terminal/main/res/terminal/images-Pre/Square44x44Logo.targetsize-32.png",
    "Category": "Development",
    "IDn": 23
  },
  {
    "ID": "Python.Python.3.12",
    "Name": "Python 3.12",
    "Domain": "python.org",
    "Aliases": [
      "Python 3.12",
      "Python",
      "Python.Python.3.12"
    ],
    "Category": "Development",
    "IDn": 24
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
    "IDn": 25
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
    "IDn": 26
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
    "IDn": 27
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
    "IDn": 28
  },
  {
    "ID": "dbeaver.dbeaver",
    "Name": "DBeaver CE",
    "Domain": "dbeaver.io",
    "Aliases": [
      "DBeaver",
      "DBeaver CE",
      "dbeaver.dbeaver"
    ],
    "Category": "Development",
    "IDn": 29
  },
  {
    "ID": "GoLang.Go",
    "Name": "Go Lang",
    "Domain": "go.dev",
    "Aliases": [
      "Go",
      "Go Programming Language",
      "GoLang",
      "GoLang.Go"
    ],
    "Category": "Development",
    "IDn": 30
  },
  {
    "ID": "Rustlang.Rustup",
    "Name": "Rust (rustup)",
    "Domain": "rust-lang.org",
    "Aliases": [
      "Rust",
      "rustup",
      "Rustlang.Rustup"
    ],
    "Category": "Development",
    "IDn": 31
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
    "IDn": 32
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
    "IDn": 33
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
    "IDn": 34
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
    "IDn": 35
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
    "IDn": 36
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
    "IDn": 37
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
    "IDn": 38
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
    "IDn": 39
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
    "IDn": 40
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
    "IDn": 41
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
    "IDn": 42
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
    "IDn": 43
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
    "IDn": 44
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
    "IDn": 45
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
    "IDn": 46
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
    "IDn": 47
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
    "IDn": 48
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
    "IDn": 49
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
    "IDn": 50
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
    "IDn": 51
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
    "IDn": 52
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
    "IDn": 53
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
    "IDn": 54
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
    "IDn": 55
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
    "IDn": 56
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
    "IDn": 57
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
    "IDn": 58
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
    "IDn": 59
  },
  {
    "ID": "Microsoft.VCRedist.2005.x64",
    "Name": "VC++ 2005 (x64)",
    "Domain": "visualstudio.microsoft.com",
    "Aliases": [
      "Microsoft Visual C++ 2005 Redistributable (x64)",
      "Microsoft.VCRedist.2005.x64"
    ],
    "Category": "C++ & System Runtimes",
    "IDn": 60
  },
  {
    "ID": "Microsoft.VCRedist.2005.x86",
    "Name": "VC++ 2005 (x86)",
    "Domain": "visualstudio.microsoft.com",
    "Aliases": [
      "Microsoft Visual C++ 2005 Redistributable (x86)",
      "Microsoft.VCRedist.2005.x86"
    ],
    "Category": "C++ & System Runtimes",
    "IDn": 61
  },
  {
    "ID": "Microsoft.VCRedist.2008.x64",
    "Name": "VC++ 2008 (x64)",
    "Domain": "visualstudio.microsoft.com",
    "Aliases": [
      "Microsoft Visual C++ 2008 Redistributable - x64",
      "Microsoft.VCRedist.2008.x64"
    ],
    "Category": "C++ & System Runtimes",
    "IDn": 62
  },
  {
    "ID": "Microsoft.VCRedist.2008.x86",
    "Name": "VC++ 2008 (x86)",
    "Domain": "visualstudio.microsoft.com",
    "Aliases": [
      "Microsoft Visual C++ 2008 Redistributable - x86",
      "Microsoft.VCRedist.2008.x86"
    ],
    "Category": "C++ & System Runtimes",
    "IDn": 63
  },
  {
    "ID": "Microsoft.VCRedist.2010.x64",
    "Name": "VC++ 2010 (x64)",
    "Domain": "visualstudio.microsoft.com",
    "Aliases": [
      "Microsoft Visual C++ 2010 x64 Redistributable",
      "Microsoft.VCRedist.2010.x64"
    ],
    "Category": "C++ & System Runtimes",
    "IDn": 64
  },
  {
    "ID": "Microsoft.VCRedist.2010.x86",
    "Name": "VC++ 2010 (x86)",
    "Domain": "visualstudio.microsoft.com",
    "Aliases": [
      "Microsoft Visual C++ 2010 x86 Redistributable",
      "Microsoft.VCRedist.2010.x86"
    ],
    "Category": "C++ & System Runtimes",
    "IDn": 65
  },
  {
    "ID": "Microsoft.VCRedist.2012.x64",
    "Name": "VC++ 2012 (x64)",
    "Domain": "visualstudio.microsoft.com",
    "Aliases": [
      "Microsoft Visual C++ 2012 Redistributable (x64)",
      "Microsoft.VCRedist.2012.x64"
    ],
    "Category": "C++ & System Runtimes",
    "IDn": 66
  },
  {
    "ID": "Microsoft.VCRedist.2012.x86",
    "Name": "VC++ 2012 (x86)",
    "Domain": "visualstudio.microsoft.com",
    "Aliases": [
      "Microsoft Visual C++ 2012 Redistributable (x86)",
      "Microsoft.VCRedist.2012.x86"
    ],
    "Category": "C++ & System Runtimes",
    "IDn": 67
  },
  {
    "ID": "Microsoft.VCRedist.2013.x64",
    "Name": "VC++ 2013 (x64)",
    "Domain": "visualstudio.microsoft.com",
    "Aliases": [
      "Microsoft Visual C++ 2013 Redistributable (x64)",
      "Microsoft.VCRedist.2013.x64"
    ],
    "Category": "C++ & System Runtimes",
    "IDn": 68
  },
  {
    "ID": "Microsoft.VCRedist.2013.x86",
    "Name": "VC++ 2013 (x86)",
    "Domain": "visualstudio.microsoft.com",
    "Aliases": [
      "Microsoft Visual C++ 2013 Redistributable (x86)",
      "Microsoft.VCRedist.2013.x86"
    ],
    "Category": "C++ & System Runtimes",
    "IDn": 69
  },
  {
    "ID": "Microsoft.VCRedist.2015+.x64",
    "Name": "VC++ 2015-2022 (x64)",
    "Domain": "visualstudio.microsoft.com",
    "Aliases": [
      "Visual C++",
      "Microsoft Visual C++ 2015-2022 Redistributable (x64)",
      "Microsoft Visual C++ 2015-2022",
      "Microsoft.VCRedist.2015+.x64"
    ],
    "Category": "C++ & System Runtimes",
    "IDn": 70
  },
  {
    "ID": "Microsoft.VCRedist.2015+.x86",
    "Name": "VC++ 2015-2022 (x86)",
    "Domain": "visualstudio.microsoft.com",
    "Aliases": [
      "Microsoft Visual C++ 2015-2022 Redistributable (x86)",
      "Microsoft.VCRedist.2015+.x86"
    ],
    "Category": "C++ & System Runtimes",
    "IDn": 71
  },
  {
    "ID": "Microsoft.DirectX",
    "Name": "DirectX End-User",
    "Domain": "xbox.com",
    "Aliases": [
      "DirectX",
      "Microsoft DirectX",
      "DirectX End-User Runtimes",
      "Microsoft.DirectX"
    ],
    "Category": "C++ & System Runtimes",
    "IDn": 72
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
    "IDn": 73
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
    "IDn": 74
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
    "IDn": 76
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
    "IDn": 77
  },
  {
    "ID": "VSRevoGroup.RevoUninstaller",
    "Name": "Revo Uninstaller",
    "Domain": "revouninstaller.com",
    "Aliases": [
      "Revo Uninstaller",
      "VSRevoGroup.RevoUninstaller"
    ],
    "Category": "System Utilities",
    "IDn": 78
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
    "IDn": 79
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
    "IDn": 81
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
    "Name": "CPUID CPU-Z",
    "Domain": "cpuid.com",
    "Aliases": [
      "CPUID CPU-Z",
      "CPU-Z",
      "CPUID.CPU-Z"
    ],
    "Category": "Hardware & Monitoring",
    "IDn": 83
  },
  {
    "ID": "CPUID.HWMonitor",
    "Name": "CPUID HWMonitor",
    "Domain": "cpuid.com",
    "Aliases": [
      "CPUID HWMonitor",
      "HWMonitor",
      "CPUID.HWMonitor"
    ],
    "Category": "Hardware & Monitoring",
    "IDn": 84
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
    "IDn": 85
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
    "IDn": 86
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
    "IDn": 87
  },
  {
    "ID": "ProtonTechnologies.ProtonVPN",
    "Name": "ProtonVPN",
    "Domain": "protonvpn.com",
    "Aliases": [
      "Proton VPN",
      "ProtonVPN",
      "Proton.ProtonVPN",
      "ProtonTechnologies.ProtonVPN"
    ],
    "Category": "Security & Network",
    "IDn": 88
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
    "IDn": 89
  },
  {
    "ID": "VideoLAN.VLC",
    "Name": "VLC Media Player",
    "Domain": "www.videolan.org",
    "Aliases": [
      "VLC media player",
      "VLC",
      "VideoLAN.VLC"
    ],
    "Category": "Audio & Video",
    "IDn": 90
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
    "IDn": 91
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
    "IDn": 92
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
    "IDn": 93
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
    "IDn": 94
  },
  {
    "ID": "CodecGuide.K-LiteCodecPack.Mega",
    "Name": "K-Lite Codec Mega",
    "Domain": "codecguide.com",
    "Aliases": [
      "K-Lite Mega Codec Pack",
      "K-Lite Codec Pack",
      "CodecGuide.K-LiteCodecPack.Mega"
    ],
    "Category": "Audio & Video",
    "IDn": 95,
    "IconUrl": "https://icons.duckduckgo.com/ip3/codecguide.com.ico"
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
    "IDn": 96
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
    "IconUrl": "https://icons.duckduckgo.com/ip3/gimp.org.ico"
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
    "IDn": 98
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
    "IDn": 99
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
    "IconUrl": "https://icons.duckduckgo.com/ip3/inkscape.org.ico"
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
    "IDn": 101
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
    "IDn": 102
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
    "IDn": 103
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
    "IDn": 104
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
    "IDn": 105
  },
  {
    "ID": "Valve.Steam",
    "Name": "Steam",
    "Domain": "steampowered.com",
    "Aliases": [
      "Steam",
      "Valve.Steam"
    ],
    "Category": "Game Launchers",
    "IDn": 106
  },
  {
    "ID": "EpicGames.EpicGamesLauncher",
    "Name": "Epic Games Launcher",
    "Domain": "epicgames.com",
    "Aliases": [
      "Epic Games Launcher",
      "Epic Games",
      "EpicGames.EpicGamesLauncher"
    ],
    "Category": "Game Launchers",
    "IDn": 107,
    "IconUrl": "https://icons.duckduckgo.com/ip3/unrealengine.com.ico"
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
    "IDn": 108
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
    "IDn": 109
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
    "IDn": 110
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
    "IDn": 111
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
    "IDn": 113
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
    "IDn": 114
  }
]
'@
$AppCatalog = ConvertFrom-Json $appsRawJson

# 4. GIAO DIỆN XAML WPF
[xml]$XAML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="DuckUtil - Cyber Obsidian Suite"
    Width="1280" Height="890"
    MinWidth="1200" MinHeight="820"
    WindowStartupLocation="CenterScreen"
    Background="#090B10"
    Foreground="#F8FAFC"
    FontFamily="Segoe UI Variable Display, Segoe UI, -apple-system, sans-serif"
    TextOptions.TextFormattingMode="Display"
    TextOptions.TextRenderingMode="ClearType"
    UseLayoutRounding="True"
    SnapsToDevicePixels="True">

    <Window.Resources>
        <!-- ═══ PHONG CÁCH THANH CUỘN (SCROLLBAR) HIỆN ĐẠI SIÊU GỌN - OBSIDIAN CYBER (8PX) ═══ -->
        <!-- Style cho Thumb thanh cuộn (Dọc) -->
        <Style x:Key="ModernScrollThumb" TargetType="{x:Type Thumb}">
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Setter Property="IsTabStop" Value="False"/>
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type Thumb}">
                        <Border Name="thumbBorder" Background="#26334D" CornerRadius="4" Margin="2,0"/>
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

        <!-- RepeatButton trong suốt không mũi tên -->
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

        <!-- Style toàn cục tự động áp dụng cho tất cả ScrollBar trong App -->
        <Style TargetType="{x:Type ScrollBar}">
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Style.Triggers>
                <Trigger Property="Orientation" Value="Vertical">
                    <Setter Property="Width" Value="8"/>
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
                    <Setter Property="Height" Value="8"/>
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
                                                        <Border Name="hThumbBorder" Background="#26334D" CornerRadius="4" Margin="0,2"/>
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

        <!-- Nút bấm phong cách Action (Primary Accent Buttons) -->
        <Style x:Key="ActionButton" TargetType="Button">
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="Margin" Value="4,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#25FFFFFF"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="btnBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="7" Padding="{TemplateBinding Padding}"
                                SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.88"/>
                                <Setter TargetName="btnBorder" Property="BorderBrush" Value="#60FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.70"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Nút phụ (Secondary Buttons - Dark Slate Accent) -->
        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="#121724"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="Margin" Value="4,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderBrush" Value="#1F2A3D"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="HorizontalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="btnBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="7" Padding="{TemplateBinding Padding}"
                                SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="#1C2538"/>
                                <Setter TargetName="btnBorder" Property="BorderBrush" Value="#38BDF8"/>
                                <Setter Property="Foreground" Value="#F8FAFC"/>
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

        <!-- Nút điều hướng Tab chính (NavTabButton) -->
        <Style x:Key="NavTabButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#64748B"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="22,12"/>
            <Setter Property="Margin" Value="2,0"/>
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
                                <Setter TargetName="navBorder" Property="Background" Value="#141824"/>
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
            <RowDefinition Height="Auto" Name="rowDefTerminal"/>  <!-- Cyber Terminal Log -->
        </Grid.RowDefinitions>

        <!-- ═══ 1. MAIN NAV TAB BAR ═══ -->
        <Border Grid.Row="0" Background="#0D1018" Padding="18,0" BorderBrush="#181E2C" BorderThickness="0,0,0,1">
            <StackPanel Orientation="Horizontal">
                <Button Name="navBtnApps" Content="📦 ỨNG DỤNG (APPLICATIONS)" Style="{StaticResource NavTabButton}"
                        BorderBrush="#38BDF8" Foreground="#38BDF8"/>
                <Button Name="navBtnRepair" Content="🔧 GỠ LỖI &amp; SỬA HỆ THỐNG" Style="{StaticResource NavTabButton}"/>
                <Button Name="navBtnDrivers" Content="🚗 QUẢN LÝ &amp; GỠ LỖI DRIVER" Style="{StaticResource NavTabButton}"/>
            </StackPanel>
        </Border>

        <!-- ═══ 2. MAIN VIEWPORT (TAB CONTROL) ═══ -->
        <TabControl Grid.Row="1" Name="MainTabControl" Background="Transparent" BorderThickness="0">
            <TabControl.ItemContainerStyle>
                <Style TargetType="TabItem">
                    <Setter Property="Visibility" Value="Collapsed"/>
                </Style>
            </TabControl.ItemContainerStyle>

            <!-- ── TAB 1: ỨNG DỤNG (BỐ CỤC 4 CỘT) ── -->
            <TabItem>
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <!-- Thanh nút bấm ứng dụng + Chú giải phân màu -->
                    <Border Grid.Row="0" Background="#0E121B" Padding="18,10" BorderBrush="#181E2C" BorderThickness="0,0,0,1">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>

                            <!-- Hàng 1: Nút bấm hành động -->
                            <Grid Grid.Row="0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>

                                <StackPanel Grid.Column="0" Orientation="Horizontal">
                                    <Button Name="btnInstall" Content="🚀 Install Selected" Style="{StaticResource ActionButton}"
                                            Background="#10B981" Padding="18,9"/>
                                    <Button Name="btnUpgradeAll" Content="⚡ Upgrade All" Style="{StaticResource ActionButton}"
                                            Background="#F59E0B" Padding="16,9"/>
                                    <Button Name="btnUninstall" Content="🗑️ Uninstall Selected" Style="{StaticResource ActionButton}"
                                            Background="#EF4444" Padding="16,9"/>
                                    <Button Name="btnScanInstalled" Content="🔍 Get Installed" Style="{StaticResource ActionButton}"
                                            Background="#0EA5E9" Padding="16,9"/>
                                </StackPanel>

                                <StackPanel Grid.Column="2" Orientation="Horizontal">
                                    <Button Name="btnSelectAll" Content="Select All" Style="{StaticResource SecondaryButton}"/>
                                    <Button Name="btnDeselectAll" Content="Clear Selection" Style="{StaticResource SecondaryButton}"/>
                                </StackPanel>
                            </Grid>

                            <!-- Hàng 2: Chú thích màu sắc chuẩn dạng Cyber Pill Badge -->
                            <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="4,10,0,0" VerticalAlignment="Center">
                                <TextBlock Text="Trạng thái màu tên App:" FontSize="11.5" Foreground="#64748B" Margin="0,0,12,0"
                                           FontWeight="SemiBold" VerticalAlignment="Center"/>
                                <Border Background="#161D2C" BorderBrush="#253249" BorderThickness="1"
                                        CornerRadius="12" Padding="10,3" Margin="0,0,8,0">
                                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                        <TextBlock Text="●" Foreground="#FFFFFF" Margin="0,0,6,0" FontSize="10" VerticalAlignment="Center"/>
                                        <TextBlock Text="Trắng: Chưa cài đặt" FontSize="11" Foreground="#FFFFFF" FontWeight="SemiBold"/>
                                    </StackPanel>
                                </Border>
                                <Border Background="#0C2518" BorderBrush="#14532D" BorderThickness="1"
                                        CornerRadius="12" Padding="10,3" Margin="0,0,8,0">
                                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                        <TextBlock Text="●" Foreground="#34D399" Margin="0,0,6,0" FontSize="10" VerticalAlignment="Center"/>
                                        <TextBlock Text="Xanh lá: Đã cài (Bản mới nhất)" FontSize="11" Foreground="#34D399" FontWeight="SemiBold"/>
                                    </StackPanel>
                                </Border>
                                <Border Background="#2A1216" BorderBrush="#5B1621" BorderThickness="1"
                                        CornerRadius="12" Padding="10,3" Margin="0,0,8,0">
                                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                        <TextBlock Text="●" Foreground="#F87171" Margin="0,0,6,0" FontSize="10" VerticalAlignment="Center"/>
                                        <TextBlock Text="Đỏ: Đã cài (Bản cũ - Có cập nhật)" FontSize="11" Foreground="#F87171" FontWeight="SemiBold"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Lưới Card 4 CỘT DỌC TỰ NHIÊN (Masonry 4 Cột, Chiều cao Auto, Chiều rộng cân đối) -->
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"
                                  CanContentScroll="False" PanningMode="VerticalOnly" Padding="10,12">
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
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="20,16">
                    <WrapPanel ItemWidth="590" Orientation="Horizontal">
                        <!-- Card 1: File Hệ Thống -->
                        <Border Background="#0F1420" BorderBrush="#1E283C" BorderThickness="1" CornerRadius="12" Margin="8" Padding="20">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                    <Border Background="#0C283F" BorderBrush="#0284C7" BorderThickness="1" CornerRadius="5" Padding="6,2" Margin="0,0,10,0" VerticalAlignment="Center">
                                        <TextBlock Text="CORE FIX" FontSize="9.5" FontWeight="ExtraBold" Foreground="#38BDF8"/>
                                    </Border>
                                    <TextBlock Text="🛠️ SỬA CHỮA FILE HỆ THỐNG" FontWeight="Bold" FontSize="14" Foreground="#38BDF8" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Quét và tự động sửa các file hệ thống Windows bị hỏng hoặc mất qua SFC và DISM."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnSfcScan" Content="SFC Scan (sfc /scannow)" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                                <Button Name="btnDismRestore" Content="DISM RestoreHealth (Phục hồi linh kiện)" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                                <Button Name="btnDismCleanup" Content="Dọn Kho Linh Kiện (Component Cleanup)" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 2: Windows Update -->
                        <Border Background="#0F1420" BorderBrush="#1E283C" BorderThickness="1" CornerRadius="12" Margin="8" Padding="20">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                    <Border Background="#311F0D" BorderBrush="#B45309" BorderThickness="1" CornerRadius="5" Padding="6,2" Margin="0,0,10,0" VerticalAlignment="Center">
                                        <TextBlock Text="UPDATE" FontSize="9.5" FontWeight="ExtraBold" Foreground="#F59E0B"/>
                                    </Border>
                                    <TextBlock Text="🔄 GỠ LỖI WINDOWS UPDATE" FontWeight="Bold" FontSize="14" Foreground="#F59E0B" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Khắc phục triệt để lỗi kẹt tải 0%, mã lỗi 0x80070002, 0x8024... khi cập nhật Windows."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnFixWindowsUpdate" Content="⚡ Reset Toàn Bộ Cache Update (Triệt để)" Style="{StaticResource ActionButton}" Background="#EA580C" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                                <Button Name="btnRestartUpdateServices" Content="Khởi Động Lại Dịch Vụ BITS &amp; Wuauserv" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                                <Button Name="btnTriggerScanUpdate" Content="Kích Hoạt Tìm Bản Cập Nhật Mới (USOClient)" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 3: Mạng & DNS -->
                        <Border Background="#0F1420" BorderBrush="#1E283C" BorderThickness="1" CornerRadius="12" Margin="8" Padding="20">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                    <Border Background="#09281C" BorderBrush="#059669" BorderThickness="1" CornerRadius="5" Padding="6,2" Margin="0,0,10,0" VerticalAlignment="Center">
                                        <TextBlock Text="NETWORK" FontSize="9.5" FontWeight="ExtraBold" Foreground="#10B981"/>
                                    </Border>
                                    <TextBlock Text="🌐 SỬA LỖI MẠNG &amp; KẾT NỐI" FontWeight="Bold" FontSize="14" Foreground="#10B981" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Khắc phục sự cố mất kết nối mạng, gián đoạn truy cập web, lỗi DNS và sự cố bộ giao thức."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnFlushDnsWinsock" Content="Flush DNS &amp; Reset Winsock (Làm mới mạng)" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                                <Button Name="btnResetTcpIp" Content="Reset Toàn Bộ Ngăn Xếp TCP/IP Stack" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 4: Dọn Rác & Khôi Phục UI -->
                        <Border Background="#0F1420" BorderBrush="#1E283C" BorderThickness="1" CornerRadius="12" Margin="8" Padding="20">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                    <Border Background="#22173B" BorderBrush="#7C3AED" BorderThickness="1" CornerRadius="5" Padding="6,2" Margin="0,0,10,0" VerticalAlignment="Center">
                                        <TextBlock Text="MAINTAIN" FontSize="9.5" FontWeight="ExtraBold" Foreground="#A78BFA"/>
                                    </Border>
                                    <TextBlock Text="🧹 BẢO TRÌ &amp; DỌN DẸP HỆ THỐNG" FontWeight="Bold" FontSize="14" Foreground="#A78BFA" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Giải phóng dung lượng ổ C bị chiếm dụng bởi tệp tạm, nhật ký sự kiện và nạp lại thanh Taskbar khi bị treo."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnClearTemp" Content="Dọn Sạch Thư Mục Temp &amp; Cache Rác" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                                <Button Name="btnCleanEventLogs" Content="Dọn Dẹp Windows Event Logs" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                                <Button Name="btnRestartExplorer" Content="Khởi Động Lại Windows Explorer (Fix đơ taskbar)" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                            </StackPanel>
                        </Border>
                    </WrapPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ── TAB 3: QUẢN LÝ & GỠ LỖI DRIVER ── -->
            <TabItem>
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="20,16">
                    <WrapPanel ItemWidth="390" Orientation="Horizontal">
                        <!-- Card 1: Chẩn Đoán Driver Lỗi -->
                        <Border Background="#0F1420" BorderBrush="#1E283C" BorderThickness="1" CornerRadius="12" Margin="8" Padding="20">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                    <Border Background="#310D18" BorderBrush="#BE123C" BorderThickness="1" CornerRadius="5" Padding="6,2" Margin="0,0,10,0" VerticalAlignment="Center">
                                        <TextBlock Text="HARDWARE" FontSize="9.5" FontWeight="ExtraBold" Foreground="#F43F5E"/>
                                    </Border>
                                    <TextBlock Text="⚠️ CHẨN ĐOÁN PHẦN CỨNG" FontWeight="Bold" FontSize="14" Foreground="#F43F5E" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Rà soát các thiết bị bị chấm than vàng, thiếu driver hoặc driver bị xung đột crash."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnScanFaultyDrivers" Content="🔍 Quét Thiết Bị &amp; Driver Bị Lỗi" Style="{StaticResource ActionButton}" Background="#E11D48" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                                <Button Name="btnPnpRescan" Content="Buộc Windows Quét Lại Phần Cứng (PnP Scan)" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                                <Button Name="btnOpenDeviceManager" Content="Mở Trình Quản Lý Device Manager" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 2: Gỡ Lỗi Update Driver -->
                        <Border Background="#0F1420" BorderBrush="#1E283C" BorderThickness="1" CornerRadius="12" Margin="8" Padding="20">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                    <Border Background="#311F0D" BorderBrush="#B45309" BorderThickness="1" CornerRadius="5" Padding="6,2" Margin="0,0,10,0" VerticalAlignment="Center">
                                        <TextBlock Text="RESOLVE" FontSize="9.5" FontWeight="ExtraBold" Foreground="#F59E0B"/>
                                    </Border>
                                    <TextBlock Text="🛠️ GỠ LỖI CẬP NHẬT DRIVER" FontWeight="Bold" FontSize="14" Foreground="#F59E0B" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Sửa lỗi Windows Update bị kẹt khi đang cài driver màn hình, âm thanh, touchpad."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnFixDriverUpdate" Content="⚡ Sửa Lỗi Kẹt Cập Nhật Driver (Xóa Queue)" Style="{StaticResource ActionButton}" Background="#EA580C" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                                <Button Name="btnScanWindowsUpdateDrivers" Content="Kích Hoạt Quét Driver Mới Từ Microsoft" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                                <Button Name="btnCleanDriverStore" Content="Dọn Dẹp Driver Cũ Trong DriverStore" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 3: Sao Lưu Driver -->
                        <Border Background="#0F1420" BorderBrush="#1E283C" BorderThickness="1" CornerRadius="12" Margin="8" Padding="20">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                    <Border Background="#09281C" BorderBrush="#059669" BorderThickness="1" CornerRadius="5" Padding="6,2" Margin="0,0,10,0" VerticalAlignment="Center">
                                        <TextBlock Text="BACKUP" FontSize="9.5" FontWeight="ExtraBold" Foreground="#10B981"/>
                                    </Border>
                                    <TextBlock Text="💾 SAO LƯU &amp; BẢO VỆ DRIVER" FontWeight="Bold" FontSize="14" Foreground="#10B981" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Trích xuất toàn bộ driver bên thứ ba để phòng khi cài lại Windows không sợ mất mạng/wifi."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnBackupDrivers" Content="Sao Lưu Toàn Bộ Driver (Ra C:\Backup_Drivers)" Style="{StaticResource ActionButton}" Background="#059669" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                                <Button Name="btnOpenBackupFolder" Content="Mở Thư Mục Chứa Driver Đã Sao Lưu" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
                            </StackPanel>
                        </Border>
                    </WrapPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- ═══ 3. STATUS & PROGRESS BAR ═══ -->
        <Border Grid.Row="2" Background="#0A0D14" Padding="20,7" BorderBrush="#181E2C" BorderThickness="0,1,0,0">
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
                    <Border Background="#10B981" Width="7" Height="7" CornerRadius="4" Margin="0,0,8,0" VerticalAlignment="Center"/>
                    <TextBlock Name="txtStatus" Text="Sẵn sàng"
                               Foreground="#38BDF8" FontSize="12" FontWeight="SemiBold"/>
                </StackPanel>

                <TextBlock Grid.Column="1" Grid.Row="0" Name="txtSelectionCount" Text="0 app được chọn"
                           Foreground="#64748B" FontSize="11.5" FontWeight="SemiBold" VerticalAlignment="Center"/>

                <ProgressBar Grid.Column="0" Grid.ColumnSpan="2" Grid.Row="1"
                             Name="progressBar" Height="3" Margin="0,6,0,2"
                             Background="#161C2A" Foreground="#0EA5E9" BorderThickness="0" Value="0"/>
            </Grid>
        </Border>

        <!-- ═══ 4. CYBER TERMINAL LOG ═══ -->
        <Border Grid.Row="3" Background="#05070B" Padding="16,8" BorderBrush="#141924" BorderThickness="0,1,0,0">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0" Margin="0,0,0,5">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <Border Background="#EF4444" Width="8" Height="8" CornerRadius="4" Margin="0,0,5,0"/>
                        <Border Background="#F59E0B" Width="8" Height="8" CornerRadius="4" Margin="0,0,5,0"/>
                        <Border Background="#10B981" Width="8" Height="8" CornerRadius="4" Margin="0,0,8,0"/>
                        <TextBlock Text="TERMINAL LOG" FontSize="10" FontWeight="Bold" Foreground="#475569"
                                   FontFamily="Cascadia Mono, Consolas, sans-serif" VerticalAlignment="Center"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                        <Button Name="btnToggleTerminal" Content="▲ Mở rộng"
                                Background="#111622" BorderBrush="#243044" BorderThickness="1"
                                Foreground="#34D399" Cursor="Hand" FontSize="11" FontWeight="SemiBold"
                                Padding="8,2" Margin="0,0,8,0" ToolTip="Ẩn / Hiện khung Terminal Log"/>
                        <Button Name="btnClearLog" Content="Xóa Log"
                                Background="Transparent" Foreground="#64748B" BorderThickness="0"
                                Cursor="Hand" FontSize="11" Padding="6,2"/>
                    </StackPanel>
                </Grid>
                <TextBox Grid.Row="1" Name="txtLog" Visibility="Collapsed" Background="Transparent" Foreground="#34D399"
                         FontFamily="Cascadia Mono, Cascadia Code, Consolas, Courier New" FontSize="11"
                         IsReadOnly="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"
                         BorderThickness="0" CaretBrush="#38BDF8"
                         Text="[DuckUtil Cyber Suite] Khởi tạo thành công với bố cục 4 cột và phân màu phiên bản.&#x0d;&#x0a;"/>
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
$script:brushNoneFg     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xFF, 0xFF, 0xFF))

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
        while (-not $readTask.IsCompleted -or -not $errTask.IsCompleted) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 30
        }
        $rawList = $readTask.Result
        $errList = $errTask.Result
        $p.WaitForExit()

        # Kiểm tra ExitCode của winget list
        if ($p.ExitCode -ne 0) {
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

    # Phân tích danh sách đã cài đặt từ winget
    $lines = $rawList -split "`r?`n"
    $separatorIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^---\s*---' -or $lines[$i] -match '^---+$') {
            $separatorIndex = $i
            break
        }
    }

    $idMap        = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $nameMap      = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $cleanNameMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $installedList = [System.Collections.Generic.List[object]]::new()

    if ($separatorIndex -gt 0) {
        $separatorLine = $lines[$separatorIndex]
        $headerLine    = $lines[$separatorIndex - 1]

        # Xác định tọa độ bắt đầu của từng cột theo dấu gạch ngang (---) hoặc khoảng trắng kép giữa các tiêu đề cột
        # Đảm bảo 100% tương thích trên mọi ngôn ngữ Windows (Việt, Anh, Nhật, Trung...) mà không phụ thuộc chuỗi "Version"/"Available"
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

            $appName  = ""
            $appId    = ""
            $version  = ""
            $avail    = ""

            if ($idIdx -gt 0 -and $line.Length -gt $idIdx) {
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
                # Fallback tách cột bằng khoảng trắng kép
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
                if (-not $idMap.ContainsKey($appId)) { $idMap[$appId] = $itemObj }
                if (-not [string]::IsNullOrWhiteSpace($appName) -and -not $nameMap.ContainsKey($appName)) { $nameMap[$appName] = $itemObj }
                if ($clean.Length -ge 3 -and -not $cleanNameMap.ContainsKey($clean)) { $cleanNameMap[$clean] = $itemObj }
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
                    if (-not $idMap.ContainsKey($appId)) { $idMap[$appId] = $itemObj }
                    if (-not [string]::IsNullOrWhiteSpace($appName) -and -not $nameMap.ContainsKey($appName)) { $nameMap[$appName] = $itemObj }
                    if ($clean.Length -ge 3 -and -not $cleanNameMap.ContainsKey($clean)) { $cleanNameMap[$clean] = $itemObj }
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
        if ($targetApp.Name -and $nameMap.TryGetValue($targetApp.Name, [ref]$match)) {
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
                if ($nameMap.TryGetValue($alias, [ref]$match)) {
                    $lookupCache[$targetId] = $match
                    return $match
                }
                $cleanAlias = Get-CleanAppName $alias
                if ($cleanAlias.Length -ge 3 -and $cleanNameMap.TryGetValue($cleanAlias, [ref]$match)) {
                    $lookupCache[$targetId] = $match
                    return $match
                }
            }
        }

        # 4. Clean Name match (O(1))
        $cleanTarget = Get-CleanAppName $targetApp.Name
        if ($cleanTarget.Length -ge 3 -and $cleanNameMap.TryGetValue($cleanTarget, [ref]$match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        # 5. Fuzzy / Token boundary matching: siết chặt yêu cầu độ dài >= 4, dùng ranh giới từ (\b), và chặn khớp chéo Preview
        if ($targetApp.Aliases) {
            foreach ($alias in $targetApp.Aliases) {
                if ([string]::IsNullOrWhiteSpace($alias) -or $alias.Length -lt 4) { continue }
                $pattern = "\b" + [System.Text.RegularExpressions.Regex]::Escape($alias) + "\b"
                foreach ($item in $installedList) {
                    # Chặn khớp chéo giữa bản thường và bản Preview
                    if (($item.Name -match 'Preview' -or $item.ID -match 'Preview') -and ($targetApp.Name -notmatch 'Preview')) { continue }
                    if (($targetApp.Name -match 'Preview') -and ($item.Name -notmatch 'Preview' -and $item.ID -notmatch 'Preview')) { continue }

                    if ($item.ID -match $pattern -or $item.Name -match $pattern) {
                        $lookupCache[$targetId] = $item
                        return $item
                    }
                }
            }
        }

        if ($cleanTarget.Length -ge 4) {
            $patternClean = "\b" + [System.Text.RegularExpressions.Regex]::Escape($cleanTarget) + "\b"
            foreach ($item in $installedList) {
                # Chặn khớp chéo giữa bản thường và bản Preview
                if (($item.Name -match 'Preview' -or $item.ID -match 'Preview') -and ($targetApp.Name -notmatch 'Preview')) { continue }
                if (($targetApp.Name -match 'Preview') -and ($item.Name -notmatch 'Preview' -and $item.ID -notmatch 'Preview')) { continue }

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
        $tb = $grid.Children[2]
        $idnPrefix = if ($app.IDn) { "[#$($app.IDn)] " } else { "" }

        $info = Find-InstalledAppFast $app

        if ($info) {
            $countInstalled++
            # Lưu lại ID phát hiện thực tế để phục vụ lệnh gỡ cài đặt chính xác
            $row.Tag.DetectedId = $info.ID
            $row.Tag.InstalledVersion = $info.Version

            if ($info.HasUpdate -eq $true) {
                # ── 🔴 BẢN CŨ: Tên ĐỎ + Gạch chân mỏng (Không tô nền đỏ) ──
                $countOutdated++
                $row.Tag.Status = "OUTDATED"
                $row.Background = $script:brushNoneBg
                $tb.Foreground = $script:brushOutdatedFg
                $updateBadge = if ($info.Available) { " (Có bản: $($info.Available))" } else { " (Có bản mới)" }
                $tb.Text = "$($app.Name)  $updateBadge"
                $tb.TextDecorations = [System.Windows.TextDecorations]::Underline
                $tb.ToolTip = "$idnPrefix$($app.Name)`nĐang cài: $($info.Version)`nCó bản mới: $($info.Available)`nID phát hiện: $($info.ID)"
            } else {
                # ── 🟢 BẢN MỚI NHẤT: Tên XANH LÁ (Không ghi 'Mới nhất', không tô nền xanh) ──
                $countLatest++
                $row.Tag.Status = "LATEST"
                $row.Background = $script:brushNoneBg
                $tb.Foreground = $script:brushLatestFg
                $tb.Text = $app.Name
                $tb.TextDecorations = $null
                $tb.ToolTip = "$idnPrefix$($app.Name)`nPhiên bản: $($info.Version) (Mới nhất)`nID phát hiện: $($info.ID)"
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
            $tb.ToolTip = "$idnPrefix$($app.Name)`nTrạng thái: Chưa cài đặt`nID: $($app.ID)"
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

function Invoke-DriverStoreCleanup {
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

$script:brushCardBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x0F, 0x14, 0x20)); $script:brushCardBg.Freeze()
$script:brushCardBorder  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1E, 0x28, 0x3C)); $script:brushCardBorder.Freeze()
$script:brushHeaderFg    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushHeaderFg.Freeze()
$script:brushSeparator   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1E, 0x26, 0x38)); $script:brushSeparator.Freeze()

$script:brushRowHover    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1C, 0x25, 0x3B)); $script:brushRowHover.Freeze()
$script:brushTextWhite   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xFF, 0xFF, 0xFF)); $script:brushTextWhite.Freeze()
$script:fontSegoeEmoji   = New-Object System.Windows.Media.FontFamily("Segoe UI Emoji, Segoe UI Symbol, Arial")

# Bảng màu cho Button Link Website ngoài cùng bên phải (Cyber Mini-Button)
$script:brushLinkBtnBg        = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x16, 0x20, 0x32)); $script:brushLinkBtnBg.Freeze()
$script:brushLinkBtnBorder    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x2A, 0x38, 0x4F)); $script:brushLinkBtnBorder.Freeze()
$script:brushLinkBtnFg        = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x94, 0xA3, 0xB8)); $script:brushLinkBtnFg.Freeze()

$script:brushLinkBtnHoverBg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x02, 0x84, 0xC7)); $script:brushLinkBtnHoverBg.Freeze()
$script:brushLinkBtnHoverBdr  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushLinkBtnHoverBdr.Freeze()
$script:brushLinkBtnHoverFg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xFF, 0xFF, 0xFF)); $script:brushLinkBtnHoverFg.Freeze()

# Bảng màu & Kiểu dáng cho Badge biểu tượng ứng dụng (Frosted Badge & Glow)
$script:brushIconBadgeBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(35, 255, 255, 255)); $script:brushIconBadgeBg.Freeze()
$script:brushIconBadgeBorder  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(50, 255, 255, 255)); $script:brushIconBadgeBorder.Freeze()
$script:cornerIconBadge       = New-Object System.Windows.CornerRadius(4)

# Cấu trúc hình học tái sử dụng (Shared Layout Geometries)
$marginCardBorder = New-Object System.Windows.Thickness(5)
$paddingCard      = New-Object System.Windows.Thickness(12, 10, 12, 12)
$marginHeaderGrid = New-Object System.Windows.Thickness(0, 0, 0, 8)
$marginSeparator  = New-Object System.Windows.Thickness(0, 2, 0, 6)
$marginRowBorder  = New-Object System.Windows.Thickness(0, 1, 0, 1)
$paddingRow       = New-Object System.Windows.Thickness(6, 4, 6, 4)
$marginIcon       = New-Object System.Windows.Thickness(7, 0, 8, 0)
$cornerCard       = New-Object System.Windows.CornerRadius(10)
$cornerRow        = New-Object System.Windows.CornerRadius(6)
$thicknessOne     = New-Object System.Windows.Thickness(1)

# Thư mục lưu cache biểu tượng ứng dụng cục bộ
$iconsCacheDir = Join-Path $env:LOCALAPPDATA "DuckUtil\Icons"
if (-not (Test-Path -LiteralPath $iconsCacheDir)) {
    try { New-Item -ItemType Directory -Path $iconsCacheDir -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
} else {
    # Tự động dọn dẹp các icon cache cũ bị sai/trùng lặp (230B Microsoft generic, 588B GitHub Octocat)
    try {
        Get-ChildItem -Path $iconsCacheDir -Filter "*.png" -ErrorAction SilentlyContinue | Where-Object {
            $_.Length -eq 230 -or $_.Length -eq 588
        } | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {}

    # Tự động dọn dẹp cache cho các app đã được nâng cấp URL/Domain chính hãng (v2.2)
    $cacheMarker = Join-Path $iconsCacheDir "cache.v2.2.marker"
    if (-not (Test-Path -LiteralPath $cacheMarker)) {
        try {
            $staleIcons = @(
                "Google.Chrome.png", "Mozilla.Firefox.png", "Opera.OperaGX.png", 
                "GoLang.Go.png", "RARLab.WinRAR.png", "VideoLAN.VLC.png", 
                "EpicGames.EpicGamesLauncher.png", "GIMP.GIMP.png", 
                "Inkscape.Inkscape.png", "CodecGuide.K-LiteCodecPack.Mega.png"
            )
            foreach ($stale in $staleIcons) {
                $stalePath = Join-Path $iconsCacheDir $stale
                if (Test-Path -LiteralPath $stalePath) { Remove-Item -LiteralPath $stalePath -Force -ErrorAction SilentlyContinue }
            }
            Set-Content -LiteralPath $cacheMarker -Value "v2.2" -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

# Trình khóa thực thi đơn nhất (Re-entrancy Guard) chống xung đột tiến trình
$script:isActionRunning = $false

function Invoke-GuardedAction {
    param([string]$ActionName, [scriptblock]$Action)
    if ($script:isActionRunning) {
        Log-Text "[⚠️] Đang có một tác vụ khác đang thực thi ($ActionName). Vui lòng đợi!"
        return
    }
    # Tự động mở rộng Terminal Log khi bắt đầu thực thi hành động để người dùng theo dõi tiến trình
    Expand-TerminalLog
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
$categoryCardMap = [System.Collections.Generic.Dictionary[object, System.Collections.Generic.List[object]]]::new()

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

$catIndex = 0
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
    $rowsInCard = [System.Collections.Generic.List[object]]::new()

    # Header Card
    $headerGrid = New-Object System.Windows.Controls.Grid
    $headerGrid.Margin = $marginHeaderGrid

    $headerText = New-Object System.Windows.Controls.TextBlock
    $headerText.Text = "$cat ($($appsInCat.Count))"
    $headerText.FontSize = 12.5
    $headerText.FontWeight = [System.Windows.FontWeights]::Bold
    $headerText.Foreground = $script:brushHeaderFg
    $headerGrid.Children.Add($headerText) | Out-Null

    $separator = New-Object System.Windows.Controls.Border
    $separator.Height = 1
    $separator.Background = $script:brushSeparator
    $separator.Margin = $marginSeparator

    $cardStack.Children.Add($headerGrid) | Out-Null
    $cardStack.Children.Add($separator) | Out-Null

    # Từng dòng App: Logo + CheckBox + Tên (90%) + Icon Link Web (10%)
    foreach ($app in $appsInCat) {
        $rowBorder = New-Object System.Windows.Controls.Border
        $rowBorder.Height = 28
        $rowBorder.CornerRadius = $cornerRow
        $rowBorder.Padding = New-Object System.Windows.Thickness(6, 0, 6, 0)
        $rowBorder.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
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
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = New-Object System.Windows.GridLength(24, [System.Windows.GridUnitType]::Pixel)
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $col3 = New-Object System.Windows.Controls.ColumnDefinition; $col3.Width = New-Object System.Windows.GridLength(24, [System.Windows.GridUnitType]::Pixel)
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

        # 2. Container Icon Huy hiệu Frosted Glass & Hiệu ứng phát sáng làm nổi Logo tối màu trên nền đen
        $iconBadge = New-Object System.Windows.Controls.Border
        $iconBadge.Width = 20
        $iconBadge.Height = 20
        $iconBadge.CornerRadius = $script:cornerIconBadge
        $iconBadge.Background = $script:brushIconBadgeBg
        $iconBadge.BorderBrush = $script:brushIconBadgeBorder
        $iconBadge.BorderThickness = $thicknessOne
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
        $img.Width = 16; $img.Height = 16
        $img.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $img.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $img.Visibility = [System.Windows.Visibility]::Collapsed

        # Hiệu ứng Outer Rim Glow (hào quang viền trắng) giúp logo màu tối (Notion, Steam, 7-Zip, Obsidian...) nổi bật 100% trên nền đen
        $imgGlow = New-Object System.Windows.Media.Effects.DropShadowEffect
        $imgGlow.Color = [System.Windows.Media.Color]::FromRgb(255, 255, 255)
        $imgGlow.BlurRadius = 3
        $imgGlow.ShadowDepth = 0
        $imgGlow.Opacity = 0.65
        $img.Effect = $imgGlow

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
                $img.Source = $bmp
                $fallbackGlyph.Visibility = [System.Windows.Visibility]::Collapsed
                $img.Visibility = [System.Windows.Visibility]::Visible
            } catch {}
        } else {
            $remoteIconTarget = if (-not [string]::IsNullOrWhiteSpace($app.IconUrl)) {
                $app.IconUrl
            } elseif (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
                "https://www.google.com/s2/favicons?domain=$($app.Domain)&sz=32"
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

                    # Gắn sự kiện DownloadCompleted an toàn với GetNewClosure() để lưu cache không bị đè icon
                    $cacheClosure = {
                        param($sender, $e)
                        try {
                            $fallbackGlyph.Visibility = [System.Windows.Visibility]::Collapsed
                            $img.Visibility = [System.Windows.Visibility]::Visible
                            if ($sender -and -not (Test-Path -LiteralPath $localIconPath)) {
                                $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                                $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($sender))
                                $fs = [System.IO.File]::OpenWrite($localIconPath)
                                $encoder.Save($fs)
                                $fs.Close()
                            }
                        } catch {}
                    }.GetNewClosure()

                    if (-not $bmp.IsDownloading) {
                        # Đã có sẵn trong RAM cache hoặc đã tải xong
                        $fallbackGlyph.Visibility = [System.Windows.Visibility]::Collapsed
                        $img.Visibility = [System.Windows.Visibility]::Visible
                        $img.Source = $bmp
                        if (-not (Test-Path -LiteralPath $localIconPath)) {
                            try {
                                $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                                $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
                                $fs = [System.IO.File]::OpenWrite($localIconPath)
                                $encoder.Save($fs)
                                $fs.Close()
                            } catch {}
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

        # 3. Tên ứng dụng (Căn chỉnh thẳng hàng tuyệt đối với lề trái đồng đều)
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
        [System.Windows.Controls.Grid]::SetColumn($nameText, 2)
        $rowGrid.Children.Add($nameText) | Out-Null

        # 4. Button Link Website ngoài cùng bên phải (Icon Link 🔗 chuẩn, căn thẳng hàng)
        $linkBtn = New-Object System.Windows.Controls.Border
        $linkBtn.Width = 22
        $linkBtn.Height = 18
        $linkBtn.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $linkBtn.Background = $script:brushLinkBtnBg
        $linkBtn.BorderBrush = $script:brushLinkBtnBorder
        $linkBtn.BorderThickness = $thicknessOne
        $linkBtn.Cursor = [System.Windows.Input.Cursors]::Hand
        $linkBtn.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
        $linkBtn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $linkBtn.Margin = New-Object System.Windows.Thickness(0)
        $linkBtn.ToolTip = "Mở trang chủ chính thức: https://$($app.Domain)"
        $linkBtn.Tag = $app.Domain

        $linkIcon = New-Object System.Windows.Controls.TextBlock
        $linkIcon.Text = [char]::ConvertFromUtf32(0x1F517) # 🔗 Link
        $linkIcon.FontFamily = $script:fontSegoeEmoji
        $linkIcon.FontSize = 9.5
        $linkIcon.Foreground = $script:brushLinkBtnFg
        $linkIcon.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $linkIcon.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $linkBtn.Child = $linkIcon

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
            if ($s.Child) { $s.Child.Foreground = $script:brushLinkBtnFg }
        })
        $linkBtn.Add_MouseLeftButtonUp({
            param($s, $e)
            $e.Handled = $true  # Chặn sự kiện nổi bọt để không làm toggle CheckBox
            $domain = $s.Tag
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

        # Hover phát sáng & phục hồi nền trong suốt thanh lịch (Không tô màu nền đỏ/xanh)
        $rowBorder.Add_MouseEnter({
            param($sender, $e)
            $sender.Background = $script:brushRowHover
        })
        $rowBorder.Add_MouseLeave({
            param($sender, $e)
            $sender.Background = $script:brushTransparent
        })

        $rowBorder.Child = $rowGrid
        $cardStack.Children.Add($rowBorder) | Out-Null
        $allItemBorders.Add($rowBorder)
        $rowsInCard.Add($rowBorder)
    }

    $cardBorder.Child = $cardStack
    $categoryCardMap[$cardBorder] = $rowsInCard
    
    # Trọng số chiều cao ước tính: 48px (Header card + Separator) + (Số dòng app * 28px) + 10px (Margin)
    $cardEstimatedHeight = 58 + ($appsInCat.Count * 28)

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
    $catIndex++
}

# ── CÁC HÀNH ĐỘNG CÀI ĐẶT / GỠ / NÂNG CẤP APP ──
Register-Click "btnScanInstalled" {
    Invoke-GuardedAction "Quét ứng dụng" {
        Scan-And-ColorizeApps
    }
}

Register-Click "btnInstall" {
    Invoke-GuardedAction "Cài đặt ứng dụng" {
        $selected = [System.Collections.Generic.List[object]]::new()
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -eq $true) {
                $selected.Add($cb.Tag.App)
            }
        }

        if ($selected.Count -eq 0) {
            Log-Text "[!] Bạn chưa tick chọn ứng dụng nào để cài đặt!"
            return
        }

        $total = $selected.Count
        $idx = 0
        Log-Text "=========================================================="
        Log-Text "🚀 BẮT ĐẦU CÀI ĐẶT $total ỨNG DỤNG ĐÃ ĐÁNH DẤU"
        Log-Text "=========================================================="

        foreach ($app in $selected) {
            $idx++
            if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }
            if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang cài đặt: $($app.Name)..." }
            Log-Text "[$idx/$total] Đang cài: $($app.Name) (ID: $($app.ID))..."

            $code = Run-CliStream "winget" "install --id `"$($app.ID)`" --exact --silent --accept-package-agreements --accept-source-agreements"
            if ($code -eq 0) {
                Log-Text "   [✓ HOÀN THÀNH] $($app.Name)"
            } else {
                Log-Text "   [❌ LỖI] $($app.Name) (Exit Code: $code)"
            }
        }
        if ($txtStatus) { $txtStatus.Text = "Cài đặt hoàn tất!" }
        if ($progressBar) { $progressBar.Value = 100 }
        Scan-And-ColorizeApps
    }
}

Register-Click "btnUninstall" {
    Invoke-GuardedAction "Gỡ cài đặt" {
        $selectedTags = [System.Collections.Generic.List[object]]::new()
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -eq $true) {
                $selectedTags.Add($cb.Tag)
            }
        }

        if ($selectedTags.Count -eq 0) {
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

        $total = $selectedTags.Count
        $idx = 0
        Log-Text "=========================================================="
        Log-Text "🗑️ BẮT ĐẦU GỠ CÀI ĐẶT $total ỨNG DỤNG ĐÃ CHỌN"
        Log-Text "=========================================================="

        foreach ($tag in $selectedTags) {
            $idx++
            $app = $tag.App
            # Ưu tiên sử dụng DetectedId thực tế phát hiện được qua SmartMatcher (Section 3.2)
            $uninstallId = if ($tag.DetectedId) { $tag.DetectedId } else { $app.ID }

            if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }
            if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang gỡ bỏ: $($app.Name)..." }
            Log-Text "[$idx/$total] Đang gỡ: $($app.Name) (Mã gỡ: $uninstallId)..."

            $code = Run-CliStream "winget" "uninstall --id `"$uninstallId`" --silent"
            if ($code -eq 0) {
                Log-Text "   [✓ ĐÃ GỠ THÀNH CÔNG] $($app.Name)"
            } else {
                Log-Text "   [❌ LỖI GỠ] $($app.Name) (Exit Code: $code)"
            }
        }
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

# Chọn tất cả: chỉ chọn các dòng đang hiển thị theo bộ lọc tìm kiếm (Section 3.3)
Register-Click "btnSelectAll" {
    $script:suppressSelectionCount = $true
    try {
        foreach ($row in $allItemBorders) {
            if ($row.Visibility -eq [System.Windows.Visibility]::Visible) {
                $grid = $row.Child
                $cb = $grid.Children[0]
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
    Invoke-GuardedAction "DISM Component Cleanup" {
        Log-Text "[*] Đang dọn dẹp kho linh kiện hệ thống (DISM Component Cleanup)..."
        if ($txtStatus) { $txtStatus.Text = "Đang dọn kho linh kiện..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-DriverStoreCleanup
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
    Invoke-GuardedAction "Dọn dẹp Windows Event Logs" {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Hành động này sẽ xóa toàn bộ nhật ký sự kiện Windows (Application, System, Security...). Bạn có chắc chắn muốn tiếp tục?",
            "Xác nhận dọn dẹp Event Logs",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

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
    Invoke-GuardedAction "Dọn dẹp DriverStore" {
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
