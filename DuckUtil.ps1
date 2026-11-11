# ==============================================================================
#                     DUCK UTIL - CYBER OBSIDIAN SUITE
#       Modular Windows Package Manager & System Maintenance Architecture
# ==============================================================================

# 1. TỰ ĐỘNG CHUYỂN SANG QUYỀN ADMINISTRATOR (SELF-ELEVATION)
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh.exe" } else { "powershell.exe" }
    if ([string]::IsNullOrWhiteSpace($PSCommandPath) -or -not (Test-Path -LiteralPath $PSCommandPath)) {
        Start-Process $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"Invoke-RestMethod -Uri 'https://is.gd/duckutil' | Invoke-Expression`"" -Verb RunAs
    } else {
        Start-Process $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    }
    exit
}

# 2. NẠP THƯ VIỆN WPF & WINFORMS
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
      "Google.Chrome"
    ],
    "Desc": "Trình duyệt phổ biến nhất thế giới"
  },
  {
    "Name": "Mozilla Firefox",
    "ID": "Mozilla.Firefox",
    "Category": "Trình Duyệt Web",
    "Domain": "mozilla.org",
    "Aliases": [
      "Mozilla Firefox",
      "Firefox"
    ],
    "Desc": "Mã nguồn mở, tôn trọng riêng tư"
  },
  {
    "Name": "Brave Browser",
    "ID": "Brave.Brave",
    "Category": "Trình Duyệt Web",
    "Domain": "brave.com",
    "Aliases": [
      "Brave",
      "BraveSoftware",
      "Brave.Brave"
    ],
    "Desc": "Chặn quảng cáo tích hợp sẵn"
  },
  {
    "Name": "LibreWolf",
    "ID": "LibreWolf.LibreWolf",
    "Category": "Trình Duyệt Web",
    "Domain": "librewolf.net",
    "Aliases": [
      "LibreWolf"
    ],
    "Desc": "Firefox không telemetry, siêu sạch"
  },
  {
    "Name": "Vivaldi",
    "ID": "VivaldiTechnologies.Vivaldi",
    "Category": "Trình Duyệt Web",
    "Domain": "vivaldi.com",
    "Aliases": [
      "Vivaldi"
    ],
    "Desc": "Tùy biến không giới hạn"
  },
  {
    "Name": "Tor Browser",
    "ID": "TorProject.TorBrowser",
    "Category": "Trình Duyệt Web",
    "Domain": "torproject.org",
    "Aliases": [
      "Tor Browser",
      "TorProject"
    ],
    "Desc": "Duyệt web ẩn danh qua Onion"
  },
  {
    "Name": "Opera GX",
    "ID": "Opera.OperaGX",
    "Category": "Trình Duyệt Web",
    "Domain": "opera.com",
    "Aliases": [
      "Opera GX",
      "Opera"
    ],
    "Desc": "Trình duyệt tối ưu tài nguyên"
  },
  {
    "Name": "Discord",
    "ID": "Discord.Discord",
    "Category": "Liên Lạc & Chat",
    "Domain": "discord.com",
    "Aliases": [
      "Discord"
    ],
    "Desc": "Voice/chat cộng đồng số 1"
  },
  {
    "Name": "Telegram",
    "ID": "Telegram.TelegramDesktop",
    "Category": "Liên Lạc & Chat",
    "Domain": "telegram.org",
    "Aliases": [
      "Telegram Desktop",
      "Telegram",
      "TelegramDesktop"
    ],
    "Desc": "Nhắn tin nhanh, cloud-sync mượt"
  },
  {
    "Name": "Signal",
    "ID": "OpenWhisperSystems.Signal",
    "Category": "Liên Lạc & Chat",
    "Domain": "signal.org",
    "Aliases": [
      "Signal"
    ],
    "Desc": "Mã hóa đầu-cuối an toàn tuyệt đối"
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
    "Desc": "Nhắn tin phổ biến nhất VN"
  },
  {
    "Name": "Zoom",
    "ID": "Zoom.Zoom",
    "Category": "Liên Lạc & Chat",
    "Domain": "zoom.us",
    "Aliases": [
      "Zoom",
      "Zoom Workplace"
    ],
    "Desc": "Họp trực tuyến trực tiếp"
  },
  {
    "Name": "Slack",
    "ID": "SlackTechnologies.Slack",
    "Category": "Liên Lạc & Chat",
    "Domain": "slack.com",
    "Aliases": [
      "Slack"
    ],
    "Desc": "Trao đổi công việc doanh nghiệp"
  },
  {
    "Name": "WhatsApp",
    "ID": "WhatsApp.WhatsApp",
    "Category": "Liên Lạc & Chat",
    "Domain": "whatsapp.com",
    "Aliases": [
      "WhatsApp"
    ],
    "Desc": "Gọi & nhắn tin toàn cầu"
  },
  {
    "Name": "Microsoft Teams",
    "ID": "Microsoft.Teams",
    "Category": "Liên Lạc & Chat",
    "Domain": "microsoft.com",
    "Aliases": [
      "Microsoft Teams",
      "MSTeams"
    ],
    "Desc": "Nền tảng làm việc Microsoft"
  },
  {
    "Name": "VS Code",
    "ID": "Microsoft.VisualStudioCode",
    "Category": "Phát Triển & Dev",
    "Domain": "code.visualstudio.com",
    "Aliases": [
      "Microsoft Visual Studio Code",
      "Visual Studio Code"
    ],
    "Desc": "Code editor chuẩn của lập trình viên"
  },
  {
    "Name": "Git",
    "ID": "Git.Git",
    "Category": "Phát Triển & Dev",
    "Domain": "git-scm.com",
    "Aliases": [
      "Git"
    ],
    "Desc": "Hệ thống quản lý phiên bản mã nguồn"
  },
  {
    "Name": "Windows Terminal",
    "ID": "Microsoft.WindowsTerminal",
    "Category": "Phát Triển & Dev",
    "Domain": "microsoft.com",
    "Aliases": [
      "Windows Terminal",
      "WindowsTerminal",
      "Bảng điều khiển Windows"
    ],
    "Desc": "Terminal hiện đại đa tab"
  },
  {
    "Name": "Python 3.12",
    "ID": "Python.Python.3.12",
    "Category": "Phát Triển & Dev",
    "Domain": "python.org",
    "Aliases": [
      "Python 3.12",
      "Python 3.13",
      "Python"
    ],
    "Desc": "Ngôn ngữ AI & tự động hóa"
  },
  {
    "Name": "Node.js LTS",
    "ID": "OpenJS.NodeJS.LTS",
    "Category": "Phát Triển & Dev",
    "Domain": "nodejs.org",
    "Aliases": [
      "Node.js",
      "OpenJS.NodeJS"
    ],
    "Desc": "Môi trường chạy JS server-side"
  },
  {
    "Name": "Docker Desktop",
    "ID": "Docker.DockerDesktop",
    "Category": "Phát Triển & Dev",
    "Domain": "docker.com",
    "Aliases": [
      "Docker Desktop"
    ],
    "Desc": "Nền tảng container ảo hóa"
  },
  {
    "Name": "Notepad++",
    "ID": "Notepad++.Notepad++",
    "Category": "Phát Triển & Dev",
    "Domain": "notepad-plus-plus.org",
    "Aliases": [
      "Notepad++"
    ],
    "Desc": "Trình soạn thảo text siêu nhẹ"
  },
  {
    "Name": "Postman",
    "ID": "Postman.Postman",
    "Category": "Phát Triển & Dev",
    "Domain": "postman.com",
    "Aliases": [
      "Postman"
    ],
    "Desc": "Test & phát triển API"
  },
  {
    "Name": "DBeaver CE",
    "ID": "dbeaver.dbeaver",
    "Category": "Phát Triển & Dev",
    "Domain": "dbeaver.io",
    "Aliases": [
      "DBeaver"
    ],
    "Desc": "Quản trị database đa năng"
  },
  {
    "Name": "Go Lang",
    "ID": "GoLang.Go",
    "Category": "Phát Triển & Dev",
    "Domain": "golang.org",
    "Aliases": [
      "Go Programming Language",
      "GoLang"
    ],
    "Desc": "Ngôn ngữ backend hiệu năng cao"
  },
  {
    "Name": "Rust (rustup)",
    "ID": "Rustlang.Rustup",
    "Category": "Phát Triển & Dev",
    "Domain": "rust-lang.org",
    "Aliases": [
      "Rustup",
      "Rust"
    ],
    "Desc": "Bộ công cụ ngôn ngữ Rust"
  },
  {
    "Name": "7-Zip",
    "ID": "7zip.7zip",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "7-zip.org",
    "Aliases": [
      "7-Zip",
      "7zip"
    ],
    "Desc": "Giải nén mọi định dạng tệp"
  },
  {
    "Name": "WinRAR",
    "ID": "RARLab.WinRAR",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "rarlab.com",
    "Aliases": [
      "WinRAR"
    ],
    "Desc": "Nén/giải nén chuẩn RAR"
  },
  {
    "Name": "Everything",
    "ID": "voidtools.Everything",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "voidtools.com",
    "Aliases": [
      "Everything"
    ],
    "Desc": "Tìm kiếm file tức thì 1 giây"
  },
  {
    "Name": "PowerToys",
    "ID": "Microsoft.PowerToys",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "github.com",
    "Aliases": [
      "PowerToys"
    ],
    "Desc": "Bộ tiện ích chính chủ Microsoft"
  },
  {
    "Name": "Flow Launcher",
    "ID": "Flow-Launcher.Flow-Launcher",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "flowlauncher.com",
    "Aliases": [
      "Flow Launcher",
      "Flow-Launcher"
    ],
    "Desc": "Thanh tìm kiếm & chạy app Alt+Space"
  },
  {
    "Name": "Revo Uninstaller",
    "ID": "VSRevoGroup.RevoUninstaller",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "revouninstaller.com",
    "Aliases": [
      "Revo Uninstaller"
    ],
    "Desc": "Gỡ phần mềm sạch tận gốc"
  },
  {
    "Name": "TreeSize Free",
    "ID": "JAMSoftware.TreeSize.Free",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "jam-software.com",
    "Aliases": [
      "TreeSize"
    ],
    "Desc": "Phân tích dung lượng ổ đĩa"
  },
  {
    "Name": "ShareX",
    "ID": "ShareX.ShareX",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "getsharex.com",
    "Aliases": [
      "ShareX"
    ],
    "Desc": "Chụp/quay màn hình & OCR đỉnh cao"
  },
  {
    "Name": "BleachBit",
    "ID": "BleachBit.BleachBit",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "bleachbit.org",
    "Aliases": [
      "BleachBit"
    ],
    "Desc": "Dọn rác & privacy thay CCleaner"
  },
  {
    "Name": "FanControl",
    "ID": "Rem0o.FanControl",
    "Category": "Tiện Ích Hệ Thống",
    "Domain": "github.com",
    "Aliases": [
      "FanControl"
    ],
    "Desc": "Tùy chỉnh quạt tản nhiệt êm ái"
  },
  {
    "Name": "VLC Media Player",
    "ID": "VideoLAN.VLC",
    "Category": "Đa Phương Tiện",
    "Domain": "videolan.org",
    "Aliases": [
      "VLC media player",
      "VLC"
    ],
    "Desc": "Xem mọi định dạng video/nhạc"
  },
  {
    "Name": "OBS Studio",
    "ID": "OBSProject.OBSStudio",
    "Category": "Đa Phương Tiện",
    "Domain": "obsproject.com",
    "Aliases": [
      "OBS Studio"
    ],
    "Desc": "Ghi hình & livestream chuyên nghiệp"
  },
  {
    "Name": "Spotify",
    "ID": "Spotify.Spotify",
    "Category": "Đa Phương Tiện",
    "Domain": "spotify.com",
    "Aliases": [
      "Spotify"
    ],
    "Desc": "Nghe nhạc bản quyền chất lượng cao"
  },
  {
    "Name": "GIMP",
    "ID": "GIMP.GIMP",
    "Category": "Đa Phương Tiện",
    "Domain": "gimp.org",
    "Aliases": [
      "GIMP"
    ],
    "Desc": "Chỉnh sửa ảnh chuyên nghiệp thay PTS"
  },
  {
    "Name": "Audacity",
    "ID": "Audacity.Audacity",
    "Category": "Đa Phương Tiện",
    "Domain": "audacityteam.org",
    "Aliases": [
      "Audacity"
    ],
    "Desc": "Thu âm & biên tập audio"
  },
  {
    "Name": "HandBrake",
    "ID": "HandBrake.HandBrake",
    "Category": "Đa Phương Tiện",
    "Domain": "handbrake.fr",
    "Aliases": [
      "HandBrake"
    ],
    "Desc": "Nén & đổi đuôi video dung lượng nhẹ"
  },
  {
    "Name": "Krita",
    "ID": "KDE.Krita",
    "Category": "Đa Phương Tiện",
    "Domain": "krita.org",
    "Aliases": [
      "Krita"
    ],
    "Desc": "Vẽ đồ họa số & concept art"
  },
  {
    "Name": "K-Lite Codec Mega",
    "ID": "CodecGuide.K-LiteCodecPack.Mega",
    "Category": "Đa Phương Tiện",
    "Domain": "codecguide.com",
    "Aliases": [
      "K-Lite Codec Pack",
      "K-Lite"
    ],
    "Desc": "Gói giải mã video/audio đầy đủ"
  },
  {
    "Name": "LibreOffice",
    "ID": "TheDocumentFoundation.LibreOffice",
    "Category": "Văn Phòng & Tài Liệu",
    "Domain": "libreoffice.org",
    "Aliases": [
      "LibreOffice"
    ],
    "Desc": "Bộ Office mã nguồn mở miễn phí"
  },
  {
    "Name": "Obsidian",
    "ID": "Obsidian.Obsidian",
    "Category": "Văn Phòng & Tài Liệu",
    "Domain": "obsidian.md",
    "Aliases": [
      "Obsidian"
    ],
    "Desc": "Ghi chú Markdown & mạng lưới tư duy"
  },
  {
    "Name": "Notion",
    "ID": "Notion.Notion",
    "Category": "Văn Phòng & Tài Liệu",
    "Domain": "notion.so",
    "Aliases": [
      "Notion"
    ],
    "Desc": "Không gian quản lý ghi chú chung"
  },
  {
    "Name": "SumatraPDF",
    "ID": "SumatraPDF.SumatraPDF",
    "Category": "Văn Phòng & Tài Liệu",
    "Domain": "sumatrapdfreader.org",
    "Aliases": [
      "SumatraPDF"
    ],
    "Desc": "Đọc PDF siêu nhẹ bật tức thì"
  },
  {
    "Name": "Foxit PDF Reader",
    "ID": "Foxit.FoxitReader",
    "Category": "Văn Phòng & Tài Liệu",
    "Domain": "foxit.com",
    "Aliases": [
      "Foxit PDF Reader",
      "Foxit Reader"
    ],
    "Desc": "Xem & ký tài liệu PDF chuyên nghiệp"
  },
  {
    "Name": "Steam",
    "ID": "Valve.Steam",
    "Category": "Nền Tảng Trò Chơi",
    "Domain": "steampowered.com",
    "Aliases": [
      "Steam"
    ],
    "Desc": "Kho game PC số 1 thế giới"
  },
  {
    "Name": "Epic Games Launcher",
    "ID": "EpicGames.EpicGamesLauncher",
    "Category": "Nền Tảng Trò Chơi",
    "Domain": "epicgames.com",
    "Aliases": [
      "Epic Games Launcher"
    ],
    "Desc": "Cửa hàng game & phát game miễn phí"
  },
  {
    "Name": "GOG Galaxy",
    "ID": "GOG.Galaxy",
    "Category": "Nền Tảng Trò Chơi",
    "Domain": "gog.com",
    "Aliases": [
      "GOG GALAXY",
      "GOG Galaxy"
    ],
    "Desc": "Quản lý thư viện game không DRM"
  },
  {
    "Name": "MSI Afterburner",
    "ID": "Guru3D.Afterburner",
    "Category": "Nền Tảng Trò Chơi",
    "Domain": "msi.com",
    "Aliases": [
      "MSI Afterburner"
    ],
    "Desc": "Đo nhiệt độ, FPS & ép xung"
  },
  {
    "Name": "Playnite",
    "ID": "Playnite.Playnite",
    "Category": "Nền Tảng Trò Chơi",
    "Domain": "playnite.link",
    "Aliases": [
      "Playnite"
    ],
    "Desc": "Gom mọi thư viện game về một nơi"
  },
  {
    "Name": "qBittorrent",
    "ID": "qBittorrent.qBittorrent",
    "Category": "Lưu Trữ & Truyền Tệp",
    "Domain": "qbittorrent.org",
    "Aliases": [
      "qBittorrent"
    ],
    "Desc": "Tải torrent sạch, không quảng cáo"
  },
  {
    "Name": "LocalSend",
    "ID": "LocalSend.LocalSend",
    "Category": "Lưu Trữ & Truyền Tệp",
    "Domain": "localsend.org",
    "Aliases": [
      "LocalSend"
    ],
    "Desc": "Bắn file qua Wi-Fi như AirDrop"
  },
  {
    "Name": "WinSCP",
    "ID": "WinSCP.WinSCP",
    "Category": "Lưu Trữ & Truyền Tệp",
    "Domain": "winscp.net",
    "Aliases": [
      "WinSCP",
      "winscp3_is1"
    ],
    "Desc": "Truyền tệp qua SFTP/FTP bảo mật"
  },
  {
    "Name": "FileZilla",
    "ID": "TimKosse.FileZilla.Client",
    "Category": "Lưu Trữ & Truyền Tệp",
    "Domain": "filezilla-project.org",
    "Aliases": [
      "FileZilla Client",
      "FileZilla"
    ],
    "Desc": "Client truyền tệp FTP phổ biến"
  },
  {
    "Name": "Rclone",
    "ID": "Rclone.Rclone",
    "Category": "Lưu Trữ & Truyền Tệp",
    "Domain": "rclone.org",
    "Aliases": [
      "Rclone"
    ],
    "Desc": "Mount & đồng bộ 70+ dịch vụ đám mây"
  },
  {
    "Name": "Bitwarden",
    "ID": "Bitwarden.Bitwarden",
    "Category": "Bảo Mật & Mạng",
    "Domain": "bitwarden.com",
    "Aliases": [
      "Bitwarden"
    ],
    "Desc": "Két mật khẩu mã hóa an toàn"
  },
  {
    "Name": "KeePassXC",
    "ID": "KeePassXCTeam.KeePassXC",
    "Category": "Bảo Mật & Mạng",
    "Domain": "keepassxc.org",
    "Aliases": [
      "KeePassXC"
    ],
    "Desc": "Quản lý mật khẩu offline độc lập"
  },
  {
    "Name": "Cryptomator",
    "ID": "Cryptomator.Cryptomator",
    "Category": "Bảo Mật & Mạng",
    "Domain": "cryptomator.org",
    "Aliases": [
      "Cryptomator"
    ],
    "Desc": "Mã hóa dữ liệu trước khi lên mây"
  },
  {
    "Name": "ProtonVPN",
    "ID": "ProtonTechnologies.ProtonVPN",
    "Category": "Bảo Mật & Mạng",
    "Domain": "protonvpn.com",
    "Aliases": [
      "Proton VPN",
      "ProtonVPN",
      "Proton.ProtonVPN"
    ],
    "Desc": "VPN bảo mật cao từ Thụy Sĩ"
  },
  {
    "Name": "RustDesk",
    "ID": "RustDesk.RustDesk",
    "Category": "Bảo Mật & Mạng",
    "Domain": "rustdesk.com",
    "Aliases": [
      "RustDesk"
    ],
    "Desc": "Điều khiển máy tính từ xa tự host"
  },
  {
    "Name": "Wireshark",
    "ID": "WiresharkFoundation.Wireshark",
    "Category": "Bảo Mật & Mạng",
    "Domain": "wireshark.org",
    "Aliases": [
      "Wireshark"
    ],
    "Desc": "Phân tích gói tin mạng chuyên sâu"
  },
  {
    "Name": "VC++ Redist 2015-2022",
    "ID": "Microsoft.VCRedist.2015+.x64",
    "Category": "Thư Viện Cốt Lõi",
    "Domain": "microsoft.com",
    "Aliases": [
      "Visual C++",
      "Microsoft Visual C++"
    ],
    "Desc": "Cần thiết cho hầu hết game & app"
  },
  {
    "Name": ".NET Desktop Runtime 8",
    "ID": "Microsoft.DotNet.DesktopRuntime.8",
    "Category": "Thư Viện Cốt Lõi",
    "Domain": "microsoft.com",
    "Aliases": [
      "Microsoft Windows Desktop Runtime - 8",
      "DesktopRuntime.8"
    ],
    "Desc": "Nền tảng chạy ứng dụng .NET 8 mới"
  },
  {
    "Name": "DirectX End-User",
    "ID": "Microsoft.DirectX",
    "Category": "Thư Viện Cốt Lõi",
    "Domain": "microsoft.com",
    "Aliases": [
      "DirectX"
    ],
    "Desc": "Thư viện đồ họa DirectX chuẩn"
  },
  {
    "Name": "Java OpenJDK 21",
    "ID": "EclipseAdoptium.Temurin.21.JDK",
    "Category": "Thư Viện Cốt Lõi",
    "Domain": "adoptium.net",
    "Aliases": [
      "Eclipse Temurin",
      "Temurin",
      "Amazon Corretto"
    ],
    "Desc": "Môi trường chạy Java LTS tiêu chuẩn"
  }
]
'@
$AppCatalog = ConvertFrom-Json $appsRawJson -AsHashtable

# 4. GIAO DIỆN XAML WPF
[xml]$XAML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="DuckUtil - Cyber Obsidian Suite"
    Width="1280" Height="890"
    WindowStartupLocation="CenterScreen"
    Background="#090B10"
    Foreground="#F8FAFC"
    FontFamily="Segoe UI Variable Display, Segoe UI, sans-serif">

    <Window.Resources>
        <!-- ═══ PHONG CÁCH THANH CUỘN (SCROLLBAR) HIỆN ĐẠI SIÊU GỌN - OBSIDIAN CYBER ═══ -->
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

        <!-- Nút bấm phong cách Action -->
        <Style x:Key="ActionButton" TargetType="Button">
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="Margin" Value="4,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="btnBorder" Background="{TemplateBinding Background}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.65"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Nút phụ -->
        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="#151A26"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="Margin" Value="4,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderBrush" Value="#222C3E"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="btnBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="#1E2738"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Nút điều hướng Tab chính -->
        <Style x:Key="NavTabButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#64748B"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="20,12"/>
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
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="#E2E8F0"/>
                                <Setter TargetName="navBorder" Property="Background" Value="#11141E"/>
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
            <RowDefinition Height="145"/>  <!-- Cyber Terminal Log -->
        </Grid.RowDefinitions>

        <!-- ═══ 1. TOP APP HEADER ═══ -->
        <Border Grid.Row="0" Background="#0C0E14" Padding="20,12" BorderBrush="#1A1F2C" BorderThickness="0,0,0,1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="360"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Background="#1E293B" CornerRadius="8" Width="36" Height="36" Margin="0,0,12,0">
                        <TextBlock Text="🦆" FontSize="20" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <StackPanel VerticalAlignment="Center">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="DUCK UTIL" FontSize="19" FontWeight="Black" Foreground="#F8FAFC"/>
                            <Border Background="#0EA5E9" CornerRadius="4" Margin="10,0,0,0" Padding="6,2" VerticalAlignment="Center">
                                <TextBlock Text="PRO SUITE" FontSize="10" FontWeight="Bold" Foreground="#FFFFFF"/>
                            </Border>
                        </StackPanel>
                        <TextBlock Text="Windows Package Manager &amp; System Maintenance Suite" FontSize="11" Foreground="#64748B"/>
                    </StackPanel>
                </StackPanel>

                <!-- Modern Search Box -->
                <Border Grid.Column="2" Background="#121620" CornerRadius="8" BorderBrush="#263147" BorderThickness="1" Padding="10,6">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="🔍" Foreground="#64748B" VerticalAlignment="Center" Margin="0,0,8,0" FontSize="12"/>
                        <TextBox Grid.Column="1" Name="txtSearch" Background="Transparent" Foreground="#F8FAFC"
                                 BorderThickness="0" FontSize="12.5" VerticalAlignment="Center"
                                 CaretBrush="#38BDF8"
                                 ToolTip="Gõ để lọc ứng dụng ngay lập tức..."/>
                    </Grid>
                </Border>
            </Grid>
        </Border>

        <!-- ═══ 2. MAIN NAV TAB BAR ═══ -->
        <Border Grid.Row="1" Background="#0E1118" Padding="16,0" BorderBrush="#1A1F2C" BorderThickness="0,0,0,1">
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
                    <Border Grid.Row="0" Background="#0F121A" Padding="18,8" BorderBrush="#1A1F2C" BorderThickness="0,0,0,1">
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

                            <!-- Hàng 2: Chú thích màu sắc chuẩn -->
                            <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="4,8,0,0">
                                <TextBlock Text="Trạng thái màu tên App:" FontSize="11.5" Foreground="#64748B" Margin="0,0,12,0" FontWeight="SemiBold"/>
                                <Border Background="#1E293B" CornerRadius="4" Padding="8,2" Margin="0,0,8,0">
                                    <TextBlock Text="⚪ Trắng: Chưa cài đặt" FontSize="11" Foreground="#FFFFFF" FontWeight="SemiBold"/>
                                </Border>
                                <Border Background="#0C2417" CornerRadius="4" Padding="8,2" Margin="0,0,8,0">
                                    <TextBlock Text="🟢 Xanh lá: Đã cài (Bản mới nhất)" FontSize="11" Foreground="#34D399" FontWeight="SemiBold"/>
                                </Border>
                                <Border Background="#271013" CornerRadius="4" Padding="8,2" Margin="0,0,8,0">
                                    <TextBlock Text="🔴 Đỏ: Đã cài (Bản cũ - Có cập nhật)" FontSize="11" Foreground="#F87171" FontWeight="SemiBold"/>
                                </Border>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Lưới Card 4 CỘT RỘNG RÃI (ItemWidth = 296) -->
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="12,10">
                        <WrapPanel Name="CardsContainer" ItemWidth="296" Orientation="Horizontal"/>
                    </ScrollViewer>
                </Grid>
            </TabItem>

            <!-- ── TAB 2: GỠ LỖI & SỬA HỆ THỐNG ── -->
            <TabItem>
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="20,16">
                    <WrapPanel ItemWidth="388" Orientation="Horizontal">
                        <!-- Card 1: File Hệ Thống -->
                        <Border Background="#10141D" BorderBrush="#1E2638" BorderThickness="1" CornerRadius="10" Margin="6" Padding="18">
                            <StackPanel>
                                <TextBlock Text="🛠️ SỬA CHỮA FILE HỆ THỐNG" FontWeight="Bold" FontSize="13.5" Foreground="#38BDF8" Margin="0,0,0,8"/>
                                <TextBlock Text="Quét và tự động sửa các file Windows bị hỏng hoặc mất." FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnSfcScan" Content="SFC Scan (sfc /scannow)" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                                <Button Name="btnDismRestore" Content="DISM RestoreHealth (Phục hồi linh kiện)" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                                <Button Name="btnDismCleanup" Content="Dọn Kho Linh Kiện (Component Cleanup)" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 2: Windows Update -->
                        <Border Background="#10141D" BorderBrush="#1E2638" BorderThickness="1" CornerRadius="10" Margin="6" Padding="18">
                            <StackPanel>
                                <TextBlock Text="🔄 GỠ LỖI WINDOWS UPDATE" FontWeight="Bold" FontSize="13.5" Foreground="#F59E0B" Margin="0,0,0,8"/>
                                <TextBlock Text="Khắc phục lỗi kẹt tải 0%, mã lỗi 0x80070002, 0x8024... khi cập nhật Windows." FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnFixWindowsUpdate" Content="⚡ Reset Toàn Bộ Cache Update (Triệt để)" Style="{StaticResource ActionButton}" Background="#EA580C" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                                <Button Name="btnRestartUpdateServices" Content="Khởi Động Lại Dịch Vụ BITS &amp; Wuauserv" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                                <Button Name="btnTriggerScanUpdate" Content="Kích Hoạt Tìm Bản Cập Nhật Mới (USOClient)" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 3: Mạng & DNS -->
                        <Border Background="#10141D" BorderBrush="#1E2638" BorderThickness="1" CornerRadius="10" Margin="6" Padding="18">
                            <StackPanel>
                                <TextBlock Text="🌐 SỬA LỖI MẠNG &amp; KẾT NỐI" FontWeight="Bold" FontSize="13.5" Foreground="#10B981" Margin="0,0,0,8"/>
                                <TextBlock Text="Khắc phục sự cố không vào được web, mạng chập chờn, lỗi DNS." FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnFlushDnsWinsock" Content="Flush DNS &amp; Reset Winsock (Làm mới mạng)" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                                <Button Name="btnResetTcpIp" Content="Reset Toàn Bộ Ngăn Xếp TCP/IP Stack" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 4: Dọn Rác & Khôi Phục UI -->
                        <Border Background="#10141D" BorderBrush="#1E2638" BorderThickness="1" CornerRadius="10" Margin="6" Padding="18">
                            <StackPanel>
                                <TextBlock Text="🧹 BẢO TRÌ &amp; DỌN DẸP HỆ THỐNG" FontWeight="Bold" FontSize="13.5" Foreground="#A78BFA" Margin="0,0,0,8"/>
                                <TextBlock Text="Dọn sạch rác ổ C và khởi động lại Taskbar khi bị đơ treo." FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnClearTemp" Content="Dọn Sạch Thư Mục Temp &amp; Cache Rác" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                                <Button Name="btnRestartExplorer" Content="Khởi Động Lại Windows Explorer (Fix đơ taskbar)" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                            </StackPanel>
                        </Border>
                    </WrapPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ── TAB 3: QUẢN LÝ & GỠ LỖI DRIVER ── -->
            <TabItem>
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="20,16">
                    <WrapPanel ItemWidth="388" Orientation="Horizontal">
                        <!-- Card 1: Chẩn Đoán Driver Lỗi -->
                        <Border Background="#10141D" BorderBrush="#1E2638" BorderThickness="1" CornerRadius="10" Margin="6" Padding="18">
                            <StackPanel>
                                <TextBlock Text="⚠️ CHẨN ĐOÁN PHẦN CỨNG &amp; DRIVER" FontWeight="Bold" FontSize="13.5" Foreground="#F43F5E" Margin="0,0,0,8"/>
                                <TextBlock Text="Rà soát các thiết bị bị chấm than vàng, thiếu driver hoặc driver bị crash." FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnScanFaultyDrivers" Content="🔍 Quét Thiết Bị &amp; Driver Bị Lỗi" Style="{StaticResource ActionButton}" Background="#E11D48" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                                <Button Name="btnPnpRescan" Content="Buộc Windows Quét Lại Phần Cứng (PnP Scan)" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                                <Button Name="btnOpenDeviceManager" Content="Mở Trình Quản Lý Device Manager" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 2: Gỡ Lỗi Update Driver -->
                        <Border Background="#10141D" BorderBrush="#1E2638" BorderThickness="1" CornerRadius="10" Margin="6" Padding="18">
                            <StackPanel>
                                <TextBlock Text="🛠️ GỠ LỖI CẬP NHẬT DRIVER" FontWeight="Bold" FontSize="13.5" Foreground="#F59E0B" Margin="0,0,0,8"/>
                                <TextBlock Text="Sửa lỗi Windows Update bị kẹt khi đang cài driver màn hình, âm thanh, touchpad." FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnFixDriverUpdate" Content="⚡ Sửa Lỗi Kẹt Cập Nhật Driver (Xóa Queue)" Style="{StaticResource ActionButton}" Background="#EA580C" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                                <Button Name="btnScanWindowsUpdateDrivers" Content="Kích Hoạt Quét Driver Mới Từ Microsoft" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                                <Button Name="btnCleanDriverStore" Content="Dọn Dẹp Driver Cũ Trong DriverStore" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 3: Sao Lưu Driver -->
                        <Border Background="#10141D" BorderBrush="#1E2638" BorderThickness="1" CornerRadius="10" Margin="6" Padding="18">
                            <StackPanel>
                                <TextBlock Text="💾 SAO LƯU &amp; BẢO VỆ DRIVER" FontWeight="Bold" FontSize="13.5" Foreground="#10B981" Margin="0,0,0,8"/>
                                <TextBlock Text="Trích xuất toàn bộ driver bên thứ ba để phòng khi cài lại Windows không sợ mất mạng/wifi." FontSize="11.5" Foreground="#64748B" Margin="0,0,0,14" TextWrapping="Wrap"/>
                                <Button Name="btnBackupDrivers" Content="Sao Lưu Toàn Bộ Driver (Ra C:\Backup_Drivers)" Style="{StaticResource ActionButton}" Background="#059669" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                                <Button Name="btnOpenBackupFolder" Content="Mở Thư Mục Chứa Driver Đã Sao Lưu" Style="{StaticResource SecondaryButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="14,10"/>
                            </StackPanel>
                        </Border>
                    </WrapPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- ═══ 4. STATUS & PROGRESS BAR ═══ -->
        <Border Grid.Row="3" Background="#0C0E14" Padding="18,6" BorderBrush="#1A1F2C" BorderThickness="0,1,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <TextBlock Grid.Column="0" Grid.Row="0" Name="txtStatus" Text="Sẵn sàng"
                           Foreground="#38BDF8" FontSize="12" FontWeight="SemiBold"/>
                <TextBlock Grid.Column="1" Grid.Row="0" Name="txtSelectionCount" Text="0 app được chọn"
                           Foreground="#64748B" FontSize="11"/>

                <ProgressBar Grid.Column="0" Grid.ColumnSpan="2" Grid.Row="1"
                             Name="progressBar" Height="3" Margin="0,6,0,2"
                             Background="#1A1F2C" Foreground="#0EA5E9" BorderThickness="0" Value="0"/>
            </Grid>
        </Border>

        <!-- ═══ 5. CYBER TERMINAL LOG ═══ -->
        <Border Grid.Row="4" Background="#05060A" Padding="14,8">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0" Margin="0,0,0,4">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <Border Background="#EF4444" Width="9" Height="9" CornerRadius="5" Margin="0,0,5,0"/>
                        <Border Background="#F59E0B" Width="9" Height="9" CornerRadius="5" Margin="0,0,5,0"/>
                        <Border Background="#10B981" Width="9" Height="9" CornerRadius="5" Margin="0,0,10,0"/>
                        <TextBlock Text="TERMINAL LOG" FontSize="10" FontWeight="Bold" Foreground="#475569" VerticalAlignment="Center"/>
                    </StackPanel>
                    <Button Name="btnClearLog" Content="Xóa Log" HorizontalAlignment="Right"
                            Background="Transparent" Foreground="#64748B" BorderThickness="0" Cursor="Hand" FontSize="11"/>
                </Grid>
                <TextBox Grid.Row="1" Name="txtLog" Background="Transparent" Foreground="#34D399"
                         FontFamily="Cascadia Mono, Consolas, Courier New" FontSize="11"
                         IsReadOnly="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"
                         BorderThickness="0"
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
    $logBox = if ($txtLog) { $txtLog } elseif ($txtTerminal) { $txtTerminal } else { $null }
    if ($logBox) {
        $timestamp = (Get-Date).ToString("HH:mm:ss")
        $logBox.AppendText("[$timestamp] $text`r`n")
        $logBox.ScrollToEnd()
    }
}

function Run-CliStream {
    param([string]$FileName, [string]$Args)
    try {
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
    } catch {
        Log-Text "[!] Lỗi khi thực thi lệnh: $($_.Exception.Message)"
        return -1
    }
}

# ── FUNCTION: QUÉT & PHÂN LOẠI MÀU PHIÊN BẢN (TRẮNG / XANH / ĐỎ) ──
function Scan-And-ColorizeApps {
    Log-Text "[🔍] Đang chạy quét nhận diện ứng dụng & phân tích phiên bản (winget list)..."
    $txtStatus.Text = "Đang kiểm tra phiên bản app..."
    $progressBar.IsIndeterminate = $true
    [System.Windows.Forms.Application]::DoEvents()

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "winget"
    $pinfo.Arguments = "list"
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($pinfo)
    $rawList = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()

    # Phân tích danh sách đã cài đặt từ winget
    $lines = $rawList -split "`r?`n"
    $start = $false
    $installedItems = @()

    foreach ($line in $lines) {
        if ($line -like "---*") { $start = $true; continue }
        if ($start -and -not [string]::IsNullOrWhiteSpace($line)) {
            $cols = [System.Text.RegularExpressions.Regex]::Split($line.Trim(), "\s{2,}")
            if ($cols.Count -ge 2) {
                $installedItems += [PSCustomObject]@{
                    Name      = $cols[0].Trim()
                    ID        = $cols[1].Trim()
                    Version   = if ($cols.Count -ge 3) { $cols[2].Trim() } else { "" }
                    Available = if ($cols.Count -ge 4) { $cols[3].Trim() } else { "" }
                    HasUpdate = ($cols.Count -ge 5 -or ($cols.Count -eq 4 -and $cols[3].Trim() -ne "winget" -and $cols[3].Trim() -ne "msstore" -and $cols[3].Trim() -ne ""))
                }
            }
        }
    }

    # Hàm khớp thông minh (Exact ID -> Aliases -> Clean Name)
    function Find-InstalledAppInfo {
        param($targetApp, $items)
        
        # 1. Exact ID
        $match = $items | Where-Object { $_.ID -eq $targetApp.ID } | Select-Object -First 1
        if ($match) { return $match }

        # 2. Check Aliases (Brave, Zalo, Telegram, WinSCP, ProtonVPN...)
        if ($targetApp.ContainsKey("Aliases") -and $targetApp.Aliases) {
            foreach ($alias in $targetApp.Aliases) {
                $al = $alias.ToLower()
                $match = $items | Where-Object {
                    $_.ID.ToLower() -eq $al -or
                    $_.Name.ToLower() -eq $al -or
                    $_.ID.ToLower().Contains($al) -or
                    $_.Name.ToLower().StartsWith($al)
                } | Select-Object -First 1
                if ($match) { return $match }
            }
        }

        # 3. Clean Name match
        $clean = ($targetApp.Name -replace '\(.*?\)', '').Trim().ToLower()
        foreach ($term in @(" browser", " desktop", " lts", " client", " free", " ce", " community", " end-user")) {
            $clean = $clean.Replace($term, "")
        }
        if ($clean.Length -ge 3) {
            $match = $items | Where-Object {
                $n = ($_.Name -replace '\(.*?\)', '').Trim().ToLower()
                $n -eq $clean -or $n.StartsWith("$clean ") -or $n.StartsWith($clean)
            } | Select-Object -First 1
            if ($match) { return $match }
        }

        return $null
    }

    $progressBar.IsIndeterminate = $false
    $countInstalled = 0
    $countLatest = 0
    $countOutdated = 0

    foreach ($row in $allItemBorders) {
        $app = $row.Tag.App
        $grid = $row.Child
        $tb = $grid.Children[2]

        $info = Find-InstalledAppInfo $app $installedItems

        if ($info) {
            $countInstalled++

            if ($info.HasUpdate -eq $true) {
                # ── 🔴 BẢN CŨ: Tên ĐỎ rực rỡ + Nền đỏ sẫm ──
                $countOutdated++
                $row.Tag.Status = "OUTDATED"
                $row.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2A1215")
                $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
                $updateBadge = if ($info.Available) { " (Có bản: $($info.Available))" } else { " (Có bản mới)" }
                $tb.Text = "$($app.Name)  ⚠️$updateBadge"
                $tb.ToolTip = "$($app.Name)`nĐang cài: $($info.Version)`nCó bản mới: $($info.Available)`nID phát hiện: $($info.ID)"
            } else {
                # ── 🟢 BẢN MỚI NHẤT: Tên XANH LÁ + Nền xanh sẫm ──
                $countLatest++
                $row.Tag.Status = "LATEST"
                $row.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0D2818")
                $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
                $tb.Text = "$($app.Name)  ✓ (Mới nhất)"
                $tb.ToolTip = "$($app.Name)`nPhiên bản: $($info.Version) (Mới nhất)`nID phát hiện: $($info.ID)"
            }
        } else {
            # ── ⚪ CHƯA CÀI ĐẶT: Tên TRẮNG + Nền trong suốt ──
            $row.Tag.Status = "NONE"
            $row.Background = [System.Windows.Media.Brushes]::Transparent
            $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
            $tb.Text = $app.Name
            $tb.ToolTip = "$($app.Name)`nTrạng thái: Chưa cài đặt`nID: $($app.ID)`n$($app.Desc)"
        }
    }

    $summary = "Đã quét xong: $countInstalled app đã cài ($countLatest bản mới nhất [🟢 XANH], $countOutdated bản cũ [🔴 ĐỎ])"
    Log-Text "[✓] $summary"
    $txtStatus.Text = "$countInstalled app đã cài ($countLatest mới / $countOutdated cũ)"
}

# ── FUNCTION: CÁC TIỆN ÍCH QUẢN LÝ & GỠ LỖI DRIVER ──

function Find-FaultyPnpDevices {
    <#
    .SYNOPSIS
        Quét và liệt kê tất cả các thiết bị phần cứng bị lỗi, thiếu driver hoặc chấm than vàng.
    #>
    return @(Get-PnpDevice | Where-Object { $_.Present -eq $true -and $_.Status -ne 'OK' })
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

    if (-not (Test-Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    try {
        Export-WindowsDriver -Online -Destination $Destination -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Run-CliStream "pnputil.exe" "/export-driver * `"$Destination`""
        return $true
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
    Rename-Item -Path "C:\Windows\SoftwareDistribution" -NewName "SoftwareDistribution.bak_$(Get-Random)" -Force -ErrorAction SilentlyContinue
    Rename-Item -Path "C:\Windows\System32\catroot2" -NewName "catroot2.bak_$(Get-Random)" -Force -ErrorAction SilentlyContinue

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
        if (Test-Path $p) {
            Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Clear-SystemEventLogs {
    <#
    .SYNOPSIS
        Xóa sạch nhật ký sự kiện Windows Event Logs.
    #>
    Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object {
        try { [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName) } catch {}
    }
}

# 6. ENTRYPOINT & CONTROLLER
# ── KHỞI TẠO CÁC CONTROL TỪ XAML ──
$reader = New-Object System.Xml.XmlNodeReader $XAML
$window = [Windows.Markup.XamlReader]::Load($reader)

# Các Control chính
$MainTabControl   = $window.FindName("MainTabControl")
$txtStatus        = $window.FindName("txtStatus")
$progressBar      = $window.FindName("progressBar")
$txtLog           = $window.FindName("txtLog")
$txtSearch        = $window.FindName("txtSearch")
$txtSelectionCount = $window.FindName("txtSelectionCount")
$cardsContainer   = $window.FindName("CardsContainer")

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
            $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
            $btn.BorderBrush = [System.Windows.Media.Brushes]::Transparent
        }
    }

    if ($activeBtn) {
        $activeBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
        $activeBtn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
    }
}

Register-Click "navBtnApps"    { Set-ActiveTab 0 $navBtnApps }
Register-Click "navBtnRepair"  { Set-ActiveTab 1 $navBtnRepair }
Register-Click "navBtnDrivers" { Set-ActiveTab 2 $navBtnDrivers }

# ── SINH CÁC CARD ỨNG DỤNG BỐ CỤC 4 CỘT RỘNG RÃI ──
$allCheckBoxes = @()
$allItemBorders = @()
$categories = $AppCatalog | Select-Object -ExpandProperty Category -Unique

function Update-SelectionCount {
    $selectedCount = @($allCheckBoxes | Where-Object { $_.IsChecked }).Count
    if ($txtSelectionCount) {
        $txtSelectionCount.Text = "$selectedCount app được chọn"
    }
}

foreach ($cat in $categories) {
    $cardBorder = New-Object System.Windows.Controls.Border
    $cardBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10131B")
    $cardBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1C2333")
    $cardBorder.BorderThickness = New-Object System.Windows.Thickness(1)
    $cardBorder.CornerRadius = New-Object System.Windows.CornerRadius(10)
    $cardBorder.Margin = New-Object System.Windows.Thickness(5)
    $cardBorder.Padding = New-Object System.Windows.Thickness(12, 10, 12, 12)

    $cardStack = New-Object System.Windows.Controls.StackPanel
    $appsInCat = @($AppCatalog | Where-Object { $_.Category -eq $cat })

    # Header Card
    $headerGrid = New-Object System.Windows.Controls.Grid
    $headerGrid.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)

    $headerText = New-Object System.Windows.Controls.TextBlock
    $headerText.Text = "$cat ($($appsInCat.Count))"
    $headerText.FontSize = 12.5
    $headerText.FontWeight = [System.Windows.FontWeights]::Bold
    $headerText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
    $headerGrid.Children.Add($headerText) | Out-Null

    $separator = New-Object System.Windows.Controls.Border
    $separator.Height = 1
    $separator.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E2638")
    $separator.Margin = New-Object System.Windows.Thickness(0, 2, 0, 6)

    $cardStack.Children.Add($headerGrid) | Out-Null
    $cardStack.Children.Add($separator) | Out-Null

    # Từng dòng App: Logo + CheckBox + Tên
    foreach ($app in $appsInCat) {
        $rowBorder = New-Object System.Windows.Controls.Border
        $rowBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $rowBorder.Padding = New-Object System.Windows.Thickness(6, 4, 6, 4)
        $rowBorder.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
        $rowBorder.Background = [System.Windows.Media.Brushes]::Transparent
        $rowBorder.Cursor = [System.Windows.Input.Cursors]::Hand
        $rowBorder.Tag = @{ App = $app; Status = "NONE" }

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
        $allCheckBoxes += $cb

        # 2. Logo Icon chính hãng
        $img = New-Object System.Windows.Controls.Image
        $img.Width = 16; $img.Height = 16
        $img.Margin = New-Object System.Windows.Thickness(7, 0, 8, 0)
        $img.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        try {
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit()
            $bmp.UriSource = New-Object System.Uri("https://www.google.com/s2/favicons?domain=$($app.Domain)&sz=32")
            $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.EndInit()
            $img.Source = $bmp
        } catch {}
        [System.Windows.Controls.Grid]::SetColumn($img, 1)
        $rowGrid.Children.Add($img) | Out-Null

        # 3. Tên ứng dụng
        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $app.Name
        $nameText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
        $nameText.FontSize = 12
        $nameText.FontWeight = [System.Windows.FontWeights]::SemiBold
        $nameText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $nameText.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $nameText.ToolTip = "$($app.Name)`nID: $($app.ID)`n$($app.Desc)"
        [System.Windows.Controls.Grid]::SetColumn($nameText, 2)
        $rowGrid.Children.Add($nameText) | Out-Null

        # Chạm chọn toàn dòng
        $rowBorder.Add_MouseDown({
            $cb.IsChecked = -not $cb.IsChecked
        })

        # Hover phát sáng & giữ màu trạng thái khi rời chuột
        $rowBorder.Add_MouseEnter({
            if ($rowBorder.Tag.Status -eq "NONE") {
                $rowBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1C2333")
            }
        })
        $rowBorder.Add_MouseLeave({
            if ($rowBorder.Tag.Status -eq "LATEST") {
                $rowBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0D2818")
            } elseif ($rowBorder.Tag.Status -eq "OUTDATED") {
                $rowBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2A1215")
            } else {
                $rowBorder.Background = [System.Windows.Media.Brushes]::Transparent
            }
        })

        $rowBorder.Child = $rowGrid
        $cardStack.Children.Add($rowBorder) | Out-Null
        $allItemBorders += $rowBorder
    }

    $cardBorder.Child = $cardStack
    if ($cardsContainer) {
        $cardsContainer.Children.Add($cardBorder) | Out-Null
    }
}

# ── LOGIC TÌM KIẾM & BỘ LỌC ──
if ($txtSearch) {
    $txtSearch.Add_TextChanged({
        $keyword = $txtSearch.Text.Trim().ToLower()
        foreach ($row in $allItemBorders) {
            $app = $row.Tag.App
            $matched = [string]::IsNullOrEmpty($keyword) -or ($app.Name.ToLower().Contains($keyword)) -or ($app.ID.ToLower().Contains($keyword))
            $row.Visibility = if ($matched) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        }
    })
}

# ── CÁC HÀNH ĐỘNG CÀI ĐẶT / GỠ / NÂNG CẤP APP ──
Register-Click "btnScanInstalled" { Scan-And-ColorizeApps }

Register-Click "btnInstall" {
    $selected = @($allCheckBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
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

        $code = Run-CliStream "winget" "install --id $($app.ID) --exact --silent --accept-package-agreements --accept-source-agreements"
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

Register-Click "btnUninstall" {
    $selected = @($allCheckBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
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

        $code = Run-CliStream "winget" "uninstall --id $($app.ID) --silent"
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

Register-Click "btnUpgradeAll" {
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

Register-Click "btnSelectAll" {
    foreach ($cb in $allCheckBoxes) { $cb.IsChecked = $true }
    Update-SelectionCount
}

Register-Click "btnDeselectAll" {
    foreach ($cb in $allCheckBoxes) { $cb.IsChecked = $false }
    Update-SelectionCount
}

Register-Click "btnClearLog" {
    if ($txtLog) { $txtLog.Clear() }
}

# ── LOGIC MODULE SỬA LỖI HỆ THỐNG (SYSTEM REPAIRS) ──
Register-Click "btnSfcScan" {
    Log-Text "[*] Đang bắt đầu quét kiểm tra tính toàn vẹn hệ thống (sfc /scannow)..."
    if ($txtStatus) { $txtStatus.Text = "Đang chạy SFC Scan..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    Invoke-SystemFileCheck
    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "Quét SFC hoàn tất" }
    Log-Text "[✓] Quá trình SFC đã kết thúc."
}

Register-Click "btnDismRestore" {
    Log-Text "[*] Đang khôi phục kho ảnh hệ thống Windows qua DISM RestoreHealth..."
    if ($txtStatus) { $txtStatus.Text = "Đang chạy DISM RestoreHealth..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    Invoke-DismRestoreHealth
    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "DISM hoàn tất" }
    Log-Text "[✓] DISM RestoreHealth hoàn thành xuất sắc."
}

Register-Click "btnDismCleanup" {
    Log-Text "[*] Đang dọn dẹp kho linh kiện hệ thống (DISM Component Cleanup)..."
    if ($txtStatus) { $txtStatus.Text = "Đang dọn kho linh kiện..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    Invoke-DriverStoreCleanup
    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "Dọn kho linh kiện hoàn tất" }
    Log-Text "[✓] Đã giải phóng dung lượng kho linh kiện."
}

Register-Click "btnFixWindowsUpdate" {
    Log-Text "[*] Bắt đầu khởi tạo và xóa sạch cache lỗi Windows Update..."
    if ($txtStatus) { $txtStatus.Text = "Đang sửa lỗi Windows Update..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    Reset-WindowsUpdateEngine
    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "Đã đặt lại Windows Update" }
}

Register-Click "btnRestartUpdateServices" {
    Log-Text "[*] Đang khởi động lại dịch vụ Windows Update & BITS..."
    Restart-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
    Restart-Service -Name "bits" -Force -ErrorAction SilentlyContinue
    Log-Text "[✓] Đã khởi động lại dịch vụ cập nhật."
}

Register-Click "btnTriggerScanUpdate" {
    Log-Text "[*] Đang gửi tín hiệu yêu cầu Windows tìm kiếm bản cập nhật mới..."
    Start-Process "usoclient" -ArgumentList "StartInteractiveScan" -NoNewWindow
    Log-Text "[✓] Đã kích hoạt USOClient quét cập nhật."
}

Register-Click "btnFlushDnsWinsock" {
    Log-Text "[*] Đang xóa sạch cache DNS và reset Winsock Catalog..."
    Clear-DnsResolverCache
    Run-CliStream "netsh.exe" "winsock reset"
    Log-Text "[✓] Đã làm mới mạng và DNS cache."
}

Register-Click "btnResetTcpIp" {
    Log-Text "[*] Đang đặt lại toàn bộ ngăn xếp giao thức mạng TCP/IP..."
    Reset-NetworkInterfaceStack
    Log-Text "[✓] Đã reset TCP/IP Stack. Khuyên bạn nên khởi động lại máy."
}

Register-Click "btnClearTemp" {
    Log-Text "[*] Đang dọn dẹp các tệp tạm thời trong User Temp và Windows Temp..."
    if ($txtStatus) { $txtStatus.Text = "Đang dọn tệp rác Temp..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    Clear-SystemTempFiles
    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "Dọn tệp tạm hoàn tất" }
    Log-Text "[✓] Dọn dẹp bộ nhớ tạm thành công!"
}

Register-Click "btnRestartExplorer" {
    Log-Text "[*] Đang khởi động lại tiến trình Windows Explorer (explorer.exe)..."
    Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Start-Process "explorer.exe"
    Log-Text "[✓] Đã nạp lại Windows Explorer thành công."
}

# ── LOGIC MODULE QUẢN LÝ & GỠ LỖI DRIVER ──
Register-Click "btnScanFaultyDrivers" {
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

Register-Click "btnPnpRescan" {
    Log-Text "[*] Đang gửi lệnh quét phần cứng Plug and Play (pnputil /scan-devices)..."
    Invoke-PnpDeviceRescan
    Log-Text "[✓] Windows đã hoàn tất quét và phát hiện lại các thiết bị phần cứng."
}

Register-Click "btnOpenDeviceManager" {
    Log-Text "[*] Đang mở Trình quản lý thiết bị (devmgmt.msc)..."
    Start-Process "devmgmt.msc"
}

Register-Click "btnFixDriverUpdate" {
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

Register-Click "btnScanWindowsUpdateDrivers" {
    Log-Text "[*] Đang kích hoạt quét driver từ Microsoft Windows Update..."
    Start-Process "usoclient" -ArgumentList "StartInteractiveScan" -NoNewWindow
    Log-Text "[✓] Đã gửi lệnh tìm kiếm Driver mới qua Windows Update."
}

Register-Click "btnCleanDriverStore" {
    Log-Text "[*] Đang quét và dọn dẹp các phiên bản driver cũ trong DriverStore..."
    if ($txtStatus) { $txtStatus.Text = "Đang dọn dẹp DriverStore..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    Invoke-DriverStoreCleanup
    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "Dọn dẹp DriverStore hoàn tất" }
    Log-Text "[✓] Đã dọn dẹp sạch sẽ các bản driver cũ."
}

Register-Click "btnBackupDrivers" {
    $dest = "C:\Backup_Drivers"
    Log-Text "[*] Đang sao lưu toàn bộ Driver của máy ra thư mục: '$dest'..."
    if ($txtStatus) { $txtStatus.Text = "Đang sao lưu driver..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }

    Export-SystemDriversBackup -Destination $dest

    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "Sao lưu driver hoàn tất" }
    Log-Text "[✓] THÀNH CÔNG! Đã sao lưu toàn bộ driver vào: $dest"
}

Register-Click "btnOpenBackupFolder" {
    $dest = "C:\Backup_Drivers"
    if (Test-Path $dest) {
        Start-Process explorer.exe $dest
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
