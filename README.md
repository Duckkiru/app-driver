# App-Driver — Windows Software, Uninstaller & Optimizer Suite

Công cụ quản lý phần mềm, gỡ cài đặt sâu, tối ưu hệ thống và kiểm soát khởi động cho **Windows 10 / Windows 11**, xây dựng theo kiến trúc lai **PowerShell + C# Win32 P/Invoke + WPF** với khả năng biên dịch 1 tệp duy nhất chuẩn 7-bit ASCII tương thích cả **Windows PowerShell 5.1** và **PowerShell 7+**.

---

## Khởi chạy nhanh

Mở **Windows Terminal** (hoặc PowerShell với quyền Administrator) và chạy:

```powershell
irm is.gd/appdriver | iex
```

*Hoặc chạy trực tiếp từ kho mã nguồn GitHub:*

```powershell
irm https://raw.githubusercontent.com/Duckkiru/app-driver/main/App-Driver.ps1 | iex
```

---

## Tính năng chính

- **Kho Ứng dụng (Catalog):** Hơn 320 ứng dụng phổ biến chia theo danh mục, quét trạng thái cài đặt & so sánh phiên bản ngữ nghĩa qua `AppCatalogEngine` (C#) + WinGet.
- **Gỡ cài đặt sâu (Deep Uninstaller):** Quét sạch tệp tồn dư, Registry, Service và khóa nền bằng `DeepUninstallerEngine` kết hợp lá chắn 4 lớp bảo vệ thư mục hệ thống Windows.
- **Tối ưu hệ thống (Optimizer):** Nhận diện phần cứng trực tiếp qua Win32 IOCTL (NVMe / SSD / HDD / Laptop / Desktop), đi kèm **OptimizerGuard** sao lưu snapshot Registry & Service trước khi áp dụng để hoàn tác chính xác trạng thái gốc.
- **Quản lý Khởi chạy (Startup Manager):** Quét toàn diện Registry Run/RunOnce/Policies, Startup Folder, Microsoft Store MSIX, Task Scheduler và Third-Party Services; dọn mục lỗi/khóa rác `StartupApproved` có sao lưu **StartupGuard**; render danh sách bằng C# mượt không khựng.

---

## Cấu trúc mã nguồn

```text
├── App-Driver.ps1            # Bản phát hành đơn tệp 7-bit ASCII (biên dịch bởi Compile.ps1)
├── Compile.ps1               # Trình đóng gói AST 7-bit ASCII + kiểm tra cú pháp
├── csharp/                   # 6 engine C# hiệu năng cao (biên dịch & cache DLL theo runtime)
│   ├── SmoothScrollController.cs
│   ├── AppCatalogEngine.cs
│   ├── DeepUninstallerEngine.cs
│   ├── WindowsOptimizerEngine.cs
│   ├── StartupManagerEngine.cs
│   └── ResourceCleanerEngine.cs
├── scripts/                  # Bootstrap (start.ps1) và tầng điều phối giao diện (main.ps1)
├── functions/                # Nghiệp vụ PowerShell (private / public)
├── config/                   # Danh mục ứng dụng (apps.json) và tinh chỉnh (tweaks.json)
├── xaml/                     # Giao diện WPF (MainWindow.xaml)
└── tests/                    # Bộ kiểm thử tự động lõi C# & PowerShell (chạy trên CI)
```

---

## Lưu trữ cục bộ & Sao lưu

- **Cache DLL biên dịch:** `%LOCALAPPDATA%\DuckUtil\Cache`
- **Phiên chạy tạm an toàn (user-private):** `%LOCALAPPDATA%\AppDriver\Session`
- **Sao lưu OptimizerGuard / StartupGuard:** `%LOCALAPPDATA%\AppDriver` (có thể khôi phục trực tiếp trong ứng dụng)

---

## Tự biên dịch & Kiểm thử

```powershell
# Biên dịch lại App-Driver.ps1 từ mã nguồn
.\Compile.ps1

# Chạy bộ kiểm thử lõi (PowerShell 7 & Windows PowerShell 5.1)
pwsh -NoProfile -STA -File .\tests\Verify-CoreEngines.ps1
powershell -NoProfile -STA -File .\tests\Verify-CoreEngines.ps1
```

**Yêu cầu hệ thống:** Windows 10 / Windows 11 (x64), PowerShell 5.1 hoặc PowerShell 7+.
