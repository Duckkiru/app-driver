Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

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
            if ([string]::IsNullOrWhiteSpace($kw)) { continue }
            $isCjk = $kw -match '[\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]'
            if ((-not $isCjk) -and $kw.Length -lt 3) { continue }
            if ($isCjk -and $kw.Length -lt 2) { continue }
            if ($leafName.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                ($parentName -and $parentName.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)) {
                $matchedOwner = $true
                break
            }
        }
        if (-not $matchedOwner) {
            $matchedOwner = [DuckUtil.DeepUninstallerEngine]::VerifyDirectoryExeOwnership($norm, $Keywords)
        }
        if (-not $matchedOwner -and $AppEntry.InstallLocation) {
            $regLoc = $AppEntry.InstallLocation.Trim().TrimEnd('\')
            if ($regLoc.Equals($norm, [System.StringComparison]::OrdinalIgnoreCase) -and $parts.Count -ge 3) {
                $matchedOwner = $true
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
    $cleanName = ($cleanName -replace '[0-9]+(\.[0-9]+)+', '').Trim()

    $cnAliasMap = @{
        "$([char]0x817E)$([char]0x8BAF)" = @("Tencent", "QQ")
        "$([char]0x5FAE)$([char]0x4FE1)" = @("WeChat", "Tencent")
        "$([char]0x767E)$([char]0x5EA6)" = @("Baidu", "BaiduNetdisk")
        "$([char]0x7F51)$([char]0x6613)" = @("NetEase", "CloudMusic")
        "$([char]0x8FC5)$([char]0x96F7)" = @("Thunder", "Xunlei", "Thunder Network")
        "$([char]0x5947)$([char]0x864E)" = @("Qihoo360", "360Safe", "360se6")
        "360"                            = @("360Safe", "Qihoo360", "360se6")
        "$([char]0x91D1)$([char]0x5C71)" = @("Kingsoft", "WPS Office", "kingsoft")
        "$([char]0x641C)$([char]0x72D7)" = @("Sogou", "SogouInput", "SogouPY")
        "$([char]0x54D4)$([char]0x54E9)" = @("Bilibili", "Bililive")
        "$([char]0x6296)$([char]0x97F3)" = @("Douyin", "ByteDance")
        "$([char]0x5B57)$([char]0x8282)" = @("ByteDance", "Douyin")
        "$([char]0x9489)$([char]0x9489)" = @("DingTalk", "Alibaba", "AliWorkbench")
        "$([char]0x963F)$([char]0x91CC)" = @("Alibaba", "AliWorkbench", "DingTalk")
        "$([char]0x7231)$([char]0x5947)$([char]0x827A)" = @("IQIYI", "QyClient")
        "$([char]0x4F18)$([char]0x9177)" = @("Youku", "YoukuClient")
        "$([char]0x9177)$([char]0x72D7)" = @("KuGou", "KuGouMusic")
        "$([char]0x9177)$([char]0x6211)" = @("Kuwo", "kwmusic")
        "$([char]0x9C81)$([char]0x5927)$([char]0x5E08)" = @("LuDaShi", "ComputerZ")
        "$([char]0x96F7)$([char]0x7535)" = @("LDPlayer", "XuanZhi", "leidian", "dnplayer")
        "$([char]0x84DD)$([char]0x53E0)" = @("BlueStacks", "BlueStacks_nxt")
        "2345"                           = @("2345Soft", "2345Pic", "2345Explorer")
        "$([char]0x864E)$([char]0x7259)" = @("Huya", "HuyaClient")
        "$([char]0x6597)$([char]0x9C7C)" = @("Douyu", "DouyuClient")
    }

    $candidateTokens = [System.Collections.Generic.List[string]]::new()
    foreach ($tk in ($cleanName -split '\s+')) {
        $isCjk = $tk -match '[\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]'
        if (($isCjk -and $tk.Length -ge 2) -or ((-not $isCjk) -and $tk.Length -ge 4)) {
            if ($exclusions -notcontains $tk) { $candidateTokens.Add($tk) }
        }
    }
    $isFullCjk = $cleanName -match '[\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]'
    if (($isFullCjk -and $cleanName.Length -ge 2) -or ((-not $isFullCjk) -and $cleanName.Length -ge 4)) {
        if ($exclusions -notcontains $cleanName) { $candidateTokens.Add($cleanName) }
    }

    if ($AppEntry.Id -and $AppEntry.Id -notmatch '^\{?[0-9A-Fa-f\-]{12,}\}?$' -and $AppEntry.Id -notmatch '^MSI') {
        $cleanId = ($AppEntry.Id -replace '_is1$', '').Trim()
        if ($cleanId.Length -ge 3 -and $exclusions -notcontains $cleanId) {
            $candidateTokens.Add($cleanId)
        }
    }

    if ($AppEntry.InstallLocation) {
        $locTrim = $AppEntry.InstallLocation.Trim().TrimEnd('\')
        $locLeaf = [System.IO.Path]::GetFileName($locTrim)
        $genericFolders = @('Program Files', 'Program Files (x86)', 'Programs', 'Apps', 'Games', 'Software', 'Tools', 'Common Files', 'bin', 'Client')
        if ($locLeaf -and $locLeaf.Length -ge 3 -and $genericFolders -notcontains $locLeaf -and $exclusions -notcontains $locLeaf) {
            $candidateTokens.Add($locLeaf)
        }
    }

    $binTokens = [DuckUtil.DeepUninstallerEngine]::ExtractBinaryAndCertTokens($AppEntry.InstallLocation, $AppEntry.UninstallString, "")
    if ($binTokens) {
        foreach ($bt in $binTokens) {
            if ($bt -and $bt.Length -ge 3 -and $exclusions -notcontains $bt) {
                $candidateTokens.Add($bt)
            }
        }
    }

    $combinedSource = "$rawName | $($AppEntry.Publisher) | $($AppEntry.InstallLocation) | $($AppEntry.UninstallString)"
    $vendorFolders = [System.Collections.Generic.List[string]]::new()
    foreach ($cnKey in $cnAliasMap.Keys) {
        if ($combinedSource.IndexOf($cnKey, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            foreach ($mapped in $cnAliasMap[$cnKey]) {
                $candidateTokens.Add($mapped)
                $vendorFolders.Add($mapped)
            }
        }
    }

    $nameKeywords = @($candidateTokens | Select-Object -Unique)
    if ($nameKeywords.Count -eq 0) { return @() }

    $ownerKeywords = [System.Collections.Generic.List[string]]::new()
    foreach ($nk in $nameKeywords) { $ownerKeywords.Add($nk) }
    if (-not [string]::IsNullOrWhiteSpace($AppEntry.Publisher)) {
        $pubClean = ($AppEntry.Publisher -replace '\(.*?\)', '').Trim()
        foreach ($pk in ($pubClean -split '\s+')) {
            $isPkCjk = $pk -match '[\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]'
            if ((($isPkCjk -and $pk.Length -ge 2) -or ($pk.Length -ge 3)) -and $exclusions -notcontains $pk) {
                $ownerKeywords.Add($pk)
            }
        }
    }

    if ($AppEntry.InstallLocation -and (Test-Path -LiteralPath $AppEntry.InstallLocation)) {
        $loc = try { (Resolve-Path -LiteralPath $AppEntry.InstallLocation).Path.TrimEnd('\') } catch { $AppEntry.InstallLocation.Trim().TrimEnd('\') }
        $isSafe = $true
        foreach ($ex in $exclusions) {
            if ($loc -like "*\$ex\*" -or $loc -like "*\$ex") { $isSafe = $false; break }
        }
        if ($isSafe -and (Test-SafeAppDirectoryForCleanup -Path $loc -AppEntry $AppEntry -Keywords $ownerKeywords.ToArray() -AllInstalledApps $AllInstalledApps)) {
            if ($seenPaths.Add($loc)) {
                $dirSize = [DuckUtil.DeepUninstallerEngine]::GetDirectorySizeFast($loc, 4)
                $leftovers.Add([PSCustomObject]@{
                    Type              = "Th$([char]0x01B0) m$([char]0x1EE5)c c$([char]0x00E0)i $([char]0x0111)$([char]0x1EB7)t"
                    Confidence        = "An to$([char]0x00E0)n 100%"
                    AppName           = $AppEntry.DisplayName
                    Path              = $loc
                    SizeBytes         = [long]$dirSize
                    SizeMB            = [math]::Round($dirSize / 1MB, 2)
                    IsRegistry        = $false
                    RegistryValueName = ""
                })
            }
        }
    }

    $folderRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($baseRoot in @($env:APPDATA, $env:LOCALAPPDATA, (Join-Path $env:LOCALAPPDATA "Programs"), "C:\ProgramData")) {
        if ($baseRoot -and (Test-Path -LiteralPath $baseRoot)) {
            $folderRoots.Add($baseRoot)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($AppEntry.Publisher)) {
        $pubClean = ($AppEntry.Publisher -replace '\(.*?\)', '' -replace '(?i)\b(Inc\.?|LLC|Ltd\.?|Corp\.?|Corporation|GmbH|Co\.?)\b', '').Trim(' ', ',', '.')
        if ($pubClean.Length -ge 2 -and $exclusions -notcontains $pubClean) {
            $vendorFolders.Add($pubClean)
        }
    }
    foreach ($vf in ($vendorFolders | Select-Object -Unique)) {
        foreach ($baseRoot in @($env:APPDATA, $env:LOCALAPPDATA, "C:\ProgramData")) {
            if ($baseRoot) {
                $pubSub = Join-Path $baseRoot $vf
                if (Test-Path -LiteralPath $pubSub) { $folderRoots.Add($pubSub) }
            }
        }
    }

    foreach ($root in $folderRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($kw in $nameKeywords) {
            $candidatePath = Join-Path $root $kw
            if (Test-Path -LiteralPath $candidatePath) {
                $fullPath = (Resolve-Path -LiteralPath $candidatePath).Path.TrimEnd('\')
                $isSafe = $true
                foreach ($ex in $exclusions) {
                    if ($fullPath -like "*\$ex\*" -or $fullPath -like "*\$ex") { $isSafe = $false; break }
                }
                if ($isSafe -and $seenPaths.Add($fullPath)) {
                    $dirSize = [DuckUtil.DeepUninstallerEngine]::GetDirectorySizeFast($fullPath, 4)
                    $leftovers.Add([PSCustomObject]@{
                        Type              = "Th$([char]0x01B0) m$([char]0x1EE5)c r$([char]0x00E1)c AppData"
                        Confidence        = "An to$([char]0x00E0)n 100%"
                        AppName           = $AppEntry.DisplayName
                        Path              = $fullPath
                        SizeBytes         = [long]$dirSize
                        SizeMB            = [math]::Round($dirSize / 1MB, 2)
                        IsRegistry        = $false
                        RegistryValueName = ""
                    })
                }
            }
        }
    }

    $crashDumpDir = Join-Path $env:LOCALAPPDATA "CrashDumps"
    if (Test-Path -LiteralPath $crashDumpDir) {
        foreach ($kw in $nameKeywords) {
            try {
                $dumps = [System.IO.Directory]::GetFiles($crashDumpDir, "*$kw*.dmp", [System.IO.SearchOption]::TopDirectoryOnly)
                foreach ($dmp in $dumps) {
                    if ($seenPaths.Add($dmp)) {
                        $dmpSize = (Get-Item -LiteralPath $dmp -ErrorAction SilentlyContinue).Length
                        $leftovers.Add([PSCustomObject]@{
                            Type              = "Crash Dump r$([char]0x00E1)c"
                            Confidence        = "An to$([char]0x00E0)n 100%"
                            AppName           = $AppEntry.DisplayName
                            Path              = $dmp
                            SizeBytes         = [long]$dmpSize
                            SizeMB            = [math]::Round($dmpSize / 1MB, 2)
                            IsRegistry        = $false
                            RegistryValueName = ""
                        })
                    }
                }
            } catch {}
        }
    }

    $shortcutDirs = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('Programs'),
        [Environment]::GetFolderPath('CommonPrograms')
    )
    $wsh = $null
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $targetLocPrefix = if ($AppEntry.InstallLocation) { $AppEntry.InstallLocation.Trim().TrimEnd('\') + "\" } else { "" }
        foreach ($sDir in $shortcutDirs) {
            if (-not $sDir -or -not (Test-Path -LiteralPath $sDir)) { continue }
            $lnks = [System.IO.Directory]::GetFiles($sDir, "*.lnk", [System.IO.SearchOption]::AllDirectories)
            foreach ($lnk in $lnks) {
                try {
                    $lnkName = [System.IO.Path]::GetFileNameWithoutExtension($lnk)
                    $sc = $wsh.CreateShortcut($lnk)
                    $tPath = $sc.TargetPath
                    $matchesApp = $false
                    if ($targetLocPrefix -and $tPath -and $tPath.StartsWith($targetLocPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $matchesApp = $true
                    } elseif ($lnkName.Equals($cleanName, [System.StringComparison]::OrdinalIgnoreCase) -and $tPath -and -not (Test-Path -LiteralPath $tPath)) {
                        $matchesApp = $true
                    }
                    if ($matchesApp -and $seenPaths.Add($lnk)) {
                        $leftovers.Add([PSCustomObject]@{
                            Type              = "Shortcut ch$([char]0x1EBF)t"
                            Confidence        = "An to$([char]0x00E0)n 100%"
                            AppName           = $AppEntry.DisplayName
                            Path              = $lnk
                            SizeBytes         = 0L
                            SizeMB            = 0.0
                            IsRegistry        = $false
                            RegistryValueName = ""
                        })
                    }
                } catch {}
            }
        }
    } catch {} finally {
        if ($null -ne $wsh) {
            try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null } catch {}
            $wsh = $null
        }
    }

    $runKeys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )
    $locPrefixForRun = if ($AppEntry.InstallLocation) { $AppEntry.InstallLocation.Trim().TrimEnd('\') + "\" } else { "" }
    foreach ($rk in $runKeys) {
        if (-not (Test-Path -LiteralPath $rk)) { continue }
        try {
            $props = Get-ItemProperty -LiteralPath $rk -ErrorAction SilentlyContinue
            if ($null -eq $props) { continue }
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) { continue }
                $valStr = [string]$p.Value
                if ([string]::IsNullOrWhiteSpace($valStr)) { continue }
                $isAppRun = $false
                if ($locPrefixForRun -and $valStr.IndexOf($locPrefixForRun, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $isAppRun = $true
                } elseif ($p.Name.Equals($cleanName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $isAppRun = $true
                }
                if ($isAppRun) {
                    $runDisplayPath = "$rk -> [$($p.Name)]"
                    if ($seenPaths.Add($runDisplayPath)) {
                        $leftovers.Add([PSCustomObject]@{
                            Type              = "Startup m$([char]0x1ED3) c$([char]0x00F4)i"
                            Confidence        = "An to$([char]0x00E0)n 100%"
                            AppName           = $AppEntry.DisplayName
                            Path              = $rk
                            SizeBytes         = 0L
                            SizeMB            = 0.0
                            IsRegistry        = $true
                            RegistryValueName = $p.Name
                        })
                    }
                }
            }
        } catch {}
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
                        Type              = "Registry m$([char]0x1ED3) c$([char]0x00F4)i"
                        Confidence        = "An to$([char]0x00E0)n 100%"
                        AppName           = $AppEntry.DisplayName
                        Path              = $regPath
                        SizeBytes         = 0L
                        SizeMB            = 0.0
                        IsRegistry        = $true
                        RegistryValueName = ""
                    })
                }
            }
        }
    }

    if ($AppEntry.RegistryPath -and (Test-Path -LiteralPath $AppEntry.RegistryPath)) {
        if ($seenPaths.Add($AppEntry.RegistryPath)) {
            $leftovers.Add([PSCustomObject]@{
                Type              = "Registry g$([char]0x1EE1) b$([char]0x1ECF) h$([char]0x1ECF)ng"
                Confidence        = "An to$([char]0x00E0)n 100%"
                AppName           = $AppEntry.DisplayName
                Path              = $AppEntry.RegistryPath
                SizeBytes         = 0L
                SizeMB            = 0.0
                IsRegistry        = $true
                RegistryValueName = ""
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
                        Type              = "[Registry m$([char]0x1ED3) c$([char]0x00F4)i]"
                        Confidence        = "An to$([char]0x00E0)n 100%"
                        AppName           = $app.DisplayName
                        Path              = $app.RegistryPath
                        SizeBytes         = 0L
                        SizeMB            = 0.0
                        IsRegistry        = $true
                        RegistryValueName = ""
                    })
                }
            }

            $appLeftovers = Find-AppLeftovers -AppEntry $app -AllInstalledApps $InstalledApps
            foreach ($lo in $appLeftovers) {
                $dedupKey = if ($lo.RegistryValueName) { "$($lo.Path)->$($lo.RegistryValueName)" } else { $lo.Path }
                if ($seenPaths.Add($dedupKey)) {
                    $badgeType = if ($lo.IsRegistry) { "[Registry m$([char]0x1ED3) c$([char]0x00F4)i]" } else { "[Th$([char]0x01B0) m$([char]0x1EE5)c r$([char]0x00E1)c AppData]" }
                    $orphans.Add([PSCustomObject]@{
                        Type              = $badgeType
                        Confidence        = if ($lo.Confidence) { $lo.Confidence } else { "An to$([char]0x00E0)n 100%" }
                        AppName           = $app.DisplayName
                        Path              = $lo.Path
                        SizeBytes         = [long]$lo.SizeBytes
                        SizeMB            = [double]$lo.SizeMB
                        IsRegistry        = [bool]$lo.IsRegistry
                        RegistryValueName = [string]$lo.RegistryValueName
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
                        Type              = "[V$([char]0x1ECF) th$([char]0x01B0) m$([char]0x1EE5)c r$([char]0x1ED7)ng]"
                        Confidence        = "An to$([char]0x00E0)n 100%"
                        AppName           = $dirName
                        Path              = $sd
                        SizeBytes         = [long]$hollowSize
                        SizeMB            = [math]::Round($hollowSize / 1MB, 2)
                        IsRegistry        = $false
                        RegistryValueName = ""
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
                                Type              = "[Th$([char]0x01B0) m$([char]0x1EE5)c r$([char]0x00E1)c AppData]"
                                Confidence        = "An to$([char]0x00E0)n 100%"
                                AppName           = $catApp.Name
                                Path              = $full
                                SizeBytes         = [long]$dirSize
                                SizeMB            = [math]::Round($dirSize / 1MB, 2)
                                IsRegistry        = $false
                                RegistryValueName = ""
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

    $wsh = $null
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
                                    Type              = "[Shortcut ch$([char]0x1EBF)t]"
                                    Confidence        = "An to$([char]0x00E0)n 100%"
                                    AppName           = [System.IO.Path]::GetFileNameWithoutExtension($lnk)
                                    Path              = $lnk
                                    SizeBytes         = 0L
                                    SizeMB            = 0.0
                                    IsRegistry        = $false
                                    RegistryValueName = ""
                                })
                            }
                        }
                    }
                } catch {}
            }
        }
    } catch {} finally {
        if ($null -ne $wsh) {
            try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null } catch {}
            $wsh = $null
        }
    }

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
    $dialog.Width = 920
    $dialog.Height = 580
    $dialog.MinWidth = 760
    $dialog.MinHeight = 440
    if ($OwnerWindow -and ($OwnerWindow -is [System.Windows.Window]) -and $OwnerWindow.IsLoaded) {
        $dialog.Owner = $OwnerWindow
        $dialog.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    } else {
        $dialog.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    }
    $dialog.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0A0E15")
    $dialog.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F1F5F9")
    $dialog.WindowStyle = [System.Windows.WindowStyle]::SingleBorderWindow
    $dialog.UseLayoutRounding = $true
    $dialog.SnapsToDevicePixels = $true

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
        $c4 = New-Object System.Windows.Controls.ColumnDefinition; $c4.Width = [System.Windows.GridLength]::Auto
        $itemGrid.ColumnDefinitions.Add($c0) | Out-Null
        $itemGrid.ColumnDefinitions.Add($c1) | Out-Null
        $itemGrid.ColumnDefinitions.Add($c2) | Out-Null
        $itemGrid.ColumnDefinitions.Add($c3) | Out-Null
        $itemGrid.ColumnDefinitions.Add($c4) | Out-Null

        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.IsChecked = $true
        $cb.Tag = $item
        $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $cb.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $itemGrid.Children.Add($cb) | Out-Null
        $itemCheckBoxes.Add($cb)

        $badgeStack = New-Object System.Windows.Controls.StackPanel
        $badgeStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $badgeStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $badgeStack.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)

        $badgeBorder = New-Object System.Windows.Controls.Border
        $badgeColor = switch -Wildcard ($item.Type) {
            "*Registry*" { "#DC2626" }
            "*Startup*" { "#E11D48" }
            "*R$([char]0x00E1)c AppData*" { "#D97706" }
            "*V$([char]0x1ECF) th$([char]0x01B0) m$([char]0x1EE5)c*" { "#2563EB" }
            "*Shortcut*" { "#7C3AED" }
            "*Crash Dump*" { "#9333EA" }
            default { "#0D9488" }
        }
        $badgeBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($badgeColor)
        $badgeBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $badgeBorder.Padding = New-Object System.Windows.Thickness(6, 2, 6, 2)

        $badgeText = New-Object System.Windows.Controls.TextBlock
        $badgeText.Text = $item.Type
        $badgeText.FontSize = 10.5
        $badgeText.FontWeight = [System.Windows.FontWeights]::SemiBold
        $badgeText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
        $badgeBorder.Child = $badgeText
        $badgeStack.Children.Add($badgeBorder) | Out-Null

        $confBorder = New-Object System.Windows.Controls.Border
        $confBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#064E3B")
        $confBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#059669")
        $confBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $confBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $confBorder.Padding = New-Object System.Windows.Thickness(5, 1, 5, 1)
        $confBorder.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0)
        $confText = New-Object System.Windows.Controls.TextBlock
        $confText.Text = if ($item.Confidence) { $item.Confidence } else { "An to$([char]0x00E0)n 100%" }
        $confText.FontSize = 9.5
        $confText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#6EE7B7")
        $confBorder.Child = $confText
        $badgeStack.Children.Add($confBorder) | Out-Null

        [System.Windows.Controls.Grid]::SetColumn($badgeStack, 1)
        $itemGrid.Children.Add($badgeStack) | Out-Null

        $infoPanel = New-Object System.Windows.Controls.StackPanel
        $infoPanel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $appBlock = New-Object System.Windows.Controls.TextBlock
        $appBlock.Text = $item.AppName
        $appBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
        $appBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0")
        $infoPanel.Children.Add($appBlock) | Out-Null

        $displayPathText = if ($item.RegistryValueName) { "$($item.Path) [Value: $($item.RegistryValueName)]" } else { $item.Path }
        $pathBlock = New-Object System.Windows.Controls.TextBlock
        $pathBlock.Text = $displayPathText
        $pathBlock.FontSize = 11
        $pathBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
        $pathBlock.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $pathBlock.ToolTip = $displayPathText
        $infoPanel.Children.Add($pathBlock) | Out-Null

        [System.Windows.Controls.Grid]::SetColumn($infoPanel, 2)
        $itemGrid.Children.Add($infoPanel) | Out-Null

        $sizeBlock = New-Object System.Windows.Controls.TextBlock
        $sizeBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $sizeBlock.FontSize = 11.5
        $sizeBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
        $sizeBlock.Margin = New-Object System.Windows.Thickness(10, 0, 8, 0)
        if ($item.IsRegistry) {
            $sizeBlock.Text = "Registry"
            $sizeBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
        } else {
            $sizeBlock.Text = "$([string]::Format('{0:N2}', $item.SizeMB)) MB"
            $sizeBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
        }
        [System.Windows.Controls.Grid]::SetColumn($sizeBlock, 3)
        $itemGrid.Children.Add($sizeBlock) | Out-Null

        $btnOpenLoc = New-Object System.Windows.Controls.Button
        $btnOpenLoc.Content = "M$([char]0x1EDF) v$([char]0x1ECB) tr$([char]0x00ED)"
        $btnOpenLoc.FontSize = 10.5
        $btnOpenLoc.Padding = New-Object System.Windows.Thickness(8, 3, 8, 3)
        $btnOpenLoc.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $btnOpenLoc.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $btnOpenLoc.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1")
        $btnOpenLoc.Tag = $item
        $btnOpenLoc.Add_Click({
            param($sender, $e)
            $tg = $sender.Tag
            if ($null -eq $tg) { return }
            try {
                if ($tg.IsRegistry) {
                    $rawKey = $tg.Path -replace '^HKCU:\\', 'HKEY_CURRENT_USER\' -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
                    $regApplet = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit"
                    if (-not (Test-Path -LiteralPath $regApplet)) {
                        New-Item -Path $regApplet -Force | Out-Null
                    }
                    Set-ItemProperty -LiteralPath $regApplet -Name "LastKey" -Value "Computer\$rawKey" -ErrorAction SilentlyContinue
                    Start-Process "regedit.exe"
                } else {
                    if (Test-Path -LiteralPath $tg.Path) {
                        Start-Process "explorer.exe" -ArgumentList "/select,`"$($tg.Path)`""
                    }
                }
            } catch {}
        })
        [System.Windows.Controls.Grid]::SetColumn($btnOpenLoc, 4)
        $itemGrid.Children.Add($btnOpenLoc) | Out-Null

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

    $leftBottomStack = New-Object System.Windows.Controls.StackPanel
    $leftBottomStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $summaryText = New-Object System.Windows.Controls.TextBlock
    $summaryText.FontSize = 12
    $summaryText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $summaryText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0")

    $chkRecycleBin = New-Object System.Windows.Controls.CheckBox
    $chkRecycleBin.IsChecked = $true
    $chkRecycleBin.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
    $chkRecycleBin.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
    $chkRecycleBin.Content = "Chuy$([char]0x1EC3)n file/th$([char]0x01B0) m$([char]0x1EE5)c v$([char]0x00E0)o Th$([char]0x00F9)ng r$([char]0x00E1)c Windows (An to$([char]0x00E0)n, kh$([char]0x00F4)i ph$([char]0x1EE5)c $([char]0x0111)$([char]0x01B0)$([char]0x1EE3)c n$([char]0x1EBF)u c$([char]0x1EA7)n)"

    $leftBottomStack.Children.Add($summaryText) | Out-Null
    $leftBottomStack.Children.Add($chkRecycleBin) | Out-Null

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

    [System.Windows.Controls.Grid]::SetColumn($leftBottomStack, 0)
    $bottomGrid.Children.Add($leftBottomStack) | Out-Null

    $btnStack = New-Object System.Windows.Controls.StackPanel
    $btnStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $btnStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

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

    $dialogResult = [PSCustomObject]@{ Confirmed = $false; RemovedCount = 0; FreedBytes = 0L; RebootScheduled = 0 }

    $btnDelete = New-Object System.Windows.Controls.Button
    $btnDelete.Content = "X$([char]0x00F3)a S$([char]0x1EA1)ch M$([char]0x1EE5)c $([char]0x0110)$([char]0x00E3) Ch$([char]0x1ECD)n"
    $btnDelete.Padding = New-Object System.Windows.Thickness(14, 6, 14, 6)
    $btnDelete.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#991B1B")
    $btnDelete.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FEE2E2")
    $btnDelete.FontWeight = [System.Windows.FontWeights]::Bold
    $btnDelete.Add_Click({
        $checkedItems = @($itemCheckBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
        if ($checkedItems.Count -eq 0) {
            [System.Windows.MessageBox]::Show($dialog, "B$([char]0x1EA1)n ch$([char]0x01B0)a ch$([char]0x1ECD)n m$([char]0x1EE5)c n$([char]0x00E0)o $([char]0x0111)$([char]0x1EC3) d$([char]0x1ECD)n s$([char]0x1EA1)ch.", "Th$([char]0x00F4)ng b$([char]0x00E1)o", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            return
        }

        $useRecycle = [bool]$chkRecycleBin.IsChecked
        $removed = 0
        $freed = 0L
        $rebootTotal = 0

        foreach ($ci in $checkedItems) {
            try {
                if ($ci.IsRegistry) {
                    if ($ci.RegistryValueName) {
                        if (Test-Path -LiteralPath $ci.Path) {
                            Remove-ItemProperty -LiteralPath $ci.Path -Name $ci.RegistryValueName -Force -ErrorAction Stop
                            $removed++
                            if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                                Log-Text "[D$([char]0x1ECC)N R$([char]0x00C1)C] $([char]0x0110)$([char]0x00E3) x$([char]0x00F3)a Startup Registry: $($ci.Path) [$($ci.RegistryValueName)]"
                            }
                        }
                    } elseif (Test-Path -LiteralPath $ci.Path) {
                        Remove-Item -LiteralPath $ci.Path -Recurse -Force -ErrorAction Stop
                        $removed++
                        if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                            Log-Text "[D$([char]0x1ECC)N R$([char]0x00C1)C] $([char]0x0110)$([char]0x00E3) x$([char]0x00F3)a Registry: $($ci.Path)"
                        }
                    }
                } elseif (Test-Path -LiteralPath $ci.Path) {
                    $deletedOk = $false
                    if ($useRecycle) {
                        try {
                            $itemObj = Get-Item -LiteralPath $ci.Path -Force -ErrorAction Stop
                            if ($itemObj.PSIsContainer) {
                                [DuckUtil.DeepUninstallerEngine]::StopProcessesInDirectory($ci.Path) | Out-Null
                                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($ci.Path, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                            } else {
                                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($ci.Path, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                            }
                            $deletedOk = $true
                        } catch {
                            $deletedOk = $false
                        }
                    }

                    if (-not $deletedOk) {
                        $rbCount = 0
                        $deletedOk = [DuckUtil.DeepUninstallerEngine]::ForceDeleteDirectory($ci.Path, [ref]$rbCount)
                        $rebootTotal += $rbCount
                    }

                    if ($deletedOk) {
                        $removed++
                        $freed += $ci.SizeBytes
                        if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                            Log-Text "[D$([char]0x1ECC)N R$([char]0x00C1)C] $([char]0x0110)$([char]0x00E3) d$([char]0x1ECD)n s$([char]0x1EA1)ch: $($ci.Type) - $($ci.Path)"
                        }
                    }
                }
            } catch {
                if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                    Log-Text "[!] L$([char]0x1ED7)i khi x$([char]0x00F3)a $($ci.Path): $($_.Exception.Message)"
                }
            }
        }

        if ($rebootTotal -gt 0 -and (Get-Command Log-Text -ErrorAction SilentlyContinue)) {
            Log-Text "[*] $([char]0x0110)$([char]0x00E3) $([char]0x0111)$([char]0x1EB7)t l$([char]0x1ECB)ch x$([char]0x00F3)a $rebootTotal file $([char]0x0111)ang b$([char]0x1ECB) kh$([char]0x00F3)a ngay khi Windows kh$([char]0x1EDF)i $([char]0x0111)$([char]0x1ED9)ng l$([char]0x1EA1)i (MoveFileEx)."
        }

        $dialogResult.Confirmed = $true
        $dialogResult.RemovedCount = $removed
        $dialogResult.FreedBytes = $freed
        $dialogResult.RebootScheduled = $rebootTotal
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

    $safeLoc = ""
    if ($AppEntry.InstallLocation -and (Test-Path -LiteralPath $AppEntry.InstallLocation)) {
        $loc = try { (Resolve-Path -LiteralPath $AppEntry.InstallLocation).Path.TrimEnd('\') } catch { $AppEntry.InstallLocation.Trim().TrimEnd('\') }
        if (Test-SafeAppDirectoryForCleanup -Path $loc -AppEntry $AppEntry -AllInstalledApps $allInstalledNow) {
            $safeLoc = $loc
            $svcCount = [DuckUtil.DeepUninstallerEngine]::DisableAndRemoveServicesInDirectory($loc)
            if ($svcCount -gt 0 -and (Get-Command Log-Text -ErrorAction SilentlyContinue)) {
                Log-Text "[*] $([char]0x0110)$([char]0x00E3) v$([char]0x00F4) hi$([char]0x1EC7)u h$([char]0x00F3)a & g$([char]0x1EE1) $svcCount Service / Kernel Driver ng$([char]0x1EA7)m trong: $loc"
            }
            $taskCount = [DuckUtil.DeepUninstallerEngine]::RemoveScheduledTasksInDirectory($loc)
            if ($taskCount -gt 0 -and (Get-Command Log-Text -ErrorAction SilentlyContinue)) {
                Log-Text "[*] $([char]0x0110)$([char]0x00E3) x$([char]0x00F3)a $taskCount Scheduled Task t$([char]0x1EF1) kh$([char]0x1EDF)i $([char]0x0111)$([char]0x1ED9)ng l$([char]0x1EA1)i trong: $loc"
            }
            $killedCount = [DuckUtil.DeepUninstallerEngine]::StopProcessesInDirectory($loc)
            if ($killedCount -gt 0 -and (Get-Command Log-Text -ErrorAction SilentlyContinue)) {
                Log-Text "[*] $([char]0x0110)$([char]0x00E3) $([char]0x0111)$([char]0x00F3)ng b$([char]0x0103)ng (NtSuspendProcess) & t$([char]0x1EAF)t $killedCount ti$([char]0x1EBF)n tr$([char]0x00EC)nh trong: $loc"
            }
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

    if ($safeLoc -and (Test-Path -LiteralPath $safeLoc)) {
        [DuckUtil.DeepUninstallerEngine]::DisableAndRemoveServicesInDirectory($safeLoc) | Out-Null
        [DuckUtil.DeepUninstallerEngine]::RemoveScheduledTasksInDirectory($safeLoc) | Out-Null
        [DuckUtil.DeepUninstallerEngine]::StopProcessesInDirectory($safeLoc) | Out-Null
    }

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
