function Find-FaultyPnpDevices {
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
    $code = Run-CliStream "pnputil.exe" "/scan-devices"
    if ($code -eq 0) {
        Log-Text "[OK] Quét lại thiết bị phần cứng PnP thành công (ExitCode: 0)."
    } else {
        Log-Text "[!] Quét thiết bị phần cứng PnP thất bại hoặc gặp lỗi (ExitCode: $code)."
    }
    return $code
}

function Invoke-PnpDriverStoreCleanup {
    Log-Text "[*] Đang phân tích danh sách gói Driver OEM bên thứ ba (pnputil /enum-drivers)..."
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "pnputil.exe"
        $pinfo.Arguments = "/enum-drivers"
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($pinfo)
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()
        $raw = $outTask.Result

        $matches = [System.Text.RegularExpressions.Regex]::Matches($raw, '(?i)(?:Published Name|Tên đã phát hành):\s*(oem\d+\.inf)')
        $oemList = @($matches | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } | Select-Object -Unique)

        if ($oemList.Count -eq 0) {
            Log-Text "[OK] Không tìm thấy gói driver OEM nào trong DriverStore."
            return
        }

        Log-Text "[*] Tìm thấy $($oemList.Count) gói driver OEM. Bắt đầu dọn dẹp an toàn (không xóa driver đang sử dụng)..."
        $deletedCount = 0
        $inUseCount = 0
        $errorCount = 0

        foreach ($inf in $oemList) {
            try {
                $delPinfo = New-Object System.Diagnostics.ProcessStartInfo
                $delPinfo.FileName = "pnputil.exe"
                $delPinfo.Arguments = "/delete-driver $inf"
                $delPinfo.RedirectStandardOutput = $true
                $delPinfo.RedirectStandardError = $true
                $delPinfo.UseShellExecute = $false
                $delPinfo.CreateNoWindow = $true
                $delP = [System.Diagnostics.Process]::Start($delPinfo)

                $delOutTask = $delP.StandardOutput.ReadToEndAsync()
                $delErrTask = $delP.StandardError.ReadToEndAsync()
                $delP.WaitForExit()

                $delOut = $delOutTask.Result
                $delErr = $delErrTask.Result
                $combined = ($delOut + "`n" + $delErr).Trim()

                if ($delP.ExitCode -eq 0 -or $combined -match 'deleted successfully|đã xóa thành công') {
                    $deletedCount++
                    Log-Text "   [OK - Đã dọn] $inf"
                } elseif ($combined -match 'installed using the specified INF|đang được sử dụng|in use|bị từ chối') {
                    $inUseCount++
                } else {
                    $errorCount++
                    $errDetail = ($combined -split "`r?`n" | Where-Object { $_ -match 'failed|lỗi|error' } | Select-Object -First 1)
                    if (-not $errDetail) { $errDetail = "ExitCode $($delP.ExitCode)" }
                    Log-Text "   [WARN - Lỗi gói $inf] $errDetail"
                }
            } catch {
                $errorCount++
                Log-Text "   [!] Lỗi ngoại lệ khi xử lý ${inf}: $($_.Exception.Message)"
            }
            [System.Windows.Forms.Application]::DoEvents()
        }

        if ($deletedCount -gt 0) {
            Log-Text "[OK] Hoàn tất! Đã giải phóng $deletedCount gói driver OEM cũ không còn sử dụng ($inUseCount gói đang được phần cứng sử dụng an toàn)."
        } else {
            Log-Text "[OK] Toàn bộ $($oemList.Count) gói driver OEM đều đang được các thiết bị phần cứng sử dụng an toàn."
        }
        if ($errorCount -gt 0) {
            Log-Text "[!] Có $errorCount gói driver gặp lỗi trong quá trình xử lý."
        }
    } catch {
        Log-Text "[!] Lỗi khi dọn dẹp DriverStore: $($_.Exception.Message)"
    }
}

function Invoke-DismComponentCleanup {
    Log-Text "[WARN] CẢNH BÁO: Tùy chọn /ResetBase sẽ xóa vĩnh viễn các bản cập nhật cũ đã bị thay thế trong WinSxS."
    Log-Text "[*] Sau khi hoàn tất thao tác này, bạn SẼ KHÔNG THỂ gỡ cài đặt (rollback) các bản Windows Update hiện tại."
    Log-Text "[*] Đang tiến hành dọn dẹp và nén kho linh kiện WinSxS qua DISM..."
    $code = Run-CliStream "dism.exe" "/Online /Cleanup-Image /StartComponentCleanup /ResetBase"
    if ($code -eq 0) {
        Log-Text "[OK] Dọn dẹp kho linh kiện WinSxS hoàn tất thành công (ExitCode: 0)."
    } else {
        Log-Text "[!] Dọn dẹp kho linh kiện WinSxS thất bại hoặc bị gián đoạn (ExitCode: $code)."
    }
    return $code
}

function Export-SystemDriversBackup {
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
        Log-Text "[OK] Sao lưu toàn bộ driver thành công qua Export-WindowsDriver."
        return $true
    } catch {
        Log-Text "[*] Export-WindowsDriver không khả dụng hoặc bị từ chối, chuyển sang pnputil.exe..."
        $exitCode = Run-CliStream "pnputil.exe" "/export-driver * `"$Destination`""
        if ($exitCode -eq 0) {
            Log-Text "[OK] Sao lưu toàn bộ driver thành công qua pnputil.exe (ExitCode: 0)."
            return $true
        } else {
            Log-Text "[!] Sao lưu driver qua pnputil.exe thất bại (ExitCode: $exitCode)."
            return $false
        }
    }
}
