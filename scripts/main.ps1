Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
if (Get-Command "Start-WingetBackgroundPreScan" -ErrorAction SilentlyContinue) {
    Start-WingetBackgroundPreScan
}

$reader = New-Object System.Xml.XmlNodeReader $XAML
$window = [Windows.Markup.XamlReader]::Load($reader)

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

$MainTabControl    = $window.FindName("MainTabControl")
$txtStatus         = $window.FindName("txtStatus")
$progressBar       = $window.FindName("progressBar")
$txtSelectionCount = $window.FindName("txtSelectionCount")
$cardsContainer    = $window.FindName("CardsContainer")

$script:brushNavActive   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushNavActive.Freeze()
$script:brushNavInactive = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x64, 0x74, 0x8B)); $script:brushNavInactive.Freeze()
$script:brushTransparent = [System.Windows.Media.Brushes]::Transparent

$script:brushCardBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x11, 0x17, 0x22)); $script:brushCardBg.Freeze()
$script:brushCardBorder  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x2B, 0x39, 0x4F)); $script:brushCardBorder.Freeze()
$script:brushHeaderFg    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x7D, 0xD3, 0xFC)); $script:brushHeaderFg.Freeze()
$script:brushHeaderCntBg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x18, 0x22, 0x34)); $script:brushHeaderCntBg.Freeze()
$script:brushHeaderCntFg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x8A, 0x9E, 0xB8)); $script:brushHeaderCntFg.Freeze()
$script:brushSeparator   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x27, 0x34, 0x4A)); $script:brushSeparator.Freeze()

$script:brushRowHover    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x19, 0x22, 0x34)); $script:brushRowHover.Freeze()
$script:brushTextWhite   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF1, 0xF5, 0xF9)); $script:brushTextWhite.Freeze()
$script:fontSegoeEmoji   = New-Object System.Windows.Media.FontFamily("Segoe UI Emoji, Segoe UI Symbol, Arial")
$script:fontSegoeUI      = New-Object System.Windows.Media.FontFamily("Segoe UI Variable Text, Segoe UI, Arial")

$script:brushLinkBtnBg        = [System.Windows.Media.Brushes]::Transparent
$script:brushLinkBtnBorder    = [System.Windows.Media.Brushes]::Transparent
$script:brushLinkBtnFg        = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x52, 0x60, 0x76)); $script:brushLinkBtnFg.Freeze()
$script:brushLinkBtnRowHover  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x94, 0xA3, 0xB8)); $script:brushLinkBtnRowHover.Freeze()

$script:brushLinkBtnHoverBg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1E, 0x29, 0x3B)); $script:brushLinkBtnHoverBg.Freeze()
$script:brushLinkBtnHoverBdr  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushLinkBtnHoverBdr.Freeze()
$script:brushLinkBtnHoverFg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushLinkBtnHoverFg.Freeze()

$script:brushIconBadgeBg        = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(14, 255, 255, 255)); $script:brushIconBadgeBg.Freeze()
$script:brushIconBadgeLightBg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(240, 0xE8, 0xEE, 0xF5)); $script:brushIconBadgeLightBg.Freeze()
$script:brushIconBadgeBorder    = [System.Windows.Media.Brushes]::Transparent

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

$script:brushCardHoverBorder = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0x74, 0xB8)); $script:brushCardHoverBorder.Freeze()
$script:styleCategoryCard = New-Object System.Windows.Style([System.Windows.Controls.Border])
$script:styleCategoryCard.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $script:brushCardBorder)))
$trigCardHover = New-Object System.Windows.Trigger
$trigCardHover.Property = [System.Windows.UIElement]::IsMouseOverProperty
$trigCardHover.Value = $true
$trigCardHover.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $script:brushCardHoverBorder)))
$script:styleCategoryCard.Triggers.Add($trigCardHover)
$script:styleCategoryCard.Seal()

if (-not ("DuckUtil.SmoothScrollController" -as [type])) {
    try {
        $csCandidates = @(
            (Join-Path $PSScriptRoot "..\csharp\SmoothScrollController.cs"),
            (Join-Path $PSScriptRoot "csharp\SmoothScrollController.cs")
        )
        foreach ($cand in $csCandidates) {
            if (Test-Path -LiteralPath $cand) {
                $wpfSmoothRefs = @(
                    [System.Windows.Controls.ScrollViewer].Assembly.Location,
                    [System.Windows.UIElement].Assembly.Location,
                    [System.Windows.DependencyObject].Assembly.Location,
                    [System.Windows.Markup.IQueryAmbient].Assembly.Location,
                    [System.Diagnostics.Stopwatch].Assembly.Location,
                    [System.Object].Assembly.Location
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
                $smoothScrollCs = Get-Content -Raw -Encoding utf8 $cand
                Add-Type -TypeDefinition $smoothScrollCs -ReferencedAssemblies $wpfSmoothRefs -ErrorAction SilentlyContinue
                break
            }
        }
    } catch {}
}

$appsScrollViewer = $window.FindName("AppsScrollViewer")
if ($appsScrollViewer -and ("DuckUtil.SmoothScrollController" -as [type])) {
    $script:smoothScrollCtrl = [DuckUtil.SmoothScrollController]::Attach($appsScrollViewer)
}
$uninstallerScrollViewer = $window.FindName("UninstallerScrollViewer")
if ($uninstallerScrollViewer -and ("DuckUtil.SmoothScrollController" -as [type])) {
    $script:uninstallerSmoothScrollCtrl = [DuckUtil.SmoothScrollController]::Attach($uninstallerScrollViewer)
}

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
    param([int]$MaxDecode = 8)
    if (-not $script:pendingIconSaves -or $script:pendingIconSaves.Count -eq 0) { return }
    if ($script:isActionRunning) { return }
    $inFlightCount = 0
    $decodedCount  = 0
    for ($idx = $script:pendingIconSaves.Count - 1; $idx -ge 0; $idx--) {
        $entry = $script:pendingIconSaves[$idx]
        $hasLocalFile = (-not [string]::IsNullOrWhiteSpace($entry.DestPath)) -and [System.IO.File]::Exists($entry.DestPath)
        if (-not $hasLocalFile -and -not $entry.DownloadInfo -and $entry.Url) {
            if ($inFlightCount -ge 12 -and -not $script:inFlightIconTasks.ContainsKey($entry.Url)) {
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
                            $hasLocalFile = $true
                        }
                    } catch {}
                }
                try { if ($dlInfo.Client) { $dlInfo.Client.Dispose() } } catch {}
            }
        }
        if ($hasLocalFile -or ($script:remoteBmpCache -and $script:remoteBmpCache.ContainsKey($entry.CacheKey))) {
            if ($decodedCount -ge $MaxDecode) { continue }
            $bmp = Import-LocalIconBitmap -Path $entry.DestPath -CacheKey $entry.CacheKey
            if ($bmp -and $bmp.PixelWidth -gt 0) {
                $decodedCount++
                if (-not $hasLocalFile) {
                    Save-BitmapToCacheAtomic -BitmapSource $bmp -DestPath $entry.DestPath
                }
                if ($entry.Img) {
                    $entry.Img.Source = $bmp
                    $entry.Img.Visibility = [System.Windows.Visibility]::Visible
                }
                if ($entry.Fallback) {
                    $entry.Fallback.Visibility = [System.Windows.Visibility]::Collapsed
                }
                if ($entry.UseLight -and $entry.Badge) {
                    $entry.Badge.Background = $script:brushIconBadgeLightBg
                }
            }
        }
        $script:pendingIconSaves.RemoveAt($idx)
    }
}
$script:cornerIconBadge         = New-Object System.Windows.CornerRadius(1)
$script:brushUpdateBadgeBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(28, 0xF8, 0x71, 0x71)); $script:brushUpdateBadgeBg.Freeze()
$script:brushUpdateBadgeBorder  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(85, 0xF8, 0x71, 0x71)); $script:brushUpdateBadgeBorder.Freeze()
$script:brushUpdateBadgeFg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xFC, 0xA5, 0xA5)); $script:brushUpdateBadgeFg.Freeze()

$marginCardBorder = New-Object System.Windows.Thickness(4)
$paddingCard      = New-Object System.Windows.Thickness(10, 8, 10, 10)
$marginHeaderGrid = New-Object System.Windows.Thickness(2, 0, 2, 6)
$marginSeparator  = New-Object System.Windows.Thickness(0, 1, 0, 5)
$marginRowBorder  = New-Object System.Windows.Thickness(0, 1, 0, 1)
$paddingRow       = New-Object System.Windows.Thickness(5, 0, 4, 0)
$marginIcon       = New-Object System.Windows.Thickness(7, 0, 8, 0)
$cornerCard       = New-Object System.Windows.CornerRadius(2)
$cornerRow        = New-Object System.Windows.CornerRadius(1)
$thicknessZero    = New-Object System.Windows.Thickness(0)
$thicknessOne     = New-Object System.Windows.Thickness(1)

$iconsCacheDir = Join-Path $env:LOCALAPPDATA "DuckUtil\Icons"
if (-not (Test-Path -LiteralPath $iconsCacheDir)) {
    try { New-Item -ItemType Directory -Path $iconsCacheDir -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
} else {
    try {
        Get-ChildItem -Path $iconsCacheDir -Filter "*.png" -ErrorAction SilentlyContinue | Where-Object {
            $_.Length -le 230 -or $_.Length -eq 588
        } | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {}

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

$script:isActionRunning = $false
$script:isUpdatingUninstaller = $false
$script:isSortingUninstaller = $false
$script:uninstallerLoadQueued = $false
$script:deferredUninstallerLoad = $false
$script:suppressUninstallerSelectionCount = $false
if (-not (Get-Variable -Name isWindowClosing -Scope Script -ErrorAction SilentlyContinue)) {
    $script:isWindowClosing = $false
}
if (-not (Get-Variable -Name isScanningApps -Scope Script -ErrorAction SilentlyContinue)) {
    $script:isScanningApps = $false
}

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
if (-not ('DuckUtil.WpfWin32Window' -as [type])) {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Windows.Forms;
namespace DuckUtil {
    public sealed class WpfWin32Window : IWin32Window {
        private readonly IntPtr _hwnd;
        public WpfWin32Window(IntPtr hwnd) { _hwnd = hwnd; }
        public IntPtr Handle { get { return _hwnd; } }
    }
}
"@ -ReferencedAssemblies ([System.Windows.Forms.IWin32Window].Assembly.Location) -ErrorAction SilentlyContinue
    } catch {}
}

function Get-WpfOwnerWin32Window {
    if (-not $window -or $script:isWindowClosing) { return $null }
    try {
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
        if ($hwnd -ne [IntPtr]::Zero -and ('DuckUtil.WpfWin32Window' -as [type])) {
            return (New-Object DuckUtil.WpfWin32Window($hwnd))
        }
    } catch {}
    return $null
}

function Show-OwnedMessageBox {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Caption,
        [System.Windows.Forms.MessageBoxButtons]$Buttons = [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information,
        [string]$PrimaryText = "",
        [string]$SecondaryText = "",
        [string[]]$DetailItems = @(),
        [string]$ModeBadgeText = "",
        [string]$ModeBadgeKind = "Info",
        [hashtable]$ToggleState = $null,
        $OwnerWindowOverride = $null
    )
    if ($script:isWindowClosing) {
        return [System.Windows.Forms.DialogResult]::Cancel
    }

    $targetOwner = if ($OwnerWindowOverride -is [System.Windows.Window]) { $OwnerWindowOverride } else { $window }
    $canAttachOwner = $false
    if ($targetOwner -and ($targetOwner -is [System.Windows.Window])) {
        try {
            if ($targetOwner.IsLoaded -and $targetOwner.IsVisible) {
                $src = [System.Windows.PresentationSource]::FromVisual($targetOwner)
                $hwndSrc = $src -as [System.Windows.Interop.HwndSource]
                $ownerHwnd = (New-Object System.Windows.Interop.WindowInteropHelper($targetOwner)).Handle
                if ($null -ne $hwndSrc -and (-not $hwndSrc.IsDisposed) -and $ownerHwnd -ne [IntPtr]::Zero) {
                    $canAttachOwner = $true
                }
            }
        } catch {
            $canAttachOwner = $false
        }
    }

    $dlgXaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    WindowStyle="None"
    ResizeMode="NoResize"
    SizeToContent="WidthAndHeight"
    MinWidth="445"
    MaxWidth="560"
    ShowInTaskbar="False"
    Background="#0C1018"
    Foreground="#E2E8F0"
    FontFamily="Segoe UI Variable Display, Segoe UI, -apple-system, sans-serif"
    TextOptions.TextFormattingMode="Display"
    TextOptions.TextRenderingMode="ClearType"
    UseLayoutRounding="True"
    SnapsToDevicePixels="True">
    <Window.Resources>
        <Style x:Key="DlgModeToggleBtn" TargetType="{x:Type ToggleButton}">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Background" Value="#101623"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="BorderBrush" Value="#27344A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,7"/>
            <Setter Property="ToolTipService.InitialShowDelay" Value="500"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type ToggleButton}">
                        <Border Name="tBox" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="2" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <ContentPresenter Grid.Column="0" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                                <Border Name="tStatePill" Grid.Column="1" Background="#141C2B" BorderBrush="#2F3E57" BorderThickness="1" CornerRadius="2" Padding="6,2" Margin="12,0,8,0" VerticalAlignment="Center">
                                    <TextBlock Name="tStateText" Text="T&#x1EAE;T" Foreground="#94A3B8" FontSize="10" FontWeight="Bold"/>
                                </Border>
                                <Border Name="tTrack" Grid.Column="2" Width="34" Height="18" Background="#0B111C" BorderBrush="#334155" BorderThickness="1" CornerRadius="2" Padding="2" VerticalAlignment="Center">
                                    <Grid>
                                        <Border Name="tThumb" Width="12" Height="12" Background="#64748B" CornerRadius="1" HorizontalAlignment="Left" VerticalAlignment="Center"/>
                                    </Grid>
                                </Border>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="tBox" Property="Background" Value="#0D2134"/>
                                <Setter TargetName="tBox" Property="BorderBrush" Value="#1D4E78"/>
                                <Setter Property="Foreground" Value="#BAE6FD"/>
                                <Setter TargetName="tStatePill" Property="Background" Value="#0B2E48"/>
                                <Setter TargetName="tStatePill" Property="BorderBrush" Value="#0284C7"/>
                                <Setter TargetName="tStateText" Property="Text" Value="B&#x1EAC;T"/>
                                <Setter TargetName="tStateText" Property="Foreground" Value="#38BDF8"/>
                                <Setter TargetName="tTrack" Property="Background" Value="#0369A1"/>
                                <Setter TargetName="tTrack" Property="BorderBrush" Value="#38BDF8"/>
                                <Setter TargetName="tThumb" Property="Background" Value="#F0F9FF"/>
                                <Setter TargetName="tThumb" Property="HorizontalAlignment" Value="Right"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="tBox" Property="BorderBrush" Value="#38BDF8"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="tBox" Property="Opacity" Value="0.88"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="DlgActionBtn" TargetType="Button">
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="16,7"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#3EFFFFFF"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="2" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="b" Property="Opacity" Value="0.90"/>
                                <Setter TargetName="b" Property="BorderBrush" Value="#80FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="b" Property="Opacity" Value="0.72"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="DlgSecondaryBtn" TargetType="Button">
            <Setter Property="Background" Value="#121826"/>
            <Setter Property="Foreground" Value="#CBD5E1"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="15,7"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderBrush" Value="#2F3E57"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="2" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="b" Property="Background" Value="#1B2538"/>
                                <Setter TargetName="b" Property="BorderBrush" Value="#38BDF8"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="b" Property="Background" Value="#161E2E"/>
                                <Setter TargetName="b" Property="BorderBrush" Value="#0EA5E9"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="DlgCloseBtn" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#64748B"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Width" Value="26"/>
            <Setter Property="Height" Value="24"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="b" Background="{TemplateBinding Background}" CornerRadius="2" SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="b" Property="Background" Value="#1E293B"/>
                                <Setter Property="Foreground" Value="#F8FAFC"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border Name="dlgOuterBorder" Background="#0C1018" BorderBrush="#334155" BorderThickness="1" CornerRadius="2">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <Border Name="dlgHeader" Grid.Row="0" Background="#090D14" BorderBrush="#27344A" BorderThickness="0,0,0,1" Padding="14,10">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Border Name="dlgIconBox" Grid.Column="0" Width="22" Height="22" CornerRadius="2" BorderThickness="1" Margin="0,0,10,0" VerticalAlignment="Center">
                        <TextBlock Name="dlgIconGlyph" FontSize="12" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Name="dlgTitleText" Grid.Column="1" Foreground="#F1F5F9" FontSize="12.5" FontWeight="Bold" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                    <Button Name="dlgBtnCloseX" Grid.Column="2" Content="✕" Style="{StaticResource DlgCloseBtn}" VerticalAlignment="Center"/>
                </Grid>
            </Border>

            <StackPanel Grid.Row="1" Margin="18,16,18,16">
                <TextBlock Name="dlgMessageText" Foreground="#E2E8F0" FontSize="12.5" LineHeight="19" TextWrapping="Wrap"/>
                <Border Name="dlgModeBadge" Visibility="Collapsed" CornerRadius="2" BorderThickness="1" Padding="9,5" Margin="0,10,0,0" HorizontalAlignment="Stretch">
                    <TextBlock Name="dlgModeBadgeText" FontSize="11" FontWeight="SemiBold"/>
                </Border>
                <ToggleButton Name="dlgModeToggle" Visibility="Collapsed" Style="{StaticResource DlgModeToggleBtn}" Margin="0,10,0,0" HorizontalAlignment="Stretch">
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Name="dlgToggleLabel" FontSize="11.5" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
                        <TextBlock Name="dlgToggleSub" Visibility="Collapsed" FontSize="10.5" Foreground="#64748B" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
                    </StackPanel>
                </ToggleButton>
                <Border Name="dlgListBorder" Visibility="Collapsed" Background="#090D14" BorderBrush="#233044" BorderThickness="1" CornerRadius="2" Margin="0,10,0,0" Padding="10,8" MaxHeight="180">
                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <StackPanel Name="dlgDetailList"/>
                    </ScrollViewer>
                </Border>
            </StackPanel>

            <Border Grid.Row="2" Background="#090D14" BorderBrush="#27344A" BorderThickness="0,1,0,0" Padding="16,11">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button Name="dlgBtnSecondary" Style="{StaticResource DlgSecondaryBtn}" Margin="0,0,8,0"/>
                    <Button Name="dlgBtnPrimary" Style="{StaticResource DlgActionBtn}"/>
                </StackPanel>
            </Border>
        </Grid>
    </Border>
</Window>
'@

    $dlg = $null
    try {
        $dlg = [System.Windows.Markup.XamlReader]::Parse($dlgXaml)
    } catch {
        $ownerWin = Get-WpfOwnerWin32Window
        if ($ownerWin) { return [System.Windows.Forms.MessageBox]::Show($ownerWin, $Text, $Caption, $Buttons, $Icon) }
        return [System.Windows.Forms.MessageBox]::Show($Text, $Caption, $Buttons, $Icon)
    }

    if ($canAttachOwner) {
        try {
            $dlg.Owner = $targetOwner
            $dlg.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
        } catch {
            try { $dlg.Owner = $null } catch {}
            $dlg.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
        }
    } else {
        $dlg.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    }

    $bc = [System.Windows.Media.BrushConverter]::new()
    $dlgOuterBorder   = $dlg.FindName("dlgOuterBorder")
    $dlgHeader        = $dlg.FindName("dlgHeader")
    $dlgIconBox       = $dlg.FindName("dlgIconBox")
    $dlgIconGlyph     = $dlg.FindName("dlgIconGlyph")
    $dlgTitleText     = $dlg.FindName("dlgTitleText")
    $dlgBtnCloseX     = $dlg.FindName("dlgBtnCloseX")
    $dlgMessageText   = $dlg.FindName("dlgMessageText")
    $dlgModeBadge     = $dlg.FindName("dlgModeBadge")
    $dlgModeBadgeText = $dlg.FindName("dlgModeBadgeText")
    $dlgModeToggle    = $dlg.FindName("dlgModeToggle")
    $dlgToggleLabel   = $dlg.FindName("dlgToggleLabel")
    $dlgToggleSub     = $dlg.FindName("dlgToggleSub")
    $dlgListBorder    = $dlg.FindName("dlgListBorder")
    $dlgDetailList    = $dlg.FindName("dlgDetailList")
    $dlgBtnSecondary  = $dlg.FindName("dlgBtnSecondary")
    $dlgBtnPrimary    = $dlg.FindName("dlgBtnPrimary")

    $dlgTitleText.Text = $Caption
    $dlgMessageText.Text = $Text

    $isWarning = ($Icon -eq [System.Windows.Forms.MessageBoxIcon]::Warning) -or ($Icon -eq [System.Windows.Forms.MessageBoxIcon]::Error)
    if ($isWarning) {
        $dlgOuterBorder.BorderBrush = $bc.ConvertFromString("#47262A")
        $dlgIconBox.Background      = $bc.ConvertFromString("#2A1519")
        $dlgIconBox.BorderBrush     = $bc.ConvertFromString("#7F1D1D")
        $dlgIconGlyph.Foreground    = $bc.ConvertFromString("#F87171")
        $dlgIconGlyph.Text          = "!"
        $dlgBtnPrimary.Background   = $bc.ConvertFromString("#991B1B")
        $dlgBtnPrimary.BorderBrush  = $bc.ConvertFromString("#DC2626")
    } else {
        $dlgOuterBorder.BorderBrush = $bc.ConvertFromString("#2B3B52")
        $dlgIconBox.Background      = $bc.ConvertFromString("#102438")
        $dlgIconBox.BorderBrush     = $bc.ConvertFromString("#1D4E78")
        $dlgIconGlyph.Foreground    = $bc.ConvertFromString("#38BDF8")
        $dlgIconGlyph.Text          = "i"
        $dlgBtnPrimary.Background   = $bc.ConvertFromString("#0284C7")
        $dlgBtnPrimary.BorderBrush  = $bc.ConvertFromString("#38BDF8")
    }

    if (-not [string]::IsNullOrWhiteSpace($ModeBadgeText)) {
        $dlgModeBadge.Visibility = [System.Windows.Visibility]::Visible
        $dlgModeBadgeText.Text = $ModeBadgeText
        if ($ModeBadgeKind -eq "Danger") {
            $dlgModeBadge.Background   = $bc.ConvertFromString("#281317")
            $dlgModeBadge.BorderBrush  = $bc.ConvertFromString("#7F1D1D")
            $dlgModeBadgeText.Foreground = $bc.ConvertFromString("#FCA5A5")
        } else {
            $dlgModeBadge.Background   = $bc.ConvertFromString("#0D2134")
            $dlgModeBadge.BorderBrush  = $bc.ConvertFromString("#1D4E78")
            $dlgModeBadgeText.Foreground = $bc.ConvertFromString("#7DD3FC")
        }
    }

    if ($null -ne $ToggleState -and $dlgModeToggle -and $dlgToggleLabel) {
        $dlgModeToggle.Visibility = [System.Windows.Visibility]::Visible
        $dlgToggleLabel.Text = if ($ToggleState.Label) { [string]$ToggleState.Label } else { "" }
        $tSubOnFg  = $bc.ConvertFromString("#7FA6C9")
        $tSubOffFg = $bc.ConvertFromString("#64748B")
        $tHintOn   = if ($ToggleState.HintOn)  { [string]$ToggleState.HintOn }  else { "" }
        $tHintOff  = if ($ToggleState.HintOff) { [string]$ToggleState.HintOff } else { "" }

        $syncToggleUi = {
            $isOn = ($dlgModeToggle.IsChecked -eq $true)
            $ToggleState.Checked = $isOn
            if ($dlgToggleSub) {
                $subMsg = if ($isOn) { $tHintOn } else { $tHintOff }
                if ([string]::IsNullOrWhiteSpace($subMsg)) {
                    $dlgToggleSub.Visibility = [System.Windows.Visibility]::Collapsed
                } else {
                    $dlgToggleSub.Text = $subMsg
                    $dlgToggleSub.Foreground = if ($isOn) { $tSubOnFg } else { $tSubOffFg }
                    $dlgToggleSub.Visibility = [System.Windows.Visibility]::Visible
                }
            }
        }.GetNewClosure()

        $dlgModeToggle.IsChecked = [bool]$ToggleState.Checked
        & $syncToggleUi
        $dlgModeToggle.Add_Checked($syncToggleUi)
        $dlgModeToggle.Add_Unchecked($syncToggleUi)
    }

    if ($DetailItems -and $DetailItems.Count -gt 0) {
        $dlgListBorder.Visibility = [System.Windows.Visibility]::Visible
        $itemFg = $bc.ConvertFromString("#CBD5E1")
        foreach ($dLine in $DetailItems) {
            if ([string]::IsNullOrWhiteSpace($dLine)) { continue }
            $tb = [System.Windows.Controls.TextBlock]::new()
            $tb.Text = $dLine
            $tb.Foreground = $itemFg
            $tb.FontSize = 11.5
            $tb.Margin = [System.Windows.Thickness]::new(0, 1.5, 0, 1.5)
            $tb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
            [void]$dlgDetailList.Children.Add($tb)
        }
    }

    $isYesNo = ($Buttons -eq [System.Windows.Forms.MessageBoxButtons]::YesNo) -or ($Buttons -eq [System.Windows.Forms.MessageBoxButtons]::YesNoCancel)
    $isOkCancel = ($Buttons -eq [System.Windows.Forms.MessageBoxButtons]::OKCancel)
    if ($isYesNo) {
        $dlgBtnPrimary.Content = if ([string]::IsNullOrWhiteSpace($PrimaryText)) { "Đồng ý" } else { $PrimaryText }
        $dlgBtnSecondary.Content = if ([string]::IsNullOrWhiteSpace($SecondaryText)) { "Hủy bỏ" } else { $SecondaryText }
    } elseif ($isOkCancel) {
        $dlgBtnPrimary.Content = if ([string]::IsNullOrWhiteSpace($PrimaryText)) { "OK" } else { $PrimaryText }
        $dlgBtnSecondary.Content = if ([string]::IsNullOrWhiteSpace($SecondaryText)) { "Hủy bỏ" } else { $SecondaryText }
    } else {
        $dlgBtnPrimary.Content = if ([string]::IsNullOrWhiteSpace($PrimaryText)) { "Đóng" } else { $PrimaryText }
        $dlgBtnSecondary.Visibility = [System.Windows.Visibility]::Collapsed
    }

    $dlgState = @{
        Outcome = if ($isYesNo) { [System.Windows.Forms.DialogResult]::No } else { [System.Windows.Forms.DialogResult]::Cancel }
    }

    $dlgHeader.Add_MouseLeftButtonDown({
        param($s, $e)
        if ($e.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
            try { $dlg.DragMove() } catch {}
        }
    }.GetNewClosure())

    $dlgBtnPrimary.Add_Click({
        $dlgState.Outcome = if ($isYesNo) { [System.Windows.Forms.DialogResult]::Yes } else { [System.Windows.Forms.DialogResult]::OK }
        $dlg.Close()
    }.GetNewClosure())

    $dlgBtnSecondary.Add_Click({
        $dlgState.Outcome = if ($isYesNo) { [System.Windows.Forms.DialogResult]::No } else { [System.Windows.Forms.DialogResult]::Cancel }
        $dlg.Close()
    }.GetNewClosure())

    $dlgBtnCloseX.Add_Click({
        $dlgState.Outcome = if ($isYesNo) { [System.Windows.Forms.DialogResult]::No } elseif ($isOkCancel) { [System.Windows.Forms.DialogResult]::Cancel } else { [System.Windows.Forms.DialogResult]::OK }
        $dlg.Close()
    }.GetNewClosure())

    $dlg.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
            $dlgState.Outcome = if ($isYesNo) { [System.Windows.Forms.DialogResult]::No } elseif ($isOkCancel) { [System.Windows.Forms.DialogResult]::Cancel } else { [System.Windows.Forms.DialogResult]::OK }
            $dlg.Close()
        }
    }.GetNewClosure())

    try {
        [void]$dlg.ShowDialog()
    } finally {
        try { $dlg.Owner = $null } catch {}
    }
    return $dlgState.Outcome
}

$script:activeWaitFrames = [System.Collections.Generic.List[object]]::new()

function Stop-ActiveWaitFrames {
    if (-not $script:activeWaitFrames -or $script:activeWaitFrames.Count -eq 0) { return }
    foreach ($fr in @($script:activeWaitFrames)) {
        try { if ($fr) { $fr.Continue = $false } } catch {}
    }
}

function Wait-TaskNonBlocking {
    param(
        [Parameter(Mandatory = $true)][System.Threading.Tasks.Task]$Task,
        [double]$TimeoutSeconds = 60
    )
    if ($null -eq $Task) { return $true }
    if ($Task.IsCompleted) { return $true }
    if ($script:isWindowClosing) { return $false }

    if ($window -and $window.Dispatcher -and $window.Dispatcher.CheckAccess()) {
        $frame = [System.Windows.Threading.DispatcherFrame]::new()
        [void]$script:activeWaitFrames.Add($frame)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $disp = $window.Dispatcher

        $guardTimer = [System.Windows.Threading.DispatcherTimer]::new([System.Windows.Threading.DispatcherPriority]::Background)
        $guardTimer.Interval = [TimeSpan]::FromMilliseconds(40)
        $guardTimer.Add_Tick({
            if ($Task.IsCompleted -or $script:isWindowClosing -or $sw.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $frame.Continue = $false
            }
        }.GetNewClosure())

        try {
            $smoothType = "DuckUtil.SmoothScrollController" -as [type]
            if ($smoothType -and $null -ne $smoothType.GetMethod("AttachFrameWake")) {
                $smoothType::AttachFrameWake($Task, $disp, $frame)
            }
            if (-not $Task.IsCompleted -and -not $script:isWindowClosing) {
                $guardTimer.Start()
                [System.Windows.Threading.Dispatcher]::PushFrame($frame)
            }
        } finally {
            try { $guardTimer.Stop() } catch {}
            try { [void]$script:activeWaitFrames.Remove($frame) } catch {}
        }
        return $Task.IsCompleted
    }

    $swFallback = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $Task.IsCompleted) {
        if ($script:isWindowClosing -or $swFallback.Elapsed.TotalSeconds -ge $TimeoutSeconds) { break }
        try { [void]$Task.Wait(25) } catch {}
    }
    return $Task.IsCompleted
}

function Invoke-GuardedAction {
    param(
        [string]$ActionName,
        [scriptblock]$Action,
        [switch]$DeferExpand
    )
    if ($script:isWindowClosing) { return }
    if ($script:isActionRunning -or $script:isScanningApps -or $script:isUpdatingUninstaller) {
        Log-Text "[WARN] Đang có một tác vụ khác đang thực thi ($ActionName). Vui lòng đợi!"
        return
    }
    if (-not $DeferExpand) {
        Expand-TerminalLog
    }
    $script:isActionRunning = $true
    try {
        & $Action
    } catch {
        Log-Text "[!] Lỗi khi thực hiện '$ActionName': $($_.Exception.Message)"
    } finally {
        $script:isActionRunning = $false
        $script:isScanningApps = $false
        $script:isUpdatingUninstaller = $false
        $script:suppressSelectionCount = $false
        $script:suppressUninstallerSelectionCount = $false
        if ($progressBar) {
            try { $progressBar.IsIndeterminate = $false } catch {}
        }
        if (-not $script:isWindowClosing) {
            try { Flush-PendingIconCache -MaxDecode 6 } catch {}
            if ($script:pendingIconSaves -and $script:pendingIconSaves.Count -gt 0 -and $script:iconSyncTimer) {
                try { $script:iconSyncTimer.Start() } catch {}
            }
            if (-not $script:uninstallerLoadedOnce -and ($script:deferredUninstallerLoad -or ($script:tabPages -and $script:tabPages.Count -gt 1 -and $script:tabPages[1] -and $script:tabPages[1].Visibility -eq [System.Windows.Visibility]::Visible))) {
                $script:deferredUninstallerLoad = $false
                if ($window -and $window.Dispatcher) {
                    $window.Dispatcher.BeginInvoke(
                        [System.Windows.Threading.DispatcherPriority]::Background,
                        [Action]{ Update-UninstallerList }
                    ) | Out-Null
                }
            }
        }
    }
}

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

$navBtnApps        = $window.FindName("navBtnApps")
$navBtnUninstaller = $window.FindName("navBtnUninstaller")
$navBtnRepair      = $window.FindName("navBtnRepair")
$navBtnDrivers     = $window.FindName("navBtnDrivers")

$script:tabPages = @(
    $window.FindName("TabPage0"),
    $window.FindName("TabPage1"),
    $window.FindName("TabPage2"),
    $window.FindName("TabPage3")
)

$script:uninstallerLoadedOnce = $false

function Set-ActiveTab {
    param([int]$index, $activeBtn)
    if ($script:isWindowClosing) { return }
    if ($script:LockMaintenanceTabs -and ($index -eq 2 -or $index -eq 3)) {
        $feature = if ($index -eq 2) { "Gỡ lỗi & Hệ thống" } else { "Quản lý Driver" }
        Test-MaintenanceFeatureLocked $feature | Out-Null
        return
    }

    for ($ti = 0; $ti -lt $script:tabPages.Count; $ti++) {
        $tp = $script:tabPages[$ti]
        if (-not $tp) { continue }
        if ($ti -eq $index) {
            $tp.Visibility = [System.Windows.Visibility]::Visible
            $tp.IsHitTestVisible = $true
        } else {
            $tp.Visibility = [System.Windows.Visibility]::Collapsed
            $tp.IsHitTestVisible = $false
        }
    }

    $buttons = @($navBtnApps, $navBtnUninstaller, $navBtnRepair, $navBtnDrivers)
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

    if ($index -eq 1 -and -not $script:uninstallerLoadedOnce) {
        if ($script:isScanningApps -or $script:isActionRunning -or $script:isUpdatingUninstaller) {
            $script:deferredUninstallerLoad = $true
            if ($txtUninstallerSummary) {
                $txtUninstallerSummary.Text = "Đang chờ tác vụ hiện tại hoàn tất để tải danh sách ứng dụng..."
            }
        } elseif (-not $script:uninstallerLoadQueued -and $window -and $window.Dispatcher) {
            $script:uninstallerLoadQueued = $true
            $window.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::Loaded,
                [Action]{
                    $script:uninstallerLoadQueued = $false
                    Update-UninstallerList
                }
            ) | Out-Null
        }
    }
}

Register-Click "navBtnApps"        { Set-ActiveTab 0 $navBtnApps }
Register-Click "navBtnUninstaller" { Set-ActiveTab 1 $navBtnUninstaller }
Register-Click "navBtnRepair"      -LockGroup "Gỡ lỗi & Hệ thống" { Set-ActiveTab 2 $navBtnRepair }
Register-Click "navBtnDrivers"     -LockGroup "Quản lý Driver"    { Set-ActiveTab 3 $navBtnDrivers }

Set-ActiveTab 0 $navBtnApps

$btnDeepUninstall        = $window.FindName("btnDeepUninstall")
$btnForceStopUninstall   = $window.FindName("btnForceStopUninstall")
$btnScanOrphans          = $window.FindName("btnScanOrphans")
$btnRefreshUninstaller   = $window.FindName("btnRefreshUninstaller")
$btnFilterUninstAll      = $window.FindName("btnFilterUninstAll")
$btnFilterUninstBroken   = $window.FindName("btnFilterUninstBroken")
$btnSortUninstName       = $window.FindName("btnSortUninstName")
$btnSortUninstSize       = $window.FindName("btnSortUninstSize")
$hdrUninstName           = $window.FindName("hdrUninstName")
$hdrUninstSize           = $window.FindName("hdrUninstSize")
$txtUninstallSearch      = $window.FindName("txtUninstallSearch")
$btnClearUninstallSearch = $window.FindName("btnClearUninstallSearch")
$btnUninstallSelectAll   = $window.FindName("btnUninstallSelectAll")
$btnUninstallDeselectAll = $window.FindName("btnUninstallDeselectAll")
$pnlSkipVendorUninst     = $window.FindName("pnlSkipVendorUninstaller")
$cbSkipVendorUninst      = $window.FindName("cbSkipVendorUninstaller")
$txtUninstallerSummary   = $window.FindName("txtUninstallerSummary")
$uninstallerRowsPanel    = $window.FindName("UninstallerRowsPanel")

if ($pnlSkipVendorUninst -and $cbSkipVendorUninst) {
    $pnlSkipVendorUninst.Add_MouseLeftButtonUp({
        param($s, $e)
        if ($script:isWindowClosing -or $script:isActionRunning) { return }
        $node = $e.OriginalSource
        while ($node -ne $null -and $node -ne $s) {
            if ($node -is [System.Windows.Controls.CheckBox]) { return }
            if ($node -is [System.Windows.Media.Visual]) {
                $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
            } else { break }
        }
        $cbSkipVendorUninst.IsChecked = -not ($cbSkipVendorUninst.IsChecked -eq $true)
    })
}

$script:cachedUninstallerApps = @()
$script:uninstallerRowEntries = [System.Collections.Generic.List[object]]::new()
$script:uninstallerFilterMode = "All"
$script:uninstallerSortMode   = "Name"
$script:autoSilentUninstall   = $true
$script:uninstallerIconCache  = [System.Collections.Generic.Dictionary[string, System.Windows.Media.ImageSource]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:pendingUninstIcons    = [System.Collections.Generic.List[hashtable]]::new()

$script:brushUninstRowBg              = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x0E, 0x13, 0x1D)); $script:brushUninstRowBg.Freeze()
$script:brushUninstRowBorder          = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(0x13, 0xFF, 0xFF, 0xFF)); $script:brushUninstRowBorder.Freeze()
$script:brushUninstColDivider         = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(0x11, 0xFF, 0xFF, 0xFF)); $script:brushUninstColDivider.Freeze()
$script:brushUninstRowHover           = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x16, 0x20, 0x32)); $script:brushUninstRowHover.Freeze()
$script:brushUninstRowCheckedBg       = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x10, 0x24, 0x3A)); $script:brushUninstRowCheckedBg.Freeze()
$script:brushUninstRowCheckedBorder   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x02, 0x84, 0xC7)); $script:brushUninstRowCheckedBorder.Freeze()
$script:brushUninstTitle              = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF1, 0xF5, 0xF9)); $script:brushUninstTitle.Freeze()
$script:brushUninstTitleBroken        = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xFC, 0xA5, 0xA5)); $script:brushUninstTitleBroken.Freeze()
$script:brushUninstMuted              = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x94, 0xA3, 0xB8)); $script:brushUninstMuted.Freeze()
$script:brushUninstDark               = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x64, 0x74, 0x8B)); $script:brushUninstDark.Freeze()
$script:brushUninstLight              = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xCB, 0xD5, 0xE1)); $script:brushUninstLight.Freeze()
$script:brushUninstBadgeBg            = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x15, 0x21, 0x36)); $script:brushUninstBadgeBg.Freeze()
$script:brushUninstBadgeFg            = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushUninstBadgeFg.Freeze()
$script:brushUninstBadgeBrokenBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x3B, 0x12, 0x18)); $script:brushUninstBadgeBrokenBg.Freeze()
$script:brushUninstBadgeBrokenFg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF8, 0x71, 0x71)); $script:brushUninstBadgeBrokenFg.Freeze()
$script:brushUninstStatusBrokenBg     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x2D, 0x12, 0x15)); $script:brushUninstStatusBrokenBg.Freeze()
$script:brushUninstStatusBrokenBorder = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xE1, 0x1D, 0x48)); $script:brushUninstStatusBrokenBorder.Freeze()
$script:brushUninstStatusOkBg         = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x0C, 0x25, 0x18)); $script:brushUninstStatusOkBg.Freeze()
$script:brushUninstStatusOkBorder     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x10, 0xB9, 0x81)); $script:brushUninstStatusOkBorder.Freeze()
$script:brushUninstStatusOkFg         = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x34, 0xD3, 0x99)); $script:brushUninstStatusOkFg.Freeze()
$script:brushUninstFolderBg           = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1E, 0x29, 0x3B)); $script:brushUninstFolderBg.Freeze()
$script:brushUninstFolderBorder       = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x42, 0x54, 0x6E)); $script:brushUninstFolderBorder.Freeze()
$script:brushUninstFilterActiveBg     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1E, 0x29, 0x3B)); $script:brushUninstFilterActiveBg.Freeze()
$script:brushUninstFilterActiveFg     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushUninstFilterActiveFg.Freeze()
$script:brushUninstHeaderInactiveFg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x7C, 0x8D, 0xA4)); $script:brushUninstHeaderInactiveFg.Freeze()

$script:catalogIconLookup = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if ($AppCatalog) {
    foreach ($catApp in $AppCatalog) {
        $pngFile = Join-Path $iconsCacheDir "$($catApp.ID).png"
        if ($catApp.ID) { $script:catalogIconLookup[$catApp.ID] = $pngFile }
        if ($catApp.Name) { $script:catalogIconLookup[$catApp.Name] = $pngFile }
        if ($catApp.Aliases) {
            foreach ($al in $catApp.Aliases) {
                if (-not [string]::IsNullOrWhiteSpace($al)) {
                    $script:catalogIconLookup[$al] = $pngFile
                }
            }
        }
    }
}

function Resolve-UninstallerCatalogPng {
    param($App)
    if (-not $App) { return "" }
    $candPath = ""
    if ($App.Id -and $script:catalogIconLookup.TryGetValue($App.Id, [ref]$candPath) -and [System.IO.File]::Exists($candPath)) {
        return $candPath
    }
    if ($App.DisplayName -and $script:catalogIconLookup.TryGetValue($App.DisplayName, [ref]$candPath) -and [System.IO.File]::Exists($candPath)) {
        return $candPath
    }

    $dn = if ($App.DisplayName) { $App.DisplayName } else { "" }
    $cleanDn = ($dn -replace '\(.*?\)', '' -replace '\b(version|v)?\s*\d+(\.\d+)+[^\s]*', '').Trim()
    if ($cleanDn -and $script:catalogIconLookup.TryGetValue($cleanDn, [ref]$candPath) -and [System.IO.File]::Exists($candPath)) {
        return $candPath
    }

    $fallbackRules = @(
        @{ Pattern = 'Visual Studio Code|VS Code';              Id = 'Microsoft.VisualStudioCode' },
        @{ Pattern = 'Visual C\+\+|VCRedist';                   Id = 'Microsoft.VCRedist.2015+.x64' },
        @{ Pattern = 'ASP\.NET|\.NET SDK|Desktop Runtime|\.NET'; Id = 'Microsoft.DotNet.DesktopRuntime.8' },
        @{ Pattern = 'Corretto';                                Id = 'Amazon.Corretto.21.JDK' },
        @{ Pattern = 'Temurin|Adoptium';                        Id = 'EclipseAdoptium.Temurin.21.JDK' },
        @{ Pattern = 'Java \d+|Java\(TM\)|OpenJDK';             Id = 'Oracle.JavaRuntimeEnvironment' },
        @{ Pattern = 'Node\.js';                                Id = 'OpenJS.NodeJS.LTS' },
        @{ Pattern = 'GitHub CLI';                              Id = 'GitHub.cli' },
        @{ Pattern = '^Git\b';                                  Id = 'Git.Git' },
        @{ Pattern = 'Python';                                  Id = 'Python.Python.3.13' },
        @{ Pattern = 'Rustup';                                  Id = 'Rustlang.Rustup' },
        @{ Pattern = 'Gitleaks';                                Id = 'Gitleaks.Gitleaks' },
        @{ Pattern = 'PowerToys';                               Id = 'Microsoft.PowerToys' },
        @{ Pattern = 'Legacy Launcher';                         Id = 'LegacyLauncher.LegacyLauncher' },
        @{ Pattern = 'Google Chrome';                           Id = 'Google.Chrome' },
        @{ Pattern = 'Chrome Remote Desktop';                   Id = 'Google.ChromeRemoteDesktopHost' },
        @{ Pattern = 'Brave';                                   Id = 'Brave.Brave' },
        @{ Pattern = 'Firefox';                                 Id = 'Mozilla.Firefox' },
        @{ Pattern = 'Microsoft Edge';                          Id = 'Microsoft.Edge' },
        @{ Pattern = 'Discord';                                 Id = 'Discord.Discord' },
        @{ Pattern = 'Zalo';                                    Id = 'VNG.Zalo' },
        @{ Pattern = 'Docker Desktop';                          Id = 'Docker.DockerDesktop' },
        @{ Pattern = 'Ollama';                                  Id = 'Ollama.Ollama' },
        @{ Pattern = 'Antigravity IDE';                         Id = 'Google.AntigravityIDE' },
        @{ Pattern = '^Antigravity';                            Id = 'Google.Antigravity' },
        @{ Pattern = 'WebStorm';                                Id = 'JetBrains.WebStorm' },
        @{ Pattern = 'Android Studio';                          Id = 'Google.AndroidStudio' },
        @{ Pattern = 'Visual Studio|vs_';                       Id = 'Microsoft.VisualStudio.2022.Community' },
        @{ Pattern = 'Windows Software Development Kit|Windows SDK'; Id = 'Microsoft.WindowsTerminal' }
    )
    foreach ($rule in $fallbackRules) {
        if ($dn -match $rule.Pattern) {
            $p = Join-Path $iconsCacheDir "$($rule.Id).png"
            if ([System.IO.File]::Exists($p)) { return $p }
        }
    }
    return ""
}

function Get-UninstallerBestIconTarget {
    param($App)
    if (-not $App) { return "" }
    $srcPath = if ($App.IconSourcePath) { $App.IconSourcePath } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($srcPath) -and [System.IO.File]::Exists($srcPath)) {
        $fn = [System.IO.Path]::GetFileNameWithoutExtension($srcPath).ToLowerInvariant()
        $inPkgCache = $srcPath.IndexOf("\Package Cache\", [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        if ((-not $inPkgCache) -and ($fn -notmatch 'unins|vc_redist|vcredist')) {
            return $srcPath
        }
    }

    $catPng = Resolve-UninstallerCatalogPng -App $App
    if (-not [string]::IsNullOrWhiteSpace($catPng)) {
        return $catPng
    }

    if (-not [string]::IsNullOrWhiteSpace($srcPath) -and [System.IO.File]::Exists($srcPath)) {
        return $srcPath
    }

    $msiExe = Join-Path $env:WINDIR "System32\msiexec.exe"
    if ([System.IO.File]::Exists($msiExe)) {
        return $msiExe
    }
    return ""
}

function ConvertTo-UninstallerBitmapSource {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $cachedImg = $null
    if ($script:uninstallerIconCache.TryGetValue($Path, [ref]$cachedImg)) {
        return $cachedImg
    }
    if (-not [System.IO.File]::Exists($Path)) { return $null }

    $resultBmp = $null
    try {
        $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
        if ($ext -eq ".png") {
            $resultBmp = Import-LocalIconBitmap -Path $Path -CacheKey "UNINST_PNG|$Path"
        } elseif ($ext -eq ".ico" -or [string]::IsNullOrEmpty($ext)) {
            $bytes = [System.IO.File]::ReadAllBytes($Path)
            if ($bytes -and $bytes.Length -gt 6 -and $bytes[0] -eq 0 -and $bytes[1] -eq 0 -and ($bytes[2] -eq 1 -or $bytes[2] -eq 2) -and $bytes[3] -eq 0) {
                $ms = [System.IO.MemoryStream]::new($bytes)
                try {
                    $ico = [System.Drawing.Icon]::new($ms, 32, 32)
                    try {
                        $bs = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                            $ico.Handle,
                            [System.Windows.Int32Rect]::Empty,
                            [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
                        )
                        $bs.Freeze()
                        $resultBmp = $bs
                    } finally {
                        $ico.Dispose()
                    }
                } finally {
                    $ms.Dispose()
                }
            }
        }

        if (-not $resultBmp) {
            $assocIco = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
            if ($assocIco) {
                try {
                    $bs2 = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                        $assocIco.Handle,
                        [System.Windows.Int32Rect]::Empty,
                        [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
                    )
                    $bs2.Freeze()
                    $resultBmp = $bs2
                } finally {
                    $assocIco.Dispose()
                }
            }
        }
    } catch {}

    if ($resultBmp) {
        $script:uninstallerIconCache[$Path] = $resultBmp
    }
    return $resultBmp
}

$script:uninstIconTimer = [System.Windows.Threading.DispatcherTimer]::new([System.Windows.Threading.DispatcherPriority]::Background)
$script:uninstIconTimer.Interval = [TimeSpan]::FromMilliseconds(25)
$script:uninstIconTimer.Add_Tick({
    if ($script:isWindowClosing) {
        $script:uninstIconTimer.Stop()
        return
    }
    if ($script:isUpdatingUninstaller) { return }
    if (-not $script:pendingUninstIcons -or $script:pendingUninstIcons.Count -eq 0) {
        $script:uninstIconTimer.Stop()
        return
    }
    $batch = 0
    while (-not $script:isWindowClosing -and -not $script:isUpdatingUninstaller -and $script:pendingUninstIcons.Count -gt 0 -and $batch -lt 4) {
        $item = $script:pendingUninstIcons[0]
        $script:pendingUninstIcons.RemoveAt(0)
        $batch++
        $bmp = ConvertTo-UninstallerBitmapSource -Path $item.Target
        if ($bmp) {
            $item.Img.Source = $bmp
            $item.Img.Visibility = [System.Windows.Visibility]::Visible
            $item.Fallback.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }
    if ($script:isWindowClosing -or $script:pendingUninstIcons.Count -eq 0) {
        $script:uninstIconTimer.Stop()
    }
})

function Update-UninstallerSelectionCount {
    if ($script:suppressUninstallerSelectionCount -or $script:isWindowClosing) { return }
    $count = 0
    foreach ($entry in $script:uninstallerRowEntries) {
        if ($entry.CheckBox -and $entry.CheckBox.IsChecked -eq $true) {
            $count++
        }
    }
    if ($btnDeepUninstall) {
        $btnDeepUninstall.Content = "Gỡ cài đặt ($count)"
        $btnDeepUninstall.IsEnabled = ($count -gt 0)
    }
    if ($btnForceStopUninstall) {
        $btnForceStopUninstall.Content = "Buộc dừng & Xóa ($count)"
        $btnForceStopUninstall.IsEnabled = ($count -gt 0)
    }
}

function Apply-UninstallerFilter {
    if ($script:isWindowClosing) { return }
    $q = if ($txtUninstallSearch) { $txtUninstallSearch.Text.Trim().ToLowerInvariant() } else { "" }
    $visibleCount = 0
    $brokenCount = 0
    [long]$visibleBytes = 0

    foreach ($entry in $script:uninstallerRowEntries) {
        $app = $entry.App
        if ($app.IsBrokenOrphan) { $brokenCount++ }

        $matchSearch = [string]::IsNullOrEmpty($q) -or $entry.SearchText.Contains($q)
        $matchFilter = if ($script:uninstallerFilterMode -eq "Broken") { [bool]$app.IsBrokenOrphan } else { $true }

        if ($matchSearch -and $matchFilter) {
            $entry.Row.Visibility = [System.Windows.Visibility]::Visible
            $visibleCount++
            if ($app.SizeBytes -and $app.SizeBytes -gt 0) {
                $visibleBytes += [long]$app.SizeBytes
            }
        } else {
            $entry.Row.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }

    if ($txtUninstallerSummary) {
        $total = $script:cachedUninstallerApps.Count
        $vMb = [double]$visibleBytes / 1MB
        $totalSizeStr = if ($vMb -ge 1024) { "{0:N2} GB" -f ($vMb / 1024.0) } else { "{0:N1} MB" -f $vMb }
        $txtUninstallerSummary.Text = "Đang hiển thị $visibleCount / $total ứng dụng (Tổng: $totalSizeStr • $brokenCount lỗi/mồ côi)"
    }
    Update-UninstallerSelectionCount
}

function Set-UninstallerSortMode {
    param(
        [string]$Mode,
        [switch]$HeadersOnly
    )
    if ($script:isWindowClosing -or $script:isSortingUninstaller) { return }
    $script:isSortingUninstaller = $true
    try {
        if ([string]::IsNullOrWhiteSpace($Mode)) { $Mode = "Name" }
        $script:uninstallerSortMode = $Mode

        if ($Mode -eq "Size") {
            if ($btnSortUninstSize) {
                $btnSortUninstSize.Background = $script:brushUninstFilterActiveBg
                $btnSortUninstSize.Foreground = $script:brushUninstFilterActiveFg
            }
            if ($btnSortUninstName) {
                $btnSortUninstName.Background = $script:brushTransparent
                $btnSortUninstName.Foreground = $script:brushUninstDark
            }
            if ($hdrUninstName) {
                $hdrUninstName.Text = "TÊN ỨNG DỤNG"
                $hdrUninstName.Foreground = $script:brushUninstHeaderInactiveFg
            }
            if ($hdrUninstSize) {
                $hdrUninstSize.Text = "DUNG LƯỢNG"
                $hdrUninstSize.Foreground = $script:brushUninstFilterActiveFg
            }
        } else {
            if ($btnSortUninstName) {
                $btnSortUninstName.Background = $script:brushUninstFilterActiveBg
                $btnSortUninstName.Foreground = $script:brushUninstFilterActiveFg
            }
            if ($btnSortUninstSize) {
                $btnSortUninstSize.Background = $script:brushTransparent
                $btnSortUninstSize.Foreground = $script:brushUninstDark
            }
            if ($hdrUninstName) {
                $hdrUninstName.Text = "TÊN ỨNG DỤNG"
                $hdrUninstName.Foreground = $script:brushUninstFilterActiveFg
            }
            if ($hdrUninstSize) {
                $hdrUninstSize.Text = "DUNG LƯỢNG"
                $hdrUninstSize.Foreground = $script:brushUninstHeaderInactiveFg
            }
        }

        if (-not $HeadersOnly -and $uninstallerRowsPanel -and $script:uninstallerRowEntries -and $script:uninstallerRowEntries.Count -gt 0) {
            $sortedEntries = if ($Mode -eq "Size") {
                @($script:uninstallerRowEntries | Sort-Object -Property @{ Expression = { [long]$_.App.SizeBytes }; Descending = $true }, @{ Expression = { $_.App.DisplayName }; Descending = $false })
            } else {
                @($script:uninstallerRowEntries | Sort-Object -Property @{ Expression = { [bool]$_.App.IsBrokenOrphan }; Descending = $true }, @{ Expression = { $_.App.DisplayName }; Descending = $false })
            }
            $prevVis = $uninstallerRowsPanel.Visibility
            $uninstallerRowsPanel.Visibility = [System.Windows.Visibility]::Collapsed
            try {
                $script:uninstallerRowEntries.Clear()
                $uninstallerRowsPanel.Children.Clear()
                foreach ($entry in $sortedEntries) {
                    [void]$script:uninstallerRowEntries.Add($entry)
                    [void]$uninstallerRowsPanel.Children.Add($entry.Row)
                }
            } finally {
                $uninstallerRowsPanel.Visibility = $prevVis
            }
        }
        Apply-UninstallerFilter
    } finally {
        $script:isSortingUninstaller = $false
    }
}

$script:uninstCbCheckedHandler = [System.Windows.RoutedEventHandler]{
    param($s, $e)
    $p = $s.Tag
    if ($p) {
        $p.Background = $script:brushUninstRowCheckedBg
    }
    Update-UninstallerSelectionCount
}
$script:uninstCbUncheckedHandler = [System.Windows.RoutedEventHandler]{
    param($s, $e)
    $p = $s.Tag
    if ($p) {
        $p.Background = $script:brushUninstRowBg
    }
    Update-UninstallerSelectionCount
}
$script:uninstRowEnterHandler = [System.Windows.Input.MouseEventHandler]{
    param($sender, $e)
    if ($sender.Tag -and -not $sender.Tag.CheckBox.IsChecked) {
        $sender.Background = $script:brushUninstRowHover
    }
}
$script:uninstRowLeaveHandler = [System.Windows.Input.MouseEventHandler]{
    param($sender, $e)
    if ($sender.Tag -and -not $sender.Tag.CheckBox.IsChecked) {
        $sender.Background = $script:brushUninstRowBg
    }
}
$script:uninstRowClickHandler = [System.Windows.Input.MouseButtonEventHandler]{
    param($sender, $e)
    if ($e.Handled -or $script:isWindowClosing -or $script:isUpdatingUninstaller -or $script:isActionRunning) { return }
    $src = $e.OriginalSource
    $node = $src
    while ($node -ne $null -and $node -ne $sender) {
        if ($node -is [System.Windows.Controls.CheckBox]) { return }
        if ($node -is [System.Windows.Media.Visual]) {
            $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
        } else { break }
    }
    if ($sender.Tag -and $sender.Tag.CheckBox) {
        $cbRef = $sender.Tag.CheckBox
        $cbRef.IsChecked = -not $cbRef.IsChecked
    }
}
$script:uninstFolderClickHandler = [System.Windows.Input.MouseButtonEventHandler]{
    param($s, $e)
    $e.Handled = $true
    $loc = [string]$s.Tag
    if (-not [string]::IsNullOrWhiteSpace($loc) -and (Test-Path -LiteralPath $loc)) {
        try { Start-Process "explorer.exe" "`"$loc`"" } catch {}
    }
}

$glUninstCol0 = New-Object System.Windows.GridLength(38, [System.Windows.GridUnitType]::Pixel)
$glUninstCol1 = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
$glUninstCol2 = New-Object System.Windows.GridLength(130, [System.Windows.GridUnitType]::Pixel)
$glUninstCol3 = New-Object System.Windows.GridLength(220, [System.Windows.GridUnitType]::Pixel)
$glUninstCol4 = New-Object System.Windows.GridLength(105, [System.Windows.GridUnitType]::Pixel)
$glUninstCol5 = New-Object System.Windows.GridLength(115, [System.Windows.GridUnitType]::Pixel)
$glUninstCol6 = New-Object System.Windows.GridLength(54, [System.Windows.GridUnitType]::Pixel)
$glUninstNameIcon = New-Object System.Windows.GridLength(28, [System.Windows.GridUnitType]::Pixel)

$cornerUninstRow    = New-Object System.Windows.CornerRadius(0)
$thicknessTableRow  = New-Object System.Windows.Thickness(1, 0, 1, 1)
$marginUninstName   = New-Object System.Windows.Thickness(10, 0, 10, 0)
$marginUninstCol    = New-Object System.Windows.Thickness(10, 0, 10, 0)
$marginUninstSize   = New-Object System.Windows.Thickness(8, 0, 12, 0)
$paddingUninstBadge = New-Object System.Windows.Thickness(8, 2, 8, 2)
$strFolderEmoji     = [char]::ConvertFromUtf32(0x1F4C1)

function Update-UninstallerList {
    param([switch]$Force)
    if ($script:isWindowClosing -or $script:isUpdatingUninstaller) { return }
    if (-not $Force -and ($script:isActionRunning -or $script:isScanningApps)) {
        $script:deferredUninstallerLoad = $true
        if ($txtUninstallerSummary -and -not $script:uninstallerLoadedOnce) {
            $txtUninstallerSummary.Text = "Đang chờ tác vụ hiện tại hoàn tất để tải danh sách ứng dụng..."
        }
        return
    }
    if (-not $Force -and $script:uninstallerLoadedOnce -and -not $script:deferredUninstallerLoad) { return }
    if (-not $uninstallerRowsPanel) { return }

    $script:isUpdatingUninstaller = $true
    $script:suppressUninstallerSelectionCount = $true
    try {
        if ($txtUninstallerSummary) { $txtUninstallerSummary.Text = "Đang quét danh sách ứng dụng đã cài..." }

        $script:uninstIconTimer.Stop()
        $script:pendingUninstIcons.Clear()

        $deepType = "DuckUtil.DeepUninstallerEngine" -as [type]
        if ($deepType -and $null -ne $deepType.GetMethod("GetInstalledAppsAsync")) {
            $scanTask = $deepType::GetInstalledAppsAsync()
            [void](Wait-TaskNonBlocking -Task $scanTask -TimeoutSeconds 45)
            if ($script:isWindowClosing) { return }
            if ($scanTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                $script:cachedUninstallerApps = @($scanTask.Result)
            } elseif (Get-Command "Get-SystemInstalledAppsFast" -ErrorAction SilentlyContinue) {
                $script:cachedUninstallerApps = @(Get-SystemInstalledAppsFast)
            } else {
                $script:cachedUninstallerApps = @()
            }
        } elseif (Get-Command "Get-SystemInstalledAppsFast" -ErrorAction SilentlyContinue) {
            $script:cachedUninstallerApps = @(Get-SystemInstalledAppsFast)
        } else {
            $script:cachedUninstallerApps = @()
        }
        if ($script:isWindowClosing) { return }

        $sortedApps = if ($script:uninstallerSortMode -eq "Size") {
            @($script:cachedUninstallerApps | Sort-Object -Property @{ Expression = { [long]$_.SizeBytes }; Descending = $true }, @{ Expression = { $_.DisplayName }; Descending = $false })
        } else {
            @($script:cachedUninstallerApps | Sort-Object -Property @{ Expression = { [bool]$_.IsBrokenOrphan }; Descending = $true }, @{ Expression = { $_.DisplayName }; Descending = $false })
        }

        $uninstallerRowsPanel.Visibility = [System.Windows.Visibility]::Collapsed
        try {
            $uninstallerRowsPanel.Children.Clear()
            $script:uninstallerRowEntries.Clear()

            foreach ($app in $sortedApps) {
                if ($script:isWindowClosing) { return }
                $rowBorder = [System.Windows.Controls.Border]::new()
                $rowBorder.Height = 38
                $rowBorder.CornerRadius = $cornerUninstRow
                $rowBorder.Padding = $thicknessZero
                $rowBorder.Margin = $thicknessZero
                $rowBorder.Background = $script:brushUninstRowBg
                $rowBorder.BorderBrush = $script:brushUninstRowBorder
                $rowBorder.BorderThickness = $thicknessTableRow
                $rowBorder.SnapsToDevicePixels = $true
                $rowBorder.Cursor = [System.Windows.Input.Cursors]::Hand

                $rowGrid = [System.Windows.Controls.Grid]::new()
                $rowGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Stretch
                $rowGrid.SnapsToDevicePixels = $true

                $c0 = [System.Windows.Controls.ColumnDefinition]::new(); $c0.Width = $glUninstCol0
                $c1 = [System.Windows.Controls.ColumnDefinition]::new(); $c1.Width = $glUninstCol1
                $c2 = [System.Windows.Controls.ColumnDefinition]::new(); $c2.Width = $glUninstCol2
                $c3 = [System.Windows.Controls.ColumnDefinition]::new(); $c3.Width = $glUninstCol3
                $c4 = [System.Windows.Controls.ColumnDefinition]::new(); $c4.Width = $glUninstCol4
                $c5 = [System.Windows.Controls.ColumnDefinition]::new(); $c5.Width = $glUninstCol5
                $c6 = [System.Windows.Controls.ColumnDefinition]::new(); $c6.Width = $glUninstCol6

                [void]$rowGrid.ColumnDefinitions.Add($c0)
                [void]$rowGrid.ColumnDefinitions.Add($c1)
                [void]$rowGrid.ColumnDefinitions.Add($c2)
                [void]$rowGrid.ColumnDefinitions.Add($c3)
                [void]$rowGrid.ColumnDefinitions.Add($c4)
                [void]$rowGrid.ColumnDefinitions.Add($c5)
                [void]$rowGrid.ColumnDefinitions.Add($c6)

                $cb = [System.Windows.Controls.CheckBox]::new()
                $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $cb.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
                $cb.Margin = $thicknessZero
                $cb.Tag = $rowBorder
                $cb.Add_Checked($script:uninstCbCheckedHandler)
                $cb.Add_Unchecked($script:uninstCbUncheckedHandler)

                [System.Windows.Controls.Grid]::SetColumn($cb, 0)
                [void]$rowGrid.Children.Add($cb)

                $nameGrid = [System.Windows.Controls.Grid]::new()
                $nameGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $nameGrid.Margin = $marginUninstName
                $ng0 = [System.Windows.Controls.ColumnDefinition]::new(); $ng0.Width = $glUninstNameIcon
                $ng1 = [System.Windows.Controls.ColumnDefinition]::new(); $ng1.Width = $glUninstCol1
                [void]$nameGrid.ColumnDefinitions.Add($ng0)
                [void]$nameGrid.ColumnDefinitions.Add($ng1)

                $iconSlotGrid = [System.Windows.Controls.Grid]::new()
                $iconSlotGrid.Width = 20
                $iconSlotGrid.Height = 20
                $iconSlotGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $iconSlotGrid.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left

                $fallbackBadge = [System.Windows.Controls.Border]::new()
                $fallbackBadge.Width = 20
                $fallbackBadge.Height = 20
                $fallbackBadge.CornerRadius = $cornerFour
                $fallbackBadge.Background = if ($app.IsBrokenOrphan) { $script:brushUninstBadgeBrokenBg } else { $script:brushUninstBadgeBg }
                $fallbackBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $fallbackBadge.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center

                $badgeTb = [System.Windows.Controls.TextBlock]::new()
                $dispTrim = if ($app.DisplayName) { $app.DisplayName.Trim() } else { "A" }
                $badgeTb.Text = if ($app.IsBrokenOrphan) { "!" } elseif ($dispTrim.Length -gt 0) { [string]$dispTrim.Substring(0, 1).ToUpper() } else { "•" }
                $badgeTb.FontSize = 10.5
                $badgeTb.FontWeight = [System.Windows.FontWeights]::Bold
                $badgeTb.Foreground = if ($app.IsBrokenOrphan) { $script:brushUninstBadgeBrokenFg } else { $script:brushUninstBadgeFg }
                $badgeTb.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
                $badgeTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $fallbackBadge.Child = $badgeTb

                $img = [System.Windows.Controls.Image]::new()
                $img.Width = 20
                $img.Height = 20
                $img.Stretch = [System.Windows.Media.Stretch]::Uniform
                [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::LowQuality)
                $img.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $img.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
                $img.Visibility = [System.Windows.Visibility]::Collapsed

                [void]$iconSlotGrid.Children.Add($fallbackBadge)
                [void]$iconSlotGrid.Children.Add($img)

                $bestTarget = Get-UninstallerBestIconTarget -App $app
                if (-not [string]::IsNullOrWhiteSpace($bestTarget)) {
                    $cachedBmp = $null
                    if ($script:uninstallerIconCache.TryGetValue($bestTarget, [ref]$cachedBmp) -and $cachedBmp) {
                        $img.Source = $cachedBmp
                        $img.Visibility = [System.Windows.Visibility]::Visible
                        $fallbackBadge.Visibility = [System.Windows.Visibility]::Collapsed
                    } else {
                        $script:pendingUninstIcons.Add(@{
                            Target   = $bestTarget
                            Img      = $img
                            Fallback = $fallbackBadge
                        })
                    }
                }

                [System.Windows.Controls.Grid]::SetColumn($iconSlotGrid, 0)
                [void]$nameGrid.Children.Add($iconSlotGrid)

                $nameTb = [System.Windows.Controls.TextBlock]::new()
                $nameTb.Text = $app.DisplayName
                $nameTb.FontSize = 12
                $nameTb.FontWeight = [System.Windows.FontWeights]::SemiBold
                $nameTb.Foreground = if ($app.IsBrokenOrphan) { $script:brushUninstTitleBroken } else { $script:brushUninstTitle }
                $nameTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $nameTb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
                $nameTb.Margin = $thicknessZero
                [System.Windows.Controls.Grid]::SetColumn($nameTb, 1)
                [void]$nameGrid.Children.Add($nameTb)

                $dataTip = if ($app.PSObject.Properties['DataLocation'] -and -not [string]::IsNullOrWhiteSpace($app.DataLocation)) { "`nKhu dữ liệu riêng: $($app.DataLocation)" } else { "" }
                $rowBorder.ToolTip = "$($app.DisplayName)`nPhiên bản: $($app.DisplayVersion)`nNhà phát hành: $($app.Publisher)`nĐường dẫn: $($app.InstallLocation)$dataTip`nLệnh gỡ: $($app.UninstallString)"
                [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($rowBorder, 5000)

                [System.Windows.Controls.Grid]::SetColumn($nameGrid, 1)
                [void]$rowGrid.Children.Add($nameGrid)

                $verTb = [System.Windows.Controls.TextBlock]::new()
                $verTb.Text = if ($app.DisplayVersion) { $app.DisplayVersion } else { "--" }
                $verTb.FontSize = 11.5
                $verTb.Foreground = $script:brushUninstMuted
                $verTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $verTb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
                $verTb.Margin = $marginUninstCol
                [System.Windows.Controls.Grid]::SetColumn($verTb, 2)
                [void]$rowGrid.Children.Add($verTb)

                $pubTb = [System.Windows.Controls.TextBlock]::new()
                $pubTb.Text = if ($app.Publisher) { $app.Publisher } else { "--" }
                $pubTb.FontSize = 11.5
                $pubTb.Foreground = $script:brushUninstMuted
                $pubTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $pubTb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
                $pubTb.Margin = $marginUninstCol
                [System.Windows.Controls.Grid]::SetColumn($pubTb, 3)
                [void]$rowGrid.Children.Add($pubTb)

                $sizeText = if ($app.SizeBytes -and $app.SizeBytes -gt 0) {
                    $mb = [double]$app.SizeBytes / 1MB
                    if ($mb -ge 1024) { "{0:N2} GB" -f ($mb / 1024.0) } else { "{0:N1} MB" -f $mb }
                } else {
                    "--"
                }
                $sizeTb = [System.Windows.Controls.TextBlock]::new()
                $sizeTb.Text = $sizeText
                $sizeTb.FontSize = 11.5
                $sizeTb.Foreground = $script:brushUninstLight
                $sizeTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $sizeTb.TextAlignment = [System.Windows.TextAlignment]::Right
                $sizeTb.Margin = $marginUninstSize
                [System.Windows.Controls.Grid]::SetColumn($sizeTb, 4)
                [void]$rowGrid.Children.Add($sizeTb)

                $statusBorder = [System.Windows.Controls.Border]::new()
                $statusBorder.CornerRadius = $cornerFour
                $statusBorder.Padding = $paddingUninstBadge
                $statusBorder.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
                $statusBorder.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $statusBorder.BorderThickness = $thicknessOne

                $statusTb = [System.Windows.Controls.TextBlock]::new()
                $statusTb.FontSize = 10.5
                $statusTb.FontWeight = [System.Windows.FontWeights]::SemiBold

                if ($app.IsBrokenOrphan) {
                    $statusBorder.Background = $script:brushUninstStatusBrokenBg
                    $statusBorder.BorderBrush = $script:brushUninstStatusBrokenBorder
                    $statusTb.Text = "Xóa sai cách"
                    $statusTb.Foreground = $script:brushUninstBadgeBrokenFg
                } else {
                    $statusBorder.Background = $script:brushUninstStatusOkBg
                    $statusBorder.BorderBrush = $script:brushUninstStatusOkBorder
                    $statusTb.Text = "Bình thường"
                    $statusTb.Foreground = $script:brushUninstStatusOkFg
                }
                $statusBorder.Child = $statusTb
                [System.Windows.Controls.Grid]::SetColumn($statusBorder, 5)
                [void]$rowGrid.Children.Add($statusBorder)

                $folderBtn = [System.Windows.Controls.Border]::new()
                $folderBtn.Width = 26
                $folderBtn.Height = 24
                $folderBtn.CornerRadius = $cornerFour
                $folderBtn.Background = $script:brushUninstFolderBg
                $folderBtn.BorderBrush = $script:brushUninstFolderBorder
                $folderBtn.BorderThickness = $thicknessOne
                $folderBtn.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
                $folderBtn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

                $folderIcon = [System.Windows.Controls.TextBlock]::new()
                $folderIcon.Text = $strFolderEmoji
                $folderIcon.FontSize = 10.5
                $folderIcon.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
                $folderIcon.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $folderBtn.Child = $folderIcon

                $targetFolder = if ($app.PSObject.Properties['TargetFolder'] -and $null -ne $app.TargetFolder) {
                    $app.TargetFolder
                } elseif (-not [string]::IsNullOrWhiteSpace($app.InstallLocation) -and [System.IO.Directory]::Exists($app.InstallLocation)) {
                    $app.InstallLocation
                } elseif ($app.PSObject.Properties['DataLocation'] -and -not [string]::IsNullOrWhiteSpace($app.DataLocation) -and [System.IO.Directory]::Exists($app.DataLocation)) {
                    $app.DataLocation
                } else {
                    ""
                }
                if (-not [string]::IsNullOrWhiteSpace($targetFolder)) {
                    $folderBtn.Cursor = [System.Windows.Input.Cursors]::Hand
                    $folderBtn.Tag = $targetFolder
                    $folderBtn.ToolTip = "Mở thư mục: $targetFolder"
                    $folderBtn.Add_MouseLeftButtonUp($script:uninstFolderClickHandler)
                } else {
                    $folderBtn.Opacity = 0.25
                    $folderBtn.Cursor = [System.Windows.Input.Cursors]::Arrow
                    $folderBtn.ToolTip = "Không tìm thấy thư mục cài đặt"
                }
                [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($folderBtn, 5000)
                [System.Windows.Controls.Grid]::SetColumn($folderBtn, 6)
                [void]$rowGrid.Children.Add($folderBtn)

                for ($divCol = 0; $divCol -lt 6; $divCol++) {
                    $colDiv = [System.Windows.Controls.Border]::new()
                    $colDiv.Width = 1
                    $colDiv.Background = $script:brushUninstColDivider
                    $colDiv.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
                    $colDiv.VerticalAlignment = [System.Windows.VerticalAlignment]::Stretch
                    $colDiv.SnapsToDevicePixels = $true
                    $colDiv.IsHitTestVisible = $false
                    [System.Windows.Controls.Grid]::SetColumn($colDiv, $divCol)
                    [void]$rowGrid.Children.Add($colDiv)
                }

                $rowBorder.Child = $rowGrid
                $rowBorder.Add_MouseEnter($script:uninstRowEnterHandler)
                $rowBorder.Add_MouseLeave($script:uninstRowLeaveHandler)
                $rowBorder.Add_MouseLeftButtonUp($script:uninstRowClickHandler)

                $searchIdx = if ($app.PSObject.Properties['SearchIndex'] -and -not [string]::IsNullOrEmpty($app.SearchIndex)) {
                    $app.SearchIndex
                } else {
                    "$($app.DisplayName) $($app.Publisher) $($app.DisplayVersion)".ToLowerInvariant()
                }
                $entry = @{
                    Row = $rowBorder
                    App = $app
                    CheckBox = $cb
                    SearchText = $searchIdx
                }
                $rowBorder.Tag = $entry
                [void]$script:uninstallerRowEntries.Add($entry)
                [void]$uninstallerRowsPanel.Children.Add($rowBorder)
            }
        } finally {
            $uninstallerRowsPanel.Visibility = [System.Windows.Visibility]::Visible
        }
        if ($script:isWindowClosing) { return }

        $script:uninstallerLoadedOnce = $true
        $script:deferredUninstallerLoad = $false
        $script:uninstallerLoadQueued = $false
        Set-UninstallerSortMode $script:uninstallerSortMode -HeadersOnly
        if (-not $script:isWindowClosing -and $script:pendingUninstIcons.Count -gt 0) {
            $script:uninstIconTimer.Start()
        }
    } finally {
        $script:suppressUninstallerSelectionCount = $false
        $script:isUpdatingUninstaller = $false
        if (-not $script:isWindowClosing) {
            Update-UninstallerSelectionCount
        }
    }
}

if ($btnSortUninstName) {
    $btnSortUninstName.Add_Click({
        if ($script:isWindowClosing -or $script:isUpdatingUninstaller) { return }
        Set-UninstallerSortMode "Name"
    })
}

if ($btnSortUninstSize) {
    $btnSortUninstSize.Add_Click({
        if ($script:isWindowClosing -or $script:isUpdatingUninstaller) { return }
        Set-UninstallerSortMode "Size"
    })
}

if ($hdrUninstName) {
    $hdrUninstName.Add_MouseLeftButtonUp({
        if ($script:isWindowClosing -or $script:isUpdatingUninstaller) { return }
        Set-UninstallerSortMode "Name"
    })
}

if ($hdrUninstSize) {
    $hdrUninstSize.Add_MouseLeftButtonUp({
        if ($script:isWindowClosing -or $script:isUpdatingUninstaller) { return }
        Set-UninstallerSortMode "Size"
    })
}

if ($btnFilterUninstAll) {
    $btnFilterUninstAll.Add_Click({
        if ($script:isWindowClosing -or $script:isUpdatingUninstaller) { return }
        $script:uninstallerFilterMode = "All"
        $btnFilterUninstAll.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $btnFilterUninstAll.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
        $btnFilterUninstBroken.Background = $script:brushTransparent
        $btnFilterUninstBroken.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
        Apply-UninstallerFilter
    })
}

if ($btnFilterUninstBroken) {
    $btnFilterUninstBroken.Add_Click({
        if ($script:isWindowClosing -or $script:isUpdatingUninstaller) { return }
        $script:uninstallerFilterMode = "Broken"
        $btnFilterUninstBroken.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2D1215")
        $btnFilterUninstBroken.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
        $btnFilterUninstAll.Background = $script:brushTransparent
        $btnFilterUninstAll.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
        Apply-UninstallerFilter
    })
}

if ($txtUninstallSearch) {
    $txtUninstallSearch.Add_TextChanged({
        if ($script:isWindowClosing -or $script:isUpdatingUninstaller) { return }
        Apply-UninstallerFilter
    })
}

if ($btnClearUninstallSearch) {
    $btnClearUninstallSearch.Add_Click({
        if ($script:isWindowClosing -or $script:isUpdatingUninstaller) { return }
        if ($txtUninstallSearch) { $txtUninstallSearch.Text = "" }
        Apply-UninstallerFilter
    })
}

if ($btnUninstallSelectAll) {
    $btnUninstallSelectAll.Add_Click({
        if ($script:isWindowClosing -or $script:isUpdatingUninstaller -or $script:isActionRunning) { return }
        $script:suppressUninstallerSelectionCount = $true
        try {
            foreach ($entry in $script:uninstallerRowEntries) {
                if ($entry.Row.Visibility -eq [System.Windows.Visibility]::Visible) {
                    $entry.CheckBox.IsChecked = $true
                }
            }
        } finally {
            $script:suppressUninstallerSelectionCount = $false
        }
        Update-UninstallerSelectionCount
    })
}

if ($btnUninstallDeselectAll) {
    $btnUninstallDeselectAll.Add_Click({
        if ($script:isWindowClosing -or $script:isUpdatingUninstaller -or $script:isActionRunning) { return }
        $script:suppressUninstallerSelectionCount = $true
        try {
            foreach ($entry in $script:uninstallerRowEntries) {
                $entry.CheckBox.IsChecked = $false
            }
        } finally {
            $script:suppressUninstallerSelectionCount = $false
        }
        Update-UninstallerSelectionCount
    })
}

if ($btnRefreshUninstaller) {
    $btnRefreshUninstaller.Add_Click({
        Invoke-GuardedAction "Làm mới danh sách Gỡ cài đặt" -DeferExpand {
            Update-UninstallerList -Force
        }
    })
}

if ($btnDeepUninstall) {
    $btnDeepUninstall.Add_Click({
        Invoke-GuardedAction "Gỡ cài đặt ứng dụng" -DeferExpand {
            $selectedItems = @($script:uninstallerRowEntries | Where-Object { $_.CheckBox -and $_.CheckBox.IsChecked -eq $true } | ForEach-Object { $_.App })
            if ($selectedItems.Count -eq 0 -or $script:isWindowClosing) { return }

            $skipVendor = ($null -ne $cbSkipVendorUninst -and $cbSkipVendorUninst.IsChecked -eq $true)
            $appLines = @($selectedItems | ForEach-Object {
                $vPart = if (-not [string]::IsNullOrWhiteSpace($_.DisplayVersion)) { " ($($_.DisplayVersion))" } else { "" }
                "• $($_.DisplayName)$vPart"
            })

            if ($skipVendor) {
                $confirm = Show-OwnedMessageBox `
                    -Text "Bạn có chắc chắn muốn gỡ cài đặt $($selectedItems.Count) ứng dụng đã chọn?" `
                    -Caption "Xác nhận Gỡ cài đặt" `
                    -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) `
                    -PrimaryText "Gỡ ngay ($($selectedItems.Count))" `
                    -SecondaryText "Hủy bỏ" `
                    -DetailItems $appLines `
                    -ModeBadgeText "Bỏ qua trình gỡ hãng — Ép xóa trực tiếp" `
                    -ModeBadgeKind "Danger"
                $useAutoSilent = $false
            } else {
                $toggleState = @{
                    Checked = [bool]$script:autoSilentUninstall
                    Label   = "Tự động gắn cờ gỡ im lặng theo bộ cài"
                    HintOn  = "Tự nhận diện bộ cài (Inno, NSIS, WiX, MSI...) và gắn cờ chạy ngầm"
                    HintOff = "Mở trình gỡ gốc của hãng như bình thường (tắt gắn cờ im lặng)"
                }
                $confirm = Show-OwnedMessageBox `
                    -Text "Bạn có chắc chắn muốn gỡ cài đặt $($selectedItems.Count) ứng dụng đã chọn?" `
                    -Caption "Xác nhận Gỡ cài đặt" `
                    -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) `
                    -PrimaryText "Gỡ ngay ($($selectedItems.Count))" `
                    -SecondaryText "Hủy bỏ" `
                    -DetailItems $appLines `
                    -ToggleState $toggleState
                if (-not $script:isWindowClosing) {
                    $script:autoSilentUninstall = [bool]$toggleState.Checked
                }
                $useAutoSilent = [bool]$toggleState.Checked
            }

            if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes -or $script:isWindowClosing) { return }

            foreach ($item in $selectedItems) {
                if ($script:isWindowClosing) { break }
                if (Get-Command "Invoke-DeepAppUninstall" -ErrorAction SilentlyContinue) {
                    Invoke-DeepAppUninstall -AppEntry $item -OwnerWindow $window -SkipVendorUninstaller:$skipVendor -AutoSilent:$useAutoSilent
                }
            }
            if (-not $script:isWindowClosing) {
                Update-UninstallerList -Force
            }
        }
    })
}

if ($btnForceStopUninstall) {
    $btnForceStopUninstall.Add_Click({
        Invoke-GuardedAction "Buộc dừng & Xóa ứng dụng" -DeferExpand {
            $selectedItems = @($script:uninstallerRowEntries | Where-Object { $_.CheckBox -and $_.CheckBox.IsChecked -eq $true } | ForEach-Object { $_.App })
            if ($selectedItems.Count -eq 0 -or $script:isWindowClosing) { return }

            $appLines = @($selectedItems | ForEach-Object {
                $vPart = if (-not [string]::IsNullOrWhiteSpace($_.DisplayVersion)) { " ($($_.DisplayVersion))" } else { "" }
                "• $($_.DisplayName)$vPart"
            })
            $confirm = Show-OwnedMessageBox `
                -Text "Buộc dừng toàn bộ tiến trình/dịch vụ đang giữ tệp của $($selectedItems.Count) ứng dụng đã chọn và xóa trực tiếp không qua trình gỡ hãng?" `
                -Caption "Xác nhận Buộc dừng & Xóa" `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) `
                -PrimaryText "Buộc dừng & Xóa ($($selectedItems.Count))" `
                -SecondaryText "Hủy bỏ" `
                -DetailItems $appLines `
                -ModeBadgeText "Restart Manager + NtSuspend + Kill Tree + MoveFileEx (bỏ qua trình gỡ hãng)" `
                -ModeBadgeKind "Danger"
            if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes -or $script:isWindowClosing) { return }

            foreach ($item in $selectedItems) {
                if ($script:isWindowClosing) { break }
                if (Get-Command "Invoke-DeepAppUninstall" -ErrorAction SilentlyContinue) {
                    Invoke-DeepAppUninstall -AppEntry $item -OwnerWindow $window -SkipVendorUninstaller:$true -AutoSilent:$false -ForceStopAndDelete
                }
            }
            if (-not $script:isWindowClosing) {
                Update-UninstallerList -Force
            }
        }
    })
}

if ($btnScanOrphans) {
    $btnScanOrphans.Add_Click({
        Invoke-GuardedAction "Quét rác tồn dư & App xóa sai cách" -DeferExpand {
            if ($script:isWindowClosing) { return }
            if (Get-Command "Find-SystemOrphanLeftovers" -ErrorAction SilentlyContinue) {
                $orphans = @(Find-SystemOrphanLeftovers -InstalledApps $script:cachedUninstallerApps -CatalogApps $AppCatalog)
                if ($script:isWindowClosing) { return }
                if ($orphans.Count -eq 0) {
                    Show-OwnedMessageBox `
                        -Text "Không phát hiện tệp tin rác hoặc ứng dụng nào bị xóa sai cách trên hệ thống!" `
                        -Caption "Quét Rác Tồn Dư" `
                        -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                        -Icon ([System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                } else {
                    if (-not $script:isWindowClosing -and (Get-Command "Show-LeftoverReviewDialog" -ErrorAction SilentlyContinue)) {
                        Show-LeftoverReviewDialog -OwnerWindow $window -Items $orphans -Title "Quét Rác Tồn Dư & App Xóa Sai Cách"
                    }
                    if (-not $script:isWindowClosing) {
                        Update-UninstallerList -Force
                    }
                }
            }
        }
    })
}

function Expand-TerminalLog {
}

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

$script:colHeights = @(0, 0, 0, 0)

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

$cardCols = @(
    $window.FindName("CardsCol0"),
    $window.FindName("CardsCol1"),
    $window.FindName("CardsCol2"),
    $window.FindName("CardsCol3")
)

$script:remoteBmpCache = [System.Collections.Generic.Dictionary[string, System.Windows.Media.Imaging.BitmapImage]]::new([System.StringComparer]::OrdinalIgnoreCase)

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
$cornerFour         = [System.Windows.CornerRadius]::new(1)
$strOpenLinkGlyph   = [string][char]0x2197

$script:cbChangedHandler = [System.Windows.RoutedEventHandler]{ Update-SelectionCount }
$script:linkClickHandler = [System.Windows.Input.MouseButtonEventHandler]{
    param($s, $e)
    $e.Handled = $true
    if ($script:isActionRunning) { return }
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
    if ($script:isActionRunning) { return }

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

$appsByCategory = @{}
foreach ($item in $AppCatalog) {
    if (-not $appsByCategory.ContainsKey($item.Category)) {
        $appsByCategory[$item.Category] = [System.Collections.Generic.List[object]]::new()
    }
    $appsByCategory[$item.Category].Add($item)
}

$script:sharedCardCache = [System.Windows.Media.BitmapCache]::new()
$script:sharedCardCache.EnableClearType = $true
$script:sharedCardCache.RenderAtScale = 1.0
$script:sharedCardCache.Freeze()
$script:defaultFallbackGlyph = [char]::ConvertFromUtf32(0x1F4E6)

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
    $cardBorder.CacheMode = $script:sharedCardCache

    $cardStack = [System.Windows.Controls.StackPanel]::new()
    $appsInCat = $appsByCategory[$cat]

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
    $headerCountBadge.BorderBrush = $script:brushCardBorder
    $headerCountBadge.BorderThickness = $thicknessOne
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

        $useLightBadge = ($app.IconBg -eq "light") -or ($cat -eq "Java Runtimes")
        $iconBadge = [System.Windows.Controls.Border]::new()
        $iconBadge.Width = 20
        $iconBadge.Height = 20
        $iconBadge.CornerRadius = $script:cornerIconBadge
        $iconBadge.Background = $script:brushIconBadgeBg
        $iconBadge.BorderBrush = $script:brushIconBadgeBorder
        $iconBadge.BorderThickness = $thicknessZero
        $iconBadge.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $iconBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $iconInnerGrid = [System.Windows.Controls.Grid]::new()
        $iconInnerGrid.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $iconInnerGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $remoteIconTarget = if (-not [string]::IsNullOrWhiteSpace($app.IconUrl)) {
            $app.IconUrl
        } elseif (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
            "https://www.google.com/s2/favicons?domain=$($app.Domain)&sz=128"
        } else {
            $null
        }
        $iconCacheKey = if ($remoteIconTarget) { $remoteIconTarget } else { "$($app.ID)" }
        $localIconPath = [System.IO.Path]::Combine($iconsCacheDir, "$($app.ID).png")
        $hasCachedInMem = $script:remoteBmpCache -and $script:remoteBmpCache.ContainsKey($iconCacheKey)
        $hasLocalCachedFile = $hasCachedInMem -or [System.IO.File]::Exists($localIconPath)

        $fallbackGlyph = [System.Windows.Controls.TextBlock]::new()
        $fallbackGlyph.Text = if ($hasLocalCachedFile) { $script:defaultFallbackGlyph } else { Get-AppFallbackGlyph -AppName $app.Name -Category $cat }
        $fallbackGlyph.FontFamily = $script:fontSegoeEmoji
        $fallbackGlyph.FontSize = 10
        $fallbackGlyph.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $fallbackGlyph.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [void]$iconInnerGrid.Children.Add($fallbackGlyph)

        $img = [System.Windows.Controls.Image]::new()
        $imgDim = if ($useLightBadge) { 15 } else { 17 }
        $img.Width = $imgDim; $img.Height = $imgDim
        $img.Stretch = [System.Windows.Media.Stretch]::Uniform
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::LowQuality)
        $img.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $img.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $img.Visibility = [System.Windows.Visibility]::Collapsed

        [void]$iconInnerGrid.Children.Add($img)
        $iconBadge.Child = $iconInnerGrid

        if ($hasCachedInMem) {
            $cachedBmp = $script:remoteBmpCache[$iconCacheKey]
            if ($cachedBmp -and $cachedBmp.PixelWidth -gt 0) {
                $img.Source = $cachedBmp
                $fallbackGlyph.Visibility = [System.Windows.Visibility]::Collapsed
                $img.Visibility = [System.Windows.Visibility]::Visible
                if ($useLightBadge) { $iconBadge.Background = $script:brushIconBadgeLightBg }
            }
        } elseif ($remoteIconTarget -or $hasLocalCachedFile) {
            $script:pendingIconSaves.Add(@{
                Url          = $remoteIconTarget
                CacheKey     = $iconCacheKey
                DestPath     = $localIconPath
                DownloadInfo = $null
                Img          = $img
                Fallback     = $fallbackGlyph
                Badge        = $iconBadge
                UseLight     = $useLightBadge
            })
        }
        [System.Windows.Controls.Grid]::SetColumn($iconBadge, 1)
        [void]$rowGrid.Children.Add($iconBadge)

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
        [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($nameText, 5000)
        [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($rowBorder, 5000)
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
        [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($linkBtn, 5000)
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

        $rowBorder.Add_MouseLeftButtonUp($script:rowClickHandler)

        $rowBorder.Child = $rowGrid
        $cardStack.Children.Add($rowBorder) | Out-Null
        $allItemBorders.Add($rowBorder)
    }

    $cardBorder.Child = $cardStack

    $cardEstimatedHeight = 56 + ($appsInCat.Count * 29)

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

    $script:colHeights[$targetColIndex] += $cardEstimatedHeight
}

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
            }
        }
    }

    if ($removedCount -gt 0) {
        $freedMB = [math]::Round($freedBytes / 1MB, 1)
        Log-Text "[CLEAN] Đã tự động dọn $removedCount thư mục/tệp bộ cài WinGet tồn dư ($freedMB MB)."
    }
}

function Wait-WindowsInstallerReady {
    param([int]$MaxWaitSeconds = 20)
    $deadline = [DateTime]::UtcNow.AddSeconds($MaxWaitSeconds)
    $logged = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($script:isWindowClosing) { break }
        $isBusy = $false
        $mtx = $null
        try {
            $mtx = [System.Threading.Mutex]::OpenExisting("Global\_MSIExecute")
            $acquired = $false
            try {
                $acquired = $mtx.WaitOne(0)
            } catch [System.Threading.AbandonedMutexException] {
                $acquired = $true
            }
            if ($acquired) {
                try { $mtx.ReleaseMutex() } catch {}
                $isBusy = $false
            } else {
                $isBusy = $true
            }
        } catch {
            $isBusy = $false
        } finally {
            if ($mtx) { try { $mtx.Dispose() } catch {} }
        }
        if (-not $isBusy) {
            if ($logged) {
                Start-Sleep -Milliseconds 600
                try { [System.Windows.Forms.Application]::DoEvents() } catch {}
            }
            return $true
        }
        if (-not $logged) {
            Log-Text "[*] Đang chờ tiến trình Windows Installer khác hoàn tất..."
            $logged = $true
        }
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Invoke-WinGetWithMsiRetry {
    param([Parameter(Mandatory = $true)][string]$Arguments)
    if ($script:isWindowClosing) { return -1 }
    [void](Wait-WindowsInstallerReady -MaxWaitSeconds 20)
    if ($script:isWindowClosing) { return -1 }
    $code = Run-CliStream "winget" $Arguments
    if (-not $script:isWindowClosing -and ($code -eq -1978334974 -or $code -eq 1618)) {
        Log-Text "[!] Windows Installer đang bận (1618), đang chờ giải phóng để thử lại..."
        [void](Wait-WindowsInstallerReady -MaxWaitSeconds 25)
        if ($script:isWindowClosing) { return -1 }
        Start-Sleep -Milliseconds 1200
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}
        if ($script:isWindowClosing) { return -1 }
        $code = Run-CliStream "winget" $Arguments
    }
    return $code
}

function Wait-SquirrelUpdatersSettle {
    param([int]$MaxWaitMs = 4000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($MaxWaitMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($script:isWindowClosing) { break }
        $running = @(Get-Process -Name "Update" -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -and $_.Path.StartsWith($env:LOCALAPPDATA, [System.StringComparison]::OrdinalIgnoreCase) } catch { $false }
        })
        if ($running.Count -eq 0) { break }
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}
        Start-Sleep -Milliseconds 350
    }
}

function Find-RegistryMatchForCatalogApp {
    param(
        $App,
        $InstalledList,
        [string]$DetectedId = ""
    )

    if (-not $App -or -not $InstalledList) { return $null }

    foreach ($inst in $InstalledList) {
        if ($null -eq $inst) { continue }
        if ($inst.Id -and ($inst.Id -ieq $App.ID -or ($DetectedId -and $inst.Id -ieq $DetectedId))) {
            return $inst
        }
    }

    $exactNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($App.Name) { [void]$exactNames.Add($App.Name) }
    if ($App.ID) { [void]$exactNames.Add($App.ID) }
    if ($App.Aliases) {
        foreach ($al in $App.Aliases) {
            if (-not [string]::IsNullOrWhiteSpace($al)) { [void]$exactNames.Add($al) }
        }
    }

    foreach ($inst in $InstalledList) {
        if ($null -eq $inst -or -not $inst.DisplayName) { continue }
        if ($exactNames.Contains($inst.DisplayName)) {
            return $inst
        }
    }

    $getClean = {
        param([string]$s)
        if ([string]::IsNullOrWhiteSpace($s)) { return "" }
        if (Get-Command Get-CleanAppName -ErrorAction SilentlyContinue) { return (Get-CleanAppName $s) }
        if ("DuckUtil.AppCatalogEngine" -as [type]) { return [DuckUtil.AppCatalogEngine]::CleanCatalogAppName($s) }
        return $s.Trim().ToLowerInvariant()
    }

    $cleanTargets = [System.Collections.Generic.List[string]]::new()
    foreach ($n in $exactNames) {
        $cn = & $getClean $n
        if ($cn -and $cn.Length -ge 2 -and -not $cleanTargets.Contains($cn)) {
            $cleanTargets.Add($cn)
        }
    }

    $hasCompat = [bool](Get-Command Test-MatchCompatible -ErrorAction SilentlyContinue)
    $bestCand = $null
    $bestScore = 0

    foreach ($inst in $InstalledList) {
        if ($null -eq $inst -or -not $inst.DisplayName) { continue }
        $cleanInst = & $getClean $inst.DisplayName
        if ([string]::IsNullOrWhiteSpace($cleanInst)) { continue }

        $score = 0
        foreach ($ct in $cleanTargets) {
            if ($cleanInst.Equals($ct, [System.StringComparison]::OrdinalIgnoreCase)) {
                $score = [Math]::Max($score, 900)
                break
            }
            if ($ct.Length -ge 4 -and $cleanInst -match ("(?<![a-zA-Z0-9])" + [regex]::Escape($ct) + "(?![a-zA-Z0-9])")) {
                $score = [Math]::Max($score, 700 + $ct.Length)
            }
        }

        if ($score -gt $bestScore) {
            if ($hasCompat) {
                $verProp = if ($inst.PSObject.Properties['DisplayVersion']) { [string]$inst.DisplayVersion } else { "" }
                $probe = [PSCustomObject]@{ Name = [string]$inst.DisplayName; ID = [string]$inst.Id; Version = $verProp }
                if (-not (Test-MatchCompatible $App $probe)) { continue }
            }
            $bestScore = $score
            $bestCand = $inst
        }
    }

    return $bestCand
}

function Invoke-SmartAppUpgrade {
    param($Tag, [switch]$IsBulkUpgrade)
    if (-not $Tag) { return 1 }
    $app = $Tag.App
    if (-not $app) { return 1 }

    $upgradeId = if ($Tag.DetectedId -and -not ($Tag.DetectedId.StartsWith("ARP\") -or $Tag.DetectedId.StartsWith("MSIX\") -or $Tag.DetectedId.StartsWith("LOCAL\"))) {
        $Tag.DetectedId
    } else {
        $app.ID
    }

    $instApps = if ($script:cachedUninstallerApps -and $script:cachedUninstallerApps.Count -gt 0) {
        $script:cachedUninstallerApps
    } elseif ("DuckUtil.DeepUninstallerEngine" -as [type]) {
        [DuckUtil.DeepUninstallerEngine]::GetInstalledApps()
    } else {
        @()
    }

    $regMatch = Find-RegistryMatchForCatalogApp -App $app -InstalledList $instApps -DetectedId $Tag.DetectedId

    $existingLoc = $null
    if ($regMatch -and -not [string]::IsNullOrWhiteSpace($regMatch.InstallLocation) -and (Test-Path -LiteralPath $regMatch.InstallLocation)) {
        $existingLoc = $regMatch.InstallLocation.Trim().TrimEnd('\')
    }

    if (-not $existingLoc -and $regMatch) {
        $uCmd = if ($regMatch.QuietUninstallString) { $regMatch.QuietUninstallString } else { $regMatch.UninstallString }
        if ($uCmd) {
            $uExe = if (Get-Command Split-CommandLineExecutableAndArgs -ErrorAction SilentlyContinue) {
                (Split-CommandLineExecutableAndArgs -CommandLine $uCmd).Exe
            } elseif ($uCmd.StartsWith('"')) {
                $q2 = $uCmd.IndexOf('"', 1)
                if ($q2 -gt 1) { $uCmd.Substring(1, $q2 - 1) } else { $uCmd.Trim('"') }
            } else {
                ($uCmd -split '\s+')[0]
            }
            if ($uExe -and (Test-Path -LiteralPath $uExe)) {
                $pDir = [System.IO.Path]::GetDirectoryName($uExe)
                if ($pDir -and (Test-Path -LiteralPath $pDir)) {
                    $existingLoc = $pDir
                }
            }
        }
    }

    if (-not $existingLoc) {
        $stdCandidates = @(
            (Join-Path $env:LOCALAPPDATA "Programs\$($app.Name)"),
            (Join-Path $env:ProgramFiles $app.Name),
            (Join-Path ${env:ProgramFiles(x86)} $app.Name)
        )
        foreach ($sc in $stdCandidates) {
            if ($sc -and (Test-Path -LiteralPath $sc)) {
                $existingLoc = $sc
                break
            }
        }
    }

    if ($existingLoc -and ("DuckUtil.AppCatalogEngine" -as [type])) {
        if ([DuckUtil.AppCatalogEngine]::HasCrackOrPatchIndicators($existingLoc)) {
            if ($IsBulkUpgrade) {
                Log-Text "[!] Phát hiện dấu hiệu file Crack/Patch tại '$existingLoc' - Tự động bỏ qua $($app.Name) để bảo vệ bản patch."
                return 2
            } else {
                if ($script:isWindowClosing) { return 2 }
                $ansCrack = Show-OwnedMessageBox `
                    -Text "Phát hiện tệp nghi ngờ là Crack/Patch hoặc loader không chính thức trong thư mục cài đặt của $($app.Name):`n$existingLoc`n`nNâng cấp qua WinGet có thể ghi đè file patch hoặc làm hỏng crack.`nBạn vẫn muốn tiếp tục nâng cấp?" `
                    -Caption "Cảnh báo bảo vệ Crack / Patch" `
                    -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
                if ($ansCrack -ne [System.Windows.Forms.DialogResult]::Yes -or $script:isWindowClosing) {
                    Log-Text "[!] Người dùng đã hủy nâng cấp $($app.Name) để giữ nguyên file Crack/Patch."
                    return 2
                }
            }
        }
    }

    $scope = ""
    if ($regMatch -and $regMatch.Scope -eq "User") {
        $scope = "user"
    } elseif ($existingLoc -and $existingLoc.StartsWith($env:USERPROFILE, [System.StringComparison]::OrdinalIgnoreCase)) {
        $scope = "user"
    }

    $nameVariations = [System.Collections.Generic.List[string]]::new()
    $nameVariations.Add($app.Name)
    $nameVariations.Add($app.ID)
    if ($app.Aliases) {
        foreach ($al in $app.Aliases) {
            if (-not [string]::IsNullOrWhiteSpace($al) -and -not $nameVariations.Contains($al)) {
                $nameVariations.Add($al)
            }
        }
    }
    if ($regMatch -and $regMatch.Publisher) {
        $pub = $regMatch.Publisher.Trim()
        if ($pub -and -not ($pub -match 'Microsoft|Windows|Corporation')) {
            $nameVariations.Add((Join-Path $pub $app.Name))
        }
    }

    $normalizedExistingLoc = if ($existingLoc) {
        try { [System.IO.Path]::GetFullPath($existingLoc).TrimEnd('\') } catch { $existingLoc.TrimEnd('\') }
    } else { "" }

    $targetAppDataDirs = [System.Collections.Generic.List[string]]::new()
    $seenSnapshotDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($normalizedExistingLoc) { [void]$seenSnapshotDirs.Add($normalizedExistingLoc) }
    foreach ($nv in $nameVariations) {
        if ([string]::IsNullOrWhiteSpace($nv)) { continue }
        foreach ($rootDir in @($env:APPDATA, $env:LOCALAPPDATA)) {
            if ([string]::IsNullOrWhiteSpace($rootDir)) { continue }
            $candDir = Join-Path $rootDir $nv
            if (Test-Path -LiteralPath $candDir) {
                $normCand = try { [System.IO.Path]::GetFullPath($candDir).TrimEnd('\') } catch { $candDir.TrimEnd('\') }
                if ($seenSnapshotDirs.Add($normCand)) {
                    $targetAppDataDirs.Add($normCand)
                }
            }
        }
    }

    $hkcuKeys = [System.Collections.Generic.List[object]]::new()
    $seenHkcu = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($nv in $nameVariations) {
        if ([string]::IsNullOrWhiteSpace($nv)) { continue }
        $rk = "HKCU:\Software\$nv"
        if ($seenHkcu.Add($rk) -and (Test-Path -LiteralPath $rk)) {
            $hadData = $false
            try {
                $kObj = Get-Item -LiteralPath $rk -ErrorAction SilentlyContinue
                if ($kObj -and ($kObj.ValueCount -gt 0 -or $kObj.SubKeyCount -gt 0)) { $hadData = $true }
            } catch {}
            $hkcuKeys.Add([PSCustomObject]@{ PSPath = $rk; HadData = $hadData })
        }
    }

    $backupRoot = Join-Path $env:TEMP "AppDriver_UpgradeGuard\$($app.ID)"
    if (Test-Path -LiteralPath $backupRoot) {
        Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    $snapshotType = if ("DuckUtil.AppCatalogEngine" -as [type]) {
        [DuckUtil.AppCatalogEngine]
    } elseif ("DuckUtil.DeepUninstallerEngine" -as [type]) {
        [DuckUtil.DeepUninstallerEngine]
    } else { $null }

    $hasSnapshots = $false
    $locBkp = Join-Path $backupRoot "InstallLocation"
    if ($existingLoc -and (Test-Path -LiteralPath $existingLoc) -and $snapshotType) {
        $bytes = $snapshotType::BackupDirectorySnapshot($existingLoc, $locBkp, 104857600L, $true)
        if ($bytes -gt 0) { $hasSnapshots = $true }
    }

    $appDataBkps = [System.Collections.Generic.List[object]]::new()
    $adIdx = 0
    if ($snapshotType) {
        foreach ($adDir in $targetAppDataDirs) {
            $adIdx++
            $adBkpDir = Join-Path $backupRoot "AppData_$adIdx"
            $b = $snapshotType::BackupDirectorySnapshot($adDir, $adBkpDir, 104857600L, $false)
            if ($b -gt 0) {
                $hasSnapshots = $true
                $appDataBkps.Add([PSCustomObject]@{ Source = $adDir; Backup = $adBkpDir })
            }
        }
    }

    $regFiles = [System.Collections.Generic.List[object]]::new()
    $rkIdx = 0
    foreach ($rkEntry in $hkcuKeys) {
        $rkIdx++
        $rf = Join-Path $backupRoot "hkcu_reg_$rkIdx.reg"
        $rawHkcu = $rkEntry.PSPath -replace '^HKCU:\\', 'HKEY_CURRENT_USER\'
        try {
            $pReg = Start-Process "reg.exe" -ArgumentList "export `"$rawHkcu`" `"$rf`" /y" -Wait -NoNewWindow -PassThru -ErrorAction SilentlyContinue
            if ($pReg.ExitCode -eq 0 -and (Test-Path -LiteralPath $rf)) {
                $hasSnapshots = $true
                $regFiles.Add([PSCustomObject]@{ PSPath = $rkEntry.PSPath; Key = $rawHkcu; File = $rf; HadData = $rkEntry.HadData })
            }
        } catch {}
    }

    if ($hasSnapshots) {
        Log-Text "[*] Đã kích hoạt UpgradeDataGuard: Chụp snapshot dữ liệu cá nhân & cấu hình trước khi nâng cấp."
    }

    $baseUpArgs = "upgrade --id `"$upgradeId`" --exact --silent --accept-package-agreements --accept-source-agreements"
    $upArgs = $baseUpArgs
    if ($existingLoc) {
        $upArgs += " --location `"$existingLoc`""
    }
    if ($scope) {
        $upArgs += " --scope $scope"
    }

    $code = Invoke-WinGetWithMsiRetry -Arguments $upArgs
    if ($code -ne 0 -and $scope) {
        Log-Text "[!] Nâng cấp theo scope '$scope' không thành công (Code: $code), đang thử lại bỏ giới hạn scope..."
        $upArgsNoScope = $baseUpArgs
        if ($existingLoc) {
            $upArgsNoScope += " --location `"$existingLoc`""
        }
        $code = Invoke-WinGetWithMsiRetry -Arguments $upArgsNoScope
    }

    if ($code -ne 0 -and $existingLoc) {
        Log-Text "[!] Nâng cấp kèm đường dẫn cố định không khả dụng (Code: $code), đang thử lại cấu hình mặc định..."
        $code = Invoke-WinGetWithMsiRetry -Arguments $baseUpArgs
    }

    $alreadyLatest = $false
    if ($code -eq -1978335189) {
        try {
            $probeCap = Invoke-WingetListCapture -Arguments "list --id `"$upgradeId`" --exact --disable-interactivity --accept-source-agreements" -TimeoutSeconds 12
            if ($probeCap.Available -and -not $probeCap.TimedOut) {
                $probeParsed = ConvertFrom-WingetListOutput -RawText $probeCap.StdOut -AllowHeaderless $true
                $probeItem = if ($probeParsed -and $probeParsed.Items.Count -gt 0) {
                    $probeParsed.Items | Where-Object { $_.ID -ieq $upgradeId } | Select-Object -First 1
                } else { $null }
                if ($probeItem -and -not $probeItem.HasUpdate) {
                    $alreadyLatest = $true
                    $code = 0
                    Log-Text "[OK] $($app.Name) hiện đã ở phiên bản mới nhất ($($probeItem.Version))."
                } elseif ($probeItem -and $probeItem.HasUpdate) {
                    Log-Text "[*] Phát hiện bản mới $($probeItem.Available) nhưng khác scope cài đặt; đang nâng cấp trực tiếp (--force)..."
                    $baseForceArgs = "install --id `"$upgradeId`" --exact --silent --force --accept-package-agreements --accept-source-agreements"
                    $forceArgs = $baseForceArgs
                    if ($existingLoc) { $forceArgs += " --location `"$existingLoc`"" }
                    if ($scope) { $forceArgs += " --scope $scope" }
                    $code = Invoke-WinGetWithMsiRetry -Arguments $forceArgs
                    if ($code -ne 0 -and ($existingLoc -or $scope)) {
                        $code = Invoke-WinGetWithMsiRetry -Arguments $baseForceArgs
                    }
                }
            }
        } catch {}
    }

    $preInstallerAborted = $alreadyLatest -or ($code -in @(-1978335189, -1978335212, -1978335191, -1978334974, 1618))
    if ($hasSnapshots) {
        if (-not $preInstallerAborted) {
            if ($existingLoc -and (Test-Path -LiteralPath $locBkp) -and $snapshotType) {
                $restoredLoc = $snapshotType::RestoreDirectorySnapshot($locBkp, $existingLoc)
                if ($restoredLoc -gt 0) {
                    Log-Text "[OK] UpgradeDataGuard: Đã khôi phục $restoredLoc tệp dữ liệu bị xóa trong thư mục cài đặt."
                }
            }

            if ($snapshotType) {
                foreach ($item in $appDataBkps) {
                    if (Test-Path -LiteralPath $item.Backup) {
                        $resAd = $snapshotType::RestoreDirectorySnapshot($item.Backup, $item.Source)
                        if ($resAd -gt 0) {
                            Log-Text "[OK] UpgradeDataGuard: Đã khôi phục $resAd tệp dữ liệu/profile trong: $($item.Source)"
                        }
                    }
                }
            }

            foreach ($rfItem in $regFiles) {
                if (Test-Path -LiteralPath $rfItem.File) {
                    $needRegRestore = $false
                    if (-not (Test-Path -LiteralPath $rfItem.PSPath)) {
                        $needRegRestore = $true
                    } elseif ($rfItem.HadData) {
                        try {
                            $curKey = Get-Item -LiteralPath $rfItem.PSPath -ErrorAction SilentlyContinue
                            if ($curKey -and $curKey.ValueCount -eq 0 -and $curKey.SubKeyCount -eq 0) { $needRegRestore = $true }
                        } catch {}
                    }
                    if ($needRegRestore) {
                        try {
                            Start-Process "reg.exe" -ArgumentList "import `"$($rfItem.File)`"" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                            Log-Text "[OK] UpgradeDataGuard: Đã khôi phục Registry cấu hình: $($rfItem.Key)"
                        } catch {}
                    }
                }
            }
        }

        try {
            Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    return $code
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
        $didAnyInstall = $false
        Log-Text "=========================================================="
        Log-Text "[INSTALL] BẮT ĐẦU CÀI ĐẶT $total ỨNG DỤNG ĐÃ ĐÁNH DẤU"
        Log-Text "=========================================================="

        try {
            foreach ($tag in $selectedTags) {
                if ($script:isWindowClosing) { break }
                $idx++
                $app = $tag.App
                if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }
                if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang cài đặt: $($app.Name)..." }

                if ($tag.Status -eq "LATEST" -or $tag.Status -eq "OUTDATED") {
                    Log-Text "[SKIP] $($app.Name) đã có trên máy (dùng 'Cập nhật mục chọn' nếu muốn nâng cấp)."
                    if ($tag.Status -ne "OUTDATED" -and $tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                    continue
                }

                $didAnyInstall = $true
                Log-Text "[$idx/$total] Đang cài: $($app.Name) (ID: $($app.ID))..."

                if ($app.BrowserDownload -eq $true -and -not [string]::IsNullOrWhiteSpace($app.FallbackUrl)) {
                    Log-Text "   [WEB] Đang mở liên kết tải bộ cài chính thức: $($app.FallbackUrl)"
                    try {
                        Start-Process $app.FallbackUrl
                        if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                    } catch {
                        Log-Text "   [ERR - LỖI] Không thể mở trình duyệt cho $($app.Name)"
                    }
                    continue
                }

                if (-not [string]::IsNullOrWhiteSpace($app.GitHubRepo) -and -not [string]::IsNullOrWhiteSpace($app.AssetRegex)) {
                    $code = Invoke-GitHubAssetInstall -App $app
                } else {
                    $wgArgs = "install --id `"$($app.ID)`" --exact --silent --accept-package-agreements --accept-source-agreements"
                    if ($app.Source -eq "msstore") { $wgArgs += " --source msstore" }
                    $code = Invoke-WinGetWithMsiRetry -Arguments $wgArgs
                }

                if ($code -eq 0) {
                    Log-Text "   [OK - HOÀN THÀNH] $($app.Name)"
                    if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                } else {
                    Log-Text "   [ERR - LỖI] $($app.Name) (Exit Code: $code)"
                    if (-not [string]::IsNullOrWhiteSpace($app.FallbackUrl)) {
                        Log-Text "   [WEB] Gói này hiện không khả dụng tự động qua WinGet. Đang mở trang tải chính thức: $($app.FallbackUrl)"
                        try { Start-Process $app.FallbackUrl } catch {}
                    }
                }
            }
        } finally {
            Clear-WinGetTempInstallers
        }
        if (-not $script:isWindowClosing) {
            Update-SelectionCount
            if ($txtStatus) { $txtStatus.Text = "Cài đặt hoàn tất!" }
            if ($progressBar) { $progressBar.Value = 100 }
            if ($didAnyInstall) {
                Wait-SquirrelUpdatersSettle
                if (-not $script:isWindowClosing) {
                    Scan-And-ColorizeApps
                }
            }
        }
    }
}

Register-Click "btnUpgradeSelected" {
    Invoke-GuardedAction "Nâng cấp đã chọn" -DeferExpand {
        $selectedTags = [System.Collections.Generic.List[object]]::new()
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -eq $true) {
                $selectedTags.Add($cb.Tag)
            }
        }

        if ($selectedTags.Count -eq 0) {
            Expand-TerminalLog
            Log-Text "[!] Bạn chưa chọn ứng dụng nào để nâng cấp!"
            return
        }

        Expand-TerminalLog
        $total = $selectedTags.Count
        $idx = 0
        Log-Text "=========================================================="
        Log-Text "[UPGRADE] BẮT ĐẦU NÂNG CẤP $total ỨNG DỤNG ĐÃ CHỌN"
        Log-Text "=========================================================="

        try {
            foreach ($tag in $selectedTags) {
                if ($script:isWindowClosing) { break }
                $idx++
                $app = $tag.App

                if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }
                if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang nâng cấp: $($app.Name)..." }

                if ($tag.Status -eq "NONE" -or $tag.Status -eq "NOT_INSTALLED" -or [string]::IsNullOrWhiteSpace($tag.Status)) {
                    Log-Text "[SKIP] $($app.Name) chưa có trên máy (dùng 'Cài đặt mục chọn' để cài mới)."
                    if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                    continue
                }

                if ($tag.Status -eq "LATEST") {
                    Log-Text "[OK] $($app.Name) đã là bản mới nhất, bỏ qua."
                    if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                    continue
                }

                Log-Text "[$idx/$total] Đang nâng cấp: $($app.Name)..."
                $code = Invoke-SmartAppUpgrade -Tag $tag
                if ($code -eq 0) {
                    Log-Text "   [OK - ĐÃ NÂNG CẤP THÀNH CÔNG] $($app.Name)"
                    if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                } elseif ($code -eq 2) {
                    Log-Text "   [SKIP - BẢO VỆ CRACK/PATCH] Đã bỏ qua $($app.Name) để giữ nguyên file patch."
                    if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                } else {
                    Log-Text "   [ERR - LỖI NÂNG CẤP HOẶC ĐÃ MỚI NHẤT] $($app.Name) (Exit Code: $code)"
                }
            }
        } finally {
            Clear-WinGetTempInstallers
        }
        if (-not $script:isWindowClosing) {
            Update-SelectionCount
            if ($txtStatus) { $txtStatus.Text = "Nâng cấp hoàn tất!" }
            if ($progressBar) { $progressBar.Value = 100 }
            Wait-SquirrelUpdatersSettle
            if (-not $script:isWindowClosing) {
                Scan-And-ColorizeApps
            }
        }
    }
}

Register-Click "btnUpgradeAll" {
    Invoke-GuardedAction "Nâng cấp toàn bộ" {
        Log-Text "=========================================================="
        Log-Text "[UPGRADE] BẮT ĐẦU NÂNG CẤP TOÀN BỘ PHẦN MỀM TRÊN MÁY"
        Log-Text "=========================================================="
        if ($txtStatus) { $txtStatus.Text = "Đang nâng cấp tất cả ứng dụng..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }

        try {
            $outdatedRows = @($allItemBorders | Where-Object { $_.Tag -and $_.Tag.Status -eq "OUTDATED" })
            if ($outdatedRows.Count -gt 0) {
                $totalOut = $outdatedRows.Count
                $idxOut = 0
                foreach ($row in $outdatedRows) {
                    if ($script:isWindowClosing) { break }
                    $idxOut++
                    $tagOut = $row.Tag
                    if ($progressBar) { $progressBar.Value = [math]::Round(($idxOut / $totalOut) * 100) }
                    if ($txtStatus) { $txtStatus.Text = "[$idxOut/$totalOut] Đang nâng cấp an toàn: $($tagOut.App.Name)..." }
                    Log-Text "[$idxOut/$totalOut] Đang nâng cấp bảo toàn dữ liệu: $($tagOut.App.Name)..."
                    $codeOut = Invoke-SmartAppUpgrade -Tag $tagOut -IsBulkUpgrade
                    if ($codeOut -eq 0) {
                        Log-Text "   [OK - ĐÃ NÂNG CẤP THÀNH CÔNG] $($tagOut.App.Name)"
                        if ($tagOut.CheckBox) { $tagOut.CheckBox.IsChecked = $false }
                    } elseif ($codeOut -eq 2) {
                        Log-Text "   [SKIP - BẢO VỆ CRACK/PATCH] Đã bỏ qua $($tagOut.App.Name) để giữ nguyên file patch."
                        if ($tagOut.CheckBox) { $tagOut.CheckBox.IsChecked = $false }
                    } else {
                        Log-Text "   [ERR - LỖI NÂNG CẤP HOẶC ĐÃ MỚI NHẤT] $($tagOut.App.Name) (Exit Code: $codeOut)"
                    }
                }
            } elseif (-not $script:isWindowClosing) {
                Run-CliStream "winget" "upgrade --all --silent --accept-package-agreements --accept-source-agreements"
            }
        } finally {
            Clear-WinGetTempInstallers
            if ($progressBar) { $progressBar.IsIndeterminate = $false }
        }

        if (-not $script:isWindowClosing) {
            if ($txtStatus) { $txtStatus.Text = "Nâng cấp hoàn tất!" }
            Log-Text "[OK] Toàn bộ ứng dụng đã được nâng cấp lên bản mới nhất."
            Wait-SquirrelUpdatersSettle
            if (-not $script:isWindowClosing) {
                Scan-And-ColorizeApps
            }
        }
    }
}

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

Register-Click "btnSfcScan" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "SFC Scan" {
        Log-Text "[*] Đang bắt đầu quét kiểm tra tính toàn vẹn hệ thống (sfc /scannow)..."
        if ($txtStatus) { $txtStatus.Text = "Đang chạy SFC Scan..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-SystemFileCheck
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Quét SFC hoàn tất" }
        Log-Text "[OK] Quá trình SFC đã kết thúc."
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
        Log-Text "[OK] DISM RestoreHealth hoàn thành xuất sắc."
    }
}

Register-Click "btnDismCleanup" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "DISM Component Cleanup" -DeferExpand {
        $confirm = Show-OwnedMessageBox `
            -Text "Lệnh DISM /StartComponentCleanup /ResetBase sẽ nén kho WinSxS và KHÔNG THỂ gỡ cài đặt (rollback) các bản Windows Update hiện tại về sau.`n`nBạn có chắc chắn muốn tiếp tục?" `
            -Caption "Xác nhận dọn kho linh kiện (WinSxS)" `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes -or $script:isWindowClosing) { return }

        Expand-TerminalLog
        Log-Text "[*] Đang dọn dẹp kho linh kiện hệ thống (DISM Component Cleanup)..."
        if ($txtStatus) { $txtStatus.Text = "Đang dọn kho linh kiện..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-DismComponentCleanup
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn kho linh kiện hoàn tất" }
        Log-Text "[OK] Đã giải phóng dung lượng kho linh kiện."
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
        Log-Text "[OK] Đã khởi động lại dịch vụ cập nhật."
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
        Log-Text "[OK] Đã làm mới mạng và DNS cache."
    }
}

Register-Click "btnResetTcpIp" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Reset TCP/IP Stack" {
        Log-Text "[*] Đang đặt lại toàn bộ ngăn xếp giao thức mạng TCP/IP..."
        Reset-NetworkInterfaceStack
        Log-Text "[OK] Đã reset TCP/IP Stack. Khuyên bạn nên khởi động lại máy."
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
        Log-Text "[OK] Dọn dẹp bộ nhớ tạm thành công!"
    }
}

Register-Click "btnCleanEventLogs" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Dọn dẹp Windows Event Logs" -DeferExpand {
        $confirm = Show-OwnedMessageBox `
            -Text "Hành động này sẽ xóa toàn bộ nhật ký sự kiện Windows (Application, System, Security...). Bạn có chắc chắn muốn tiếp tục?" `
            -Caption "Xác nhận dọn dẹp Event Logs" `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes -or $script:isWindowClosing) { return }

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
        Log-Text "[OK] Đã nạp lại Windows Explorer thành công."
    }
}

Register-Click "btnScanFaultyDrivers" -LockGroup "Quản lý Driver" {
    Invoke-GuardedAction "Quét Driver lỗi" {
        Log-Text "=========================================================="
        Log-Text "[SCAN] ĐANG QUÉT TOÀN BỘ THIẾT BỊ PHẦN CỨNG & DRIVER BỊ LỖI..."
        Log-Text "=========================================================="
        if ($txtStatus) { $txtStatus.Text = "Đang quét thiết bị lỗi..." }

        $faulty = Find-FaultyPnpDevices

        if ($faulty.Count -eq 0) {
            Log-Text "[OK] Tuyệt vời! Không phát hiện thiết bị nào bị lỗi hoặc thiếu driver trên máy bạn."
            if ($txtStatus) { $txtStatus.Text = "Tất cả Driver đều hoạt động tốt" }
        } else {
            Log-Text "[WARN] PHÁT HIỆN $($faulty.Count) THIẾT BỊ ĐANG BỊ LỖI / THIẾU DRIVER:"
            foreach ($d in $faulty) {
                Log-Text "   - Tên thiết bị: $($d.FriendlyName)"
                Log-Text "     Mã phần cứng: $($d.InstanceId)"
                Log-Text "     Trạng thái: $($d.Status) | ErrorCode: $($d.ConfigManagerErrorCode)"
                Log-Text "   ------------------------------------------------"
            }
            if ($txtStatus) { $txtStatus.Text = "Phát hiện $($faulty.Count) thiết bị lỗi" }
        }
    }
}

Register-Click "btnPnpRescan" -LockGroup "Quản lý Driver" {
    Invoke-GuardedAction "Quét lại thiết bị PnP" {
        Log-Text "[*] Đang gửi lệnh quét phần cứng Plug and Play (pnputil /scan-devices)..."
        Invoke-PnpDeviceRescan
        Log-Text "[OK] Windows đã hoàn tất quét và phát hiện lại các thiết bị phần cứng."
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
        Log-Text "[OK] Hoàn thành! Lỗi kẹt tải driver đã được dọn sạch."
    }
}

Register-Click "btnScanWindowsUpdateDrivers" -LockGroup "Quản lý Driver" {
    Invoke-GuardedAction "Quét driver từ Windows Update" {
        Invoke-WindowsUpdateScan
    }
}

Register-Click "btnCleanDriverStore" -LockGroup "Quản lý Driver" {
    Invoke-GuardedAction "Dọn dẹp DriverStore" -DeferExpand {
        $confirm = Show-OwnedMessageBox `
            -Text "Hành động này sẽ xóa các gói driver OEM cũ không còn thiết bị sử dụng trong DriverStore.`nBạn có chắc chắn muốn tiếp tục?" `
            -Caption "Xác nhận dọn dẹp DriverStore" `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes -or $script:isWindowClosing) { return }

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
            Log-Text "[OK] THÀNH CÔNG! Đã sao lưu toàn bộ driver vào: $dest"
        } else {
            if ($txtStatus) { $txtStatus.Text = "Sao lưu driver thất bại" }
            Log-Text "[ERR] Lỗi trong quá trình sao lưu driver."
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

function Stop-AllBackgroundWork {
    $script:isWindowClosing = $true
    try { Stop-ActiveWaitFrames } catch {}
    try { if ($script:iconSyncTimer) { $script:iconSyncTimer.Stop() } } catch {}
    try { if ($script:uninstIconTimer) { $script:uninstIconTimer.Stop() } } catch {}
    try {
        if (Get-Command "Stop-PreSpawnedWinget" -ErrorAction SilentlyContinue) {
            Stop-PreSpawnedWinget
        } elseif ($null -ne $script:preSpawnedWinget -and $script:preSpawnedWinget.Process) {
            if (-not $script:preSpawnedWinget.Process.HasExited) {
                $script:preSpawnedWinget.Process.Kill()
            }
            $script:preSpawnedWinget.Process.Dispose()
            $script:preSpawnedWinget = $null
        }
    } catch {}
    try { Stop-ActiveChildProcess } catch {}
}

if ($window -and $window.Dispatcher) {
    $window.Dispatcher.add_UnhandledException({
        param($sender, $e)
        $errMsg = if ($e -and $e.Exception) { $e.Exception.Message } else { "Lỗi giao diện không xác định" }
        try { Log-Text "[!] Đã chặn lỗi ngoại lệ UI: $errMsg" } catch {}
        $script:isActionRunning = $false
        $script:isScanningApps = $false
        $script:isUpdatingUninstaller = $false
        $script:isSortingUninstaller = $false
        $script:uninstallerLoadQueued = $false
        $script:suppressSelectionCount = $false
        $script:suppressUninstallerSelectionCount = $false
        if ($progressBar) {
            try { $progressBar.IsIndeterminate = $false } catch {}
        }
        if ($script:isWindowClosing) {
            try { if ($script:iconSyncTimer) { $script:iconSyncTimer.Stop() } } catch {}
            try { if ($script:uninstIconTimer) { $script:uninstIconTimer.Stop() } } catch {}
        }
        if ($e) {
            $e.Handled = $true
        }
    })
}

$script:iconSyncTimer = [System.Windows.Threading.DispatcherTimer]::new([System.Windows.Threading.DispatcherPriority]::Background)
$script:iconSyncTimer.Interval = [TimeSpan]::FromMilliseconds(35)
$script:iconSyncTimer.Add_Tick({
    if ($script:isWindowClosing) {
        $script:iconSyncTimer.Stop()
        return
    }
    if ($script:isActionRunning) { return }
    Flush-PendingIconCache -MaxDecode 8
    if ($script:isWindowClosing -or -not $script:pendingIconSaves -or $script:pendingIconSaves.Count -eq 0) {
        $script:iconSyncTimer.Stop()
    }
})

$script:autoScannedOnStartup = $false
$window.Add_ContentRendered({
    if (-not $script:autoScannedOnStartup -and -not $script:isWindowClosing) {
        $script:autoScannedOnStartup = $true
        Log-Text "[OK] Sẵn sàng ($($allItemBorders.Count) ứng dụng / $($categories.Count) danh mục)."
        Flush-PendingIconCache -MaxDecode 10
        if ($script:pendingIconSaves -and $script:pendingIconSaves.Count -gt 0) {
            $script:iconSyncTimer.Start()
        }
        $window.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [Action]{
                if ($script:isWindowClosing) { return }
                try {
                    Scan-And-ColorizeApps
                } catch {
                    Log-Text "[!] Lỗi quét ứng dụng khởi động: $($_.Exception.Message)"
                } finally {
                    $script:isScanningApps = $false
                }
                if ($script:isWindowClosing) { return }
                $window.Dispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::ContextIdle,
                    [Action]{
                        if (-not $script:isWindowClosing -and (-not $script:uninstallerLoadedOnce -or $script:deferredUninstallerLoad)) {
                            $script:deferredUninstallerLoad = $false
                            Update-UninstallerList
                        }
                    }
                ) | Out-Null
            }
        ) | Out-Null
    }
})
$window.Add_Closing({
    Stop-AllBackgroundWork
})
$window.Add_Closed({
    Stop-AllBackgroundWork
})

$window.ShowDialog() | Out-Null
if (-not $script:SkipHostExit) {
    Stop-AllBackgroundWork
    [Environment]::Exit(0)
}
