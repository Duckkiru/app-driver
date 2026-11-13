# ── KHỞI TẠO CÁC CONTROL TỪ XAML ──
$reader = New-Object System.Xml.XmlNodeReader $XAML
$window = [Windows.Markup.XamlReader]::Load($reader)

# Tự động co kích thước cửa sổ vừa với vùng làm việc màn hình (hỗ trợ laptop / DPI 125%-150%)
try {
    $wa = [System.Windows.SystemParameters]::WorkArea
    if ($wa.Width -gt 0 -and $window.Width -gt ($wa.Width - 24)) {
        $window.Width = [math]::Max($window.MinWidth, $wa.Width - 24)
    }
    if ($wa.Height -gt 0 -and $window.Height -gt ($wa.Height - 24)) {
        $window.Height = [math]::Max(560, $wa.Height - 24)
        $window.MinHeight = [math]::Min($window.MinHeight, $window.Height)
    }
} catch {}

# Các Control chính
$MainTabControl    = $window.FindName("MainTabControl")
$txtStatus         = $window.FindName("txtStatus")
$progressBar       = $window.FindName("progressBar")
$txtSelectionCount = $window.FindName("txtSelectionCount")
$cardsContainer    = $window.FindName("CardsContainer")

# Bảng màu Frozen Brush tĩnh tái sử dụng tối đa, loại trừ cấp phát bộ nhớ rác (GC)
$script:brushNavActive   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushNavActive.Freeze()
$script:brushNavInactive = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x64, 0x74, 0x8B)); $script:brushNavInactive.Freeze()
$script:brushTransparent = [System.Windows.Media.Brushes]::Transparent

$script:brushCardBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x11, 0x17, 0x22)); $script:brushCardBg.Freeze()
$script:brushCardBorder  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1C, 0x25, 0x36)); $script:brushCardBorder.Freeze()
$script:brushHeaderFg    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x7D, 0xD3, 0xFC)); $script:brushHeaderFg.Freeze()
$script:brushHeaderCntBg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x16, 0x1E, 0x2E)); $script:brushHeaderCntBg.Freeze()
$script:brushHeaderCntFg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x64, 0x74, 0x8B)); $script:brushHeaderCntFg.Freeze()
$script:brushSeparator   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1A, 0x22, 0x32)); $script:brushSeparator.Freeze()

$script:brushRowHover    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x19, 0x22, 0x34)); $script:brushRowHover.Freeze()
$script:brushTextWhite   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF1, 0xF5, 0xF9)); $script:brushTextWhite.Freeze()
$script:fontSegoeEmoji   = New-Object System.Windows.Media.FontFamily("Segoe UI Emoji, Segoe UI Symbol, Arial")
$script:fontSegoeUI      = New-Object System.Windows.Media.FontFamily("Segoe UI Variable Text, Segoe UI, Arial")

# Bảng màu cho Button Link Website ngoài cùng bên phải (Tối giản chuẩn WinUtil)
$script:brushLinkBtnBg        = [System.Windows.Media.Brushes]::Transparent
$script:brushLinkBtnBorder    = [System.Windows.Media.Brushes]::Transparent
$script:brushLinkBtnFg        = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x52, 0x60, 0x76)); $script:brushLinkBtnFg.Freeze()
$script:brushLinkBtnRowHover  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x94, 0xA3, 0xB8)); $script:brushLinkBtnRowHover.Freeze()

$script:brushLinkBtnHoverBg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1E, 0x29, 0x3B)); $script:brushLinkBtnHoverBg.Freeze()
$script:brushLinkBtnHoverBdr  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushLinkBtnHoverBdr.Freeze()
$script:brushLinkBtnHoverFg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushLinkBtnHoverFg.Freeze()

# Nền icon sương mờ siêu nhẹ (~5.5% trắng, không viền), nền trắng chuẩn cho Java & Update Pill gọn gàng
$script:brushIconBadgeBg        = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(14, 255, 255, 255)); $script:brushIconBadgeBg.Freeze()
$script:brushIconBadgeLightBg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(245, 255, 255, 255)); $script:brushIconBadgeLightBg.Freeze()
$script:brushIconBadgeBorder    = [System.Windows.Media.Brushes]::Transparent

# Native WPF Styles cho dòng App & nút Link (chạy 100% trong WPF C++ engine, không gọi PowerShell ScriptBlock khi di chuột)
$script:styleAppRow = New-Object System.Windows.Style([System.Windows.Controls.Border])
$script:styleAppRow.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $script:brushTransparent)))
$trigRowHover = New-Object System.Windows.Trigger
$trigRowHover.Property = [System.Windows.UIElement]::IsMouseOverProperty
$trigRowHover.Value = $true
$trigRowHover.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $script:brushRowHover)))
$script:styleAppRow.Triggers.Add($trigRowHover)
$script:styleAppRow.Seal()

$script:styleLinkBtn = New-Object System.Windows.Style([System.Windows.Controls.Border])
$script:styleLinkBtn.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $script:brushLinkBtnBg)))
$script:styleLinkBtn.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $script:brushLinkBtnBorder)))
$trigLinkHover = New-Object System.Windows.Trigger
$trigLinkHover.Property = [System.Windows.UIElement]::IsMouseOverProperty
$trigLinkHover.Value = $true
$trigLinkHover.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $script:brushLinkBtnHoverBg)))
$trigLinkHover.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $script:brushLinkBtnHoverBdr)))
$script:styleLinkBtn.Triggers.Add($trigLinkHover)
$script:styleLinkBtn.Seal()

# Style viền Card phát sáng nhẹ khi rê chuột qua nhóm danh mục
$script:brushCardHoverBorder = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x2B, 0x45, 0x68)); $script:brushCardHoverBorder.Freeze()
$script:styleCategoryCard = New-Object System.Windows.Style([System.Windows.Controls.Border])
$script:styleCategoryCard.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $script:brushCardBorder)))
$trigCardHover = New-Object System.Windows.Trigger
$trigCardHover.Property = [System.Windows.UIElement]::IsMouseOverProperty
$trigCardHover.Value = $true
$trigCardHover.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $script:brushCardHoverBorder)))
$script:styleCategoryCard.Triggers.Add($trigCardHover)
$script:styleCategoryCard.Seal()

# ── BỘ ĐIỀU KHIỂN CUỘN CON LĂN CHUỘT MƯỢT (INERTIA SMOOTH SCROLL 60-240FPS BẰNG C# THUẦN) ──
if (-not ("DuckUtil.SmoothScrollController" -as [type])) {
    try {
        $wpfSmoothRefs = @(
            [System.Windows.Controls.ScrollViewer].Assembly.Location,
            [System.Windows.UIElement].Assembly.Location,
            [System.Windows.DependencyObject].Assembly.Location,
            [System.Windows.Markup.IQueryAmbient].Assembly.Location,
            [System.Diagnostics.Stopwatch].Assembly.Location,
            [System.Object].Assembly.Location
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

        $smoothScrollCs = @"
using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace DuckUtil {
    public sealed class SmoothScrollController {
        private readonly ScrollViewer _sv;
        private double _currentOffset;
        private double _targetOffset;
        private double _lastAppliedOffset;
        private bool _isAnimating;
        private readonly Stopwatch _sw = new Stopwatch();
        private double _lastTimeSec;

        private SmoothScrollController(ScrollViewer sv) {
            _sv = sv;
            _currentOffset = sv.VerticalOffset;
            _targetOffset = sv.VerticalOffset;
            _lastAppliedOffset = sv.VerticalOffset;
            _sv.PreviewMouseWheel += OnPreviewMouseWheel;
        }

        public static SmoothScrollController Attach(ScrollViewer sv) {
            if (sv == null) return null;
            return new SmoothScrollController(sv);
        }

        private void OnPreviewMouseWheel(object sender, MouseWheelEventArgs e) {
            if (e == null || e.Handled) return;
            if (Keyboard.Modifiers != ModifierKeys.None) return;

            double maxScroll = _sv.ScrollableHeight;
            if (maxScroll <= 0) return;

            if (!_isAnimating || Math.Abs(_sv.VerticalOffset - _lastAppliedOffset) > 2.5) {
                _currentOffset = _sv.VerticalOffset;
                _targetOffset = _sv.VerticalOffset;
            }

            double step = -e.Delta * 0.85;
            _targetOffset = Math.Max(0.0, Math.Min(maxScroll, _targetOffset + step));
            e.Handled = true;

            if (!_isAnimating) {
                _isAnimating = true;
                _sw.Restart();
                _lastTimeSec = 0.0;
                CompositionTarget.Rendering += OnRendering;
            }
        }

        private void OnRendering(object sender, EventArgs e) {
            if (!_sv.IsLoaded) {
                StopAnimation();
                return;
            }

            if (Math.Abs(_sv.VerticalOffset - _lastAppliedOffset) > 2.5) {
                _currentOffset = _sv.VerticalOffset;
                _targetOffset = _sv.VerticalOffset;
                StopAnimation();
                return;
            }

            double nowSec = _sw.Elapsed.TotalSeconds;
            double dt = nowSec - _lastTimeSec;
            _lastTimeSec = nowSec;
            if (dt <= 0.0 || dt > 0.1) dt = 0.016;

            double maxScroll = _sv.ScrollableHeight;
            if (_targetOffset > maxScroll) _targetOffset = maxScroll;
            if (_targetOffset < 0.0) _targetOffset = 0.0;

            double diff = _targetOffset - _currentOffset;
            if (Math.Abs(diff) < 0.25) {
                _currentOffset = _targetOffset;
                _lastAppliedOffset = _currentOffset;
                _sv.ScrollToVerticalOffset(_currentOffset);
                StopAnimation();
                return;
            }

            double factor = 1.0 - Math.Exp(-17.0 * dt);
            _currentOffset += diff * factor;
            _lastAppliedOffset = _currentOffset;
            _sv.ScrollToVerticalOffset(_currentOffset);
        }

        private void StopAnimation() {
            if (_isAnimating) {
                _isAnimating = false;
                CompositionTarget.Rendering -= OnRendering;
                _sw.Stop();
            }
        }
    }
}
"@
        Add-Type -TypeDefinition $smoothScrollCs -ReferencedAssemblies $wpfSmoothRefs -ErrorAction SilentlyContinue
    } catch {}
}

$appsScrollViewer = $window.FindName("AppsScrollViewer")
if ($appsScrollViewer -and ("DuckUtil.SmoothScrollController" -as [type])) {
    $script:smoothScrollCtrl = [DuckUtil.SmoothScrollController]::Attach($appsScrollViewer)
}

# Tối ưu giới hạn kết nối mạng song song cho tiến trình tải icon nền
try {
    [System.Net.ServicePointManager]::DefaultConnectionLimit = 24
    [System.Net.ServicePointManager]::Expect100Continue = $false
} catch {}

function Import-LocalIconBitmap {
    param(
        [string]$Path,
        [string]$CacheKey = ""
    )
    if (-not [string]::IsNullOrWhiteSpace($CacheKey)) {
        $cached = $null
        if ($script:remoteBmpCache -and $script:remoteBmpCache.TryGetValue($CacheKey, [ref]$cached)) {
            return $cached
        }
    }
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.File]::Exists($Path)) { return $null }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if (-not $bytes -or $bytes.Length -le 64) { return $null }
        $ms = [System.IO.MemoryStream]::new($bytes)
        try {
            $bmp = [System.Windows.Media.Imaging.BitmapImage]::new()
            $bmp.BeginInit()
            $bmp.StreamSource = $ms
            $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.DecodePixelWidth = 36
            $bmp.EndInit()
            $bmp.Freeze()
            if (-not [string]::IsNullOrWhiteSpace($CacheKey) -and $script:remoteBmpCache) {
                $script:remoteBmpCache[$CacheKey] = $bmp
            }
            return $bmp
        } finally {
            $ms.Dispose()
        }
    } catch {
        try { [System.IO.File]::Delete($Path) } catch {}
        return $null
    }
}

# Hàng đợi tải icon bất đồng bộ bằng Task nền .NET (không dùng Add-Type csc.exe, không khóa luồng UI hay PowerShell Runspace)
$script:pendingIconSaves = [System.Collections.Generic.List[hashtable]]::new()
$script:inFlightIconTasks = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Start-BackgroundIconDownload {
    param(
        [string]$Url,
        [string]$DestPath
    )
    if ([string]::IsNullOrWhiteSpace($Url) -or [string]::IsNullOrWhiteSpace($DestPath)) { return $null }
    $existing = $null
    if ($script:inFlightIconTasks.TryGetValue($Url, [ref]$existing)) {
        return $existing
    }
    try {
        $wc = [System.Net.WebClient]::new()
        $wc.Proxy = $null
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) DuckUtil/3.5")
        $task = $wc.DownloadDataTaskAsync([uri]$Url)
        $info = @{
            Url      = $Url
            DestPath = $DestPath
            Client   = $wc
            Task     = $task
            Saved    = $false
        }
        $script:inFlightIconTasks[$Url] = $info
        return $info
    } catch {
        return $null
    }
}

function Flush-PendingIconCache {
    if (-not $script:pendingIconSaves -or $script:pendingIconSaves.Count -eq 0) { return }
    if ($script:isScanningApps -or $script:isActionRunning) { return }
    $inFlightCount = 0
    $decodedCount  = 0
    for ($idx = $script:pendingIconSaves.Count - 1; $idx -ge 0; $idx--) {
        $entry = $script:pendingIconSaves[$idx]
        if (-not $entry.DownloadInfo -and $entry.Url) {
            if ($inFlightCount -ge 10 -and -not $script:inFlightIconTasks.ContainsKey($entry.Url)) {
                continue
            }
            $entry.DownloadInfo = Start-BackgroundIconDownload -Url $entry.Url -DestPath $entry.DestPath
        }
        $dlInfo = $entry.DownloadInfo
        if ($dlInfo -and $dlInfo.Task) {
            if (-not $dlInfo.Task.IsCompleted) {
                $inFlightCount++
                continue
            }
            if (-not $dlInfo.Saved) {
                $dlInfo.Saved = $true
                if ($dlInfo.Task.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                    try {
                        $data = $dlInfo.Task.Result
                        if ($data -and $data.Length -gt 64 -and -not [System.IO.File]::Exists($entry.DestPath)) {
                            $tmpFile = "$($entry.DestPath).$([guid]::NewGuid().ToString('N')).tmp"
                            [System.IO.File]::WriteAllBytes($tmpFile, $data)
                            Move-Item -LiteralPath $tmpFile -Destination $entry.DestPath -Force -ErrorAction SilentlyContinue
                        }
                    } catch {}
                }
                try { if ($dlInfo.Client) { $dlInfo.Client.Dispose() } } catch {}
            }
        }
        if ([System.IO.File]::Exists($entry.DestPath) -or ($script:remoteBmpCache -and $script:remoteBmpCache.ContainsKey($entry.CacheKey))) {
            if ($decodedCount -ge 20) { continue }
            $bmp = Import-LocalIconBitmap -Path $entry.DestPath -CacheKey $entry.CacheKey
            if ($bmp -and $bmp.PixelWidth -gt 0) {
                $decodedCount++
                if (-not [System.IO.File]::Exists($entry.DestPath)) {
                    Save-BitmapToCacheAtomic -BitmapSource $bmp -DestPath $entry.DestPath
                }
                if ($entry.Img) {
                    $entry.Img.Source = $bmp
                    $entry.Img.Visibility = [System.Windows.Visibility]::Visible
                }
                if ($entry.Fallback) {
                    $entry.Fallback.Visibility = [System.Windows.Visibility]::Collapsed
                }
            }
        }
        $script:pendingIconSaves.RemoveAt($idx)
    }
}
$script:cornerIconBadge         = New-Object System.Windows.CornerRadius(5)
$script:brushUpdateBadgeBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(28, 0xF8, 0x71, 0x71)); $script:brushUpdateBadgeBg.Freeze()
$script:brushUpdateBadgeBorder  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(85, 0xF8, 0x71, 0x71)); $script:brushUpdateBadgeBorder.Freeze()
$script:brushUpdateBadgeFg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xFC, 0xA5, 0xA5)); $script:brushUpdateBadgeFg.Freeze()

# Cấu trúc hình học tái sử dụng (Shared Layout Geometries)
$marginCardBorder = New-Object System.Windows.Thickness(4)
$paddingCard      = New-Object System.Windows.Thickness(10, 8, 10, 10)
$marginHeaderGrid = New-Object System.Windows.Thickness(2, 0, 2, 6)
$marginSeparator  = New-Object System.Windows.Thickness(0, 1, 0, 5)
$marginRowBorder  = New-Object System.Windows.Thickness(0, 1, 0, 1)
$paddingRow       = New-Object System.Windows.Thickness(5, 0, 4, 0)
$marginIcon       = New-Object System.Windows.Thickness(7, 0, 8, 0)
$cornerCard       = New-Object System.Windows.CornerRadius(8)
$cornerRow        = New-Object System.Windows.CornerRadius(5)
$thicknessZero    = New-Object System.Windows.Thickness(0)
$thicknessOne     = New-Object System.Windows.Thickness(1)

# Thư mục lưu cache biểu tượng ứng dụng cục bộ
$iconsCacheDir = Join-Path $env:LOCALAPPDATA "DuckUtil\Icons"
if (-not (Test-Path -LiteralPath $iconsCacheDir)) {
    try { New-Item -ItemType Directory -Path $iconsCacheDir -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
} else {
    # Tự động dọn dẹp các icon cache rỗng / bị hỏng / quá nhỏ từ phiên bản cũ
    try {
        Get-ChildItem -Path $iconsCacheDir -Filter "*.png" -ErrorAction SilentlyContinue | Where-Object {
            $_.Length -le 230 -or $_.Length -eq 588
        } | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {}

    # Đồng bộ cache icon thông minh theo từng ứng dụng (chỉ xóa icon của app có URL thay đổi, không bao giờ xóa toàn bộ cache)
    try {
        $mapFile = Join-Path $iconsCacheDir "cache.icons.map.txt"
        $oldMap = @{}
        if (Test-Path -LiteralPath $mapFile) {
            foreach ($line in [System.IO.File]::ReadAllLines($mapFile)) {
                $sepIdx = $line.IndexOf('=')
                if ($sepIdx -gt 0) {
                    $oldMap[$line.Substring(0, $sepIdx)] = $line.Substring($sepIdx + 1)
                }
            }
        }
        $newLines = [System.Collections.Generic.List[string]]::new()
        $mapChanged = $false
        if ($AppCatalog) {
            foreach ($appItem in $AppCatalog) {
                $appKey = "$($appItem.ID)"
                $appVal = "$($appItem.IconUrl)|$($appItem.Domain)"
                $newLines.Add("$appKey=$appVal")
                if ($oldMap.ContainsKey($appKey)) {
                    if ($oldMap[$appKey] -ne $appVal) {
                        $staleIcon = Join-Path $iconsCacheDir "$appKey.png"
                        if (Test-Path -LiteralPath $staleIcon) {
                            Remove-Item -LiteralPath $staleIcon -Force -ErrorAction SilentlyContinue
                        }
                        $mapChanged = $true
                    }
                } else {
                    $mapChanged = $true
                }
            }
        }
        if ($mapChanged -or -not (Test-Path -LiteralPath $mapFile)) {
            [System.IO.File]::WriteAllLines($mapFile, $newLines, [System.Text.Encoding]::UTF8)
        }
    } catch {}
}

function Save-BitmapToCacheAtomic {
    param($BitmapSource, [string]$DestPath)
    if (-not $BitmapSource -or [string]::IsNullOrWhiteSpace($DestPath) -or (Test-Path -LiteralPath $DestPath)) { return }
    try {
        if ($BitmapSource.PixelWidth -le 0 -or $BitmapSource.PixelHeight -le 0) { return }
        $tmpPath = "$DestPath.$([guid]::NewGuid().ToString('N')).tmp"
        $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($BitmapSource))
        $fs = $null
        try {
            $fs = [System.IO.File]::OpenWrite($tmpPath)
            $encoder.Save($fs)
        } finally {
            if ($fs) { $fs.Dispose() }
        }
        if ((Test-Path -LiteralPath $tmpPath) -and (Get-Item -LiteralPath $tmpPath).Length -gt 64) {
            Move-Item -LiteralPath $tmpPath -Destination $DestPath -Force -ErrorAction SilentlyContinue
        } elseif (Test-Path -LiteralPath $tmpPath) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
    } catch {
        if ($tmpPath -and (Test-Path -LiteralPath $tmpPath)) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Trình khóa thực thi đơn nhất (Re-entrancy Guard) chống xung đột tiến trình
$script:isActionRunning = $false

function Invoke-GuardedAction {
    param(
        [string]$ActionName,
        [scriptblock]$Action,
        [switch]$DeferExpand
    )
    if ($script:isActionRunning) {
        Log-Text "[⚠️] Đang có một tác vụ khác đang thực thi ($ActionName). Vui lòng đợi!"
        return
    }
    if (-not $DeferExpand) {
        # Tự động mở rộng Terminal Log khi bắt đầu thực thi hành động để người dùng theo dõi tiến trình
        Expand-TerminalLog
    }
    $script:isActionRunning = $true
    try {
        & $Action
    } catch {
        Log-Text "[!] Lỗi khi thực hiện '$ActionName': $($_.Exception.Message)"
    } finally {
        $script:isActionRunning = $false
        try { Flush-PendingIconCache } catch {}
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# Khóa an toàn các module bảo trì hệ thống & driver khi chưa mở rộng sử dụng
$script:LockMaintenanceTabs = $true
$script:LockedButtonActions = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Test-MaintenanceFeatureLocked {
    param([string]$FeatureName)
    if ($script:LockMaintenanceTabs) {
        Log-Text "[LOCK] Tính năng '$FeatureName' hiện đang được tạm khóa."
        if ($txtStatus) { $txtStatus.Text = "Tính năng '$FeatureName' đang tạm khóa" }
        return $true
    }
    return $false
}

# Hàm an toàn gắn sự kiện Click cho nút (hỗ trợ khóa theo nhóm tính năng)
function Register-Click {
    param(
        [string]$ButtonName,
        [scriptblock]$Action,
        [string]$LockGroup = ""
    )
    $btn = $window.FindName($ButtonName)
    if ($btn) {
        if (-not [string]::IsNullOrWhiteSpace($LockGroup)) {
            $script:LockedButtonActions[$ButtonName] = @{
                Group  = $LockGroup
                Action = $Action
            }
            if ($script:LockMaintenanceTabs) {
                $btn.IsEnabled = $false
            }
            $btn.Add_Click({
                param($sender, $e)
                $entry = $script:LockedButtonActions[$sender.Name]
                if ($entry -and (Test-MaintenanceFeatureLocked $entry.Group)) { return }
                if ($entry -and $entry.Action) { & $entry.Action }
            })
        } else {
            $btn.Add_Click($Action)
        }
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
    if ($script:LockMaintenanceTabs -and ($index -eq 1 -or $index -eq 2)) {
        $feature = if ($index -eq 1) { "Gỡ lỗi & Hệ thống" } else { "Quản lý Driver" }
        Test-MaintenanceFeatureLocked $feature | Out-Null
        return
    }
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
Register-Click "navBtnRepair"  -LockGroup "Gỡ lỗi & Hệ thống" { Set-ActiveTab 1 $navBtnRepair }
Register-Click "navBtnDrivers" -LockGroup "Quản lý Driver"    { Set-ActiveTab 2 $navBtnDrivers }

# Đồng bộ trạng thái tab khởi tạo ban đầu (Section 3.4)
Set-ActiveTab 0 $navBtnApps

# ── CỬA SỔ TERMINAL CHẠY NỀN RIÊNG BIỆT (CHUẨN WINUTIL) ──
function Expand-TerminalLog {
    # Terminal Log hiện được tách sang cửa sổ Console chạy nền riêng biệt
}

# Hàm ánh xạ icon emoji/glyph đặc trưng cho ứng dụng và danh mục (hiển thị tức thì 0ms, không bao giờ bị khuyết icon)
function Get-AppFallbackGlyph {
    param([string]$AppName, [string]$Category)
    $nameLower = if ($AppName) { $AppName.ToLowerInvariant() } else { "" }
    if ($nameLower -match 'chrome') { return [char]::ConvertFromUtf32(0x1F310) }
    if ($nameLower -match 'firefox') { return [char]::ConvertFromUtf32(0x1F98A) }
    if ($nameLower -match 'brave') { return [char]::ConvertFromUtf32(0x1F981) }
    if ($nameLower -match 'tor') { return [char]::ConvertFromUtf32(0x1F9C5) }
    if ($nameLower -match 'opera') { return [char]::ConvertFromUtf32(0x1F534) }
    if ($nameLower -match 'vivaldi') { return [char]::ConvertFromUtf32(0x1F3AD) }
    if ($nameLower -match 'librewolf') { return [char]::ConvertFromUtf32(0x1F43A) }
    if ($nameLower -match 'discord') { return [char]::ConvertFromUtf32(0x1F4AC) }
    if ($nameLower -match 'telegram') { return [char]::ConvertFromUtf32(0x2708) }
    if ($nameLower -match 'zalo') { return [char]::ConvertFromUtf32(0x1F4AC) }
    if ($nameLower -match 'slack') { return [char]::ConvertFromUtf32(0x1F4BC) }
    if ($nameLower -match 'teams') { return [char]::ConvertFromUtf32(0x1F465) }
    if ($nameLower -match 'whatsapp') { return [char]::ConvertFromUtf32(0x1F4F1) }
    if ($nameLower -match 'zoom') { return [char]::ConvertFromUtf32(0x1F4F9) }
    if ($nameLower -match 'vs code|visual studio') { return [char]::ConvertFromUtf32(0x1F4BB) }
    if ($nameLower -match 'git') { return [char]::ConvertFromUtf32(0x1F419) }
    if ($nameLower -match 'terminal') { return [char]::ConvertFromUtf32(0x1F4DF) }
    if ($nameLower -match 'python') { return [char]::ConvertFromUtf32(0x1F40D) }
    if ($nameLower -match 'node') { return [char]::ConvertFromUtf32(0x1F7E2) }
    if ($nameLower -match 'docker') { return [char]::ConvertFromUtf32(0x1F433) }
    if ($nameLower -match 'notepad\+\+') { return [char]::ConvertFromUtf32(0x1F4DD) }
    if ($nameLower -match 'postman') { return [char]::ConvertFromUtf32(0x1F680) }
    if ($nameLower -match 'dbeaver') { return [char]::ConvertFromUtf32(0x1F9AB) }
    if ($nameLower -match 'rustup|\brust\b') { return [char]::ConvertFromUtf32(0x1F980) }
    if ($nameLower -match 'go lang|golang') { return [char]::ConvertFromUtf32(0x1F439) }
    if ($nameLower -match '7-zip') { return [char]::ConvertFromUtf32(0x1F5DC) }
    if ($nameLower -match 'winrar') { return [char]::ConvertFromUtf32(0x1F4E6) }
    if ($nameLower -match 'everything') { return [char]::ConvertFromUtf32(0x1F50D) }
    if ($nameLower -match 'powertoys') { return [char]::ConvertFromUtf32(0x26A1) }
    if ($nameLower -match 'flow launcher') { return [char]::ConvertFromUtf32(0x1F680) }
    if ($nameLower -match 'revo') { return [char]::ConvertFromUtf32(0x1F9F9) }
    if ($nameLower -match 'treesize') { return [char]::ConvertFromUtf32(0x1F4CA) }
    if ($nameLower -match 'sharex') { return [char]::ConvertFromUtf32(0x1F4F8) }
    if ($nameLower -match 'bleachbit') { return [char]::ConvertFromUtf32(0x1F9FC) }
    if ($nameLower -match 'fancontrol') { return [char]::ConvertFromUtf32(0x1F300) }
    if ($nameLower -match 'spotify') { return [char]::ConvertFromUtf32(0x1F3B5) }
    if ($nameLower -match 'vlc') { return [char]::ConvertFromUtf32(0x1F538) }
    if ($nameLower -match 'obs') { return [char]::ConvertFromUtf32(0x1F3AC) }
    if ($nameLower -match 'steam') { return [char]::ConvertFromUtf32(0x1F579) }
    if ($nameLower -match 'epic') { return [char]::ConvertFromUtf32(0x1F3AE) }
    if ($nameLower -match 'onedrive|gdrive|drive|dropbox') { return [char]::ConvertFromUtf32(0x2601) }
    if ($nameLower -match 'rustdesk|anydesk|ultraviewer|teamviewer') { return [char]::ConvertFromUtf32(0x1F5A5) }
    if ($nameLower -match 'afterburner') { return [char]::ConvertFromUtf32(0x26A1) }
    if ($nameLower -match 'gimp|krita') { return [char]::ConvertFromUtf32(0x1F3A8) }
    if ($nameLower -match 'blender') { return [char]::ConvertFromUtf32(0x1F3A8) }
    if ($nameLower -match 'inkscape') { return [char]::ConvertFromUtf32(0x2712) }
    if ($nameLower -match 'java|openjdk|temurin') { return [char]::ConvertFromUtf32(0x2615) }
    if ($nameLower -match '\.net|desktopruntime') { return [char]::ConvertFromUtf32(0x1F7E3) }
    if ($nameLower -match 'vc\+\+|visual c\+\+') { return [char]::ConvertFromUtf32(0x2699) }
    if ($nameLower -match 'directx') { return [char]::ConvertFromUtf32(0x1F3AE) }
    if ($nameLower -match 'cpu-z|hwmonitor') { return [char]::ConvertFromUtf32(0x1F39B) }

    if ($Category -match 'Antigravity') { return [char]::ConvertFromUtf32(0x1F680) }
    if ($Category -match 'JetBrains') { return [char]::ConvertFromUtf32(0x1F9E9) }
    if ($Category -match 'AI|Assistant') { return [char]::ConvertFromUtf32(0x1F916) }
    if ($Category -match 'Database|DevOps') { return [char]::ConvertFromUtf32(0x1F5C4) }
    if ($Category -match 'Minecraft|Modding') { return [char]::ConvertFromUtf32(0x26CF) }
    if ($Category -match 'Download') { return [char]::ConvertFromUtf32(0x2B07) }
    if ($Category -match 'Web|Browser') { return [char]::ConvertFromUtf32(0x1F310) }
    if ($Category -match 'Chat|Liên|Communication') { return [char]::ConvertFromUtf32(0x1F4AC) }
    if ($Category -match 'Remote') { return [char]::ConvertFromUtf32(0x1F5A5) }
    if ($Category -match 'Dev|Triển|Development') { return [char]::ConvertFromUtf32(0x1F4BB) }
    if ($Category -match 'Java') { return [char]::ConvertFromUtf32(0x2615) }
    if ($Category -match '\.NET') { return [char]::ConvertFromUtf32(0x1F7E3) }
    if ($Category -match 'Hardware|Monitoring') { return [char]::ConvertFromUtf32(0x1F39B) }
    if ($Category -match 'C\+\+|System Runtimes') { return [char]::ConvertFromUtf32(0x2699) }
    if ($Category -match 'Tiện|Thống|Utilities|Utility') { return [char]::ConvertFromUtf32(0x1F6E0) }
    if ($Category -match 'Graphic|Design') { return [char]::ConvertFromUtf32(0x1F3A8) }
    if ($Category -match 'Audio|Video|Media') { return [char]::ConvertFromUtf32(0x1F3AC) }
    if ($Category -match 'Phòng|Liệu|Documents|Office') { return [char]::ConvertFromUtf32(0x1F4C4) }
    if ($Category -match 'Chơi|Game|Launcher') { return [char]::ConvertFromUtf32(0x1F3AE) }
    if ($Category -match 'Trữ|Tệp|Storage|File|Transfer') { return [char]::ConvertFromUtf32(0x2601) }
    if ($Category -match 'Security|Bảo Mật|Network|Mạng') { return [char]::ConvertFromUtf32(0x1F6E1) }
    if ($Category -match 'Core|Runtimes|Thư Viện') { return [char]::ConvertFromUtf32(0x2699) }

    return [char]::ConvertFromUtf32(0x1F4E6)
}

# ── MASONRY CÂN BẰNG CHIỀU CAO 4 CỘT TỰ ĐỘNG (LOẠI BỎ TRIỆT ĐỂ KHOẢNG TRỐNG) ──
$script:colHeights = @(0, 0, 0, 0)

# ── SINH CÁC CARD ỨNG DỤNG BỐ CỤC 4 CỘT HIỆU NĂNG CAO ──
$allCheckBoxes   = [System.Collections.Generic.List[object]]::new()
$allItemBorders  = [System.Collections.Generic.List[object]]::new()

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

# 4 cột dọc phân bố đều các card danh mục (Chiều cao tự nhiên, không cố định, triệt tiêu khoảng trống thừa)
$cardCols = @(
    $window.FindName("CardsCol0"),
    $window.FindName("CardsCol1"),
    $window.FindName("CardsCol2"),
    $window.FindName("CardsCol3")
)

# Cache BitmapImage từ xa theo URL trong RAM để cắt giảm triệt để request mạng trùng lặp
$script:remoteBmpCache = [System.Collections.Generic.Dictionary[string, System.Windows.Media.Imaging.BitmapImage]]::new([System.StringComparer]::OrdinalIgnoreCase)

# Các hằng số hình học & delegate dùng chung cho toàn bộ 190 dòng (tránh gọi cmdlet New-Object hàng ngàn lần khi khởi tạo)
$glCol0             = [System.Windows.GridLength]::new(20, [System.Windows.GridUnitType]::Pixel)
$glCol1             = [System.Windows.GridLength]::new(23, [System.Windows.GridUnitType]::Pixel)
$glCol2             = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
$glCol3             = [System.Windows.GridLength]::new(22, [System.Windows.GridUnitType]::Pixel)
$glAuto             = [System.Windows.GridLength]::Auto
$marginCardBottom   = [System.Windows.Thickness]::new(0, 0, 0, 10)
$paddingHeaderCnt   = [System.Windows.Thickness]::new(6, 1, 6, 1)
$marginNameText     = [System.Windows.Thickness]::new(5, 0, 4, 0)
$paddingUpdateBadge = [System.Windows.Thickness]::new(5, 1, 5, 1)
$marginUpdateBadge  = [System.Windows.Thickness]::new(2, 0, 4, 0)
$marginLinkIcon     = [System.Windows.Thickness]::new(0, -1, 0, 0)
$cornerFour         = [System.Windows.CornerRadius]::new(4)
$strOpenLinkGlyph   = [string][char]0x2197

$script:cbChangedHandler = [System.Windows.RoutedEventHandler]{ Update-SelectionCount }
$script:linkClickHandler = [System.Windows.Input.MouseButtonEventHandler]{
    param($s, $e)
    $e.Handled = $true
    if ($script:isScanningApps -or $script:isActionRunning) { return }
    $domain = if ($s.Tag -and $s.Tag.Url) { $s.Tag.Url } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($domain)) {
        $targetUrl = if ($domain.StartsWith("http")) { $domain } else { "https://$domain" }
        try {
            Start-Process $targetUrl
        } catch {
            Log-Text "[!] Không thể mở trang web: $targetUrl"
        }
    }
}
$script:rowClickHandler = [System.Windows.Input.MouseButtonEventHandler]{
    param($sender, $e)
    if ($e.Handled) { return }
    if ($script:isScanningApps -or $script:isActionRunning) { return }

    $src = $e.OriginalSource
    $isCb = $false
    $node = $src
    while ($node -ne $null -and $node -ne $sender) {
        if ($node -is [System.Windows.Controls.CheckBox]) {
            $isCb = $true
            break
        }
        if ($node -is [System.Windows.Media.Visual]) {
            $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
        } else {
            break
        }
    }
    if ($isCb) { return }

    if ($sender.Tag -and $sender.Tag.CheckBox) {
        $targetCb = $sender.Tag.CheckBox
        $targetCb.IsChecked = -not $targetCb.IsChecked
    }
}

# Gom nhóm sẵn ứng dụng theo Category bằng Dictionary O(1)
$appsByCategory = @{}
foreach ($item in $AppCatalog) {
    if (-not $appsByCategory.ContainsKey($item.Category)) {
        $appsByCategory[$item.Category] = [System.Collections.Generic.List[object]]::new()
    }
    $appsByCategory[$item.Category].Add($item)
}

foreach ($cat in $categories) {
    $cardBorder = [System.Windows.Controls.Border]::new()
    $cardBorder.Background = $script:brushCardBg
    $cardBorder.Style = $script:styleCategoryCard
    $cardBorder.BorderThickness = $thicknessOne
    $cardBorder.CornerRadius = $cornerCard
    $cardBorder.Margin = $marginCardBottom
    $cardBorder.Padding = $paddingCard
    $cardBorder.Height = [double]::NaN
    $cardBorder.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch

    $cardStack = [System.Windows.Controls.StackPanel]::new()
    $appsInCat = $appsByCategory[$cat]

    # Header Card (Tiêu đề bên trái + Badge đếm tối giản bên phải)
    $headerGrid = [System.Windows.Controls.Grid]::new()
    $headerGrid.Margin = $marginHeaderGrid

    $headerText = [System.Windows.Controls.TextBlock]::new()
    $headerText.Text = $cat
    $headerText.FontSize = 12
    $headerText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $headerText.Foreground = $script:brushHeaderFg
    $headerText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $headerText.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    [void]$headerGrid.Children.Add($headerText)

    $headerCountBadge = [System.Windows.Controls.Border]::new()
    $headerCountBadge.Background = $script:brushHeaderCntBg
    $headerCountBadge.CornerRadius = $cornerFour
    $headerCountBadge.Padding = $paddingHeaderCnt
    $headerCountBadge.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $headerCountBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $headerCountText = [System.Windows.Controls.TextBlock]::new()
    $headerCountText.Text = "$($appsInCat.Count)"
    $headerCountText.FontSize = 10
    $headerCountText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $headerCountText.Foreground = $script:brushHeaderCntFg
    $headerCountBadge.Child = $headerCountText
    [void]$headerGrid.Children.Add($headerCountBadge)

    $separator = [System.Windows.Controls.Border]::new()
    $separator.Height = 1
    $separator.Background = $script:brushSeparator
    $separator.Margin = $marginSeparator

    [void]$cardStack.Children.Add($headerGrid)
    [void]$cardStack.Children.Add($separator)

    # Từng dòng App: CheckBox + Logo (nền mờ nhẹ) + Tên + Nút Link tối giản
    foreach ($app in $appsInCat) {
        $rowBorder = [System.Windows.Controls.Border]::new()
        $rowBorder.Height = 27
        $rowBorder.CornerRadius = $cornerRow
        $rowBorder.Padding = $paddingRow
        $rowBorder.Margin = $marginRowBorder
        $rowBorder.Style = $script:styleAppRow
        $rowBorder.Cursor = [System.Windows.Input.Cursors]::Hand

        $rowBorder.Tag = @{
            App              = $app
            Status           = "NONE"
            DetectedId       = $null
            InstalledVersion = $null
            CardBorder       = $cardBorder
        }

        # Grid 4 cột cố định tỉ lệ, triệt tiêu hoàn toàn hiện tượng lệch dòng
        $rowGrid = [System.Windows.Controls.Grid]::new()
        $rowGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $col0 = [System.Windows.Controls.ColumnDefinition]::new(); $col0.Width = $glCol0
        $col1 = [System.Windows.Controls.ColumnDefinition]::new(); $col1.Width = $glCol1
        $col2 = [System.Windows.Controls.ColumnDefinition]::new(); $col2.Width = $glCol2
        $col3 = [System.Windows.Controls.ColumnDefinition]::new(); $col3.Width = $glCol3
        [void]$rowGrid.ColumnDefinitions.Add($col0)
        [void]$rowGrid.ColumnDefinitions.Add($col1)
        [void]$rowGrid.ColumnDefinitions.Add($col2)
        [void]$rowGrid.ColumnDefinitions.Add($col3)

        # 1. CheckBox
        $cb = [System.Windows.Controls.CheckBox]::new()
        $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $cb.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $cb.Margin = $thicknessZero
        $cb.Tag = $rowBorder.Tag
        $cb.Add_Checked($script:cbChangedHandler)
        $cb.Add_Unchecked($script:cbChangedHandler)
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        [void]$rowGrid.Children.Add($cb)
        $allCheckBoxes.Add($cb)
        $rowBorder.Tag["CheckBox"] = $cb

        # 2. Khung đỡ Logo (nền trắng chuẩn cho Java / logo tối màu, nền sương mờ nhẹ cho app thường)
        $useLightBadge = ($app.IconBg -eq "light") -or ($cat -eq "Java Runtimes")
        $iconBadge = [System.Windows.Controls.Border]::new()
        $iconBadge.Width = 20
        $iconBadge.Height = 20
        $iconBadge.CornerRadius = $script:cornerIconBadge
        $iconBadge.Background = if ($useLightBadge) { $script:brushIconBadgeLightBg } else { $script:brushIconBadgeBg }
        $iconBadge.BorderBrush = $script:brushIconBadgeBorder
        $iconBadge.BorderThickness = $thicknessZero
        $iconBadge.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $iconBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $iconInnerGrid = [System.Windows.Controls.Grid]::new()
        $iconInnerGrid.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $iconInnerGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $fallbackGlyph = [System.Windows.Controls.TextBlock]::new()
        $fallbackGlyph.Text = Get-AppFallbackGlyph -AppName $app.Name -Category $cat
        $fallbackGlyph.FontFamily = $script:fontSegoeEmoji
        $fallbackGlyph.FontSize = 10
        $fallbackGlyph.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $fallbackGlyph.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [void]$iconInnerGrid.Children.Add($fallbackGlyph)

        $img = [System.Windows.Controls.Image]::new()
        $imgDim = if ($useLightBadge) { 15 } else { 17 }
        $img.Width = $imgDim; $img.Height = $imgDim
        $img.Stretch = [System.Windows.Media.Stretch]::Uniform
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::HighQuality)
        $img.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $img.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $img.Visibility = [System.Windows.Visibility]::Collapsed

        [void]$iconInnerGrid.Children.Add($img)
        $iconBadge.Child = $iconInnerGrid

        $remoteIconTarget = if (-not [string]::IsNullOrWhiteSpace($app.IconUrl)) {
            $app.IconUrl
        } elseif (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
            "https://www.google.com/s2/favicons?domain=$($app.Domain)&sz=128"
        } else {
            $null
        }
        $iconCacheKey = if ($remoteIconTarget) { $remoteIconTarget } else { "$($app.ID)" }
        $localIconPath = Join-Path $iconsCacheDir "$($app.ID).png"

        $loadedBmp = Import-LocalIconBitmap -Path $localIconPath -CacheKey $iconCacheKey
        if ($loadedBmp -and $loadedBmp.PixelWidth -gt 0) {
            $img.Source = $loadedBmp
            $fallbackGlyph.Visibility = [System.Windows.Visibility]::Collapsed
            $img.Visibility = [System.Windows.Visibility]::Visible
            if (-not [System.IO.File]::Exists($localIconPath)) {
                Save-BitmapToCacheAtomic -BitmapSource $loadedBmp -DestPath $localIconPath
            }
        } elseif ($remoteIconTarget) {
            $script:pendingIconSaves.Add(@{
                Url          = $remoteIconTarget
                CacheKey     = $iconCacheKey
                DestPath     = $localIconPath
                DownloadInfo = $null
                Img          = $img
                Fallback     = $fallbackGlyph
            })
        }
        [System.Windows.Controls.Grid]::SetColumn($iconBadge, 1)
        [void]$rowGrid.Children.Add($iconBadge)

        # 3. Tên ứng dụng + Badge phiên bản mới gọn gàng (tránh cắt tên App khi cột hẹp)
        $nameAreaGrid = [System.Windows.Controls.Grid]::new()
        $nameCol0 = [System.Windows.Controls.ColumnDefinition]::new(); $nameCol0.Width = $glCol2
        $nameCol1 = [System.Windows.Controls.ColumnDefinition]::new(); $nameCol1.Width = $glAuto
        [void]$nameAreaGrid.ColumnDefinitions.Add($nameCol0)
        [void]$nameAreaGrid.ColumnDefinitions.Add($nameCol1)

        $nameText = [System.Windows.Controls.TextBlock]::new()
        $nameText.Text = $app.Name
        $nameText.Foreground = $script:brushTextWhite
        $nameText.FontSize = 12
        $nameText.FontWeight = [System.Windows.FontWeights]::SemiBold
        $nameText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $nameText.Margin = $marginNameText
        $nameText.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $idnPrefix = if ($app.IDn) { "[#$($app.IDn)] " } else { "" }
        $nameText.ToolTip = "$idnPrefix$($app.Name)`nID: $($app.ID)"
        $rowBorder.ToolTip = $nameText.ToolTip
        [System.Windows.Controls.Grid]::SetColumn($nameText, 0)
        [void]$nameAreaGrid.Children.Add($nameText)

        $updateBadge = [System.Windows.Controls.Border]::new()
        $updateBadge.Background = $script:brushUpdateBadgeBg
        $updateBadge.BorderBrush = $script:brushUpdateBadgeBorder
        $updateBadge.BorderThickness = $thicknessOne
        $updateBadge.CornerRadius = $script:cornerIconBadge
        $updateBadge.Padding = $paddingUpdateBadge
        $updateBadge.Margin = $marginUpdateBadge
        $updateBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed
        $updateBadge.MaxWidth = 86

        $updateText = [System.Windows.Controls.TextBlock]::new()
        $updateText.FontSize = 9.5
        $updateText.FontWeight = [System.Windows.FontWeights]::Bold
        $updateText.Foreground = $script:brushUpdateBadgeFg
        $updateText.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $updateBadge.Child = $updateText
        [System.Windows.Controls.Grid]::SetColumn($updateBadge, 1)
        [void]$nameAreaGrid.Children.Add($updateBadge)

        $rowBorder.Tag["NameText"]    = $nameText
        $rowBorder.Tag["UpdateBadge"] = $updateBadge
        $rowBorder.Tag["UpdateText"]  = $updateText

        [System.Windows.Controls.Grid]::SetColumn($nameAreaGrid, 2)
        [void]$rowGrid.Children.Add($nameAreaGrid)

        # 4. Button Link Website ngoài cùng bên phải (Tối giản chuẩn WinUtil, chỉ sáng khi hover)
        $targetPageUrl = if (-not [string]::IsNullOrWhiteSpace($app.Url)) {
            $app.Url
        } elseif (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
            if ($app.Domain.StartsWith("http")) { $app.Domain } else { "https://$($app.Domain)" }
        } else { "" }

        $linkBtn = [System.Windows.Controls.Border]::new()
        $linkBtn.Width = 20
        $linkBtn.Height = 19
        $linkBtn.CornerRadius = $cornerFour
        $linkBtn.Style = $script:styleLinkBtn
        $linkBtn.BorderThickness = $thicknessOne
        $linkBtn.Cursor = [System.Windows.Input.Cursors]::Hand
        $linkBtn.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
        $linkBtn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $linkBtn.Margin = $thicknessZero
        $linkBtn.ToolTip = "Mở trang chính thức: $targetPageUrl"
        $linkBtn.Tag = @{ Url = $targetPageUrl; Row = $rowBorder }

        $linkIcon = [System.Windows.Controls.TextBlock]::new()
        $linkIcon.Text = $strOpenLinkGlyph
        $linkIcon.FontFamily = $script:fontSegoeUI
        $linkIcon.FontSize = 11.5
        $linkIcon.FontWeight = [System.Windows.FontWeights]::Bold
        $linkIcon.Foreground = $script:brushLinkBtnRowHover
        $linkIcon.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $linkIcon.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $linkIcon.Margin = $marginLinkIcon
        $linkBtn.Child = $linkIcon
        $rowBorder.Tag["LinkBtn"]  = $linkBtn
        $rowBorder.Tag["LinkIcon"] = $linkIcon

        $linkBtn.Add_MouseLeftButtonUp($script:linkClickHandler)
        [System.Windows.Controls.Grid]::SetColumn($linkBtn, 3)
        [void]$rowGrid.Children.Add($linkBtn)

        # Tối ưu nhấp chọn toàn dòng: Nhấp vào Tên ứng dụng hoặc khoảng trống dòng -> TỰ ĐỘNG TÍCH CHECKBOX
        $rowBorder.Add_MouseLeftButtonUp($script:rowClickHandler)

        $rowBorder.Child = $rowGrid
        $cardStack.Children.Add($rowBorder) | Out-Null
        $allItemBorders.Add($rowBorder)
    }

    $cardBorder.Child = $cardStack

    # Trọng số chiều cao ước tính: 46px (Header card + Separator) + (Số dòng app * 29px) + 10px (Margin)
    $cardEstimatedHeight = 56 + ($appsInCat.Count * 29)

    # Tìm cột hiện có tổng chiều cao thấp nhất để rót card vào (nguyên lý bình thông nhau, triệt tiêu khoảng trống)
    $targetColIndex = 0
    $minHeight = $script:colHeights[0]
    for ($i = 1; $i -lt 4; $i++) {
        if ($script:colHeights[$i] -lt $minHeight) {
            $minHeight = $script:colHeights[$i]
            $targetColIndex = $i
        }
    }

    $targetColPanel = if ($cardCols[0] -and $cardCols[$targetColIndex]) { $cardCols[$targetColIndex] } else { $cardsContainer }
    if ($targetColPanel) {
        $targetColPanel.Children.Add($cardBorder) | Out-Null
    }

    # Cập nhật chiều cao tích lũy của cột
    $script:colHeights[$targetColIndex] += $cardEstimatedHeight
}

# ── CÁC HÀNH ĐỘNG CÀI ĐẶT / GỠ / NÂNG CẤP APP ──
Register-Click "btnScanInstalled" {
    Invoke-GuardedAction "Quét ứng dụng" {
        Scan-And-ColorizeApps
    }
}

function Clear-AllCheckBoxes {
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

function Invoke-GitHubAssetInstall {
    param($App)
    try {
        Log-Text "   -> Đang tìm bản phát hành mới nhất từ GitHub ($($App.GitHubRepo))..."
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$($App.GitHubRepo)/releases/latest" -Headers @{ "User-Agent" = "DuckUtil" } -TimeoutSec 15
        $asset = $rel.assets | Where-Object { $_.name -match $App.AssetRegex } | Select-Object -First 1
        if (-not $asset) {
            Log-Text "   [!] Không tìm thấy bộ cài phù hợp trên GitHub Release."
            return -1
        }
        $dlPath = Join-Path $env:TEMP $asset.name
        Log-Text "   -> Đang tải $($asset.name)..."
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dlPath -UseBasicParsing -Headers @{ "User-Agent" = "DuckUtil" } -TimeoutSec 120
        try {
            if ($dlPath -match '\.msi$') {
                return (Run-CliStream "msiexec.exe" "/i `"$dlPath`" /qn /norestart")
            } else {
                return (Run-CliStream $dlPath "--silent-install")
            }
        } finally {
            if (Test-Path -LiteralPath $dlPath) { Remove-Item -LiteralPath $dlPath -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        Log-Text "   [!] Lỗi tải/cài từ GitHub: $($_.Exception.Message)"
        return -1
    }
}

function Clear-WinGetTempInstallers {
    param([string[]]$RootPaths)
    if (-not $RootPaths -or $RootPaths.Count -eq 0) {
        $rawCandidates = @(
            (Join-Path ([System.IO.Path]::GetTempPath()) "WinGet"),
            $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Temp\WinGet" })
        )
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $RootPaths = foreach ($cand in $rawCandidates) {
            if ([string]::IsNullOrWhiteSpace($cand)) { continue }
            $full = [System.IO.Path]::GetFullPath($cand).TrimEnd('\')
            if ($seen.Add($full)) { $full }
        }
    }

    $removedCount = 0
    $freedBytes = [long]0
    foreach ($wingetTemp in $RootPaths) {
        if ([string]::IsNullOrWhiteSpace($wingetTemp) -or -not (Test-Path -LiteralPath $wingetTemp)) { continue }

        $entries = Get-ChildItem -LiteralPath $wingetTemp -Force -ErrorAction SilentlyContinue
        foreach ($entry in $entries) {
            # Giữ lại thư mục cache manifest nội bộ của WinGet
            if ($entry.Name -ieq "cache") { continue }

            $entryBytes = [long]0
            if ($entry.PSIsContainer) {
                $measure = Get-ChildItem -LiteralPath $entry.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
                if ($measure -and $null -ne $measure.Sum) { $entryBytes = [long]$measure.Sum }
            } else {
                $entryBytes = [long]$entry.Length
            }

            try {
                Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction Stop
                $removedCount++
                $freedBytes += $entryBytes
            } catch {
                # Bỏ qua tệp đang bị tiến trình cài đặt khác giữ khóa
            }
        }
    }

    if ($removedCount -gt 0) {
        $freedMB = [math]::Round($freedBytes / 1MB, 1)
        Log-Text "[CLEAN] Đã tự động dọn $removedCount thư mục/tệp bộ cài WinGet tồn dư ($freedMB MB)."
    }
}

Register-Click "btnInstall" {
    Invoke-GuardedAction "Cài đặt ứng dụng" {
        $selectedTags = [System.Collections.Generic.List[object]]::new()
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -eq $true) {
                $selectedTags.Add($cb.Tag)
            }
        }

        if ($selectedTags.Count -eq 0) {
            Log-Text "[!] Bạn chưa tick chọn ứng dụng nào để cài đặt!"
            return
        }

        $total = $selectedTags.Count
        $idx = 0
        Log-Text "=========================================================="
        Log-Text "🚀 BẮT ĐẦU CÀI ĐẶT $total ỨNG DỤNG ĐÃ ĐÁNH DẤU"
        Log-Text "=========================================================="

        try {
            foreach ($tag in $selectedTags) {
                $idx++
                $app = $tag.App
                if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }
                if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang cài đặt: $($app.Name)..." }
                Log-Text "[$idx/$total] Đang cài: $($app.Name) (ID: $($app.ID))..."

                if (-not [string]::IsNullOrWhiteSpace($app.GitHubRepo) -and -not [string]::IsNullOrWhiteSpace($app.AssetRegex)) {
                    $code = Invoke-GitHubAssetInstall -App $app
                } else {
                    $wgArgs = "install --id `"$($app.ID)`" --exact --silent --accept-package-agreements --accept-source-agreements"
                    if ($app.Source -eq "msstore") { $wgArgs += " --source msstore" }
                    $code = Run-CliStream "winget" $wgArgs
                }

                if ($code -eq 0) {
                    Log-Text "   [✓ HOÀN THÀNH] $($app.Name)"
                    if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                } else {
                    Log-Text "   [❌ LỖI] $($app.Name) (Exit Code: $code)"
                    if (-not [string]::IsNullOrWhiteSpace($app.FallbackUrl)) {
                        Log-Text "   [↗] Gói này hiện không khả dụng tự động qua WinGet. Đang mở trang tải chính thức: $($app.FallbackUrl)"
                        try { Start-Process $app.FallbackUrl } catch {}
                    }
                }
            }
        } finally {
            Clear-WinGetTempInstallers
        }
        Update-SelectionCount
        if ($txtStatus) { $txtStatus.Text = "Cài đặt hoàn tất!" }
        if ($progressBar) { $progressBar.Value = 100 }
        Scan-And-ColorizeApps
    }
}

Register-Click "btnUninstall" {
    Invoke-GuardedAction "Gỡ cài đặt" -DeferExpand {
        $selectedTags = [System.Collections.Generic.List[object]]::new()
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -eq $true) {
                $selectedTags.Add($cb.Tag)
            }
        }

        if ($selectedTags.Count -eq 0) {
            Expand-TerminalLog
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

        Expand-TerminalLog
        $total = $selectedTags.Count
        $idx = 0
        Log-Text "=========================================================="
        Log-Text "🗑️ BẮT ĐẦU GỠ CÀI ĐẶT $total ỨNG DỤNG ĐÃ CHỌN"
        Log-Text "=========================================================="

        foreach ($tag in $selectedTags) {
            $idx++
            $app = $tag.App
            # Ưu tiên sử dụng DetectedId thực tế phát hiện được qua SmartMatcher
            $uninstallId = if ($tag.DetectedId) { $tag.DetectedId } else { $app.ID }

            if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }
            if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang gỡ bỏ: $($app.Name)..." }
            Log-Text "[$idx/$total] Đang gỡ: $($app.Name) (Mã gỡ: $uninstallId)..."

            $unArgs = "uninstall --id `"$uninstallId`" --silent --accept-source-agreements"
            if ($app.Source -eq "msstore" -and $uninstallId -eq $app.ID) {
                $unArgs += " --source msstore"
            }
            $code = Run-CliStream "winget" $unArgs
            if ($code -eq 0) {
                Log-Text "   [✓ ĐÃ GỠ THÀNH CÔNG] $($app.Name)"
                if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
            } else {
                Log-Text "   [❌ LỖI GỠ] $($app.Name) (Exit Code: $code)"
            }
        }
        Update-SelectionCount
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

        try {
            Run-CliStream "winget" "upgrade --all --silent --accept-package-agreements --accept-source-agreements"
        } finally {
            Clear-WinGetTempInstallers
        }

        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Nâng cấp hoàn tất!" }
        Log-Text "[✓] Toàn bộ ứng dụng đã được nâng cấp lên bản mới nhất."
        Scan-And-ColorizeApps
    }
}

# Chọn tất cả các dòng đang hiển thị
Register-Click "btnSelectAll" {
    $script:suppressSelectionCount = $true
    try {
        foreach ($row in $allItemBorders) {
            if ($row.Visibility -eq [System.Windows.Visibility]::Visible -and $row.Tag -and $row.Tag.CheckBox) {
                $cb = $row.Tag.CheckBox
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
    Clear-AllCheckBoxes
}

# ── LOGIC MODULE SỬA LỖI HỆ THỐNG (SYSTEM REPAIRS) ──
Register-Click "btnSfcScan" -LockGroup "Gỡ lỗi & Hệ thống" {
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

Register-Click "btnDismRestore" -LockGroup "Gỡ lỗi & Hệ thống" {
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

Register-Click "btnDismCleanup" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "DISM Component Cleanup" -DeferExpand {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Lệnh DISM /StartComponentCleanup /ResetBase sẽ nén kho WinSxS và KHÔNG THỂ gỡ cài đặt (rollback) các bản Windows Update hiện tại về sau.`n`nBạn có chắc chắn muốn tiếp tục?",
            "Xác nhận dọn kho linh kiện (WinSxS)",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Expand-TerminalLog
        Log-Text "[*] Đang dọn dẹp kho linh kiện hệ thống (DISM Component Cleanup)..."
        if ($txtStatus) { $txtStatus.Text = "Đang dọn kho linh kiện..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-DismComponentCleanup
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn kho linh kiện hoàn tất" }
        Log-Text "[✓] Đã giải phóng dung lượng kho linh kiện."
    }
}

Register-Click "btnFixWindowsUpdate" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Khởi tạo lại Windows Update" {
        Log-Text "[*] Bắt đầu khởi tạo và xóa sạch cache lỗi Windows Update..."
        if ($txtStatus) { $txtStatus.Text = "Đang sửa lỗi Windows Update..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Reset-WindowsUpdateEngine
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Đã đặt lại Windows Update" }
    }
}

Register-Click "btnRestartUpdateServices" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Khởi động lại Update Services" {
        Log-Text "[*] Đang khởi động lại dịch vụ Windows Update & BITS..."
        Restart-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
        Restart-Service -Name "bits" -Force -ErrorAction SilentlyContinue
        Log-Text "[✓] Đã khởi động lại dịch vụ cập nhật."
    }
}

Register-Click "btnTriggerScanUpdate" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Kích hoạt quét cập nhật" {
        Invoke-WindowsUpdateScan
    }
}

Register-Click "btnFlushDnsWinsock" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Flush DNS & Reset Winsock" {
        Log-Text "[*] Đang xóa sạch cache DNS và reset Winsock Catalog..."
        Clear-DnsResolverCache
        Run-CliStream "netsh.exe" "winsock reset"
        Log-Text "[✓] Đã làm mới mạng và DNS cache."
    }
}

Register-Click "btnResetTcpIp" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Reset TCP/IP Stack" {
        Log-Text "[*] Đang đặt lại toàn bộ ngăn xếp giao thức mạng TCP/IP..."
        Reset-NetworkInterfaceStack
        Log-Text "[✓] Đã reset TCP/IP Stack. Khuyên bạn nên khởi động lại máy."
    }
}

Register-Click "btnClearTemp" -LockGroup "Gỡ lỗi & Hệ thống" {
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

Register-Click "btnCleanEventLogs" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Dọn dẹp Windows Event Logs" -DeferExpand {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Hành động này sẽ xóa toàn bộ nhật ký sự kiện Windows (Application, System, Security...). Bạn có chắc chắn muốn tiếp tục?",
            "Xác nhận dọn dẹp Event Logs",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Expand-TerminalLog
        if ($txtStatus) { $txtStatus.Text = "Đang dọn Event Logs..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Clear-SystemEventLogs
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn Event Logs hoàn tất" }
    }
}

Register-Click "btnRestartExplorer" -LockGroup "Gỡ lỗi & Hệ thống" {
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
Register-Click "btnScanFaultyDrivers" -LockGroup "Quản lý Driver" {
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

Register-Click "btnPnpRescan" -LockGroup "Quản lý Driver" {
    Invoke-GuardedAction "Quét lại thiết bị PnP" {
        Log-Text "[*] Đang gửi lệnh quét phần cứng Plug and Play (pnputil /scan-devices)..."
        Invoke-PnpDeviceRescan
        Log-Text "[✓] Windows đã hoàn tất quét và phát hiện lại các thiết bị phần cứng."
    }
}

Register-Click "btnOpenDeviceManager" -LockGroup "Quản lý Driver" {
    Log-Text "[*] Đang mở Trình quản lý thiết bị (devmgmt.msc)..."
    Start-Process "devmgmt.msc"
}

Register-Click "btnFixDriverUpdate" -LockGroup "Quản lý Driver" {
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

Register-Click "btnScanWindowsUpdateDrivers" -LockGroup "Quản lý Driver" {
    Invoke-GuardedAction "Quét driver từ Windows Update" {
        Invoke-WindowsUpdateScan
    }
}

Register-Click "btnCleanDriverStore" -LockGroup "Quản lý Driver" {
    Invoke-GuardedAction "Dọn dẹp DriverStore" -DeferExpand {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Hành động này sẽ xóa các gói driver OEM cũ không còn thiết bị sử dụng trong DriverStore.`nBạn có chắc chắn muốn tiếp tục?",
            "Xác nhận dọn dẹp DriverStore",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Expand-TerminalLog
        if ($txtStatus) { $txtStatus.Text = "Đang dọn dẹp DriverStore..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-PnpDriverStoreCleanup
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn dẹp DriverStore hoàn tất" }
    }
}

Register-Click "btnBackupDrivers" -LockGroup "Quản lý Driver" {
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

Register-Click "btnOpenBackupFolder" -LockGroup "Quản lý Driver" {
    $dest = "C:\Backup_Drivers"
    if (Test-Path -LiteralPath $dest) {
        Start-Process explorer.exe "`"$dest`""
    } else {
        Log-Text "[!] Thư mục $dest chưa tồn tại. Hãy bấm nút 'Sao Lưu Toàn Bộ Driver' trước."
    }
}

# ── TỰ ĐỘNG QUÉT KHI MỞ CỬA SỔ & KHỞI CHẠY GIAO DIỆN ──
$script:iconSyncTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:iconSyncTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$script:iconSyncTimer.Add_Tick({
    if ($script:isScanningApps -or $script:isActionRunning) { return }
    Flush-PendingIconCache
    if (-not $script:pendingIconSaves -or $script:pendingIconSaves.Count -eq 0) {
        $script:iconSyncTimer.Stop()
    }
})

$script:autoScannedOnStartup = $false
$window.Add_ContentRendered({
    if (-not $script:autoScannedOnStartup) {
        $script:autoScannedOnStartup = $true
        Log-Text "[✓] Giao diện App-Driver đã sẵn sàng ($($allItemBorders.Count) ứng dụng / $($categories.Count) danh mục)."
        if ($script:pendingIconSaves -and $script:pendingIconSaves.Count -gt 0) {
            $script:iconSyncTimer.Start()
        }
        $window.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
            [Action]{
                Invoke-GuardedAction "Quét ứng dụng khởi động" -DeferExpand {
                    Scan-And-ColorizeApps
                }
            }
        ) | Out-Null
    }
})
$window.Add_Closed({
    try {
        if ($script:iconSyncTimer) { $script:iconSyncTimer.Stop() }
        Flush-PendingIconCache
    } catch {}
})

$window.ShowDialog() | Out-Null
