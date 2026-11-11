# 🦆 DuckUtil - Windows Package Manager & System Maintenance Suite

Công cụ tối ưu hóa, cài đặt phần mềm hàng loạt và quản lý / gỡ lỗi Driver chuyên nghiệp cho Windows 10 & Windows 11.
Lấy cảm hứng từ Chris Titus WinUtil, xây dựng 100% bằng PowerShell và Fluent WPF UI.

---

## ⚡ Cài Đặt & Khởi Chạy Nhanh (1 Dòng Lệnh Duy Nhất)

Mở **PowerShell (Run as Administrator)** và dán dòng lệnh sau:

```powershell
irm is.gd/duckutil | iex
```

*(Hoặc link gốc: `irm https://raw.githubusercontent.com/Duckkiru/app-driver/main/DuckUtil.ps1 | iex`)*

---

## 🌟 Tính Năng Nổi Bật

### 1. 📦 Ứng Dụng (Package Manager)
- Lưới Card Grid đa cột chuẩn Fluent Dark Mode, hiển thị trực quan toàn bộ danh mục ứng dụng cùng lúc.
- Phân loại thuần túy 10 danh mục: Trình Duyệt, Liên Lạc, Phát Triển & Dev, Tiện Ích, Đa Phương Tiện, Văn Phòng, Game, Lưu Trữ, Bảo Mật, Thư Viện Cốt Lõi.
- Tìm kiếm tức thì (Live Search Filter).
- **Get Installed**: Tự động quét và đánh dấu `[✓]` các phần mềm đã có sẵn trên máy.
- **Install Selected / Uninstall Selected**: Cài hoặc gỡ cài đặt hàng loạt ngầm (Silent Mode) từ nguồn chính thức của nhà phát triển.
- **Upgrade All**: Nâng cấp toàn bộ phần mềm có trên máy tính lên bản mới nhất chỉ với 1 click (`winget upgrade --all`).

### 2. 🔧 Gỡ Lỗi & Sửa Hệ Thống (System Repairs)
- **SFC Scan (`sfc /scannow`)**: Tự động quét và sửa lỗi file hệ thống Windows.
- **DISM RestoreHealth**: Khắc phục và phục hồi kho linh kiện Windows từ server gốc.
- **Reset Windows Update Cache**: Xóa cache SoftwareDistribution & Catroot2, khắc phục lỗi kẹt tải 0%, mã lỗi 0x80070002...
- **Sửa Lỗi Mạng**: Flush DNS, Reset Winsock, Reset TCP/IP Stack.
- **Bảo Trì**: Dọn sạch rác Temp, khởi động lại Windows Explorer khi đơ Taskbar.

### 3. 🚗 Quản Lý & Gỡ Lỗi Driver (Driver Suite)
- **Quét Driver Lỗi**: Phát hiện thiết bị chấm than vàng, thiếu driver hoặc driver bị crash.
- **Gỡ Lỗi Kẹt Cập Nhật Driver**: Xóa hàng đợi và buộc Windows quét lại phần cứng (`pnputil /scan-devices`).
- **Sao Lưu Toàn Bộ Driver**: Xuất toàn bộ Driver bên thứ ba ra thư mục `C:\Backup_Drivers` bằng `Export-WindowsDriver`.
- **Dọn Dẹp Driver Cũ**: Giải phóng hàng chục GB dung lượng trong DriverStore.

---

## 🛠️ Yêu Cầu Hệ Thống
- Windows 10 / Windows 11
- Quyền Administrator
- WinGet (Tích hợp sẵn trong App Installer của Microsoft)
