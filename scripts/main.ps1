# ── KHỞI TẠO CÁC CONTROL TỪ XAML ──
$reader = New-Object System.Xml.XmlNodeReader $XAML
$window = [Windows.Markup.XamlReader]::Load($reader)

# Các Control chính
$tabMain = $window.FindName("tabMain")
$txtStatus = $window.FindName("txtStatus")
$progressBar = $window.FindName("progressBar")
$txtTerminal = $window.FindName("txtTerminal")
$txtSearch = $window.FindName("txtSearch")
$txtSelectionCount = $window.FindName("txtSelectionCount")
$cardsContainer = $window.FindName("CardsContainer")

# Tab Navigation Buttons
$navBtnApps = $window.FindName("navBtnApps")
$navBtnRepair = $window.FindName("navBtnRepair")
$navBtnDrivers = $window.FindName("navBtnDrivers")

# App Action Buttons
$btnInstall = $window.FindName("btnInstall")
$btnUpgrade = $window.FindName("btnUpgrade")
$btnUninstall = $window.FindName("btnUninstall")
$btnScanInstalled = $window.FindName("btnScanInstalled")
$btnSelectAll = $window.FindName("btnSelectAll")
$btnClear = $window.FindName("btnClear")
$btnClearLog = $window.FindName("btnClearLog")

# System Repair Buttons
$btnSfc = $window.FindName("btnSfc")
$btnDism = $window.FindName("btnDism")
$btnResetWu = $window.FindName("btnResetWu")
$btnWuTroubleshoot = $window.FindName("btnWuTroubleshoot")
$btnFlushDns = $window.FindName("btnFlushDns")
$btnResetWinsock = $window.FindName("btnResetWinsock")
$btnCleanTemp = $window.FindName("btnCleanTemp")
$btnCleanLogs = $window.FindName("btnCleanLogs")

# Driver Suite Buttons
$btnScanFaultyDrivers = $window.FindName("btnScanFaultyDrivers")
$btnPnpRescan = $window.FindName("btnPnpRescan")
$btnOpenDeviceManager = $window.FindName("btnOpenDeviceManager")
$btnFixDriverUpdate = $window.FindName("btnFixDriverUpdate")
$btnScanWindowsUpdateDrivers = $window.FindName("btnScanWindowsUpdateDrivers")
$btnCleanDriverStore = $window.FindName("btnCleanDriverStore")
$btnBackupDrivers = $window.FindName("btnBackupDrivers")
$btnOpenBackupFolder = $window.FindName("btnOpenBackupFolder")

# ── LOGIC ĐIỀU HƯỚNG TAB CHÍNH ──
function Set-ActiveTab {
    param([int]$index, $activeBtn)
    $tabMain.SelectedIndex = $index

    $buttons = @($navBtnApps, $navBtnRepair, $navBtnDrivers)
    foreach ($btn in $buttons) {
        $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
        $btn.BorderBrush = [System.Windows.Media.Brushes]::Transparent
    }

    $activeBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
    $activeBtn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
}

$navBtnApps.Add_Click({ Set-ActiveTab 0 $navBtnApps })
$navBtnRepair.Add_Click({ Set-ActiveTab 1 $navBtnRepair })
$navBtnDrivers.Add_Click({ Set-ActiveTab 2 $navBtnDrivers })

# ── SINH CÁC CARD ỨNG DỤNG BỐ CỤC 4 CỘT RỘNG RÃI ──
$allCheckBoxes = @()
$allItemBorders = @()
$categories = $AppCatalog | Select-Object -ExpandProperty Category -Unique

function Update-SelectionCount {
    $selectedCount = @($allCheckBoxes | Where-Object { $_.IsChecked }).Count
    $txtSelectionCount.Text = "$selectedCount app được chọn"
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
    $cardsContainer.Children.Add($cardBorder) | Out-Null
}

# ── LOGIC TÌM KIẾM & BỘ LỌC ──
$txtSearch.Add_TextChanged({
    $keyword = $txtSearch.Text.Trim().ToLower()
    foreach ($row in $allItemBorders) {
        $app = $row.Tag.App
        $matched = [string]::IsNullOrEmpty($keyword) -or ($app.Name.ToLower().Contains($keyword)) -or ($app.ID.ToLower().Contains($keyword))
        $row.Visibility = if ($matched) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    }
})

$btnScanInstalled.Add_Click({ Scan-And-ColorizeApps })

# ── CÁC HÀNH ĐỘNG CÀI ĐẶT / GỠ / NÂNG CẤP ──
$btnInstall.Add_Click({
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
        $progressBar.Value = [math]::Round(($idx / $total) * 100)
        $txtStatus.Text = "[$idx/$total] Đang cài đặt: $($app.Name)..."
        Log-Text "[$idx/$total] Đang cài: $($app.Name) (ID: $($app.ID))..."

        $code = Run-CliStream "winget" "install --id $($app.ID) --exact --silent --accept-package-agreements --accept-source-agreements"
        if ($code -eq 0) {
            Log-Text "   [✓ HOÀN THÀNH] $($app.Name)"
        } else {
            Log-Text "   [❌ LỖI] $($app.Name) (Exit Code: $code)"
        }
    }
    $txtStatus.Text = "Cài đặt hoàn tất!"
    $progressBar.Value = 100
    Scan-And-ColorizeApps
})

$btnUninstall.Add_Click({
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
        $progressBar.Value = [math]::Round(($idx / $total) * 100)
        $txtStatus.Text = "[$idx/$total] Đang gỡ bỏ: $($app.Name)..."
        Log-Text "[$idx/$total] Đang gỡ: $($app.Name) (ID: $($app.ID))..."

        $code = Run-CliStream "winget" "uninstall --id $($app.ID) --silent"
        if ($code -eq 0) {
            Log-Text "   [✓ ĐÃ GỠ THÀNH CÔNG] $($app.Name)"
        } else {
            Log-Text "   [❌ LỖI GỠ] $($app.Name) (Exit Code: $code)"
        }
    }
    $txtStatus.Text = "Gỡ cài đặt hoàn tất!"
    $progressBar.Value = 100
    Scan-And-ColorizeApps
})

$btnUpgrade.Add_Click({
    Log-Text "=========================================================="
    Log-Text "⚡ BẮT ĐẦU NÂNG CẤP TOÀN BỘ PHẦN MỀM TRÊN MÁY"
    Log-Text "=========================================================="
    $txtStatus.Text = "Đang nâng cấp tất cả ứng dụng..."
    $progressBar.IsIndeterminate = $true

    Run-CliStream "winget" "upgrade --all --silent --accept-package-agreements --accept-source-agreements"

    $progressBar.IsIndeterminate = $false
    $txtStatus.Text = "Nâng cấp hoàn tất!"
    Log-Text "[✓] Toàn bộ ứng dụng đã được nâng cấp lên bản mới nhất."
    Scan-And-ColorizeApps
})

$btnSelectAll.Add_Click({
    foreach ($cb in $allCheckBoxes) { $cb.IsChecked = $true }
    Update-SelectionCount
})

$btnClear.Add_Click({
    foreach ($cb in $allCheckBoxes) { $cb.IsChecked = $false }
    Update-SelectionCount
})

$btnClearLog.Add_Click({
    $txtTerminal.Clear()
})

# ── LOGIC MODULE SỬA LỖI HỆ THỐNG (SYSTEM REPAIRS) ──
$btnSfc.Add_Click({
    Log-Text "[*] Đang bắt đầu quét kiểm tra tính toàn vẹn hệ thống (sfc /scannow)..."
    $txtStatus.Text = "Đang chạy SFC Scan..."
    $progressBar.IsIndeterminate = $true
    Run-CliStream "sfc.exe" "/scannow"
    $progressBar.IsIndeterminate = $false
    $txtStatus.Text = "Quét SFC hoàn tất"
    Log-Text "[✓] Quá trình SFC đã kết thúc."
})

$btnDism.Add_Click({
    Log-Text "[*] Đang khôi phục kho ảnh hệ thống Windows qua DISM RestoreHealth..."
    $txtStatus.Text = "Đang chạy DISM RestoreHealth..."
    $progressBar.IsIndeterminate = $true
    Run-CliStream "dism.exe" "/Online /Cleanup-Image /RestoreHealth"
    $progressBar.IsIndeterminate = $false
    $txtStatus.Text = "DISM hoàn tất"
    Log-Text "[✓] DISM RestoreHealth hoàn thành xuất sắc."
})

$btnResetWu.Add_Click({
    Log-Text "[*] Bắt đầu khởi động lại hoàn toàn dịch vụ Windows Update..."
    $txtStatus.Text = "Đang sửa lỗi Windows Update..."
    $progressBar.IsIndeterminate = $true
    Reset-WindowsUpdateEngine
    $progressBar.IsIndeterminate = $false
    $txtStatus.Text = "Đã đặt lại Windows Update"
})

$btnWuTroubleshoot.Add_Click({
    Log-Text "[*] Đang khởi chạy Trình khắc phục sự cố Windows Update chính chủ Microsoft..."
    Start-Process "ms-settings:troubleshoot"
})

$btnFlushDns.Add_Click({
    Log-Text "[*] Đang xóa sạch bộ nhớ đệm phân giải DNS (ipconfig /flushdns)..."
    Run-CliStream "ipconfig.exe" "/flushdns"
    Log-Text "[✓] Đã làm mới DNS resolver cache."
})

$btnResetWinsock.Add_Click({
    Log-Text "[*] Đang đặt lại danh mục Winsock Catalog và TCP/IP Stack..."
    Run-CliStream "netsh.exe" "winsock reset"
    Run-CliStream "netsh.exe" "int ip reset"
    Log-Text "[✓] Đã khôi phục cài đặt mạng mặc định. Khuyên bạn nên khởi động lại máy."
})

$btnCleanTemp.Add_Click({
    Log-Text "[*] Đang dọn dẹp các tệp tạm thời trong User Temp và Windows Temp..."
    $txtStatus.Text = "Đang dọn tệp rác Temp..."
    $progressBar.IsIndeterminate = $true

    $tempPaths = @($env:TEMP, "C:\Windows\Temp")
    foreach ($p in $tempPaths) {
        if (Test-Path $p) {
            Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $progressBar.IsIndeterminate = $false
    $txtStatus.Text = "Dọn tệp tạm hoàn tất"
    Log-Text "[✓] Dọn dẹp bộ nhớ tạm thành công!"
})

$btnCleanLogs.Add_Click({
    Log-Text "[*] Đang xóa sạch các nhật ký sự kiện Windows Event Logs cũ..."
    $txtStatus.Text = "Đang xóa Event Logs..."
    $progressBar.IsIndeterminate = $true

    Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object {
        try { [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName) } catch {}
    }

    $progressBar.IsIndeterminate = $false
    $txtStatus.Text = "Xóa Event Logs hoàn tất"
    Log-Text "[✓] Nhật ký sự kiện đã được giải phóng sạch sẽ."
})

# ── LOGIC MODULE QUẢN LÝ & GỠ LỖI DRIVER ──
$btnScanFaultyDrivers.Add_Click({
    Log-Text "=========================================================="
    Log-Text "🔍 ĐANG QUÉT TOÀN BỘ THIẾT BỊ PHẦN CỨNG & DRIVER BỊ LỖI..."
    Log-Text "=========================================================="
    $txtStatus.Text = "Đang quét thiết bị lỗi..."

    $faulty = @(Get-PnpDevice | Where-Object { $_.Present -eq $true -and $_.Status -ne 'OK' })

    if ($faulty.Count -eq 0) {
        Log-Text "[✓] Tuyệt vời! Không phát hiện thiết bị nào bị lỗi hoặc thiếu driver trên máy bạn."
        $txtStatus.Text = "Tất cả Driver đều hoạt động tốt"
    } else {
        Log-Text "[⚠️] PHÁT HIỆN $($faulty.Count) THIẾT BỊ ĐANG BỊ LỖI / THIẾU DRIVER:"
        foreach ($d in $faulty) {
            Log-Text "   • Tên thiết bị: $($d.FriendlyName)"
            Log-Text "     Mã phần cứng: $($d.InstanceId)"
            Log-Text "     Trạng thái: $($d.Status) | Vấn đề: $($d.Problem)"
            Log-Text "   ────────────────────────────────────────────────"
        }
        $txtStatus.Text = "Phát hiện $($faulty.Count) thiết bị lỗi"
    }
})

$btnPnpRescan.Add_Click({
    Log-Text "[*] Đang gửi lệnh quét phần cứng Plug and Play (pnputil /scan-devices)..."
    Run-CliStream "pnputil.exe" "/scan-devices"
    Log-Text "[✓] Windows đã hoàn tất quét và phát hiện lại các thiết bị phần cứng."
})

$btnOpenDeviceManager.Add_Click({
    Log-Text "[*] Đang mở Trình quản lý thiết bị (devmgmt.msc)..."
    Start-Process "devmgmt.msc"
})

$btnFixDriverUpdate.Add_Click({
    Log-Text "[*] Đang giải phóng hàng đợi tải driver bị kẹt trong Windows Update..."
    $txtStatus.Text = "Đang sửa lỗi kẹt cập nhật driver..."
    $progressBar.IsIndeterminate = $true

    Reset-WindowsUpdateEngine

    Log-Text "   - Đang buộc nhận diện lại các thiết bị phần cứng..."
    Run-CliStream "pnputil.exe" "/scan-devices"

    Log-Text "   - Yêu cầu Windows Update quét tìm driver thay thế mới..."
    Start-Process "usoclient" -ArgumentList "StartScan" -NoNewWindow

    $progressBar.IsIndeterminate = $false
    $txtStatus.Text = "Đã gỡ lỗi kẹt driver update"
    Log-Text "[✓] Hoàn thành! Lỗi kẹt tải driver đã được dọn sạch."
})

$btnScanWindowsUpdateDrivers.Add_Click({
    Log-Text "[*] Đang kích hoạt quét driver từ Microsoft Windows Update..."
    Start-Process "usoclient" -ArgumentList "StartInteractiveScan" -NoNewWindow
    Log-Text "[✓] Đã gửi lệnh tìm kiếm Driver mới qua Windows Update."
})

$btnCleanDriverStore.Add_Click({
    Log-Text "[*] Đang quét và dọn dẹp các phiên bản driver cũ không còn sử dụng trong DriverStore..."
    $txtStatus.Text = "Đang dọn dẹp DriverStore..."
    $progressBar.IsIndeterminate = $true

    Run-CliStream "dism.exe" "/Online /Cleanup-Image /StartComponentCleanup /ResetBase"

    $progressBar.IsIndeterminate = $false
    $txtStatus.Text = "Dọn dẹp DriverStore hoàn tất"
    Log-Text "[✓] Đã dọn dẹp sạch sẽ các bản driver cũ."
})

$btnBackupDrivers.Add_Click({
    $dest = "C:\Backup_Drivers"
    Log-Text "[*] Đang sao lưu toàn bộ Driver của máy ra thư mục: '$dest'..."
    $txtStatus.Text = "Đang sao lưu driver..."
    $progressBar.IsIndeterminate = $true

    if (-not (Test-Path $dest)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }

    try {
        Export-WindowsDriver -Online -Destination $dest -ErrorAction Stop | Out-Null
        Log-Text "[✓] THÀNH CÔNG! Đã sao lưu toàn bộ driver bên thứ ba vào: $dest"
        $txtStatus.Text = "Sao lưu driver hoàn tất"
    } catch {
        Log-Text "[!] Lỗi khi xuất bằng Export-WindowsDriver. Đang thử lại bằng pnputil..."
        Run-CliStream "pnputil.exe" "/export-driver * `"$dest`""
        Log-Text "[✓] Đã sao lưu driver qua pnputil vào: $dest"
    }

    $progressBar.IsIndeterminate = $false
})

$btnOpenBackupFolder.Add_Click({
    $dest = "C:\Backup_Drivers"
    if (Test-Path $dest) {
        Start-Process explorer.exe $dest
    } else {
        Log-Text "[!] Thư mục $dest chưa tồn tại. Hãy bấm nút 'Sao Lưu Toàn Bộ Driver' trước."
    }
})

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
