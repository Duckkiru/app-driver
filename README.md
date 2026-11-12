# DuckUtil

Công cụ cài đặt phần mềm, sửa lỗi hệ thống và quản lý Driver cho Windows 10/11.

## Khởi Chạy (Run)

Mở PowerShell hoặc Windows Terminal với quyền Quản trị viên (Admin) và chạy lệnh:

```powershell
irm is.gd/duckutil | iex
```

Link dự phòng (GitHub Raw):

```powershell
irm https://raw.githubusercontent.com/Duckkiru/app-driver/main/DuckUtil.ps1 | iex
```

## Tính Năng

- **Quản lý ứng dụng (WinGet):** Cài đặt, gỡ bỏ và cập nhật hàng loạt 70+ phần mềm theo bố cục 4 cột. Tự động quét trạng thái: Chưa cài (Trắng), Đã cài bản mới nhất (Xanh lá), Có bản cập nhật (Đỏ gạch chân).
- **Sửa lỗi hệ thống (System Repair):** Quét và khôi phục tệp hệ thống (SFC, DISM), đặt lại Windows Update, khôi phục mạng (DNS, Winsock, TCP/IP) và dọn dẹp bộ nhớ tạm (Temp, Event Logs).
- **Quản lý Driver (Driver Suite):** Quét thiết bị lỗi PnP, sao lưu toàn bộ Driver bên thứ ba vào `C:\Backup_Drivers` và xóa các gói OEM cũ trong DriverStore.

## Cấu Trúc Thư Mục

```text
config/apps.json          Danh sách cấu hình 70+ ứng dụng
xaml/MainWindow.xaml      Giao diện WPF Dark Mode
functions/                Các module xử lý (SmartMatcher, ProcessRunner, Repair, Driver)
scripts/                  Điều phối khởi chạy (start.ps1) và sự kiện giao diện (main.ps1)
Compile.ps1               Đóng gói toàn bộ mã nguồn thành file DuckUtil.ps1
DuckUtil.ps1              File thực thi độc lập duy nhất
```

## Đóng Gói Từ Mã Nguồn (Build)

Sau khi thêm ứng dụng tại `config/apps.json` hoặc chỉnh sửa mã nguồn, chạy lệnh sau để cập nhật file `DuckUtil.ps1`:

```powershell
.\Compile.ps1
```

## Giấy Phép (License)

(Chưa có)
