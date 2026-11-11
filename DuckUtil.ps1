<#
╔══════════════════════════════════════════════════════════════════════════════╗
║                       🦆 DUCK UTIL - PRO SUITE                               ║
║       1. Ứng Dụng (Package Manager) - Lưới Card Grid chuẩn WinUtil           ║
║       2. Gỡ Lỗi Hệ Thống (Troubleshoot & System Repairs)                     ║
║       3. Quản Lý & Gỡ Lỗi Driver (Driver & Windows Update Troubleshooting)    ║
╚══════════════════════════════════════════════════════════════════════════════╝
#>

# ═══════════════════════════════════════════════════════════════════════════════
# 1. TỰ ĐỘNG CHUYỂN SANG QUYỀN ADMINISTRATOR
# ═══════════════════════════════════════════════════════════════════════════════
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2. NẠP THƯ VIỆN WPF & WINFORMS
# ═══════════════════════════════════════════════════════════════════════════════
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ═══════════════════════════════════════════════════════════════════════════════
# 3. KHO DỮ LIỆU ỨNG DỤNG (PHÂN THEO DANH MỤC)
# ═══════════════════════════════════════════════════════════════════════════════
$AppCatalog = @(
    # ── 🌐 TRÌNH DUYỆT WEB ──
    @{ Name="Google Chrome";       ID="Google.Chrome";                    Category="Trình Duyệt Web";    Desc="Trình duyệt phổ biến nhất" }
    @{ Name="Mozilla Firefox";     ID="Mozilla.Firefox";                  Category="Trình Duyệt Web";    Desc="Mã nguồn mở, bảo mật" }
    @{ Name="Brave Browser";       ID="Brave.Brave";                      Category="Trình Duyệt Web";    Desc="Tự động chặn quảng cáo" }
    @{ Name="LibreWolf";           ID="LibreWolf.LibreWolf";              Category="Trình Duyệt Web";    Desc="Firefox không telemetry" }
    @{ Name="Vivaldi";             ID="VivaldiTechnologies.Vivaldi";      Category="Trình Duyệt Web";    Desc="Tùy biến cao, đa nhiệm" }
    @{ Name="Tor Browser";         ID="TorProject.TorBrowser";            Category="Trình Duyệt Web";    Desc="Ẩn danh qua mạng Onion" }
    @{ Name="Opera GX";            ID="Opera.OperaGX";                    Category="Trình Duyệt Web";    Desc="Trình duyệt tối ưu tài nguyên" }

    # ── 💬 LIÊN LẠC & CHAT ──
    @{ Name="Discord";             ID="Discord.Discord";                  Category="Liên Lạc & Chat";   Desc="Voice & chat cộng đồng" }
    @{ Name="Telegram";            ID="Telegram.TelegramDesktop";         Category="Liên Lạc & Chat";   Desc="Nhắn tin nhanh, cloud-sync" }
    @{ Name="Signal";              ID="OpenWhisperSystems.Signal";        Category="Liên Lạc & Chat";   Desc="Mã hóa đầu cuối tuyệt đối" }
    @{ Name="Zalo";                ID="VNG.Zalo";                         Category="Liên Lạc & Chat";   Desc="Nhắn tin phổ biến VN" }
    @{ Name="Zoom";                ID="Zoom.Zoom";                        Category="Liên Lạc & Chat";   Desc="Họp trực tuyến video" }
    @{ Name="Slack";               ID="SlackTechnologies.Slack";          Category="Liên Lạc & Chat";   Desc="Trao đổi công việc nhóm" }
    @{ Name="WhatsApp";            ID="WhatsApp.WhatsApp";                Category="Liên Lạc & Chat";   Desc="Gọi & nhắn tin đa nền tảng" }
    @{ Name="Microsoft Teams";     ID="Microsoft.Teams";                  Category="Liên Lạc & Chat";   Desc="Nền tảng họp & làm việc" }

    # ── 💻 PHÁT TRIỂN & DEV ──
    @{ Name="VS Code";             ID="Microsoft.VisualStudioCode";       Category="Phát Triển & Dev";   Desc="Code editor đa năng" }
    @{ Name="Git";                 ID="Git.Git";                          Category="Phát Triển & Dev";   Desc="Quản lý mã nguồn phân tán" }
    @{ Name="Windows Terminal";    ID="Microsoft.WindowsTerminal";        Category="Phát Triển & Dev";   Desc="Terminal tab hiện đại" }
    @{ Name="Python 3.12";         ID="Python.Python.3.12";              Category="Phát Triển & Dev";   Desc="Ngôn ngữ lập trình đa năng" }
    @{ Name="Node.js LTS";         ID="OpenJS.NodeJS.LTS";               Category="Phát Triển & Dev";   Desc="Runtime JavaScript server" }
    @{ Name="Docker Desktop";      ID="Docker.DockerDesktop";             Category="Phát Triển & Dev";   Desc="Chạy container ảo hóa" }
    @{ Name="Notepad++";           ID="Notepad++.Notepad++";              Category="Phát Triển & Dev";   Desc="Soạn thảo text siêu nhẹ" }
    @{ Name="Postman";             ID="Postman.Postman";                  Category="Phát Triển & Dev";   Desc="Test & xây dựng API" }
    @{ Name="DBeaver CE";          ID="dbeaver.dbeaver";                  Category="Phát Triển & Dev";   Desc="Quản lý database toàn diện" }
    @{ Name="Go Lang";             ID="GoLang.Go";                        Category="Phát Triển & Dev";   Desc="Ngôn ngữ backend hiệu năng cao" }
    @{ Name="Rust (rustup)";       ID="Rustlang.Rustup";                  Category="Phát Triển & Dev";   Desc="Bộ công cụ ngôn ngữ Rust" }

    # ── 🛠️ TIỆN ÍCH HỆ THỐNG ──
    @{ Name="7-Zip";               ID="7zip.7zip";                        Category="Tiện Ích Hệ Thống";  Desc="Giải nén mọi định dạng" }
    @{ Name="WinRAR";              ID="RARLab.WinRAR";                    Category="Tiện Ích Hệ Thống";  Desc="Trình nén tệp tiêu chuẩn" }
    @{ Name="Everything";          ID="voidtools.Everything";             Category="Tiện Ích Hệ Thống";  Desc="Tìm kiếm file tức thì 1s" }
    @{ Name="PowerToys";           ID="Microsoft.PowerToys";              Category="Tiện Ích Hệ Thống";  Desc="Bộ tiện ích chính chủ MS" }
    @{ Name="Flow Launcher";       ID="Flow-Launcher.Flow-Launcher";      Category="Tiện Ích Hệ Thống";  Desc="Thanh tìm kiếm Alt+Space" }
    @{ Name="Revo Uninstaller";    ID="VSRevoGroup.RevoUninstaller";      Category="Tiện Ích Hệ Thống";  Desc="Gỡ phần mềm sạch tận gốc" }
    @{ Name="TreeSize Free";       ID="JAMSoftware.TreeSize.Free";        Category="Tiện Ích Hệ Thống";  Desc="Phân tích dung lượng ổ đĩa" }
    @{ Name="ShareX";              ID="ShareX.ShareX";                    Category="Tiện Ích Hệ Thống";  Desc="Chụp/quay màn hình & OCR" }
    @{ Name="BleachBit";           ID="BleachBit.BleachBit";              Category="Tiện Ích Hệ Thống";  Desc="Dọn dẹp rác & privacy" }
    @{ Name="FanControl";          ID="Rem0o.FanControl";                 Category="Tiện Ích Hệ Thống";  Desc="Tùy chỉnh quạt tản nhiệt" }

    # ── 🎬 ĐA PHƯƠNG TIỆN ──
    @{ Name="VLC Media Player";    ID="VideoLAN.VLC";                     Category="Đa Phương Tiện";     Desc="Xem mọi định dạng video" }
    @{ Name="OBS Studio";          ID="OBSProject.OBSStudio";             Category="Đa Phương Tiện";     Desc="Ghi hình & livestream" }
    @{ Name="Spotify";             ID="Spotify.Spotify";                  Category="Đa Phương Tiện";     Desc="Nghe nhạc bản quyền" }
    @{ Name="GIMP";                ID="GIMP.GIMP";                        Category="Đa Phương Tiện";     Desc="Chỉnh sửa ảnh chuyên nghiệp" }
    @{ Name="Audacity";            ID="Audacity.Audacity";                Category="Đa Phương Tiện";     Desc="Thu âm & biên tập audio" }
    @{ Name="HandBrake";           ID="HandBrake.HandBrake";              Category="Đa Phương Tiện";     Desc="Nén & đổi đuôi video" }
    @{ Name="Krita";               ID="KDE.Krita";                        Category="Đa Phương Tiện";     Desc="Vẽ đồ họa & sketch 2D" }
    @{ Name="K-Lite Codec Mega";   ID="CodecGuide.K-LiteCodecPack.Mega";  Category="Đa Phương Tiện";     Desc="Gói giải mã video/audio" }

    # ── 📝 VĂN PHÒNG & TÀI LIỆU ──
    @{ Name="LibreOffice";         ID="TheDocumentFoundation.LibreOffice"; Category="Văn Phòng & Tài Liệu"; Desc="Bộ Office mã nguồn mở" }
    @{ Name="Obsidian";            ID="Obsidian.Obsidian";                Category="Văn Phòng & Tài Liệu"; Desc="Ghi chú Markdown liên kết" }
    @{ Name="Notion";              ID="Notion.Notion";                    Category="Văn Phòng & Tài Liệu"; Desc="Không gian quản lý ghi chú" }
    @{ Name="SumatraPDF";          ID="SumatraPDF.SumatraPDF";            Category="Văn Phòng & Tài Liệu"; Desc="Đọc PDF siêu nhẹ tức thì" }
    @{ Name="Foxit PDF Reader";    ID="Foxit.FoxitReader";                Category="Văn Phòng & Tài Liệu"; Desc="Xem & ký tài liệu PDF" }

    # ── 🎮 NỀN TẢNG TRÒ CHƠI ──
    @{ Name="Steam";               ID="Valve.Steam";                      Category="Nền Tảng Trò Chơi";  Desc="Kho game PC số 1 thế giới" }
    @{ Name="Epic Games Launcher"; ID="EpicGames.EpicGamesLauncher";      Category="Nền Tảng Trò Chơi";  Desc="Cửa hàng game & phát quà" }
    @{ Name="GOG Galaxy";          ID="GOG.Galaxy";                       Category="Nền Tảng Trò Chơi";  Desc="Quản lý thư viện không DRM" }
    @{ Name="MSI Afterburner";     ID="Guru3D.Afterburner";               Category="Nền Tảng Trò Chơi";  Desc="Đo nhiệt độ, FPS & ép xung" }
    @{ Name="Playnite";            ID="Playnite.Playnite";                Category="Nền Tảng Trò Chơi";  Desc="Gom mọi thư viện game về một" }

    # ── 📁 LƯU TRỮ & TRUYỀN TỆP ──
    @{ Name="qBittorrent";         ID="qBittorrent.qBittorrent";          Category="Lưu Trữ & Truyền Tệp"; Desc="Tải torrent sạch, không QC" }
    @{ Name="LocalSend";           ID="LocalSend.LocalSend";              Category="Lưu Trữ & Truyền Tệp"; Desc="Bắn file qua Wi-Fi nội bộ" }
    @{ Name="WinSCP";              ID="WinSCP.WinSCP";                    Category="Lưu Trữ & Truyền Tệp"; Desc="Truyền tệp qua SFTP/FTP" }
    @{ Name="FileZilla";           ID="TimKosse.FileZilla.Client";        Category="Lưu Trữ & Truyền Tệp"; Desc="Client truyền tệp FTP" }
    @{ Name="Rclone";              ID="Rclone.Rclone";                    Category="Lưu Trữ & Truyền Tệp"; Desc="Mount & đồng bộ đám mây" }

    # ── 🔒 BẢO MẬT & MẠNG ──
    @{ Name="Bitwarden";           ID="Bitwarden.Bitwarden";              Category="Bảo Mật & Mạng";     Desc="Két mật khẩu mã hóa" }
    @{ Name="KeePassXC";           ID="KeePassXCTeam.KeePassXC";          Category="Bảo Mật & Mạng";     Desc="Quản lý mật khẩu offline" }
    @{ Name="Cryptomator";         ID="Cryptomator.Cryptomator";          Category="Bảo Mật & Mạng";     Desc="Mã hóa dữ liệu trước cloud" }
    @{ Name="ProtonVPN";           ID="ProtonTechnologies.ProtonVPN";     Category="Bảo Mật & Mạng";     Desc="Mạng riêng ảo bảo mật cao" }
    @{ Name="RustDesk";            ID="RustDesk.RustDesk";                Category="Bảo Mật & Mạng";     Desc="Điều khiển từ xa tự host" }
    @{ Name="Wireshark";           ID="WiresharkFoundation.Wireshark";    Category="Bảo Mật & Mạng";     Desc="Phân tích gói tin mạng" }

    # ── 🔧 THƯ VIỆN CỐT LÕI ──
    @{ Name="VC++ Redist 2015-2022"; ID="Microsoft.VCRedist.2015+.x64";  Category="Thư Viện Cốt Lõi";   Desc="Cần thiết cho hầu hết app/game" }
    @{ Name=".NET Desktop Runtime 8"; ID="Microsoft.DotNet.DesktopRuntime.8"; Category="Thư Viện Cốt Lõi"; Desc="Nền tảng chạy ứng dụng .NET 8" }
    @{ Name="DirectX End-User";    ID="Microsoft.DirectX";                Category="Thư Viện Cốt Lõi";   Desc="Thư viện đồ họa DirectX" }
    @{ Name="Java OpenJDK 21";     ID="EclipseAdoptium.Temurin.21.JDK";   Category="Thư Viện Cốt Lõi";   Desc="Môi trường chạy Java LTS" }
)

# ═══════════════════════════════════════════════════════════════════════════════
# 4. GIAO DIỆN XAML: FLUENT DARK MODE + THANH ĐIỀU HƯỚNG 3 MỤC
# ═══════════════════════════════════════════════════════════════════════════════
[xml]$XAML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="DuckUtil - Windows Package Manager &amp; System Maintenance Suite"
    Width="1280" Height="880"
    WindowStartupLocation="CenterScreen"
    Background="#1F1F1F"
    Foreground="#F3F3F3"
    FontFamily="Segoe UI Variable Text, Segoe UI">

    <Window.Resources>
        <!-- Nút bấm chức năng chuẩn Fluent -->
        <Style x:Key="FluentButton" TargetType="Button">
            <Setter Property="Background" Value="#2D2D2D"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="Margin" Value="4,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderBrush" Value="#3D3D3D"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="btnBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="#383838"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="#181818"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Nút điều hướng Top Bar -->
        <Style x:Key="NavButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#A0A0A0"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="18,10"/>
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
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                                <Setter TargetName="navBorder" Property="Background" Value="#2A2A2A"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Checkbox Fluent -->
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#D4D4D4"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Margin" Value="0,3"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/> <!-- Top Brand & Search -->
            <RowDefinition Height="Auto"/> <!-- Main Navigation Bar -->
            <RowDefinition Height="*"/>    <!-- Content Container (Tabs) -->
            <RowDefinition Height="Auto"/> <!-- Status & Progress -->
            <RowDefinition Height="150"/>  <!-- Console Drawer -->
        </Grid.RowDefinitions>

        <!-- ═══ 1. HEADER BAR ═══ -->
        <Border Grid.Row="0" Background="#181818" Padding="18,12" BorderBrush="#2B2B2B" BorderThickness="0,0,0,1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="340"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="🦆" FontSize="22" VerticalAlignment="Center" Margin="0,0,10,0"/>
                    <TextBlock Text="DUCK UTIL" FontSize="18" FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"/>
                    <Border Background="#2D2D2D" CornerRadius="4" Margin="10,0,0,0" Padding="6,2" VerticalAlignment="Center">
                        <TextBlock Text="PRO SUITE" FontSize="10" FontWeight="Bold" Foreground="#60CDFF"/>
                    </Border>
                </StackPanel>

                <!-- Search Box -->
                <Border Grid.Column="2" Background="#202020" CornerRadius="4" BorderBrush="#3D3D3D" BorderThickness="1" Padding="8,4">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="🔍" Foreground="#888888" VerticalAlignment="Center" Margin="0,0,6,0"/>
                        <TextBox Grid.Column="1" Name="txtSearch" Background="Transparent" Foreground="#FFFFFF"
                                 BorderThickness="0" FontSize="12" VerticalAlignment="Center"
                                 ToolTip="Gõ để lọc ứng dụng ngay lập tức..."/>
                    </Grid>
                </Border>
            </Grid>
        </Border>

        <!-- ═══ 2. MAIN NAVIGATION TABS BAR ═══ -->
        <Border Grid.Row="1" Background="#202020" Padding="12,0" BorderBrush="#2B2B2B" BorderThickness="0,0,0,1">
            <StackPanel Orientation="Horizontal">
                <Button Name="navBtnApps" Content="📦 ỨNG DỤNG (APPLICATIONS)" Style="{StaticResource NavButton}"
                        BorderBrush="#60CDFF" Foreground="#FFFFFF"/>
                <Button Name="navBtnRepair" Content="🔧 GỠ LỖI &amp; SỬA HỆ THỐNG" Style="{StaticResource NavButton}"/>
                <Button Name="navBtnDrivers" Content="🚗 QUẢN LÝ &amp; GỠ LỖI DRIVER" Style="{StaticResource NavButton}"/>
            </StackPanel>
        </Border>

        <!-- ═══ 3. MAIN CONTENT (TAB CONTROL KHÔNG VIỀN) ═══ -->
        <TabControl Grid.Row="2" Name="MainTabControl" Background="Transparent" BorderThickness="0">
            <!-- Ẩn header mặc định của TabControl vì ta dùng navBtn điều khiển -->
            <TabControl.ItemContainerStyle>
                <Style TargetType="TabItem">
                    <Setter Property="Visibility" Value="Collapsed"/>
                </Style>
            </TabControl.ItemContainerStyle>

            <!-- ── TAB 1: ỨNG DỤNG (CARD GRID) ── -->
            <TabItem>
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <!-- Thanh nút bấm ứng dụng -->
                    <Border Grid.Row="0" Background="#222222" Padding="16,8" BorderBrush="#2B2B2B" BorderThickness="0,0,0,1">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>

                            <StackPanel Grid.Column="0" Orientation="Horizontal">
                                <Button Name="btnInstall" Content="🚀 Install Selected" Style="{StaticResource FluentButton}"
                                        Background="#107C41" BorderBrush="#107C41" Padding="18,8"/>
                                <Button Name="btnUpgradeAll" Content="⚡ Upgrade All" Style="{StaticResource FluentButton}"
                                        Background="#D83B01" BorderBrush="#D83B01"/>
                                <Button Name="btnUninstall" Content="🗑️ Uninstall Selected" Style="{StaticResource FluentButton}"
                                        Background="#A80000" BorderBrush="#A80000"/>
                                <Button Name="btnScanInstalled" Content="🔍 Get Installed" Style="{StaticResource FluentButton}"
                                        Background="#0078D4" BorderBrush="#0078D4"/>
                            </StackPanel>

                            <StackPanel Grid.Column="2" Orientation="Horizontal">
                                <Button Name="btnSelectAll" Content="Select All" Style="{StaticResource FluentButton}"/>
                                <Button Name="btnDeselectAll" Content="Clear Selection" Style="{StaticResource FluentButton}"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Lưới Card chứa ứng dụng -->
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="14,10">
                        <WrapPanel Name="CardsContainer" ItemWidth="236" Orientation="Horizontal"/>
                    </ScrollViewer>
                </Grid>
            </TabItem>

            <!-- ── TAB 2: GỠ LỖI & SỬA HỆ THỐNG ── -->
            <TabItem>
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="18,14">
                    <WrapPanel ItemWidth="380" Orientation="Horizontal">
                        <!-- Card 1: File Hệ Thống -->
                        <Border Background="#252526" BorderBrush="#333333" BorderThickness="1" CornerRadius="6" Margin="6" Padding="14">
                            <StackPanel>
                                <TextBlock Text="🛠️ SỬA CHỮA FILE HỆ THỐNG" FontWeight="Bold" FontSize="13" Foreground="#60CDFF" Margin="0,0,0,10"/>
                                <TextBlock Text="Quét và tự động sửa các file Windows bị hỏng hoặc mất." FontSize="11" Foreground="#999999" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnSfcScan" Content="SFC Scan (sfc /scannow)" Style="{StaticResource FluentButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                                <Button Name="btnDismRestore" Content="DISM RestoreHealth (Phục hồi linh kiện)" Style="{StaticResource FluentButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                                <Button Name="btnDismCleanup" Content="Dọn Kho Linh Kiện (Component Cleanup)" Style="{StaticResource FluentButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 2: Windows Update -->
                        <Border Background="#252526" BorderBrush="#333333" BorderThickness="1" CornerRadius="6" Margin="6" Padding="14">
                            <StackPanel>
                                <TextBlock Text="🔄 GỠ LỖI WINDOWS UPDATE" FontWeight="Bold" FontSize="13" Foreground="#F59E0B" Margin="0,0,0,10"/>
                                <TextBlock Text="Khắc phục lỗi kẹt tải 0%, mã lỗi 0x80070002, 0x8024... khi cập nhật Windows." FontSize="11" Foreground="#999999" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnFixWindowsUpdate" Content="⚡ Reset Toàn Bộ Cache Update (Triệt để)" Style="{StaticResource FluentButton}" Background="#D83B01" BorderBrush="#D83B01" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                                <Button Name="btnRestartUpdateServices" Content="Khởi Động Lại Dịch Vụ BITS &amp; Wuauserv" Style="{StaticResource FluentButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                                <Button Name="btnTriggerScanUpdate" Content="Kích Hoạt Tìm Bản Cập Nhật Mới (USOClient)" Style="{StaticResource FluentButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 3: Mạng & DNS -->
                        <Border Background="#252526" BorderBrush="#333333" BorderThickness="1" CornerRadius="6" Margin="6" Padding="14">
                            <StackPanel>
                                <TextBlock Text="🌐 SỬA LỖI MẠNG &amp; KẾT NỐI" FontWeight="Bold" FontSize="13" Foreground="#10B981" Margin="0,0,0,10"/>
                                <TextBlock Text="Khắc phục sự cố không vào được web, mạng chập chờn, lỗi DNS." FontSize="11" Foreground="#999999" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnFlushDnsWinsock" Content="Flush DNS &amp; Reset Winsock (Làm mới mạng)" Style="{StaticResource FluentButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                                <Button Name="btnResetTcpIp" Content="Reset Toàn Bộ Ngăn Xếp TCP/IP Stack" Style="{StaticResource FluentButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 4: Dọn Rác & Khôi Phục UI -->
                        <Border Background="#252526" BorderBrush="#333333" BorderThickness="1" CornerRadius="6" Margin="6" Padding="14">
                            <StackPanel>
                                <TextBlock Text="🧹 BẢO TRÌ &amp; DỌN DẸP HỆ THỐNG" FontWeight="Bold" FontSize="13" Foreground="#A78BFA" Margin="0,0,0,10"/>
                                <TextBlock Text="Dọn sạch rác ổ C và khởi động lại Taskbar khi bị đơ treo." FontSize="11" Foreground="#999999" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnClearTemp" Content="Dọn Sạch Thư Mục Temp &amp; Cache Rác" Style="{StaticResource FluentButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                                <Button Name="btnRestartExplorer" Content="Khởi Động Lại Windows Explorer (Fix đơ taskbar)" Style="{StaticResource FluentButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                            </StackPanel>
                        </Border>
                    </WrapPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ── TAB 3: QUẢN LÝ & GỠ LỖI DRIVER ── -->
            <TabItem>
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="18,14">
                    <WrapPanel ItemWidth="380" Orientation="Horizontal">
                        <!-- Card 1: Chẩn Đoán Driver Lỗi -->
                        <Border Background="#252526" BorderBrush="#333333" BorderThickness="1" CornerRadius="6" Margin="6" Padding="14">
                            <StackPanel>
                                <TextBlock Text="⚠️ CHẨN ĐOÁN PHẦN CỨNG &amp; DRIVER" FontWeight="Bold" FontSize="13" Foreground="#F43F5E" Margin="0,0,0,10"/>
                                <TextBlock Text="Rà soát các thiết bị bị chấm than vàng, thiếu driver hoặc driver bị crash." FontSize="11" Foreground="#999999" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnScanFaultyDrivers" Content="🔍 Quét Thiết Bị &amp; Driver Bị Lỗi" Style="{StaticResource FluentButton}" Background="#BE123C" BorderBrush="#BE123C" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                                <Button Name="btnPnpRescan" Content="Buộc Windows Quét Lại Phần Cứng (PnP Scan)" Style="{StaticResource FluentButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                                <Button Name="btnOpenDeviceManager" Content="Mở Trình Quản Lý Device Manager" Style="{StaticResource FluentButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 2: Gỡ Lỗi Update Driver -->
                        <Border Background="#252526" BorderBrush="#333333" BorderThickness="1" CornerRadius="6" Margin="6" Padding="14">
                            <StackPanel>
                                <TextBlock Text="🛠️ GỠ LỖI CẬP NHẬT DRIVER" FontWeight="Bold" FontSize="13" Foreground="#F59E0B" Margin="0,0,0,10"/>
                                <TextBlock Text="Sửa lỗi Windows Update bị kẹt khi đang cài driver màn hình, âm thanh, touchpad." FontSize="11" Foreground="#999999" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnFixDriverUpdate" Content="⚡ Sửa Lỗi Kẹt Cập Nhật Driver (Xóa Queue)" Style="{StaticResource FluentButton}" Background="#D83B01" BorderBrush="#D83B01" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                                <Button Name="btnScanWindowsUpdateDrivers" Content="Kích Hoạt Quét Driver Mới Từ Microsoft" Style="{StaticResource FluentButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                                <Button Name="btnCleanDriverStore" Content="Dọn Dẹp Driver Cũ Trong DriverStore" Style="{StaticResource FluentButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                            </StackPanel>
                        </Border>

                        <!-- Card 3: Sao Lưu Driver -->
                        <Border Background="#252526" BorderBrush="#333333" BorderThickness="1" CornerRadius="6" Margin="6" Padding="14">
                            <StackPanel>
                                <TextBlock Text="💾 SAO LƯU &amp; BẢO VỆ DRIVER" FontWeight="Bold" FontSize="13" Foreground="#10B981" Margin="0,0,0,10"/>
                                <TextBlock Text="Trích xuất toàn bộ driver bên thứ ba để phòng khi cài lại Windows không sợ mất mạng/wifi." FontSize="11" Foreground="#999999" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnBackupDrivers" Content="Sao Lưu Toàn Bộ Driver (Ra C:\Backup_Drivers)" Style="{StaticResource FluentButton}" Background="#047857" BorderBrush="#047857" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                                <Button Name="btnOpenBackupFolder" Content="Mở Thư Mục Chứa Driver Đã Sao Lưu" Style="{StaticResource FluentButton}" Margin="0,4" HorizontalContentAlignment="Left" Padding="12,10"/>
                            </StackPanel>
                        </Border>
                    </WrapPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- ═══ 4. STATUS & PROGRESS ═══ -->
        <Border Grid.Row="3" Background="#181818" Padding="16,6" BorderBrush="#2B2B2B" BorderThickness="0,1,0,0">
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
                           Foreground="#60CDFF" FontSize="12" FontWeight="SemiBold"/>
                <TextBlock Grid.Column="1" Grid.Row="0" Name="txtSelectionCount" Text="0 app được chọn"
                           Foreground="#888888" FontSize="11"/>

                <ProgressBar Grid.Column="0" Grid.ColumnSpan="2" Grid.Row="1"
                             Name="progressBar" Height="4" Margin="0,6,0,2"
                             Background="#2B2B2B" Foreground="#0078D4" BorderThickness="0" Value="0"/>
            </Grid>
        </Border>

        <!-- ═══ 5. CONSOLE LOG DRAWER ═══ -->
        <Border Grid.Row="4" Background="#111111" Padding="12,8">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0" Margin="0,0,0,4">
                    <TextBlock Text="TERMINAL LOG" FontSize="10" FontWeight="Bold" Foreground="#666666"/>
                    <Button Name="btnClearLog" Content="Xóa Log" HorizontalAlignment="Right"
                            Background="Transparent" Foreground="#888888" BorderThickness="0" Cursor="Hand" FontSize="11"/>
                </Grid>
                <TextBox Grid.Row="1" Name="txtLog" Background="Transparent" Foreground="#4EC9B0"
                         FontFamily="Cascadia Mono, Consolas, Courier New" FontSize="11"
                         IsReadOnly="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"
                         BorderThickness="0"
                         Text="[DuckUtil Suite] Khởi tạo thành công với đầy đủ module App, Repair &amp; Drivers.&#x0d;&#x0a;"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# ═══════════════════════════════════════════════════════════════════════════════
# 5. KHỞI TẠO CỬA SỔ & ÁNH XẠ BIẾN ĐIỀU KHIỂN
# ═══════════════════════════════════════════════════════════════════════════════
$reader = New-Object System.Xml.XmlNodeReader $XAML
$window = [Windows.Markup.XamlReader]::Load($reader)

# Điều hướng chính
$mainTabControl     = $window.FindName("MainTabControl")
$navBtnApps         = $window.FindName("navBtnApps")
$navBtnRepair       = $window.FindName("navBtnRepair")
$navBtnDrivers      = $window.FindName("navBtnDrivers")

# Trạng thái & log
$txtSearch          = $window.FindName("txtSearch")
$txtLog             = $window.FindName("txtLog")
$txtStatus          = $window.FindName("txtStatus")
$txtSelectionCount  = $window.FindName("txtSelectionCount")
$progressBar        = $window.FindName("progressBar")
$btnClearLog        = $window.FindName("btnClearLog")

# Nút App
$cardsContainer     = $window.FindName("CardsContainer")
$btnInstall         = $window.FindName("btnInstall")
$btnUninstall       = $window.FindName("btnUninstall")
$btnUpgradeAll      = $window.FindName("btnUpgradeAll")
$btnSelectAll       = $window.FindName("btnSelectAll")
$btnDeselectAll     = $window.FindName("btnDeselectAll")
$btnScanInstalled   = $window.FindName("btnScanInstalled")

# Nút Sửa Hệ Thống
$btnSfcScan                 = $window.FindName("btnSfcScan")
$btnDismRestore             = $window.FindName("btnDismRestore")
$btnDismCleanup             = $window.FindName("btnDismCleanup")
$btnFixWindowsUpdate        = $window.FindName("btnFixWindowsUpdate")
$btnRestartUpdateServices   = $window.FindName("btnRestartUpdateServices")
$btnTriggerScanUpdate       = $window.FindName("btnTriggerScanUpdate")
$btnFlushDnsWinsock         = $window.FindName("btnFlushDnsWinsock")
$btnResetTcpIp              = $window.FindName("btnResetTcpIp")
$btnClearTemp               = $window.FindName("btnClearTemp")
$btnRestartExplorer         = $window.FindName("btnRestartExplorer")

# Nút Driver
$btnScanFaultyDrivers       = $window.FindName("btnScanFaultyDrivers")
$btnPnpRescan               = $window.FindName("btnPnpRescan")
$btnOpenDeviceManager       = $window.FindName("btnOpenDeviceManager")
$btnFixDriverUpdate         = $window.FindName("btnFixDriverUpdate")
$btnScanWindowsUpdateDrivers= $window.FindName("btnScanWindowsUpdateDrivers")
$btnCleanDriverStore        = $window.FindName("btnCleanDriverStore")
$btnBackupDrivers           = $window.FindName("btnBackupDrivers")
$btnOpenBackupFolder        = $window.FindName("btnOpenBackupFolder")

# ═══════════════════════════════════════════════════════════════════════════════
# 6. HỆ THỐNG ĐIỀU HƯỚNG TAB CHÍNH (TOP NAV)
# ═══════════════════════════════════════════════════════════════════════════════
function Set-ActiveTab {
    param([int]$Index, [System.Windows.Controls.Button]$ActiveBtn)
    $mainTabControl.SelectedIndex = $Index
    $navButtons = @($navBtnApps, $navBtnRepair, $navBtnDrivers)
    foreach ($btn in $navButtons) {
        $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A0A0A0")
        $btn.BorderBrush = [System.Windows.Media.Brushes]::Transparent
    }
    $ActiveBtn.Foreground = [System.Windows.Media.Brushes]::White
    $ActiveBtn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#60CDFF")
}

$navBtnApps.Add_Click({ Set-ActiveTab 0 $navBtnApps })
$navBtnRepair.Add_Click({ Set-ActiveTab 1 $navBtnRepair })
$navBtnDrivers.Add_Click({ Set-ActiveTab 2 $navBtnDrivers })

# ═══════════════════════════════════════════════════════════════════════════════
# 7. SINH TỰ ĐỘNG CÁC CARD ỨNG DỤNG
# ═══════════════════════════════════════════════════════════════════════════════
$allCheckBoxes = @()
$categories = $AppCatalog | Select-Object -ExpandProperty Category -Unique

function Update-SelectionCount {
    $selectedCount = @($allCheckBoxes | Where-Object { $_.IsChecked }).Count
    $txtSelectionCount.Text = "$selectedCount app được chọn"
}

foreach ($cat in $categories) {
    $cardBorder = New-Object System.Windows.Controls.Border
    $cardBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#252526")
    $cardBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#333333")
    $cardBorder.BorderThickness = New-Object System.Windows.Thickness(1)
    $cardBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
    $cardBorder.Margin = New-Object System.Windows.Thickness(5)
    $cardBorder.Padding = New-Object System.Windows.Thickness(10, 8, 10, 10)

    $cardStack = New-Object System.Windows.Controls.StackPanel
    $appsInCat = @($AppCatalog | Where-Object { $_.Category -eq $cat })

    $headerText = New-Object System.Windows.Controls.TextBlock
    $headerText.Text = "$cat ($($appsInCat.Count))"
    $headerText.FontSize = 12
    $headerText.FontWeight = [System.Windows.FontWeights]::Bold
    $headerText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#60CDFF")
    $cardStack.Children.Add($headerText) | Out-Null

    $separator = New-Object System.Windows.Controls.Border
    $separator.Height = 1
    $separator.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#383838")
    $separator.Margin = New-Object System.Windows.Thickness(0, 4, 0, 6)
    $cardStack.Children.Add($separator) | Out-Null

    foreach ($app in $appsInCat) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $app.Name
        $cb.Tag = $app
        $cb.ToolTip = "$($app.Name)`nID: $($app.ID)`n$($app.Desc)"
        $cb.Margin = New-Object System.Windows.Thickness(2, 3, 2, 3)

        $cb.Add_Checked({ Update-SelectionCount })
        $cb.Add_Unchecked({ Update-SelectionCount })

        $cardStack.Children.Add($cb) | Out-Null
        $allCheckBoxes += $cb
    }

    $cardBorder.Child = $cardStack
    $cardsContainer.Children.Add($cardBorder) | Out-Null
}

# ═══════════════════════════════════════════════════════════════════════════════
# 8. HÀM THỰC THI TIẾN TRÌNH & STREAMING OUTPUT MƯỢT MÀ
# ═══════════════════════════════════════════════════════════════════════════════
function Log-Text {
    param([string]$Msg)
    $txtLog.AppendText($Msg + "`r`n")
    $txtLog.ScrollToEnd()
    [System.Windows.Forms.Application]::DoEvents()
}

$btnClearLog.Add_Click({ $txtLog.Text = "" })

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

# ═══════════════════════════════════════════════════════════════════════════════
# 9. MODULE 1: LOGIC ỨNG DỤNG
# ═══════════════════════════════════════════════════════════════════════════════
$txtSearch.Add_TextChanged({
    $keyword = $txtSearch.Text.Trim().ToLower()
    foreach ($cb in $allCheckBoxes) {
        $app = $cb.Tag
        $matched = [string]::IsNullOrEmpty($keyword) -or ($app.Name.ToLower().Contains($keyword)) -or ($app.ID.ToLower().Contains($keyword))
        $cb.Visibility = if ($matched) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    }
})

$btnScanInstalled.Add_Click({
    Log-Text "[🔍] Đang chạy 'winget list' để quét toàn bộ phần mềm hiện có trên máy..."
    $txtStatus.Text = "Đang quét danh sách phần mềm..."
    $progressBar.IsIndeterminate = $true

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "winget"
    $pinfo.Arguments = "list"
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($pinfo)
    $installed = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()

    $progressBar.IsIndeterminate = $false
    $found = 0

    foreach ($cb in $allCheckBoxes) {
        $app = $cb.Tag
        if ($installed.Contains($app.ID) -or $installed.Contains($app.Name)) {
            $cb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#60CDFF")
            $cb.Content = "$($app.Name) [✓]"
            $found++
        }
    }
    Log-Text "[✓] Quét hoàn tất! Phát hiện $found ứng dụng trong danh mục đã có mặt trên máy bạn."
    $txtStatus.Text = "Phát hiện $found ứng dụng đã cài"
})

$btnInstall.Add_Click({
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
        $progressBar.Value = [math]::Round(($idx / $total) * 100)
        $txtStatus.Text = "[$idx/$total] Đang cài đặt: $($app.Name)..."
        Log-Text "[$idx/$total] Đang cài: $($app.Name) (ID: $($app.ID))..."

        $code = Run-CliStream "winget" "install --id $($app.ID) --exact --silent --accept-package-agreements --accept-source-agreements"
        if ($code -eq 0) {
            Log-Text "   [✓ HOÀN THÀNH] $($app.Name)"
        } else {
            Log-Text "   [❌ LỖI] $($app.Name) (Exit Code: $code)"
        }
    }
    $txtStatus.Text = "Cài đặt hoàn tất!"
    $progressBar.Value = 100
})

$btnUninstall.Add_Click({
    $selected = @($allCheckBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($selected.Count -eq 0) {
        Log-Text "[!] Bạn chưa chọn ứng dụng nào để gỡ cài đặt!"
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Bạn có chắc chắn muốn gỡ cài đặt $($selected.Count) ứng dụng đã chọn?",
        "Xác nhận gỡ bỏ",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $total = $selected.Count
    $idx = 0
    Log-Text "🗑️ BẮT ĐẦU GỠ CÀI ĐẶT $total ỨNG DỤNG..."

    foreach ($app in $selected) {
        $idx++
        $progressBar.Value = [math]::Round(($idx / $total) * 100)
        $txtStatus.Text = "[$idx/$total] Đang gỡ bỏ: $($app.Name)..."
        Log-Text "[$idx/$total] Đang gỡ: $($app.Name)..."

        $code = Run-CliStream "winget" "uninstall --id $($app.ID) --exact --silent"
        if ($code -eq 0) {
            Log-Text "   [✓ ĐÃ GỠ BỎ] $($app.Name)"
        } else {
            Log-Text "   [❌ KHÔNG THỂ GỠ] $($app.Name) (Code: $code)"
        }
    }
    $txtStatus.Text = "Gỡ cài đặt hoàn tất"
    $progressBar.Value = 100
})

$btnUpgradeAll.Add_Click({
    Log-Text "⚡ Đang kiểm tra và cập nhật toàn bộ ứng dụng trên máy ('winget upgrade --all')..."
    $txtStatus.Text = "Đang cập nhật toàn bộ hệ thống..."
    $progressBar.IsIndeterminate = $true

    Run-CliStream "winget" "upgrade --all --silent --accept-package-agreements --accept-source-agreements --include-unknown"

    $progressBar.IsIndeterminate = $false
    $progressBar.Value = 100
    $txtStatus.Text = "Nâng cấp hoàn tất"
})

$btnSelectAll.Add_Click({
    foreach ($cb in $allCheckBoxes) { $cb.IsChecked = $true }
    Update-SelectionCount
})

$btnDeselectAll.Add_Click({
    foreach ($cb in $allCheckBoxes) { $cb.IsChecked = $false }
    Update-SelectionCount
})

# ═══════════════════════════════════════════════════════════════════════════════
# 10. MODULE 2: GỠ LỖI & SỬA HỆ THỐNG (SYSTEM REPAIR)
# ═══════════════════════════════════════════════════════════════════════════════
$btnSfcScan.Add_Click({
    Log-Text "[*] Đang khởi chạy System File Checker (sfc /scannow)... Quá trình có thể mất vài phút."
    $txtStatus.Text = "Đang chạy SFC Scan..."
    $progressBar.IsIndeterminate = $true

    Run-CliStream "sfc.exe" "/scannow"

    $progressBar.IsIndeterminate = $false
    $txtStatus.Text = "SFC Scan hoàn tất"
})

$btnDismRestore.Add_Click({
    Log-Text "[*] Đang khởi chạy DISM RestoreHealth... Khắc phục kho linh kiện Windows từ bản chuẩn."
    $txtStatus.Text = "Đang chạy DISM RestoreHealth..."
    $progressBar.IsIndeterminate = $true

    Run-CliStream "dism.exe" "/Online /Cleanup-Image /RestoreHealth"

    $progressBar.IsIndeterminate = $false
    $txtStatus.Text = "DISM Restore hoàn tất"
})

$btnDismCleanup.Add_Click({
    Log-Text "[*] Đang dọn dẹp các bản backup cũ trong kho linh kiện (DISM Component Cleanup)..."
    $txtStatus.Text = "Đang dọn Component Store..."
    $progressBar.IsIndeterminate = $true

    Run-CliStream "dism.exe" "/Online /Cleanup-Image /StartComponentCleanup"

    $progressBar.IsIndeterminate = $false
    $txtStatus.Text = "Component Cleanup hoàn tất"
})

function Reset-WindowsUpdateEngine {
    Log-Text "[*] Bắt đầu quy trình làm sạch & gỡ lỗi Windows Update triệt để..."
    $txtStatus.Text = "Đang reset Windows Update..."
    $progressBar.IsIndeterminate = $true

    $services = @("wuauserv", "bits", "cryptsvc", "trustedinstaller")
    foreach ($s in $services) {
        Log-Text "   - Đang dừng dịch vụ: $s"
        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
    }

    $sd = "C:\Windows\SoftwareDistribution"
    if (Test-Path $sd) {
        $timestamp = (Get-Date).ToString("yyyyMMddHHmmss")
        Log-Text "   - Xóa bỏ bộ nhớ đệm cập nhật cũ trong SoftwareDistribution..."
        Rename-Item -Path $sd -NewName "SoftwareDistribution.bak.$timestamp" -ErrorAction SilentlyContinue
    }

    $cr2 = "C:\Windows\System32\catroot2"
    if (Test-Path $cr2) {
        $timestamp = (Get-Date).ToString("yyyyMMddHHmmss")
        Log-Text "   - Làm mới chữ ký danh mục catroot2..."
        Rename-Item -Path $cr2 -NewName "catroot2.bak.$timestamp" -ErrorAction SilentlyContinue
    }

    foreach ($s in @("cryptsvc", "bits", "wuauserv")) {
        Log-Text "   - Đang khởi động lại dịch vụ: $s"
        Start-Service -Name $s -ErrorAction SilentlyContinue
    }

    $progressBar.IsIndeterminate = $false
    $txtStatus.Text = "Đã reset xong Windows Update"
    Log-Text "[✓] Hoàn thành! Toàn bộ cache kẹt của Windows Update đã được xóa bỏ sạch sẽ."
}

$btnFixWindowsUpdate.Add_Click({ Reset-WindowsUpdateEngine })

$btnRestartUpdateServices.Add_Click({
    Log-Text "[*] Đang restart dịch vụ BITS và Windows Update..."
    Restart-Service -Name bits -Force -ErrorAction SilentlyContinue
    Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Log-Text "[✓] Đã khởi động lại dịch vụ BITS & WUAUSERV."
})

$btnTriggerScanUpdate.Add_Click({
    Log-Text "[*] Đang gửi tín hiệu kích hoạt quét bản cập nhật mới qua USOClient..."
    Start-Process "usoclient" -ArgumentList "StartScan" -NoNewWindow
    Log-Text "[✓] Đã kích hoạt quét cập nhật ngầm."
})

$btnFlushDnsWinsock.Add_Click({
    Log-Text "[*] Đang làm mới cấu hình DNS và đặt lại Winsock..."
    ipconfig /flushdns | Out-Null
    netsh winsock reset | Out-Null
    Log-Text "[✓] Đã Flush DNS và Reset Winsock thành công."
})

$btnResetTcpIp.Add_Click({
    Log-Text "[*] Đang reset ngăn xếp TCP/IP..."
    netsh int ip reset | Out-Null
    Log-Text "[✓] Đã reset giao thức TCP/IP Stack."
})

$btnClearTemp.Add_Click({
    Log-Text "[*] Đang dọn dẹp các thư mục temp và file rác..."
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Log-Text "[✓] Đã giải phóng các file rác trong Temp."
})

$btnRestartExplorer.Add_Click({
    Log-Text "[*] Đang khởi động lại tiến trình Windows Explorer..."
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
    Log-Text "[✓] Đã khởi động lại Taskbar & Explorer."
})

# ═══════════════════════════════════════════════════════════════════════════════
# 11. MODULE 3: QUẢN LÝ & GỠ LỖI DRIVER
# ═══════════════════════════════════════════════════════════════════════════════
$btnScanFaultyDrivers.Add_Click({
    Log-Text "=========================================================="
    Log-Text "🔍 ĐANG RÀ SOÁT TẤT CẢ THIẾT BỊ & TRÌNH ĐIỀU KHIỂN..."
    Log-Text "=========================================================="
    $txtStatus.Text = "Đang quét thiết bị lỗi..."

    $faulty = @(Get-PnpDevice | Where-Object { $_.Present -eq $true -and $_.Status -ne 'OK' })

    if ($faulty.Count -eq 0) {
        Log-Text "[✓] Tuyệt vời! Không phát hiện thiết bị nào bị lỗi hoặc thiếu driver trên máy bạn."
        $txtStatus.Text = "Tất cả Driver đều hoạt động tốt"
    } else {
        Log-Text "[⚠️] PHÁT HIỆN $($faulty.Count) THIẾT BỊ ĐANG BỊ LỖI / THIẾU DRIVER:"
        foreach ($d in $faulty) {
            Log-Text "   • Tên thiết bị: $($d.FriendlyName)"
            Log-Text "     Mã phần cứng: $($d.InstanceId)"
            Log-Text "     Trạng thái: $($d.Status) | Vấn đề: $($d.Problem)"
            Log-Text "   ────────────────────────────────────────────────"
        }
        $txtStatus.Text = "Phát hiện $($faulty.Count) thiết bị lỗi"
    }
})

$btnPnpRescan.Add_Click({
    Log-Text "[*] Đang gửi lệnh quét phần cứng Plug and Play (pnputil /scan-devices)..."
    Run-CliStream "pnputil.exe" "/scan-devices"
    Log-Text "[✓] Windows đã hoàn tất quét và phát hiện lại các thiết bị phần cứng."
})

$btnOpenDeviceManager.Add_Click({
    Log-Text "[*] Đang mở Trình quản lý thiết bị (devmgmt.msc)..."
    Start-Process "devmgmt.msc"
})

$btnFixDriverUpdate.Add_Click({
    Log-Text "[*] Đang giải phóng hàng đợi tải driver bị kẹt trong Windows Update..."
    $txtStatus.Text = "Đang sửa lỗi kẹt cập nhật driver..."
    $progressBar.IsIndeterminate = $true

    # Reset update cache
    Reset-WindowsUpdateEngine

    # Kích hoạt quét lại phần cứng
    Log-Text "   - Đang buộc nhận diện lại các thiết bị phần cứng..."
    Run-CliStream "pnputil.exe" "/scan-devices"

    # Gửi lệnh tìm kiếm driver mới
    Log-Text "   - Yêu cầu Windows Update quét tìm driver thay thế mới..."
    Start-Process "usoclient" -ArgumentList "StartScan" -NoNewWindow

    $progressBar.IsIndeterminate = $false
    $txtStatus.Text = "Đã gỡ lỗi kẹt driver update"
    Log-Text "[✓] Hoàn thành! Lỗi kẹt tải driver đã được dọn sạch."
})

$btnScanWindowsUpdateDrivers.Add_Click({
    Log-Text "[*] Đang kích hoạt quét driver từ Microsoft Windows Update..."
    Start-Process "usoclient" -ArgumentList "StartInteractiveScan" -NoNewWindow
    Log-Text "[✓] Đã gửi lệnh tìm kiếm Driver mới qua Windows Update."
})

$btnCleanDriverStore.Add_Click({
    Log-Text "[*] Đang quét và dọn dẹp các phiên bản driver cũ không còn sử dụng trong DriverStore..."
    $txtStatus.Text = "Đang dọn dẹp DriverStore..."
    $progressBar.IsIndeterminate = $true

    Run-CliStream "dism.exe" "/Online /Cleanup-Image /StartComponentCleanup /ResetBase"

    $progressBar.IsIndeterminate = $false
    $txtStatus.Text = "Dọn dẹp DriverStore hoàn tất"
    Log-Text "[✓] Đã dọn dẹp sạch sẽ các bản driver cũ."
})

$btnBackupDrivers.Add_Click({
    $dest = "C:\Backup_Drivers"
    Log-Text "[*] Đang sao lưu toàn bộ Driver của máy ra thư mục: '$dest'..."
    $txtStatus.Text = "Đang sao lưu driver..."
    $progressBar.IsIndeterminate = $true

    if (-not (Test-Path $dest)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }

    try {
        Export-WindowsDriver -Online -Destination $dest -ErrorAction Stop | Out-Null
        Log-Text "[✓] THÀNH CÔNG! Đã sao lưu toàn bộ driver bên thứ ba vào: $dest"
        $txtStatus.Text = "Sao lưu driver hoàn tất"
    } catch {
        Log-Text "[!] Lỗi khi xuất bằng Export-WindowsDriver. Đang thử lại bằng pnputil..."
        Run-CliStream "pnputil.exe" "/export-driver * `"$dest`""
        Log-Text "[✓] Đã sao lưu driver qua pnputil vào: $dest"
    }

    $progressBar.IsIndeterminate = $false
})

$btnOpenBackupFolder.Add_Click({
    $dest = "C:\Backup_Drivers"
    if (Test-Path $dest) {
        Start-Process explorer.exe $dest
    } else {
        Log-Text "[!] Thư mục $dest chưa tồn tại. Hãy bấm nút 'Sao Lưu Toàn Bộ Driver' trước."
    }
})

# ═══════════════════════════════════════════════════════════════════════════════
# 12. KHỞI CHẠY GIAO DIỆN
# ═══════════════════════════════════════════════════════════════════════════════
$window.ShowDialog() | Out-Null
