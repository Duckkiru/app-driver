# ── FUNCTION: CÁC TIỆN ÍCH SỬA LỖI HỆ THỐNG (SYSTEM REPAIRS) ──

function Reset-WindowsUpdateEngine {
    <#
    .SYNOPSIS
        Khởi tạo lại toàn bộ dịch vụ Windows Update và xóa cache bị lỗi/kẹt.
    #>
    Log-Text "[*] Đang dừng các dịch vụ Windows Update, BITS, DoSvc & TrustedInstaller..."
    $services = @("wuauserv", "bits", "cryptsvc", "dosvc", "trustedinstaller")
    foreach ($s in $services) {
        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
    }

    # Chờ tiến trình giải phóng hoàn toàn các handle tệp tin
    Start-Sleep -Milliseconds 1500

    Log-Text "[*] Đang làm mới bộ nhớ đệm SoftwareDistribution và Catroot2..."
    $sdPath = "C:\Windows\SoftwareDistribution"
    $sdRenamed = $true
    if (Test-Path -LiteralPath $sdPath) {
        $backupSD = "SoftwareDistribution.bak_$(Get-Random)"
        Rename-Item -LiteralPath $sdPath -NewName $backupSD -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $sdPath) {
            $sdRenamed = $false
            Log-Text "[⚠️] Không thể đổi tên SoftwareDistribution (tệp đang bị khóa bởi tiến trình khác)."
        }
    }

    $crPath = "C:\Windows\System32\catroot2"
    $crRenamed = $true
    if (Test-Path -LiteralPath $crPath) {
        $backupCR = "catroot2.bak_$(Get-Random)"
        Rename-Item -LiteralPath $crPath -NewName $backupCR -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $crPath) {
            $crRenamed = $false
            Log-Text "[⚠️] Không thể đổi tên catroot2 (tệp đang bị khóa)."
        }
    }

    Log-Text "[*] Khởi động lại các dịch vụ hệ thống..."
    Start-Service -Name "cryptsvc" -ErrorAction SilentlyContinue
    Start-Service -Name "bits" -ErrorAction SilentlyContinue
    Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    Start-Service -Name "dosvc" -ErrorAction SilentlyContinue

    if ($sdRenamed -and $crRenamed) {
        Log-Text "[✓] Đã khởi tạo lại dịch vụ Windows Update và xóa sạch cache thành công!"
    } else {
        Log-Text "[*] Đã đặt lại dịch vụ Windows Update (một số thư mục cache đang được hệ thống bảo vệ)."
    }
}

function Invoke-WindowsUpdateScan {
    <#
    .SYNOPSIS
        Kích hoạt quét tìm kiếm bản cập nhật Windows qua COM API chính thức và Windows Settings.
    #>
    Log-Text "[*] Đang gửi tín hiệu yêu cầu Windows tìm kiếm bản cập nhật mới..."
    try {
        $au = New-Object -ComObject Microsoft.Update.AutoUpdate
        $au.DetectNow()
        Log-Text "[✓] Đã kích hoạt Microsoft.Update.AutoUpdate.DetectNow() thành công."
    } catch {
        Log-Text "[*] COM AutoUpdate không phản hồi, mở trang cập nhật hệ thống..."
    }

    try {
        Start-Process "ms-settings:windowsupdate-action" -ErrorAction SilentlyContinue
    } catch {}
}

function Invoke-SystemFileCheck {
    <#
    .SYNOPSIS
        Chạy SFC Scan kiểm tra toàn vẹn file hệ thống.
    #>
    Log-Text "[*] Đang khởi chạy System File Checker (sfc /scannow)..."
    $code = Run-CliStream "sfc.exe" "/scannow"
    if ($code -eq 0) {
        Log-Text "[✓] SFC Scan hoàn tất: Toàn vẹn tệp hệ thống đạt chuẩn (ExitCode: 0)."
    } else {
        Log-Text "[!] SFC Scan phát hiện lỗi hoặc không thể sửa chữa toàn bộ tệp hệ thống (ExitCode: $code)."
    }
    return $code
}

function Invoke-DismRestoreHealth {
    <#
    .SYNOPSIS
        Khôi phục kho linh kiện Windows qua DISM RestoreHealth từ server Microsoft.
    #>
    Log-Text "[*] Đang khởi chạy DISM RestoreHealth khôi phục kho linh kiện hệ thống..."
    $code = Run-CliStream "dism.exe" "/Online /Cleanup-Image /RestoreHealth"
    if ($code -eq 0) {
        Log-Text "[✓] DISM RestoreHealth hoàn tất thành công (ExitCode: 0)."
    } else {
        Log-Text "[!] DISM RestoreHealth thất bại hoặc gặp sự cố (ExitCode: $code). Hãy kiểm tra kết nối mạng hoặc nguồn tệp hệ thống."
    }
    return $code
}

function Clear-DnsResolverCache {
    <#
    .SYNOPSIS
        Làm mới bộ nhớ đệm DNS.
    #>
    $code = Run-CliStream "ipconfig.exe" "/flushdns"
    if ($code -eq 0) {
        Log-Text "[✓] Làm mới bộ nhớ đệm DNS thành công (ExitCode: 0)."
    } else {
        Log-Text "[!] Làm mới bộ nhớ đệm DNS thất bại (ExitCode: $code)."
    }
    return $code
}

function Reset-NetworkInterfaceStack {
    <#
    .SYNOPSIS
        Khôi phục danh mục Winsock Catalog và TCP/IP Stack.
    #>
    $codeWinsock = Run-CliStream "netsh.exe" "winsock reset"
    $codeTcpIp = Run-CliStream "netsh.exe" "int ip reset"
    if ($codeWinsock -eq 0 -and $codeTcpIp -eq 0) {
        Log-Text "[✓] Đặt lại Winsock Catalog và TCP/IP Stack thành công (ExitCode: 0). Khuyên bạn nên khởi động lại máy."
    } else {
        Log-Text "[!] Đặt lại mạng gặp lỗi (Winsock ExitCode: $codeWinsock, TCP/IP ExitCode: $codeTcpIp)."
    }
    return ($codeWinsock -eq 0 -and $codeTcpIp -eq 0)
}

function Clear-SystemTempFiles {
    <#
    .SYNOPSIS
        Dọn dẹp tệp tạm thời trong thư mục User Temp và Windows Temp.
    #>
    $tempPaths = @($env:TEMP, "C:\Windows\Temp")
    foreach ($p in $tempPaths) {
        if (Test-Path -LiteralPath $p) {
            Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Clear-SystemEventLogs {
    <#
    .SYNOPSIS
        Xóa sạch toàn bộ nhật ký sự kiện Windows Event Logs.
    #>
    Log-Text "[*] Đang quét và dọn sạch nhật ký sự kiện Windows Event Logs..."
    Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName)
        } catch {}
    }
    Log-Text "[✓] Toàn bộ Windows Event Logs đã được làm sạch."
}
