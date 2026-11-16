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

function Resolve-PathSafe {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path.TrimEnd('\')
    } catch {
        return $null
    }
}

function Get-DirectoriesSafe {
    param([string]$RootPath)
    if ([string]::IsNullOrWhiteSpace($RootPath)) { return @() }
    try {
        return [System.IO.Directory]::GetDirectories($RootPath)
    } catch {
        return @()
    }
}

function Get-FilesRecursiveSafe {
    param(
        [string]$RootPath,
        [string]$SearchPattern = "*"
    )
    $results = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($RootPath) -or -not (Test-Path -LiteralPath $RootPath)) {
        return @()
    }
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($RootPath)
    while ($queue.Count -gt 0) {
        if ($script:isWindowClosing) { break }
        $dir = $queue.Dequeue()
        try {
            foreach ($f in [System.IO.Directory]::GetFiles($dir, $SearchPattern, [System.IO.SearchOption]::TopDirectoryOnly)) {
                $results.Add($f)
            }
        } catch {}
        try {
            foreach ($sub in [System.IO.Directory]::GetDirectories($dir)) {
                $isReparse = try {
                    ([System.IO.File]::GetAttributes($sub) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
                } catch { $true }
                if (-not $isReparse) {
                    $queue.Enqueue($sub)
                }
            }
        } catch {}
    }
    return @($results)
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
    $rawTrim = $Path.Trim()
    if ($rawTrim.StartsWith("\\")) { return $false }
    if ($rawTrim -notmatch '^[A-Za-z]:\\') { return $false }
    $norm = try { [System.IO.Path]::GetFullPath($rawTrim).TrimEnd('\') } catch { return $false }
    if ($norm -match '^[A-Za-z]:$') { return $false }
    if ($norm -match '^[A-Za-z]:\\Users\\[^\\]+$') { return $false }

    $protectedRaw = @(
        $env:USERPROFILE,
        $env:PUBLIC,
        (Join-Path $env:SystemDrive "Users\Default"),
        $env:LOCALAPPDATA,
        $env:APPDATA,
        $env:ProgramData,
        $(if ($env:ProgramData) { Join-Path $env:ProgramData "Microsoft" } else { "" }),
        $env:SystemRoot,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        ${env:CommonProgramFiles},
        ${env:CommonProgramFiles(x86)},
        $env:TEMP
    )
    foreach ($pr in $protectedRaw) {
        if (-not [string]::IsNullOrWhiteSpace($pr)) {
            $prNorm = try { [System.IO.Path]::GetFullPath($pr).TrimEnd('\') } catch { $pr.Trim().TrimEnd('\') }
            if ($norm.Equals($prNorm, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
    }

    $parts = @($norm -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -lt 2) { return $false }

    $genericContainers = @(
        'Windows', 'System32', 'SysWOW64', 'Program Files', 'Program Files (x86)',
        'ProgramData', 'Programs', 'Users', 'Public', 'Default', 'Microsoft', 'AppData', 'Local', 'Roaming', 'LocalLow',
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
        if (-not $matchedOwner -and $AppEntry.PSObject.Properties['DataLocation'] -and $AppEntry.DataLocation) {
            $dataRegLoc = $AppEntry.DataLocation.Trim().TrimEnd('\')
            if ($dataRegLoc.Equals($norm, [System.StringComparison]::OrdinalIgnoreCase) -and $parts.Count -ge 2) {
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
            $otherDataLoc = if ($other.PSObject.Properties['DataLocation'] -and $other.DataLocation) { $other.DataLocation.Trim().TrimEnd('\') } else { "" }
            if ($otherDataLoc) {
                if ($otherDataLoc.Equals($norm, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $otherDataLoc.StartsWith($normWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $false
                }
            }
        }
    }

    return $true
}

function Get-NormalizedAppIdentity {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
    $s = $Name -replace '\((?i:user|system|machine|64-bit|32-bit|x64|x86|arm64|lts|preview|portable)[^)]*\)', ''
    $s = $s -replace '\b(?i:x64|x86|arm64|64-bit|32-bit|user\s+installer|system\s+installer)\b', ''
    $s = $s -replace '\b\d+(?:\.\d+)+\b', ''
    $s = ($s -replace '[^a-zA-Z0-9\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]+', ' ').Trim().ToLowerInvariant()
    return $s
}

function Test-PathClaimedByActiveApp {
    param(
        [string]$CandidateName,
        $ActiveApps
    )
    if ([string]::IsNullOrWhiteSpace($CandidateName) -or -not $ActiveApps) { return $false }
    $candNorm = Get-NormalizedAppIdentity $CandidateName
    $candTrim = $CandidateName.Trim()
    foreach ($act in $ActiveApps) {
        if ($null -eq $act) { continue }
        $actNorm = Get-NormalizedAppIdentity $act.DisplayName
        if ($candNorm -and $actNorm) {
            if ($actNorm.Equals($candNorm, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
            if ($candNorm.Length -ge 3 -and $actNorm -match ('(?i)(?:^|\s)' + [regex]::Escape($candNorm) + '(?:\s|$)')) { return $true }
        }
        if ($act.InstallLocation) {
            $actLocLeaf = [System.IO.Path]::GetFileName($act.InstallLocation.Trim().TrimEnd('\'))
            if ($actLocLeaf -and $actLocLeaf.Equals($candTrim, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        if ($act.Publisher) {
            $pubNorm = Get-NormalizedAppIdentity $act.Publisher
            if ($candNorm -and $pubNorm) {
                if ($pubNorm.Equals($candNorm, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
                if ($candNorm.Length -ge 3 -and $pubNorm -match ('(?i)(?:^|\s)' + [regex]::Escape($candNorm) + '(?:\s|$)')) { return $true }
            }
        }
    }
    return $false
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

    $selfNorm = Get-NormalizedAppIdentity $rawName
    $activeApps = [System.Collections.Generic.List[object]]::new()
    $hasActiveSameIdentity = $false
    if ($AllInstalledApps) {
        foreach ($other in $AllInstalledApps) {
            if ($null -eq $other -or $other.IsBrokenOrphan) { continue }
            if ($other.Id -eq $AppEntry.Id -and $other.RegistryPath -eq $AppEntry.RegistryPath) { continue }
            $activeApps.Add($other)
            $otherNorm = Get-NormalizedAppIdentity $other.DisplayName
            if ($selfNorm -and $otherNorm -and $selfNorm.Equals($otherNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
                $hasActiveSameIdentity = $true
            }
        }
    }

    if ($hasActiveSameIdentity) {
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

    $genericStopWords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($sw in @(
        'visual', 'studio', 'code', 'desktop', 'client', 'server', 'runtime', 'manager',
        'player', 'viewer', 'editor', 'reader', 'writer', 'updater', 'helper', 'launcher',
        'installer', 'setup', 'portable', 'pro', 'plus', 'lite', 'home', 'enterprise',
        'community', 'edition', 'ultimate', 'express', 'standard', 'core', 'tool', 'tools',
        'app', 'apps', 'program', 'programs', 'software', 'game', 'games', 'system',
        'windows', 'microsoft', 'google', 'adobe', 'apple', 'intel', 'nvidia', 'oracle',
        'python', 'java', 'dotnet', 'assistant', 'companion', 'service', 'services',
        'driver', 'drivers', 'agent', 'remote', 'connect', 'sync', 'cloud', 'workplace',
        'browser', 'terminal', 'console', 'shell', 'data', 'files', 'media', 'audio',
        'video', 'photo', 'image', 'chat', 'mail', 'note', 'notes', 'office', 'suite',
        'free', 'open', 'auto', 'smart', 'fast', 'easy', 'mini', 'super', 'ultra', 'mega',
        'beta', 'alpha', 'preview', 'nightly', 'user', 'machine', '64-bit', '32-bit', 'x64', 'x86'
    )) {
        $genericStopWords.Add($sw) | Out-Null
    }

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
    $isFullCjk = $cleanName -match '[\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]'
    if (($isFullCjk -and $cleanName.Length -ge 2) -or ((-not $isFullCjk) -and $cleanName.Length -ge 4)) {
        if ($exclusions -notcontains $cleanName -and -not $genericStopWords.Contains($cleanName)) {
            $candidateTokens.Add($cleanName)
        }
    }
    $rawSubTokens = @($cleanName -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($rawSubTokens.Count -gt 1) {
        foreach ($tk in $rawSubTokens) {
            $isCjk = $tk -match '[\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]'
            if (($isCjk -and $tk.Length -ge 2) -or ((-not $isCjk) -and $tk.Length -ge 5)) {
                if ($exclusions -notcontains $tk -and -not $genericStopWords.Contains($tk)) {
                    $candidateTokens.Add($tk)
                }
            }
        }
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

    if ($AppEntry.PSObject.Properties['DataLocation'] -and $AppEntry.DataLocation -and (Test-Path -LiteralPath $AppEntry.DataLocation)) {
        $dataLoc = try { (Resolve-Path -LiteralPath $AppEntry.DataLocation).Path.TrimEnd('\') } catch { $AppEntry.DataLocation.Trim().TrimEnd('\') }
        $isDataSafe = $true
        foreach ($ex in $exclusions) {
            if ($dataLoc -like "*\$ex\*" -or $dataLoc -like "*\$ex") { $isDataSafe = $false; break }
        }
        if ($isDataSafe -and (Test-SafeAppDirectoryForCleanup -Path $dataLoc -AppEntry $AppEntry -Keywords $ownerKeywords.ToArray() -AllInstalledApps $AllInstalledApps)) {
            if ($seenPaths.Add($dataLoc)) {
                $dataSize = [DuckUtil.DeepUninstallerEngine]::GetDirectorySizeFast($dataLoc, 4)
                $leftovers.Add([PSCustomObject]@{
                    Type              = "Th$([char]0x01B0) m$([char]0x1EE5)c d$([char]0x1EEF) li$([char]0x1EC7)u Game/App"
                    Confidence        = "An to$([char]0x00E0)n 100%"
                    AppName           = $AppEntry.DisplayName
                    Path              = $dataLoc
                    SizeBytes         = [long]$dataSize
                    SizeMB            = [math]::Round($dataSize / 1MB, 2)
                    IsRegistry        = $false
                    RegistryValueName = ""
                })
            }
        }
    }

    $localLowRoot = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE "AppData\LocalLow" } else { "" }
    $folderRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($baseRoot in @($env:APPDATA, $env:LOCALAPPDATA, $localLowRoot, (Join-Path $env:LOCALAPPDATA "Programs"), "C:\ProgramData")) {
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
        foreach ($baseRoot in @($env:APPDATA, $env:LOCALAPPDATA, $localLowRoot, "C:\ProgramData")) {
            if ($baseRoot) {
                $pubSub = Join-Path $baseRoot $vf
                if (Test-Path -LiteralPath $pubSub) { $folderRoots.Add($pubSub) }
            }
        }
    }

    foreach ($root in $folderRoots) {
        if ($script:isWindowClosing) { break }
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($kw in $nameKeywords) {
            if ($script:isWindowClosing) { break }
            if ($genericStopWords.Contains($kw)) { continue }
            if (Test-PathClaimedByActiveApp -CandidateName $kw -ActiveApps $activeApps) { continue }
            $candidatePath = Join-Path $root $kw
            if (Test-Path -LiteralPath $candidatePath) {
                $fullPath = Resolve-PathSafe -Path $candidatePath
                if (-not $fullPath) { continue }
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
            if ($script:isWindowClosing) { break }
            if (-not $sDir -or -not (Test-Path -LiteralPath $sDir)) { continue }
            $lnks = Get-FilesRecursiveSafe -RootPath $sDir -SearchPattern "*.lnk"
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
            if ($genericStopWords.Contains($kw)) { continue }
            if (Test-PathClaimedByActiveApp -CandidateName $kw -ActiveApps $activeApps) { continue }
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

    $activeApps = [System.Collections.Generic.List[object]]::new()
    $activeNormIdentities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($ia in $InstalledApps) {
        if (-not $ia.IsBrokenOrphan) {
            $activeApps.Add($ia)
            $normIa = Get-NormalizedAppIdentity $ia.DisplayName
            if ($normIa) { $activeNormIdentities.Add($normIa) | Out-Null }
        }
    }

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

            $brokenNorm = Get-NormalizedAppIdentity $app.DisplayName
            if ($brokenNorm -and $activeNormIdentities.Contains($brokenNorm)) {
                continue
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
        if (-not $ia.IsBrokenOrphan) {
            if (-not [string]::IsNullOrWhiteSpace($ia.InstallLocation)) {
                $activeInstallLocs.Add($ia.InstallLocation.Trim().TrimEnd('\'))
            }
            if ($ia.PSObject.Properties['DataLocation'] -and -not [string]::IsNullOrWhiteSpace($ia.DataLocation)) {
                $activeInstallLocs.Add($ia.DataLocation.Trim().TrimEnd('\'))
            }
        }
    }

    foreach ($pRoot in $programRoots) {
        if ($script:isWindowClosing) { break }
        if (-not (Test-Path -LiteralPath $pRoot)) { continue }
        $subDirs = Get-DirectoriesSafe -RootPath $pRoot
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
        $installedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($ia in $InstalledApps) {
            if (-not $ia.IsBrokenOrphan) {
                $installedNames.Add($ia.DisplayName) | Out-Null
                if ($ia.Id) { $installedIds.Add($ia.Id) | Out-Null }
            }
        }

        $catalogInstalledIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $uiBorders = Get-Variable -Name allItemBorders -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if ($uiBorders) {
            foreach ($b in $uiBorders) {
                if ($b.Tag -and $b.Tag.Status -in @("LATEST", "OUTDATED") -and $b.Tag.App) {
                    if ($b.Tag.App.ID) { $catalogInstalledIds.Add($b.Tag.App.ID) | Out-Null }
                    if ($b.Tag.DetectedId) { $catalogInstalledIds.Add($b.Tag.DetectedId) | Out-Null }
                }
            }
        }

        $appDataRoots = @($env:APPDATA, $env:LOCALAPPDATA)
        foreach ($catApp in $CatalogApps) {
            if ($script:isWindowClosing) { break }
            if ($catApp.ID -and $catalogInstalledIds.Contains($catApp.ID)) { continue }

            $catName = ($catApp.Name -replace '\(.*?\)', '').Trim()
            if ($catName.Length -lt 5) { continue }

            $candidateDirs = $null
            foreach ($ar in $appDataRoots) {
                if ([string]::IsNullOrWhiteSpace($ar)) { continue }
                $cand = [System.IO.Path]::Combine($ar, $catName)
                if ([System.IO.Directory]::Exists($cand)) {
                    if ($null -eq $candidateDirs) { $candidateDirs = [System.Collections.Generic.List[string]]::new() }
                    $candidateDirs.Add($cand)
                }
            }
            if ($null -eq $candidateDirs) { continue }

            $catNorm = Get-NormalizedAppIdentity $catApp.Name
            $isInstalled = $false
            if ($catNorm -and $activeNormIdentities.Contains($catNorm)) { $isInstalled = $true }
            if (-not $isInstalled -and $catApp.ID -and $installedIds.Contains($catApp.ID)) { $isInstalled = $true }
            if (-not $isInstalled) {
                foreach ($inName in $installedNames) {
                    if ($inName.IndexOf($catName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $isInstalled = $true
                        break
                    }
                }
            }
            if (-not $isInstalled -and $catApp.Aliases) {
                foreach ($al in $catApp.Aliases) {
                    if ([string]::IsNullOrWhiteSpace($al)) { continue }
                    $alNorm = Get-NormalizedAppIdentity $al
                    if ($alNorm -and $activeNormIdentities.Contains($alNorm)) {
                        $isInstalled = $true
                        break
                    }
                    foreach ($inName in $installedNames) {
                        if ($inName.IndexOf($al, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                            $isInstalled = $true
                            break
                        }
                    }
                    if ($isInstalled) { break }
                }
            }
            if (-not $isInstalled -and (Test-PathClaimedByActiveApp -CandidateName $catName -ActiveApps $activeApps)) {
                $isInstalled = $true
            }
            if (-not $isInstalled) {
                foreach ($cand in $candidateDirs) {
                    if ($script:isWindowClosing) { break }
                    $full = Resolve-PathSafe -Path $cand
                    if (-not $full) { continue }
                    if (([DuckUtil.DeepUninstallerEngine]::GetHollowDirectorySize($full, 3, 52428800L)) -lt 0L) {
                        continue
                    }
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
            if ($script:isWindowClosing) { break }
            if ([string]::IsNullOrWhiteSpace($dp) -or -not [System.IO.Directory]::Exists($dp)) { continue }
            $lnks = Get-FilesRecursiveSafe -RootPath $dp -SearchPattern "*.lnk"
            foreach ($lnk in $lnks) {
                try {
                    $sc = $wsh.CreateShortcut($lnk)
                    $target = $sc.TargetPath
                    if ($target -and $target -match '^[A-Za-z]:\\' -and $target.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
                        if (-not [System.IO.File]::Exists($target)) {
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

    if ($script:isWindowClosing -or $null -eq $Items -or $Items.Count -eq 0) {
        return [PSCustomObject]@{ Confirmed = $false; RemovedCount = 0; FreedBytes = 0L }
    }

    $dialog = New-Object System.Windows.Window
    $dialog.Title = $Title
    $dialog.Width = 920
    $dialog.Height = 580
    $dialog.MinWidth = 760
    $dialog.MinHeight = 440
    $dialog.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    $canAttachOwner = $false
    if ($OwnerWindow -and ($OwnerWindow -is [System.Windows.Window]) -and -not $script:isWindowClosing) {
        try {
            if ($OwnerWindow.IsLoaded -and $OwnerWindow.IsVisible) {
                $src = [System.Windows.PresentationSource]::FromVisual($OwnerWindow)
                $hwndSrc = $src -as [System.Windows.Interop.HwndSource]
                $ownerHwnd = (New-Object System.Windows.Interop.WindowInteropHelper($OwnerWindow)).Handle
                if ($null -ne $hwndSrc -and (-not $hwndSrc.IsDisposed) -and $ownerHwnd -ne [IntPtr]::Zero) {
                    $canAttachOwner = $true
                }
            }
        } catch {
            $canAttachOwner = $false
        }
    }
    if ($canAttachOwner) {
        try {
            $dialog.Owner = $OwnerWindow
            $dialog.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
        } catch {
            try { $dialog.Owner = $null } catch {}
            $dialog.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
        }
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
        $itemBorder.CornerRadius = New-Object System.Windows.CornerRadius(2)
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
            $safeSizeMb = if ($null -ne $item.SizeMB) { try { [double]$item.SizeMB } catch { 0.0 } } else { 0.0 }
            $sizeBlock.Text = "$([string]::Format('{0:N2}', $safeSizeMb)) MB"
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
            if (Get-Command "Show-OwnedMessageBox" -ErrorAction SilentlyContinue) {
                Show-OwnedMessageBox -Text "B$([char]0x1EA1)n ch$([char]0x01B0)a ch$([char]0x1ECD)n m$([char]0x1EE5)c n$([char]0x00E0)o $([char]0x0111)$([char]0x1EC3) d$([char]0x1ECD)n s$([char]0x1EA1)ch." -Caption "Th$([char]0x00F4)ng b$([char]0x00E1)o" -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) -Icon ([System.Windows.Forms.MessageBoxIcon]::Information) -OwnerWindowOverride $dialog | Out-Null
            } else {
                [System.Windows.MessageBox]::Show($dialog, "B$([char]0x1EA1)n ch$([char]0x01B0)a ch$([char]0x1ECD)n m$([char]0x1EE5)c n$([char]0x00E0)o $([char]0x0111)$([char]0x1EC3) d$([char]0x1ECD)n s$([char]0x1EA1)ch.", "Th$([char]0x00F4)ng b$([char]0x00E1)o", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            }
            return
        }

        $useRecycle = [bool]$chkRecycleBin.IsChecked
        $removed = 0
        $freed = 0L
        $rebootTotal = 0

        $btnDelete.IsEnabled = $false
        try {
            foreach ($ci in $checkedItems) {
                if ($script:isWindowClosing) { break }
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
        } finally {
            $btnDelete.IsEnabled = $true
        }
    })
    $btnStack.Children.Add($btnDelete) | Out-Null

    [System.Windows.Controls.Grid]::SetColumn($btnStack, 1)
    $bottomGrid.Children.Add($btnStack) | Out-Null

    $bottomBar.Child = $bottomGrid
    [System.Windows.Controls.Grid]::SetRow($bottomBar, 2)
    $rootGrid.Children.Add($bottomBar) | Out-Null

    $dialog.Content = $rootGrid
    if (-not $script:isWindowClosing) {
        try {
            $null = $dialog.ShowDialog()
        } catch {} finally {
            try { $dialog.Owner = $null } catch {}
        }
    }

    return $dialogResult
}

function Resolve-SilentUninstallPlan {
    param([Parameter(Mandatory = $true)]$AppEntry)

    $hasExplicitQuiet = -not [string]::IsNullOrWhiteSpace($AppEntry.QuietUninstallString)
    $rawCmd = if ($hasExplicitQuiet) {
        $AppEntry.QuietUninstallString.Trim()
    } elseif (-not [string]::IsNullOrWhiteSpace($AppEntry.UninstallString)) {
        $AppEntry.UninstallString.Trim()
    } else {
        ""
    }

    if ([string]::IsNullOrWhiteSpace($rawCmd)) {
        return [PSCustomObject]@{
            Mode                = "None"
            Exe                 = ""
            Args                = ""
            Framework           = ""
            AddedSilentFlags    = $false
            IsSilent            = $false
            IsLikelyDarkPattern = $false
        }
    }

    if ($rawCmd.IndexOf("msiexec", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $msiId = if (Get-Command Get-MsiProductCodeFromCommand -ErrorAction SilentlyContinue) {
            Get-MsiProductCodeFromCommand -UninstallCommand $rawCmd -FallbackId $AppEntry.Id
        } else {
            $AppEntry.Id
        }
        return [PSCustomObject]@{
            Mode                = "MSI"
            Exe                 = "msiexec.exe"
            Args                = "/x `"$msiId`" /qn /norestart"
            MsiId               = $msiId
            Framework           = "MSI"
            AddedSilentFlags    = $true
            IsSilent            = $true
            IsLikelyDarkPattern = $false
        }
    }

    $cmdParts = if (Get-Command Split-CommandLineExecutableAndArgs -ErrorAction SilentlyContinue) {
        Split-CommandLineExecutableAndArgs -CommandLine $rawCmd
    } else {
        $spParts = $rawCmd -split '\s+', 2
        [PSCustomObject]@{ Exe = $spParts[0].Trim('"'); Args = if ($spParts.Count -gt 1) { $spParts[1] } else { "" } }
    }

    $exe = [string]$cmdParts.Exe
    $origArgs = if ($null -eq $cmdParts.Args) { "" } else { ([string]$cmdParts.Args).Trim() }
    $missingExe = ($exe -match '^[A-Za-z]:\\') -and (-not [System.IO.File]::Exists($exe))
    if ($missingExe) {
        return [PSCustomObject]@{
            Mode                = "MissingExe"
            Exe                 = $exe
            Args                = $origArgs
            Framework           = ""
            AddedSilentFlags    = $false
            IsSilent            = $false
            IsLikelyDarkPattern = $false
        }
    }

    $framework = ""
    $deepType = "DuckUtil.DeepUninstallerEngine" -as [type]
    if ($deepType -and $null -ne $deepType.GetMethod("DetectInstallerFramework")) {
        $framework = [string]$deepType::DetectInstallerFramework($exe)
    }

    $newArgs = $origArgs
    $addedFlags = $false
    $isSilent = $false

    switch ($framework) {
        "InnoSetup" {
            if ($newArgs -match '(?i)(^|\s)/VERYSILENT(\s|$)') {
                $isSilent = $true
            } elseif ($newArgs -match '(?i)(^|\s)/SILENT(\s|$)') {
                $newArgs = [regex]::Replace($newArgs, '(?i)(?<=^|\s)/SILENT(?=\s|$)', '/VERYSILENT')
                $addedFlags = $true
                $isSilent = $true
            } else {
                $newArgs = "$newArgs /VERYSILENT".Trim()
                $addedFlags = $true
                $isSilent = $true
            }
            if ($newArgs -notmatch '(?i)(^|\s)/SUPPRESSMSGBOXES(\s|$)') {
                $newArgs = "$newArgs /SUPPRESSMSGBOXES".Trim()
                $addedFlags = $true
            }
            if ($newArgs -notmatch '(?i)(^|\s)/NORESTART(\s|$)') {
                $newArgs = "$newArgs /NORESTART".Trim()
                $addedFlags = $true
            }
        }
        "NSIS" {
            if ($newArgs -cmatch '(^|\s)/S(\s|$)' -or $newArgs -match '(?i)(^|\s)(--silent|/silent)(\s|$)') {
                $isSilent = $true
            } elseif ($newArgs -cmatch '(^|\s)/s(\s|$)') {
                $newArgs = [regex]::Replace($newArgs, '(?<=^|\s)/s(?=\s|$)', '/S')
                $addedFlags = $true
                $isSilent = $true
            } else {
                $newArgs = "$newArgs /S".Trim()
                $addedFlags = $true
                $isSilent = $true
            }
        }
        "WiX" {
            if ($newArgs -match '(?i)(^|\s)(/q|/quiet|/silent|/passive)(\s|$)') {
                $isSilent = $true
            } else {
                if ($newArgs -notmatch '(?i)(^|\s)(/uninstall|/x)(\s|$)') {
                    $newArgs = "$newArgs /uninstall".Trim()
                }
                $newArgs = "$newArgs /quiet /norestart".Trim()
                $addedFlags = $true
                $isSilent = $true
            }
        }
        "BitRock" {
            if ($newArgs -match '(?i)(^|\s)--mode(\s|=)(unattended|minimal)(\s|$)') {
                $isSilent = $true
            } elseif ($newArgs -notmatch '(?i)(^|\s)--mode(\s|=|$)') {
                $newArgs = "$newArgs --mode unattended".Trim()
                $addedFlags = $true
                $isSilent = $true
            }
        }
        "Squirrel" {
            if ($newArgs -match '(?i)(^|\s)(-s|--silent)(\s|$)') {
                $isSilent = $true
            } elseif ($newArgs -match '(?i)--uninstall') {
                $newArgs = "$newArgs -s".Trim()
                $addedFlags = $true
                $isSilent = $true
            }
        }
        default {
            $exeBase = [System.IO.Path]::GetFileName($exe)
            if ($exeBase -ieq "setup.exe" -and $newArgs -match '(?i)--uninstall' -and $newArgs -notmatch '(?i)--force-uninstall') {
                $framework = "ChromiumSetup"
                $newArgs = "$newArgs --force-uninstall".Trim()
                $addedFlags = $true
                $isSilent = $true
            } elseif ($hasExplicitQuiet -or ($newArgs -match '(?i)(^|\s)(/s|/silent|/verysilent|/quiet|/qn|--silent|--quiet|-silent|-s)(\s|$)')) {
                $isSilent = $true
            }
        }
    }

    $hintMeta = "$($AppEntry.DisplayName) $($AppEntry.Publisher) $exe"
    $isDark = ($hintMeta -match '(?i)\b(360Safe|360 Total|Qihu|2345|Kingsoft|Sogou|Baidu|Driver Booster|IObit)\b')

    return [PSCustomObject]@{
        Mode                = "Exe"
        Exe                 = $exe
        Args                = $newArgs
        Framework           = $framework
        AddedSilentFlags    = $addedFlags
        IsSilent            = $isSilent
        IsLikelyDarkPattern = $isDark
    }
}

function Invoke-DeepAppUninstall {
    param(
        [Parameter(Mandatory = $true)]$AppEntry,
        [Parameter(Mandatory = $false)]$OwnerWindow,
        [switch]$SkipVendorUninstaller
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
        if ($SkipVendorUninstaller) {
            if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                Log-Text "[FORCE] B$([char]0x1ECF) qua tr$([char]0x00EC)nh g$([char]0x1EE1) c$([char]0x1EE7)a h$([char]0x00E3)ng ($([char]0x0111)$([char]0x00E3) t$([char]0x1EAF)t service/ti$([char]0x1EBF)n tr$([char]0x00EC)nh) -> qu$([char]0x00E9)t x$([char]0x00F3)a s$([char]0x1EA1)ch tr$([char]0x1EF1)c ti$([char]0x1EBF)p."
            }
        } else {
            $plan = Resolve-SilentUninstallPlan -AppEntry $AppEntry
            if ($plan.Mode -eq "MSI") {
                if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                    Log-Text "[*] $([char]0x0110)ang g$([char]0x1ECD)i Windows Installer g$([char]0x1EE1) b$([char]0x1ECF) g$([char]0x00F3)i MSI: $($AppEntry.DisplayName) ($($plan.MsiId))..."
                }
                if (Get-Command Run-CliStream -ErrorAction SilentlyContinue) {
                    $msiCode = Run-CliStream "msiexec.exe" $plan.Args
                    if ($msiCode -eq 1618) {
                        Start-Sleep -Seconds 3
                        $null = Run-CliStream "msiexec.exe" $plan.Args
                    }
                } else {
                    Start-Process "msiexec.exe" -ArgumentList $plan.Args -Wait -NoNewWindow
                }
            } elseif ($plan.Mode -eq "MissingExe") {
                if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                    Log-Text "[!] Kh$([char]0x00F4)ng t$([char]0x00EC)m th$([char]0x1EA5)y tr$([char]0x00EC)nh g$([char]0x1EE1) g$([char]0x1ED1)c t$([char]0x1EA1)i '$($plan.Exe)' - chuy$([char]0x1EC3)n sang qu$([char]0x00E9)t d$([char]0x1ECD)n s$([char]0x1EA1)ch tr$([char]0x1EF1)c ti$([char]0x1EBF)p."
                }
            } elseif ($plan.Mode -eq "Exe") {
                if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                    if ($plan.AddedSilentFlags) {
                        Log-Text "[SILENT] Nh$([char]0x1EAD)n di$([char]0x1EC7)n [$($plan.Framework)], $([char]0x0111)$([char]0x00E3) g$([char]0x1EAF)n c$([char]0x1EDD) g$([char]0x1EE1) im l$([char]0x1EB7)ng: $($plan.Exe) $($plan.Args)"
                    } else {
                        Log-Text "[*] $([char]0x0110)ang th$([char]0x1EF1)c thi tr$([char]0x00EC)nh g$([char]0x1EE1) b$([char]0x1ECF) ch$([char]0x00ED)nh th$([char]0x1EE9)c: $($plan.Exe) $($plan.Args)"
                        if (-not $plan.IsSilent) {
                            $hintText = if ($plan.IsLikelyDarkPattern) {
                                "[!] $([char]0x1EE8)ng d$([char]0x1EE5)ng n$([char]0x00E0)y hay c$([char]0x00F3) b$([char]0x1EA3)ng h$([char]0x1ECF)i gi$([char]0x1EEF) ch$([char]0x00E2)n; n$([char]0x1EBF)u popup hi$([char]0x1EC7)n l$([char]0x00EA)n, l$([char]0x1EA7)n sau h$([char]0x00E3)y t$([char]0x00ED)ch 'B$([char]0x1ECF) qua tr$([char]0x00EC)nh g$([char]0x1EE1) h$([char]0x00E3)ng'."
                            } else {
                                "[!] Kh$([char]0x00F4)ng r$([char]0x00F5) c$([char]0x1EDD) im l$([char]0x1EB7)ng chu$([char]0x1EA9)n cho tr$([char]0x00EC)nh g$([char]0x1EE1) n$([char]0x00E0)y; n$([char]0x1EBF)u c$([char]0x00F3) b$([char]0x1EA3)ng h$([char]0x1ECF)i l$([char]0x00E0)m phi$([char]0x1EC1)n, c$([char]0x00F3) th$([char]0x1EC3) t$([char]0x00ED)ch 'B$([char]0x1ECF) qua tr$([char]0x00EC)nh g$([char]0x1EE1) h$([char]0x00E3)ng'."
                            }
                            Log-Text $hintText
                        }
                    }
                }
                if (Get-Command Run-CliStream -ErrorAction SilentlyContinue) {
                    $null = Run-CliStream $plan.Exe $plan.Args
                } else {
                    Start-Process $plan.Exe -ArgumentList $plan.Args -Wait -NoNewWindow
                }
            }
        }
    }

    if ($script:isWindowClosing) { return }
    Start-Sleep -Milliseconds 800
    if ($script:isWindowClosing) { return }

    if ($safeLoc -and (Test-Path -LiteralPath $safeLoc)) {
        [DuckUtil.DeepUninstallerEngine]::DisableAndRemoveServicesInDirectory($safeLoc) | Out-Null
        [DuckUtil.DeepUninstallerEngine]::RemoveScheduledTasksInDirectory($safeLoc) | Out-Null
        [DuckUtil.DeepUninstallerEngine]::StopProcessesInDirectory($safeLoc) | Out-Null
    }

    $leftovers = Find-AppLeftovers -AppEntry $AppEntry -AllInstalledApps $allInstalledNow
    if ($script:isWindowClosing) { return }
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
