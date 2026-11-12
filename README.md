# 🦆 DuckUtil - Cyber Obsidian Suite
> **Enterprise-Grade Windows Package Manager, System Maintenance & Driver Suite**  
> Giải pháp quản trị hệ thống toàn diện cho Windows 10 & 11, xây dựng trên nền tảng **PowerShell 7 / Windows PowerShell 5.1** kết hợp giao diện đồ họa **WPF Fluent Cyber Dark Mode**.

---

## ⚡ Khởi Chạy Nhanh (Quick Launch)

Mở **Windows Terminal** (hoặc PowerShell với quyền Administrator) và thực thi lệnh:

```powershell
irm is.gd/duckutil | iex
```

*Hoặc sử dụng liên kết kho mã nguồn trực tiếp từ GitHub:*

```powershell
irm https://raw.githubusercontent.com/Duckkiru/app-driver/main/DuckUtil.ps1 | iex
```

> **Ghi chú phân quyền & môi trường:** DuckUtil tích hợp cơ chế tự động nâng quyền Quản trị viên (UAC Self-Elevation). Khi khởi chạy từ môi trường người dùng tiêu chuẩn hoặc Windows Terminal, ứng dụng sẽ yêu cầu xác nhận UAC và duy trì phiên làm việc liền mạch trên chế độ Single-Threaded Apartment (`-Sta`) với khả năng tương thích 100% trên cả Windows PowerShell 5.1 và PowerShell 7.

---

## 📂 Kiến Trúc Hệ Thống (Modular Architecture)

DuckUtil áp dụng kiến trúc mô-đun hóa độc lập, phân tách rõ ràng giữa cấu hình dữ liệu, giao diện người dùng và các luồng xử lý nghiệp vụ:

```text
DuckUtil/
├── config/
│   └── apps.json               # Danh mục cấu hình 114 ứng dụng qua 15 nhóm chuyên biệt
├── xaml/
│   └── MainWindow.xaml         # Giao diện WPF Fluent Cyber Dark Mode, thanh cuộn Minimalist 8px
├── functions/
│   ├── public/
│   │   ├── Invoke-DriverSuite.ps1    # Phân hệ chẩn đoán, xuất bản sao lưu và tối ưu hóa DriverStore
│   │   └── Invoke-SystemRepairs.ps1  # Phân hệ phục hồi hệ thống, DISM, SFC, Windows Update & Network
│   └── private/
│       ├── ProcessRunner.ps1         # Trình thực thi CLI bất đồng bộ hai luồng, chống deadlock và vỡ font
│       └── SmartMatcher.ps1          # Thuật toán đối soát phiên bản 5 tầng (Exact ID, Aliases, Clean Name)
├── scripts/
│   ├── start.ps1               # Khởi tạo tiến trình, điều phối Windows Terminal và tự động nâng quyền UAC
│   └── main.ps1                # Bộ điều phối sự kiện (Controller), kết nối dữ liệu và hiển thị WPF
├── Compile.ps1                 # Trình đóng gói tự động toàn bộ module thành tệp DuckUtil.ps1 duy nhất
├── .github/
│   └── workflows/
│       └── build.yml           # CI/CD Pipeline tự động kiểm tra cú pháp và đóng gói bản phát hành
├── DuckUtil.ps1                # Bản phát hành phân phối độc lập (Single-file Distribution)
└── README.md                   # Tài liệu hướng dẫn kỹ thuật và đặc tả hệ thống
```

---

## 🌟 Phân Hệ Tính Năng Chính

### 1. Quản Lý Ứng Dụng (Package Manager - Cyber Dark Mode)
- **Kho danh mục đồ sộ 114 ứng dụng qua 15 danh mục chuyên biệt:**
  - **Web Browsers (7 app):** Google Chrome, Mozilla Firefox, Brave Browser, LibreWolf, Vivaldi, Tor Browser, Opera GX.
  - **Communication (8 app):** Discord, Telegram, Signal, Zalo, Zoom, Slack, WhatsApp, Microsoft Teams.
  - **Remote Desktop (4 app):** RustDesk, AnyDesk, UltraViewer, TeamViewer.
  - **Development (12 app):** VS Code, Git, Windows Terminal, Windows Terminal Preview, Python 3.12, Node.js LTS, Docker Desktop, Notepad++, Postman, DBeaver CE, Go Lang, Rust (rustup).
  - **.NET Runtimes (12 app):** .NET Framework 4.8.1, .NET Desktop Runtime 3.1 / 5.0 / 6 (x64/x86) / 7 (x64/x86) / 8 LTS (x64/x86) / 9 / 10 / 11 Preview.
  - **Java Runtimes (16 app):** Eclipse Temurin OpenJDK / JRE các phiên bản 8, 11, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25.
  - **C++ & System Runtimes (13 app):** Microsoft Visual C++ Redistributable từ bản 2005 đến 2022 (đầy đủ cả hai kiến trúc x64 và x86), DirectX End-User Runtimes.
  - **System Utilities (8 app):** 7-Zip, WinRAR, Everything, Microsoft PowerToys, Flow Launcher, Revo Uninstaller, TreeSize Free, BleachBit.
  - **Hardware & Monitoring (4 app):** MSI Afterburner, FanControl, CPUID CPU-Z, CPUID HWMonitor.
  - **Security & Network (5 app):** Bitwarden, KeePassXC, Cryptomator, ProtonVPN, Wireshark.
  - **Audio & Video (6 app):** VLC Media Player, OBS Studio, Spotify, Audacity, HandBrake, K-Lite Codec Pack Mega.
  - **Graphics & Design (5 app):** ShareX, GIMP, Krita, Blender, Inkscape.
  - **Documents & Office (5 app):** LibreOffice, Obsidian, Notion, SumatraPDF, Foxit PDF Reader.
  - **Game Launchers (4 app):** Steam, Epic Games Launcher, GOG Galaxy, Playnite.
  - **File Transfer & Cloud (5 app):** qBittorrent, LocalSend, WinSCP, FileZilla, Rclone.

- **Cơ chế nhận diện trạng thái phiên bản 3 màu sắc trực quan:**
  - ⚪ **Trắng (`Chưa cài đặt`)**: Ứng dụng chưa hiện diện trên hệ thống máy trạm.
  - 🟢 **Xanh lục (`✓ Mới nhất`)**: Ứng dụng đã được cài đặt và đang vận hành ở phiên bản mới nhất.
  - 🔴 **Đỏ (`⚠️ Có bản mới`)**: Phát hiện phiên bản cũ hơn so với kho phân phối chính thức; hiển thị phiên bản khả dụng trên tooltip.

- **Thuật toán Smart Matcher 5 tầng nâng cao:**
  - *Tầng 1 - Khớp mã định danh chính xác (Exact WinGet ID)*: Tra cứu O(1) qua từ điển băm `Dictionary[string, object]`.
  - *Tầng 2 - Khớp tên chính xác (Exact Name)*: Đối soát tên chuẩn từ WinGet.
  - *Tầng 3 - Tra cứu bí danh mở rộng (Rich Aliases Dictionary)*: Hỗ trợ nhận diện các phần mềm nội địa và quốc tế.
  - *Tầng 4 - Chuẩn hóa tên ứng dụng (Normalized Name Heuristics)*: Lược bỏ các hậu tố kỹ thuật nhưng **bảo tồn nguyên vẹn nhãn kiến trúc `(x64)`, `(x86)`, `(arm64)`**, đảm bảo không nhận diện nhầm giữa bản 64-bit và 32-bit.
  - *Tầng 5 - Khớp từ khóa chặt chẽ có ranh giới từ (`\b`)*: Yêu cầu độ dài bí danh tối thiểu >= 4 ký tự, kết hợp cờ **chặn khớp chéo giữa bản thường (Stable) và bản thử nghiệm (Preview)**.
  - *Bảo toàn định danh thứ tự*: Giữ tiền tố `[#IDn]` trên tooltip của ứng dụng trước và sau khi quét.
  - *Xử lý lỗi & Timeout*: Kiểm tra ExitCode của `winget list`, không xóa trắng giao diện nếu WinGet gặp sự cố gián đoạn.

- **Thao tác hàng loạt chuyên nghiệp:**
  - Cài đặt danh sách đã chọn, gỡ cài đặt có kiểm soát theo mã ID phát hiện thực tế (`DetectedId`).
  - Nâng cấp toàn bộ hệ thống (`winget upgrade --all`) với thanh tiến trình trực quan.
  - Lọc ứng dụng theo thời gian thực (Search filter); nút *Chọn tất cả* chỉ chọn các ứng dụng đang hiển thị theo bộ lọc.

---

### 2. Chẩn Đoán & Khắc Phục Lỗi Hệ Thống (System Diagnostic & Repair)
- **Kiểm tra tệp tin hệ thống (SFC Scan):** Thực thi `sfc /scannow` với bộ giải mã luồng Unicode (UTF-16LE) chống vỡ font tiếng Việt. Kiểm tra mã thoát (ExitCode) và thông báo kết quả chi tiết.
- **Khôi phục ảnh hệ thống (DISM Health Restore):**
  - Thực thi `dism /online /cleanup-image /restorehealth` kết nối trực tiếp đến Windows Update để sửa chữa kho thành phần.
  - Tùy chọn dọn dẹp sâu Component Store (`/StartComponentCleanup /ResetBase`): **Tích hợp cảnh báo an toàn rõ ràng** thông báo cho quản trị viên rằng các bản cập nhật cũ sẽ không thể rollback sau khi tiến trình hoàn tất.
- **Đặt lại tiến trình Windows Update (Deep Reset):**
  - Dừng an toàn toàn bộ 5 dịch vụ cốt lõi: `wuauserv`, `bits`, `cryptsvc`, `dosvc`, `trustedinstaller`.
  - Giải phóng bộ điều khiển tệp, đổi tên và làm mới bộ nhớ tạm `SoftwareDistribution` và `Catroot2`. Xác thực việc giải phóng thành công trước khi báo cáo kết quả.
- **Khôi phục cấu hình mạng (Network Stack Reset):** Xóa bộ đệm phân giải tên miền (`ipconfig /flushdns`), đặt lại Winsock (`netsh winsock reset`) và khôi phục ngăn xếp TCP/IP (`netsh int ip reset`).
- **Dọn dẹp hệ thống & Nhật ký sự kiện có xác nhận:**
  - Giải phóng bộ nhớ tạm người dùng (`User Temp`) và bộ nhớ đệm hệ điều hành (`Windows Temp`).
  - Nút chức năng riêng biệt **Dọn Dẹp Windows Event Logs** (`btnCleanEventLogs`): **Tích hợp hộp thoại xác nhận an toàn (Confirmation Dialog)** giúp quản trị viên chủ động tránh xóa nhầm nhật ký sự cố khi đang điều tra lỗi máy tính tính.

---

### 3. Quản Lý & Chẩn Đoán Driver (Driver Management Suite)
- **Quét & chẩn đoán phần cứng chuyên sâu:** Sử dụng cmdlet `Get-PnpDevice` truy vấn trực tiếp thuộc tính `ConfigManagerErrorCode`, nhanh chóng cô lập các thiết bị lỗi, xung đột hoặc thiếu driver. Kiểm tra mã thoát và báo cáo tình trạng rõ ràng.
- **Khơi thông hàng đợi Driver:** Giải phóng các gói driver bị treo trong tiến trình cập nhật ngầm của Windows Update qua COM Object `Microsoft.Update.AutoUpdate`.
- **Sao lưu Driver bên thứ ba:** Tự động trích xuất toàn bộ driver bên thứ ba hiện hành thông qua `Export-WindowsDriver` vào thư mục `C:\Backup_Drivers`, hỗ trợ cài lại Windows offline.
- **Dọn dẹp DriverStore an toàn từng gói:** Tích hợp `pnputil /enum-drivers` và `pnputil /delete-driver` để quét và loại bỏ triệt để các phiên bản gói OEM (`oemX.inf`) đã bị thay thế hoặc không còn liên kết phần cứng, bắt lỗi độc lập cho từng gói driver.

---

### 4. Công Nghệ Thực Thi Không Khóa Giao Diện (ProcessRunner)
- **Đọc luồng dữ liệu bất đồng bộ song song:** Lắng nghe đồng thời cả StandardOutput và StandardError qua các tác vụ bất đồng bộ, triệt tiêu 100% nguy cơ tắc nghẽn (deadlock) khi ứng dụng CLI ghi nhiều thông điệp ra stderr.
- **Tự động thích ứng bảng mã ký tự (Adaptive Stream Encoding):**
  - UTF-16LE cho `sfc.exe`.
  - UTF-8 cho `winget.exe`.
  - Console / OEM Encoding cho `dism.exe`, `netsh.exe`, `ipconfig.exe`, `pnputil.exe`.
- **Điều tiết hiển thị giao diện (Throttling):** Giới hạn tần suất cập nhật log (25ms), loại bỏ ký tự điều khiển ANSI, gộp dòng cập nhật tại chỗ (`\r`), và giới hạn bộ đệm tối đa 1500 dòng nhằm đảm bảo ứng dụng không bao giờ bị tràn bộ nhớ hay lag đơ giao diện.

---

## 🛠️ Quy Trình Đóng Gói & Phát Triển (Build Workflow)

Sau khi điều chỉnh cấu hình trong `config/apps.json`, mẫu giao diện `xaml/MainWindow.xaml`, hoặc các hàm xử lý trong `functions/`, tiến hành biên dịch dự án bằng lệnh:

```powershell
.\Compile.ps1
```

Quy trình biên dịch tự động hóa các bước:
1. Đọc và xác thực cấu trúc cú pháp của các mô-đun thành phần.
2. Nạp kho 114 ứng dụng JSON vào cấu trúc phân phối `$AppCatalog`.
3. Nhúng giao diện XML/WPF và liên kết toàn bộ script nghiệp vụ.
4. Xuất tệp tin thực thi độc lập `DuckUtil.ps1` theo định dạng **UTF-8 không chứa Byte Order Mark (BOM)** nhằm đảm bảo tính tương thích tuyệt đối khi chạy qua `iex`.
5. Tích hợp kiểm tra tính toàn vẹn trong GitHub Actions CI/CD (`git diff --exit-code DuckUtil.ps1`).

---

## 💻 Yêu Cầu Kỹ Thuật

| Thành phần | Yêu cầu tối thiểu | Khuyến nghị |
| :--- | :--- | :--- |
| **Hệ điều hành** | Windows 10 (Phiên bản 1809 trở lên, 64-bit) | Windows 11 (22H2 / 23H2 / 24H2) |
| **Môi trường PowerShell** | Windows PowerShell 5.1 | PowerShell 7.4+ LTS |
| **Trình quản lý gói** | Microsoft WinGet (App Installer) | WinGet v1.6+ |
| **Trình giả lập dòng lệnh** | Windows Console Host (conhost.exe) | Windows Terminal / Windows Terminal Preview |
| **Quyền thực thi** | Tài khoản quản trị viên cục bộ (Local Administrator) | UAC tự động kích hoạt |

---

## 📄 Bản Quyền & Giấy Phép

Dự án được phân phối dưới giấy phép nguồn mở **MIT License**. Bạn được tự do sử dụng, chỉnh sửa và tích hợp vào các hệ thống quản trị nội bộ của cá nhân và doanh nghiệp.