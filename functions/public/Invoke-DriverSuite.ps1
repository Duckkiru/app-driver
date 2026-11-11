# ── FUNCTION: CÁC TIỆN ÍCH QUẢN LÝ & GỠ LỖI DRIVER ──

function Find-FaultyPnpDevices {
    <#
    .SYNOPSIS
        Quét và liệt kê tất cả các thiết bị phần cứng bị lỗi, thiếu driver hoặc chấm than vàng qua ConfigManagerErrorCode.
    #>
    try {
        return @(Get-PnpDevice -ErrorAction Stop | Where-Object {
            $_.Present -eq $true -and ($_.Status -ne 'OK' -or ($null -ne $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0))
        })
    } catch {
        Log-Text "[!] Lỗi khi quét danh sách PnpDevice: $($_.Exception.Message)"
        return @()
    }
}

function Invoke-PnpDeviceRescan {
    <#
    .SYNOPSIS
        Buộc Windows gửi tín hiệu quét lại toàn bộ phần cứng cắm trên máy.
    #>
    Run-CliStream "pnputil.exe" "/scan-devices"
}

function Invoke-PnpDriverStoreCleanup {
    <#
    .SYNOPSIS
        Quét và dọn dẹp các gói Driver OEM của bên thứ ba không còn được sử dụng trong DriverStore bằng pnputil.
    #>
    Log-Text "[*] Đang phân tích danh sách gói Driver OEM bên thứ ba (pnputil /enum-drivers)..."
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "pnputil.exe"
        $pinfo.Arguments = "/enum-drivers"
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($pinfo)
        $raw = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()

        # Tìm các Published Name: oemX.inf
        $matches = [System.Text.RegularExpressions.Regex]::Matches($raw, '(?i)(?:Published Name|Tên đã phát hành):\s*(oem\d+\.inf)')
        $oemList = @($matches | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } | Select-Object -Unique)

        if ($oemList.Count -eq 0) {
            Log-Text "[✓] Không tìm thấy gói driver OEM nào trong DriverStore."
            return
        }

        Log-Text "[*] Tìm thấy $($oemList.Count) gói driver OEM. Bắt đầu dọn dẹp an toàn (không xóa driver đang sử dụng)..."
        $deletedCount = 0
        foreach ($inf in $oemList) {
            # Chạy xóa an toàn không dùng /force để Windows tự bảo vệ các driver đang được phần cứng sử dụng
            $delPinfo = New-Object System.Diagnostics.ProcessStartInfo
            $delPinfo.FileName = "pnputil.exe"
            $delPinfo.Arguments = "/delete-driver $inf"
            $delPinfo.RedirectStandardOutput = $true
            $delPinfo.RedirectStandardError = $true
            $delPinfo.UseShellExecute = $false
            $delPinfo.CreateNoWindow = $true
            $delP = [System.Diagnostics.Process]::Start($delPinfo)
            $delOut = $delP.StandardOutput.ReadToEnd()
            $delP.WaitForExit()

            if ($delP.ExitCode -eq 0 -or $delOut -match 'deleted successfully|đã xóa thành công') {
                $deletedCount++
                Log-Text "   [✓ Đã dọn] $inf"
            }
            [System.Windows.Forms.Application]::DoEvents()
        }

        if ($deletedCount -gt 0) {
            Log-Text "[✓] Hoàn tất! Đã giải phóng $deletedCount gói driver OEM cũ không còn sử dụng."
        } else {
            Log-Text "[✓] Toàn bộ $($oemList.Count) gói driver OEM đều đang được các thiết bị phần cứng sử dụng an toàn."
        }
    } catch {
        Log-Text "[!] Lỗi khi dọn dẹp DriverStore: $($_.Exception.Message)"
    }
}

function Invoke-DriverStoreCleanup {
    <#
    .SYNOPSIS
        Dọn dẹp và giải phóng kho linh kiện Windows qua DISM Component Cleanup.
    #>
    Run-CliStream "dism.exe" "/Online /Cleanup-Image /StartComponentCleanup /ResetBase"
}

function Export-SystemDriversBackup {
    <#
    .SYNOPSIS
        Sao lưu toàn bộ Driver của máy ra thư mục chỉ định.
    #>
    param([string]$Destination = "C:\Backup_Drivers")

    if (-not (Test-Path -LiteralPath $Destination)) {
        try {
            New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop | Out-Null
        } catch {
            Log-Text "[!] Không thể tạo thư mục sao lưu '$Destination': $($_.Exception.Message)"
            return $false
        }
    }

    try {
        Export-WindowsDriver -Online -Destination $Destination -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Log-Text "[*] Export-WindowsDriver không khả dụng hoặc bị từ chối, chuyển sang pnputil.exe..."
        $exitCode = Run-CliStream "pnputil.exe" "/export-driver * `"$Destination`""
        return ($exitCode -eq 0)
    }
}
