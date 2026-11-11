# ── FUNCTION: CÁC TIỆN ÍCH QUẢN LÝ & GỠ LỖI DRIVER ──

function Find-FaultyPnpDevices {
    <#
    .SYNOPSIS
        Quét và liệt kê tất cả các thiết bị phần cứng bị lỗi, thiếu driver hoặc chấm than vàng.
    #>
    return @(Get-PnpDevice | Where-Object { $_.Present -eq $true -and $_.Status -ne 'OK' })
}

function Invoke-PnpDeviceRescan {
    <#
    .SYNOPSIS
        Buộc Windows gửi tín hiệu quét lại toàn bộ phần cứng cắm trên máy.
    #>
    Run-CliStream "pnputil.exe" "/scan-devices"
}

function Invoke-DriverStoreCleanup {
    <#
    .SYNOPSIS
        Dọn dẹp và giải phóng các bản Driver cũ không còn dùng trong DriverStore.
    #>
    Run-CliStream "dism.exe" "/Online /Cleanup-Image /StartComponentCleanup /ResetBase"
}

function Export-SystemDriversBackup {
    <#
    .SYNOPSIS
        Sao lưu toàn bộ Driver của máy ra thư mục chỉ định.
    #>
    param([string]$Destination = "C:\Backup_Drivers")

    if (-not (Test-Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    try {
        Export-WindowsDriver -Online -Destination $Destination -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Run-CliStream "pnputil.exe" "/export-driver * `"$Destination`""
        return $true
    }
}
