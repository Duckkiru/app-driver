# 🦆 DuckUtil - Cyber Obsidian Suite
> **Enterprise-Grade Windows Package Manager, System Maintenance & Driver Suite**  
> Giải pháp quản trị hệ thống toàn diện cho Windows, xây dựng trên nền tảng **PowerShell 7 / Windows PowerShell 5.1** kết hợp giao diện đồ họa **WPF Fluent Cyber Dark Mode**.

---

## ⚡ Khởi Chạy Nhanh (One-Liner Execution)

Mở **Windows Terminal** (hoặc PowerShell với quyền Administrator) và thực thi lệnh:

```powershell
irm is.gd/duckutil | iex
```

*Hoặc sử dụng liên kết kho mã nguồn trực tiếp từ GitHub:*

```powershell
irm https://raw.githubusercontent.com/Duckkiru/app-driver/main/DuckUtil.ps1 | iex
```

> **Ghi chú về phân quyền:** DuckUtil tích hợp cơ chế tự động nâng quyền Quản trị viên (UAC Self-Elevation). Khi khởi chạy từ môi trường người dùng tiêu chuẩn hoặc Windows Terminal, ứng dụng sẽ yêu cầu xác nhận UAC và duy trì phiên làm việc liền mạch trên Single-Threaded Apartment (`-Sta`).

---

## 🏛️ Kiến Trúc Hệ Thống (Modular Architecture)

DuckUtil áp dụng kiến trúc mô-đun hóa độc lập, phân tách rõ ràng giữa cấu hình dữ liệu, giao diện người dùng và các luồng xử lý nghiệp vụ:

```text
DuckUtil/
├── config/
│   └── apps.json               # Kho danh mục 70 ứng dụng (dễ dàng mở rộng, chuẩn hóa JSON Schema)
├── xaml/
│   └── MainWindow.xaml         # Giao diện WPF Fluent Cyber Dark Mode với thanh cuộn Minimalist 8px
├── functions/
│   ├── public/
│   │   ├── Invoke-DriverSuite.ps1    # Bộ công cụ chẩn đoán, xuất bản sao lưu và tối ưu hóa driver
│   │   └── Invoke-SystemRepairs.ps1  # Bộ công cụ phục hồi hệ thống, DISM, SFC, Windows Update & Network
│   └── private/
│       ├── ProcessRunner.ps1         # Trình thực thi tiến trình không đồng bộ, truyền trực tiếp log vào UI
│       └── SmartMatcher.ps1          # Thuật toán đối soát phiên bản 3 lớp (Exact ID, Aliases, Clean Name)
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
- **Giao diện lưới 4 cột tối ưu hóa:** Hiển thị 70 ứng dụng phân loại qua 10 danh mục chuyên biệt, sử dụng bảng màu Cyber Obsidian (`#10131B`), viền phân cách tinh tế, tích hợp biểu tượng chính hãng từ dịch vụ favicon độ nét cao.
- **Cơ chế nhận diện trạng thái phiên bản 3 màu:**
  - ⚪ **Trắng (`Chưa cài đặt`)**: Ứng dụng chưa hiện diện trên hệ thống máy trạm.
  - 🟢 **Xanh lục (`✓ Mới nhất`)**: Ứng dụng đã được cài đặt và đang vận hành ở phiên bản mới nhất.
  - 🔴 **Đỏ (`⚠️ Có bản mới`)**: Phát hiện phiên bản cũ hơn so with kho phân phối chính thức; hiển thị phiên bản khả dụng trên tooltip.
- **Thuật toán Smart Matcher chuẩn xác cao:**
  - *Lớp 1 - Khớp mã định danh chính xác (Exact WinGet ID)*: Tra cứu O(1) qua từ điển băm `Dictionary[string, object]`.
  - *Lớp 2 - Tra cứu bí danh mở rộng (Rich Aliases Dictionary)*: Hỗ trợ nhận diện các phần mềm nội địa và quốc tế (Brave, Zalo, Telegram, WinSCP, ProtonVPN, Windows Terminal...). Các bí danh được tinh chỉnh nghiêm ngặt để loại bỏ nguy cơ trùng lặp (false-positive).
  - *Lớp 3 - Chuẩn hóa tên ứng dụng (Normalized Name Heuristics)*: Tự động lược bỏ các hậu tố kỹ thuật (`Browser`, `Desktop`, `LTS`, `Client`) để nhận diện chính xác.
  - *Phân tích ranh giới cột theo dấu phân cách*: Tự động xác định tọa độ bảng từ dòng gạch ngang `^---+`, tương thích 100% với WinGet trên Windows tiếng Việt và đa ngôn ngữ.
- **Hỗ trợ toàn diện Windows Terminal:**
  - Tích hợp cả hai phiên bản độc lập: **Windows Terminal** (`Microsoft.WindowsTerminal`) và **Windows Terminal Preview** (`Microsoft.WindowsTerminal.Preview`).
  - Hệ thống bí danh nhận diện chặt chẽ: App Installer IDs (`9N0DX20HK701`, `9N8G5RFZ9XK3`), tên hiển thị cục bộ (`Bảng điều khiển Windows`, `Bản xem trước của Bảng điều khiển Windows`), và từ khóa chuẩn xác (`Terminal`, `Terminal Preview`).
- **Thao tác hàng loạt chuyên nghiệp:** Cài đặt danh sách đã chọn, gỡ cài đặt có kiểm soát theo mã ID phát hiện thực tế (`DetectedId`), hoặc kích hoạt nâng cấp toàn bộ hệ thống (`winget upgrade --all`) với thanh tiến trình trực quan.

### 2. Chẩn Đoán & Khắc Phục Lỗi Hệ Thống (System Diagnostic & Repair)
- **Kiểm tra tệp tin hệ thống (SFC Scan):** Thực thi `sfc /scannow` với bộ giải mã luồng Unicode (UTF-16LE) chống lỗi vỡ font tiếng Việt để phát hiện và khôi phục các tệp tin hệ điều hành bị lỗi.
- **Khôi phục ảnh hệ thống (DISM Health Restore):** Thực thi `dism /online /cleanup-image /restorehealth` kết nối trực tiếp đến Windows Update để sửa chữa kho thành phần bị hỏng.
- **Đặt lại tiến trình Windows Update:** Dừng an toàn toàn bộ các dịch vụ liên quan (`wuauserv`, `bits`, `cryptsvc`, `dosvc`, `trustedinstaller`), giải phóng bộ điều khiển tệp, làm mới cache `SoftwareDistribution` và `Catroot2`, giải quyết triệt để lỗi nghẽn tải bản vá và driver.
- **Khôi phục cấu hình mạng (Network Stack Reset):** Xóa bộ đệm phân giải tên miền (`ipconfig /flushdns`), đặt lại Winsock (`netsh winsock reset`) và khôi phục ngăn xếp TCP/IP (`netsh int ip reset`).
- **Dọn dẹp hệ thống chuyên sâu:**
  - Giải phóng bộ nhớ tạm người dùng (`User Temp`) và bộ nhớ đệm hệ điều hành (`Windows Temp`).
  - Nút chức năng riêng biệt **Dọn Dẹp Windows Event Logs** (`btnCleanEventLogs`): giải phóng nhật ký sự kiện hệ thống một cách chủ động và an toàn.

### 3. Quản Lý & Chẩn Đoán Driver (Driver Management Suite)
- **Quét & chẩn đoán phần cứng chuyên sâu:** Sử dụng cmdlet `Get-PnpDevice` truy vấn trực tiếp mã lỗi phần cứng `ConfigManagerErrorCode`, nhanh chóng cô lập các thiết bị lỗi, xung đột hoặc thiếu driver.
- **Khơi thông hàng đợi Driver:** Giải phóng các gói driver bị treo trong tiến trình cập nhật ngầm của Windows Update qua COM Object `Microsoft.Update.AutoUpdate`.
- **Sao lưu Driver bên thứ ba:** Tự động trích xuất toàn bộ driver bên thứ ba hiện hành thông qua `Export-WindowsDriver` vào thư mục `C:\Backup_Drivers`, hỗ trợ triển khai hệ thống ngoại tuyến.
- **Dọn dẹp DriverStore thực thụ:** Tích hợp `pnputil /enum-drivers` và `pnputil /delete-driver` để quét và loại bỏ triệt để các phiên bản gói OEM (`oemX.inf`) đã bị thay thế hoặc không còn sử dụng.

---

## 🛠️ Quy Trình Đóng Gói & Phát Triển (Build Workflow)

Sau khi điều chỉnh cấu hình trong `config/apps.json`, mẫu giao diện `xaml/MainWindow.xaml`, hoặc các hàm xử lý trong `functions/`, tiến hành biên dịch dự án bằng lệnh:

```powershell
.\Compile.ps1
```

Quy trình biên dịch tự động hóa các bước:
1. Đọc và xác thực cấu trúc cú pháp của các mô-đun thành phần.
2. Nạp kho 70 ứng dụng JSON vào cấu trúc phân phối `$AppCatalog`.
3. Nhúng giao diện XML/WPF và liên kết toàn bộ script nghiệp vụ.
4. Xuất tệp tin thực thi độc lập `DuckUtil.ps1` theo định dạng **UTF-8 không chứa Byte Order Mark (BOM)** nhằm đảm bảo tính tương thích tuyệt đối khi chạy qua `iex`.
5. Tích hợp kiểm tra đồng bộ trong GitHub Actions CI/CD (`git diff --exit-code DuckUtil.ps1`).

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

Dự án được phân phối dưới giấy phép nguồn mở **MIT License**. Bạn được tự do sử dụng, chỉnh sửa và tích hợp vào các hệ thống quản trị nội bộ của doanh nghiệp.