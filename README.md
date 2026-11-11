# 🦆 DuckUtil - Cyber Obsidian Suite
> **Next-Gen Windows Package Manager, System Maintenance & Driver Suite**  
> Lấy cảm hứng từ Chris Titus WinUtil, xây dựng 100% bằng kiến trúc module hiện đại với **PowerShell 7 / Windows PowerShell** và **Fluent WPF Cyber Dark Mode**.

---

## ⚡ Cài Đặt & Khởi Chạy Nhanh (1 Dòng Lệnh Duy Nhất)

Mở **PowerShell** (hoặc Windows Terminal) và dán dòng lệnh:

```powershell
irm is.gd/duckutil | iex
```

*(Tự động nâng quyền Administrator UAC nếu đang ở tài khoản thường, tự động quét nhận diện phiên bản phần mềm ngay khi mở).*

---

## 📂 Kiến Trúc Dự Án (Modular Architecture)

Tương tự như cấu trúc nguồn mở của Chris Titus WinUtil, DuckUtil được tách thành các module chuyên biệt để dễ dàng bảo trì, mở rộng và phát triển:

```text
app-driver/
├── config/
│   └── apps.json               # Kho 70+ ứng dụng (dễ dàng thêm/sửa app không cần biết code PowerShell)
├── xaml/
│   └── MainWindow.xaml         # Toàn bộ XAML giao diện WPF, custom scrollbar 8px Cyber Obsidian
├── functions/
│   ├── public/
│   │   └── Invoke-SystemRepairs.ps1  # Các module sửa lỗi Windows Update, DISM, SFC, Network...
│   └── private/
│       ├── ProcessRunner.ps1         # Bộ thực thi lệnh CLI stream log thời gian thực vào Terminal
│       └── SmartMatcher.ps1          # Thuật toán nhận diện phiên bản 3 lớp (Exact ID, Aliases, Clean Name)
├── scripts/
│   ├── start.ps1               # Khởi tạo quyền Admin tự động (Self-Elevation) & nạp thư viện WPF
│   └── main.ps1                # Bộ điều khiển sự kiện (Controller), sinh card 4 cột & ShowDialog
├── Compile.ps1                 # Script dịch tự động đóng gói toàn bộ dự án thành DuckUtil.ps1 duy nhất
├── .github/
│   └── workflows/
│       └── build.yml           # GitHub Actions tự động kiểm tra cú pháp và build trên CI/CD
├── DuckUtil.ps1                # Bản phát hành phân phối chính thức cho lệnh irm is.gd/duckutil | iex
└── README.md                   # Tài liệu hướng dẫn sử dụng và phát triển
```

---

## 🛠️ Cách Đóng Gói (Build Project)

Nếu bạn muốn chỉnh sửa giao diện hoặc thêm ứng dụng trong `config/apps.json`, chỉ cần chạy script đóng gói:

```powershell
.\Compile.ps1
```

Script sẽ tự động:
1. Đọc `config/apps.json`, `xaml/MainWindow.xaml`, `functions/` và `scripts/`.
2. Ghép nối thành file phân phối `DuckUtil.ps1` duy nhất.
3. Đảm bảo chuẩn mã hóa **UTF-8 không có BOM** (chống lỗi phân tích cú pháp khi chạy qua `iex`).

---

## 🌟 Tính Năng Nổi Bật

### 1. Ứng Dụng (Package Manager - Cyber Dark Mode 4 Cột)
- **Bố cục 4 cột rộng rãi**: Card nền obsidian `#10131B`, viền phát sáng, tích hợp Logo icon chính hãng cho từng ứng dụng.
- **Nhận diện màu phiên bản thông minh**:
  - ⚪ **Trắng**: Chưa cài đặt trên máy.
  - 🟢 **Xanh lá (`✓ Mới nhất`)**: Đã cài đặt và đang ở phiên bản mới nhất.
  - 🔴 **Đỏ (`⚠️ Có bản mới`)**: Đã cài đặt nhưng đã có bản cập nhật mới trên kho.
- **Thanh cuộn Minimalist 8px**: Thiết kế phẳng, không mũi tên, track trong suốt, con trượt dạng viên thuốc phát sáng Neon Cyan (`#38BDF8`) khi hover.
- **Thao tác hàng loạt**: Cài đặt chọn lọc, Gỡ bỏ an toàn, hoặc Nâng cấp toàn bộ máy tính chỉ bằng 1-Click (`winget upgrade --all`).

### 2. Gỡ Lỗi & Sửa Hệ Thống (System Repairs)
- **SFC Scan (`sfc /scannow`)**: Tự động sửa chữa các tệp hệ thống bị hỏng.
- **DISM RestoreHealth**: Khôi phục kho linh kiện Windows Image từ máy chủ Microsoft.
- **Reset Windows Update Engine**: Tự động dừng service, làm mới cache SoftwareDistribution & Catroot2, sửa triệt để lỗi kẹt tải driver và cập nhật Windows.
- **Sửa Lỗi Mạng**: Làm mới DNS (`ipconfig /flushdns`), khôi phục TCP/IP stack (`netsh int ip reset`).
- **Dọn Rác Hệ Thống**: Dọn dẹp User Temp, Windows Temp và làm sạch Windows Event Logs.

### 3. Quản Lý & Gỡ Lỗi Driver (Driver Suite)
- **Chẩn đoán phần cứng**: Quét toàn bộ thiết bị đang bị lỗi hoặc thiếu driver (`Get-PnpDevice`).
- **Gỡ kẹt cập nhật Driver**: Giải phóng hàng đợi cập nhật driver bị treo trong Windows Update.
- **Sao lưu toàn bộ Driver**: Xuất toàn bộ driver bên thứ ba của máy ra thư mục `C:\Backup_Drivers` để phục vụ cài lại Windows offline.
- **Dọn dẹp DriverStore**: Giải phóng hàng chục GB dung lượng từ các bản driver cũ không còn sử dụng.

---

## 💻 Yêu Cầu Hệ Thống
- **Hệ điều hành**: Windows 10 / Windows 11 (64-bit).
- **PowerShell**: Windows PowerShell 5.1 hoặc PowerShell 7.x trở lên.
- **WinGet**: Tích hợp sẵn trong Windows App Installer.
