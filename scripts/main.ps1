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
$btnCancelAction   = $window.FindName("btnCancelAction")
$borderQueueBadge  = $window.FindName("borderQueueBadge")
$txtQueueBadge     = $window.FindName("txtQueueBadge")
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
                    [System.Drawing.Icon].Assembly.Location,
                    [System.Net.Http.HttpClient].Assembly.Location,
                    [System.Object].Assembly.Location
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
                if ($PSVersionTable.PSEdition -eq "Core") {
                    try {
                        $refDllsCore = @([System.IO.Directory]::GetFiles((Join-Path $PSHOME "ref"), "*.dll"))
                        $loadedExtraCore = @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { -not $_.IsDynamic -and -not [string]::IsNullOrWhiteSpace($_.Location) -and $_.GetName().Name -match "^(Presentation|WindowsBase|System\.Drawing|System\.Private\.Windows|DirectWriteForwarder|ReachFramework|UIAutomation)" } | ForEach-Object { $_.Location })
                        $wpfSmoothRefs = @($refDllsCore + $loadedExtraCore + $wpfSmoothRefs | Select-Object -Unique)
                    } catch {}
                }
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
$categorySidebarScrollViewer = $window.FindName("CategorySidebarScrollViewer")
if ($categorySidebarScrollViewer -and ("DuckUtil.SmoothScrollController" -as [type])) {
    $script:catSidebarSmoothScrollCtrl = [DuckUtil.SmoothScrollController]::Attach($categorySidebarScrollViewer)
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
$script:remotePipelineStarted = $false
$script:pendingIconTargets = $null

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

$script:remoteIconRegistry    = [System.Collections.Generic.List[hashtable]]::new()
$script:cardDescriptors       = [System.Collections.Generic.List[hashtable]]::new()
$script:cardDescByCategory     = [System.Collections.Generic.Dictionary[string, hashtable]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:activeCatalogCategory    = "__ALL__"
$script:activeSingleCatDesc      = $null
$script:activeAllowedCategories  = $null
$script:activeMasonryDescriptors = $null
$script:deferredCardTimer        = $null

function Try-EnableCompletedCardCaches {
    if ($script:isWindowClosing -or -not $script:hasCompletedAppScan -or -not $script:sharedCardCache) { return }
    $pipeType = "DuckUtil.UiAssetPipeline" -as [type]
    $isIdleNow = ($null -ne $pipeType -and $null -ne $pipeType.GetProperty("IsRemoteIdle")) -and [DuckUtil.UiAssetPipeline]::IsRemoteIdle
    foreach ($cd in $script:cardDescriptors) {
        if ($cd -eq $script:activeSingleCatDesc -or -not $cd.Attached -or $cd.CacheEnabled) { continue }
        if ($cd.TotalIcons -eq 0 -or ($cd.IconsEnqueued -and ($cd.LoadedIcons -ge $cd.TotalIcons -or $isIdleNow))) {
            $cd.Card.CacheMode = $script:sharedCardCache
            $cd.CacheEnabled = $true
        }
    }
}

function Enqueue-CardIconsNow {
    param($CardDesc)
    if ($null -eq $CardDesc -or $CardDesc.IconsEnqueued) { return }
    $CardDesc.IconsEnqueued = $true
    if (-not $CardDesc.IconIndices -or $CardDesc.IconIndices.Count -eq 0) { return }

    $pipeType = "DuckUtil.UiAssetPipeline" -as [type]
    $hasIncremental = ($null -ne $pipeType) -and ($null -ne $pipeType.GetMethod("EnqueueRemoteIcons"))
    if ($hasIncremental) {
        $idxList  = [System.Collections.Generic.List[int]]::new()
        $urlList  = [System.Collections.Generic.List[string]]::new()
        $fbList   = [System.Collections.Generic.List[string]]::new()
        $destList = [System.Collections.Generic.List[string]]::new()
        $keyList  = [System.Collections.Generic.List[string]]::new()
        foreach ($rIdx in $CardDesc.IconIndices) {
            $t = $script:remoteIconRegistry[$rIdx]
            if ($t -and -not $t.Applied) {
                $idxList.Add($rIdx)
                $urlList.Add([string]$t.Url)
                $fbList.Add([string]$t.FallbackUrl)
                $destList.Add([string]$t.DestPath)
                $keyList.Add([string]$t.CacheKey)
                $script:pendingIconSaves.Add($t)
            }
        }
        if ($idxList.Count -gt 0) {
            $script:remotePipelineStarted = $true
            [DuckUtil.UiAssetPipeline]::EnqueueRemoteIcons($idxList.ToArray(), $urlList.ToArray(), $fbList.ToArray(), $destList.ToArray(), $keyList.ToArray())
            if ($script:iconSyncTimer -and -not $script:iconSyncTimer.IsEnabled) {
                $script:iconSyncTimer.Start()
            }
        }
    } else {
        foreach ($rIdx in $CardDesc.IconIndices) {
            $t = $script:remoteIconRegistry[$rIdx]
            if ($t -and -not $t.Applied) { $script:pendingIconSaves.Add($t) }
        }
        if ($script:pendingIconSaves.Count -gt 0 -and $script:iconSyncTimer -and -not $script:iconSyncTimer.IsEnabled) {
            $script:iconSyncTimer.Start()
        }
    }
}

function Sync-Tab0ViewportAssets {
    if ($script:isWindowClosing -or -not $script:cardDescriptors -or $script:cardDescriptors.Count -eq 0) { return }
    $isGroupView = $script:activeCatalogCategory -and $script:activeCatalogCategory.StartsWith("__GROUP__:")
    if ($script:activeCatalogCategory -and $script:activeCatalogCategory -ne "__ALL__" -and -not $isGroupView) { return }
    $vOff = if ($appsScrollViewer) { [double]$appsScrollViewer.VerticalOffset } else { 0.0 }
    $vH   = if ($appsScrollViewer -and $appsScrollViewer.ViewportHeight -gt 100) { [double]$appsScrollViewer.ViewportHeight } else { 820.0 }
    $bandTop = $vOff - 250.0
    $bandBot = $vOff + $vH + 520.0

    $pipeType = "DuckUtil.UiAssetPipeline" -as [type]
    $hasIncremental = ($null -ne $pipeType) -and ($null -ne $pipeType.GetMethod("EnqueueRemoteIcons"))

    $idxList  = $null
    $urlList  = $null
    $fbList   = $null
    $destList = $null
    $keyList  = $null

    $descPool = if ($script:activeMasonryDescriptors) { $script:activeMasonryDescriptors } else { $script:cardDescriptors }
    foreach ($cd in $descPool) {
        if (-not $cd.Attached -and $cd.EstTop -le $bandBot) {
            $cd.Attached = $true
            if ($cd.ColPanel) { [void]$cd.ColPanel.Children.Add($cd.Card) }
        }
        if ($cd.Attached -and -not $cd.IconsEnqueued -and $cd.EstBottom -ge $bandTop -and $cd.EstTop -le $bandBot) {
            $cd.IconsEnqueued = $true
            if ($cd.IconIndices -and $cd.IconIndices.Count -gt 0) {
                if ($hasIncremental) {
                    if ($null -eq $idxList) {
                        $idxList  = [System.Collections.Generic.List[int]]::new()
                        $urlList  = [System.Collections.Generic.List[string]]::new()
                        $fbList   = [System.Collections.Generic.List[string]]::new()
                        $destList = [System.Collections.Generic.List[string]]::new()
                        $keyList  = [System.Collections.Generic.List[string]]::new()
                    }
                    foreach ($rIdx in $cd.IconIndices) {
                        $t = $script:remoteIconRegistry[$rIdx]
                        if ($t -and -not $t.Applied) {
                            $idxList.Add($rIdx)
                            $urlList.Add([string]$t.Url)
                            $fbList.Add([string]$t.FallbackUrl)
                            $destList.Add([string]$t.DestPath)
                            $keyList.Add([string]$t.CacheKey)
                            $script:pendingIconSaves.Add($t)
                        }
                    }
                } else {
                    foreach ($rIdx in $cd.IconIndices) {
                        $t = $script:remoteIconRegistry[$rIdx]
                        if ($t -and -not $t.Applied) { $script:pendingIconSaves.Add($t) }
                    }
                }
            }
        }
    }

    if ($hasIncremental -and $null -ne $idxList -and $idxList.Count -gt 0) {
        $script:remotePipelineStarted = $true
        [DuckUtil.UiAssetPipeline]::EnqueueRemoteIcons($idxList.ToArray(), $urlList.ToArray(), $fbList.ToArray(), $destList.ToArray(), $keyList.ToArray())
        if ($script:iconSyncTimer -and -not $script:iconSyncTimer.IsEnabled) {
            $script:iconSyncTimer.Start()
        }
    }
    Try-EnableCompletedCardCaches
}

function Flush-PendingIconCache {
    param([int]$MaxDecode = 24)
    if ($script:isWindowClosing -or $script:isActionRunning) { return }
    $pipeType = "DuckUtil.UiAssetPipeline" -as [type]
    if ($pipeType -and $null -ne $pipeType.GetMethod("EnqueueRemoteIcons")) {
        if (-not $script:remotePipelineStarted -and $script:cardDescriptors -and $script:cardDescriptors.Count -gt 0) {
            Sync-Tab0ViewportAssets
        }

        $readyItems = [DuckUtil.UiAssetPipeline]::DequeueReadyRemoteIcons($MaxDecode)
        $anyCardCompleted = $false
        if ($readyItems -and $readyItems.Length -gt 0) {
            foreach ($ri in $readyItems) {
                if ($null -eq $ri -or $null -eq $ri.Bitmap) { continue }
                if ($script:remoteBmpCache -and -not [string]::IsNullOrEmpty($ri.CacheKey)) {
                    $script:remoteBmpCache[$ri.CacheKey] = $ri.Bitmap
                }
                if ($script:remoteIconRegistry -and $ri.Index -ge 0 -and $ri.Index -lt $script:remoteIconRegistry.Count) {
                    $t = $script:remoteIconRegistry[$ri.Index]
                    if ($t -and -not $t.Applied) {
                        $t.Applied = $true
                        if ($script:pendingIconSaves) { [void]$script:pendingIconSaves.Remove($t) }
                        if ($t.Img) {
                            $t.Img.Source = $ri.Bitmap
                            $t.Img.Visibility = [System.Windows.Visibility]::Visible
                        }
                        if ($t.Fallback) {
                            $t.Fallback.Visibility = [System.Windows.Visibility]::Collapsed
                        }
                        if ($t.UseLight -and $t.Badge) {
                            $t.Badge.Background = $script:brushIconBadgeLightBg
                        }
                        if ($t.CardDesc) {
                            $t.CardDesc.LoadedIcons++
                            if ($t.CardDesc.LoadedIcons -ge $t.CardDesc.TotalIcons) {
                                $anyCardCompleted = $true
                            }
                        }
                    }
                }
            }
        }

        if ([DuckUtil.UiAssetPipeline]::IsRemoteIdle) {
            $script:pendingIconSaves.Clear()
            Try-EnableCompletedCardCaches
            if ($script:iconSyncTimer) { $script:iconSyncTimer.Stop() }
        } elseif ($anyCardCompleted) {
            Try-EnableCompletedCardCaches
        }
        return
    }

    if (-not $script:pendingIconSaves -or $script:pendingIconSaves.Count -eq 0) { return }
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
                        if ($data -and $data.Length -gt 230 -and $data.Length -ne 588 -and -not [System.IO.File]::Exists($entry.DestPath)) {
                            $tmpFile = "$($entry.DestPath).$([guid]::NewGuid().ToString('N')).tmp"
                            [System.IO.File]::WriteAllBytes($tmpFile, $data)
                            [System.IO.File]::Move($tmpFile, $entry.DestPath)
                            $hasLocalFile = $true
                        }
                    } catch {}
                }
                try { if ($dlInfo.Client) { $dlInfo.Client.Dispose() } } catch {}
                if (-not $hasLocalFile -and -not [string]::IsNullOrWhiteSpace($entry.FallbackUrl)) {
                    $entry.Url = $entry.FallbackUrl
                    $entry.FallbackUrl = $null
                    $entry.DownloadInfo = $null
                    continue
                }
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
$script:remoteExistingFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if (-not [System.IO.Directory]::Exists($iconsCacheDir)) {
    try { [System.IO.Directory]::CreateDirectory($iconsCacheDir) | Out-Null } catch {}
} else {
    try {
        $dirInfo = [System.IO.DirectoryInfo]::new($iconsCacheDir)
        foreach ($fi in $dirInfo.EnumerateFiles("*.png")) {
            if ($fi.Length -le 230 -or $fi.Length -eq 588) {
                try { $fi.Delete() } catch {}
            } else {
                [void]$script:remoteExistingFiles.Add($fi.Name)
            }
        }
    } catch {}

    try {
        $mapFile = Join-Path $iconsCacheDir "cache.icons.map.txt"
        $oldMap = @{}
        if ([System.IO.File]::Exists($mapFile)) {
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
                        if ([System.IO.File]::Exists($staleIcon)) {
                            try { [System.IO.File]::Delete($staleIcon) } catch {}
                            [void]$script:remoteExistingFiles.Remove("$appKey.png")
                        }
                        $mapChanged = $true
                    }
                } else {
                    $mapChanged = $true
                }
            }
        }
        if ($mapChanged -or -not [System.IO.File]::Exists($mapFile)) {
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
$script:cancelRequested = $false
$script:isUninstallingQueue = $false
$script:uninstallQueue = [System.Collections.Generic.List[object]]::new()
$script:uninstallQueuedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
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
                    <TextBlock Name="dlgModeBadgeText" FontSize="11" FontWeight="SemiBold" TextWrapping="Wrap"/>
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
        [double]$TimeoutSeconds = 60,
        [scriptblock]$CancelCheck = $null
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
            $canceledNow = $false
            if ($CancelCheck) {
                try { $canceledNow = [bool](& $CancelCheck) } catch {}
            }
            if ($Task.IsCompleted -or $script:isWindowClosing -or $canceledNow -or $sw.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $frame.Continue = $false
            }
        }.GetNewClosure())

        try {
            $smoothType = "DuckUtil.SmoothScrollController" -as [type]
            if ($smoothType -and $null -ne $smoothType.GetMethod("AttachFrameWake")) {
                $smoothType::AttachFrameWake($Task, $disp, $frame)
            }
            $canceledInit = $false
            if ($CancelCheck) { try { $canceledInit = [bool](& $CancelCheck) } catch {} }
            if (-not $Task.IsCompleted -and -not $script:isWindowClosing -and -not $canceledInit) {
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
        $canceledFb = $false
        if ($CancelCheck) { try { $canceledFb = [bool](& $CancelCheck) } catch {} }
        if ($script:isWindowClosing -or $canceledFb -or $swFallback.Elapsed.TotalSeconds -ge $TimeoutSeconds) { break }
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
    if ($script:isActionRunning -or $script:isScanningApps -or $script:isUpdatingUninstaller -or $script:isUninstallingQueue) {
        Log-Text "[WARN] Đang có một tác vụ khác đang thực thi ($ActionName). Vui lòng đợi!"
        return
    }
    if (-not $DeferExpand) {
        Expand-TerminalLog
    }
    $script:isActionRunning = $true
    $script:cancelRequested = $false
    try {
        & $Action
    } catch {
        Log-Text "[!] Lỗi khi thực hiện '$ActionName': $($_.Exception.Message)"
    } finally {
        $script:isActionRunning = $false
        $script:cancelRequested = $false
        $script:isScanningApps = $false
        $script:isUpdatingUninstaller = $false
        $script:suppressSelectionCount = $false
        $script:suppressUninstallerSelectionCount = $false
        if ($btnCancelAction) {
            try {
                $btnCancelAction.Visibility = [System.Windows.Visibility]::Collapsed
                $btnCancelAction.IsEnabled = $true
                $btnCancelAction.Content = "Dừng tác vụ"
            } catch {}
        }
        if ($borderQueueBadge) {
            try { $borderQueueBadge.Visibility = [System.Windows.Visibility]::Collapsed } catch {}
        }
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

    if ($index -eq 0) {
        if ($script:cardDescriptors -and $script:cardDescriptors.Count -gt 0) {
            try { Sync-Tab0ViewportAssets } catch {}
        }
    } elseif ($index -eq 1) {
        if (-not $script:uninstallerLoadedOnce) {
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
        } else {
            if ($script:uninstallerVirtualView) {
                $script:uninstallerVirtualView.SyncViewport($true)
            } elseif (Get-Command "Sync-UninstallerViewport" -ErrorAction SilentlyContinue) {
                Sync-UninstallerViewport -Force
            }
            if ($script:uninstIconsPipelineNeedsStart -and (Get-Command "Start-UninstallerIconPipelineIfNeeded" -ErrorAction SilentlyContinue)) {
                Start-UninstallerIconPipelineIfNeeded
            }
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
$script:brushUninstFilterBrokenBg     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x2D, 0x12, 0x15)); $script:brushUninstFilterBrokenBg.Freeze()
$script:brushUninstFilterBrokenFg     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF8, 0x71, 0x71)); $script:brushUninstFilterBrokenFg.Freeze()
$script:brushUninstHeaderInactiveFg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x7C, 0x8D, 0xA4)); $script:brushUninstHeaderInactiveFg.Freeze()

$script:styleUninstRow = New-Object System.Windows.Style([System.Windows.Controls.Border])
$script:styleUninstRow.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $script:brushUninstRowBg)))
$trigUninstHover = New-Object System.Windows.Trigger
$trigUninstHover.Property = [System.Windows.UIElement]::IsMouseOverProperty
$trigUninstHover.Value = $true
$trigUninstHover.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $script:brushUninstRowHover)))
$script:styleUninstRow.Triggers.Add($trigUninstHover)
$script:styleUninstRow.Seal()

$script:uninstIconsPipelineNeedsStart = $false
$script:uninstPipelineStarted       = $false
$script:pendingUninstTargets          = $null
$script:uninstPanelRoutedAttached     = $false

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
        @{ Pattern = 'Corretto';                                Id = 'Amazon.Corretto.25.JDK' },
        @{ Pattern = 'Temurin|Adoptium';                        Id = 'EclipseAdoptium.Temurin.21.JDK' },
        @{ Pattern = 'Java \d+|Java\(TM\)|OpenJDK';             Id = 'Oracle.JavaRuntimeEnvironment' },
        @{ Pattern = 'Node\.js';                                Id = 'OpenJS.NodeJS.LTS' },
        @{ Pattern = 'GitHub CLI';                              Id = 'GitHub.cli' },
        @{ Pattern = '^Git\b';                                  Id = 'Git.Git' },
        @{ Pattern = 'Python';                                  Id = 'Python.Python.3.13' },
        @{ Pattern = 'Rustup';                                  Id = 'Rustlang.Rustup' },
        @{ Pattern = 'PowerToys';                               Id = 'Microsoft.PowerToys' },
        @{ Pattern = 'Legacy Launcher';                         Id = 'LegacyLauncher.LegacyLauncher' },
        @{ Pattern = 'Google Chrome';                           Id = 'Google.Chrome' },
        @{ Pattern = 'Chrome Remote Desktop';                   Id = 'Google.ChromeRemoteDesktopHost' },
        @{ Pattern = 'Brave';                                   Id = 'Brave.Brave' },
        @{ Pattern = 'Firefox';                                 Id = 'Mozilla.Firefox' },
        @{ Pattern = 'Microsoft Edge';                          Id = 'Microsoft.Edge' },
        @{ Pattern = 'Discord';                                 Id = 'Discord.Discord' },
        @{ Pattern = 'Zalo';                                    Id = 'VNGCorp.Zalo' },
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

$script:uninstallerVisibleEntries = [System.Collections.Generic.List[object]]::new()
$script:uninstIconRegistry        = [System.Collections.Generic.List[object]]::new()
$script:uninstTopSpacer           = [System.Windows.Controls.Border]::new()
$script:uninstTopSpacer.IsHitTestVisible = $false
$script:uninstTopSpacer.Height    = 0.0
$script:uninstBottomSpacer        = [System.Windows.Controls.Border]::new()
$script:uninstBottomSpacer.IsHitTestVisible = $false
$script:uninstBottomSpacer.Height = 0.0
$script:uninstLastStart           = -1
$script:uninstLastEnd             = -1

function Ensure-UninstallerRowRealized {
    param($Entry)
    if ($null -eq $Entry) { return $null }
    if ($null -ne $Entry.Row) { return $Entry.Row }

    $app = $Entry.App
    $sizeText = if ($app.SizeBytes -and $app.SizeBytes -gt 0) {
        $mb = [double]$app.SizeBytes / 1MB
        if ($mb -ge 1024) { "{0:N2} GB" -f ($mb / 1024.0) } else { "{0:N1} MB" -f $mb }
    } else {
        "--"
    }
    $targetFolder = if ($app.PSObject.Properties['TargetFolder'] -and $null -ne $app.TargetFolder) {
        $app.TargetFolder
    } elseif (-not [string]::IsNullOrWhiteSpace($app.InstallLocation) -and [System.IO.Directory]::Exists($app.InstallLocation)) {
        $app.InstallLocation
    } elseif ($app.PSObject.Properties['DataLocation'] -and -not [string]::IsNullOrWhiteSpace($app.DataLocation) -and [System.IO.Directory]::Exists($app.DataLocation)) {
        $app.DataLocation
    } else {
        ""
    }
    $dataTip = if ($app.PSObject.Properties['DataLocation'] -and -not [string]::IsNullOrWhiteSpace($app.DataLocation)) { "`nKhu dữ liệu riêng: $($app.DataLocation)" } else { "" }
    $rowTip = "$($app.DisplayName)`nPhiên bản: $($app.DisplayVersion)`nNhà phát hành: $($app.Publisher)`nĐường dẫn: $($app.InstallLocation)$dataTip`nLệnh gỡ: $($app.UninstallString)"

    $bestTarget = $Entry.IconTarget
    $preCached = $null
    if (-not [string]::IsNullOrWhiteSpace($bestTarget)) {
        if ("DuckUtil.UiAssetPipeline" -as [type]) {
            $preCached = [DuckUtil.UiAssetPipeline]::TryGetCachedUninstIcon($bestTarget)
        }
        if ($null -eq $preCached -and $script:uninstallerIconCache.TryGetValue($bestTarget, [ref]$preCached)) {
        }
    }

    $vis = [DuckUtil.UiAssetPipeline]::CreateUninstallerRow(
        [string]$app.DisplayName,
        [string]$app.DisplayVersion,
        [string]$app.Publisher,
        [string]$sizeText,
        [bool]$app.IsBrokenOrphan,
        [string]$targetFolder,
        [string]$rowTip,
        [string]$strFolderEmoji,
        $script:styleUninstRow,
        $script:brushUninstRowBorder,
        $script:brushUninstTitle,
        $script:brushUninstTitleBroken,
        $script:brushUninstMuted,
        $script:brushUninstLight,
        $script:brushUninstBadgeBg,
        $script:brushUninstBadgeFg,
        $script:brushUninstBadgeBrokenBg,
        $script:brushUninstBadgeBrokenFg,
        $script:brushUninstStatusOkBg,
        $script:brushUninstStatusOkBorder,
        $script:brushUninstStatusOkFg,
        $script:brushUninstStatusBrokenBg,
        $script:brushUninstStatusBrokenBorder,
        $script:brushUninstFolderBg,
        $script:brushUninstFolderBorder,
        $preCached
    )

    $Entry.Row           = $vis.RowBorder
    $Entry.CheckBox      = $vis.CheckBox
    $Entry.IconImg       = $vis.IconImg
    $Entry.FallbackBadge = $vis.FallbackBadge
    $vis.RowBorder.Tag   = $Entry
    if ($null -ne $preCached) { $Entry.IconLoaded = $true }
    if ($Entry.IsQueued) { $vis.RowBorder.Opacity = 0.52 }

    if ($Entry.IsSelected) {
        $prevSup = $script:suppressUninstallerSelectionCount
        $script:suppressUninstallerSelectionCount = $true
        try {
            $vis.CheckBox.IsChecked = $true
            $vis.RowBorder.Background = $script:brushUninstRowCheckedBg
        } finally {
            $script:suppressUninstallerSelectionCount = $prevSup
        }
    }
    return $Entry.Row
}

function Sync-UninstallerViewport {
    param([switch]$Force)
    if ($script:isWindowClosing -or -not $uninstallerRowsPanel) { return }
    $pipeType = "DuckUtil.UiAssetPipeline" -as [type]
    if (-not ($pipeType -and $null -ne $pipeType.GetMethod("CreateUninstallerRow"))) { return }

    $isTab1Visible = $script:tabPages -and $script:tabPages.Count -gt 1 -and $script:tabPages[1] -and $script:tabPages[1].Visibility -eq [System.Windows.Visibility]::Visible
    if (-not $isTab1Visible) { return }

    $visCount = $script:uninstallerVisibleEntries.Count
    if ($visCount -eq 0) {
        if ($uninstallerRowsPanel.Children.Count -gt 0) { $uninstallerRowsPanel.Children.Clear() }
        $script:uninstLastStart = -1
        $script:uninstLastEnd   = -1
        return
    }

    $rowH = 38.0
    $vOff = if ($uninstallerScrollViewer) { [double]$uninstallerScrollViewer.VerticalOffset } else { 0.0 }
    $vH   = if ($uninstallerScrollViewer -and $uninstallerScrollViewer.ViewportHeight -gt 100) { [double]$uninstallerScrollViewer.ViewportHeight } else { 620.0 }

    $startIdx = [Math]::Max(0, [int][Math]::Floor($vOff / $rowH) - 5)
    $endIdx   = [Math]::Min($visCount - 1, [int][Math]::Ceiling(($vOff + $vH) / $rowH) + 8)

    $prevStart = $script:uninstLastStart
    $prevEnd   = $script:uninstLastEnd
    if (-not $Force -and $startIdx -eq $prevStart -and $endIdx -eq $prevEnd) {
        return
    }
    $script:uninstLastStart = $startIdx
    $script:uninstLastEnd   = $endIdx

    $enqIdx   = $null
    $enqPaths = $null
    $hasIncUninst = ($null -ne $pipeType.GetMethod("EnqueueUninstallerIcons"))

    $script:uninstTopSpacer.Height    = $startIdx * $rowH
    $script:uninstBottomSpacer.Height = [Math]::Max(0, ($visCount - 1 - $endIdx)) * $rowH

    $canSlide = (-not $Force) -and ($prevStart -ge 0) -and ($prevEnd -ge $prevStart) -and
        ($startIdx -le $prevEnd) -and ($endIdx -ge $prevStart) -and
        ($uninstallerRowsPanel.Children.Count -eq ($prevEnd - $prevStart + 3))

    if ($canSlide) {
        $curS = $prevStart
        $curE = $prevEnd
        while ($curS -lt $startIdx) {
            $uninstallerRowsPanel.Children.RemoveAt(1)
            $curS++
        }
        while ($curE -gt $endIdx) {
            $uninstallerRowsPanel.Children.RemoveAt($uninstallerRowsPanel.Children.Count - 2)
            $curE--
        }
        for ($i = $curS - 1; $i -ge $startIdx; $i--) {
            $entry = $script:uninstallerVisibleEntries[$i]
            $rowEl = Ensure-UninstallerRowRealized -Entry $entry
            if ($null -ne $rowEl) { $uninstallerRowsPanel.Children.Insert(1, $rowEl) }
            if ($hasIncUninst -and -not $entry.IconLoaded -and -not $entry.IconEnqueued -and -not [string]::IsNullOrWhiteSpace($entry.IconTarget)) {
                $entry.IconEnqueued = $true
                if ($null -eq $enqIdx) { $enqIdx = [System.Collections.Generic.List[int]]::new(); $enqPaths = [System.Collections.Generic.List[string]]::new() }
                $enqIdx.Add([int]$entry.RegIndex); $enqPaths.Add([string]$entry.IconTarget); $script:pendingUninstIcons.Add($entry)
            }
        }
        for ($i = $curE + 1; $i -le $endIdx; $i++) {
            $entry = $script:uninstallerVisibleEntries[$i]
            $rowEl = Ensure-UninstallerRowRealized -Entry $entry
            if ($null -ne $rowEl) { $uninstallerRowsPanel.Children.Insert($uninstallerRowsPanel.Children.Count - 1, $rowEl) }
            if ($hasIncUninst -and -not $entry.IconLoaded -and -not $entry.IconEnqueued -and -not [string]::IsNullOrWhiteSpace($entry.IconTarget)) {
                $entry.IconEnqueued = $true
                if ($null -eq $enqIdx) { $enqIdx = [System.Collections.Generic.List[int]]::new(); $enqPaths = [System.Collections.Generic.List[string]]::new() }
                $enqIdx.Add([int]$entry.RegIndex); $enqPaths.Add([string]$entry.IconTarget); $script:pendingUninstIcons.Add($entry)
            }
        }
    } else {
        $uninstallerRowsPanel.Children.Clear()
        [void]$uninstallerRowsPanel.Children.Add($script:uninstTopSpacer)
        for ($i = $startIdx; $i -le $endIdx; $i++) {
            $entry = $script:uninstallerVisibleEntries[$i]
            $rowEl = Ensure-UninstallerRowRealized -Entry $entry
            if ($null -ne $rowEl) {
                [void]$uninstallerRowsPanel.Children.Add($rowEl)
            }
            if ($hasIncUninst -and -not $entry.IconLoaded -and -not $entry.IconEnqueued -and -not [string]::IsNullOrWhiteSpace($entry.IconTarget)) {
                $entry.IconEnqueued = $true
                if ($null -eq $enqIdx) {
                    $enqIdx   = [System.Collections.Generic.List[int]]::new()
                    $enqPaths = [System.Collections.Generic.List[string]]::new()
                }
                $enqIdx.Add([int]$entry.RegIndex)
                $enqPaths.Add([string]$entry.IconTarget)
                $script:pendingUninstIcons.Add($entry)
            }
        }
        [void]$uninstallerRowsPanel.Children.Add($script:uninstBottomSpacer)
    }

    if ($hasIncUninst -and $null -ne $enqIdx -and $enqIdx.Count -gt 0) {
        $script:uninstPipelineStarted = $true
        [DuckUtil.UiAssetPipeline]::EnqueueUninstallerIcons($enqIdx.ToArray(), $enqPaths.ToArray())
        if ($script:uninstIconTimer -and -not $script:uninstIconTimer.IsEnabled) {
            $script:uninstIconTimer.Start()
        }
    }
}

$script:uninstallerVirtualView = $null
if ($uninstallerScrollViewer -and ($uninstallerRowsPanel -is [System.Windows.Controls.Canvas]) -and ("DuckUtil.UninstallerVirtualView" -as [type])) {
    $tabPage1Ref = if ($script:tabPages -and $script:tabPages.Count -gt 1) { $script:tabPages[1] } else { $null }
    $strFolderGlyphInit = [char]::ConvertFromUtf32(0x1F4C1)
    $script:uninstallerVirtualView = [DuckUtil.UninstallerVirtualView]::new(
        $uninstallerScrollViewer,
        $uninstallerRowsPanel,
        $tabPage1Ref,
        $strFolderGlyphInit,
        $script:styleUninstRow,
        $script:brushUninstRowBorder,
        $script:brushUninstColDivider,
        $script:brushUninstRowCheckedBg,
        $script:brushUninstTitle,
        $script:brushUninstTitleBroken,
        $script:brushUninstMuted,
        $script:brushUninstLight,
        $script:brushUninstBadgeBg,
        $script:brushUninstBadgeFg,
        $script:brushUninstBadgeBrokenBg,
        $script:brushUninstBadgeBrokenFg,
        $script:brushUninstStatusOkBg,
        $script:brushUninstStatusOkBorder,
        $script:brushUninstStatusOkFg,
        $script:brushUninstStatusBrokenBg,
        $script:brushUninstStatusBrokenBorder,
        $script:brushUninstFolderBg,
        $script:brushUninstFolderBorder
    )
    $script:uninstallerVirtualView.CanInteract = [System.Func[bool]]{
        return (-not $script:isWindowClosing -and -not $script:isUpdatingUninstaller -and -not $script:isActionRunning)
    }
    $script:uninstallerVirtualView.OnSelectionChanged = [System.Action[int]]{
        param([int]$cnt)
        Update-UninstallerSelectionButtons -Count $cnt
    }
    $script:uninstallerRowEntries = $script:uninstallerVirtualView.AllItems
    $script:uninstallerVisibleEntries = $script:uninstallerVirtualView.VisibleItems
}

if ($uninstallerScrollViewer -and -not $script:uninstallerVirtualView) {
    $uninstallerScrollViewer.Add_ScrollChanged({
        Sync-UninstallerViewport
    })
}

function Start-UninstallerIconPipelineIfNeeded {
    if ($script:isWindowClosing) {
        $script:uninstIconsPipelineNeedsStart = $false
        return
    }
    $script:uninstIconsPipelineNeedsStart = $false
    if ($script:uninstallerVirtualView) {
        $script:uninstallerVirtualView.SyncViewport($true)
        return
    }
    $pipeType = "DuckUtil.UiAssetPipeline" -as [type]
    if ($pipeType -and $null -ne $pipeType.GetMethod("EnqueueUninstallerIcons")) {
        Sync-UninstallerViewport -Force
        return
    }
    if (-not $script:pendingUninstIcons -or $script:pendingUninstIcons.Count -eq 0) { return }
    if ($script:uninstIconTimer -and -not $script:uninstIconTimer.IsEnabled) {
        $script:uninstIconTimer.Start()
    }
}

$script:uninstIconTimer = [System.Windows.Threading.DispatcherTimer]::new([System.Windows.Threading.DispatcherPriority]::Background)
$script:uninstIconTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$script:uninstIconTimer.Add_Tick({
    if ($script:isWindowClosing) {
        $script:uninstIconTimer.Stop()
        return
    }
    if ($script:isUpdatingUninstaller) { return }
    $pipeType = "DuckUtil.UiAssetPipeline" -as [type]
    if ($pipeType -and $null -ne $pipeType.GetMethod("DequeueReadyUninstallerIcons")) {
        $readyItems = [DuckUtil.UiAssetPipeline]::DequeueReadyUninstallerIcons(12)
        if ($readyItems -and $readyItems.Length -gt 0) {
            foreach ($ri in $readyItems) {
                if ($null -eq $ri -or $null -eq $ri.Bitmap) { continue }
                if (-not [string]::IsNullOrEmpty($ri.CacheKey)) {
                    $script:uninstallerIconCache[$ri.CacheKey] = $ri.Bitmap
                }
                if ($script:uninstIconRegistry -and $ri.Index -ge 0 -and $ri.Index -lt $script:uninstIconRegistry.Count) {
                    $ent = $script:uninstIconRegistry[$ri.Index]
                    if ($ent) {
                        $ent.IconLoaded = $true
                        if ($script:pendingUninstIcons) { [void]$script:pendingUninstIcons.Remove($ent) }
                        if ($ent.IconImg) {
                            $ent.IconImg.Source = $ri.Bitmap
                            $ent.IconImg.Visibility = [System.Windows.Visibility]::Visible
                        }
                        if ($ent.FallbackBadge) {
                            $ent.FallbackBadge.Visibility = [System.Windows.Visibility]::Collapsed
                        }
                    }
                }
            }
        }
        if ([DuckUtil.UiAssetPipeline]::IsUninstIdle) {
            $script:pendingUninstIcons.Clear()
            $script:uninstIconTimer.Stop()
        }
        return
    }

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

function Update-UninstallerSelectionButtons {
    param([int]$Count)
    if ($script:suppressUninstallerSelectionCount -or $script:isWindowClosing) { return }
    if ($btnDeepUninstall) {
        $btnDeepUninstall.Content = if ($script:isUninstallingQueue) { "+ Thêm vào hàng đợi ($Count)" } else { "Gỡ cài đặt ($Count)" }
        $btnDeepUninstall.IsEnabled = ($Count -gt 0)
    }
    if ($btnForceStopUninstall) {
        $btnForceStopUninstall.Content = if ($script:isUninstallingQueue) { "+ Buộc dừng vào hàng ($Count)" } else { "Buộc dừng & Xóa ($Count)" }
        $btnForceStopUninstall.IsEnabled = ($Count -gt 0)
    }
}

function Update-UninstallerSelectionCount {
    if ($script:suppressUninstallerSelectionCount -or $script:isWindowClosing) { return }
    if ($script:uninstallerVirtualView) {
        Update-UninstallerSelectionButtons -Count ([int]$script:uninstallerVirtualView.SelectedCount)
        return
    }
    $count = 0
    foreach ($entry in $script:uninstallerRowEntries) {
        if (-not $entry.IsRemoved -and ($entry.IsSelected -or ($entry.CheckBox -and $entry.CheckBox.IsChecked -eq $true))) {
            $count++
        }
    }
    Update-UninstallerSelectionButtons -Count $count
}

function Apply-UninstallerFilter {
    param([switch]$Resort)
    if ($script:isWindowClosing) { return }
    $q = if ($txtUninstallSearch) { $txtUninstallSearch.Text } else { "" }

    if ($script:uninstallerVirtualView) {
        $stats = $script:uninstallerVirtualView.ApplyFilterAndSort(
            [string]$q,
            ($script:uninstallerFilterMode -eq "Broken"),
            ($script:uninstallerSortMode -eq "Size"),
            [bool]$Resort
        )
        if ($txtUninstallerSummary -and $stats) {
            $vMb = [double]$stats.VisibleBytes / 1MB
            $totalSizeStr = if ($vMb -ge 1024) { "{0:N2} GB" -f ($vMb / 1024.0) } else { "{0:N1} MB" -f $vMb }
            $txtUninstallerSummary.Text = "Đang hiển thị $($stats.VisibleCount) / $($stats.TotalCount) ứng dụng (Tổng: $totalSizeStr • $($stats.BrokenCount) lỗi/mồ côi)"
        }
        Update-UninstallerSelectionButtons -Count $(if ($stats) { [int]$stats.SelectedCount } else { 0 })
        return
    }

    $q = if ($q) { $q.Trim().ToLowerInvariant() } else { "" }
    $visibleCount = 0
    $brokenCount = 0
    [long]$visibleBytes = 0

    $pipeType = "DuckUtil.UiAssetPipeline" -as [type]
    $useVirtualTab1 = ($null -ne $pipeType) -and ($null -ne $pipeType.GetMethod("CreateUninstallerRow"))
    $script:uninstallerVisibleEntries.Clear()

    foreach ($entry in $script:uninstallerRowEntries) {
        if ($entry.IsRemoved) { continue }
        $app = $entry.App
        if ($app.IsBrokenOrphan) { $brokenCount++ }

        $matchSearch = [string]::IsNullOrEmpty($q) -or $entry.SearchText.Contains($q)
        $matchFilter = if ($script:uninstallerFilterMode -eq "Broken") { [bool]$app.IsBrokenOrphan } else { $true }

        if ($matchSearch -and $matchFilter) {
            if ($useVirtualTab1) {
                [void]$script:uninstallerVisibleEntries.Add($entry)
            } elseif ($entry.Row) {
                $entry.Row.Visibility = [System.Windows.Visibility]::Visible
            }
            $visibleCount++
            if ($app.SizeBytes -and $app.SizeBytes -gt 0) {
                $visibleBytes += [long]$app.SizeBytes
            }
        } elseif (-not $useVirtualTab1 -and $entry.Row) {
            $entry.Row.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }

    if ($useVirtualTab1) {
        if ($uninstallerScrollViewer) {
            $maxOff = [Math]::Max(0.0, ($visibleCount * 38.0) - [Math]::Max(100.0, [double]$uninstallerScrollViewer.ViewportHeight))
            if ($uninstallerScrollViewer.VerticalOffset -gt $maxOff) {
                $uninstallerScrollViewer.ScrollToVerticalOffset($maxOff)
            }
        }
        Sync-UninstallerViewport -Force
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

        if ($script:uninstallerVirtualView) {
            Apply-UninstallerFilter -Resort:(-not $HeadersOnly)
        } else {
            if (-not $HeadersOnly -and $uninstallerRowsPanel -and $script:uninstallerRowEntries -and $script:uninstallerRowEntries.Count -gt 0) {
                $sortedEntries = if ($Mode -eq "Size") {
                    @($script:uninstallerRowEntries | Sort-Object -Property @{ Expression = { [long]$_.App.SizeBytes }; Descending = $true }, @{ Expression = { $_.App.DisplayName }; Descending = $false })
                } else {
                    @($script:uninstallerRowEntries | Sort-Object -Property @{ Expression = { [bool]$_.App.IsBrokenOrphan }; Descending = $true }, @{ Expression = { $_.App.DisplayName }; Descending = $false })
                }
                $pipeType = "DuckUtil.UiAssetPipeline" -as [type]
                $useVirtualTab1 = ($null -ne $pipeType) -and ($null -ne $pipeType.GetMethod("CreateUninstallerRow"))
                if ($useVirtualTab1) {
                    $script:uninstallerRowEntries.Clear()
                    foreach ($entry in $sortedEntries) {
                        [void]$script:uninstallerRowEntries.Add($entry)
                    }
                } else {
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
            }
            Apply-UninstallerFilter
        }
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

if ($uninstallerRowsPanel -and -not $script:uninstallerVirtualView -and -not $script:uninstPanelRoutedAttached) {
    $script:uninstPanelRoutedAttached = $true
    $uninstallerRowsPanel.AddHandler(
        [System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent,
        [System.Windows.RoutedEventHandler]{
            param($s, $e)
            $cb = $e.OriginalSource -as [System.Windows.Controls.CheckBox]
            if ($cb -and $cb.Tag -is [System.Windows.Controls.Border]) {
                $cb.Tag.Background = $script:brushUninstRowCheckedBg
                if ($cb.Tag.Tag -is [hashtable]) { $cb.Tag.Tag.IsSelected = $true }
            }
            Update-UninstallerSelectionCount
        }
    )
    $uninstallerRowsPanel.AddHandler(
        [System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent,
        [System.Windows.RoutedEventHandler]{
            param($s, $e)
            $cb = $e.OriginalSource -as [System.Windows.Controls.CheckBox]
            if ($cb -and $cb.Tag -is [System.Windows.Controls.Border]) {
                if ($cb.Tag.Style -eq $script:styleUninstRow) {
                    $cb.Tag.ClearValue([System.Windows.Controls.Border]::BackgroundProperty)
                } else {
                    $cb.Tag.Background = $script:brushUninstRowBg
                }
                if ($cb.Tag.Tag -is [hashtable]) { $cb.Tag.Tag.IsSelected = $false }
            }
            Update-UninstallerSelectionCount
        }
    )
    $uninstallerRowsPanel.AddHandler(
        [System.Windows.UIElement]::MouseLeftButtonUpEvent,
        [System.Windows.Input.MouseButtonEventHandler]{
            param($sender, $e)
            if ($e.Handled -or $script:isWindowClosing -or $script:isUpdatingUninstaller -or $script:isActionRunning) { return }
            $node = $e.OriginalSource
            while ($node -ne $null -and $node -ne $sender) {
                if ($node -is [System.Windows.Controls.Primitives.ToggleButton]) { return }
                if ($node -is [System.Windows.Controls.Border]) {
                    if ($node.Tag -is [string] -and -not [string]::IsNullOrWhiteSpace($node.Tag)) {
                        $e.Handled = $true
                        $loc = [string]$node.Tag
                        if ([System.IO.Directory]::Exists($loc)) {
                            try { Start-Process "explorer.exe" "`"$loc`"" } catch {}
                        }
                        return
                    }
                    if ($node.Tag -is [hashtable] -and $node.Tag.ContainsKey('CheckBox') -and $node.Style -eq $script:styleUninstRow) {
                        $cbRef = $node.Tag['CheckBox']
                        if ($cbRef) { $cbRef.IsChecked = -not $cbRef.IsChecked }
                        return
                    }
                }
                if ($node -is [System.Windows.Media.Visual]) {
                    $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
                } else { break }
            }
        }
    )
}

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
        if ("DuckUtil.UiAssetPipeline" -as [type]) {
            try { [DuckUtil.UiAssetPipeline]::StopUninstallerIconPipeline() } catch {}
        }
        $script:uninstPipelineStarted = $false
        $script:uninstIconsPipelineNeedsStart = $false
        $script:pendingUninstTargets = $null
        $script:pendingUninstIcons.Clear()
        $script:uninstIconRegistry.Clear()
        $script:uninstLastStart = -1
        $script:uninstLastEnd   = -1

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

        if ($script:uninstallerVirtualView) {
            $buildTask = [DuckUtil.UninstallerVirtualView]::BuildVirtualItemsAsync($script:cachedUninstallerApps, $script:catalogIconLookup, $iconsCacheDir)
            [void](Wait-TaskNonBlocking -Task $buildTask -TimeoutSeconds 30)
            if ($script:isWindowClosing) { return }
            $builtItems = if ($buildTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) { $buildTask.Result } else { $null }
            $script:uninstallerVirtualView.SetItems($builtItems, $script:cachedUninstallerApps.Count)
            $script:uninstallerRowEntries = $script:uninstallerVirtualView.AllItems
            $script:uninstallerVisibleEntries = $script:uninstallerVirtualView.VisibleItems
            $script:uninstallerLoadedOnce = $true
            $script:deferredUninstallerLoad = $false
            $script:uninstallerLoadQueued = $false
            Set-UninstallerSortMode $script:uninstallerSortMode
        } else {
        $sortedApps = if ($script:uninstallerSortMode -eq "Size") {
            @($script:cachedUninstallerApps | Sort-Object -Property @{ Expression = { [long]$_.SizeBytes }; Descending = $true }, @{ Expression = { $_.DisplayName }; Descending = $false })
        } else {
            @($script:cachedUninstallerApps | Sort-Object -Property @{ Expression = { [bool]$_.IsBrokenOrphan }; Descending = $true }, @{ Expression = { $_.DisplayName }; Descending = $false })
        }

        $uninstallerRowsPanel.Visibility = [System.Windows.Visibility]::Collapsed
        try {
            $uninstallerRowsPanel.Children.Clear()
            $script:uninstallerRowEntries.Clear()

            $pipeType = "DuckUtil.UiAssetPipeline" -as [type]
            $hasFastRowBuilder = ($null -ne $pipeType) -and ($null -ne $pipeType.GetMethod("CreateUninstallerRow"))
            if ($hasFastRowBuilder) {
                $regIdx = 0
                foreach ($app in $sortedApps) {
                    if ($script:isWindowClosing) { return }
                    $searchIdx = if ($app.PSObject.Properties['SearchIndex'] -and -not [string]::IsNullOrEmpty($app.SearchIndex)) {
                        $app.SearchIndex
                    } else {
                        "$($app.DisplayName) $($app.Publisher) $($app.DisplayVersion)".ToLowerInvariant()
                    }
                    $bestTarget = Get-UninstallerBestIconTarget -App $app
                    $entry = @{
                        Row           = $null
                        App           = $app
                        CheckBox      = $null
                        IconImg       = $null
                        FallbackBadge = $null
                        SearchText    = $searchIdx
                        IconTarget    = $bestTarget
                        IconEnqueued  = $false
                        IconLoaded    = $false
                        IsSelected    = $false
                        IsQueued      = $false
                        IsRemoved     = $false
                        RegIndex      = $regIdx
                    }
                    $regIdx++
                    [void]$script:uninstIconRegistry.Add($entry)
                    [void]$script:uninstallerRowEntries.Add($entry)
                }
            } else {
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
            $isTab1Visible = $script:tabPages -and $script:tabPages.Count -gt 1 -and $script:tabPages[1] -and $script:tabPages[1].Visibility -eq [System.Windows.Visibility]::Visible
            if ($isTab1Visible) {
                Start-UninstallerIconPipelineIfNeeded
            } else {
                $script:uninstIconsPipelineNeedsStart = $true
            }
        }
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
        $btnFilterUninstAll.Background = $script:brushUninstFilterActiveBg
        $btnFilterUninstAll.Foreground = $script:brushUninstFilterActiveFg
        $btnFilterUninstBroken.Background = $script:brushTransparent
        $btnFilterUninstBroken.Foreground = $script:brushUninstDark
        Apply-UninstallerFilter
    })
}

if ($btnFilterUninstBroken) {
    $btnFilterUninstBroken.Add_Click({
        if ($script:isWindowClosing -or $script:isUpdatingUninstaller) { return }
        $script:uninstallerFilterMode = "Broken"
        $btnFilterUninstBroken.Background = $script:brushUninstFilterBrokenBg
        $btnFilterUninstBroken.Foreground = $script:brushUninstFilterBrokenFg
        $btnFilterUninstAll.Background = $script:brushTransparent
        $btnFilterUninstAll.Foreground = $script:brushUninstDark
        Apply-UninstallerFilter
    })
}

$script:uninstSearchDebounceTimer = [System.Windows.Threading.DispatcherTimer]::new([System.Windows.Threading.DispatcherPriority]::Background)
$script:uninstSearchDebounceTimer.Interval = [TimeSpan]::FromMilliseconds(55)
$script:uninstSearchDebounceTimer.Add_Tick({
    $script:uninstSearchDebounceTimer.Stop()
    if ($script:isWindowClosing -or $script:isUpdatingUninstaller) { return }
    Apply-UninstallerFilter
})

if ($txtUninstallSearch) {
    $txtUninstallSearch.Add_TextChanged({
        if ($script:isWindowClosing -or $script:isUpdatingUninstaller) { return }
        $script:uninstSearchDebounceTimer.Stop()
        $script:uninstSearchDebounceTimer.Start()
    })
}

if ($btnClearUninstallSearch) {
    $btnClearUninstallSearch.Add_Click({
        if ($script:isWindowClosing -or $script:isUpdatingUninstaller) { return }
        $script:uninstSearchDebounceTimer.Stop()
        if ($txtUninstallSearch) { $txtUninstallSearch.Text = "" }
        $script:uninstSearchDebounceTimer.Stop()
        Apply-UninstallerFilter
    })
}

if ($btnUninstallSelectAll) {
    $btnUninstallSelectAll.Add_Click({
        if ($script:isWindowClosing -or $script:isUpdatingUninstaller -or $script:isActionRunning) { return }
        if ($script:uninstallerVirtualView) {
            [void]$script:uninstallerVirtualView.SelectAllVisible()
            return
        }
        $script:suppressUninstallerSelectionCount = $true
        try {
            $pipeType = "DuckUtil.UiAssetPipeline" -as [type]
            if ($pipeType -and $null -ne $pipeType.GetMethod("CreateUninstallerRow")) {
                foreach ($entry in $script:uninstallerVisibleEntries) {
                    $entry.IsSelected = $true
                    if ($entry.CheckBox) { $entry.CheckBox.IsChecked = $true }
                    if ($entry.Row) { $entry.Row.Background = $script:brushUninstRowCheckedBg }
                }
            } else {
                foreach ($entry in $script:uninstallerRowEntries) {
                    if ($entry.Row -and $entry.Row.Visibility -eq [System.Windows.Visibility]::Visible) {
                        $entry.IsSelected = $true
                        $entry.CheckBox.IsChecked = $true
                    }
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
        if ($script:uninstallerVirtualView) {
            [void]$script:uninstallerVirtualView.DeselectAll()
            return
        }
        $script:suppressUninstallerSelectionCount = $true
        try {
            foreach ($entry in $script:uninstallerRowEntries) {
                $entry.IsSelected = $false
                if ($entry.CheckBox) { $entry.CheckBox.IsChecked = $false }
                if ($entry.Row) {
                    if ($entry.Row.Style -eq $script:styleUninstRow) {
                        $entry.Row.ClearValue([System.Windows.Controls.Border]::BackgroundProperty)
                    } else {
                        $entry.Row.Background = $script:brushUninstRowBg
                    }
                }
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

function Get-UninstallerAppQueueKey {
    param($App)
    if (-not $App) { return "" }
    if ($App.PSObject.Properties["RawRegPath"] -and -not [string]::IsNullOrWhiteSpace($App.RawRegPath)) {
        return "REG:" + [string]$App.RawRegPath
    }
    if ($App.PSObject.Properties["Id"] -and -not [string]::IsNullOrWhiteSpace($App.Id)) {
        return "ID:" + [string]$App.Id + "|" + [string]$App.DisplayName
    }
    return "NAME:" + [string]$App.DisplayName + "|" + [string]$App.InstallLocation
}

function Update-UninstallQueueUiState {
    if ($script:isWindowClosing) { return }
    if ($borderQueueBadge -and $txtQueueBadge) {
        if ($script:isUninstallingQueue) {
            $borderQueueBadge.Visibility = [System.Windows.Visibility]::Visible
            if ($script:uninstallQueue.Count -gt 0) {
                $txtQueueBadge.Text = "Hàng đợi: +$($script:uninstallQueue.Count)"
            } else {
                $txtQueueBadge.Text = "Đang gỡ..."
            }
        } else {
            $borderQueueBadge.Visibility = [System.Windows.Visibility]::Collapsed
            $txtQueueBadge.Text = ""
        }
    }
    if ($btnCancelAction) {
        if ($script:isUninstallingQueue -or $script:isActionRunning) {
            $btnCancelAction.Visibility = [System.Windows.Visibility]::Visible
        } else {
            $btnCancelAction.Visibility = [System.Windows.Visibility]::Collapsed
            $btnCancelAction.IsEnabled = $true
            $btnCancelAction.Content = "Dừng tác vụ"
        }
    }
}

if ($btnCancelAction) {
    $btnCancelAction.Add_Click({
        $script:cancelRequested = $true
        $btnCancelAction.IsEnabled = $false
        $btnCancelAction.Content = "Đang dừng..."
        if ($script:uninstallQueue) { $script:uninstallQueue.Clear() }
        if ($script:uninstallQueuedKeys) { $script:uninstallQueuedKeys.Clear() }
        if ($txtStatus) { $txtStatus.Text = "Đang dừng tác vụ theo yêu cầu..." }
        Log-Text "[STOP] Đã nhận yêu cầu dừng tác vụ & xóa hàng đợi!"
        try { Stop-ActiveChildProcess } catch {}
        try { Stop-ActiveWaitFrames } catch {}
    })
}

function Add-ItemsToUninstallQueue {
    param(
        [object[]]$Items,
        [bool]$SkipVendor = $false,
        [bool]$ForceStop = $false,
        [bool]$AutoSilent = $true
    )
    $added = 0
    $addedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($it in $Items) {
        if (-not $it) { continue }
        $k = Get-UninstallerAppQueueKey $it
        if ([string]::IsNullOrWhiteSpace($k) -or $script:uninstallQueuedKeys.Contains($k)) { continue }
        [void]$script:uninstallQueuedKeys.Add($k)
        [void]$addedKeys.Add($k)
        $script:uninstallQueue.Add([PSCustomObject]@{
            App        = $it
            SkipVendor = $SkipVendor
            ForceStop  = $ForceStop
            AutoSilent = $AutoSilent
            Key        = $k
        })
        $added++
    }
    if ($added -gt 0) {
        if ($script:uninstallerVirtualView) {
            $script:uninstallerVirtualView.MarkQueuedByKeys($addedKeys)
        } else {
            $script:suppressUninstallerSelectionCount = $true
            try {
                foreach ($entry in $script:uninstallerRowEntries) {
                    $rk = Get-UninstallerAppQueueKey $entry.App
                    if ($addedKeys.Contains($rk)) {
                        $entry.IsSelected = $false
                        $entry.IsQueued = $true
                        if ($entry.CheckBox) { $entry.CheckBox.IsChecked = $false }
                        if ($entry.Row) { $entry.Row.Opacity = 0.52 }
                    }
                }
            } finally {
                $script:suppressUninstallerSelectionCount = $false
            }
            Update-UninstallerSelectionCount
        }
    }
    Update-UninstallQueueUiState
    return $added
}

function Start-UninstallQueueExecution {
    $script:isUninstallingQueue = $true
    $script:cancelRequested = $false
    if ($btnCancelAction) {
        $btnCancelAction.Content = "Dừng tác vụ"
        $btnCancelAction.IsEnabled = $true
        $btnCancelAction.Visibility = [System.Windows.Visibility]::Visible
    }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    Update-UninstallQueueUiState

    $collectedLeftovers = [System.Collections.Generic.List[object]]::new()
    $completedApps = 0
    try {
        while ($script:uninstallQueue.Count -gt 0 -and -not $script:isWindowClosing -and -not $script:cancelRequested) {
            $qItem = $script:uninstallQueue[0]
            $script:uninstallQueue.RemoveAt(0)
            $totalCurrent = $completedApps + 1 + $script:uninstallQueue.Count
            if ($txtStatus) {
                $txtStatus.Text = "[$($completedApps + 1)/$totalCurrent] Đang gỡ: $($qItem.App.DisplayName)..."
            }
            Update-UninstallQueueUiState

            if (Get-Command "Invoke-DeepAppUninstall" -ErrorAction SilentlyContinue) {
                Invoke-DeepAppUninstall `
                    -AppEntry $qItem.App `
                    -OwnerWindow $window `
                    -SkipVendorUninstaller:$qItem.SkipVendor `
                    -ForceStopAndDelete:$qItem.ForceStop `
                    -AutoSilent:$qItem.AutoSilent `
                    -AllInstalledApps $script:cachedUninstallerApps `
                    -DeferLeftoverDialog `
                    -CollectedLeftoversOut $collectedLeftovers `
                    -AllowCancel
            }

            if ($script:isWindowClosing -or $script:cancelRequested) { break }
            $completedApps++
            $removedAnyRow = $false
            if ($script:uninstallerVirtualView) {
                $removedAnyRow = [bool]$script:uninstallerVirtualView.MarkRemovedByKey($qItem.Key)
            } else {
                foreach ($entry in $script:uninstallerRowEntries) {
                    if ((Get-UninstallerAppQueueKey $entry.App) -eq $qItem.Key) {
                        $entry.IsRemoved = $true
                        $entry.IsSelected = $false
                        $entry.IsQueued = $false
                        if ($entry.CheckBox) { $entry.CheckBox.IsChecked = $false }
                        if ($entry.Row) { $entry.Row.Visibility = [System.Windows.Visibility]::Collapsed }
                        $removedAnyRow = $true
                    }
                }
            }
            if ($removedAnyRow) { Apply-UninstallerFilter } else { Update-UninstallerSelectionCount }
        }

        if (-not $script:isWindowClosing -and -not $script:cancelRequested -and $collectedLeftovers.Count -gt 0) {
            $dedupLeftovers = [System.Collections.Generic.List[object]]::new()
            $seenLo = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($lo in $collectedLeftovers) {
                if (-not $lo) { continue }
                $dKey = if ($lo.RegistryValueName) { "$($lo.Path)->$($lo.RegistryValueName)" } else { [string]$lo.Path }
                if ($seenLo.Add($dKey)) { $dedupLeftovers.Add($lo) }
            }
            if ($dedupLeftovers.Count -gt 0 -and (Get-Command "Show-LeftoverReviewDialog" -ErrorAction SilentlyContinue)) {
                Log-Text "[*] Tổng hợp $($dedupLeftovers.Count) mục rác / Registry còn sót sau khi gỡ $completedApps ứng dụng."
                if ($txtStatus) { $txtStatus.Text = "Đang chờ xác nhận dọn $($dedupLeftovers.Count) mục rác tồn dư..." }
                $dialogTitle = if ($completedApps -gt 1) { "Dọn rác tồn dư sau khi gỡ ($completedApps ứng dụng)" } else { "Dọn rác tồn dư sau khi gỡ" }
                $res = Show-LeftoverReviewDialog -OwnerWindow $window -Items @($dedupLeftovers) -Title $dialogTitle -ForceStopByDefault:$true
                if ($res.Confirmed) {
                    $freedMb = [math]::Round($res.FreedBytes / 1MB, 2)
                    Log-Text "[OK] Đã dọn sạch $($res.RemovedCount) mục tồn dư (~$freedMb MB)."
                }
            }
        }
    } finally {
        $wasCanceled = [bool]$script:cancelRequested
        $script:isUninstallingQueue = $false
        $script:uninstallQueue.Clear()
        $script:uninstallQueuedKeys.Clear()
        if ($script:uninstallerVirtualView) {
            $script:uninstallerVirtualView.ClearAllQueued()
        } else {
            foreach ($entry in $script:uninstallerRowEntries) {
                $entry.IsQueued = $false
                if ($entry.Row -and -not $entry.IsRemoved) {
                    $entry.Row.Opacity = 1.0
                }
            }
        }
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        Update-UninstallQueueUiState
        if ($txtStatus -and -not $script:isWindowClosing) {
            $txtStatus.Text = if ($wasCanceled) { "Đã dừng hàng đợi gỡ ($completedApps đã xong)" } else { "Gỡ cài đặt hoàn tất ($completedApps ứng dụng)!" }
        }
    }

    if (-not $script:isWindowClosing -and $completedApps -gt 0) {
        Update-UninstallerList -Force
    }
}

if ($btnDeepUninstall) {
    $btnDeepUninstall.Add_Click({
        $selectedItems = @($script:uninstallerRowEntries | Where-Object { -not $_.IsRemoved -and ($_.IsSelected -or ($_.CheckBox -and $_.CheckBox.IsChecked -eq $true)) } | ForEach-Object { $_.App })
        if ($selectedItems.Count -eq 0 -or $script:isWindowClosing) { return }

        if ($script:isUninstallingQueue) {
            $newItems = @($selectedItems | Where-Object { -not $script:uninstallQueuedKeys.Contains((Get-UninstallerAppQueueKey $_)) })
            if ($newItems.Count -eq 0) {
                Log-Text "[WARN] Các ứng dụng đã chọn hiện đã nằm trong hàng đợi gỡ cài đặt."
                return
            }
            $skipVendorAppend = ($null -ne $cbSkipVendorUninst -and $cbSkipVendorUninst.IsChecked -eq $true)
            $appLinesAppend = @($newItems | ForEach-Object {
                $vPart = if (-not [string]::IsNullOrWhiteSpace($_.DisplayVersion)) { " ($($_.DisplayVersion))" } else { "" }
                "• $($_.DisplayName)$vPart"
            })
            $ansAppend = Show-OwnedMessageBox `
                -Text "Hàng đợi gỡ cài đặt đang chạy. Thêm $($newItems.Count) ứng dụng mới vào hàng đợi (chạy nối tiếp và gộp bảng dọn rác cuối lượt)?" `
                -Caption "Thêm vào Hàng đợi Gỡ" `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Question) `
                -PrimaryText "Thêm vào hàng đợi ($($newItems.Count))" `
                -SecondaryText "Bỏ qua" `
                -DetailItems $appLinesAppend
            if ($ansAppend -eq [System.Windows.Forms.DialogResult]::Yes -and $script:isUninstallingQueue -and -not $script:isWindowClosing) {
                $nAdded = Add-ItemsToUninstallQueue -Items $newItems -SkipVendor:$skipVendorAppend -ForceStop:$false -AutoSilent:(if ($skipVendorAppend) { $false } else { [bool]$script:autoSilentUninstall })
                if ($nAdded -gt 0) {
                    Log-Text "[QUEUE] Đã thêm +$nAdded ứng dụng vào hàng đợi gỡ cài đặt."
                }
            }
            return
        }

        Invoke-GuardedAction "Gỡ cài đặt ứng dụng" -DeferExpand {
            $selectedNow = @($script:uninstallerRowEntries | Where-Object { -not $_.IsRemoved -and ($_.IsSelected -or ($_.CheckBox -and $_.CheckBox.IsChecked -eq $true)) } | ForEach-Object { $_.App })
            if ($selectedNow.Count -eq 0 -or $script:isWindowClosing) { return }

            $skipVendor = ($null -ne $cbSkipVendorUninst -and $cbSkipVendorUninst.IsChecked -eq $true)
            $appLines = @($selectedNow | ForEach-Object {
                $vPart = if (-not [string]::IsNullOrWhiteSpace($_.DisplayVersion)) { " ($($_.DisplayVersion))" } else { "" }
                "• $($_.DisplayName)$vPart"
            })

            if ($skipVendor) {
                $confirm = Show-OwnedMessageBox `
                    -Text "Bạn có chắc chắn muốn gỡ cài đặt $($selectedNow.Count) ứng dụng đã chọn?" `
                    -Caption "Xác nhận Gỡ cài đặt" `
                    -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) `
                    -PrimaryText "Gỡ ngay ($($selectedNow.Count))" `
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
                    -Text "Bạn có chắc chắn muốn gỡ cài đặt $($selectedNow.Count) ứng dụng đã chọn?" `
                    -Caption "Xác nhận Gỡ cài đặt" `
                    -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) `
                    -PrimaryText "Gỡ ngay ($($selectedNow.Count))" `
                    -SecondaryText "Hủy bỏ" `
                    -DetailItems $appLines `
                    -ToggleState $toggleState
                if (-not $script:isWindowClosing) {
                    $script:autoSilentUninstall = [bool]$toggleState.Checked
                }
                $useAutoSilent = [bool]$toggleState.Checked
            }

            if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes -or $script:isWindowClosing) { return }

            [void](Add-ItemsToUninstallQueue -Items $selectedNow -SkipVendor:$skipVendor -ForceStop:$false -AutoSilent:$useAutoSilent)
            Start-UninstallQueueExecution
        }
    })
}

if ($btnForceStopUninstall) {
    $btnForceStopUninstall.Add_Click({
        $selectedItems = @($script:uninstallerRowEntries | Where-Object { -not $_.IsRemoved -and ($_.IsSelected -or ($_.CheckBox -and $_.CheckBox.IsChecked -eq $true)) } | ForEach-Object { $_.App })
        if ($selectedItems.Count -eq 0 -or $script:isWindowClosing) { return }

        if ($script:isUninstallingQueue) {
            $newItems = @($selectedItems | Where-Object { -not $script:uninstallQueuedKeys.Contains((Get-UninstallerAppQueueKey $_)) })
            if ($newItems.Count -eq 0) {
                Log-Text "[WARN] Các ứng dụng đã chọn hiện đã nằm trong hàng đợi gỡ cài đặt."
                return
            }
            $appLinesAppend = @($newItems | ForEach-Object {
                $vPart = if (-not [string]::IsNullOrWhiteSpace($_.DisplayVersion)) { " ($($_.DisplayVersion))" } else { "" }
                "• $($_.DisplayName)$vPart"
            })
            $ansAppend = Show-OwnedMessageBox `
                -Text "Hàng đợi đang chạy. Thêm $($newItems.Count) ứng dụng vào hàng đợi Buộc dừng & Xóa trực tiếp?" `
                -Caption "Thêm Buộc dừng & Xóa vào Hàng đợi" `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) `
                -PrimaryText "Thêm vào hàng đợi ($($newItems.Count))" `
                -SecondaryText "Bỏ qua" `
                -DetailItems $appLinesAppend `
                -ModeBadgeText "Chế độ Buộc dừng & Xóa nối tiếp trong hàng đợi" `
                -ModeBadgeKind "Danger"
            if ($ansAppend -eq [System.Windows.Forms.DialogResult]::Yes -and $script:isUninstallingQueue -and -not $script:isWindowClosing) {
                $nAdded = Add-ItemsToUninstallQueue -Items $newItems -SkipVendor:$true -ForceStop:$true -AutoSilent:$false
                if ($nAdded -gt 0) {
                    Log-Text "[QUEUE] Đã thêm +$nAdded ứng dụng (Buộc dừng & Xóa) vào hàng đợi."
                }
            }
            return
        }

        Invoke-GuardedAction "Buộc dừng & Xóa ứng dụng" -DeferExpand {
            $selectedNow = @($script:uninstallerRowEntries | Where-Object { -not $_.IsRemoved -and ($_.IsSelected -or ($_.CheckBox -and $_.CheckBox.IsChecked -eq $true)) } | ForEach-Object { $_.App })
            if ($selectedNow.Count -eq 0 -or $script:isWindowClosing) { return }

            $appLines = @($selectedNow | ForEach-Object {
                $vPart = if (-not [string]::IsNullOrWhiteSpace($_.DisplayVersion)) { " ($($_.DisplayVersion))" } else { "" }
                "• $($_.DisplayName)$vPart"
            })
            $confirm = Show-OwnedMessageBox `
                -Text "Buộc dừng toàn bộ tiến trình/dịch vụ đang giữ tệp của $($selectedNow.Count) ứng dụng đã chọn và xóa trực tiếp không qua trình gỡ hãng?" `
                -Caption "Xác nhận Buộc dừng & Xóa" `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) `
                -PrimaryText "Buộc dừng & Xóa ($($selectedNow.Count))" `
                -SecondaryText "Hủy bỏ" `
                -DetailItems $appLines `
                -ModeBadgeText "Restart Manager + NtSuspend + Kill Tree + MoveFileEx (bỏ qua trình gỡ hãng)" `
                -ModeBadgeKind "Danger"
            if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes -or $script:isWindowClosing) { return }

            [void](Add-ItemsToUninstallQueue -Items $selectedNow -SkipVendor:$true -ForceStop:$true -AutoSilent:$false)
            Start-UninstallQueueExecution
        }
    })
}

if ($btnScanOrphans) {
    $btnScanOrphans.Add_Click({
        Invoke-GuardedAction "Quét rác tồn dư & App xóa sai cách" -DeferExpand {
            if ($script:isWindowClosing) { return }
            if ($txtStatus) { $txtStatus.Text = "Đang quét rác tồn dư & driver Ring-0 mồ côi..." }
            if ($progressBar) { $progressBar.IsIndeterminate = $true }
            try {
                if (Get-Command "Find-SystemOrphanLeftovers" -ErrorAction SilentlyContinue) {
                    $orphans = @(Find-SystemOrphanLeftovers -InstalledApps $script:cachedUninstallerApps -CatalogApps $AppCatalog)
                    if ($progressBar) { $progressBar.IsIndeterminate = $false }
                    if ($script:isWindowClosing) { return }
                    if ($orphans.Count -eq 0) {
                        if ($txtStatus) { $txtStatus.Text = "Không phát hiện rác tồn dư" }
                        Show-OwnedMessageBox `
                            -Text "Không phát hiện tệp tin rác hoặc ứng dụng nào bị xóa sai cách trên hệ thống!" `
                            -Caption "Quét Rác Tồn Dư" `
                            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                            -Icon ([System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                    } else {
                        if ($txtStatus) { $txtStatus.Text = "Phát hiện $($orphans.Count) mục rác tồn dư" }
                        if (-not $script:isWindowClosing -and (Get-Command "Show-LeftoverReviewDialog" -ErrorAction SilentlyContinue)) {
                            Show-LeftoverReviewDialog -OwnerWindow $window -Items $orphans -Title "Quét Rác Tồn Dư & App Xóa Sai Cách"
                        }
                        if (-not $script:isWindowClosing) {
                            Update-UninstallerList -Force
                        }
                    }
                }
            } finally {
                if ($progressBar) { $progressBar.IsIndeterminate = $false }
                if ($txtStatus -and -not $script:isWindowClosing -and $txtStatus.Text -like "Đang quét rác*") {
                    $txtStatus.Text = "Sẵn sàng"
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

$script:colHeights = @(0, 0, 0)

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

$cardsMasonrySection  = $window.FindName("CardsMasonrySection")
$cardsMasonryHost     = $window.FindName("CardsMasonryHost")
$cardsColDef2         = $window.FindName("CardsColDef2")
$cardsCol2Panel       = $window.FindName("CardsCol2")
$groupFilterBanner    = $window.FindName("GroupFilterBanner")
$txtGroupFilterTitle  = $window.FindName("txtGroupFilterTitle")
$txtGroupFilterMeta   = $window.FindName("txtGroupFilterMeta")
$btnGroupBack         = $window.FindName("btnGroupBack")
$singleCategoryHost   = $window.FindName("SingleCategoryHost")
$btnSingleCatParent   = $window.FindName("btnSingleCatParent")
$txtSingleCatParent   = $window.FindName("txtSingleCatParent")
$iconSingleCatCrumb   = $window.FindName("iconSingleCatCrumb")
$txtSingleCatTitle    = $window.FindName("txtSingleCatTitle")
$txtSingleCatCount    = $window.FindName("txtSingleCatCount")
$btnSingleCatBack     = $window.FindName("btnSingleCatBack")
$categorySidebarTop   = $window.FindName("CategorySidebarTop")
$categorySidebarPanel = $window.FindName("CategorySidebarPanel")
$txtCategorySidebarMeta = $window.FindName("txtCategorySidebarMeta")
$script:singleCatCols = @(
    $window.FindName("SingleCatCol0"),
    $window.FindName("SingleCatCol1"),
    $window.FindName("SingleCatCol2")
)
$cardCols = @(
    $window.FindName("CardsCol0"),
    $window.FindName("CardsCol1"),
    $cardsCol2Panel
) | Where-Object { $null -ne $_ }

$script:remoteBmpCache = [System.Collections.Generic.Dictionary[string, System.Windows.Media.Imaging.BitmapImage]]::new([System.StringComparer]::OrdinalIgnoreCase)

$glCol0             = [System.Windows.GridLength]::new(20, [System.Windows.GridUnitType]::Pixel)
$glCol1             = [System.Windows.GridLength]::new(23, [System.Windows.GridUnitType]::Pixel)
$glCol2             = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
$glCol3             = [System.Windows.GridLength]::new(22, [System.Windows.GridUnitType]::Pixel)
$glAuto             = [System.Windows.GridLength]::Auto
$glZero             = [System.Windows.GridLength]::new(0, [System.Windows.GridUnitType]::Pixel)
$glChevron          = [System.Windows.GridLength]::new(16, [System.Windows.GridUnitType]::Pixel)
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

$pipeCatalogType = "DuckUtil.UiAssetPipeline" -as [type]
$script:hasFastCatalogRowBuilder = ($null -ne $pipeCatalogType) -and ($null -ne $pipeCatalogType.GetMethod("CreateCatalogRow"))

if ($cardsContainer -and $script:hasFastCatalogRowBuilder) {
    $cardsContainer.AddHandler(
        [System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent,
        [System.Windows.RoutedEventHandler]{ Update-SelectionCount }
    )
    $cardsContainer.AddHandler(
        [System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent,
        [System.Windows.RoutedEventHandler]{ Update-SelectionCount }
    )
    $cardsContainer.AddHandler(
        [System.Windows.UIElement]::MouseLeftButtonUpEvent,
        [System.Windows.Input.MouseButtonEventHandler]{
            param($sender, $e)
            if ($e.Handled -or $script:isActionRunning -or $script:isWindowClosing) { return }
            $node = $e.OriginalSource
            while ($node -ne $null -and $node -ne $sender) {
                if ($node -is [System.Windows.Controls.Primitives.ToggleButton]) { return }
                if ($node -is [System.Windows.Controls.Border]) {
                    if ($node.Tag -is [string] -and -not [string]::IsNullOrWhiteSpace($node.Tag)) {
                        $e.Handled = $true
                        $domain = [string]$node.Tag
                        $targetUrl = if ($domain.StartsWith("http")) { $domain } else { "https://$domain" }
                        try {
                            Start-Process $targetUrl
                        } catch {
                            Log-Text "[!] Không thể mở trang web: $targetUrl"
                        }
                        return
                    }
                    if ($node.Tag -is [hashtable] -and $node.Tag.ContainsKey('CheckBox') -and $node.Style -eq $script:styleAppRow) {
                        $targetCb = $node.Tag['CheckBox']
                        if ($targetCb) { $targetCb.IsChecked = -not $targetCb.IsChecked }
                        return
                    }
                }
                if ($node -is [System.Windows.Controls.Grid] -and $node.Tag -is [hashtable] -and $node.Tag.ContainsKey('OpenCategory')) {
                    $e.Handled = $true
                    Set-ActiveCatalogCategory ([string]$node.Tag['OpenCategory'])
                    return
                }
                if ($node -is [System.Windows.Media.Visual]) {
                    $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
                } else { break }
            }
        }
    )
}

if ($appsScrollViewer) {
    $appsScrollViewer.Add_ScrollChanged({
        Sync-Tab0ViewportAssets
    })
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
    if (-not $script:hasFastCatalogRowBuilder) {
        $cardBorder.CacheMode = $script:sharedCardCache
    }

    $cardStack = [System.Windows.Controls.StackPanel]::new()
    $appsInCat = $appsByCategory[$cat]

    $headerGrid = [System.Windows.Controls.Grid]::new()
    $headerGrid.Margin = $marginHeaderGrid
    $headerGrid.Background = $script:brushTransparent
    $headerGrid.Cursor = [System.Windows.Input.Cursors]::Hand
    $headerGrid.Tag = @{ OpenCategory = [string]$cat }
    $headerGrid.ToolTip = "Bấm để mở riêng danh mục '$cat'"

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

    $rowsStack = [System.Windows.Controls.StackPanel]::new()
    $cardRowsList = [System.Collections.Generic.List[object]]::new()

    [void]$cardStack.Children.Add($headerGrid)
    [void]$cardStack.Children.Add($separator)
    [void]$cardStack.Children.Add($rowsStack)

    $cardEstimatedHeight = 56 + ($appsInCat.Count * 29)
    $targetColIndex = 0
    $minHeight = $script:colHeights[0]
    for ($i = 1; $i -lt $cardCols.Count; $i++) {
        if ($script:colHeights[$i] -lt $minHeight) {
            $minHeight = $script:colHeights[$i]
            $targetColIndex = $i
        }
    }
    $cardEstTop = [double]$script:colHeights[$targetColIndex]
    $cardEstBot = $cardEstTop + $cardEstimatedHeight
    $targetColPanel = if ($cardCols.Count -gt 0 -and $cardCols[$targetColIndex]) { $cardCols[$targetColIndex] } else { $cardsContainer }

    $cardDesc = @{
        Category      = [string]$cat
        Card          = $cardBorder
        CardStack     = $cardStack
        RowsStack     = $rowsStack
        Rows          = $cardRowsList
        ColPanel      = $targetColPanel
        AllColPanel   = $targetColPanel
        EstTop        = $cardEstTop
        AllEstTop     = $cardEstTop
        EstBottom     = $cardEstBot
        AllEstBottom  = $cardEstBot
        EstHeight     = [double]$cardEstimatedHeight
        Attached      = $false
        IconsEnqueued = $false
        TotalIcons    = 0
        LoadedIcons   = 0
        CacheEnabled  = (-not $script:hasFastCatalogRowBuilder)
        IconIndices   = [System.Collections.Generic.List[int]]::new()
    }

    if ($script:hasFastCatalogRowBuilder) {
        foreach ($app in $appsInCat) {
            $useLightBadge = ($app.IconBg -eq "light")
            $fallbackIconUrl = if (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
                "https://icons.duckduckgo.com/ip3/$($app.Domain).ico"
            } else { $null }
            $remoteIconTarget = if (-not [string]::IsNullOrWhiteSpace($app.IconUrl)) {
                $app.IconUrl
            } elseif (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
                "https://www.google.com/s2/favicons?domain=$($app.Domain)&sz=128"
            } else { $null }
            if ($remoteIconTarget -and $fallbackIconUrl -and $remoteIconTarget -eq $fallbackIconUrl) {
                $fallbackIconUrl = $null
            }
            $iconCacheKey = if ($remoteIconTarget) { $remoteIconTarget } else { "$($app.ID)" }
            $iconFileName = "$($app.ID).png"
            $localIconPath = [System.IO.Path]::Combine($iconsCacheDir, $iconFileName)
            $cachedBmp = $null
            $hasCachedInMem = $false
            if ($script:remoteBmpCache -and $script:remoteBmpCache.TryGetValue($iconCacheKey, [ref]$cachedBmp) -and $cachedBmp -and $cachedBmp.PixelWidth -gt 0) {
                $hasCachedInMem = $true
            } else {
                $cachedBmp = [DuckUtil.UiAssetPipeline]::TryGetCachedRemoteIcon($iconCacheKey)
                if ($cachedBmp -and $cachedBmp.PixelWidth -gt 0) {
                    $hasCachedInMem = $true
                    if ($script:remoteBmpCache) { $script:remoteBmpCache[$iconCacheKey] = $cachedBmp }
                }
            }
            $hasLocalCachedFile = $hasCachedInMem -or ($script:remoteExistingFiles -and $script:remoteExistingFiles.Contains($iconFileName))
            $glyphTxt = if ($hasLocalCachedFile) { $script:defaultFallbackGlyph } else { Get-AppFallbackGlyph -AppName $app.Name -Category $cat }
            $idnPrefix = if ($app.IDn) { "[#$($app.IDn)] " } else { "" }
            $rowTip = "$idnPrefix$($app.Name)`nTrạng thái: Chưa cài đặt`nID: $($app.ID)"
            $targetPageUrl = if (-not [string]::IsNullOrWhiteSpace($app.Url)) {
                $app.Url
            } elseif (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
                if ($app.Domain.StartsWith("http")) { $app.Domain } else { "https://$($app.Domain)" }
            } else { "" }

            $vis = [DuckUtil.UiAssetPipeline]::CreateCatalogRow(
                [string]$app.Name,
                [string]$rowTip,
                [string]$targetPageUrl,
                [string]$glyphTxt,
                [bool]$useLightBadge,
                $script:styleAppRow,
                $script:styleLinkBtn,
                $script:fontSegoeUI,
                $script:fontSegoeEmoji,
                $script:brushTextWhite,
                $script:brushIconBadgeBg,
                $script:brushIconBadgeLightBg,
                $script:brushIconBadgeBorder,
                $script:brushUpdateBadgeBg,
                $script:brushUpdateBadgeBorder,
                $script:brushUpdateBadgeFg,
                $script:brushLinkBtnRowHover,
                $(if ($hasCachedInMem) { $cachedBmp } else { $null })
            )

            $rowTag = @{
                App              = $app
                Status           = "NONE"
                DetectedId       = $null
                InstalledVersion = $null
                CardBorder       = $cardBorder
                CheckBox         = $vis.CheckBox
                NameText         = $vis.NameText
                UpdateBadge      = $vis.UpdateBadge
                UpdateText       = $vis.UpdateText
                LinkBtn          = $vis.LinkBtn
                LinkIcon         = $vis.LinkIcon
            }
            $vis.RowBorder.Tag = $rowTag
            $vis.CheckBox.Tag  = $rowTag

            if (-not $hasCachedInMem -and ($remoteIconTarget -or $hasLocalCachedFile)) {
                $rIdx = $script:remoteIconRegistry.Count
                $script:remoteIconRegistry.Add(@{
                    Url          = $remoteIconTarget
                    FallbackUrl  = $fallbackIconUrl
                    CacheKey     = $iconCacheKey
                    DestPath     = $localIconPath
                    Img          = $vis.IconImg
                    Fallback     = $vis.FallbackGlyph
                    Badge        = $vis.IconBadge
                    UseLight     = $useLightBadge
                    Applied      = $false
                    CardDesc     = $cardDesc
                })
                $cardDesc.IconIndices.Add($rIdx)
                $cardDesc.TotalIcons++
            }

            $allCheckBoxes.Add($vis.CheckBox)
            [void]$rowsStack.Children.Add($vis.RowBorder)
            [void]$cardRowsList.Add($vis.RowBorder)
            $allItemBorders.Add($vis.RowBorder)
        }
    } else {
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

        $useLightBadge = ($app.IconBg -eq "light")
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
        $iconInnerGrid.Width = 20
        $iconInnerGrid.Height = 20
        $iconInnerGrid.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $iconInnerGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $fallbackIconUrl = if (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
            "https://icons.duckduckgo.com/ip3/$($app.Domain).ico"
        } else {
            $null
        }
        $remoteIconTarget = if (-not [string]::IsNullOrWhiteSpace($app.IconUrl)) {
            $app.IconUrl
        } elseif (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
            "https://www.google.com/s2/favicons?domain=$($app.Domain)&sz=128"
        } else {
            $null
        }
        if ($remoteIconTarget -and $fallbackIconUrl -and $remoteIconTarget -eq $fallbackIconUrl) {
            $fallbackIconUrl = $null
        }
        $iconCacheKey = if ($remoteIconTarget) { $remoteIconTarget } else { "$($app.ID)" }
        $iconFileName = "$($app.ID).png"
        $localIconPath = [System.IO.Path]::Combine($iconsCacheDir, $iconFileName)
        $cachedBmp = $null
        $hasCachedInMem = $false
        if ($script:remoteBmpCache -and $script:remoteBmpCache.TryGetValue($iconCacheKey, [ref]$cachedBmp) -and $cachedBmp -and $cachedBmp.PixelWidth -gt 0) {
            $hasCachedInMem = $true
        } elseif (("DuckUtil.UiAssetPipeline" -as [type]) -and $null -ne ([DuckUtil.UiAssetPipeline].GetMethod("TryGetCachedRemoteIcon"))) {
            $cachedBmp = [DuckUtil.UiAssetPipeline]::TryGetCachedRemoteIcon($iconCacheKey)
            if ($cachedBmp -and $cachedBmp.PixelWidth -gt 0) {
                $hasCachedInMem = $true
                if ($script:remoteBmpCache) { $script:remoteBmpCache[$iconCacheKey] = $cachedBmp }
            }
        }
        $hasLocalCachedFile = $hasCachedInMem -or ($script:remoteExistingFiles -and $script:remoteExistingFiles.Contains($iconFileName))

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
            $img.Source = $cachedBmp
            $fallbackGlyph.Visibility = [System.Windows.Visibility]::Collapsed
            $img.Visibility = [System.Windows.Visibility]::Visible
            if ($useLightBadge) { $iconBadge.Background = $script:brushIconBadgeLightBg }
        } elseif ($remoteIconTarget -or $hasLocalCachedFile) {
            $script:pendingIconSaves.Add(@{
                Url          = $remoteIconTarget
                FallbackUrl  = $fallbackIconUrl
                CacheKey     = $iconCacheKey
                DestPath     = $localIconPath
                DownloadInfo = $null
                Img          = $img
                Fallback     = $fallbackGlyph
                Badge        = $iconBadge
                UseLight     = $useLightBadge
                Applied      = $false
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
        $rowBorder.ToolTip = "$idnPrefix$($app.Name)`nTrạng thái: Chưa cài đặt`nID: $($app.ID)"
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
        $rowsStack.Children.Add($rowBorder) | Out-Null
        [void]$cardRowsList.Add($rowBorder)
        $allItemBorders.Add($rowBorder)
    }
    }

    $cardBorder.Child = $cardStack

    if (-not $script:hasFastCatalogRowBuilder -or $cardEstTop -lt 950.0) {
        if ($targetColPanel) {
            $targetColPanel.Children.Add($cardBorder) | Out-Null
        }
        $cardDesc.Attached = $true
    }
    [void]$script:cardDescriptors.Add($cardDesc)
    $script:cardDescByCategory[[string]$cat] = $cardDesc

    $script:colHeights[$targetColIndex] += $cardEstimatedHeight
}

$script:sidebarCatButtons       = [System.Collections.Generic.Dictionary[string, hashtable]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:catalogGroupByKey       = [System.Collections.Generic.Dictionary[string, hashtable]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:catalogGroupsOrdered    = [System.Collections.Generic.List[hashtable]]::new()
$script:catToGroupKey           = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:brushSidebarHoverBg     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x13, 0x1B, 0x2B)); $script:brushSidebarHoverBg.Freeze()
$script:brushSidebarHoverBorder = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x2B, 0x3A, 0x52)); $script:brushSidebarHoverBorder.Freeze()
$script:brushSidebarActiveBg    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x11, 0x22, 0x38)); $script:brushSidebarActiveBg.Freeze()
$script:brushSidebarActiveBdr   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushSidebarActiveBdr.Freeze()
$script:brushSidebarAncBg       = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x0E, 0x19, 0x2A)); $script:brushSidebarAncBg.Freeze()
$script:brushSidebarAncBdr      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x2B, 0x5B, 0x84)); $script:brushSidebarAncBdr.Freeze()
$script:brushSidebarAncFg       = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x7D, 0xD3, 0xFC)); $script:brushSidebarAncFg.Freeze()
$script:brushSidebarFg          = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x94, 0xA3, 0xB8)); $script:brushSidebarFg.Freeze()
$script:brushSidebarParentFg    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xCB, 0xD5, 0xE1)); $script:brushSidebarParentFg.Freeze()
$script:brushSidebarActiveFg    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushSidebarActiveFg.Freeze()
$script:brushSidebarCntBg       = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x16, 0x20, 0x32)); $script:brushSidebarCntBg.Freeze()
$script:brushSidebarCntActiveBg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x0C, 0x34, 0x54)); $script:brushSidebarCntActiveBg.Freeze()
$script:brushSidebarCntFg       = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x64, 0x74, 0x8B)); $script:brushSidebarCntFg.Freeze()
$script:brushSidebarGuide       = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x24, 0x32, 0x47)); $script:brushSidebarGuide.Freeze()
$script:chevronGeom             = [System.Windows.Media.Geometry]::Parse("M 0,0 L 4,3.5 L 0,7"); if ($script:chevronGeom) { $script:chevronGeom.Freeze() }

$script:styleSidebarCatBtn = New-Object System.Windows.Style([System.Windows.Controls.Border])
$script:styleSidebarCatBtn.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $script:brushTransparent)))
$script:styleSidebarCatBtn.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $script:brushTransparent)))
$trigSideHover = New-Object System.Windows.Trigger
$trigSideHover.Property = [System.Windows.UIElement]::IsMouseOverProperty
$trigSideHover.Value = $true
$trigSideHover.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $script:brushSidebarHoverBg)))
$trigSideHover.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $script:brushSidebarHoverBorder)))
$script:styleSidebarCatBtn.Triggers.Add($trigSideHover)
$script:styleSidebarCatBtn.Seal()

$script:catalogGroupDefs = @(
    @{ Key = "__GROUP__:Internet"; Title = "Internet & Kết nối";  Categories = @("Web Browsers", "Communication", "Remote Desktop", "Download Managers", "File Transfer & Cloud") },
    @{ Key = "__GROUP__:DevAI";    Title = "AI & Lập trình";      Categories = @("Antigravity", "AI & Assistants", "JetBrains", "Development", "Database & DevOps") },
    @{ Key = "__GROUP__:Runtimes"; Title = "Thư viện & Runtimes"; Categories = @(".NET Runtimes", "Java Runtimes", "C++ & System Runtimes") },
    @{ Key = "__GROUP__:System";   Title = "Hệ thống & Bảo mật";  Categories = @("System Utilities", "Optimization & Tuning", "Hardware & Monitoring", "Benchmark & Stress Test", "Security & Network") },
    @{ Key = "__GROUP__:Media";    Title = "Media & Văn phòng";   Categories = @("Audio & Video", "Graphics & Design", "Documents & Office") },
    @{ Key = "__GROUP__:Gaming";   Title = "Gaming & Modding";    Categories = @("Game Launchers", "Minecraft & Modding") }
)

function New-SidebarNavRow {
    param(
        [string]$Key,
        [string]$Label,
        [int]$Count,
        [ValidateSet("Root", "Group", "Child")]
        [string]$Role = "Child"
    )
    $isParentOrRoot = ($Role -ne "Child")
    $b = [System.Windows.Controls.Border]::new()
    $b.Height = if ($Role -eq "Child") { 25 } else { 29 }
    $b.Style = $script:styleSidebarCatBtn
    $b.BorderThickness = [System.Windows.Thickness]::new(2, 0, 0, 0)
    $b.CornerRadius = $cornerFour
    $b.Padding = if ($Role -eq "Group") {
        [System.Windows.Thickness]::new(4, 0, 6, 0)
    } elseif ($Role -eq "Root") {
        [System.Windows.Thickness]::new(8, 0, 6, 0)
    } else {
        [System.Windows.Thickness]::new(7, 0, 6, 0)
    }
    $b.Margin = [System.Windows.Thickness]::new(0, 1, 0, 1)
    $b.Cursor = [System.Windows.Input.Cursors]::Hand

    $g = [System.Windows.Controls.Grid]::new()
    $g.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $chevPath = $null
    $chevWrap = $null
    $titleColIdx = 0
    $countColIdx = 1

    if ($Role -eq "Group") {
        $cChev = [System.Windows.Controls.ColumnDefinition]::new(); $cChev.Width = $glChevron
        $cTitle = [System.Windows.Controls.ColumnDefinition]::new(); $cTitle.Width = $glCol2
        $cCnt = [System.Windows.Controls.ColumnDefinition]::new(); $cCnt.Width = $glAuto
        [void]$g.ColumnDefinitions.Add($cChev)
        [void]$g.ColumnDefinitions.Add($cTitle)
        [void]$g.ColumnDefinitions.Add($cCnt)
        $titleColIdx = 1
        $countColIdx = 2

        $chevWrap = [System.Windows.Controls.Border]::new()
        $chevWrap.Background = $script:brushTransparent
        $chevWrap.Height = 26
        $chevWrap.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $chevWrap.Tag = @{ ToggleGroup = $Key }
        $chevWrap.ToolTip = "Mở rộng / thu gọn nhóm"

        $chevPath = [System.Windows.Shapes.Path]::new()
        $chevPath.Data = $script:chevronGeom
        $chevPath.Stroke = $script:brushSidebarCntFg
        $chevPath.StrokeThickness = 1.5
        $chevPath.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
        $chevPath.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
        $chevPath.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $chevPath.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $chevPath.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.5)
        $chevPath.RenderTransform = [System.Windows.Media.RotateTransform]::new(0)
        $chevWrap.Child = $chevPath
        [System.Windows.Controls.Grid]::SetColumn($chevWrap, 0)
        [void]$g.Children.Add($chevWrap)
    } else {
        $cTitle = [System.Windows.Controls.ColumnDefinition]::new(); $cTitle.Width = $glCol2
        $cCnt = [System.Windows.Controls.ColumnDefinition]::new(); $cCnt.Width = $glAuto
        [void]$g.ColumnDefinitions.Add($cTitle)
        [void]$g.ColumnDefinitions.Add($cCnt)
    }

    $tb = [System.Windows.Controls.TextBlock]::new()
    $tb.Text = $Label
    $tb.FontSize = if ($Role -eq "Child") { 11.2 } else { 11.8 }
    $tb.FontWeight = if ($isParentOrRoot) { [System.Windows.FontWeights]::SemiBold } else { [System.Windows.FontWeights]::Medium }
    $tb.Foreground = if ($isParentOrRoot) { $script:brushSidebarParentFg } else { $script:brushSidebarFg }
    $tb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $tb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $tb.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
    [System.Windows.Controls.Grid]::SetColumn($tb, $titleColIdx)
    [void]$g.Children.Add($tb)

    $cntB = [System.Windows.Controls.Border]::new()
    $cntB.Background = $script:brushSidebarCntBg
    $cntB.CornerRadius = $cornerFour
    $cntB.Padding = [System.Windows.Thickness]::new(5, 1, 5, 1)
    $cntB.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $cntTb = [System.Windows.Controls.TextBlock]::new()
    $cntTb.Text = "$Count"
    $cntTb.FontSize = 9.5
    $cntTb.FontWeight = [System.Windows.FontWeights]::SemiBold
    $cntTb.Foreground = $script:brushSidebarCntFg
    $cntB.Child = $cntTb
    [System.Windows.Controls.Grid]::SetColumn($cntB, $countColIdx)
    [void]$g.Children.Add($cntB)

    $b.Child = $g
    $desc = @{
        Key            = $Key
        Role           = $Role
        Border         = $b
        TitleText      = $tb
        CountBadge     = $cntB
        CountText      = $cntTb
        Chevron        = $chevPath
        ChevronWrap    = $chevWrap
        IsParentOrRoot = $isParentOrRoot
    }
    $b.Tag = $desc
    $script:sidebarCatButtons[$Key] = $desc
    return $desc
}

function Update-SidebarVisuals {
    $activeKey = if ([string]::IsNullOrWhiteSpace($script:activeCatalogCategory)) { "__ALL__" } else { $script:activeCatalogCategory }
    $activeParentKey = ""
    if ($activeKey -ne "__ALL__" -and -not $activeKey.StartsWith("__GROUP__:")) {
        $mappedParent = $null
        if ($script:catToGroupKey.TryGetValue($activeKey, [ref]$mappedParent)) {
            $activeParentKey = $mappedParent
        }
    }

    foreach ($entry in $script:sidebarCatButtons.Values) {
        $k = $entry.Key
        if ($k -eq $activeKey) {
            $entry.Border.Background = $script:brushSidebarActiveBg
            $entry.Border.BorderBrush = $script:brushSidebarActiveBdr
            $entry.TitleText.Foreground = $script:brushSidebarActiveFg
            $entry.TitleText.FontWeight = [System.Windows.FontWeights]::SemiBold
            $entry.CountBadge.Background = $script:brushSidebarCntActiveBg
            $entry.CountText.Foreground = $script:brushSidebarActiveFg
        } elseif ($activeParentKey -and $k -eq $activeParentKey) {
            $entry.Border.Background = $script:brushSidebarAncBg
            $entry.Border.BorderBrush = $script:brushSidebarAncBdr
            $entry.TitleText.Foreground = $script:brushSidebarAncFg
            $entry.TitleText.FontWeight = [System.Windows.FontWeights]::SemiBold
            $entry.CountBadge.Background = $script:brushSidebarCntActiveBg
            $entry.CountText.Foreground = $script:brushSidebarAncFg
        } else {
            $entry.Border.ClearValue([System.Windows.Controls.Border]::BackgroundProperty)
            $entry.Border.ClearValue([System.Windows.Controls.Border]::BorderBrushProperty)
            $entry.TitleText.Foreground = if ($entry.IsParentOrRoot) { $script:brushSidebarParentFg } else { $script:brushSidebarFg }
            $entry.TitleText.FontWeight = if ($entry.IsParentOrRoot) { [System.Windows.FontWeights]::SemiBold } else { [System.Windows.FontWeights]::Medium }
            $entry.CountBadge.Background = $script:brushSidebarCntBg
            $entry.CountText.Foreground = $script:brushSidebarCntFg
        }
    }

    foreach ($grp in $script:catalogGroupsOrdered) {
        $expanded = [bool]$grp.IsExpanded
        if ($grp.ChildrenHost) {
            $grp.ChildrenHost.Visibility = if ($expanded) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        }
        $btn = $grp.BtnDesc
        if ($btn -and $btn.Chevron) {
            $rot = $btn.Chevron.RenderTransform -as [System.Windows.Media.RotateTransform]
            if ($rot) { $rot.Angle = if ($expanded) { 90 } else { 0 } }
            $isHighlighted = ($grp.Key -eq $activeKey) -or ($grp.Key -eq $activeParentKey)
            $btn.Chevron.Stroke = if ($isHighlighted -or $expanded) { $script:brushSidebarActiveFg } else { $script:brushSidebarCntFg }
        }
    }
}

function Toggle-SidebarGroupExpanded {
    param([string]$GroupKey)
    $grp = $null
    if ($GroupKey -and $script:catalogGroupByKey.TryGetValue($GroupKey, [ref]$grp)) {
        $grp.IsExpanded = -not $grp.IsExpanded
        Update-SidebarVisuals
    }
}

function Set-ActiveCatalogCategory {
    param([string]$CategoryKey)
    if ($script:isWindowClosing) { return }
    $targetKey = if ([string]::IsNullOrWhiteSpace($CategoryKey)) { "__ALL__" } else { $CategoryKey }

    $isGroupTarget = $targetKey.StartsWith("__GROUP__:")
    if ($targetKey -ne "__ALL__" -and -not $isGroupTarget -and -not $script:cardDescByCategory.ContainsKey($targetKey)) {
        $targetKey = "__ALL__"
        $isGroupTarget = $false
    } elseif ($isGroupTarget -and -not $script:catalogGroupByKey.ContainsKey($targetKey)) {
        $targetKey = "__ALL__"
        $isGroupTarget = $false
    }

    if ($targetKey -eq $script:activeCatalogCategory) {
        if ($isGroupTarget) {
            Toggle-SidebarGroupExpanded $targetKey
        }
        if ($appsScrollViewer) { $appsScrollViewer.ScrollToVerticalOffset(0) }
        return
    }

    if ($script:activeSingleCatDesc) {
        foreach ($scCol in $script:singleCatCols) {
            if ($scCol) { $scCol.Children.Clear() }
        }
        $prevCd = $script:activeSingleCatDesc
        $prevCd.RowsStack.Children.Clear()
        foreach ($r in $prevCd.Rows) {
            [void]$prevCd.RowsStack.Children.Add($r)
        }
        $script:activeSingleCatDesc = $null
    }

    if ($script:deferredCardTimer) { $script:deferredCardTimer.Stop() }

    $script:activeCatalogCategory = $targetKey

    if ($targetKey -eq "__ALL__") {
        foreach ($grp in $script:catalogGroupsOrdered) { $grp.IsExpanded = $false }
    } elseif ($isGroupTarget) {
        foreach ($grp in $script:catalogGroupsOrdered) { $grp.IsExpanded = ($grp.Key -eq $targetKey) }
    } else {
        $pKey = $null
        [void]$script:catToGroupKey.TryGetValue($targetKey, [ref]$pKey)
        foreach ($grp in $script:catalogGroupsOrdered) { $grp.IsExpanded = ($pKey -and $grp.Key -eq $pKey) }
    }

    Update-SidebarVisuals
    if ($appsScrollViewer) { $appsScrollViewer.ScrollToVerticalOffset(0) }

    if ($targetKey -eq "__ALL__") {
        foreach ($colP in $cardCols) {
            if ($colP) { $colP.Children.Clear() }
        }
        if ($cardsCol2Panel) { $cardsCol2Panel.Visibility = [System.Windows.Visibility]::Visible }
        if ($cardsColDef2) { $cardsColDef2.Width = $glCol2 }
        foreach ($cd in $script:cardDescriptors) {
            $cd.ColPanel = $cd.AllColPanel
            $cd.EstTop = $cd.AllEstTop
            $cd.EstBottom = $cd.AllEstBottom
            $cd.Attached = $true
            if ($cd.ColPanel) { [void]$cd.ColPanel.Children.Add($cd.Card) }
        }
        $script:activeMasonryDescriptors = $null
        $script:activeAllowedCategories = $null
        if ($singleCategoryHost) { $singleCategoryHost.Visibility = [System.Windows.Visibility]::Collapsed }
        if ($groupFilterBanner) { $groupFilterBanner.Visibility = [System.Windows.Visibility]::Collapsed }
        if ($cardsMasonrySection) { $cardsMasonrySection.Visibility = [System.Windows.Visibility]::Visible }
        if ($cardsMasonryHost) { $cardsMasonryHost.Visibility = [System.Windows.Visibility]::Visible }
        Sync-Tab0ViewportAssets
        return
    }

    if ($isGroupTarget) {
        $grp = $script:catalogGroupByKey[$targetKey]
        foreach ($colP in $cardCols) {
            if ($colP) { $colP.Children.Clear() }
        }
        foreach ($cd in $script:cardDescriptors) {
            $cd.Attached = $false
        }

        $grpDescs = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($cName in $grp.Categories) {
            $cdItem = $null
            if ($script:cardDescByCategory.TryGetValue($cName, [ref]$cdItem)) {
                [void]$grpDescs.Add($cdItem)
            }
        }

        $colLimit = if ($grpDescs.Count -le 2 -and $cardCols.Count -ge 2) { 2 } else { [Math]::Max(1, $cardCols.Count) }
        if ($colLimit -eq 2 -and $cardCols.Count -ge 3) {
            if ($cardsCol2Panel) { $cardsCol2Panel.Visibility = [System.Windows.Visibility]::Collapsed }
            if ($cardsColDef2) { $cardsColDef2.Width = $glZero }
        } else {
            if ($cardsCol2Panel) { $cardsCol2Panel.Visibility = [System.Windows.Visibility]::Visible }
            if ($cardsColDef2) { $cardsColDef2.Width = $glCol2 }
        }

        $grpHeights = @(0.0, 0.0, 0.0)
        foreach ($cd in $grpDescs) {
            $bestCol = 0
            $minH = $grpHeights[0]
            for ($ci = 1; $ci -lt $colLimit; $ci++) {
                if ($grpHeights[$ci] -lt $minH) {
                    $minH = $grpHeights[$ci]
                    $bestCol = $ci
                }
            }
            $colPanel = $cardCols[$bestCol]
            $cd.ColPanel = $colPanel
            $cd.EstTop = $minH
            $cd.EstBottom = $minH + $cd.EstHeight
            $cd.Attached = $true
            $cd.Card.CacheMode = $null
            $cd.CacheEnabled = $false
            if ($colPanel) { [void]$colPanel.Children.Add($cd.Card) }
            $grpHeights[$bestCol] += $cd.EstHeight
        }

        $script:activeMasonryDescriptors = $grpDescs
        $script:activeAllowedCategories = $grp.CategorySet
        if ($txtGroupFilterTitle) { $txtGroupFilterTitle.Text = $grp.Title }
        if ($txtGroupFilterMeta) { $txtGroupFilterMeta.Text = "$($grp.Categories.Count) danh mục  $([char]0x00B7)  $($grp.AppCount) ứng dụng" }
        if ($singleCategoryHost) { $singleCategoryHost.Visibility = [System.Windows.Visibility]::Collapsed }
        if ($groupFilterBanner) { $groupFilterBanner.Visibility = [System.Windows.Visibility]::Visible }
        if ($cardsMasonrySection) { $cardsMasonrySection.Visibility = [System.Windows.Visibility]::Visible }
        if ($cardsMasonryHost) { $cardsMasonryHost.Visibility = [System.Windows.Visibility]::Visible }

        foreach ($cd in $grpDescs) { Enqueue-CardIconsNow -CardDesc $cd }
        Flush-PendingIconCache -MaxDecode 48
        Try-EnableCompletedCardCaches
        return
    }

    $cd = $script:cardDescByCategory[$targetKey]
    $script:activeSingleCatDesc = $cd
    $singleSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    [void]$singleSet.Add([string]$targetKey)
    $script:activeAllowedCategories = $singleSet

    if ($cd.Card) {
        $cd.Card.CacheMode = $null
        $cd.CacheEnabled = $false
    }
    $cd.RowsStack.Children.Clear()

    $n = $cd.Rows.Count
    $colCnt = [Math]::Max(1, $script:singleCatCols.Count)
    $base = [int][Math]::Floor($n / $colCnt)
    $rem = $n % $colCnt
    $offset = 0
    for ($ci = 0; $ci -lt $colCnt; $ci++) {
        $take = $base + $(if ($ci -lt $rem) { 1 } else { 0 })
        $colPanel = $script:singleCatCols[$ci]
        for ($k = 0; $k -lt $take -and ($offset + $k) -lt $n; $k++) {
            if ($colPanel) { [void]$colPanel.Children.Add($cd.Rows[$offset + $k]) }
        }
        $offset += $take
    }

    $parentGrpKey = $null
    if ($script:catToGroupKey.TryGetValue($targetKey, [ref]$parentGrpKey) -and $script:catalogGroupByKey.ContainsKey($parentGrpKey)) {
        $pGrp = $script:catalogGroupByKey[$parentGrpKey]
        if ($txtSingleCatParent) { $txtSingleCatParent.Text = $pGrp.Title }
        if ($btnSingleCatParent) {
            $btnSingleCatParent.Tag = $pGrp.Key
            $btnSingleCatParent.Visibility = [System.Windows.Visibility]::Visible
        }
        if ($iconSingleCatCrumb) { $iconSingleCatCrumb.Visibility = [System.Windows.Visibility]::Visible }
    } else {
        if ($btnSingleCatParent) { $btnSingleCatParent.Visibility = [System.Windows.Visibility]::Collapsed }
        if ($iconSingleCatCrumb) { $iconSingleCatCrumb.Visibility = [System.Windows.Visibility]::Collapsed }
    }

    if ($txtSingleCatTitle) { $txtSingleCatTitle.Text = $targetKey }
    if ($txtSingleCatCount) { $txtSingleCatCount.Text = "$n ứng dụng" }
    if ($cardsMasonryHost) { $cardsMasonryHost.Visibility = [System.Windows.Visibility]::Collapsed }
    if ($cardsMasonrySection) { $cardsMasonrySection.Visibility = [System.Windows.Visibility]::Collapsed }
    if ($singleCategoryHost) { $singleCategoryHost.Visibility = [System.Windows.Visibility]::Visible }

    Enqueue-CardIconsNow -CardDesc $cd
    Flush-PendingIconCache -MaxDecode 32
}

if ($categorySidebarTop -and $categorySidebarPanel) {
    $allDesc = New-SidebarNavRow -Key "__ALL__" -Label "Tất cả" -Count $allItemBorders.Count -Role "Root"
    [void]$categorySidebarTop.Children.Add($allDesc.Border)
    $sepSide = [System.Windows.Controls.Border]::new()
    $sepSide.Height = 1
    $sepSide.Background = $script:brushSeparator
    $sepSide.Margin = [System.Windows.Thickness]::new(2, 4, 2, 0)
    $sepSide.IsHitTestVisible = $false
    [void]$categorySidebarTop.Children.Add($sepSide)

    $assignedCats = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $effectiveDefs = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($gDef in $script:catalogGroupDefs) {
        $validCats = [System.Collections.Generic.List[string]]::new()
        foreach ($cName in $gDef.Categories) {
            if ($appsByCategory.ContainsKey($cName)) {
                [void]$validCats.Add([string]$cName)
                [void]$assignedCats.Add([string]$cName)
            }
        }
        if ($validCats.Count -gt 0) {
            [void]$effectiveDefs.Add(@{ Key = $gDef.Key; Title = $gDef.Title; Categories = $validCats })
        }
    }
    $unassignedCats = [System.Collections.Generic.List[string]]::new()
    foreach ($cat in $categories) {
        if (-not $assignedCats.Contains([string]$cat)) {
            [void]$unassignedCats.Add([string]$cat)
        }
    }
    if ($unassignedCats.Count -gt 0) {
        [void]$effectiveDefs.Add(@{ Key = "__GROUP__:Other"; Title = "Khác"; Categories = $unassignedCats })
    }

    foreach ($gDef in $effectiveDefs) {
        $grpApps = 0
        $cSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($cName in $gDef.Categories) {
            [void]$cSet.Add([string]$cName)
            $script:catToGroupKey[[string]$cName] = $gDef.Key
            if ($appsByCategory.ContainsKey($cName)) { $grpApps += $appsByCategory[$cName].Count }
        }

        $grpBtnDesc = New-SidebarNavRow -Key $gDef.Key -Label $gDef.Title -Count $grpApps -Role "Group"
        [void]$categorySidebarPanel.Children.Add($grpBtnDesc.Border)

        $childrenHost = [System.Windows.Controls.Border]::new()
        $childrenHost.BorderBrush = $script:brushSidebarGuide
        $childrenHost.BorderThickness = [System.Windows.Thickness]::new(1, 0, 0, 0)
        $childrenHost.Margin = [System.Windows.Thickness]::new(12, 1, 0, 4)
        $childrenHost.Padding = [System.Windows.Thickness]::new(6, 0, 0, 0)
        $childrenHost.Visibility = [System.Windows.Visibility]::Collapsed

        $childrenStack = [System.Windows.Controls.StackPanel]::new()
        foreach ($cName in $gDef.Categories) {
            $cCnt = if ($appsByCategory.ContainsKey($cName)) { $appsByCategory[$cName].Count } else { 0 }
            $subDesc = New-SidebarNavRow -Key $cName -Label $cName -Count $cCnt -Role "Child"
            [void]$childrenStack.Children.Add($subDesc.Border)
        }
        $childrenHost.Child = $childrenStack
        [void]$categorySidebarPanel.Children.Add($childrenHost)

        $grpObj = @{
            Key           = $gDef.Key
            Title         = $gDef.Title
            Categories    = $gDef.Categories
            CategorySet   = $cSet
            AppCount      = $grpApps
            IsExpanded    = $false
            ChildrenHost  = $childrenHost
            ChildrenStack = $childrenStack
            BtnDesc       = $grpBtnDesc
        }
        $script:catalogGroupByKey[$gDef.Key] = $grpObj
        [void]$script:catalogGroupsOrdered.Add($grpObj)
    }

    if ($txtCategorySidebarMeta) {
        $txtCategorySidebarMeta.Text = "$($script:catalogGroupsOrdered.Count) nhóm $([char]0x00B7) $($categories.Count) mục"
    }

    Update-SidebarVisuals

    $sidebarClickRouter = [System.Windows.Input.MouseButtonEventHandler]{
        param($sender, $e)
        if ($e.Handled -or $script:isWindowClosing) { return }
        $node = $e.OriginalSource
        while ($null -ne $node -and $node -ne $sender) {
            if ($node -is [System.Windows.Controls.Border] -and $node.Tag -is [hashtable]) {
                if ($node.Tag.ContainsKey('ToggleGroup')) {
                    $e.Handled = $true
                    Toggle-SidebarGroupExpanded ([string]$node.Tag['ToggleGroup'])
                    return
                }
                if ($node.Tag.ContainsKey('Key')) {
                    $e.Handled = $true
                    Set-ActiveCatalogCategory ([string]$node.Tag['Key'])
                    return
                }
            }
            if ($node -is [System.Windows.Media.Visual]) {
                $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
            } else { break }
        }
    }
    $categorySidebarTop.Add_MouseLeftButtonUp($sidebarClickRouter)
    $categorySidebarPanel.Add_MouseLeftButtonUp($sidebarClickRouter)
}

if ($btnGroupBack) {
    $btnGroupBack.Add_MouseLeftButtonUp({
        param($s, $e)
        $e.Handled = $true
        Set-ActiveCatalogCategory "__ALL__"
    })
}

if ($btnSingleCatParent) {
    $btnSingleCatParent.Add_MouseLeftButtonUp({
        param($s, $e)
        $e.Handled = $true
        if ($s.Tag) {
            Set-ActiveCatalogCategory ([string]$s.Tag)
        }
    })
}

if ($btnSingleCatBack) {
    $btnSingleCatBack.Add_MouseLeftButtonUp({
        param($s, $e)
        $e.Handled = $true
        Set-ActiveCatalogCategory "__ALL__"
    })
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
                return (Run-CliStream "msiexec.exe" "/i `"$dlPath`" /qn /norestart" -IsolateStdin -AllowCancel)
            } else {
                return (Run-CliStream $dlPath "--silent-install" -IsolateStdin -AllowCancel)
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
                [void](Wait-TaskNonBlocking -Task ([System.Threading.Tasks.Task]::Delay(600)) -TimeoutSeconds 2 -CancelCheck { [bool]$script:cancelRequested })
            }
            return $true
        }
        if (-not $logged) {
            Log-Text "[*] Đang chờ tiến trình Windows Installer khác hoàn tất..."
            $logged = $true
        }
        [void](Wait-TaskNonBlocking -Task ([System.Threading.Tasks.Task]::Delay(500)) -TimeoutSeconds 2 -CancelCheck { [bool]$script:cancelRequested })
        if ($script:cancelRequested) { break }
    }
    return $false
}

function Invoke-WinGetWithMsiRetry {
    param([Parameter(Mandatory = $true)][string]$Arguments)
    if ($script:isWindowClosing -or $script:cancelRequested) { return -1 }
    [void](Wait-WindowsInstallerReady -MaxWaitSeconds 20)
    if ($script:isWindowClosing -or $script:cancelRequested) { return -1 }
    $code = Run-CliStream "winget" $Arguments -IsolateStdin -AllowCancel
    if (-not $script:isWindowClosing -and -not $script:cancelRequested -and ($code -eq -1978334974 -or $code -eq 1618)) {
        Log-Text "[!] Windows Installer đang bận (1618), đang chờ giải phóng để thử lại..."
        [void](Wait-WindowsInstallerReady -MaxWaitSeconds 25)
        if ($script:isWindowClosing -or $script:cancelRequested) { return -1 }
        [void](Wait-TaskNonBlocking -Task ([System.Threading.Tasks.Task]::Delay(1200)) -TimeoutSeconds 3 -CancelCheck { [bool]$script:cancelRequested })
        if ($script:isWindowClosing -or $script:cancelRequested) { return -1 }
        $code = Run-CliStream "winget" $Arguments -IsolateStdin -AllowCancel
    }
    return $code
}

function Wait-SquirrelUpdatersSettle {
    param([int]$MaxWaitMs = 4000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($MaxWaitMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($script:isWindowClosing -or $script:cancelRequested) { break }
        $running = @(Get-Process -Name "Update" -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -and $_.Path.StartsWith($env:LOCALAPPDATA, [System.StringComparison]::OrdinalIgnoreCase) } catch { $false }
        })
        if ($running.Count -eq 0) { break }
        [void](Wait-TaskNonBlocking -Task ([System.Threading.Tasks.Task]::Delay(350)) -TimeoutSeconds 1 -CancelCheck { [bool]$script:cancelRequested })
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
    Invoke-GuardedAction "Cài đặt & Cập nhật" {
        $selectedTags = [System.Collections.Generic.List[object]]::new()
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -eq $true) {
                $selectedTags.Add($cb.Tag)
            }
        }

        if ($selectedTags.Count -eq 0) {
            Log-Text "[!] Bạn chưa tick chọn ứng dụng nào để cài đặt hoặc cập nhật!"
            return
        }

        $total = $selectedTags.Count
        $idx = 0
        $didAnyAction = $false
        if ($btnCancelAction) {
            $btnCancelAction.Content = "Dừng tác vụ"
            $btnCancelAction.IsEnabled = $true
            $btnCancelAction.Visibility = [System.Windows.Visibility]::Visible
        }
        Log-Text "=========================================================="
        Log-Text "[INSTALL & UPGRADE] XỬ LÝ $total ỨNG DỤNG ĐÃ ĐÁNH DẤU"
        Log-Text "=========================================================="

        try {
            foreach ($tag in $selectedTags) {
                if ($script:isWindowClosing -or $script:cancelRequested) { break }
                $idx++
                $app = $tag.App
                if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }

                if ($tag.Status -eq "LATEST") {
                    Log-Text "[OK] $($app.Name) đã là bản mới nhất, bỏ qua."
                    if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                    continue
                }

                if ($tag.Status -eq "OUTDATED") {
                    $didAnyAction = $true
                    if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang cập nhật: $($app.Name)..." }
                    Log-Text "[$idx/$total] Đang cập nhật: $($app.Name) (ID: $($app.ID))..."
                    $upCode = Invoke-SmartAppUpgrade -Tag $tag
                    if ($upCode -eq 0) {
                        Log-Text "   [OK - ĐÃ CẬP NHẬT THÀNH CÔNG] $($app.Name)"
                        if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                    } elseif ($upCode -eq 2) {
                        Log-Text "   [SKIP - BẢO VỆ CRACK/PATCH] Đã bỏ qua $($app.Name) để giữ nguyên file patch."
                        if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                    } else {
                        Log-Text "   [ERR - LỖI CẬP NHẬT HOẶC ĐÃ MỚI NHẤT] $($app.Name) (Exit Code: $upCode)"
                    }
                    continue
                }

                $didAnyAction = $true
                if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang cài đặt: $($app.Name)..." }
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
            if ($txtStatus) { $txtStatus.Text = "Cài đặt & Cập nhật hoàn tất!" }
            if ($progressBar) { $progressBar.Value = 100 }
            if ($didAnyAction) {
                Wait-SquirrelUpdatersSettle
                if (-not $script:isWindowClosing) {
                    Scan-And-ColorizeApps
                }
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
        if ($btnCancelAction) {
            $btnCancelAction.Content = "Dừng tác vụ"
            $btnCancelAction.IsEnabled = $true
            $btnCancelAction.Visibility = [System.Windows.Visibility]::Visible
        }

        try {
            $outdatedRows = @($allItemBorders | Where-Object { $_.Tag -and $_.Tag.Status -eq "OUTDATED" })
            if ($outdatedRows.Count -gt 0) {
                $totalOut = $outdatedRows.Count
                $idxOut = 0
                foreach ($row in $outdatedRows) {
                    if ($script:isWindowClosing -or $script:cancelRequested) { break }
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
            } elseif (-not $script:isWindowClosing -and -not $script:cancelRequested) {
                Run-CliStream "winget" "upgrade --all --silent --accept-package-agreements --accept-source-agreements" -IsolateStdin -AllowCancel
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
    $filterSet = $script:activeAllowedCategories
    try {
        foreach ($row in $allItemBorders) {
            if ($row.Visibility -eq [System.Windows.Visibility]::Visible -and $row.Tag -and $row.Tag.CheckBox) {
                if ($null -ne $filterSet -and (-not $row.Tag.App -or -not $filterSet.Contains([string]$row.Tag.App.Category))) {
                    continue
                }
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
    $script:cancelRequested = $true
    $script:isUninstallingQueue = $false
    if ($script:uninstallQueue) { try { $script:uninstallQueue.Clear() } catch {} }
    if ($script:uninstallQueuedKeys) { try { $script:uninstallQueuedKeys.Clear() } catch {} }
    try { Stop-ActiveWaitFrames } catch {}
    try { if ($script:iconSyncTimer) { $script:iconSyncTimer.Stop() } } catch {}
    try { if ($script:uninstIconTimer) { $script:uninstIconTimer.Stop() } } catch {}
    try { if ($script:uninstSearchDebounceTimer) { $script:uninstSearchDebounceTimer.Stop() } } catch {}
    try { if ($script:uninstallerVirtualView) { $script:uninstallerVirtualView.Stop() } } catch {}
    try { if ($script:deferredCardTimer) { $script:deferredCardTimer.Stop() } } catch {}
    try {
        if ("DuckUtil.UiAssetPipeline" -as [type]) {
            [DuckUtil.UiAssetPipeline]::StopRemoteIconPipeline()
            [DuckUtil.UiAssetPipeline]::StopUninstallerIconPipeline()
        }
    } catch {}
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
        $script:cancelRequested = $false
        $script:isUninstallingQueue = $false
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

$script:deferredCardTimer = [System.Windows.Threading.DispatcherTimer]::new([System.Windows.Threading.DispatcherPriority]::Background)
$script:deferredCardTimer.Interval = [TimeSpan]::FromMilliseconds(35)
$script:deferredCardTimer.Add_Tick({
    if ($script:isWindowClosing -or -not $script:cardDescriptors -or $script:activeCatalogCategory -ne "__ALL__") {
        $script:deferredCardTimer.Stop()
        return
    }
    $attachedNow = 0
    $anyRemaining = $false
    foreach ($cd in $script:cardDescriptors) {
        if (-not $cd.Attached) {
            if ($attachedNow -lt 2) {
                $cd.Attached = $true
                if ($cd.ColPanel) { [void]$cd.ColPanel.Children.Add($cd.Card) }
                $attachedNow++
            } else {
                $anyRemaining = $true
                break
            }
        }
    }
    if (-not $anyRemaining) {
        $script:deferredCardTimer.Stop()
        Try-EnableCompletedCardCaches
    }
})

$script:iconSyncTimer = [System.Windows.Threading.DispatcherTimer]::new([System.Windows.Threading.DispatcherPriority]::Background)
$script:iconSyncTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$script:iconSyncTimer.Add_Tick({
    if ($script:isWindowClosing) {
        $script:iconSyncTimer.Stop()
        return
    }
    if ($script:isActionRunning) { return }
    Flush-PendingIconCache -MaxDecode 24
    if ($script:isWindowClosing -or -not $script:pendingIconSaves -or $script:pendingIconSaves.Count -eq 0) {
        $script:iconSyncTimer.Stop()
    }
})

$script:autoScannedOnStartup = $false
$window.Add_ContentRendered({
    if (-not $script:autoScannedOnStartup -and -not $script:isWindowClosing) {
        $script:autoScannedOnStartup = $true
        Log-Text "[OK] Sẵn sàng ($($allItemBorders.Count) ứng dụng / $($categories.Count) danh mục)."
        if ($script:hasFastCatalogRowBuilder) {
            Sync-Tab0ViewportAssets
            if ($script:deferredCardTimer) { $script:deferredCardTimer.Start() }
        }
        Flush-PendingIconCache -MaxDecode 24
        if ($script:pendingIconSaves -and $script:pendingIconSaves.Count -gt 0 -and -not $script:iconSyncTimer.IsEnabled) {
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
