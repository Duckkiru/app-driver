# ── KHỞI TẠO CÁC CONTROL TỪ XAML ──
$reader = New-Object System.Xml.XmlNodeReader $XAML
$window = [Windows.Markup.XamlReader]::Load($reader)

# Các Control chính
$MainTabControl    = $window.FindName("MainTabControl")
$txtStatus         = $window.FindName("txtStatus")
$progressBar       = $window.FindName("progressBar")
$txtLog            = $window.FindName("txtLog")
$txtSearch         = $window.FindName("txtSearch")
$txtSelectionCount = $window.FindName("txtSelectionCount")
$cardsContainer    = $window.FindName("CardsContainer")

# Bảng màu Frozen Brush tĩnh tái sử dụng tối đa, loại trừ cấp phát bộ nhớ rác (GC)
$script:brushNavActive   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushNavActive.Freeze()
$script:brushNavInactive = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x64, 0x74, 0x8B)); $script:brushNavInactive.Freeze()
$script:brushTransparent = [System.Windows.Media.Brushes]::Transparent

$script:brushCardBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x0F, 0x14, 0x20)); $script:brushCardBg.Freeze()
$script:brushCardBorder  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1E, 0x28, 0x3C)); $script:brushCardBorder.Freeze()
$script:brushHeaderFg    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushHeaderFg.Freeze()
$script:brushSeparator   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1E, 0x26, 0x38)); $script:brushSeparator.Freeze()

$script:brushRowHover    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1C, 0x25, 0x3B)); $script:brushRowHover.Freeze()
$script:brushTextWhite   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xFF, 0xFF, 0xFF)); $script:brushTextWhite.Freeze()

# Cấu trúc hình học tái sử dụng (Shared Layout Geometries)
$marginCardBorder = New-Object System.Windows.Thickness(5)
$paddingCard      = New-Object System.Windows.Thickness(12, 10, 12, 12)
$marginHeaderGrid = New-Object System.Windows.Thickness(0, 0, 0, 8)
$marginSeparator  = New-Object System.Windows.Thickness(0, 2, 0, 6)
$marginRowBorder  = New-Object System.Windows.Thickness(0, 1, 0, 1)
$paddingRow       = New-Object System.Windows.Thickness(6, 4, 6, 4)
$marginIcon       = New-Object System.Windows.Thickness(7, 0, 8, 0)
$cornerCard       = New-Object System.Windows.CornerRadius(10)
$cornerRow        = New-Object System.Windows.CornerRadius(6)
$thicknessOne     = New-Object System.Windows.Thickness(1)

# Thư mục lưu cache biểu tượng ứng dụng cục bộ
$iconsCacheDir = Join-Path $env:LOCALAPPDATA "DuckUtil\Icons"
if (-not (Test-Path -LiteralPath $iconsCacheDir)) {
    try { New-Item -ItemType Directory -Path $iconsCacheDir -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
}

# Trình khóa thực thi đơn nhất (Re-entrancy Guard) chống xung đột tiến trình
$script:isActionRunning = $false

function Invoke-GuardedAction {
    param([string]$ActionName, [scriptblock]$Action)
    if ($script:isActionRunning) {
        Log-Text "[⚠️] Đang có một tác vụ khác đang thực thi ($ActionName). Vui lòng đợi!"
        return
    }
    $script:isActionRunning = $true
    try {
        & $Action
    } catch {
        Log-Text "[!] Lỗi khi thực hiện '$ActionName': $($_.Exception.Message)"
    } finally {
        $script:isActionRunning = $false
        [System.Windows.Forms.Application]::DoEvents()
    }
}

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
            $btn.Foreground  = $script:brushNavInactive
            $btn.BorderBrush = $script:brushTransparent
        }
    }

    if ($activeBtn) {
        $activeBtn.Foreground  = $script:brushNavActive
        $activeBtn.BorderBrush = $script:brushNavActive
    }
}

Register-Click "navBtnApps"    { Set-ActiveTab 0 $navBtnApps }
Register-Click "navBtnRepair"  { Set-ActiveTab 1 $navBtnRepair }
Register-Click "navBtnDrivers" { Set-ActiveTab 2 $navBtnDrivers }

# Đồng bộ trạng thái tab khởi tạo ban đầu (Section 3.4)
Set-ActiveTab 0 $navBtnApps

# ── SINH CÁC CARD ỨNG DỤNG BỐ CỤC 4 CỘT HIỆU NĂNG CAO ──
$allCheckBoxes   = [System.Collections.Generic.List[object]]::new()
$allItemBorders  = [System.Collections.Generic.List[object]]::new()
$categoryCardMap = [System.Collections.Generic.Dictionary[object, System.Collections.Generic.List[object]]]::new()

$categories = $AppCatalog | Select-Object -ExpandProperty Category -Unique

$script:suppressSelectionCount = $false

function Update-SelectionCount {
    if ($script:suppressSelectionCount) { return }
    $selectedCount = 0
    foreach ($cb in $allCheckBoxes) {
        if ($cb.IsChecked -eq $true) {
            $selectedCount++
        }
    }
    if ($txtSelectionCount) {
        $txtSelectionCount.Text = "$selectedCount app được chọn"
    }
}

foreach ($cat in $categories) {
    $cardBorder = New-Object System.Windows.Controls.Border
    $cardBorder.Background = $script:brushCardBg
    $cardBorder.BorderBrush = $script:brushCardBorder
    $cardBorder.BorderThickness = $thicknessOne
    $cardBorder.CornerRadius = $cornerCard
    $cardBorder.Margin = $marginCardBorder
    $cardBorder.Padding = $paddingCard

    $cardStack = New-Object System.Windows.Controls.StackPanel
    $appsInCat = @($AppCatalog | Where-Object { $_.Category -eq $cat })
    $rowsInCard = [System.Collections.Generic.List[object]]::new()

    # Header Card
    $headerGrid = New-Object System.Windows.Controls.Grid
    $headerGrid.Margin = $marginHeaderGrid

    $headerText = New-Object System.Windows.Controls.TextBlock
    $headerText.Text = "$cat ($($appsInCat.Count))"
    $headerText.FontSize = 12.5
    $headerText.FontWeight = [System.Windows.FontWeights]::Bold
    $headerText.Foreground = $script:brushHeaderFg
    $headerGrid.Children.Add($headerText) | Out-Null

    $separator = New-Object System.Windows.Controls.Border
    $separator.Height = 1
    $separator.Background = $script:brushSeparator
    $separator.Margin = $marginSeparator

    $cardStack.Children.Add($headerGrid) | Out-Null
    $cardStack.Children.Add($separator) | Out-Null

    # Từng dòng App: Logo + CheckBox + Tên
    foreach ($app in $appsInCat) {
        $rowBorder = New-Object System.Windows.Controls.Border
        $rowBorder.CornerRadius = $cornerRow
        $rowBorder.Padding = $paddingRow
        $rowBorder.Margin = $marginRowBorder
        $rowBorder.Background = $script:brushTransparent
        $rowBorder.Cursor = [System.Windows.Input.Cursors]::Hand

        # Tiền tính toán chuỗi tìm kiếm để bộ lọc TextChanged chạy tức thì
        $aliasText = if ($app.Aliases) { $app.Aliases -join " " } else { "" }
        $searchIndex = "$($app.Name) $($app.ID) $($app.Category) $aliasText $($app.Desc)".ToLowerInvariant()

        $rowBorder.Tag = @{
            App              = $app
            Status           = "NONE"
            DetectedId       = $null
            InstalledVersion = $null
            CardBorder       = $cardBorder
            SearchIndex      = $searchIndex
        }

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
        $cb.Tag = $rowBorder.Tag
        $cb.Add_Checked({ Update-SelectionCount })
        $cb.Add_Unchecked({ Update-SelectionCount })
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $rowGrid.Children.Add($cb) | Out-Null
        $allCheckBoxes.Add($cb)

        # 2. Logo Icon chính hãng (Cache tệp theo ID ứng dụng và sử dụng GetNewClosure() chống xung đột biến - Section 3.1)
        $img = New-Object System.Windows.Controls.Image
        $img.Width = 16; $img.Height = 16
        $img.Margin = $marginIcon
        $img.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $localIconPath = Join-Path $iconsCacheDir "$($app.ID).png"
        if (Test-Path -LiteralPath $localIconPath) {
            try {
                $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                $bmp.BeginInit()
                $bmp.UriSource = New-Object System.Uri($localIconPath, [System.UriKind]::Absolute)
                $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bmp.EndInit()
                $img.Source = $bmp
            } catch {}
        } elseif (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
            try {
                $remoteUri = New-Object System.Uri("https://www.google.com/s2/favicons?domain=$($app.Domain)&sz=32", [System.UriKind]::Absolute)
                $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                $bmp.BeginInit()
                $bmp.UriSource = $remoteUri
                $bmp.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::DelayCreation
                $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnDemand
                $bmp.EndInit()

                # Gắn sự kiện DownloadCompleted an toàn với GetNewClosure() để lưu cache không bị đè icon
                $cacheClosure = {
                    param($sender, $e)
                    try {
                        if ($sender -and -not (Test-Path -LiteralPath $localIconPath)) {
                            $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                            $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($sender))
                            $fs = [System.IO.File]::OpenWrite($localIconPath)
                            $encoder.Save($fs)
                            $fs.Close()
                        }
                    } catch {}
                }.GetNewClosure()

                $bmp.Add_DownloadCompleted($cacheClosure)
                $img.Source = $bmp
            } catch {}
        }
        [System.Windows.Controls.Grid]::SetColumn($img, 1)
        $rowGrid.Children.Add($img) | Out-Null

        # 3. Tên ứng dụng
        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $app.Name
        $nameText.Foreground = $script:brushTextWhite
        $nameText.FontSize = 12
        $nameText.FontWeight = [System.Windows.FontWeights]::SemiBold
        $nameText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $nameText.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $nameText.ToolTip = "$($app.Name)`nID: $($app.ID)`n$($app.Desc)"
        [System.Windows.Controls.Grid]::SetColumn($nameText, 2)
        $rowGrid.Children.Add($nameText) | Out-Null

        # Tối ưu nhấp chọn toàn dòng mượt mà, phân lập rõ click CheckBox và click nền để chống giật/lặp sự kiện
        $rowBorder.Add_MouseLeftButtonUp({
            param($sender, $e)
            $src = $e.OriginalSource
            $isCb = $false
            while ($src -ne $null -and $src -ne $sender) {
                if ($src -is [System.Windows.Controls.CheckBox]) {
                    $isCb = $true
                    break
                }
                if ($src -is [System.Windows.Media.Visual]) {
                    $src = [System.Windows.Media.VisualTreeHelper]::GetParent($src)
                } else {
                    break
                }
            }
            if (-not $isCb) {
                $cb.IsChecked = -not $cb.IsChecked
            }
        })

        # Hover phát sáng & phục hồi màu trạng thái cực nhanh nhờ Frozen Brushes
        $rowBorder.Add_MouseEnter({
            if ($rowBorder.Tag.Status -eq "NONE") {
                $rowBorder.Background = $script:brushRowHover
            }
        })
        $rowBorder.Add_MouseLeave({
            $status = $rowBorder.Tag.Status
            if ($status -eq "LATEST") {
                $rowBorder.Background = $script:brushLatestBg
            } elseif ($status -eq "OUTDATED") {
                $rowBorder.Background = $script:brushOutdatedBg
            } else {
                $rowBorder.Background = $script:brushTransparent
            }
        })

        $rowBorder.Child = $rowGrid
        $cardStack.Children.Add($rowBorder) | Out-Null
        $allItemBorders.Add($rowBorder)
        $rowsInCard.Add($rowBorder)
    }

    $cardBorder.Child = $cardStack
    $categoryCardMap[$cardBorder] = $rowsInCard
    if ($cardsContainer) {
        $cardsContainer.Children.Add($cardBorder) | Out-Null
    }
}

# ── LOGIC TÌM KIẾM & BỘ LỌC TỐC ĐỘ CAO (INDEXED SEARCH) ──
if ($txtSearch) {
    $txtSearch.Add_TextChanged({
        $keyword = $txtSearch.Text.Trim().ToLowerInvariant()
        $isEmpty = [string]::IsNullOrEmpty($keyword)

        foreach ($entry in $categoryCardMap.GetEnumerator()) {
            $card = $entry.Key
            $rows = $entry.Value
            $visibleRowsCount = 0

            foreach ($row in $rows) {
                $matched = $isEmpty -or ($row.Tag.SearchIndex.Contains($keyword))
                if ($matched) {
                    $row.Visibility = [System.Windows.Visibility]::Visible
                    $visibleRowsCount++
                } else {
                    $row.Visibility = [System.Windows.Visibility]::Collapsed
                }
            }

            # Ẩn cả khung Card Category nếu không có ứng dụng nào khớp từ khóa
            if ($isEmpty -or $visibleRowsCount -gt 0) {
                $card.Visibility = [System.Windows.Visibility]::Visible
            } else {
                $card.Visibility = [System.Windows.Visibility]::Collapsed
            }
        }
    })
}

# ── CÁC HÀNH ĐỘNG CÀI ĐẶT / GỠ / NÂNG CẤP APP ──
Register-Click "btnScanInstalled" {
    Invoke-GuardedAction "Quét ứng dụng" {
        Scan-And-ColorizeApps
    }
}

Register-Click "btnInstall" {
    Invoke-GuardedAction "Cài đặt ứng dụng" {
        $selected = [System.Collections.Generic.List[object]]::new()
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -eq $true) {
                $selected.Add($cb.Tag.App)
            }
        }

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

            $code = Run-CliStream "winget" "install --id `"$($app.ID)`" --exact --silent --accept-package-agreements --accept-source-agreements"
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
}

Register-Click "btnUninstall" {
    Invoke-GuardedAction "Gỡ cài đặt" {
        $selectedTags = [System.Collections.Generic.List[object]]::new()
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -eq $true) {
                $selectedTags.Add($cb.Tag)
            }
        }

        if ($selectedTags.Count -eq 0) {
            Log-Text "[!] Bạn chưa chọn ứng dụng nào để gỡ cài đặt!"
            return
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Bạn có chắc chắn muốn gỡ bỏ $($selectedTags.Count) ứng dụng đã chọn?",
            "Xác nhận gỡ cài đặt",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $total = $selectedTags.Count
        $idx = 0
        Log-Text "=========================================================="
        Log-Text "🗑️ BẮT ĐẦU GỠ CÀI ĐẶT $total ỨNG DỤNG ĐÃ CHỌN"
        Log-Text "=========================================================="

        foreach ($tag in $selectedTags) {
            $idx++
            $app = $tag.App
            # Ưu tiên sử dụng DetectedId thực tế phát hiện được qua SmartMatcher (Section 3.2)
            $uninstallId = if ($tag.DetectedId) { $tag.DetectedId } else { $app.ID }

            if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }
            if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang gỡ bỏ: $($app.Name)..." }
            Log-Text "[$idx/$total] Đang gỡ: $($app.Name) (Mã gỡ: $uninstallId)..."

            $code = Run-CliStream "winget" "uninstall --id `"$uninstallId`" --silent"
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
}

Register-Click "btnUpgradeAll" {
    Invoke-GuardedAction "Nâng cấp toàn bộ" {
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
}

# Chọn tất cả: chỉ chọn các dòng đang hiển thị theo bộ lọc tìm kiếm (Section 3.3)
Register-Click "btnSelectAll" {
    $script:suppressSelectionCount = $true
    try {
        foreach ($row in $allItemBorders) {
            if ($row.Visibility -eq [System.Windows.Visibility]::Visible) {
                $grid = $row.Child
                $cb = $grid.Children[0]
                if ($cb.IsChecked -ne $true) {
                    $cb.IsChecked = $true
                }
            }
        }
    } finally {
        $script:suppressSelectionCount = $false
    }
    Update-SelectionCount
}

Register-Click "btnDeselectAll" {
    $script:suppressSelectionCount = $true
    try {
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -ne $false) {
                $cb.IsChecked = $false
            }
        }
    } finally {
        $script:suppressSelectionCount = $false
    }
    Update-SelectionCount
}

Register-Click "btnClearLog" {
    if ($txtLog) { $txtLog.Clear() }
}

# ── LOGIC MODULE SỬA LỖI HỆ THỐNG (SYSTEM REPAIRS) ──
Register-Click "btnSfcScan" {
    Invoke-GuardedAction "SFC Scan" {
        Log-Text "[*] Đang bắt đầu quét kiểm tra tính toàn vẹn hệ thống (sfc /scannow)..."
        if ($txtStatus) { $txtStatus.Text = "Đang chạy SFC Scan..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-SystemFileCheck
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Quét SFC hoàn tất" }
        Log-Text "[✓] Quá trình SFC đã kết thúc."
    }
}

Register-Click "btnDismRestore" {
    Invoke-GuardedAction "DISM RestoreHealth" {
        Log-Text "[*] Đang khôi phục kho ảnh hệ thống Windows qua DISM RestoreHealth..."
        if ($txtStatus) { $txtStatus.Text = "Đang chạy DISM RestoreHealth..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-DismRestoreHealth
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "DISM hoàn tất" }
        Log-Text "[✓] DISM RestoreHealth hoàn thành xuất sắc."
    }
}

Register-Click "btnDismCleanup" {
    Invoke-GuardedAction "DISM Component Cleanup" {
        Log-Text "[*] Đang dọn dẹp kho linh kiện hệ thống (DISM Component Cleanup)..."
        if ($txtStatus) { $txtStatus.Text = "Đang dọn kho linh kiện..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-DriverStoreCleanup
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn kho linh kiện hoàn tất" }
        Log-Text "[✓] Đã giải phóng dung lượng kho linh kiện."
    }
}

Register-Click "btnFixWindowsUpdate" {
    Invoke-GuardedAction "Khởi tạo lại Windows Update" {
        Log-Text "[*] Bắt đầu khởi tạo và xóa sạch cache lỗi Windows Update..."
        if ($txtStatus) { $txtStatus.Text = "Đang sửa lỗi Windows Update..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Reset-WindowsUpdateEngine
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Đã đặt lại Windows Update" }
    }
}

Register-Click "btnRestartUpdateServices" {
    Invoke-GuardedAction "Khởi động lại Update Services" {
        Log-Text "[*] Đang khởi động lại dịch vụ Windows Update & BITS..."
        Restart-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
        Restart-Service -Name "bits" -Force -ErrorAction SilentlyContinue
        Log-Text "[✓] Đã khởi động lại dịch vụ cập nhật."
    }
}

Register-Click "btnTriggerScanUpdate" {
    Invoke-GuardedAction "Kích hoạt quét cập nhật" {
        Invoke-WindowsUpdateScan
    }
}

Register-Click "btnFlushDnsWinsock" {
    Invoke-GuardedAction "Flush DNS & Reset Winsock" {
        Log-Text "[*] Đang xóa sạch cache DNS và reset Winsock Catalog..."
        Clear-DnsResolverCache
        Run-CliStream "netsh.exe" "winsock reset"
        Log-Text "[✓] Đã làm mới mạng và DNS cache."
    }
}

Register-Click "btnResetTcpIp" {
    Invoke-GuardedAction "Reset TCP/IP Stack" {
        Log-Text "[*] Đang đặt lại toàn bộ ngăn xếp giao thức mạng TCP/IP..."
        Reset-NetworkInterfaceStack
        Log-Text "[✓] Đã reset TCP/IP Stack. Khuyên bạn nên khởi động lại máy."
    }
}

Register-Click "btnClearTemp" {
    Invoke-GuardedAction "Dọn dẹp Temp" {
        Log-Text "[*] Đang dọn dẹp các tệp tạm thời trong User Temp và Windows Temp..."
        if ($txtStatus) { $txtStatus.Text = "Đang dọn tệp rác Temp..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Clear-SystemTempFiles
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn tệp tạm hoàn tất" }
        Log-Text "[✓] Dọn dẹp bộ nhớ tạm thành công!"
    }
}

Register-Click "btnCleanEventLogs" {
    Invoke-GuardedAction "Dọn dẹp Windows Event Logs" {
        if ($txtStatus) { $txtStatus.Text = "Đang dọn Event Logs..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Clear-SystemEventLogs
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn Event Logs hoàn tất" }
    }
}

Register-Click "btnRestartExplorer" {
    Invoke-GuardedAction "Khởi động lại Windows Explorer" {
        Log-Text "[*] Đang khởi động lại tiến trình Windows Explorer (explorer.exe)..."
        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
            Start-Process "explorer.exe"
        }
        Log-Text "[✓] Đã nạp lại Windows Explorer thành công."
    }
}

# ── LOGIC MODULE QUẢN LÝ & GỠ LỖI DRIVER ──
Register-Click "btnScanFaultyDrivers" {
    Invoke-GuardedAction "Quét Driver lỗi" {
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
                Log-Text "     Trạng thái: $($d.Status) | ErrorCode: $($d.ConfigManagerErrorCode)"
                Log-Text "   ────────────────────────────────────────────────"
            }
            if ($txtStatus) { $txtStatus.Text = "Phát hiện $($faulty.Count) thiết bị lỗi" }
        }
    }
}

Register-Click "btnPnpRescan" {
    Invoke-GuardedAction "Quét lại thiết bị PnP" {
        Log-Text "[*] Đang gửi lệnh quét phần cứng Plug and Play (pnputil /scan-devices)..."
        Invoke-PnpDeviceRescan
        Log-Text "[✓] Windows đã hoàn tất quét và phát hiện lại các thiết bị phần cứng."
    }
}

Register-Click "btnOpenDeviceManager" {
    Log-Text "[*] Đang mở Trình quản lý thiết bị (devmgmt.msc)..."
    Start-Process "devmgmt.msc"
}

Register-Click "btnFixDriverUpdate" {
    Invoke-GuardedAction "Gỡ lỗi kẹt driver update" {
        Log-Text "[*] Đang giải phóng hàng đợi tải driver bị kẹt trong Windows Update..."
        if ($txtStatus) { $txtStatus.Text = "Đang sửa lỗi kẹt cập nhật driver..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }

        Reset-WindowsUpdateEngine

        Log-Text "   - Đang buộc nhận diện lại các thiết bị phần cứng..."
        Invoke-PnpDeviceRescan

        Log-Text "   - Yêu cầu Windows Update quét tìm driver thay thế mới..."
        Invoke-WindowsUpdateScan

        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Đã gỡ lỗi kẹt driver update" }
        Log-Text "[✓] Hoàn thành! Lỗi kẹt tải driver đã được dọn sạch."
    }
}

Register-Click "btnScanWindowsUpdateDrivers" {
    Invoke-GuardedAction "Quét driver từ Windows Update" {
        Invoke-WindowsUpdateScan
    }
}

Register-Click "btnCleanDriverStore" {
    Invoke-GuardedAction "Dọn dẹp DriverStore" {
        if ($txtStatus) { $txtStatus.Text = "Đang dọn dẹp DriverStore..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-PnpDriverStoreCleanup
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn dẹp DriverStore hoàn tất" }
    }
}

Register-Click "btnBackupDrivers" {
    Invoke-GuardedAction "Sao lưu Driver" {
        $dest = "C:\Backup_Drivers"
        Log-Text "[*] Đang sao lưu toàn bộ Driver của máy ra thư mục: '$dest'..."
        if ($txtStatus) { $txtStatus.Text = "Đang sao lưu driver..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }

        $res = Export-SystemDriversBackup -Destination $dest

        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($res) {
            if ($txtStatus) { $txtStatus.Text = "Sao lưu driver hoàn tất" }
            Log-Text "[✓] THÀNH CÔNG! Đã sao lưu toàn bộ driver vào: $dest"
        } else {
            if ($txtStatus) { $txtStatus.Text = "Sao lưu driver thất bại" }
            Log-Text "[❌] Lỗi trong quá trình sao lưu driver."
        }
    }
}

Register-Click "btnOpenBackupFolder" {
    $dest = "C:\Backup_Drivers"
    if (Test-Path -LiteralPath $dest) {
        Start-Process explorer.exe "`"$dest`""
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
