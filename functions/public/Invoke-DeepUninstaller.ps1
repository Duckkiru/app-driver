if (-not ("DuckUtil.DeepUninstallerEngine" -as [type])) {
    try {
        $csCandidates = @(
            (Join-Path $PSScriptRoot "..\..\csharp\DeepUninstallerEngine.cs"),
            (Join-Path $PSScriptRoot "..\csharp\DeepUninstallerEngine.cs"),
            (Join-Path $PSScriptRoot "csharp\DeepUninstallerEngine.cs")
        )
        foreach ($cand in $csCandidates) {
            if (Test-Path -LiteralPath $cand) {
                $deepUninstCs = Get-Content -Raw -Encoding utf8 $cand
                Add-Type -TypeDefinition $deepUninstCs -ErrorAction SilentlyContinue
                break
            }
        }
    } catch {}
}

function Get-SystemInstalledAppsFast {
    $apps = [DuckUtil.DeepUninstallerEngine]::GetInstalledApps()
    return @($apps | Sort-Object -Property @{ Expression = { $_.IsBrokenOrphan }; Descending = $true }, @{ Expression = { $_.DisplayName }; Descending = $false })
}

function Test-SafeAppDirectoryForCleanup {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$AppEntry,
        [Parameter(Mandatory = $false)][string[]]$Keywords = @(),
        [Parameter(Mandatory = $false)]$AllInstalledApps = $null
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $norm = $Path.Trim().TrimEnd('\')
    if ($norm -match '^[A-Za-z]:$') { return $false }

    $parts = @($norm -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -lt 2) { return $false }

    $genericContainers = @(
        'Windows', 'System32', 'SysWOW64', 'Program Files', 'Program Files (x86)',
        'ProgramData', 'Programs', 'Users', 'AppData', 'Local', 'Roaming', 'LocalLow',
        'Common Files', 'WindowsApps', 'ModifiableWindowsApps', 'Package Cache', 'Packages',
        'Temp', 'Apps', 'Applications', 'Games', 'Game', 'Software', 'Softwares', 'Tools',
        'Downloads', 'Desktop', 'Documents', 'Pictures', 'Music', 'Videos', 'OneDrive',
        'Steam', 'SteamLibrary', 'steamapps', 'common', 'Epic Games', 'GOG Galaxy', 'Riot Games'
    )

    $leafName = $parts[$parts.Count - 1]
    foreach ($gc in $genericContainers) {
        if ($leafName.Equals($gc, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }

    if ($Keywords -and $Keywords.Count -gt 0) {
        $parentName = if ($parts.Count -ge 3) { $parts[$parts.Count - 2] } else { "" }
        $matchedOwner = $false
        foreach ($kw in $Keywords) {
            if ([string]::IsNullOrWhiteSpace($kw) -or $kw.Length -lt 3) { continue }
            if ($leafName.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                ($parentName -and $parentName.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)) {
                $matchedOwner = $true
                break
            }
        }
        if (-not $matchedOwner) { return $false }
    }

    if ($AllInstalledApps) {
        $normWithSlash = $norm + "\"
        foreach ($other in $AllInstalledApps) {
            if ($null -eq $other -or $other.Id -eq $AppEntry.Id) { continue }
            if ($other.IsBrokenOrphan) { continue }
            $otherLoc = if ($other.InstallLocation) { $other.InstallLocation.Trim().TrimEnd('\') } else { "" }
            if ($otherLoc) {
                if ($otherLoc.Equals($norm, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $otherLoc.StartsWith($normWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $false
                }
            }
        }
    }

    return $true
}

function Find-AppLeftovers {
    param(
        [Parameter(Mandatory = $true)]$AppEntry,
        [Parameter(Mandatory = $false)]$AllInstalledApps = $null
    )

    $leftovers = [System.Collections.Generic.List[object]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $exclusions = @(
        'Microsoft', 'Windows', 'Intel', 'AMD', 'NVIDIA', 'Google', 'Common Files',
        'WindowsApps', 'Package Cache', 'Packages', 'Temp', 'System32', 'Explorer', 'Internet Explorer'
    )

    $rawName = $AppEntry.DisplayName
    if ([string]::IsNullOrWhiteSpace($rawName)) { return @() }

    $cleanName = ($rawName -replace '\(.*?\)', '').Trim()
    $cleanName = ($cleanName -replace '[0-9]+(\.[0-9]+)*', '').Trim()
    $nameKeywords = @($cleanName -split '\s+' | Where-Object { $_.Length -ge 4 -and $exclusions -notcontains $_ })
    if ($cleanName.Length -ge 4 -and $exclusions -notcontains $cleanName) {
        $nameKeywords = @($cleanName) + $nameKeywords
    }
    $nameKeywords = @($nameKeywords | Select-Object -Unique)
    if ($nameKeywords.Count -eq 0) { return @() }

    $ownerKeywords = [System.Collections.Generic.List[string]]::new()
    foreach ($nk in $nameKeywords) { $ownerKeywords.Add($nk) }
    if (-not [string]::IsNullOrWhiteSpace($AppEntry.Publisher)) {
        $pubClean = ($AppEntry.Publisher -replace '\(.*?\)', '').Trim()
        foreach ($pk in ($pubClean -split '\s+')) {
            if ($pk.Length -ge 4 -and $exclusions -notcontains $pk) {
                $ownerKeywords.Add($pk)
            }
        }
    }

    if ($AppEntry.InstallLocation -and (Test-Path -LiteralPath $AppEntry.InstallLocation)) {
        $loc = (Resolve-Path -LiteralPath $AppEntry.InstallLocation).Path.TrimEnd('\')
        $isSafe = $true
        foreach ($ex in $exclusions) {
            if ($loc -like "*\$ex\*" -or $loc -like "*\$ex") { $isSafe = $false; break }
        }
        if ($isSafe -and (Test-SafeAppDirectoryForCleanup -Path $loc -AppEntry $AppEntry -Keywords $ownerKeywords.ToArray() -AllInstalledApps $AllInstalledApps)) {
            if ($seenPaths.Add($loc)) {
                $dirSize = [DuckUtil.DeepUninstallerEngine]::GetDirectorySizeFast($loc, 4)
                $leftovers.Add([PSCustomObject]@{
                    Type       = "Th$([char]0x01B0) m$([char]0x1EE5)c r$([char]0x00E1)c t$([char]0x1ED3)n d$([char]0x01B0)"
                    AppName    = $AppEntry.DisplayName
                    Path       = $loc
                    SizeBytes  = [long]$dirSize
                    SizeMB     = [math]::Round($dirSize / 1MB, 2)
                    IsRegistry = $false
                })
            }
        }
    }

    $folderRoots = @(
        $env:APPDATA,
        $env:LOCALAPPDATA,
        (Join-Path $env:LOCALAPPDATA "Programs"),
        "C:\ProgramData"
    )

    foreach ($root in $folderRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($kw in $nameKeywords) {
            $candidatePath = Join-Path $root $kw
            if (Test-Path -LiteralPath $candidatePath) {
                $fullPath = (Resolve-Path -LiteralPath $candidatePath).Path
                $isSafe = $true
                foreach ($ex in $exclusions) {
                    if ($fullPath -like "*\$ex*" -or $fullPath -like "*\$ex") { $isSafe = $false; break }
                }
                if ($isSafe -and $seenPaths.Add($fullPath)) {
                    $dirSize = [DuckUtil.DeepUninstallerEngine]::GetDirectorySizeFast($fullPath, 4)
                    $leftovers.Add([PSCustomObject]@{
                        Type       = "Th$([char]0x01B0) m$([char]0x1EE5)c r$([char]0x00E1)c AppData"
                        AppName    = $AppEntry.DisplayName
                        Path       = $fullPath
                        SizeBytes  = [long]$dirSize
                        SizeMB     = [math]::Round($dirSize / 1MB, 2)
                        IsRegistry = $false
                    })
                }
            }
        }
    }

    $regRoots = @(
        "HKCU:\Software",
        "HKLM:\SOFTWARE",
        "HKLM:\SOFTWARE\WOW6432Node"
    )

    foreach ($regRoot in $regRoots) {
        if (-not (Test-Path -LiteralPath $regRoot)) { continue }
        foreach ($kw in $nameKeywords) {
            $regPath = Join-Path $regRoot $kw
            if (Test-Path -LiteralPath $regPath) {
                $isSafe = $true
                foreach ($ex in $exclusions) {
                    if ($kw -eq $ex) { $isSafe = $false; break }
                }
                if ($isSafe -and $seenPaths.Add($regPath)) {
                    $leftovers.Add([PSCustomObject]@{
                        Type       = "Registry m$([char]0x1ED3) c$([char]0x00F4)i"
                        AppName    = $AppEntry.DisplayName
                        Path       = $regPath
                        SizeBytes  = 0L
                        SizeMB     = 0.0
                        IsRegistry = $true
                    })
                }
            }
        }
    }

    if ($AppEntry.RegistryPath -and (Test-Path -LiteralPath $AppEntry.RegistryPath)) {
        if ($seenPaths.Add($AppEntry.RegistryPath)) {
            $leftovers.Add([PSCustomObject]@{
                Type       = "Registry g$([char]0x1EE1) b$([char]0x1ECF) h$([char]0x1ECF)ng"
                AppName    = $AppEntry.DisplayName
                Path       = $AppEntry.RegistryPath
                SizeBytes  = 0L
                SizeMB     = 0.0
                IsRegistry = $true
            })
        }
    }

    return @($leftovers)
}

function Find-SystemOrphanLeftovers {
    param(
        [Parameter(Mandatory = $false)]$InstalledApps,
        [Parameter(Mandatory = $false)]$CatalogApps
    )

    if ($null -eq $InstalledApps) {
        $InstalledApps = Get-SystemInstalledAppsFast
    }

    $orphans = [System.Collections.Generic.List[object]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $exclusions = @(
        'Microsoft', 'Windows', 'Intel', 'AMD', 'NVIDIA', 'Google', 'Common Files',
        'WindowsApps', 'ModifiableWindowsApps', 'Internet Explorer', 'Windows Defender',
        'Windows Mail', 'Windows Media Player', 'Windows NT', 'Windows Photo Viewer',
        'Windows Portable Devices', 'Windows Security', 'Windows Sidebar', 'WindowsPowerShell',
        'PowerShell', 'dotnet', 'Reference Assemblies', 'MSBuild', 'Package Cache',
        'Packages', 'Temp', 'System32', 'Uninstall Information'
    )

    foreach ($app in $InstalledApps) {
        if ($app.IsBrokenOrphan) {
            if ($app.RegistryPath -and (Test-Path -LiteralPath $app.RegistryPath)) {
                if ($seenPaths.Add($app.RegistryPath)) {
                    $orphans.Add([PSCustomObject]@{
                        Type       = "[Registry m$([char]0x1ED3) c$([char]0x00F4)i]"
                        AppName    = $app.DisplayName
                        Path       = $app.RegistryPath
                        SizeBytes  = 0L
                        SizeMB     = 0.0
                        IsRegistry = $true
                    })
                }
            }

            $appLeftovers = Find-AppLeftovers -AppEntry $app -AllInstalledApps $InstalledApps
            foreach ($lo in $appLeftovers) {
                if ($seenPaths.Add($lo.Path)) {
                    $badgeType = if ($lo.IsRegistry) { "[Registry m$([char]0x1ED3) c$([char]0x00F4)i]" } else { "[Th$([char]0x01B0) m$([char]0x1EE5)c r$([char]0x00E1)c AppData]" }
                    $orphans.Add([PSCustomObject]@{
                        Type       = $badgeType
                        AppName    = $app.DisplayName
                        Path       = $lo.Path
                        SizeBytes  = [long]$lo.SizeBytes
                        SizeMB     = [double]$lo.SizeMB
                        IsRegistry = [bool]$lo.IsRegistry
                    })
                }
            }
        }
    }

    $programRoots = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($drv in [System.IO.DriveInfo]::GetDrives()) {
            if ($drv.DriveType -eq [System.IO.DriveType]::Fixed -and $drv.IsReady) {
                $pf1 = Join-Path $drv.RootDirectory.FullName "Program Files"
                $pf2 = Join-Path $drv.RootDirectory.FullName "Program Files (x86)"
                if (Test-Path -LiteralPath $pf1) { $programRoots.Add($pf1) }
                if (Test-Path -LiteralPath $pf2) { $programRoots.Add($pf2) }
            }
        }
    } catch {
        $programRoots.Add("C:\Program Files")
        $programRoots.Add("C:\Program Files (x86)")
    }
    $localProgs = Join-Path $env:LOCALAPPDATA "Programs"
    if (Test-Path -LiteralPath $localProgs) { $programRoots.Add($localProgs) }

    $activeInstallLocs = [System.Collections.Generic.List[string]]::new()
    foreach ($ia in $InstalledApps) {
        if (-not $ia.IsBrokenOrphan -and -not [string]::IsNullOrWhiteSpace($ia.InstallLocation)) {
            $activeInstallLocs.Add($ia.InstallLocation.Trim().TrimEnd('\'))
        }
    }

    foreach ($pRoot in $programRoots) {
        if (-not (Test-Path -LiteralPath $pRoot)) { continue }
        $subDirs = [System.IO.Directory]::GetDirectories($pRoot)
        foreach ($sd in $subDirs) {
            $dirName = [System.IO.Path]::GetFileName($sd)
            $isExcluded = $false
            foreach ($ex in $exclusions) {
                if ($dirName -like "$ex*" -or $dirName -eq $ex) { $isExcluded = $true; break }
            }
            if ($isExcluded) { continue }

            $sdNorm = $sd.Trim().TrimEnd('\')
            $isUsedByActiveApp = $false
            foreach ($actLoc in $activeInstallLocs) {
                if ($actLoc.Equals($sdNorm, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $actLoc.StartsWith($sdNorm + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
                    $isUsedByActiveApp = $true
                    break
                }
            }
            if ($isUsedByActiveApp) { continue }

            $hollowSize = [DuckUtil.DeepUninstallerEngine]::GetHollowDirectorySize($sd, 3, 52428800L)
            if ($hollowSize -ge 0L) {
                if ($seenPaths.Add($sd)) {
                    $orphans.Add([PSCustomObject]@{
                        Type       = "[V$([char]0x1ECF) th$([char]0x01B0) m$([char]0x1EE5)c r$([char]0x1ED7)ng]"
                        AppName    = $dirName
                        Path       = $sd
                        SizeBytes  = [long]$hollowSize
                        SizeMB     = [math]::Round($hollowSize / 1MB, 2)
                        IsRegistry = $false
                    })
                }
            }
        }
    }

    if ($CatalogApps) {
        $installedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($ia in $InstalledApps) {
            $installedNames.Add($ia.DisplayName) | Out-Null
        }

        $appDataRoots = @($env:APPDATA, $env:LOCALAPPDATA)
        foreach ($catApp in $CatalogApps) {
            $catName = ($catApp.Name -replace '\(.*?\)', '').Trim()
            if ($catName.Length -lt 5) { continue }
            $isInstalled = $false
            foreach ($inName in $installedNames) {
                if ($inName.IndexOf($catName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $isInstalled = $true
                    break
                }
            }
            if (-not $isInstalled) {
                foreach ($ar in $appDataRoots) {
                    $cand = Join-Path $ar $catName
                    if (Test-Path -LiteralPath $cand) {
                        $full = (Resolve-Path -LiteralPath $cand).Path
                        if ($seenPaths.Add($full)) {
                            $dirSize = [DuckUtil.DeepUninstallerEngine]::GetDirectorySizeFast($full, 3)
                            $orphans.Add([PSCustomObject]@{
                                Type       = "[Th$([char]0x01B0) m$([char]0x1EE5)c r$([char]0x00E1)c AppData]"
                                AppName    = $catApp.Name
                                Path       = $full
                                SizeBytes  = [long]$dirSize
                                SizeMB     = [math]::Round($dirSize / 1MB, 2)
                                IsRegistry = $false
                            })
                        }
                    }
                }
            }
        }
    }

    $desktopPaths = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('Programs'),
        [Environment]::GetFolderPath('CommonPrograms')
    )

    try {
        $wsh = New-Object -ComObject WScript.Shell
        foreach ($dp in $desktopPaths) {
            if (-not (Test-Path -LiteralPath $dp)) { continue }
            $lnks = [System.IO.Directory]::GetFiles($dp, "*.lnk", [System.IO.SearchOption]::AllDirectories)
            foreach ($lnk in $lnks) {
                try {
                    $sc = $wsh.CreateShortcut($lnk)
                    $target = $sc.TargetPath
                    if ($target -and $target -match '^[A-Za-z]:\\' -and $target.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
                        if (-not (Test-Path -LiteralPath $target)) {
                            if ($seenPaths.Add($lnk)) {
                                $orphans.Add([PSCustomObject]@{
                                    Type       = "[Shortcut ch$([char]0x1EBF)t]"
                                    AppName    = [System.IO.Path]::GetFileNameWithoutExtension($lnk)
                                    Path       = $lnk
                                    SizeBytes  = 0L
                                    SizeMB     = 0.0
                                    IsRegistry = $false
                                })
                            }
                        }
                    }
                } catch {}
            }
        }
    } catch {}

    return @($orphans)
}

function Show-LeftoverReviewDialog {
    param(
        [Parameter(Mandatory = $false)]$OwnerWindow,
        [Parameter(Mandatory = $true)][object[]]$Items,
        [Parameter(Mandatory = $false)][string]$Title = "Duy$([char]0x1EC7)t & D$([char]0x1ECD)n S$([char]0x1EA1)ch R$([char]0x00E1)c T$([char]0x1ED3)n D$([char]0x01B0)"
    )

    if ($null -eq $Items -or $Items.Count -eq 0) {
        return [PSCustomObject]@{ Confirmed = $false; RemovedCount = 0; FreedBytes = 0L }
    }

    $dialog = New-Object System.Windows.Window
    $dialog.Title = $Title
    $dialog.Width = 840
    $dialog.Height = 540
    $dialog.MinWidth = 720
    $dialog.MinHeight = 420
    $dialog.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    $dialog.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0A0E15")
    $dialog.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F1F5F9")
    $dialog.WindowStyle = [System.Windows.WindowStyle]::SingleBorderWindow
    $dialog.UseLayoutRounding = $true
    $dialog.SnapsToDevicePixels = $true
    if ($OwnerWindow) { $dialog.Owner = $OwnerWindow }

    $rootGrid = New-Object System.Windows.Controls.Grid
    $rowTop = New-Object System.Windows.Controls.RowDefinition; $rowTop.Height = [System.Windows.GridLength]::Auto
    $rowList = New-Object System.Windows.Controls.RowDefinition; $rowList.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $rowBottom = New-Object System.Windows.Controls.RowDefinition; $rowBottom.Height = [System.Windows.GridLength]::Auto
    $rootGrid.RowDefinitions.Add($rowTop) | Out-Null
    $rootGrid.RowDefinitions.Add($rowList) | Out-Null
    $rootGrid.RowDefinitions.Add($rowBottom) | Out-Null

    $headerPanel = New-Object System.Windows.Controls.DockPanel
    $headerPanel.Margin = New-Object System.Windows.Thickness(18, 14, 18, 10)
    $titleBlock = New-Object System.Windows.Controls.TextBlock
    $titleBlock.Text = $Title
    $titleBlock.FontSize = 15
    $titleBlock.FontWeight = [System.Windows.FontWeights]::Bold
    $titleBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
    $headerPanel.Children.Add($titleBlock) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($headerPanel, 0)
    $rootGrid.Children.Add($headerPanel) | Out-Null

    $scrollViewer = New-Object System.Windows.Controls.ScrollViewer
    $scrollViewer.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $scrollViewer.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Disabled
    $scrollViewer.Margin = New-Object System.Windows.Thickness(18, 0, 18, 10)

    $itemsStack = New-Object System.Windows.Controls.StackPanel
    $itemCheckBoxes = [System.Collections.Generic.List[System.Windows.Controls.CheckBox]]::new()

    foreach ($item in $Items) {
        $itemBorder = New-Object System.Windows.Controls.Border
        $itemBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#101520")
        $itemBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $itemBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $itemBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $itemBorder.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
        $itemBorder.Padding = New-Object System.Windows.Thickness(10, 8, 10, 8)

        $itemGrid = New-Object System.Windows.Controls.Grid
        $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = [System.Windows.GridLength]::Auto
        $itemGrid.ColumnDefinitions.Add($c0) | Out-Null
        $itemGrid.ColumnDefinitions.Add($c1) | Out-Null
        $itemGrid.ColumnDefinitions.Add($c2) | Out-Null
        $itemGrid.ColumnDefinitions.Add($c3) | Out-Null

        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.IsChecked = $true
        $cb.Tag = $item
        $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $cb.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $itemGrid.Children.Add($cb) | Out-Null
        $itemCheckBoxes.Add($cb)

        $badgeBorder = New-Object System.Windows.Controls.Border
        $badgeColor = switch -Wildcard ($item.Type) {
            "*Registry*" { "#DC2626" }
            "*R$([char]0x00E1)c AppData*" { "#D97706" }
            "*V$([char]0x1ECF) th$([char]0x01B0) m$([char]0x1EE5)c*" { "#2563EB" }
            "*Shortcut*" { "#7C3AED" }
            default { "#0D9488" }
        }
        $badgeBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($badgeColor)
        $badgeBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $badgeBorder.Padding = New-Object System.Windows.Thickness(6, 2, 6, 2)
        $badgeBorder.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
        $badgeBorder.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $badgeText = New-Object System.Windows.Controls.TextBlock
        $badgeText.Text = $item.Type
        $badgeText.FontSize = 10.5
        $badgeText.FontWeight = [System.Windows.FontWeights]::SemiBold
        $badgeText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
        $badgeBorder.Child = $badgeText
        [System.Windows.Controls.Grid]::SetColumn($badgeBorder, 1)
        $itemGrid.Children.Add($badgeBorder) | Out-Null

        $infoPanel = New-Object System.Windows.Controls.StackPanel
        $infoPanel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $appBlock = New-Object System.Windows.Controls.TextBlock
        $appBlock.Text = $item.AppName
        $appBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
        $appBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0")
        $infoPanel.Children.Add($appBlock) | Out-Null

        $pathBlock = New-Object System.Windows.Controls.TextBlock
        $pathBlock.Text = $item.Path
        $pathBlock.FontSize = 11
        $pathBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
        $pathBlock.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $pathBlock.ToolTip = $item.Path
        $infoPanel.Children.Add($pathBlock) | Out-Null

        [System.Windows.Controls.Grid]::SetColumn($infoPanel, 2)
        $itemGrid.Children.Add($infoPanel) | Out-Null

        $sizeBlock = New-Object System.Windows.Controls.TextBlock
        $sizeBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $sizeBlock.FontSize = 11.5
        $sizeBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
        $sizeBlock.Margin = New-Object System.Windows.Thickness(10, 0, 4, 0)
        if ($item.IsRegistry) {
            $sizeBlock.Text = "Registry"
            $sizeBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
        } else {
            $sizeBlock.Text = "$([string]::Format('{0:N2}', $item.SizeMB)) MB"
            $sizeBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
        }
        [System.Windows.Controls.Grid]::SetColumn($sizeBlock, 3)
        $itemGrid.Children.Add($sizeBlock) | Out-Null

        $itemBorder.Child = $itemGrid
        $itemsStack.Children.Add($itemBorder) | Out-Null
    }

    $scrollViewer.Content = $itemsStack
    [System.Windows.Controls.Grid]::SetRow($scrollViewer, 1)
    $rootGrid.Children.Add($scrollViewer) | Out-Null

    $bottomBar = New-Object System.Windows.Controls.Border
    $bottomBar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0D121B")
    $bottomBar.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
    $bottomBar.BorderThickness = New-Object System.Windows.Thickness(0, 1, 0, 0)
    $bottomBar.Padding = New-Object System.Windows.Thickness(18, 10, 18, 10)

    $bottomGrid = New-Object System.Windows.Controls.Grid
    $bgCol0 = New-Object System.Windows.Controls.ColumnDefinition; $bgCol0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $bgCol1 = New-Object System.Windows.Controls.ColumnDefinition; $bgCol1.Width = [System.Windows.GridLength]::Auto
    $bottomGrid.ColumnDefinitions.Add($bgCol0) | Out-Null
    $bottomGrid.ColumnDefinitions.Add($bgCol1) | Out-Null

    $summaryText = New-Object System.Windows.Controls.TextBlock
    $summaryText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $summaryText.FontSize = 12
    $summaryText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")

    $updateSummary = {
        $selCount = 0
        $selBytes = 0L
        foreach ($c in $itemCheckBoxes) {
            if ($c.IsChecked) {
                $selCount++
                $selBytes += $c.Tag.SizeBytes
            }
        }
        $mb = [math]::Round($selBytes / 1MB, 2)
        $summaryText.Text = "$([char]0x0110)$([char]0x00E3) ch$([char]0x1ECD)n: $selCount / $($itemCheckBoxes.Count) m$([char]0x1EE5)c (~$mb MB)"
    }
    & $updateSummary

    foreach ($c in $itemCheckBoxes) {
        $c.Add_Checked($updateSummary)
        $c.Add_Unchecked($updateSummary)
    }

    [System.Windows.Controls.Grid]::SetColumn($summaryText, 0)
    $bottomGrid.Children.Add($summaryText) | Out-Null

    $btnStack = New-Object System.Windows.Controls.StackPanel
    $btnStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal

    $btnSelectAll = New-Object System.Windows.Controls.Button
    $btnSelectAll.Content = "Ch$([char]0x1ECD)n t$([char]0x1EA5)t c$([char]0x1EA3)"
    $btnSelectAll.Padding = New-Object System.Windows.Thickness(10, 6, 10, 6)
    $btnSelectAll.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $btnSelectAll.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
    $btnSelectAll.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1")
    $btnSelectAll.Add_Click({
        foreach ($c in $itemCheckBoxes) { $c.IsChecked = $true }
    })
    $btnStack.Children.Add($btnSelectAll) | Out-Null

    $btnDeselectAll = New-Object System.Windows.Controls.Button
    $btnDeselectAll.Content = "B$([char]0x1ECF) ch$([char]0x1ECD)n"
    $btnDeselectAll.Padding = New-Object System.Windows.Thickness(10, 6, 10, 6)
    $btnDeselectAll.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $btnDeselectAll.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
    $btnDeselectAll.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1")
    $btnDeselectAll.Add_Click({
        foreach ($c in $itemCheckBoxes) { $c.IsChecked = $false }
    })
    $btnStack.Children.Add($btnDeselectAll) | Out-Null

    $btnCancel = New-Object System.Windows.Controls.Button
    $btnCancel.Content = "H$([char]0x1EE7)y b$([char]0x1ECF)"
    $btnCancel.Padding = New-Object System.Windows.Thickness(12, 6, 12, 6)
    $btnCancel.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $btnCancel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
    $btnCancel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
    $btnCancel.Add_Click({ $dialog.Close() })
    $btnStack.Children.Add($btnCancel) | Out-Null

    $dialogResult = [PSCustomObject]@{ Confirmed = $false; RemovedCount = 0; FreedBytes = 0L }

    $btnDelete = New-Object System.Windows.Controls.Button
    $btnDelete.Content = "X$([char]0x00F3)a S$([char]0x1EA1)ch M$([char]0x1EE5)c $([char]0x0110)$([char]0x00E3) Ch$([char]0x1ECD)n"
    $btnDelete.Padding = New-Object System.Windows.Thickness(14, 6, 14, 6)
    $btnDelete.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#991B1B")
    $btnDelete.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FEE2E2")
    $btnDelete.FontWeight = [System.Windows.FontWeights]::Bold
    $btnDelete.Add_Click({
        $checkedItems = @($itemCheckBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
        if ($checkedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("B$([char]0x1EA1)n ch$([char]0x01B0)a ch$([char]0x1ECD)n m$([char]0x1EE5)c n$([char]0x00E0)o $([char]0x0111)$([char]0x1EC3) d$([char]0x1ECD)n s$([char]0x1EA1)ch.", "Th$([char]0x00F4)ng b$([char]0x00E1)o", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }

        $removed = 0
        $freed = 0L

        foreach ($ci in $checkedItems) {
            try {
                if (Test-Path -LiteralPath $ci.Path) {
                    Remove-Item -LiteralPath $ci.Path -Recurse -Force -ErrorAction Stop
                    $removed++
                    $freed += $ci.SizeBytes
                    if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                        Log-Text "[D$([char]0x1ECC)N R$([char]0x00C1)C] $([char]0x0110)$([char]0x00E3) x$([char]0x00F3)a: $($ci.Type) - $($ci.Path)"
                    }
                }
            } catch {
                if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                    Log-Text "[!] L$([char]0x1ED7)i khi x$([char]0x00F3)a $($ci.Path): $($_.Exception.Message)"
                }
            }
        }

        $dialogResult.Confirmed = $true
        $dialogResult.RemovedCount = $removed
        $dialogResult.FreedBytes = $freed
        $dialog.Close()
    })
    $btnStack.Children.Add($btnDelete) | Out-Null

    [System.Windows.Controls.Grid]::SetColumn($btnStack, 1)
    $bottomGrid.Children.Add($btnStack) | Out-Null

    $bottomBar.Child = $bottomGrid
    [System.Windows.Controls.Grid]::SetRow($bottomBar, 2)
    $rootGrid.Children.Add($bottomBar) | Out-Null

    $dialog.Content = $rootGrid
    $null = $dialog.ShowDialog()

    return $dialogResult
}

function Invoke-DeepAppUninstall {
    param(
        [Parameter(Mandatory = $true)]$AppEntry,
        [Parameter(Mandatory = $false)]$OwnerWindow
    )

    if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
        Log-Text "=========================================================="
        Log-Text "B$([char]0x1EAE)T $([char]0x0110)$([char]0x1EA6)U G$([char]0x1EE0) C$([char]0x00C0)I $([char]0x0110)$([char]0x1EB6)T T$([char]0x1EAC)N G$([char]0x1ED0)C: $($AppEntry.DisplayName)"
        Log-Text "=========================================================="
    }

    $allInstalledNow = Get-SystemInstalledAppsFast

    if ($AppEntry.InstallLocation -and (Test-Path -LiteralPath $AppEntry.InstallLocation)) {
        $loc = (Resolve-Path -LiteralPath $AppEntry.InstallLocation).Path.TrimEnd('\')
        if (Test-SafeAppDirectoryForCleanup -Path $loc -AppEntry $AppEntry -AllInstalledApps $allInstalledNow) {
            try {
                $procs = Get-Process -ErrorAction SilentlyContinue
                foreach ($proc in $procs) {
                    try {
                        if ($proc.MainModule -and $proc.MainModule.FileName -and $proc.MainModule.FileName.StartsWith($loc + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
                            if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                                Log-Text "[*] $([char]0x0110)ang $([char]0x0111)$([char]0x00F3)ng ti$([char]0x1EBF)n tr$([char]0x00EC)nh $([char]0x0111)ang ch$([char]0x1EA1)y: $($proc.ProcessName) (PID: $($proc.Id))"
                            }
                            $proc.Kill()
                        }
                    } catch {}
                }
            } catch {}
        }
    }

    if (-not $AppEntry.IsBrokenOrphan) {
        $uninstCmd = if (-not [string]::IsNullOrWhiteSpace($AppEntry.QuietUninstallString)) {
            $AppEntry.QuietUninstallString
        } else {
            $AppEntry.UninstallString
        }

        if (-not [string]::IsNullOrWhiteSpace($uninstCmd)) {
            $uninstCmd = $uninstCmd.Trim()
            if ($uninstCmd.IndexOf("msiexec", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                    Log-Text "[*] $([char]0x0110)ang g$([char]0x1ECD)i Windows Installer g$([char]0x1EE1) b$([char]0x1ECF) g$([char]0x00F3)i MSI: $($AppEntry.DisplayName)..."
                }
                if (Get-Command Run-CliStream -ErrorAction SilentlyContinue) {
                    Run-CliStream "msiexec.exe" "/x `"$($AppEntry.Id)`" /qn /norestart"
                } else {
                    Start-Process "msiexec.exe" -ArgumentList "/x `"$($AppEntry.Id)`" /qn /norestart" -Wait -NoNewWindow
                }
            } else {
                $exe = ""
                $args = ""
                if ($uninstCmd.StartsWith('"')) {
                    $nextQ = $uninstCmd.IndexOf('"', 1)
                    if ($nextQ -gt 1) {
                        $exe = $uninstCmd.Substring(1, $nextQ - 1)
                        $args = $uninstCmd.Substring($nextQ + 1).Trim()
                    } else {
                        $exe = $uninstCmd.Trim('"')
                    }
                } else {
                    $parts = $uninstCmd -split '\s+', 2
                    $exe = $parts[0]
                    if ($parts.Count -gt 1) { $args = $parts[1] }
                }

                if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                    Log-Text "[*] $([char]0x0110)ang th$([char]0x1EF1)c thi tr$([char]0x00EC)nh g$([char]0x1EE1) b$([char]0x1ECF) ch$([char]0x00ED)nh th$([char]0x1EE9)c: $exe $args"
                }
                if (Get-Command Run-CliStream -ErrorAction SilentlyContinue) {
                    Run-CliStream $exe $args
                } else {
                    Start-Process $exe -ArgumentList $args -Wait -NoNewWindow
                }
            }
        }
    }

    Start-Sleep -Milliseconds 800

    $leftovers = Find-AppLeftovers -AppEntry $AppEntry -AllInstalledApps $allInstalledNow
    if ($leftovers.Count -gt 0) {
        if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
            Log-Text "[*] Ph$([char]0x00E1)t hi$([char]0x1EC7)n $($leftovers.Count) m$([char]0x1EE5)c r$([char]0x00E1)c / Registry c$([char]0x00F2)n s$([char]0x00F3)t l$([char]0x1EA1)i sau khi g$([char]0x1EE1) b$([char]0x1ECF)."
        }
        $dialogTitle = "D$([char]0x1ECD)n r$([char]0x00E1)c t$([char]0x1ED3)n d$([char]0x01B0) sau khi g$([char]0x1EE1): $($AppEntry.DisplayName)"
        $res = Show-LeftoverReviewDialog -OwnerWindow $OwnerWindow -Items $leftovers -Title $dialogTitle
        if ($res.Confirmed) {
            if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                $freedMb = [math]::Round($res.FreedBytes / 1MB, 2)
                Log-Text "[OK] $([char]0x0110)$([char]0x00E3) d$([char]0x1ECD)n s$([char]0x1EA1)ch $($res.RemovedCount) m$([char]0x1EE5)c t$([char]0x1ED3)n d$([char]0x01B0) (~$freedMb MB)."
            }
        }
    } else {
        if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
            Log-Text "[OK] Tr$([char]0x00EC)nh g$([char]0x1EE1) b$([char]0x1ECF) $([char]0x0111)$([char]0x00E3) d$([char]0x1ECD)n d$([char]0x1EB9)p s$([char]0x1EA1)ch s$([char]0x1EBD), kh$([char]0x00F4)ng ph$([char]0x00E1)t hi$([char]0x1EC7)n r$([char]0x00E1)c t$([char]0x1ED3)n d$([char]0x01B0)."
        }
    }
}
