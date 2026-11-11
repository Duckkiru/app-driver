# ── FUNCTION: CÁC TIỆN ÍCH SỬA LỖI HỆ THỐNG ──
function Reset-WindowsUpdateEngine {
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
