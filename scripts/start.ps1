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
