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

    # Xây dựng đối số thực thi cho PowerShell
    if ($isWebSource) {
        $psArgs = "-NoProfile -ExecutionPolicy Bypass -Command `"Invoke-RestMethod -Uri 'https://is.gd/duckutil' | Invoke-Expression`""
    } else {
        $scriptTarget = (Resolve-Path -LiteralPath $PSCommandPath).Path
        $psArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptTarget`""
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
        $wtArgs = "-d `"$workDir`" $psExe $psArgs"
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
    "Name": "Google Chrome",
    "ID": "Google.Chrome",
    "Category": "Trình Duyệt Web",
    "Domain": "google.com",
    "Aliases": [
      "Google Chrome",
      "Google.Chrome",
      "Chrome"
    ],
    "Desc": "Trình duyệt web chuẩn công nghiệp từ Google"
  },
  {
    "Name": "Mozilla Firefox",
    "ID": "Mozilla.Firefox",
    "Category": "Trình Duyệt Web",
    "Domain": "mozilla.org",
    "Aliases": [
      "Mozilla Firefox",
      "Firefox",
      "Mozilla.Firefox"
    ],
    "Desc": "Trình duyệt web mã nguồn mở chú trọng quyền riêng tư"
  },
  {
    "Name": "Brave Browser",
    "ID": "Brave.Brave",
    "Category": "Trình Duyệt Web",
    "Domain": "brave.com",
    "Aliases": [
      "Brave",
      "BraveSoftware",
      "Brave.Brave",
      "Brave Browser"
    ],
    "Desc": "Trình duyệt bảo mật tích hợp công cụ chặn quảng cáo"
  },
  {
    "Name": "LibreWolf",
    "ID": "LibreWolf.LibreWolf",
    "Category": "Trình Duyệt Web",
    "Domain": "librewolf.net",
    "Aliases": [
      "LibreWolf",
      "LibreWolf.LibreWolf"
    ],
    "Desc": "Bản phân phối Firefox bảo mật cao, loại bỏ hoàn toàn đo lường từ xa (telemetry)"
  },
  {
    "Name": "Vivaldi",
    "ID": "VivaldiTechnologies.Vivaldi",
    "Category": "Trình Duyệt Web",
    "Domain": "vivaldi.com",
    "Aliases": [
      "Vivaldi",
      "VivaldiTechnologies.Vivaldi"
    ],
    "Desc": "Trình duyệt hiệu năng cao với khả năng tùy biến giao diện linh hoạt"
  },
  {
    "Name": "Tor Browser",
    "ID": "TorProject.TorBrowser",
    "Category": "Trình Duyệt Web",
    "Domain": "torproject.org",
    "Aliases": [
      "Tor Browser",
      "TorProject",
      "TorProject.TorBrowser"
    ],
    "Desc": "Trình duyệt bảo mật ẩn danh qua mạng định tuyến củ hành (Onion Network)"
  },
  {
    "Name": "Opera GX",
    "ID": "Opera.OperaGX",
    "Category": "Trình Duyệt Web",
    "Domain": "opera.com",
    "Aliases": [
      "Opera GX",
      "Opera",
      "Opera.OperaGX"
    ],
    "Desc": "Trình duyệt tùy chỉnh tài nguyên phần cứng và kiểm soát băng thông mạng"
  },
  {
    "Name": "Discord",
    "ID": "Discord.Discord",
    "Category": "Liên Lạc & Chat",
    "Domain": "discord.com",
    "Aliases": [
      "Discord",
      "Discord.Discord"
    ],
    "Desc": "Nền tảng giao tiếp bằng giọng nói, video và văn bản thời gian thực"
  },
  {
    "Name": "Telegram",
    "ID": "Telegram.TelegramDesktop",
    "Category": "Liên Lạc & Chat",
    "Domain": "telegram.org",
    "Aliases": [
      "Telegram Desktop",
      "Telegram",
      "TelegramDesktop",
      "Telegram.TelegramDesktop"
    ],
    "Desc": "Ứng dụng nhắn tin bảo mật cao và đồng bộ đám mây tức thì"
  },
  {
    "Name": "Signal",
    "ID": "OpenWhisperSystems.Signal",
    "Category": "Liên Lạc & Chat",
    "Domain": "signal.org",
    "Aliases": [
      "Signal",
      "OpenWhisperSystems.Signal"
    ],
    "Desc": "Nền tảng liên lạc bảo mật với công nghệ mã hóa đầu cuối (E2EE)"
  },
  {
    "Name": "Zalo",
    "ID": "VNG.Zalo",
    "Category": "Liên Lạc & Chat",
    "Domain": "zalo.me",
    "Aliases": [
      "Zalo",
      "VNGCorp.Zalo",
      "VNG.Zalo"
    ],
    "Desc": "Ứng dụng nhắn tin và gọi thoại phổ biến tại Việt Nam"
  },
  {
    "Name": "Zoom",
    "ID": "Zoom.Zoom",
    "Category": "Liên Lạc & Chat",
    "Domain": "zoom.us",
    "Aliases": [
      "Zoom",
      "Zoom Workplace",
      "Zoom.Zoom"
    ],
    "Desc": "Nền tảng hội nghị truyền hình và họp trực tuyến doanh nghiệp"
  },
  {
    "Name": "Slack",
    "ID": "SlackTechnologies.Slack",
    "Category": "Liên Lạc & Chat",
    "Domain": "slack.com",
    "Aliases": [
      "Slack",
      "SlackTechnologies.Slack"
    ],
    "Desc": "Nền tảng cộng tác và giao tiếp chuyên nghiệp cho doanh nghiệp"
  },
  {
    "Name": "WhatsApp",
    "ID": "WhatsApp.WhatsApp",
    "Category": "Liên Lạc & Chat",
    "Domain": "whatsapp.com",
    "Aliases": [
      "WhatsApp",
      "WhatsApp.WhatsApp",
      "WhatsApp Desktop"
    ],
    "Desc": "Ứng dụng nhắn tin và gọi thoại quốc tế bảo mật cao"
  },
  {
    "Name": "Microsoft Teams",
    "ID": "Microsoft.Teams",
    "Category": "Liên Lạc & Chat",
    "Domain": "microsoft.com",
    "Aliases": [
      "Microsoft Teams",
      "MSTeams",
      "Microsoft.Teams"
    ],
    "Desc": "Giải pháp cộng tác và hội họp tích hợp Microsoft 365"
  },
  {
    "Name": "VS Code",
    "ID": "Microsoft.VisualStudioCode",
    "Category": "Phát Triển & Dev",
    "Domain": "code.visualstudio.com",
    "Aliases": [
      "Microsoft Visual Studio Code",
      "Visual Studio Code",
      "VS Code",
      "Microsoft.VisualStudioCode"
    ],
    "Desc": "Trình soạn thảo mã nguồn mở mạnh mẽ và mở rộng phong phú từ Microsoft"
  },
  {
    "Name": "Git",
    "ID": "Git.Git",
    "Category": "Phát Triển & Dev",
    "Domain": "git-scm.com",
    "Aliases": [
      "Git",
      "Git.Git"
    ],
    "Desc": "Hệ thống quản lý phiên bản phân tán (Distributed Version Control)"
  },
  {
    "Name": "Windows Terminal",
    "ID": "Microsoft.WindowsTerminal",
    "Category": "Phát Triển & Dev",
    "Domain": "microsoft.com",
    "Aliases": [
      "Windows Terminal",
      "WindowsTerminal",
      "Microsoft.WindowsTerminal",
      "9N0DX20HK701",
      "Bảng điều khiển Windows",
      "wt",
      "wt.exe"
    ],
    "Desc": "Trình giả lập dòng lệnh đa tab hiện đại cho Windows"
  },
  {
    "Name": "Windows Terminal Preview",
    "ID": "Microsoft.WindowsTerminal.Preview",
    "Category": "Phát Triển & Dev",
    "Domain": "microsoft.com",
    "Aliases": [
      "Windows Terminal Preview",
      "WindowsTerminalPreview",
      "Microsoft.WindowsTerminal.Preview",
      "9N8G5RFZ9XK3",
      "Bảng điều khiển Windows (Bản xem trước)",
      "Bản xem trước của Bảng điều khiển Windows",
      "wt preview",
      "wt.exe preview"
    ],
    "Desc": "Phiên bản thử nghiệm sớm các tính năng mới của Windows Terminal"
  },
  {
    "Name": "Python 3.12",
    "ID": "Python.Python.3.12",
    "Category": "Phát Triển & Dev",
    "Domain": "python.org",
    "Aliases": [
      "Python 3.12",
      "Python 3.13",
      "Python",
      "Python.Python.3.12"
    ],
    "Desc": "Ngôn ngữ lập trình thông dịch phổ biến cho AI, dữ liệu và tự động hóa"
  },
  {
    "Name": "Node.js LTS",
    "ID": "OpenJS.NodeJS.LTS",
    "Category": "Phát Triển & Dev",
    "Domain": "nodejs.org",
    "Aliases": [
      "Node.js",
      "OpenJS.NodeJS",
      "OpenJS.NodeJS.LTS",
      "NodeJS"
    ],
    "Desc": "Môi trường thực thi JavaScript phía máy chủ phiên bản hỗ trợ dài hạn (LTS)"
  },
  {
    "Name": "Docker Desktop",
    "ID": "Docker.DockerDesktop",
    "Category": "Phát Triển & Dev",
    "Domain": "docker.com",
    "Aliases": [
      "Docker Desktop",
      "Docker.DockerDesktop"
    ],
    "Desc": "Nền tảng ảo hóa container và công cụ quản trị Docker cho máy trạm"
  },
  {
    "Name": "Notepad++",
    "ID": "Notepad++.Notepad++",
    "Category": "Phát Triển & Dev",
    "Domain": "notepad-plus-plus.org",
    "Aliases": [
      "Notepad++",
      "Notepad++.Notepad++"
    ],
    "Desc": "Trình soạn thảo văn bản và mã nguồn gọn nhẹ, hiệu năng cao"
  },
  {
    "Name": "Postman",
    "ID": "Postman.Postman",
    "Category": "Phát Triển & Dev",
    "Domain": "postman.com",
    "Aliases": [
      "Postman",
      "Postman.Postman"
    ],
    "Desc": "Nền tảng phát triển, kiểm thử và quản lý vòng đời API"
  },
  {
    "Name": "DBeaver CE",
    "ID": "dbeaver.dbeaver",
    "Category": "Phát Triển & Dev",
    "Domain": "dbeaver.io",
    "Aliases": [
      "DBeaver",
      "DBeaver CE",
      "dbeaver.dbeaver"
    ],
    "Desc": "Công cụ quản trị cơ sở dữ liệu đa nền tảng cho nhà phát triển và DBA"
  },
  {
    "Name": "Go Lang",
    "ID": "GoLang.Go",
    "Category": "Phát Triển & Dev",
    "Domain": "golang.org",
    "Aliases": [
      "Go Programming Language",
      "GoLang",
      "GoLang.Go"
    ],
    "Desc": "Ngôn ngữ lập trình mã nguồn mở hiệu năng cao từ Google"
  },
  {
    "Name": "Rust (rustup)",
    "ID": "Rustlang.Rustup",
    "Category": "Phát Triển & Dev",
    "Domain": "rust-lang.org",
    "Aliases": [
      "Rustup",
      "Rust",
      "Rustlang.Rustup"
    ],
    "Desc": "Trình cài đặt và quản lý chuỗi công cụ ngôn ngữ lập trình Rust"
  },
  {
    "Name": "7-Zip",
    "ID": "7zip.7zip",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "7-zip.org",
    "Aliases": [
      "7-Zip",
      "7zip",
      "7zip.7zip"
    ],
    "Desc": "Công cụ nén và giải nén tệp mã nguồn mở với tỷ lệ nén cao"
  },
  {
    "Name": "WinRAR",
    "ID": "RARLab.WinRAR",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "rarlab.com",
    "Aliases": [
      "WinRAR",
      "RARLab.WinRAR"
    ],
    "Desc": "Phần mềm nén và giải nén lưu trữ dữ liệu định dạng RAR và ZIP"
  },
  {
    "Name": "Everything",
    "ID": "voidtools.Everything",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "voidtools.com",
    "Aliases": [
      "Everything",
      "voidtools.Everything"
    ],
    "Desc": "Công cụ chỉ mục và định vị tập tin tức thì trên phân vùng NTFS"
  },
  {
    "Name": "PowerToys",
    "ID": "Microsoft.PowerToys",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "github.com",
    "Aliases": [
      "PowerToys",
      "Microsoft.PowerToys"
    ],
    "Desc": "Bộ tiện ích mở rộng nâng cao năng suất hệ thống từ Microsoft"
  },
  {
    "Name": "Flow Launcher",
    "ID": "Flow-Launcher.Flow-Launcher",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "flowlauncher.com",
    "Aliases": [
      "Flow Launcher",
      "Flow-Launcher",
      "Flow-Launcher.Flow-Launcher"
    ],
    "Desc": "Thanh tìm kiếm và khởi chạy tệp tin, ứng dụng nhanh qua phím tắt"
  },
  {
    "Name": "Revo Uninstaller",
    "ID": "VSRevoGroup.RevoUninstaller",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "revouninstaller.com",
    "Aliases": [
      "Revo Uninstaller",
      "VSRevoGroup.RevoUninstaller"
    ],
    "Desc": "Công cụ gỡ cài đặt phần mềm chuyên sâu và dọn dẹp khóa Registry tồn đọng"
  },
  {
    "Name": "TreeSize Free",
    "ID": "JAMSoftware.TreeSize.Free",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "jam-software.com",
    "Aliases": [
      "TreeSize",
      "TreeSize Free",
      "JAMSoftware.TreeSize.Free"
    ],
    "Desc": "Công cụ phân tích và trực quan hóa dung lượng sử dụng ổ đĩa"
  },
  {
    "Name": "ShareX",
    "ID": "ShareX.ShareX",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "getsharex.com",
    "Aliases": [
      "ShareX",
      "ShareX.ShareX"
    ],
    "Desc": "Công cụ chụp ảnh, quay video màn hình, nhận diện OCR và chia sẻ tệp"
  },
  {
    "Name": "BleachBit",
    "ID": "BleachBit.BleachBit",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "bleachbit.org",
    "Aliases": [
      "BleachBit",
      "BleachBit.BleachBit"
    ],
    "Desc": "Tiện ích dọn dẹp tập tin rác và bảo vệ quyền riêng tư mã nguồn mở"
  },
  {
    "Name": "FanControl",
    "ID": "Rem0o.FanControl",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "github.com",
    "Aliases": [
      "FanControl",
      "Rem0o.FanControl"
    ],
    "Desc": "Phần mềm tinh chỉnh và điều khiển tốc độ quạt làm mát phần cứng máy tính"
  },
  {
    "Name": "VLC Media Player",
    "ID": "VideoLAN.VLC",
    "Category": "Đa Phương Tiện",
    "Domain": "videolan.org",
    "Aliases": [
      "VLC media player",
      "VLC",
      "VideoLAN.VLC"
    ],
    "Desc": "Trình phát đa phương tiện mã nguồn mở tương thích hầu hết định dạng"
  },
  {
    "Name": "OBS Studio",
    "ID": "OBSProject.OBSStudio",
    "Category": "Đa Phương Tiện",
    "Domain": "obsproject.com",
    "Aliases": [
      "OBS Studio",
      "OBSProject.OBSStudio"
    ],
    "Desc": "Phần mềm ghi hình màn hình và truyền phát trực tiếp chuyên nghiệp"
  },
  {
    "Name": "Spotify",
    "ID": "Spotify.Spotify",
    "Category": "Đa Phương Tiện",
    "Domain": "spotify.com",
    "Aliases": [
      "Spotify",
      "Spotify.Spotify"
    ],
    "Desc": "Dịch vụ truyền phát âm nhạc và podcast kỹ thuật số toàn cầu"
  },
  {
    "Name": "GIMP",
    "ID": "GIMP.GIMP",
    "Category": "Đa Phương Tiện",
    "Domain": "gimp.org",
    "Aliases": [
      "GIMP",
      "GIMP.GIMP"
    ],
    "Desc": "Phần mềm xử lý đồ họa và chỉnh sửa hình ảnh mã nguồn mở nâng cao"
  },
  {
    "Name": "Audacity",
    "ID": "Audacity.Audacity",
    "Category": "Đa Phương Tiện",
    "Domain": "audacityteam.org",
    "Aliases": [
      "Audacity",
      "Audacity.Audacity"
    ],
    "Desc": "Phần mềm thu âm và biên tập âm thanh đa kênh mã nguồn mở"
  },
  {
    "Name": "HandBrake",
    "ID": "HandBrake.HandBrake",
    "Category": "Đa Phương Tiện",
    "Domain": "handbrake.fr",
    "Aliases": [
      "HandBrake",
      "HandBrake.HandBrake"
    ],
    "Desc": "Công cụ chuyển mã video mã nguồn mở hỗ trợ tối ưu dung lượng tệp"
  },
  {
    "Name": "Krita",
    "ID": "KDE.Krita",
    "Category": "Đa Phương Tiện",
    "Domain": "krita.org",
    "Aliases": [
      "Krita",
      "KDE.Krita"
    ],
    "Desc": "Phần mềm vẽ đồ họa số, minh họa và diễn hoạt chuyên nghiệp"
  },
  {
    "Name": "K-Lite Codec Mega",
    "ID": "CodecGuide.K-LiteCodecPack.Mega",
    "Category": "Đa Phương Tiện",
    "Domain": "codecguide.com",
    "Aliases": [
      "K-Lite Codec Pack",
      "K-Lite",
      "CodecGuide.K-LiteCodecPack.Mega"
    ],
    "Desc": "Gói bộ giải mã codec âm thanh và video toàn diện cho hệ điều hành Windows"
  },
  {
    "Name": "LibreOffice",
    "ID": "TheDocumentFoundation.LibreOffice",
    "Category": "Văn Phòng & Tài Liệu",
    "Domain": "libreoffice.org",
    "Aliases": [
      "LibreOffice",
      "TheDocumentFoundation.LibreOffice"
    ],
    "Desc": "Bộ ứng dụng văn phòng mã nguồn mở toàn diện tương thích chuẩn tài liệu mở"
  },
  {
    "Name": "Obsidian",
    "ID": "Obsidian.Obsidian",
    "Category": "Văn Phòng & Tài Liệu",
    "Domain": "obsidian.md",
    "Aliases": [
      "Obsidian",
      "Obsidian.Obsidian"
    ],
    "Desc": "Ứng dụng ghi chú và xây dựng cơ sở tri thức cá nhân trên nền tảng Markdown"
  },
  {
    "Name": "Notion",
    "ID": "Notion.Notion",
    "Category": "Văn Phòng & Tài Liệu",
    "Domain": "notion.so",
    "Aliases": [
      "Notion",
      "Notion.Notion"
    ],
    "Desc": "Không gian làm việc tích hợp ghi chú, quản lý tác vụ và dữ liệu cộng tác"
  },
  {
    "Name": "SumatraPDF",
    "ID": "SumatraPDF.SumatraPDF",
    "Category": "Văn Phòng & Tài Liệu",
    "Domain": "sumatrapdfreader.org",
    "Aliases": [
      "SumatraPDF",
      "SumatraPDF.SumatraPDF"
    ],
    "Desc": "Trình đọc tài liệu PDF, ePub, Mobi gọn nhẹ với tốc độ phản hồi cao"
  },
  {
    "Name": "Foxit PDF Reader",
    "ID": "Foxit.FoxitReader",
    "Category": "Văn Phòng & Tài Liệu",
    "Domain": "foxit.com",
    "Aliases": [
      "Foxit PDF Reader",
      "Foxit Reader",
      "Foxit.FoxitReader"
    ],
    "Desc": "Giải pháp xem, ghi chú, biểu mẫu và ký số tài liệu PDF chuẩn doanh nghiệp"
  },
  {
    "Name": "Steam",
    "ID": "Valve.Steam",
    "Category": "Nền Tảng Trò Chơi",
    "Domain": "steampowered.com",
    "Aliases": [
      "Steam",
      "Valve.Steam"
    ],
    "Desc": "Nền tảng phân phối kỹ thuật số và cộng đồng trò chơi điện tử từ Valve"
  },
  {
    "Name": "Epic Games Launcher",
    "ID": "EpicGames.EpicGamesLauncher",
    "Category": "Nền Tảng Trò Chơi",
    "Domain": "epicgames.com",
    "Aliases": [
      "Epic Games Launcher",
      "EpicGames.EpicGamesLauncher"
    ],
    "Desc": "Cửa hàng phân phối trò chơi điện tử và công cụ phát triển Unreal Engine"
  },
  {
    "Name": "GOG Galaxy",
    "ID": "GOG.Galaxy",
    "Category": "Nền Tảng Trò Chơi",
    "Domain": "gog.com",
    "Aliases": [
      "GOG GALAXY",
      "GOG Galaxy",
      "GOG.Galaxy"
    ],
    "Desc": "Nền tảng phân phối và quản lý trò chơi bản quyền không ràng buộc DRM"
  },
  {
    "Name": "MSI Afterburner",
    "ID": "Guru3D.Afterburner",
    "Category": "Nền Tảng Trò Chơi",
    "Domain": "msi.com",
    "Aliases": [
      "MSI Afterburner",
      "Guru3D.Afterburner"
    ],
    "Desc": "Tiện ích giám sát phần cứng, hiển thị OSD và tinh chỉnh tham số card đồ họa"
  },
  {
    "Name": "Playnite",
    "ID": "Playnite.Playnite",
    "Category": "Nền Tảng Trò Chơi",
    "Domain": "playnite.link",
    "Aliases": [
      "Playnite",
      "Playnite.Playnite"
    ],
    "Desc": "Trình quản lý và hợp nhất thư viện trò chơi đa nền tảng mã nguồn mở"
  },
  {
    "Name": "qBittorrent",
    "ID": "qBittorrent.qBittorrent",
    "Category": "Lưu Trữ & Truyền Tệp",
    "Domain": "qbittorrent.org",
    "Aliases": [
      "qBittorrent",
      "qBittorrent.qBittorrent"
    ],
    "Desc": "Trình khách BitTorrent mã nguồn mở không quảng cáo với giao diện trực quan"
  },
  {
    "Name": "LocalSend",
    "ID": "LocalSend.LocalSend",
    "Category": "Lưu Trữ & Truyền Tệp",
    "Domain": "localsend.org",
    "Aliases": [
      "LocalSend",
      "LocalSend.LocalSend"
    ],
    "Desc": "Giải pháp truyền tập tin ngang hàng an toàn qua mạng cục bộ không cần Internet"
  },
  {
    "Name": "WinSCP",
    "ID": "WinSCP.WinSCP",
    "Category": "Lưu Trữ & Truyền Tệp",
    "Domain": "winscp.net",
    "Aliases": [
      "WinSCP",
      "winscp3_is1",
      "WinSCP.WinSCP"
    ],
    "Desc": "Trình khách truyền tập tin đồ họa hỗ trợ giao thức SFTP, SCP, FTPS và WebDAV"
  },
  {
    "Name": "FileZilla",
    "ID": "TimKosse.FileZilla.Client",
    "Category": "Lưu Trữ & Truyền Tệp",
    "Domain": "filezilla-project.org",
    "Aliases": [
      "FileZilla Client",
      "FileZilla",
      "TimKosse.FileZilla.Client"
    ],
    "Desc": "Giải pháp truyền tập tin mã nguồn mở hỗ trợ giao thức FTP, FTPS và SFTP"
  },
  {
    "Name": "Rclone",
    "ID": "Rclone.Rclone",
    "Category": "Lưu Trữ & Truyền Tệp",
    "Domain": "rclone.org",
    "Aliases": [
      "Rclone",
      "Rclone.Rclone"
    ],
    "Desc": "Công cụ dòng lệnh đồng bộ, sao lưu và gắn kết dịch vụ lưu trữ đám mây"
  },
  {
    "Name": "Bitwarden",
    "ID": "Bitwarden.Bitwarden",
    "Category": "Bảo Mật & Mạng",
    "Domain": "bitwarden.com",
    "Aliases": [
      "Bitwarden",
      "Bitwarden.Bitwarden"
    ],
    "Desc": "Trình quản lý mật khẩu mã nguồn mở với chuẩn mã hóa đầu cuối zero-knowledge"
  },
  {
    "Name": "KeePassXC",
    "ID": "KeePassXCTeam.KeePassXC",
    "Category": "Bảo Mật & Mạng",
    "Domain": "keepassxc.org",
    "Aliases": [
      "KeePassXC",
      "KeePassXCTeam.KeePassXC"
    ],
    "Desc": "Trình quản lý cơ sở dữ liệu mật khẩu ngoại tuyến an toàn mã nguồn mở"
  },
  {
    "Name": "Cryptomator",
    "ID": "Cryptomator.Cryptomator",
    "Category": "Bảo Mật & Mạng",
    "Domain": "cryptomator.org",
    "Aliases": [
      "Cryptomator",
      "Cryptomator.Cryptomator"
    ],
    "Desc": "Giải pháp mã hóa dữ liệu phía máy khách độc lập cho lưu trữ đám mây"
  },
  {
    "Name": "ProtonVPN",
    "ID": "ProtonTechnologies.ProtonVPN",
    "Category": "Bảo Mật & Mạng",
    "Domain": "protonvpn.com",
    "Aliases": [
      "Proton VPN",
      "ProtonVPN",
      "Proton.ProtonVPN",
      "ProtonTechnologies.ProtonVPN"
    ],
    "Desc": "Dịch vụ mạng riêng ảo (VPN) bảo mật cao với chính sách không lưu nhật ký (no-logs)"
  },
  {
    "Name": "RustDesk",
    "ID": "RustDesk.RustDesk",
    "Category": "Bảo Mật & Mạng",
    "Domain": "rustdesk.com",
    "Aliases": [
      "RustDesk",
      "RustDesk.RustDesk"
    ],
    "Desc": "Phần mềm điều khiển máy tính từ xa mã nguồn mở hỗ trợ tự triển khai máy chủ"
  },
  {
    "Name": "Wireshark",
    "ID": "WiresharkFoundation.Wireshark",
    "Category": "Bảo Mật & Mạng",
    "Domain": "wireshark.org",
    "Aliases": [
      "Wireshark",
      "WiresharkFoundation.Wireshark"
    ],
    "Desc": "Công cụ phân tích giao thức và bắt gói tin mạng hàng đầu cho chuyên gia CNTT"
  },
  {
    "Name": "VC++ Redist 2015-2022",
    "ID": "Microsoft.VCRedist.2015+.x64",
    "Category": "Thư Viện Cốt Lõi",
    "Domain": "microsoft.com",
    "Aliases": [
      "Visual C++",
      "Microsoft Visual C++",
      "Microsoft Visual C++ 2015-2022 Redistributable",
      "Microsoft.VCRedist.2015+.x64"
    ],
    "Desc": "Gói thư viện thời gian chạy Microsoft Visual C++ cần thiết cho các ứng dụng Windows"
  },
  {
    "Name": ".NET Desktop Runtime 8",
    "ID": "Microsoft.DotNet.DesktopRuntime.8",
    "Category": "Thư Viện Cốt Lõi",
    "Domain": "microsoft.com",
    "Aliases": [
      "Microsoft Windows Desktop Runtime - 8",
      "DesktopRuntime.8",
      "Microsoft .NET Desktop Runtime 8",
      "Microsoft.DotNet.DesktopRuntime.8"
    ],
    "Desc": "Môi trường thực thi cho các ứng dụng máy tính Windows xây dựng trên nền .NET 8"
  },
  {
    "Name": "DirectX End-User",
    "ID": "Microsoft.DirectX",
    "Category": "Thư Viện Cốt Lõi",
    "Domain": "microsoft.com",
    "Aliases": [
      "DirectX",
      "Microsoft DirectX",
      "DirectX End-User Runtimes",
      "Microsoft.DirectX"
    ],
    "Desc": "Bộ thư viện thời gian chạy công nghệ đa phương tiện và đồ họa DirectX"
  },
  {
    "Name": "Java OpenJDK 21",
    "ID": "EclipseAdoptium.Temurin.21.JDK",
    "Category": "Thư Viện Cốt Lõi",
    "Domain": "adoptium.net",
    "Aliases": [
      "Eclipse Temurin",
      "Temurin",
      "Amazon Corretto",
      "Eclipse Temurin JDK with Hotspot 21",
      "EclipseAdoptium.Temurin.21.JDK"
    ],
    "Desc": "Môi trường phát triển và thực thi Java chuẩn doanh nghiệp phiên bản hỗ trợ dài hạn (LTS)"
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
    TextOptions.TextRenderingMode="ClearType">

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
            <RowDefinition Height="Auto"/> <!-- Top App Header -->
            <RowDefinition Height="Auto"/> <!-- Main Nav Tab Bar -->
            <RowDefinition Height="*"/>    <!-- Main Viewport -->
            <RowDefinition Height="Auto"/> <!-- Status & Progress Bar -->
            <RowDefinition Height="150"/>  <!-- Cyber Terminal Log -->
        </Grid.RowDefinitions>

        <!-- ═══ 1. TOP APP HEADER ═══ -->
        <Border Grid.Row="0" Background="#0B0E15" Padding="22,13" BorderBrush="#181E2C" BorderThickness="0,0,0,1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="380"/>
                </Grid.ColumnDefinitions>

                <!-- Brand & Logo -->
                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Background="#131A2B" BorderBrush="#202D47" BorderThickness="1"
                            CornerRadius="10" Width="42" Height="42" Margin="0,0,14,0">
                        <TextBlock Text="🦆" FontSize="22" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <StackPanel VerticalAlignment="Center">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <TextBlock Text="DUCK UTIL" FontSize="20" FontWeight="Black" Foreground="#F8FAFC"/>
                            <Border Background="#0284C7" BorderBrush="#38BDF8" BorderThickness="1"
                                    CornerRadius="5" Margin="10,0,0,0" Padding="7,2" VerticalAlignment="Center">
                                <TextBlock Text="PRO SUITE" FontSize="9.5" FontWeight="ExtraBold" Foreground="#FFFFFF"/>
                            </Border>
                        </StackPanel>
                        <TextBlock Text="Windows Package Manager &amp; System Maintenance Suite"
                                   FontSize="11.5" Foreground="#64748B" Margin="0,2,0,0"/>
                    </StackPanel>
                </StackPanel>

                <!-- Modern Search Box -->
                <Border Grid.Column="2" Background="#111622" CornerRadius="8" BorderBrush="#243044" BorderThickness="1" Padding="12,7" VerticalAlignment="Center">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="🔍" Foreground="#64748B" VerticalAlignment="Center" Margin="0,0,8,0" FontSize="12"/>
                        <TextBox Grid.Column="1" Name="txtSearch" Background="Transparent" Foreground="#F8FAFC"
                                 BorderThickness="0" FontSize="12.5" VerticalAlignment="Center"
                                 CaretBrush="#38BDF8"
                                 ToolTip="Gõ để lọc ứng dụng ngay lập tức theo tên hoặc ID..."/>
                    </Grid>
                </Border>
            </Grid>
        </Border>

        <!-- ═══ 2. MAIN NAV TAB BAR ═══ -->
        <Border Grid.Row="1" Background="#0D1018" Padding="18,0" BorderBrush="#181E2C" BorderThickness="0,0,0,1">
            <StackPanel Orientation="Horizontal">
                <Button Name="navBtnApps" Content="📦 ỨNG DỤNG (APPLICATIONS)" Style="{StaticResource NavTabButton}"
                        BorderBrush="#0EA5E9" Foreground="#F8FAFC"/>
                <Button Name="navBtnRepair" Content="🔧 GỠ LỖI &amp; SỬA HỆ THỐNG" Style="{StaticResource NavTabButton}"/>
                <Button Name="navBtnDrivers" Content="🚗 QUẢN LÝ &amp; GỠ LỖI DRIVER" Style="{StaticResource NavTabButton}"/>
            </StackPanel>
        </Border>

        <!-- ═══ 3. MAIN VIEWPORT (TAB CONTROL) ═══ -->
        <TabControl Grid.Row="2" Name="MainTabControl" Background="Transparent" BorderThickness="0">
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

                    <!-- Lưới Card 4 CỘT RỘNG RÃI (ItemWidth = 296) -->
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="14,12">
                        <WrapPanel Name="CardsContainer" ItemWidth="296" Orientation="Horizontal"/>
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
                                <TextBlock Text="Giải phóng dung lượng ổ C bị chiếm dụng bởi tệp tạm và nạp lại thanh Taskbar khi bị treo."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnClearTemp" Content="Dọn Sạch Thư Mục Temp &amp; Cache Rác" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="16,10"/>
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

        <!-- ═══ 4. STATUS & PROGRESS BAR ═══ -->
        <Border Grid.Row="3" Background="#0A0D14" Padding="20,7" BorderBrush="#181E2C" BorderThickness="0,1,0,0">
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

        <!-- ═══ 5. CYBER TERMINAL LOG ═══ -->
        <Border Grid.Row="4" Background="#05070B" Padding="16,8" BorderBrush="#141924" BorderThickness="0,1,0,0">
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
                    <Button Name="btnClearLog" Content="Xóa Log" HorizontalAlignment="Right"
                            Background="Transparent" Foreground="#64748B" BorderThickness="0" Cursor="Hand" FontSize="11" Padding="6,2"/>
                </Grid>
                <TextBox Grid.Row="1" Name="txtLog" Background="Transparent" Foreground="#34D399"
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

# ── FUNCTION: QUÉT & PHÂN LOẠI MÀU PHIÊN BẢN (TRẮNG / XANH / ĐỎ) ──

# Bộ nhớ đệm tĩnh lưu trữ Brush của WPF giúp tối ưu render và triệt tiêu Garbage Collection
$script:brushOutdatedBg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x2A, 0x12, 0x15))
$script:brushOutdatedFg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF8, 0x71, 0x71))
$script:brushLatestBg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x0D, 0x28, 0x18))
$script:brushLatestFg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x34, 0xD3, 0x99))
$script:brushNoneBg     = [System.Windows.Media.Brushes]::Transparent
$script:brushNoneFg     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xFF, 0xFF, 0xFF))

$script:brushOutdatedBg.Freeze()
$script:brushOutdatedFg.Freeze()
$script:brushLatestBg.Freeze()
$script:brushLatestFg.Freeze()
$script:brushNoneFg.Freeze()

function Get-CleanAppName {
    param([string]$RawName)
    if ([string]::IsNullOrWhiteSpace($RawName)) { return "" }
    $clean = ($RawName -replace '\(.*?\)', '').Trim().ToLowerInvariant()
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
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "winget"
        $pinfo.Arguments = "list --disable-interactivity"
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

        # Đọc dữ liệu bất đồng bộ kèm bơm Application::DoEvents để thanh tiến trình & UI luôn hoạt động
        $readTask = $p.StandardOutput.ReadToEndAsync()
        while (-not $readTask.IsCompleted) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 30
        }
        $rawList = $readTask.Result
        $p.WaitForExit()
    } catch {
        Log-Text "[!] Lỗi khi quét danh sách ứng dụng qua WinGet: $($_.Exception.Message)"
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        return
    }

    # Phân tích danh sách đã cài đặt từ winget với bộ tách cột theo tọa độ Header chuẩn xác
    $lines = $rawList -split "`r?`n"
    $separatorIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^---\s*---') {
            $separatorIndex = $i
            break
        }
    }

    $idMap        = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $nameMap      = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $cleanNameMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $installedList = [System.Collections.Generic.List[object]]::new()

    if ($separatorIndex -gt 0) {
        $headerLine = $lines[$separatorIndex - 1]
        $idIdx    = $headerLine.IndexOf("Id")
        if ($idIdx -lt 0) { $idIdx = $headerLine.IndexOf("ID") }
        $verIdx   = $headerLine.IndexOf("Version")
        $availIdx = $headerLine.IndexOf("Available")
        $srcIdx   = $headerLine.IndexOf("Source")

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
                # Fallback tách cột bằng khoảng trắng nếu độ dài chuỗi không khớp
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
                $itemObj = [PSCustomObject]@{
                    Name      = $appName
                    ID        = $appId
                    Version   = $version
                    Available = $avail
                    HasUpdate = $hasUpdate
                }

                $installedList.Add($itemObj)
                if (-not $idMap.ContainsKey($appId)) { $idMap[$appId] = $itemObj }
                if (-not [string]::IsNullOrWhiteSpace($appName) -and -not $nameMap.ContainsKey($appName)) { $nameMap[$appName] = $itemObj }
                $clean = Get-CleanAppName $appName
                if ($clean.Length -ge 3 -and -not $cleanNameMap.ContainsKey($clean)) { $cleanNameMap[$clean] = $itemObj }
            }
        }
    } else {
        # Fallback hoàn toàn cho phiên bản winget không in header tiêu chuẩn
        foreach ($line in $lines) {
            if (-not [string]::IsNullOrWhiteSpace($line) -and -not ($line -like "---*")) {
                $cols = [System.Text.RegularExpressions.Regex]::Split($line.Trim(), '\s{2,}')
                if ($cols.Count -ge 2) {
                    $appName = $cols[0].Trim()
                    $appId   = $cols[1].Trim()
                    $version = if ($cols.Count -ge 3) { $cols[2].Trim() } else { "" }
                    $avail   = if ($cols.Count -ge 4) { $cols[3].Trim() } else { "" }
                    $hasUpdate = ($cols.Count -ge 5 -or ($cols.Count -eq 4 -and $avail -ne "winget" -and $avail -ne "msstore" -and $avail -ne ""))

                    $itemObj = [PSCustomObject]@{
                        Name      = $appName
                        ID        = $appId
                        Version   = $version
                        Available = $avail
                        HasUpdate = $hasUpdate
                    }

                    $installedList.Add($itemObj)
                    if (-not $idMap.ContainsKey($appId)) { $idMap[$appId] = $itemObj }
                    if (-not [string]::IsNullOrWhiteSpace($appName) -and -not $nameMap.ContainsKey($appName)) { $nameMap[$appName] = $itemObj }
                    $clean = Get-CleanAppName $appName
                    if ($clean.Length -ge 3 -and -not $cleanNameMap.ContainsKey($clean)) { $cleanNameMap[$clean] = $itemObj }
                }
            }
        }
    }

    # Bộ nhớ đệm tra cứu đa bí danh (Multi-Alias Lookup Cache)
    $lookupCache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Find-InstalledAppFast {
        param($targetApp)

        $targetId = $targetApp.ID
        $cachedMatch = $null
        if ($lookupCache.TryGetValue($targetId, [ref]$cachedMatch)) {
            return $cachedMatch
        }

        # 1. Exact ID
        $match = $null
        if ($idMap.TryGetValue($targetId, [ref]$match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        # 2. Exact Name
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

        # 4. Clean Name match
        $cleanTarget = Get-CleanAppName $targetApp.Name
        if ($cleanTarget.Length -ge 3 -and $cleanNameMap.TryGetValue($cleanTarget, [ref]$match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        # 5. Fuzzy / Substring fallback quét nhanh trên danh sách
        if ($targetApp.Aliases) {
            foreach ($alias in $targetApp.Aliases) {
                $al = $alias.ToLowerInvariant()
                foreach ($item in $installedList) {
                    if ($item.ID.ToLowerInvariant().Contains($al) -or $item.Name.ToLowerInvariant().StartsWith($al)) {
                        $lookupCache[$targetId] = $item
                        return $item
                    }
                }
            }
        }

        if ($cleanTarget.Length -ge 3) {
            foreach ($item in $installedList) {
                $cleanItem = Get-CleanAppName $item.Name
                if ($cleanItem -eq $cleanTarget -or $cleanItem.StartsWith("$cleanTarget ") -or $cleanItem.StartsWith($cleanTarget)) {
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

        $info = Find-InstalledAppFast $app

        if ($info) {
            $countInstalled++

            if ($info.HasUpdate -eq $true) {
                # ── 🔴 BẢN CŨ: Tên ĐỎ rực rỡ + Nền đỏ sẫm ──
                $countOutdated++
                $row.Tag.Status = "OUTDATED"
                $row.Background = $script:brushOutdatedBg
                $tb.Foreground = $script:brushOutdatedFg
                $updateBadge = if ($info.Available) { " (Có bản: $($info.Available))" } else { " (Có bản mới)" }
                $tb.Text = "$($app.Name)  ⚠️$updateBadge"
                $tb.ToolTip = "$($app.Name)`nĐang cài: $($info.Version)`nCó bản mới: $($info.Available)`nID phát hiện: $($info.ID)"
            } else {
                # ── 🟢 BẢN MỚI NHẤT: Tên XANH LÁ + Nền xanh sẫm ──
                $countLatest++
                $row.Tag.Status = "LATEST"
                $row.Background = $script:brushLatestBg
                $tb.Foreground = $script:brushLatestFg
                $tb.Text = "$($app.Name)  ✓ (Mới nhất)"
                $tb.ToolTip = "$($app.Name)`nPhiên bản: $($info.Version) (Mới nhất)`nID phát hiện: $($info.ID)"
            }
        } else {
            # ── ⚪ CHƯA CÀI ĐẶT: Tên TRẮNG + Nền trong suốt ──
            $row.Tag.Status = "NONE"
            $row.Background = $script:brushNoneBg
            $tb.Foreground = $script:brushNoneFg
            $tb.Text = $app.Name
            $tb.ToolTip = "$($app.Name)`nTrạng thái: Chưa cài đặt`nID: $($app.ID)`n$($app.Desc)"
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
        Quét và liệt kê tất cả các thiết bị phần cứng bị lỗi, thiếu driver hoặc chấm than vàng.
    #>
    try {
        return @(Get-PnpDevice -ErrorAction Stop | Where-Object { $_.Present -eq $true -and $_.Status -ne 'OK' })
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
    Run-CliStream "pnputil.exe" "/scan-devices"
}

function Invoke-DriverStoreCleanup {
    <#
    .SYNOPSIS
        Dọn dẹp và giải phóng các bản Driver cũ không còn dùng trong DriverStore.
    #>
    Run-CliStream "dism.exe" "/Online /Cleanup-Image /StartComponentCleanup /ResetBase"
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
        return $true
    } catch {
        Log-Text "[*] Export-WindowsDriver không khả dụng hoặc bị từ chối, chuyển sang pnputil.exe..."
        $exitCode = Run-CliStream "pnputil.exe" "/export-driver * `"$Destination`""
        return ($exitCode -eq 0)
    }
}

# ── FUNCTION: CÁC TIỆN ÍCH SỬA LỖI HỆ THỐNG (SYSTEM REPAIRS) ──

function Reset-WindowsUpdateEngine {
    <#
    .SYNOPSIS
        Khởi tạo lại toàn bộ dịch vụ Windows Update và xóa cache bị lỗi/kẹt.
    #>
    Log-Text "[*] Đang dừng các dịch vụ Windows Update & BITS..."
    Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "bits" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "cryptsvc" -Force -ErrorAction SilentlyContinue

    Log-Text "[*] Đang làm mới bộ nhớ đệm SoftwareDistribution và Catroot2..."
    $sdPath = "C:\Windows\SoftwareDistribution"
    if (Test-Path -LiteralPath $sdPath) {
        Rename-Item -LiteralPath $sdPath -NewName "SoftwareDistribution.bak_$(Get-Random)" -Force -ErrorAction SilentlyContinue
    }
    $crPath = "C:\Windows\System32\catroot2"
    if (Test-Path -LiteralPath $crPath) {
        Rename-Item -LiteralPath $crPath -NewName "catroot2.bak_$(Get-Random)" -Force -ErrorAction SilentlyContinue
    }

    Log-Text "[*] Khởi động lại các dịch vụ hệ thống..."
    Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    Start-Service -Name "bits" -ErrorAction SilentlyContinue
    Start-Service -Name "cryptsvc" -ErrorAction SilentlyContinue
    Log-Text "[✓] Đã khởi tạo lại dịch vụ Windows Update thành công!"
}

function Invoke-SystemFileCheck {
    <#
    .SYNOPSIS
        Chạy SFC Scan kiểm tra toàn vẹn file hệ thống.
    #>
    Run-CliStream "sfc.exe" "/scannow"
}

function Invoke-DismRestoreHealth {
    <#
    .SYNOPSIS
        Khôi phục kho linh kiện Windows qua DISM RestoreHealth từ server Microsoft.
    #>
    Run-CliStream "dism.exe" "/Online /Cleanup-Image /RestoreHealth"
}

function Clear-DnsResolverCache {
    <#
    .SYNOPSIS
        Làm mới bộ nhớ đệm DNS.
    #>
    Run-CliStream "ipconfig.exe" "/flushdns"
}

function Reset-NetworkInterfaceStack {
    <#
    .SYNOPSIS
        Khôi phục danh mục Winsock Catalog và TCP/IP Stack.
    #>
    Run-CliStream "netsh.exe" "winsock reset"
    Run-CliStream "netsh.exe" "int ip reset"
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
        Xóa sạch nhật ký sự kiện Windows Event Logs.
    #>
    Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName)
        } catch {}
    }
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
$txtSearch         = $window.FindName("txtSearch")
$txtSelectionCount = $window.FindName("txtSelectionCount")
$cardsContainer    = $window.FindName("CardsContainer")

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

# Trình khóa thực thi đơn nhất (Re-entrancy Guard) chống xung đột tiến trình
$script:isActionRunning = $false

function Invoke-GuardedAction {
    param([string]$ActionName, [scriptblock]$Action)
    if ($script:isActionRunning) {
        Log-Text "[⚠️] Đang có một tác vụ khác đang thực thi ($ActionName). Vui lòng đợi!"
        return
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

foreach ($cat in $categories) {
    $cardBorder = New-Object System.Windows.Controls.Border
    $cardBorder.Background = $script:brushCardBg
    $cardBorder.BorderBrush = $script:brushCardBorder
    $cardBorder.BorderThickness = $thicknessOne
    $cardBorder.CornerRadius = $cornerCard
    $cardBorder.Margin = $marginCardBorder
    $cardBorder.Padding = $paddingCard

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

    # Từng dòng App: Logo + CheckBox + Tên
    foreach ($app in $appsInCat) {
        $rowBorder = New-Object System.Windows.Controls.Border
        $rowBorder.CornerRadius = $cornerRow
        $rowBorder.Padding = $paddingRow
        $rowBorder.Margin = $marginRowBorder
        $rowBorder.Background = $script:brushTransparent
        $rowBorder.Cursor = [System.Windows.Input.Cursors]::Hand

        # Tiền tính toán chuỗi tìm kiếm để bộ lọc TextChanged chạy tức thì
        $aliasText = if ($app.Aliases) { $app.Aliases -join " " } else { "" }
        $searchIndex = "$($app.Name) $($app.ID) $($app.Category) $aliasText $($app.Desc)".ToLowerInvariant()

        $rowBorder.Tag = @{
            App         = $app
            Status      = "NONE"
            CardBorder  = $cardBorder
            SearchIndex = $searchIndex
        }

        $rowGrid = New-Object System.Windows.Controls.Grid
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = [System.Windows.GridLength]::Auto
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = [System.Windows.GridLength]::Auto
        $col3 = New-Object System.Windows.Controls.ColumnDefinition; $col3.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $rowGrid.ColumnDefinitions.Add($col1) | Out-Null
        $rowGrid.ColumnDefinitions.Add($col2) | Out-Null
        $rowGrid.ColumnDefinitions.Add($col3) | Out-Null

        # 1. CheckBox
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $cb.Tag = $app
        $cb.Add_Checked({ Update-SelectionCount })
        $cb.Add_Unchecked({ Update-SelectionCount })
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $rowGrid.Children.Add($cb) | Out-Null
        $allCheckBoxes.Add($cb)

        # 2. Logo Icon chính hãng (Nạp bất đồng bộ, an toàn không chặn render)
        $img = New-Object System.Windows.Controls.Image
        $img.Width = 16; $img.Height = 16
        $img.Margin = $marginIcon
        $img.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        if (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
            try {
                $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                $bmp.BeginInit()
                $bmp.UriSource = New-Object System.Uri("https://www.google.com/s2/favicons?domain=$($app.Domain)&sz=32", [System.UriKind]::Absolute)
                $bmp.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::DelayCreation
                $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnDemand
                $bmp.EndInit()
                $img.Source = $bmp
            } catch {}
        }
        [System.Windows.Controls.Grid]::SetColumn($img, 1)
        $rowGrid.Children.Add($img) | Out-Null

        # 3. Tên ứng dụng
        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $app.Name
        $nameText.Foreground = $script:brushTextWhite
        $nameText.FontSize = 12
        $nameText.FontWeight = [System.Windows.FontWeights]::SemiBold
        $nameText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $nameText.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $nameText.ToolTip = "$($app.Name)`nID: $($app.ID)`n$($app.Desc)"
        [System.Windows.Controls.Grid]::SetColumn($nameText, 2)
        $rowGrid.Children.Add($nameText) | Out-Null

        # Tối ưu nhấp chọn toàn dòng mượt mà, phân lập rõ click CheckBox và click nền để chống giật/lặp sự kiện
        $rowBorder.Add_MouseLeftButtonUp({
            param($sender, $e)
            $src = $e.OriginalSource
            $isCb = $false
            while ($src -ne $null -and $src -ne $sender) {
                if ($src -is [System.Windows.Controls.CheckBox]) {
                    $isCb = $true
                    break
                }
                if ($src -is [System.Windows.Media.Visual]) {
                    $src = [System.Windows.Media.VisualTreeHelper]::GetParent($src)
                } else {
                    break
                }
            }
            if (-not $isCb) {
                $cb.IsChecked = -not $cb.IsChecked
            }
        })

        # Hover phát sáng & phục hồi màu trạng thái cực nhanh nhờ Frozen Brushes
        $rowBorder.Add_MouseEnter({
            if ($rowBorder.Tag.Status -eq "NONE") {
                $rowBorder.Background = $script:brushRowHover
            }
        })
        $rowBorder.Add_MouseLeave({
            $status = $rowBorder.Tag.Status
            if ($status -eq "LATEST") {
                $rowBorder.Background = $script:brushLatestBg
            } elseif ($status -eq "OUTDATED") {
                $rowBorder.Background = $script:brushOutdatedBg
            } else {
                $rowBorder.Background = $script:brushTransparent
            }
        })

        $rowBorder.Child = $rowGrid
        $cardStack.Children.Add($rowBorder) | Out-Null
        $allItemBorders.Add($rowBorder)
        $rowsInCard.Add($rowBorder)
    }

    $cardBorder.Child = $cardStack
    $categoryCardMap[$cardBorder] = $rowsInCard
    if ($cardsContainer) {
        $cardsContainer.Children.Add($cardBorder) | Out-Null
    }
}

# ── LOGIC TÌM KIẾM & BỘ LỌC TỐC ĐỘ CAO (INDEXED SEARCH) ──
if ($txtSearch) {
    $txtSearch.Add_TextChanged({
        $keyword = $txtSearch.Text.Trim().ToLowerInvariant()
        $isEmpty = [string]::IsNullOrEmpty($keyword)

        foreach ($entry in $categoryCardMap.GetEnumerator()) {
            $card = $entry.Key
            $rows = $entry.Value
            $visibleRowsCount = 0

            foreach ($row in $rows) {
                $matched = $isEmpty -or ($row.Tag.SearchIndex.Contains($keyword))
                if ($matched) {
                    $row.Visibility = [System.Windows.Visibility]::Visible
                    $visibleRowsCount++
                } else {
                    $row.Visibility = [System.Windows.Visibility]::Collapsed
                }
            }

            # Ẩn cả khung Card Category nếu không có ứng dụng nào khớp từ khóa
            if ($isEmpty -or $visibleRowsCount -gt 0) {
                $card.Visibility = [System.Windows.Visibility]::Visible
            } else {
                $card.Visibility = [System.Windows.Visibility]::Collapsed
            }
        }
    })
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
                $selected.Add($cb.Tag)
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
        $selected = [System.Collections.Generic.List[object]]::new()
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -eq $true) {
                $selected.Add($cb.Tag)
            }
        }

        if ($selected.Count -eq 0) {
            Log-Text "[!] Bạn chưa chọn ứng dụng nào để gỡ cài đặt!"
            return
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Bạn có chắc chắn muốn gỡ bỏ $($selected.Count) ứng dụng đã chọn?",
            "Xác nhận gỡ cài đặt",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $total = $selected.Count
        $idx = 0
        Log-Text "=========================================================="
        Log-Text "🗑️ BẮT ĐẦU GỠ CÀI ĐẶT $total ỨNG DỤNG ĐÃ CHỌN"
        Log-Text "=========================================================="

        foreach ($app in $selected) {
            $idx++
            if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }
            if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang gỡ bỏ: $($app.Name)..." }
            Log-Text "[$idx/$total] Đang gỡ: $($app.Name) (ID: $($app.ID))..."

            $code = Run-CliStream "winget" "uninstall --id `"$($app.ID)`" --silent"
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

Register-Click "btnSelectAll" {
    $script:suppressSelectionCount = $true
    try {
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -ne $true) {
                $cb.IsChecked = $true
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
        Log-Text "[*] Đang gửi tín hiệu yêu cầu Windows tìm kiếm bản cập nhật mới..."
        Start-Process "usoclient" -ArgumentList "StartInteractiveScan" -NoNewWindow
        Log-Text "[✓] Đã kích hoạt USOClient quét cập nhật."
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
                Log-Text "     Trạng thái: $($d.Status) | Vấn đề: $($d.Problem)"
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
        Start-Process "usoclient" -ArgumentList "StartScan" -NoNewWindow

        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Đã gỡ lỗi kẹt driver update" }
        Log-Text "[✓] Hoàn thành! Lỗi kẹt tải driver đã được dọn sạch."
    }
}

Register-Click "btnScanWindowsUpdateDrivers" {
    Invoke-GuardedAction "Quét driver từ Windows Update" {
        Log-Text "[*] Đang kích hoạt quét driver từ Microsoft Windows Update..."
        Start-Process "usoclient" -ArgumentList "StartInteractiveScan" -NoNewWindow
        Log-Text "[✓] Đã gửi lệnh tìm kiếm Driver mới qua Windows Update."
    }
}

Register-Click "btnCleanDriverStore" {
    Invoke-GuardedAction "Dọn dẹp DriverStore" {
        Log-Text "[*] Đang quét và dọn dẹp các phiên bản driver cũ trong DriverStore..."
        if ($txtStatus) { $txtStatus.Text = "Đang dọn dẹp DriverStore..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-DriverStoreCleanup
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn dẹp DriverStore hoàn tất" }
        Log-Text "[✓] Đã dọn dẹp sạch sẽ các bản driver cũ."
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
