# ── KHỞI TẠO CÁC CONTROL TỪ XAML ──
$reader = New-Object System.Xml.XmlNodeReader $XAML
$window = [Windows.Markup.XamlReader]::Load($reader)

# Các Control chính
$MainTabControl   = $window.FindName("MainTabControl")
$txtStatus        = $window.FindName("txtStatus")
$progressBar      = $window.FindName("progressBar")
$txtLog           = $window.FindName("txtLog")
$txtSearch        = $window.FindName("txtSearch")
$txtSelectionCount = $window.FindName("txtSelectionCount")
$cardsContainer   = $window.FindName("CardsContainer")

# Hàm an toàn gắn sự kiện Click cho nút
function Register-Click {
    param([string]$ButtonName, [scriptblock]$Action)
    $btn = $window.FindName($ButtonName)
    if ($btn) {
        $btn.Add_Click($Action)
    } else {
        Write-Warning "Không tìm thấy nút trong XAML: $ButtonName"
    }
}

# ── LOGIC ĐIỀU HƯỚNG TAB CHÍNH ──
$navBtnApps    = $window.FindName("navBtnApps")
$navBtnRepair  = $window.FindName("navBtnRepair")
$navBtnDrivers = $window.FindName("navBtnDrivers")

function Set-ActiveTab {
    param([int]$index, $activeBtn)
    if ($MainTabControl) {
        $MainTabControl.SelectedIndex = $index
    }

    $buttons = @($navBtnApps, $navBtnRepair, $navBtnDrivers)
    foreach ($btn in $buttons) {
        if ($btn) {
            $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
            $btn.BorderBrush = [System.Windows.Media.Brushes]::Transparent
        }
    }

    if ($activeBtn) {
        $activeBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
        $activeBtn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
    }
}

Register-Click "navBtnApps"    { Set-ActiveTab 0 $navBtnApps }
Register-Click "navBtnRepair"  { Set-ActiveTab 1 $navBtnRepair }
Register-Click "navBtnDrivers" { Set-ActiveTab 2 $navBtnDrivers }

# ── SINH CÁC CARD ỨNG DỤNG BỐ CỤC 4 CỘT RỘNG RÃI ──
$allCheckBoxes = @()
$allItemBorders = @()
$categories = $AppCatalog | Select-Object -ExpandProperty Category -Unique

function Update-SelectionCount {
    $selectedCount = @($allCheckBoxes | Where-Object { $_.IsChecked }).Count
    if ($txtSelectionCount) {
        $txtSelectionCount.Text = "$selectedCount app được chọn"
    }
}

foreach ($cat in $categories) {
    $cardBorder = New-Object System.Windows.Controls.Border
    $cardBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10131B")
    $cardBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1C2333")
    $cardBorder.BorderThickness = New-Object System.Windows.Thickness(1)
    $cardBorder.CornerRadius = New-Object System.Windows.CornerRadius(10)
    $cardBorder.Margin = New-Object System.Windows.Thickness(5)
    $cardBorder.Padding = New-Object System.Windows.Thickness(12, 10, 12, 12)

    $cardStack = New-Object System.Windows.Controls.StackPanel
    $appsInCat = @($AppCatalog | Where-Object { $_.Category -eq $cat })

    # Header Card
    $headerGrid = New-Object System.Windows.Controls.Grid
    $headerGrid.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)

    $headerText = New-Object System.Windows.Controls.TextBlock
    $headerText.Text = "$cat ($($appsInCat.Count))"
    $headerText.FontSize = 12.5
    $headerText.FontWeight = [System.Windows.FontWeights]::Bold
    $headerText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
    $headerGrid.Children.Add($headerText) | Out-Null

    $separator = New-Object System.Windows.Controls.Border
    $separator.Height = 1
    $separator.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E2638")
    $separator.Margin = New-Object System.Windows.Thickness(0, 2, 0, 6)

    $cardStack.Children.Add($headerGrid) | Out-Null
    $cardStack.Children.Add($separator) | Out-Null

    # Từng dòng App: Logo + CheckBox + Tên
    foreach ($app in $appsInCat) {
        $rowBorder = New-Object System.Windows.Controls.Border
        $rowBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $rowBorder.Padding = New-Object System.Windows.Thickness(6, 4, 6, 4)
        $rowBorder.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
        $rowBorder.Background = [System.Windows.Media.Brushes]::Transparent
        $rowBorder.Cursor = [System.Windows.Input.Cursors]::Hand
        $rowBorder.Tag = @{ App = $app; Status = "NONE" }

        $rowGrid = New-Object System.Windows.Controls.Grid
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = [System.Windows.GridLength]::Auto
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = [System.Windows.GridLength]::Auto
        $col3 = New-Object System.Windows.Controls.ColumnDefinition; $col3.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $rowGrid.ColumnDefinitions.Add($col1) | Out-Null
        $rowGrid.ColumnDefinitions.Add($col2) | Out-Null
        $rowGrid.ColumnDefinitions.Add($col3) | Out-Null

        # 1. CheckBox
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $cb.Tag = $app
        $cb.Add_Checked({ Update-SelectionCount })
        $cb.Add_Unchecked({ Update-SelectionCount })
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $rowGrid.Children.Add($cb) | Out-Null
        $allCheckBoxes += $cb

        # 2. Logo Icon chính hãng
        $img = New-Object System.Windows.Controls.Image
        $img.Width = 16; $img.Height = 16
        $img.Margin = New-Object System.Windows.Thickness(7, 0, 8, 0)
        $img.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        try {
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit()
            $bmp.UriSource = New-Object System.Uri("https://www.google.com/s2/favicons?domain=$($app.Domain)&sz=32")
            $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.EndInit()
            $img.Source = $bmp
        } catch {}
        [System.Windows.Controls.Grid]::SetColumn($img, 1)
        $rowGrid.Children.Add($img) | Out-Null

        # 3. Tên ứng dụng
        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $app.Name
        $nameText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
        $nameText.FontSize = 12
        $nameText.FontWeight = [System.Windows.FontWeights]::SemiBold
        $nameText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $nameText.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $nameText.ToolTip = "$($app.Name)`nID: $($app.ID)`n$($app.Desc)"
        [System.Windows.Controls.Grid]::SetColumn($nameText, 2)
        $rowGrid.Children.Add($nameText) | Out-Null

        # Chạm chọn toàn dòng
        $rowBorder.Add_MouseDown({
            $cb.IsChecked = -not $cb.IsChecked
        })

        # Hover phát sáng & giữ màu trạng thái khi rời chuột
        $rowBorder.Add_MouseEnter({
            if ($rowBorder.Tag.Status -eq "NONE") {
                $rowBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1C2333")
            }
        })
        $rowBorder.Add_MouseLeave({
            if ($rowBorder.Tag.Status -eq "LATEST") {
                $rowBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0D2818")
            } elseif ($rowBorder.Tag.Status -eq "OUTDATED") {
                $rowBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2A1215")
            } else {
                $rowBorder.Background = [System.Windows.Media.Brushes]::Transparent
            }
        })

        $rowBorder.Child = $rowGrid
        $cardStack.Children.Add($rowBorder) | Out-Null
        $allItemBorders += $rowBorder
    }

    $cardBorder.Child = $cardStack
    if ($cardsContainer) {
        $cardsContainer.Children.Add($cardBorder) | Out-Null
    }
}

# ── LOGIC TÌM KIẾM & BỘ LỌC ──
if ($txtSearch) {
    $txtSearch.Add_TextChanged({
        $keyword = $txtSearch.Text.Trim().ToLower()
        foreach ($row in $allItemBorders) {
            $app = $row.Tag.App
            $matched = [string]::IsNullOrEmpty($keyword) -or ($app.Name.ToLower().Contains($keyword)) -or ($app.ID.ToLower().Contains($keyword))
            $row.Visibility = if ($matched) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        }
    })
}

# ── CÁC HÀNH ĐỘNG CÀI ĐẶT / GỠ / NÂNG CẤP APP ──
Register-Click "btnScanInstalled" { Scan-And-ColorizeApps }

Register-Click "btnInstall" {
    $selected = @($allCheckBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($selected.Count -eq 0) {
        Log-Text "[!] Bạn chưa tick chọn ứng dụng nào để cài đặt!"
        return
    }

    $total = $selected.Count
    $idx = 0
    Log-Text "=========================================================="
    Log-Text "🚀 BẮT ĐẦU CÀI ĐẶT $total ỨNG DỤNG ĐÃ ĐÁNH DẤU"
    Log-Text "=========================================================="

    foreach ($app in $selected) {
        $idx++
        if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }
        if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang cài đặt: $($app.Name)..." }
        Log-Text "[$idx/$total] Đang cài: $($app.Name) (ID: $($app.ID))..."

        $code = Run-CliStream "winget" "install --id $($app.ID) --exact --silent --accept-package-agreements --accept-source-agreements"
        if ($code -eq 0) {
            Log-Text "   [✓ HOÀN THÀNH] $($app.Name)"
        } else {
            Log-Text "   [❌ LỖI] $($app.Name) (Exit Code: $code)"
        }
    }
    if ($txtStatus) { $txtStatus.Text = "Cài đặt hoàn tất!" }
    if ($progressBar) { $progressBar.Value = 100 }
    Scan-And-ColorizeApps
}

Register-Click "btnUninstall" {
    $selected = @($allCheckBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($selected.Count -eq 0) {
        Log-Text "[!] Bạn chưa chọn ứng dụng nào để gỡ cài đặt!"
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Bạn có chắc chắn muốn gỡ bỏ $($selected.Count) ứng dụng đã chọn?",
        "Xác nhận gỡ cài đặt",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $total = $selected.Count
    $idx = 0
    Log-Text "=========================================================="
    Log-Text "🗑️ BẮT ĐẦU GỠ CÀI ĐẶT $total ỨNG DỤNG ĐÃ CHỌN"
    Log-Text "=========================================================="

    foreach ($app in $selected) {
        $idx++
        if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }
        if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang gỡ bỏ: $($app.Name)..." }
        Log-Text "[$idx/$total] Đang gỡ: $($app.Name) (ID: $($app.ID))..."

        $code = Run-CliStream "winget" "uninstall --id $($app.ID) --silent"
        if ($code -eq 0) {
            Log-Text "   [✓ ĐÃ GỠ THÀNH CÔNG] $($app.Name)"
        } else {
            Log-Text "   [❌ LỖI GỠ] $($app.Name) (Exit Code: $code)"
        }
    }
    if ($txtStatus) { $txtStatus.Text = "Gỡ cài đặt hoàn tất!" }
    if ($progressBar) { $progressBar.Value = 100 }
    Scan-And-ColorizeApps
}

Register-Click "btnUpgradeAll" {
    Log-Text "=========================================================="
    Log-Text "⚡ BẮT ĐẦU NÂNG CẤP TOÀN BỘ PHẦN MỀM TRÊN MÁY"
    Log-Text "=========================================================="
    if ($txtStatus) { $txtStatus.Text = "Đang nâng cấp tất cả ứng dụng..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }

    Run-CliStream "winget" "upgrade --all --silent --accept-package-agreements --accept-source-agreements"

    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "Nâng cấp hoàn tất!" }
    Log-Text "[✓] Toàn bộ ứng dụng đã được nâng cấp lên bản mới nhất."
    Scan-And-ColorizeApps
}

Register-Click "btnSelectAll" {
    foreach ($cb in $allCheckBoxes) { $cb.IsChecked = $true }
    Update-SelectionCount
}

Register-Click "btnDeselectAll" {
    foreach ($cb in $allCheckBoxes) { $cb.IsChecked = $false }
    Update-SelectionCount
}

Register-Click "btnClearLog" {
    if ($txtLog) { $txtLog.Clear() }
}

# ── LOGIC MODULE SỬA LỖI HỆ THỐNG (SYSTEM REPAIRS) ──
Register-Click "btnSfcScan" {
    Log-Text "[*] Đang bắt đầu quét kiểm tra tính toàn vẹn hệ thống (sfc /scannow)..."
    if ($txtStatus) { $txtStatus.Text = "Đang chạy SFC Scan..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    Invoke-SystemFileCheck
    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "Quét SFC hoàn tất" }
    Log-Text "[✓] Quá trình SFC đã kết thúc."
}

Register-Click "btnDismRestore" {
    Log-Text "[*] Đang khôi phục kho ảnh hệ thống Windows qua DISM RestoreHealth..."
    if ($txtStatus) { $txtStatus.Text = "Đang chạy DISM RestoreHealth..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    Invoke-DismRestoreHealth
    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "DISM hoàn tất" }
    Log-Text "[✓] DISM RestoreHealth hoàn thành xuất sắc."
}

Register-Click "btnDismCleanup" {
    Log-Text "[*] Đang dọn dẹp kho linh kiện hệ thống (DISM Component Cleanup)..."
    if ($txtStatus) { $txtStatus.Text = "Đang dọn kho linh kiện..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    Invoke-DriverStoreCleanup
    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "Dọn kho linh kiện hoàn tất" }
    Log-Text "[✓] Đã giải phóng dung lượng kho linh kiện."
}

Register-Click "btnFixWindowsUpdate" {
    Log-Text "[*] Bắt đầu khởi tạo và xóa sạch cache lỗi Windows Update..."
    if ($txtStatus) { $txtStatus.Text = "Đang sửa lỗi Windows Update..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    Reset-WindowsUpdateEngine
    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "Đã đặt lại Windows Update" }
}

Register-Click "btnRestartUpdateServices" {
    Log-Text "[*] Đang khởi động lại dịch vụ Windows Update & BITS..."
    Restart-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
    Restart-Service -Name "bits" -Force -ErrorAction SilentlyContinue
    Log-Text "[✓] Đã khởi động lại dịch vụ cập nhật."
}

Register-Click "btnTriggerScanUpdate" {
    Log-Text "[*] Đang gửi tín hiệu yêu cầu Windows tìm kiếm bản cập nhật mới..."
    Start-Process "usoclient" -ArgumentList "StartInteractiveScan" -NoNewWindow
    Log-Text "[✓] Đã kích hoạt USOClient quét cập nhật."
}

Register-Click "btnFlushDnsWinsock" {
    Log-Text "[*] Đang xóa sạch cache DNS và reset Winsock Catalog..."
    Clear-DnsResolverCache
    Run-CliStream "netsh.exe" "winsock reset"
    Log-Text "[✓] Đã làm mới mạng và DNS cache."
}

Register-Click "btnResetTcpIp" {
    Log-Text "[*] Đang đặt lại toàn bộ ngăn xếp giao thức mạng TCP/IP..."
    Reset-NetworkInterfaceStack
    Log-Text "[✓] Đã reset TCP/IP Stack. Khuyên bạn nên khởi động lại máy."
}

Register-Click "btnClearTemp" {
    Log-Text "[*] Đang dọn dẹp các tệp tạm thời trong User Temp và Windows Temp..."
    if ($txtStatus) { $txtStatus.Text = "Đang dọn tệp rác Temp..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    Clear-SystemTempFiles
    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "Dọn tệp tạm hoàn tất" }
    Log-Text "[✓] Dọn dẹp bộ nhớ tạm thành công!"
}

Register-Click "btnRestartExplorer" {
    Log-Text "[*] Đang khởi động lại tiến trình Windows Explorer (explorer.exe)..."
    Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Start-Process "explorer.exe"
    Log-Text "[✓] Đã nạp lại Windows Explorer thành công."
}

# ── LOGIC MODULE QUẢN LÝ & GỠ LỖI DRIVER ──
Register-Click "btnScanFaultyDrivers" {
    Log-Text "=========================================================="
    Log-Text "🔍 ĐANG QUÉT TOÀN BỘ THIẾT BỊ PHẦN CỨNG & DRIVER BỊ LỖI..."
    Log-Text "=========================================================="
    if ($txtStatus) { $txtStatus.Text = "Đang quét thiết bị lỗi..." }

    $faulty = Find-FaultyPnpDevices

    if ($faulty.Count -eq 0) {
        Log-Text "[✓] Tuyệt vời! Không phát hiện thiết bị nào bị lỗi hoặc thiếu driver trên máy bạn."
        if ($txtStatus) { $txtStatus.Text = "Tất cả Driver đều hoạt động tốt" }
    } else {
        Log-Text "[⚠️] PHÁT HIỆN $($faulty.Count) THIẾT BỊ ĐANG BỊ LỖI / THIẾU DRIVER:"
        foreach ($d in $faulty) {
            Log-Text "   • Tên thiết bị: $($d.FriendlyName)"
            Log-Text "     Mã phần cứng: $($d.InstanceId)"
            Log-Text "     Trạng thái: $($d.Status) | Vấn đề: $($d.Problem)"
            Log-Text "   ────────────────────────────────────────────────"
        }
        if ($txtStatus) { $txtStatus.Text = "Phát hiện $($faulty.Count) thiết bị lỗi" }
    }
}

Register-Click "btnPnpRescan" {
    Log-Text "[*] Đang gửi lệnh quét phần cứng Plug and Play (pnputil /scan-devices)..."
    Invoke-PnpDeviceRescan
    Log-Text "[✓] Windows đã hoàn tất quét và phát hiện lại các thiết bị phần cứng."
}

Register-Click "btnOpenDeviceManager" {
    Log-Text "[*] Đang mở Trình quản lý thiết bị (devmgmt.msc)..."
    Start-Process "devmgmt.msc"
}

Register-Click "btnFixDriverUpdate" {
    Log-Text "[*] Đang giải phóng hàng đợi tải driver bị kẹt trong Windows Update..."
    if ($txtStatus) { $txtStatus.Text = "Đang sửa lỗi kẹt cập nhật driver..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }

    Reset-WindowsUpdateEngine

    Log-Text "   - Đang buộc nhận diện lại các thiết bị phần cứng..."
    Invoke-PnpDeviceRescan

    Log-Text "   - Yêu cầu Windows Update quét tìm driver thay thế mới..."
    Start-Process "usoclient" -ArgumentList "StartScan" -NoNewWindow

    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "Đã gỡ lỗi kẹt driver update" }
    Log-Text "[✓] Hoàn thành! Lỗi kẹt tải driver đã được dọn sạch."
}

Register-Click "btnScanWindowsUpdateDrivers" {
    Log-Text "[*] Đang kích hoạt quét driver từ Microsoft Windows Update..."
    Start-Process "usoclient" -ArgumentList "StartInteractiveScan" -NoNewWindow
    Log-Text "[✓] Đã gửi lệnh tìm kiếm Driver mới qua Windows Update."
}

Register-Click "btnCleanDriverStore" {
    Log-Text "[*] Đang quét và dọn dẹp các phiên bản driver cũ trong DriverStore..."
    if ($txtStatus) { $txtStatus.Text = "Đang dọn dẹp DriverStore..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    Invoke-DriverStoreCleanup
    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "Dọn dẹp DriverStore hoàn tất" }
    Log-Text "[✓] Đã dọn dẹp sạch sẽ các bản driver cũ."
}

Register-Click "btnBackupDrivers" {
    $dest = "C:\Backup_Drivers"
    Log-Text "[*] Đang sao lưu toàn bộ Driver của máy ra thư mục: '$dest'..."
    if ($txtStatus) { $txtStatus.Text = "Đang sao lưu driver..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }

    Export-SystemDriversBackup -Destination $dest

    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    if ($txtStatus) { $txtStatus.Text = "Sao lưu driver hoàn tất" }
    Log-Text "[✓] THÀNH CÔNG! Đã sao lưu toàn bộ driver vào: $dest"
}

Register-Click "btnOpenBackupFolder" {
    $dest = "C:\Backup_Drivers"
    if (Test-Path $dest) {
        Start-Process explorer.exe $dest
    } else {
        Log-Text "[!] Thư mục $dest chưa tồn tại. Hãy bấm nút 'Sao Lưu Toàn Bộ Driver' trước."
    }
}

# ── TỰ ĐỘNG QUÉT KHI MỞ CỬA SỔ & KHỞI CHẠY GIAO DIỆN ──
$script:autoScannedOnStartup = $false
$window.Add_ContentRendered({
    if (-not $script:autoScannedOnStartup) {
        $script:autoScannedOnStartup = $true
        [System.Windows.Forms.Application]::DoEvents()
        Scan-And-ColorizeApps
    }
})

$window.ShowDialog() | Out-Null
