# ==============================================================================
#                     DUCK UTIL - CYBER OBSIDIAN SUITE
#       Modular Windows Package Manager & System Maintenance Architecture
# ==============================================================================

# 1. TỰ ĐỘNG CHUYỂN SANG QUYỀN ADMINISTRATOR (SELF-ELEVATION)
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh.exe" } else { "powershell.exe" }
    try {
        if ([string]::IsNullOrWhiteSpace($PSCommandPath) -or -not (Test-Path -LiteralPath $PSCommandPath)) {
            Start-Process $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"Invoke-RestMethod -Uri 'https://is.gd/duckutil' | Invoke-Expression`"" -Verb RunAs -ErrorAction Stop
        } else {
            Start-Process $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop
        }
    } catch {
        Write-Host "`n[!] Bạn đã từ chối cấp quyền Administrator (UAC)." -ForegroundColor Yellow
        Write-Host "[*] DuckUtil cần quyền Administrator để thực hiện sửa lỗi hệ thống và quản lý Driver.`n" -ForegroundColor DarkGray
    }
    exit
}

# 2. NẠP THƯ VIỆN WPF & WINFORMS
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
