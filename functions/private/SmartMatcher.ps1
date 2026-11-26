if (-not ("System.Windows.Media.SolidColorBrush" -as [type])) {
    Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
}

if (-not ("DuckUtil.AppCatalogEngine" -as [type])) {
    try {
        if ($PSScriptRoot) {
            $csCandidates = @(
                (Join-Path $PSScriptRoot "..\..\csharp\AppCatalogEngine.cs"),
                (Join-Path $PSScriptRoot "..\csharp\AppCatalogEngine.cs"),
                (Join-Path $PSScriptRoot "csharp\AppCatalogEngine.cs")
            )
            foreach ($cand in $csCandidates) {
                if (Test-Path -LiteralPath $cand) {
                    $appCatalogCs = Get-Content -Raw -Encoding utf8 $cand
                    Add-Type -TypeDefinition $appCatalogCs -ErrorAction SilentlyContinue
                    break
                }
            }
        }
    } catch {}
}

$script:brushOutdatedFg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF8, 0x71, 0x71))
$script:brushLatestFg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x34, 0xD3, 0x99))
$script:brushNoneBg     = [System.Windows.Media.Brushes]::Transparent
$script:brushNoneFg     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF1, 0xF5, 0xF9))

$script:brushOutdatedFg.Freeze()
$script:brushLatestFg.Freeze()
$script:brushNoneFg.Freeze()

$script:cleanNameCache     = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:versionNumCache    = [System.Collections.Generic.Dictionary[string, long[]]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:targetAppMetaCache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:stopWordSet        = [System.Collections.Generic.HashSet[string]]::new([string[]]@("microsoft", "windows", "google", "runtime", "desktop", "client", "studio", "server", "edition", "community", "x64", "x86", "arm64", "arp", "msix", "machine", "user", "app", "pro", "free", "jdk", "jre", "lts", "cli", "ide", "gui", "vpn", "bit"), [System.StringComparer]::OrdinalIgnoreCase)
$script:preSpawnedWinget   = $null

function Get-CleanAppName {
    param([string]$RawName)
    if ([string]::IsNullOrWhiteSpace($RawName)) { return "" }
    $cached = $null
    if ($script:cleanNameCache.TryGetValue($RawName, [ref]$cached)) {
        return $cached
    }
    if ("DuckUtil.AppCatalogEngine" -as [type]) {
        $clean = [DuckUtil.AppCatalogEngine]::CleanCatalogAppName($RawName)
        $script:cleanNameCache[$RawName] = $clean
        return $clean
    }
    $clean = ($RawName -replace '\((?!x64|x86|arm64).*?\)', '').Replace('(', '').Replace(')', '').Trim().ToLowerInvariant()
    $clean = $clean -replace '\b(version|ver|v|release)\s*\d+(\.\d+)*[^\s]*', ''
    $clean = $clean -replace '\b\d+(\.\d+){1,4}(-[a-z0-9.]+)?\b', ''
    $terms = @(" browser", " desktop", " lts", " client", " free", " ce", " community", " end-user", " stable", " edition", " x64", " x86", " 64-bit", " 32-bit")
    foreach ($term in $terms) {
        $clean = $clean.Replace($term, "")
    }
    $clean = ($clean -replace '\s+', ' ').Trim()
    $script:cleanNameCache[$RawName] = $clean
    return $clean
}

function Get-VersionNumbers {
    param([string]$VerStr)
    if ([string]::IsNullOrWhiteSpace($VerStr)) { return [long[]]@() }
    $cached = $null
    if ($script:versionNumCache.TryGetValue($VerStr, [ref]$cached)) {
        return $cached
    }
    if ("DuckUtil.AppCatalogEngine" -as [type]) {
        $arr = [DuckUtil.AppCatalogEngine]::GetVersionNumbers($VerStr)
        $script:versionNumCache[$VerStr] = $arr
        return $arr
    }
    $s = $VerStr.Trim()
    if ($s.StartsWith("<")) { $s = $s.Substring(1).Trim() }
    $m = [System.Text.RegularExpressions.Regex]::Match($s, '\d+(?:[.+_-]\d+)*')
    if (-not $m.Success) {
        $empty = [long[]]@()
        $script:versionNumCache[$VerStr] = $empty
        return $empty
    }
    $parts = $m.Value -split '[.+_-]'
    $nums = [System.Collections.Generic.List[long]]::new()
    foreach ($p in $parts) {
        $v = 0L
        if ([long]::TryParse($p, [ref]$v)) {
            $nums.Add($v)
        }
    }
    $arr = $nums.ToArray()
    $script:versionNumCache[$VerStr] = $arr
    return $arr
}

function Compare-AppVersions {
    param([string]$VerA, [string]$VerB)
    if ("DuckUtil.AppCatalogEngine" -as [type]) {
        return [DuckUtil.AppCatalogEngine]::CompareAppVersions($VerA, $VerB)
    }
    $a = @(Get-VersionNumbers $VerA)
    $b = @(Get-VersionNumbers $VerB)
    if ($a.Count -eq 0 -and $b.Count -eq 0) { return 0 }
    if ($a.Count -gt 0 -and $b.Count -eq 0) { return 1 }
    if ($a.Count -eq 0 -and $b.Count -gt 0) { return -1 }

    $maxLen = [Math]::Max($a.Count, $b.Count)
    for ($i = 0; $i -lt $maxLen; $i++) {
        $va = if ($i -lt $a.Count) { [long]$a[$i] } else { 0L }
        $vb = if ($i -lt $b.Count) { [long]$b[$i] } else { 0L }
        if ($va -gt $vb) { return 1 }
        if ($va -lt $vb) { return -1 }
    }
    return 0
}

function Test-AppUpdateGenuine {
    param([string]$InstalledVer, [string]$AvailableVer)
    if ("DuckUtil.AppCatalogEngine" -as [type]) {
        return [DuckUtil.AppCatalogEngine]::TestAppUpdateGenuine($InstalledVer, $AvailableVer)
    }
    if ([string]::IsNullOrWhiteSpace($AvailableVer)) { return $false }
    $av = $AvailableVer.Trim()
    if ($av -eq "winget" -or $av -eq "msstore" -or $av -eq "Unknown" -or $av -match '(?i)^kh[o\u00F4]ng\s*x[a\u00E1]c\s*[d\u0111][i\u1ECB]nh$') { return $false }
    if ($av -notmatch '\d') { return $false }
    if ([string]::IsNullOrWhiteSpace($InstalledVer)) { return $false }
    $iv = $InstalledVer.Trim()
    if ($iv -eq "Unknown" -or $iv -eq "Installed" -or $iv -match '(?i)^kh[o\u00F4]ng\s*x[a\u00E1]c\s*[d\u0111][i\u1ECB]nh$' -or $iv -notmatch '\d') { return $false }
    $cmp = Compare-AppVersions $av $iv
    if ($iv.StartsWith("<")) { return ($cmp -ge 0) }
    if ($cmp -gt 0) { return $true }
    $rxPre = '(?i)(?:^|[-.+_])(?:alpha|beta|rc|pre|preview|dev|canary|nightly)(?:$|[-.+_\d])'
    if ($cmp -eq 0 -and ($iv -match $rxPre) -and ($av -notmatch $rxPre)) { return $true }
    return $false
}

function Get-CharDisplayWidth {
    param([int]$Code)
    if (
        ($Code -ge 0x1100 -and $Code -le 0x115F) -or
        ($Code -eq 0x2329 -or $Code -eq 0x232A) -or
        ($Code -ge 0x2E80 -and $Code -le 0x303E) -or
        ($Code -ge 0x3041 -and $Code -le 0x33FF) -or
        ($Code -ge 0x3400 -and $Code -le 0x4DBF) -or
        ($Code -ge 0x4E00 -and $Code -le 0xA4CF) -or
        ($Code -ge 0xA960 -and $Code -le 0xA97F) -or
        ($Code -ge 0xAC00 -and $Code -le 0xD7AF) -or
        ($Code -ge 0xF900 -and $Code -le 0xFAFF) -or
        ($Code -ge 0xFE10 -and $Code -le 0xFE19) -or
        ($Code -ge 0xFE30 -and $Code -le 0xFE6F) -or
        ($Code -ge 0xFF01 -and $Code -le 0xFF60) -or
        ($Code -ge 0xFFE0 -and $Code -le 0xFFE6) -or
        ($Code -ge 0x1F300 -and $Code -le 0x1FAFF)
    ) { return 2 }
    return 1
}

function Get-SliceByDisplayWidth {
    param([string]$Line, [int[]]$Offsets)
    $idIdx    = if ($Offsets.Count -ge 2) { $Offsets[1] } else { -1 }
    $verIdx   = if ($Offsets.Count -ge 3) { $Offsets[2] } else { -1 }
    $availIdx = if ($Offsets.Count -ge 4) { $Offsets[3] } else { -1 }
    $srcIdx   = if ($Offsets.Count -ge 5) { $Offsets[4] } else { -1 }

    $targets = @($idIdx, $verIdx, $availIdx, $srcIdx)
    $charPos = @(-1, -1, -1, -1)
    $w = 0
    for ($i = 0; $i -lt $Line.Length; $i++) {
        for ($t = 0; $t -lt 4; $t++) {
            if ($charPos[$t] -lt 0 -and $targets[$t] -ge 0 -and $w -ge $targets[$t]) {
                $charPos[$t] = $i
            }
        }
        $ch = $Line[$i]
        if ([char]::IsHighSurrogate($ch) -and ($i + 1) -lt $Line.Length -and [char]::IsLowSurrogate($Line[$i + 1])) {
            $cp = [char]::ConvertToUtf32($ch, $Line[$i + 1])
            $w += Get-CharDisplayWidth $cp
            $i++
        } else {
            $w += Get-CharDisplayWidth ([int]$ch)
        }
    }

    return Slice-WingetRowColumnsByPositions -Line $Line -CId $charPos[0] -CVer $charPos[1] -CAvail $charPos[2] -CSrc $charPos[3]
}

function Get-StringDisplayWidth {
    param([string]$Text, [int]$EndIndex = -1)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    $limit = if ($EndIndex -ge 0 -and $EndIndex -le $Text.Length) { $EndIndex } else { $Text.Length }
    $w = 0
    for ($i = 0; $i -lt $limit; $i++) {
        $ch = $Text[$i]
        if ([char]::IsHighSurrogate($ch) -and ($i + 1) -lt $limit -and [char]::IsLowSurrogate($Text[$i + 1])) {
            $cp = [char]::ConvertToUtf32($ch, $Text[$i + 1])
            $w += Get-CharDisplayWidth $cp
            $i++
        } else {
            $w += Get-CharDisplayWidth ([int]$ch)
        }
    }
    return $w
}

function Snap-WingetColumnBoundary {
    param([string]$Line, [int]$Pos, [int]$MinPos)
    if ([string]::IsNullOrEmpty($Line) -or $Pos -le $MinPos -or $Pos -ge $Line.Length) { return $Pos }
    if ([char]::IsWhiteSpace($Line[$Pos]) -or [char]::IsWhiteSpace($Line[$Pos - 1])) { return $Pos }

    $leftCand = -1
    $minLeft = [Math]::Max($MinPos + 1, $Pos - 10)
    for ($j = $Pos - 1; $j -ge $minLeft; $j--) {
        if ([char]::IsWhiteSpace($Line[$j])) { $leftCand = $j + 1; break }
    }

    $rightCand = -1
    $maxRight = [Math]::Min($Line.Length - 1, $Pos + 10)
    for ($j = $Pos + 1; $j -le $maxRight; $j++) {
        if ([char]::IsWhiteSpace($Line[$j])) {
            $k = $j
            while ($k -lt $Line.Length -and [char]::IsWhiteSpace($Line[$k])) { $k++ }
            if ($k -lt $Line.Length) { $rightCand = $k }
            break
        }
    }

    if ($leftCand -ge 0 -and $rightCand -ge 0) {
        if (($Pos - $leftCand) -le ($rightCand - $Pos)) { return $leftCand }
        return $rightCand
    }
    if ($leftCand -ge 0) { return $leftCand }
    if ($rightCand -ge 0) { return $rightCand }
    return $Pos
}

function Find-NextWingetColumnStartOrEnd {
    param([string]$Line, [int]$Pos, [int]$MaxEnd)
    $limit = if ($MaxEnd -gt $Pos -and $MaxEnd -le $Line.Length) { $MaxEnd } else { $Line.Length }
    if ($Pos -lt 0 -or $Pos -ge $limit) { return $limit }
    if ([char]::IsWhiteSpace($Line[$Pos]) -or ($Pos -gt 0 -and [char]::IsWhiteSpace($Line[$Pos - 1]))) { return $Pos }
    $j = $Pos
    while ($j -lt $limit -and -not [char]::IsWhiteSpace($Line[$j])) { $j++ }
    while ($j -lt $limit -and [char]::IsWhiteSpace($Line[$j])) { $j++ }
    return $j
}

function Split-WingetTailAvailAndSource {
    param([string]$Tail)
    $avail = ""; $src = ""
    if ([string]::IsNullOrWhiteSpace($Tail)) { return @($avail, $src) }
    $t = $Tail.Trim()
    if ($t -match '^(?i)(winget|msstore)$') {
        return @("", $t)
    }
    $lastSpace = -1
    for ($i = $t.Length - 1; $i -ge 0; $i--) {
        if ([char]::IsWhiteSpace($t[$i])) { $lastSpace = $i; break }
    }
    if ($lastSpace -gt 0) {
        $lastTok = $t.Substring($lastSpace + 1).Trim()
        if ($lastTok -match '^(?i)(winget|msstore)$') {
            $src = $lastTok
            $avail = $t.Substring(0, $lastSpace).Trim()
            return @($avail, $src)
        }
    }
    return @($t, "")
}

function Resolve-WingetRowSource {
    param([string]$AppId, [string]$SrcCol)
    if (-not [string]::IsNullOrWhiteSpace($SrcCol)) {
        $s = $SrcCol.Trim()
        if ($s.Equals("msstore", [System.StringComparison]::OrdinalIgnoreCase)) { return "msstore" }
        return "winget"
    }
    if (-not [string]::IsNullOrWhiteSpace($AppId) -and ($AppId.StartsWith("ARP\", [System.StringComparison]::OrdinalIgnoreCase) -or $AppId.StartsWith("MSIX\", [System.StringComparison]::OrdinalIgnoreCase))) {
        return "local"
    }
    return "winget"
}

function Slice-WingetRowColumnsByPositions {
    param([string]$Line, [int]$CId, [int]$CVer, [int]$CAvail, [int]$CSrc)
    $appName = ""; $appId = ""; $version = ""; $avail = ""; $src = ""
    if ($CId -gt 0 -and $Line.Length -gt $CId) {
        $CId = Snap-WingetColumnBoundary -Line $Line -Pos $CId -MinPos 0
        $appName = $Line.Substring(0, $CId).Trim()
        if ($CVer -gt $CId -and $Line.Length -gt $CVer) {
            $CVer = Snap-WingetColumnBoundary -Line $Line -Pos $CVer -MinPos $CId
            if ($CVer -gt $CId -and $CVer -lt $Line.Length -and -not [char]::IsWhiteSpace($Line[$CVer]) -and -not [char]::IsWhiteSpace($Line[$CVer - 1])) {
                $CVer = Find-NextWingetColumnStartOrEnd -Line $Line -Pos $CVer -MaxEnd $Line.Length
            }
            $appId = if ($CVer -lt $Line.Length) { $Line.Substring($CId, $CVer - $CId).Trim() } else { $Line.Substring($CId).Trim() }
            if ($CVer -lt $Line.Length) {
                if ($CAvail -gt $CVer -and $Line.Length -gt $CAvail) {
                    $availStart = Find-NextWingetColumnStartOrEnd -Line $Line -Pos $CAvail -MaxEnd $Line.Length
                    if ($availStart -le $CVer) { $availStart = $CAvail }
                    if ($availStart -lt $Line.Length) {
                        $verSlice = $Line.Substring($CVer, $availStart - $CVer).Trim()
                        if ($verSlice -eq "<" -or $verSlice -eq ">") {
                            while ($availStart -lt $Line.Length -and [char]::IsWhiteSpace($Line[$availStart])) { $availStart++ }
                            $availStart = Find-NextWingetColumnStartOrEnd -Line $Line -Pos $availStart -MaxEnd $Line.Length
                        }
                    }
                    if ($availStart -ge $Line.Length) {
                        $version = $Line.Substring($CVer).Trim()
                    } else {
                        $version = $Line.Substring($CVer, $availStart - $CVer).Trim()
                        if ($CSrc -gt $availStart -and $Line.Length -gt $CSrc) {
                            $srcStart = Find-NextWingetColumnStartOrEnd -Line $Line -Pos $CSrc -MaxEnd $Line.Length
                            $avail = $Line.Substring($availStart, $srcStart - $availStart).Trim()
                            if ($srcStart -lt $Line.Length) { $src = $Line.Substring($srcStart).Trim() }
                        } elseif ($CSrc -gt 0 -and $CSrc -le $availStart -and $Line.Length -gt $availStart) {
                            $splitTail = Split-WingetTailAvailAndSource -Tail $Line.Substring($availStart)
                            $avail = $splitTail[0]; $src = $splitTail[1]
                        } else {
                            $avail = $Line.Substring($availStart).Trim()
                        }
                    }
                } elseif ($CAvail -gt 0 -and $CVer -ge $CAvail) {
                    $verEnd = $CVer
                    while ($verEnd -lt $Line.Length -and -not [char]::IsWhiteSpace($Line[$verEnd])) { $verEnd++ }
                    $tok = $Line.Substring($CVer, $verEnd - $CVer)
                    if (($tok -eq "<" -or $tok -eq ">") -and $verEnd -lt $Line.Length) {
                        $p = $verEnd
                        while ($p -lt $Line.Length -and [char]::IsWhiteSpace($Line[$p])) { $p++ }
                        while ($p -lt $Line.Length -and -not [char]::IsWhiteSpace($Line[$p])) { $p++ }
                        $verEnd = $p
                    }
                    $version = $Line.Substring($CVer, $verEnd - $CVer).Trim()
                    $availStart = $verEnd
                    while ($availStart -lt $Line.Length -and [char]::IsWhiteSpace($Line[$availStart])) { $availStart++ }
                    if ($availStart -lt $Line.Length) {
                        $tail = $Line.Substring($availStart).Trim()
                        if ($CSrc -gt 0) {
                            $splitTail = Split-WingetTailAvailAndSource -Tail $tail
                            $avail = $splitTail[0]; $src = $splitTail[1]
                        } else {
                            $avail = $tail
                        }
                    }
                } else {
                    $version = $Line.Substring($CVer).Trim()
                }
            }
        } else {
            $appId = $Line.Substring($CId).Trim()
        }
    }
    return @($appName, $appId, $version, $avail, $src)
}

function Test-VersionAtLeastAvailable {
    param([string]$InstalledVer, [string]$WgVer, [string]$WgAvail)
    if ([string]::IsNullOrWhiteSpace($InstalledVer) -or $InstalledVer -match '^(Installed|Unknown)$' -or $InstalledVer -notmatch '\d') { return $false }
    if ([string]::IsNullOrWhiteSpace($WgAvail) -or $WgAvail -match '^(Installed|Unknown)$' -or $WgAvail -notmatch '\d') { return $false }
    if ((Compare-AppVersions $InstalledVer $WgAvail) -ge 0) { return $true }
    $locNums = @(Get-VersionNumbers $InstalledVer)
    $availNums = @(Get-VersionNumbers $WgAvail)
    if ($locNums.Count -ge 2 -and $locNums.Count -lt $availNums.Count) {
        $isPrefix = $true
        for ($i = 0; $i -lt $locNums.Count; $i++) {
            if ($locNums[$i] -ne $availNums[$i]) { $isPrefix = $false; break }
        }
        if ($isPrefix -and -not [string]::IsNullOrWhiteSpace($WgVer) -and ($WgVer -match '\d') -and ((Compare-AppVersions $InstalledVer $WgVer) -gt 0)) {
            return $true
        }
    }
    return $false
}

function Set-PreferredMapEntry {
    param($Map, [string]$Key, $Candidate)
    if ([string]::IsNullOrWhiteSpace($Key) -or $null -eq $Candidate) { return }
    if (-not $Map.ContainsKey($Key)) {
        $Map[$Key] = $Candidate
        return
    }
    $cur = $Map[$Key]
    $curIsLocal = ($cur.Source -eq "local")
    $candIsLocal = ($Candidate.Source -eq "local")

    if ($curIsLocal -ne $candIsLocal) {
        $locItem = if ($curIsLocal) { $cur } else { $Candidate }
        $wgItem = if ($curIsLocal) { $Candidate } else { $cur }
        $hasLocNum = (-not [string]::IsNullOrWhiteSpace($locItem.Version) -and $locItem.Version -notmatch '^(Installed|Unknown)$' -and $locItem.Version -match '\d')
        $hasWgVerNum = (-not [string]::IsNullOrWhiteSpace($wgItem.Version) -and $wgItem.Version -notmatch '^(Installed|Unknown)$' -and $wgItem.Version -match '\d')
        $hasWgAvailNum = (-not [string]::IsNullOrWhiteSpace($wgItem.Available) -and $wgItem.Available -notmatch '^(Installed|Unknown)$' -and $wgItem.Available -match '\d')
        if ($hasLocNum) {
            if ($wgItem.HasUpdate -and $hasWgAvailNum) {
                $Map[$Key] = if (Test-VersionAtLeastAvailable -InstalledVer $locItem.Version -WgVer $wgItem.Version -WgAvail $wgItem.Available) { $locItem } else { $wgItem }
                return
            }
            if (-not $hasWgVerNum -or (Compare-AppVersions $locItem.Version $wgItem.Version) -gt 0) {
                $Map[$Key] = $locItem
                return
            }
        }
        $Map[$Key] = $wgItem
        return
    }

    $curIsSynthetic = ($cur.ID -match '^(ARP|MSIX|LOCAL)\\')
    $candIsSynthetic = ($Candidate.ID -match '^(ARP|MSIX|LOCAL)\\')
    if ($curIsSynthetic -ne $candIsSynthetic) {
        $synItem = if ($curIsSynthetic) { $cur } else { $Candidate }
        $realItem = if ($curIsSynthetic) { $Candidate } else { $cur }
        $hasSynNum = (-not [string]::IsNullOrWhiteSpace($synItem.Version) -and $synItem.Version -notmatch '^(Installed|Unknown)$' -and $synItem.Version -match '\d')
        $hasRealVerNum = (-not [string]::IsNullOrWhiteSpace($realItem.Version) -and $realItem.Version -notmatch '^(Installed|Unknown)$' -and $realItem.Version -match '\d')
        $hasRealAvailNum = (-not [string]::IsNullOrWhiteSpace($realItem.Available) -and $realItem.Available -notmatch '^(Installed|Unknown)$' -and $realItem.Available -match '\d')
        if ($hasSynNum) {
            if ($realItem.HasUpdate -and $hasRealAvailNum) {
                $Map[$Key] = if (Test-VersionAtLeastAvailable -InstalledVer $synItem.Version -WgVer $realItem.Version -WgAvail $realItem.Available) { $synItem } else { $realItem }
                return
            }
            if (-not $hasRealVerNum -or (Compare-AppVersions $synItem.Version $realItem.Version) -gt 0) {
                $Map[$Key] = $synItem
                return
            }
        }
        $Map[$Key] = $realItem
        return
    }

    $verCmp = Compare-AppVersions $Candidate.Version $cur.Version
    $bestVer = if ($verCmp -gt 0 -or [string]::IsNullOrWhiteSpace($cur.Version)) { $Candidate.Version } else { $cur.Version }

    $availCmp = Compare-AppVersions $Candidate.Available $cur.Available
    $bestAvail = if ($availCmp -gt 0) { $Candidate.Available } else { $cur.Available }

    $mergedHasUpdate = Test-AppUpdateGenuine -InstalledVer $bestVer -AvailableVer $bestAvail
    if (-not $mergedHasUpdate) { $bestAvail = "" }

    $useCandIdentity = (-not $cur.HasUpdate -and $Candidate.HasUpdate) -or ($verCmp -gt 0)
    $baseObj = if ($useCandIdentity) { $Candidate } else { $cur }
    $Map[$Key] = [PSCustomObject]@{
        Name      = $baseObj.Name
        ID        = $baseObj.ID
        Version   = $bestVer
        Available = $bestAvail
        HasUpdate = $mergedHasUpdate
        CleanName = $baseObj.CleanName
        Source    = $baseObj.Source
    }
}

function Get-TargetAppMeta {
    param($TargetApp)
    $tId = [string]$TargetApp.ID
    $meta = $null
    if ($script:targetAppMetaCache.TryGetValue($tId, [ref]$meta)) {
        return $meta
    }

    $tName = [string]$TargetApp.Name
    $hasCsClean = ($null -ne ("DuckUtil.AppCatalogEngine" -as [type]))
    $cleanTarget = ""
    if (-not [string]::IsNullOrWhiteSpace($tName)) {
        if (-not $script:cleanNameCache.TryGetValue($tName, [ref]$cleanTarget)) {
            $cleanTarget = if ($hasCsClean) { [DuckUtil.AppCatalogEngine]::CleanCatalogAppName($tName) } else { Get-CleanAppName $tName }
            $script:cleanNameCache[$tName] = $cleanTarget
        }
    }
    $aliasEntries = [System.Collections.Generic.List[hashtable]]::new()
    $cleanAliases = [System.Collections.Generic.List[hashtable]]::new()
    $queryTokens  = [System.Collections.Generic.List[string]]::new()
    $seenTokens   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($cleanTarget.Length -ge 4) {
        foreach ($qt in ([System.Text.RegularExpressions.Regex]::Split($cleanTarget, '[^a-zA-Z0-9+]+'))) {
            if ($qt.Length -ge 3 -and (-not $script:stopWordSet.Contains($qt)) -and $seenTokens.Add($qt)) {
                $queryTokens.Add($qt)
            }
        }
    }

    if ($TargetApp.Aliases) {
        foreach ($alias in $TargetApp.Aliases) {
            if ([string]::IsNullOrWhiteSpace($alias)) { continue }
            $cAl = ""
            if (-not $script:cleanNameCache.TryGetValue($alias, [ref]$cAl)) {
                $cAl = if ($hasCsClean) { [DuckUtil.AppCatalogEngine]::CleanCatalogAppName($alias) } else { Get-CleanAppName $alias }
                $script:cleanNameCache[$alias] = $cAl
            }
            $cleanAliases.Add(@{ Raw = $alias; Clean = $cAl })
            if ($alias.Length -ge 4) {
                $aliasEntries.Add(@{
                    Raw     = $alias
                    Pattern = "(?<![a-zA-Z0-9])" + [System.Text.RegularExpressions.Regex]::Escape($alias) + "(?![a-zA-Z0-9])"
                })
                foreach ($qt in ([System.Text.RegularExpressions.Regex]::Split($alias, '[^a-zA-Z0-9+]+'))) {
                    if ($qt.Length -ge 3 -and (-not $script:stopWordSet.Contains($qt)) -and $seenTokens.Add($qt)) {
                        $queryTokens.Add($qt)
                    }
                }
            }
        }
    }

    $patternClean = if ($cleanTarget.Length -ge 4) {
        "(?<![a-zA-Z0-9])" + [System.Text.RegularExpressions.Regex]::Escape($cleanTarget) + "(?![a-zA-Z0-9])"
    } else { "" }

    $reqPy = ""
    if ($tId -match '^Python\.Python\.(\d+\.\d+)$') {
        $reqPy = [regex]::Escape($Matches[1])
    }
    $reqJava = ""
    if ($tId -match '\.(Temurin|Corretto)\.(\d+)\.') {
        $reqJava = $Matches[2]
    }
    $reqDnRaw = ""
    $reqDnEsc = ""
    if ($tId -match '^Microsoft\.DotNet\.DesktopRuntime\.(\d+(?:_\d+)?)(?:\.|$)') {
        $reqDnRaw = $Matches[1]
        $reqDnEsc = $Matches[1].Replace('_', '\.')
    }
    $reqYear = ""
    if ($tId -match '^Microsoft\.VCRedist\.(\d{4})\.') {
        $reqYear = $Matches[1]
    }

    $tNameNoParens = ([regex]::Replace($tName, '(?i)\((?!x64|x86|arm64).*?\)', '')).Trim()
    $aliasIdSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if (-not [string]::IsNullOrWhiteSpace($tId)) { [void]$aliasIdSet.Add($tId) }
    if ($TargetApp.Aliases) {
        foreach ($al in $TargetApp.Aliases) {
            if (-not [string]::IsNullOrWhiteSpace($al)) { [void]$aliasIdSet.Add($al) }
        }
    }
    $tIdSegs = if ($tId) { $tId.Split('.') } else { @() }
    $pubPref = if ($tIdSegs.Count -ge 2) { $tIdSegs[0] } else { "" }
    $secSeg  = if ($tIdSegs.Count -ge 2) { $tIdSegs[1] } else { "" }
    $hasThreePlus = ($tIdSegs.Count -ge 3)

    $tArch = if ($tName -match '\(x64\)|\.x64' -or $tId -match '\.x64$') { "x64" }
             elseif ($tName -match '\(x86\)|\.x86' -or $tId -match '\.x86$') { "x86" }
             elseif ($tName -match '\(arm64\)|\.arm64' -or $tId -match '\.arm64$') { "arm64" }
             elseif ([Environment]::Is64BitOperatingSystem -and $TargetApp.Category -eq '.NET Runtimes' -and $tId -match 'DesktopRuntime') { "x64" }
             else { "" }

    $meta = [PSCustomObject]@{
        ID                  = $tId
        Name                = $tName
        CleanTarget         = $cleanTarget
        CleanAliases        = $cleanAliases
        AliasEntries        = $aliasEntries
        AliasIdSet          = $aliasIdSet
        PublisherPrefix     = $pubPref
        SecondSegment       = $secSeg
        HasThreePlusIdParts = $hasThreePlus
        PatternClean        = $patternClean
        QueryTokens         = $queryTokens
        AllowNoise          = ($tName -match '(?i)(Maintenance|Control Panel|Context Menu|AddOn|Installer|Agent)')
        IsPrev              = (($tNameNoParens -match '(?i)Preview') -or ($tId -match '(?i)Preview'))
        IsBeta              = (($tNameNoParens -match '(?i)\bBeta\b') -or ($tId -match '(?i)\.Beta(?:\.|$)'))
        IsCanary            = (($tNameNoParens -match '(?i)\bCanary\b') -or ($tId -match '(?i)\.Canary(?:\.|$)'))
        IsDevChannel        = (($tNameNoParens -match '(?i)\b(?:Dev|Developer\s*Edition)\b') -or ($tId -match '(?i)\.(?:Dev|DeveloperEdition)(?:\.|$)'))
        IsNightly           = (($tNameNoParens -match '(?i)\bNightly\b') -or ($tId -match '(?i)\.Nightly(?:\.|$)'))
        IsAlpha             = (($tNameNoParens -match '(?i)\bAlpha\b') -or ($tId -match '(?i)\.Alpha(?:\.|$)'))
        IsPtb               = (($tNameNoParens -match '(?i)\bPTB\b') -or ($tId -match '(?i)\.PTB(?:\.|$)'))
        IsEsr               = (($tNameNoParens -match '(?i)\bESR\b') -or ($tId -match '(?i)\.ESR(?:\.|$)'))
        IsInsiders          = (($tNameNoParens -match '(?i)\bInsiders?\b') -or ($tId -match '(?i)\.Insiders?(?:\.|$)'))
        IsVcRedist          = (($tId -match 'VCRedist') -or ($tName -match 'VC\+\+'))
        IsComm              = (($tNameNoParens -match '\bCommunity\b') -or ($tId -match '\.Community\b'))
        IsPro               = (($tNameNoParens -match '\b(Ultimate|Professional)\b') -or ($tId -match '\.(Ultimate|Professional)\b'))
        IsIde               = (($tNameNoParens -match '\bIDE\b') -or ($tId -match 'IDE$'))
        IsAntigravity       = ($tId -match 'Antigravity')
        IsCli               = (($tNameNoParens -match '\bCLI\b') -or ($tId -match '(\.cli|CLI)$'))
        IsBt                = (($tNameNoParens -match '(?i)Build Tools') -or ($tId -match '(?i)BuildTools'))
        IsVsc               = (($tId -match 'VisualStudioCode') -or ($tNameNoParens -match 'VS Code|Visual Studio Code'))
        IsVsAny             = ($tId -match 'VisualStudio')
        IsEtb               = (($tId -match 'EverythingToolbar') -or ($tName -match 'EverythingToolbar'))
        IsTemurin           = ($tId -match 'Temurin')
        IsOracleJava        = ($tId -match 'Oracle\.Java')
        IsCorretto          = ($tId -match 'Corretto')
        IsJdk               = (($tNameNoParens -match '\bJDK\b') -or ($tId -match '\.JDK$'))
        IsJre               = (($tNameNoParens -match '\bJRE\b') -or ($tId -match '\.(JRE|JavaRuntimeEnvironment)$'))
        ReqPy               = $reqPy
        ReqJava             = $reqJava
        ReqDnRaw            = $reqDnRaw
        ReqDnEsc            = $reqDnEsc
        ReqYear             = $reqYear
        Arch                = $tArch
    }
    $script:targetAppMetaCache[$tId] = $meta
    return $meta
}

function Test-MatchCompatible {
    param($TargetApp, $Item)
    if (-not $TargetApp -or -not $Item) { return $false }

    $meta          = Get-TargetAppMeta $TargetApp
    $tId           = $meta.ID
    $iName         = [string]$Item.Name
    $iNameNoParens = ([regex]::Replace($iName, '(?i)\((?!x64|x86|arm64).*?\)', '')).Trim()
    $iId           = [string]$Item.ID

    if (-not $meta.AllowNoise) {
        if ($iName -match '(?i)(Maintenance Service|Control Panels|Context Menu|SparseApp|SDK AddOn|CoreEditorFonts|Visual Studio Installer|Development Libraries|Standard Library|Test Suite|Tcl/Tk Support|pip Bootstrap)' -or
            $iId   -match '(?i)(MozillaMaintenanceService|ContextMenu|SparseApp|FigmaAgent)') {
            return $false
        }
    }

    if ($iId -eq 'Python.Launcher' -or $iName -match '^Python Launcher\b') {
        if ($tId -ne 'Python.Launcher') { return $false }
    }

    $iPrev = ($iNameNoParens.IndexOf('Preview', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($iId.IndexOf('Preview', [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
    if ($meta.IsPrev -ne $iPrev -and $tId -ne 'Microsoft.PowerToys') { return $false }

    if ($meta.IsBeta       -ne (($iNameNoParens -match '(?i)\bBeta\b') -or ($iId -match '(?i)\.Beta(?:\.|$)'))) { return $false }
    if ($meta.IsCanary     -ne (($iNameNoParens -match '(?i)\bCanary\b') -or ($iId -match '(?i)\.Canary(?:\.|$)'))) { return $false }
    if ($meta.IsDevChannel -ne (($iNameNoParens -match '(?i)\b(?:Dev|Developer\s*Edition)\b') -or ($iId -match '(?i)\.(?:Dev|DeveloperEdition)(?:\.|$)'))) { return $false }
    if ($meta.IsNightly    -ne (($iNameNoParens -match '(?i)\bNightly\b') -or ($iId -match '(?i)\.Nightly(?:\.|$)'))) { return $false }
    if ($meta.IsAlpha      -ne (($iNameNoParens -match '(?i)\bAlpha\b') -or ($iId -match '(?i)\.Alpha(?:\.|$)'))) { return $false }
    if ($meta.IsPtb        -ne (($iNameNoParens -match '(?i)\bPTB\b') -or ($iId -match '(?i)\.PTB(?:\.|$)'))) { return $false }
    if ($meta.IsEsr        -ne (($iNameNoParens -match '(?i)\bESR\b') -or ($iId -match '(?i)\.ESR(?:\.|$)'))) { return $false }
    if ($meta.IsInsiders   -ne (($iNameNoParens -match '(?i)\bInsiders?\b') -or ($iId -match '(?i)\.Insiders?(?:\.|$)'))) { return $false }

    if ($iId -notmatch '^(?i)(ARP|MSIX|LOCAL)\\' -and -not $meta.AliasIdSet.Contains($iId) -and -not $iId.StartsWith($tId + ".", [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($tId.Equals('OpenJS.NodeJS.LTS', [System.StringComparison]::OrdinalIgnoreCase) -and $iId.StartsWith('OpenJS.NodeJS', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        if ($meta.PublisherPrefix.Length -ge 3 -and $iId.StartsWith($meta.PublisherPrefix + ".", [System.StringComparison]::OrdinalIgnoreCase)) {
            $iSegs = $iId.Split('.')
            if ($iSegs.Count -ge 2) {
                if (-not $iSegs[1].Equals($meta.SecondSegment, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
                if ($meta.HasThreePlusIdParts) { return $false }
            }
        }
    }

    if ($meta.IsVcRedist -and ($iName -match '\bUWP\b' -or $iId -match 'VCLibs')) {
        return $false
    }

    if ($meta.IsComm -or $meta.IsPro) {
        $iComm = ($iName -match '\bCommunity\b') -or ($iId -match '\.Community\b')
        $iPro  = ($iName -match '\b(Ultimate|Professional)\b') -or ($iId -match '\.(Ultimate|Professional)\b')
        if (($meta.IsComm -and $iPro) -or ($meta.IsPro -and $iComm)) { return $false }
    }

    if ($meta.IsAntigravity -or $iId.IndexOf('Antigravity', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $iIde = ($iName -match '\bIDE\b') -or ($iId -match 'IDE$')
        if ($meta.IsIde -ne $iIde) { return $false }
    }

    $iCli = ($iName -match '\bCLI\b') -or ($iId -match '(\.cli|CLI)$')
    if ($meta.IsCli -ne $iCli) { return $false }

    $iBt = ($iName.IndexOf('Build Tools', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($iId.IndexOf('BuildTools', [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
    if ($meta.IsBt -ne $iBt) { return $false }

    if ($meta.IsVsAny -or $iId.IndexOf('VisualStudio', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $iVsc = ($iId -match 'VisualStudioCode') -or ($iName -match 'VS Code|Visual Studio Code')
        if ($meta.IsVsc -ne $iVsc) { return $false }
    }

    $iEtb = ($iId.IndexOf('EverythingToolbar', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($iName.IndexOf('EverythingToolbar', [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
    if ($meta.IsEtb -ne $iEtb) { return $false }

    if ($meta.IsTemurin -and ($iId -match 'Oracle|Corretto' -or $iName -match 'Corretto|^Java \d+ Update')) { return $false }
    if ($meta.IsOracleJava -and ($iId -match 'Temurin|Corretto' -or $iName -match 'Temurin|Corretto')) { return $false }
    if ($meta.IsCorretto -and ($iId -match 'Temurin|Oracle' -or $iName -match 'Temurin|^Java \d+ Update')) { return $false }

    if ($meta.IsJdk -or $meta.IsJre) {
        $iJdk = ($iName -match '\bJDK\b') -or ($iId -match '\.JDK$')
        $iJre = ($iName -match '\bJRE\b|^Java \d+ Update') -or ($iId -match '\.(JRE|JavaRuntimeEnvironment)$')
        if (($meta.IsJdk -and $iJre -and -not $iJdk) -or ($meta.IsJre -and $iJdk -and -not $iJre)) { return $false }
    }

    if ($meta.ReqPy) {
        $reqPy = $meta.ReqPy
        if ($iId -notmatch $reqPy -and $iName -notmatch $reqPy -and [string]$Item.Version -notmatch "^$reqPy(\.|$)") {
            return $false
        }
    }

    if ($meta.ReqJava) {
        $reqJava = $meta.ReqJava
        if ($iId -notmatch "\b$reqJava\b" -and $iName -notmatch "\b$reqJava\b" -and [string]$Item.Version -notmatch "^$reqJava(\.|$)") {
            return $false
        }
    }

    if ($meta.ReqDnRaw) {
        if ($iId -notmatch 'DesktopRuntime' -and $iName -notmatch '(?i)Desktop') {
            return $false
        }
        $reqDn = $meta.ReqDnEsc
        if ($iId -notmatch "DesktopRuntime\.$($meta.ReqDnRaw)(\.|$)" -and $iName -notmatch "\b$reqDn(\.\d+|\b)" -and [string]$Item.Version -notmatch "^$reqDn(\.|$)") {
            return $false
        }
    }

    if ($meta.ReqYear) {
        if ($iId.IndexOf($meta.ReqYear, [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and $iName.IndexOf($meta.ReqYear, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            return $false
        }
    }

    if ($meta.Arch) {
        $idForArch = if ($iId -match '^(ARP|MSIX|LOCAL)\\') { "" } else { $iId }
        $iArch = if ($iName -match '(?<![a-zA-Z0-9])(x64|64-bit)(?![a-zA-Z0-9])' -or $idForArch -match '\.x64$') { "x64" }
                 elseif ($iName -match '(?<![a-zA-Z0-9])(x86|32-bit)(?![a-zA-Z0-9])' -or $idForArch -match '\.x86$') { "x86" }
                 elseif ($iName -match '(?<![a-zA-Z0-9])arm64(?![a-zA-Z0-9])' -or $idForArch -match '\.arm64$') { "arm64" }
                 else { "" }
        if ($iArch -and $iArch -ne $meta.Arch) { return $false }
    }

    return $true
}

$script:isScanningApps         = $false
$script:isAutoRefreshing       = $false
$script:cancelAutoScan         = $false
$script:pendingManualAppRefresh = $false
$script:autoScanGeneration     = 0
$script:activeAutoScanGen      = 0
$script:hasCompletedAppScan    = $false
$script:lastAppScanSignature   = ""
$script:lastLocalScanSig       = ""
$script:lastLocalInstalledCnt  = -1
$script:autoScanWingetProcess  = $null

function Stop-ActiveAutoScan {
    $script:autoScanGeneration++
    $script:cancelAutoScan = $true
    $pAuto = $script:autoScanWingetProcess
    $script:autoScanWingetProcess = $null
    if ($null -ne $pAuto) {
        try {
            $hasEx = try { $pAuto.HasExited } catch { $true }
            if (-not $hasEx) { $pAuto.Kill() }
        } catch {}
        try { $pAuto.Dispose() } catch {}
    }
}

function Stop-PreSpawnedWinget {
    $job = $script:preSpawnedWinget
    $script:preSpawnedWinget = $null
    if ($null -ne $job -and $null -ne $job.Process) {
        try {
            $hasExited = try { $job.Process.HasExited } catch { $true }
            if (-not $hasExited) { $job.Process.Kill() }
        } catch {}
        try { $job.Process.Dispose() } catch {}
    }
}

function Start-WingetBackgroundPreScan {
    if ($script:isWindowClosing -or $null -ne $script:preSpawnedWinget) { return }
    try {
        if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) { return }
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "winget"
        $pinfo.Arguments = "list --source winget --disable-interactivity --accept-source-agreements"
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $pinfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($pinfo)
        if ($null -ne $p) {
            $script:preSpawnedWinget = [PSCustomObject]@{
                Process   = $p
                ReadTask  = $p.StandardOutput.ReadToEndAsync()
                ErrTask   = $p.StandardError.ReadToEndAsync()
                Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                Arguments = "list --source winget --disable-interactivity --accept-source-agreements"
            }
        }
    } catch {
        $script:preSpawnedWinget = $null
    }
}

function Invoke-WingetListCapture {
    param(
        [string]$Arguments = "list --disable-interactivity --accept-source-agreements",
        [int]$TimeoutSeconds = 35,
        [scriptblock]$CancelCheck = $null,
        [switch]$TrackAsAuto
    )

    $isCanceledNow = $script:isWindowClosing
    if (-not $isCanceledNow -and $CancelCheck) {
        try { $isCanceledNow = [bool](& $CancelCheck) } catch {}
    }
    if ($isCanceledNow) {
        Stop-PreSpawnedWinget
        return [PSCustomObject]@{
            Available   = $true
            TimedOut    = $true
            WasCanceled = $true
            ExitCode    = -1
            StdOut      = ""
            StdErr      = ""
        }
    }

    $p = $null
    $readTask = $null
    $errTask = $null
    $sw = $null
    $rawList = ""
    $errList = ""
    $timedOut = $false
    $wasCanceled = $false
    $exitCode = -1

    try {
        $canUsePreSpawned = (-not $TrackAsAuto -and -not $script:hasCompletedAppScan -and $null -ne $script:preSpawnedWinget -and $script:preSpawnedWinget.Arguments -eq $Arguments -and $script:preSpawnedWinget.Stopwatch.Elapsed.TotalSeconds -lt 30)
        if ($canUsePreSpawned) {
            $job = $script:preSpawnedWinget
            $script:preSpawnedWinget = $null
            $p = $job.Process
            $readTask = $job.ReadTask
            $errTask = $job.ErrTask
            $sw = $job.Stopwatch
        } else {
            if (-not $TrackAsAuto -and $null -ne $script:preSpawnedWinget) {
                Stop-PreSpawnedWinget
            }
            if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
                return [PSCustomObject]@{
                    Available   = $false
                    TimedOut    = $false
                    WasCanceled = $false
                    ExitCode    = -1
                    StdOut      = ""
                    StdErr      = ""
                }
            }

            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = "winget"
            $pinfo.Arguments = $Arguments
            $pinfo.RedirectStandardOutput = $true
            $pinfo.RedirectStandardError = $true
            $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $pinfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
            $pinfo.UseShellExecute = $false
            $pinfo.CreateNoWindow = $true

            $p = [System.Diagnostics.Process]::Start($pinfo)
            if ($null -eq $p) {
                throw "Không thể khởi động tiến trình winget."
            }
            if ($TrackAsAuto) {
                $script:autoScanWingetProcess = $p
            }
            $readTask = $p.StandardOutput.ReadToEndAsync()
            $errTask  = $p.StandardError.ReadToEndAsync()
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
        }

        if ((Get-Command "Wait-TaskNonBlocking" -ErrorAction SilentlyContinue) -and $null -ne $readTask -and $null -ne $errTask) {
            $bothTask = [System.Threading.Tasks.Task]::WhenAll([System.Threading.Tasks.Task[]](@($readTask, $errTask)))
            $remSec = [Math]::Max(0.1, ($TimeoutSeconds - $sw.Elapsed.TotalSeconds))
            $completedOk = Wait-TaskNonBlocking -Task $bothTask -TimeoutSeconds $remSec -CancelCheck $CancelCheck
            $cancelHit = $script:isWindowClosing
            if (-not $cancelHit -and $CancelCheck) {
                try { $cancelHit = [bool](& $CancelCheck) } catch {}
            }
            if ($cancelHit) {
                $wasCanceled = $true
                $timedOut = $true
                try { if ($null -ne $p -and -not $p.HasExited) { $p.Kill() } } catch {}
            } elseif (-not $completedOk -or -not $readTask.IsCompleted -or -not $errTask.IsCompleted) {
                $timedOut = $true
                try { if ($null -ne $p -and -not $p.HasExited) { $p.Kill() } } catch {}
            }
        } else {
            while (-not $readTask.IsCompleted -or -not $errTask.IsCompleted) {
                $cancelHit = $script:isWindowClosing
                if (-not $cancelHit -and $CancelCheck) {
                    try { $cancelHit = [bool](& $CancelCheck) } catch {}
                }
                if ($cancelHit -or $sw.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
                    $wasCanceled = $cancelHit
                    $timedOut = $true
                    try { if ($null -ne $p -and -not $p.HasExited) { $p.Kill() } } catch {}
                    break
                }
                try { [System.Windows.Forms.Application]::DoEvents() } catch {}
                Start-Sleep -Milliseconds 15
            }
        }

        if (-not $script:isWindowClosing -and -not $wasCanceled -and -not $timedOut -and $null -ne $p) {
            try {
                if (-not $p.HasExited) {
                    $deepTypeWg = "DuckUtil.DeepUninstallerEngine" -as [type]
                    if ($deepTypeWg -and $null -ne $deepTypeWg.GetMethod("WaitForProcessExitAsync") -and (Get-Command "Wait-TaskNonBlocking" -ErrorAction SilentlyContinue)) {
                        $exitWaitTask = $deepTypeWg::WaitForProcessExitAsync($p)
                        [void](Wait-TaskNonBlocking -Task $exitWaitTask -TimeoutSeconds 5 -CancelCheck $CancelCheck)
                    } else {
                        $p.WaitForExit(5000) | Out-Null
                    }
                }
            } catch {}
        }
        if (-not $wasCanceled) {
            if ($null -ne $readTask -and $readTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                $rawList = $readTask.Result
            }
            if ($null -ne $errTask -and $errTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                $errList = $errTask.Result
            }
            $hasExited = try { $null -ne $p -and $p.HasExited } catch { $false }
            if ($hasExited) {
                $exitCode = try { $p.ExitCode } catch { -1 }
            }
        }
    } finally {
        if ($TrackAsAuto -and $script:autoScanWingetProcess -eq $p) {
            $script:autoScanWingetProcess = $null
        }
        if ($null -ne $p) {
            try { $p.Dispose() } catch {}
        }
    }

    if (-not $wasCanceled -and -not $timedOut -and ($exitCode -eq -1978335230 -or ($exitCode -ne 0 -and ("$rawList`n$errList") -match '(?i)Unrecognized argument|Đối số không được nhận dạng')) -and $Arguments -match '--disable-interactivity') {
        $compatCaptureArgs = ($Arguments -replace '\s*--disable-interactivity\b', '').Trim()
        if ($compatCaptureArgs -ne $Arguments) {
            return (Invoke-WingetListCapture -Arguments $compatCaptureArgs -TimeoutSeconds $TimeoutSeconds -CancelCheck $CancelCheck -TrackAsAuto:$TrackAsAuto)
        }
    }

    return [PSCustomObject]@{
        Available   = $true
        TimedOut    = $timedOut
        WasCanceled = $wasCanceled
        ExitCode    = $exitCode
        StdOut      = $rawList
        StdErr      = $errList
    }
}

function ConvertFrom-WingetListOutput {
    param(
        [string]$RawText,
        [bool]$AllowHeaderless = $false
    )

    if ([string]::IsNullOrWhiteSpace($RawText)) {
        return [PSCustomObject]@{ HasTable = $false; Items = [System.Collections.Generic.List[object]]::new() }
    }

    if ("DuckUtil.AppCatalogEngine" -as [type]) {
        $hasTable = $false
        $items = [DuckUtil.AppCatalogEngine]::ParseWingetListOutput($RawText, $AllowHeaderless, [ref]$hasTable)
        return [PSCustomObject]@{ HasTable = $hasTable; Items = $items }
    }

    $parsed = [System.Collections.Generic.List[object]]::new()

    $rawLines = $RawText -split "`n"
    $lines = [System.Collections.Generic.List[string]]::new($rawLines.Count)
    foreach ($rl in $rawLines) {
        $cleanLine = $rl.TrimEnd("`r")
        if ($cleanLine.Contains("`r")) { $cleanLine = ($cleanLine -split "`r")[-1] }
        if ($cleanLine.Contains([char]0x1B)) {
            $cleanLine = [System.Text.RegularExpressions.Regex]::Replace($cleanLine, '\x1B\[[0-9;?]*[A-Za-z]', '')
        }
        $lines.Add($cleanLine)
    }

    $separatorIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*-{10,}') {
            $separatorIndex = $i
            break
        }
    }

    if ($separatorIndex -gt 0) {
        $separatorLine = $lines[$separatorIndex]
        $headerLine    = $lines[$separatorIndex - 1]
        $knownHdrTokens = [System.Collections.Generic.HashSet[string]]::new([string[]]@("Name", "Id", "Version", "Available", "Source", "Match", "Tag", "Command", "Moniker"), [System.StringComparer]::OrdinalIgnoreCase)

        $colOffsets = @()
        if ($separatorLine -match '---+\s+---+') {
            $dashMatches = [System.Text.RegularExpressions.Regex]::Matches($separatorLine, '-+')
            foreach ($dm in $dashMatches) { $colOffsets += $dm.Index }
        } elseif ($headerLine) {
            $singleTokens = [System.Text.RegularExpressions.Regex]::Matches($headerLine, '\S+')
            $allKnown = ($singleTokens.Count -ge 3)
            if ($allKnown) {
                foreach ($st in $singleTokens) {
                    if (-not $knownHdrTokens.Contains($st.Value)) { $allKnown = $false; break }
                }
            }
            if ($allKnown) {
                foreach ($st in $singleTokens) { $colOffsets += (Get-StringDisplayWidth -Text $headerLine -EndIndex $st.Index) }
            } else {
                $groupedMatches = [System.Text.RegularExpressions.Regex]::Matches($headerLine, '\S+(?:\s\S+)*')
                foreach ($gm in $groupedMatches) {
                    $subTokens = [System.Text.RegularExpressions.Regex]::Matches($gm.Value, '\S+')
                    for ($k = 0; $k -lt $subTokens.Count; $k++) {
                        if ($k -eq 0 -or $knownHdrTokens.Contains($subTokens[$k].Value) -or $knownHdrTokens.Contains($subTokens[$k - 1].Value)) {
                            $colOffsets += (Get-StringDisplayWidth -Text $headerLine -EndIndex ($gm.Index + $subTokens[$k].Index))
                        }
                    }
                }
                if ($colOffsets.Count -lt 3 -and $singleTokens.Count -ge 3) {
                    $colOffsets = @()
                    foreach ($st in $singleTokens) { $colOffsets += (Get-StringDisplayWidth -Text $headerLine -EndIndex $st.Index) }
                }
            }
        }

        $idIdx    = if ($colOffsets.Count -ge 2) { $colOffsets[1] } else { -1 }
        $verIdx   = if ($colOffsets.Count -ge 3) { $colOffsets[2] } else { -1 }
        $availIdx = if ($colOffsets.Count -ge 4) { $colOffsets[3] } else { -1 }
        $srcIdx   = if ($colOffsets.Count -ge 5) { $colOffsets[4] } else { -1 }

        for ($j = $separatorIndex + 1; $j -lt $lines.Count; $j++) {
            $line = $lines[$j]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $appName = ""; $appId = ""; $version = ""; $avail = ""; $srcCol = ""

            if ($colOffsets.Count -ge 3) {
                if ($line -match '[^\x00-\x7F]') {
                    $sliced = Get-SliceByDisplayWidth -Line $line -Offsets $colOffsets
                    $appName = $sliced[0]; $appId = $sliced[1]; $version = $sliced[2]; $avail = $sliced[3]; $srcCol = $sliced[4]
                } else {
                    $sliced = Slice-WingetRowColumnsByPositions -Line $line -CId $idIdx -CVer $verIdx -CAvail $availIdx -CSrc $srcIdx
                    $appName = $sliced[0]; $appId = $sliced[1]; $version = $sliced[2]; $avail = $sliced[3]; $srcCol = $sliced[4]
                }
            }

            if ([string]::IsNullOrEmpty($appId) -or $appId.IndexOf(' ') -ge 0) {
                $tailCols = $null
                if (-not [string]::IsNullOrEmpty($appName) -and $colOffsets.Count -ge 3) {
                    $nameEnd = $line.IndexOf($appName, [System.StringComparison]::Ordinal)
                    $searchFrom = if ($nameEnd -ge 0) { $nameEnd + $appName.Length } else { 0 }
                    while ($searchFrom -lt $line.Length -and [char]::IsWhiteSpace($line[$searchFrom])) { $searchFrom++ }
                    if ($searchFrom -lt $line.Length) {
                        $tCols = [System.Text.RegularExpressions.Regex]::Split($line.Substring($searchFrom).Trim(), '\s{2,}')
                        if ($tCols.Count -ge 1 -and -not [string]::IsNullOrWhiteSpace($tCols[0])) {
                            $tailCols = $tCols
                        }
                    }
                }
                if ($null -ne $tailCols) {
                    $appId   = $tailCols[0].Trim()
                    $version = if ($tailCols.Count -ge 2) { $tailCols[1].Trim() } else { "" }
                    $c3      = if ($tailCols.Count -ge 3) { $tailCols[2].Trim() } else { "" }
                    $c4      = if ($tailCols.Count -ge 4) { $tailCols[3].Trim() } else { "" }
                    if ($c3 -match '^(?i)(winget|msstore)$' -and [string]::IsNullOrEmpty($c4)) {
                        $srcCol = $c3
                        $avail  = ""
                    } else {
                        $avail = $c3
                        if (-not [string]::IsNullOrEmpty($c4)) { $srcCol = $c4 }
                    }
                } else {
                    $cols = [System.Text.RegularExpressions.Regex]::Split($line.Trim(), '\s{2,}')
                    if ($cols.Count -ge 2) {
                        $appName = $cols[0].Trim()
                        $appId   = $cols[1].Trim()
                        $version = if ($cols.Count -ge 3) { $cols[2].Trim() } else { "" }
                        $c3      = if ($cols.Count -ge 4) { $cols[3].Trim() } else { "" }
                        $c4      = if ($cols.Count -ge 5) { $cols[4].Trim() } else { "" }
                        if ($c3 -match '^(?i)(winget|msstore)$' -and [string]::IsNullOrEmpty($c4)) {
                            $srcCol = $c3
                            $avail  = ""
                        } else {
                            $avail = $c3
                            if (-not [string]::IsNullOrEmpty($c4)) { $srcCol = $c4 }
                        }
                    }
                }
            }

            if (-not [string]::IsNullOrEmpty($appName) -and -not [string]::IsNullOrEmpty($appId)) {
                if ($appId.StartsWith("MSIX\NotepadPlusPlus_", [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                if ($avail -match '^(?i)(winget|msstore)$') {
                    $srcCol = $avail
                    $avail  = ""
                }
                $hasUpdate = Test-AppUpdateGenuine -InstalledVer $version -AvailableVer $avail
                $clean = Get-CleanAppName $appName
                $rowSrc = if ($colOffsets.Count -lt 5 -and [string]::IsNullOrWhiteSpace($srcCol)) { "winget" } else { Resolve-WingetRowSource -AppId $appId -SrcCol $srcCol }
                $parsed.Add([PSCustomObject]@{
                    Name      = $appName
                    ID        = $appId
                    Version   = $version
                    Available = $(if ($hasUpdate) { $avail } else { "" })
                    HasUpdate = $hasUpdate
                    CleanName = $clean
                    Source    = $rowSrc
                })
            }
        }
    } elseif ($AllowHeaderless) {
        foreach ($line in $lines) {
            if (-not [string]::IsNullOrWhiteSpace($line) -and -not ($line.Trim().StartsWith("---"))) {
                $cols = [System.Text.RegularExpressions.Regex]::Split($line.Trim(), '\s{2,}')
                if ($cols.Count -ge 2) {
                    $appName = $cols[0].Trim()
                    $appId   = $cols[1].Trim()
                    if ($appId -notmatch '^(ARP|MSIX)\\|\S+\.\S+') { continue }
                    if ($appId.StartsWith("MSIX\NotepadPlusPlus_", [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                    $version = if ($cols.Count -ge 3) { $cols[2].Trim() } else { "" }
                    $c3      = if ($cols.Count -ge 4) { $cols[3].Trim() } else { "" }
                    $c4      = if ($cols.Count -ge 5) { $cols[4].Trim() } else { "" }
                    $srcCol  = ""
                    $avail   = ""
                    if ($c3 -match '^(?i)(winget|msstore)$' -and [string]::IsNullOrEmpty($c4)) {
                        $srcCol = $c3
                    } else {
                        $avail = $c3
                        if (-not [string]::IsNullOrEmpty($c4)) { $srcCol = $c4 }
                    }
                    $hasUpdate = Test-AppUpdateGenuine -InstalledVer $version -AvailableVer $avail
                    $clean = Get-CleanAppName $appName
                    $rowSrc = Resolve-WingetRowSource -AppId $appId -SrcCol $srcCol

                    $parsed.Add([PSCustomObject]@{
                        Name      = $appName
                        ID        = $appId
                        Version   = $version
                        Available = $(if ($hasUpdate) { $avail } else { "" })
                        HasUpdate = $hasUpdate
                        CleanName = $clean
                        Source    = $rowSrc
                    })
                }
            }
        }
    }

    return [PSCustomObject]@{ HasTable = ($separatorIndex -gt 0); Items = $parsed }
}

function Test-RegistryEntryIsBrokenOrphan {
    param([string]$UninstallString, [string]$InstallLocation, [string]$DisplayIcon)
    if (-not [string]::IsNullOrWhiteSpace($InstallLocation)) {
        $loc = $InstallLocation.Trim().Trim('"')
        if ($loc.Length -ge 3 -and $loc -match '^[a-zA-Z]:\\') {
            if (-not [System.IO.Directory]::Exists($loc)) {
                return $true
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($UninstallString) -and $UninstallString -notmatch '(?i)msiexec') {
        $u = $UninstallString.Trim()
        $exePath = ""
        if ($u.StartsWith('"')) {
            $q = $u.IndexOf('"', 1)
            if ($q -gt 1) { $exePath = $u.Substring(1, $q - 1) }
        } elseif ($u -match '(?i)^([a-zA-Z]:\\[^"]*?\.exe)\b') {
            $exePath = $Matches[1]
        }
        if (-not [string]::IsNullOrWhiteSpace($exePath) -and $exePath -match '^[a-zA-Z]:\\') {
            if (-not [System.IO.File]::Exists($exePath)) {
                return $true
            }
        }
    }
    return $false
}

function Get-ExecutableCleanVersion {
    param([string]$FilePath)
    if ([string]::IsNullOrWhiteSpace($FilePath) -or -not [System.IO.File]::Exists($FilePath)) { return "Installed" }
    try {
        $fvi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($FilePath)
        foreach ($cand in @($fvi.ProductVersion, $fvi.FileVersion)) {
            if (-not [string]::IsNullOrWhiteSpace($cand)) {
                $clean = ($cand -split '\+')[0].Trim()
                if ($clean -match '\d' -and $clean -notmatch '^0(\.0)+$') {
                    return $clean
                }
            }
        }
    } catch {}
    return "Installed"
}

function Get-LocalInstalledEntries {
    param(
        [switch]$SkipAppx,
        [scriptblock]$CancelCheck = $null
    )
    if ("DuckUtil.AppCatalogEngine" -as [type]) {
        try {
            $csType = [DuckUtil.AppCatalogEngine]
            if ($null -ne $csType.GetMethod("ScanCatalogSensorsAsync") -and (Get-Command "Wait-TaskNonBlocking" -ErrorAction SilentlyContinue)) {
                $scanTask = $csType::ScanCatalogSensorsAsync()
                if (Wait-TaskNonBlocking -Task $scanTask -TimeoutSeconds 30 -CancelCheck $CancelCheck) {
                    if ($scanTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                        return $scanTask.Result
                    }
                }
                $canceledNow = $script:isWindowClosing
                if (-not $canceledNow -and $CancelCheck) { try { $canceledNow = [bool](& $CancelCheck) } catch {} }
                if ($canceledNow) { return @() }
            }
            return [DuckUtil.AppCatalogEngine]::ScanCatalogSensors()
        } catch {}
    }

    $localItems = [System.Collections.Generic.List[object]]::new()
    $regConfigs = @(
        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; SubKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';             Prefix = 'ARP\Machine\X64\' },
        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; SubKey = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Prefix = 'ARP\Machine\X86\' },
        @{ Hive = [Microsoft.Win32.Registry]::CurrentUser;  SubKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';             Prefix = 'ARP\User\X64\' },
        @{ Hive = [Microsoft.Win32.Registry]::CurrentUser;  SubKey = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Prefix = 'ARP\User\X86\' }
    )

    foreach ($cfg in $regConfigs) {
        $baseKey = $null
        try {
            $baseKey = $cfg.Hive.OpenSubKey($cfg.SubKey, $false)
            if ($null -eq $baseKey) { continue }
            foreach ($subName in $baseKey.GetSubKeyNames()) {
                $subKey = $null
                try {
                    $subKey = $baseKey.OpenSubKey($subName, $false)
                    if ($null -eq $subKey) { continue }
                    $dispName = [string]$subKey.GetValue('DisplayName', '')
                    if ([string]::IsNullOrWhiteSpace($dispName)) { continue }
                    $sysComp = $subKey.GetValue('SystemComponent', 0)
                    if ($sysComp -eq 1) { continue }
                    $relType = [string]$subKey.GetValue('ReleaseType', '')
                    if (-not [string]::IsNullOrWhiteSpace($relType) -and $relType -match '(?i)Update|Hotfix') { continue }
                    if ($dispName -match 'Additional Runtime|Minimum Runtime|Debug Runtime|IntelliSense|Language Pack') { continue }

                    $uninstStr  = [string]$subKey.GetValue('UninstallString', '')
                    $installLoc = [string]$subKey.GetValue('InstallLocation', '')
                    $dispIcon   = [string]$subKey.GetValue('DisplayIcon', '')
                    if (Test-RegistryEntryIsBrokenOrphan -UninstallString $uninstStr -InstallLocation $installLoc -DisplayIcon $dispIcon) {
                        continue
                    }

                    $dispVer = [string]$subKey.GetValue('DisplayVersion', '')
                    $localItems.Add([PSCustomObject]@{
                        Name      = $dispName.Trim()
                        ID        = ($cfg.Prefix + $subName)
                        Version   = $dispVer
                        Available = ""
                        HasUpdate = $false
                        CleanName = (Get-CleanAppName $dispName)
                        Source    = "local"
                    })
                } catch {} finally {
                    if ($null -ne $subKey) { $subKey.Dispose() }
                }
            }
        } catch {} finally {
            if ($null -ne $baseKey) { $baseKey.Dispose() }
        }
    }

    try {
        $ndpKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full', $false)
        if ($ndpKey) {
            try {
                $release = [int]$ndpKey.GetValue('Release', 0)
                $ndpVer  = [string]$ndpKey.GetValue('Version', '4.8.1')
                if ($release -ge 533320) {
                    $localItems.Add([PSCustomObject]@{
                        Name      = "Microsoft .NET Framework 4.8.1 Runtime"
                        ID        = "Microsoft.DotNet.Framework.Runtime"
                        Version   = $ndpVer
                        Available = ""
                        HasUpdate = $false
                        CleanName = "microsoft .net framework 4.8.1 runtime"
                        Source    = "local"
                    })
                }
            } finally {
                $ndpKey.Dispose()
            }
        }
    } catch {}

    $pf64Dn = if ($env:ProgramW6432) { $env:ProgramW6432 } else { [Environment]::GetFolderPath('ProgramFiles') }
    $pf86Dn = if (${env:ProgramFiles(x86)}) { ${env:ProgramFiles(x86)} } else { [Environment]::GetFolderPath('ProgramFilesX86') }
    $dotnetSharedConfigs = @()
    if ($pf64Dn) { $dotnetSharedConfigs += @{ Path = (Join-Path $pf64Dn "dotnet\shared\Microsoft.WindowsDesktop.App"); Suffix = ""; ArchLabel = "(x64)" } }
    if ($pf86Dn) { $dotnetSharedConfigs += @{ Path = (Join-Path $pf86Dn "dotnet\shared\Microsoft.WindowsDesktop.App"); Suffix = ".x86"; ArchLabel = "(x86)" } }
    foreach ($dnCfg in $dotnetSharedConfigs) {
        if ([System.IO.Directory]::Exists($dnCfg.Path)) {
            try {
                $verDirs = [System.IO.Directory]::GetDirectories($dnCfg.Path)
                $byMajor = @{}
                foreach ($vd in $verDirs) {
                    $vName = [System.IO.Path]::GetFileName($vd)
                    if ($vName -match '^(\d+)\.(\d+)\.') {
                        $maj = $Matches[1]
                        $min = $Matches[2]
                        $trackKey = if ($maj -eq "3" -and $min -eq "1") { "3_1" } elseif ($vName -match 'preview|rc|alpha|beta') { "Preview" } else { $maj }
                        if (-not $byMajor.ContainsKey($trackKey) -or (Compare-AppVersions $vName $byMajor[$trackKey]) -gt 0) {
                            $byMajor[$trackKey] = $vName
                        }
                    }
                }
                foreach ($tk in $byMajor.Keys) {
                    if ($dnCfg.Suffix -eq ".x86" -and $tk -notin @("6", "7", "8")) { continue }
                    $bestV = $byMajor[$tk]
                    $synId = "Microsoft.DotNet.DesktopRuntime.$tk$($dnCfg.Suffix)"
                    $localItems.Add([PSCustomObject]@{
                        Name      = "Microsoft Windows Desktop Runtime - $bestV $($dnCfg.ArchLabel)"
                        ID        = $synId
                        Version   = $bestV
                        Available = ""
                        HasUpdate = $false
                        CleanName = "microsoft windows runtime $bestV"
                        Source    = "local"
                    })
                }
            } catch {}
        }
    }

    $pathDirs = [System.Collections.Generic.List[string]]::new()
    foreach ($rawDir in ($env:PATH -split ';')) {
        if (-not [string]::IsNullOrWhiteSpace($rawDir)) {
            $cleanD = $rawDir.Trim().Trim('"')
            if ($cleanD.Length -gt 2 -and [System.IO.Directory]::Exists($cleanD)) {
                $pathDirs.Add($cleanD)
            }
        }
    }

    $pyScriptsYtdlp = [System.Collections.Generic.List[string]]::new()
    try {
        $pyRoot = "$env:LOCALAPPDATA\Programs\Python"
        if ([System.IO.Directory]::Exists($pyRoot)) {
            foreach ($pyDir in [System.IO.Directory]::GetDirectories($pyRoot, "Python3*")) {
                $pyScriptsYtdlp.Add((Join-Path $pyDir "Scripts\yt-dlp.exe"))
            }
        }
    } catch {}
    $neovimRoot = if ($env:ProgramW6432) { $env:ProgramW6432 } elseif ($env:ProgramFiles) { $env:ProgramFiles } else { "C:\Program Files" }

    $cliProbes = @(
        @{ ID = "Google.AntigravityCLI";     Name = "Antigravity CLI";       Cmd = "agy.exe";         Paths = @("$env:LOCALAPPDATA\agy\bin\agy.exe") },
        @{ ID = "astral-sh.uv";              Name = "uv (Python Manager)";   Cmd = "uv.exe";          Paths = @("$env:USERPROFILE\.local\bin\uv.exe", "$env:USERPROFILE\.cargo\bin\uv.exe") },
        @{ ID = "yt-dlp.yt-dlp";             Name = "yt-dlp";                Cmd = "yt-dlp.exe";      Paths = @($pyScriptsYtdlp) },
        @{ ID = "Gyan.FFmpeg";               Name = "FFmpeg";                Cmd = "ffmpeg.exe";      Paths = @() },
        @{ ID = "aria2.aria2";               Name = "aria2";                 Cmd = "aria2c.exe";      Paths = @() },
        @{ ID = "Rclone.Rclone";             Name = "Rclone";                Cmd = "rclone.exe";      Paths = @() },
        @{ ID = "Oven-sh.Bun";               Name = "Bun";                   Cmd = "bun.exe";         Paths = @("$env:USERPROFILE\.bun\bin\bun.exe") },
        @{ ID = "pnpm.pnpm";                 Name = "pnpm";                  Cmd = "pnpm.exe";        Paths = @("$env:LOCALAPPDATA\pnpm\pnpm.exe", "$env:APPDATA\npm\pnpm.cmd") },
        @{ ID = "Yarn.Yarn";                 Name = "Yarn";                  Cmd = "yarn.cmd";        Paths = @("$env:APPDATA\npm\yarn.cmd") },
        @{ ID = "Fastfetch-cli.Fastfetch";   Name = "Fastfetch";             Cmd = "fastfetch.exe";   Paths = @() },
        @{ ID = "JanDeDobbeleer.OhMyPosh";   Name = "Oh My Posh";            Cmd = "oh-my-posh.exe";  Paths = @("$env:LOCALAPPDATA\Programs\oh-my-posh\bin\oh-my-posh.exe") },
        @{ ID = "Neovim.Neovim";             Name = "Neovim";                Cmd = "nvim.exe";        Paths = @("$neovimRoot\Neovim\bin\nvim.exe") },
        @{ ID = "Google.PlatformTools";      Name = "ADB & Fastboot";        Cmd = "adb.exe";         Paths = @("$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe") },
        @{ ID = "Gitleaks.Gitleaks";         Name = "Gitleaks";              Cmd = "gitleaks.exe";    Paths = @() }
    )
    foreach ($probe in $cliProbes) {
        $foundBin = ""
        foreach ($fixedP in $probe.Paths) {
            if (-not [string]::IsNullOrWhiteSpace($fixedP) -and [System.IO.File]::Exists($fixedP)) {
                $foundBin = $fixedP
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($foundBin)) {
            foreach ($pd in $pathDirs) {
                $candP = Join-Path $pd $probe.Cmd
                if ([System.IO.File]::Exists($candP)) {
                    $foundBin = $candP
                    break
                }
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($foundBin)) {
            $binVer = Get-ExecutableCleanVersion -FilePath $foundBin
            $localItems.Add([PSCustomObject]@{
                Name      = $probe.Name
                ID        = $probe.ID
                Version   = $binVer
                Available = ""
                HasUpdate = $false
                CleanName = (Get-CleanAppName $probe.Name)
                Source    = "local"
            })
        }
    }

    $llPaths = @(
        (Join-Path $env:APPDATA ".tlauncher\legacy\Minecraft\TL.exe"),
        (Join-Path $env:APPDATA ".tlauncher\legacy"),
        (Join-Path $env:APPDATA ".minecraft\LLauncher.exe"),
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Legacy Launcher.lnk")
    )
    foreach ($lp in $llPaths) {
        if (($lp -and [System.IO.File]::Exists($lp)) -or ($lp -and [System.IO.Directory]::Exists($lp))) {
            $localItems.Add([PSCustomObject]@{
                Name      = "Legacy Launcher"
                ID        = "LegacyLauncher.LegacyLauncher"
                Version   = "Installed"
                Available = ""
                HasUpdate = $false
                CleanName = "legacylauncher"
                Source    = "local"
            })
            break
        }
    }

    if (-not $SkipAppx) {
        if ($script:isWindowClosing) { return [object[]]@($localItems.ToArray()) }
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}
        if ($script:isWindowClosing) { return [object[]]@($localItems.ToArray()) }
        try {
            foreach ($pkg in (Get-AppxPackage -ErrorAction SilentlyContinue)) {
                if ($pkg.IsFramework -or [string]::IsNullOrWhiteSpace($pkg.Name)) { continue }
                $pkgName = [string]$pkg.Name
                if ($pkgName -match '^(Microsoft\.Windows\.|MicrosoftWindows\.|Windows\.|Microsoft\.UI\.Xaml|Microsoft\.VCLibs|Microsoft\.NET\.Native|Microsoft\.WinAppRuntime|Microsoft\.Services\.Store)') {
                    continue
                }
                $localItems.Add([PSCustomObject]@{
                    Name      = $pkgName
                    ID        = "MSIX\" + [string]$pkg.PackageFullName
                    Version   = [string]$pkg.Version
                    Available = ""
                    HasUpdate = $false
                    CleanName = (Get-CleanAppName $pkgName)
                    Source    = "local"
                })
            }
        } catch {}
    }

    return $localItems
}

$script:cachedCatalogMatchTargets = $null
$script:cachedCatalogMatchCount   = -1

function Get-CatalogMatchTargetsCached {
    if (-not $allItemBorders -or $allItemBorders.Count -eq 0) { return [DuckUtil.CatalogMatchTarget[]]@() }
    if ($null -ne $script:cachedCatalogMatchTargets -and $script:cachedCatalogMatchCount -eq $allItemBorders.Count) {
        return $script:cachedCatalogMatchTargets
    }
    $n = $allItemBorders.Count
    $arr = [DuckUtil.CatalogMatchTarget[]]::new($n)
    for ($i = 0; $i -lt $n; $i++) {
        $app = $allItemBorders[$i].Tag.App
        $t = [DuckUtil.CatalogMatchTarget]::new()
        $t.ID = [string]$app.ID
        $t.Name = [string]$app.Name
        $t.Category = [string]$app.Category
        if ($app.Aliases) {
            $t.Aliases = [string[]]@($app.Aliases)
        } else {
            $t.Aliases = [string[]]@()
        }
        $arr[$i] = $t
    }
    $script:cachedCatalogMatchTargets = $arr
    $script:cachedCatalogMatchCount = $n
    return $arr
}

function Apply-InstalledDatabaseToRows {
    param(
        $IdMap,
        $NameMap,
        $CleanNameMap,
        $InstalledList,
        [scriptblock]$CancelCheck = $null,
        [switch]$PreserveOutdatedOnLocalFallback
    )

    $prevOutdatedSnapshot = $null
    if ($PreserveOutdatedOnLocalFallback -and $allItemBorders -and $allItemBorders.Count -gt 0) {
        $prevOutdatedSnapshot = @{}
        for ($pi = 0; $pi -lt $allItemBorders.Count; $pi++) {
            $pt = $allItemBorders[$pi].Tag
            if ($pt -and $pt.Status -eq "OUTDATED") {
                $prevAv = ""
                if ($pt.UpdateText -and -not [string]::IsNullOrWhiteSpace($pt.UpdateText.Text)) {
                    $rawAv = [string]$pt.UpdateText.Text
                    if ($rawAv.StartsWith("↑ ") -and $rawAv -ne "↑ Mới") {
                        $prevAv = $rawAv.Substring(2).Trim()
                    }
                }
                $prevOutdatedSnapshot[$pi] = @{
                    Version   = [string]$pt.InstalledVersion
                    Available = $prevAv
                }
            }
        }
    }

    $countInstalled = 0
    $countLatest = 0
    $countOutdated = 0

    $csMatchType = "DuckUtil.AppCatalogEngine" -as [type]
    if ($csMatchType -and $null -ne $csMatchType.GetMethod("MatchCatalogApps")) {
        $targets = Get-CatalogMatchTargetsCached
        $instCount = if ($InstalledList) { $InstalledList.Count } else { 0 }
        $sensorArr = [DuckUtil.CatalogSensorItem[]]::new($instCount)
        for ($si = 0; $si -lt $instCount; $si++) {
            $item = $InstalledList[$si]
            if ($item -is [DuckUtil.CatalogSensorItem]) {
                $sensorArr[$si] = $item
            } elseif ($null -ne $item) {
                $obj = [DuckUtil.CatalogSensorItem]::new()
                $obj.Name      = [string]$item.Name
                $obj.ID        = [string]$item.ID
                $obj.Version   = [string]$item.Version
                $obj.Available = [string]$item.Available
                $obj.HasUpdate = [bool]$item.HasUpdate
                $obj.CleanName = [string]$item.CleanName
                $obj.Source    = [string]$item.Source
                $sensorArr[$si] = $obj
            }
        }

        $matchedArr = $null
        if ($null -ne $csMatchType.GetMethod("MatchCatalogAppsAsync") -and (Get-Command "Wait-TaskNonBlocking" -ErrorAction SilentlyContinue) -and $window -and $window.Dispatcher -and $window.Dispatcher.CheckAccess()) {
            $mTask = [DuckUtil.AppCatalogEngine]::MatchCatalogAppsAsync($targets, $sensorArr)
            [void](Wait-TaskNonBlocking -Task $mTask -TimeoutSeconds 15 -CancelCheck $CancelCheck)
            $canceledApply = $script:isWindowClosing
            if (-not $canceledApply -and $CancelCheck) { try { $canceledApply = [bool](& $CancelCheck) } catch {} }
            if ($canceledApply) {
                return [PSCustomObject]@{ Installed = 0; Latest = 0; Outdated = 0; Canceled = $true }
            }
            if ($mTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                $matchedArr = $mTask.Result
            }
        }
        if ($null -eq $matchedArr) {
            $matchedArr = [DuckUtil.AppCatalogEngine]::MatchCatalogApps($targets, $sensorArr)
        }

        $rowCount = $allItemBorders.Count
        for ($ri = 0; $ri -lt $rowCount; $ri++) {
            $row = $allItemBorders[$ri]
            $tag = $row.Tag
            $app = $tag.App
            $tb  = $tag.NameText
            $updateBadge = $tag.UpdateBadge
            $updateText  = $tag.UpdateText
            $idnPrefix = if ($app.IDn) { "[#$($app.IDn)] " } else { "" }
            $info = if ($matchedArr -and $ri -lt $matchedArr.Length) { $matchedArr[$ri] } else { $null }

            if ($null -ne $info) {
                $countInstalled++
                $effectiveHasUpdate = [bool]($info.HasUpdate -eq $true)
                $effectiveAvailable = [string]$info.Available
                if (-not $effectiveHasUpdate -and $prevOutdatedSnapshot -and $prevOutdatedSnapshot.ContainsKey($ri)) {
                    $snapOut = $prevOutdatedSnapshot[$ri]
                    $stillOut = if (-not [string]::IsNullOrWhiteSpace($snapOut.Available)) {
                        [DuckUtil.AppCatalogEngine]::TestAppUpdateGenuine([string]$info.Version, [string]$snapOut.Available)
                    } else {
                        [string]$info.Version -eq $snapOut.Version
                    }
                    if ($stillOut) {
                        $effectiveHasUpdate = $true
                        $effectiveAvailable = $snapOut.Available
                    }
                }

                $prevStatus = $tag.Status
                $prevVer = $tag.InstalledVersion
                $prevDet = $tag.DetectedId
                $tag.DetectedId = $info.ID
                $tag.InstalledVersion = $info.Version
                if ($tag.PSObject.Properties['AvailableVersion']) {
                    $tag.AvailableVersion = if ($effectiveHasUpdate) { $effectiveAvailable } else { $null }
                } else {
                    Add-Member -InputObject $tag -NotePropertyName AvailableVersion -NotePropertyValue $(if ($effectiveHasUpdate) { $effectiveAvailable } else { $null }) -Force
                }

                if ($effectiveHasUpdate) {
                    $countOutdated++
                    $newBadgeTxt = if ($effectiveAvailable) { "↑ $effectiveAvailable" } else { "↑ Mới" }
                    if ($prevStatus -ne "OUTDATED" -or $prevVer -ne $info.Version -or $prevDet -ne $info.ID -or ($updateText -and $updateText.Text -ne $newBadgeTxt)) {
                        $tag.Status = "OUTDATED"
                        if ($tb) {
                            $tb.Foreground = $script:brushOutdatedFg
                            $tb.Text = $app.Name
                            $tb.TextDecorations = $null
                        }
                        if ($updateBadge -and $updateText) {
                            $updateText.Text = $newBadgeTxt
                            $updateBadge.Visibility = [System.Windows.Visibility]::Visible
                        }
                        $row.ToolTip = "$idnPrefix$($app.Name)`nĐang cài: $($info.Version)`nCó bản mới: $effectiveAvailable`nID phát hiện: $($info.ID)"
                    }
                } else {
                    $countLatest++
                    $badgeStillShown = ($updateBadge -and $updateBadge.Visibility -ne [System.Windows.Visibility]::Collapsed)
                    if ($prevStatus -ne "LATEST" -or $prevVer -ne $info.Version -or $prevDet -ne $info.ID -or $badgeStillShown) {
                        $tag.Status = "LATEST"
                        if ($tb) {
                            $tb.Foreground = $script:brushLatestFg
                            $tb.Text = $app.Name
                            $tb.TextDecorations = $null
                        }
                        if ($badgeStillShown) {
                            $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed
                        }
                        $row.ToolTip = "$idnPrefix$($app.Name)`nPhiên bản: $($info.Version) (Mới nhất)`nID phát hiện: $($info.ID)"
                    }
                }
            } else {
                $prevStatus = $tag.Status
                $tag.DetectedId = $null
                $tag.InstalledVersion = $null
                if ($tag.PSObject.Properties['AvailableVersion']) { $tag.AvailableVersion = $null }
                $badgeStillShown = ($updateBadge -and $updateBadge.Visibility -ne [System.Windows.Visibility]::Collapsed)
                if ($prevStatus -ne "NONE" -or $badgeStillShown) {
                    $tag.Status = "NONE"
                    if ($tb) {
                        $tb.Foreground = $script:brushNoneFg
                        $tb.Text = $app.Name
                        $tb.TextDecorations = $null
                    }
                    if ($badgeStillShown) {
                        $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed
                    }
                    $row.ToolTip = "$idnPrefix$($app.Name)`nTrạng thái: Chưa cài đặt`nID: $($app.ID)"
                }
            }
        }

        return [PSCustomObject]@{
            Installed = $countInstalled
            Latest    = $countLatest
            Outdated  = $countOutdated
        }
    }

    $lookupCache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $tokenIndex  = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($instItem in $InstalledList) {
        $rawText = "$($instItem.ID) $($instItem.Name) $($instItem.CleanName)"
        $tokens = [System.Text.RegularExpressions.Regex]::Split($rawText, '[^a-zA-Z0-9+]+')
        $seenTokens = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($tk in $tokens) {
            if ($tk.Length -ge 3 -and $seenTokens.Add($tk)) {
                $bucket = $null
                if (-not $tokenIndex.TryGetValue($tk, [ref]$bucket)) {
                    $bucket = [System.Collections.Generic.List[object]]::new()
                    $tokenIndex[$tk] = $bucket
                }
                $bucket.Add($instItem)
            }
        }
    }

    function Find-InstalledAppFast {
        param($targetApp)

        $targetId = $targetApp.ID
        $cachedMatch = $null
        if ($lookupCache.TryGetValue($targetId, [ref]$cachedMatch)) {
            return $cachedMatch
        }

        $meta = Get-TargetAppMeta $targetApp
        $match = $null
        if ($IdMap.TryGetValue($targetId, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        foreach ($alPair in $meta.CleanAliases) {
            $alias = $alPair.Raw
            if ($IdMap.TryGetValue($alias, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
                $lookupCache[$targetId] = $match
                return $match
            }
        }

        if ($targetApp.Name -and $NameMap.TryGetValue($targetApp.Name, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        foreach ($alPair in $meta.CleanAliases) {
            $alias = $alPair.Raw
            if ($NameMap.TryGetValue($alias, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
                $lookupCache[$targetId] = $match
                return $match
            }
            $cleanAlias = $alPair.Clean
            if ($cleanAlias.Length -ge 2 -and $CleanNameMap.TryGetValue($cleanAlias, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
                $lookupCache[$targetId] = $match
                return $match
            }
        }

        $cleanTarget = $meta.CleanTarget
        if ($cleanTarget.Length -ge 2 -and $CleanNameMap.TryGetValue($cleanTarget, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        $candidatePool = [System.Collections.Generic.List[object]]::new()
        $seenCand = [System.Collections.Generic.HashSet[object]]::new()

        foreach ($qt in $meta.QueryTokens) {
            $bucket = $null
            if ($tokenIndex.TryGetValue($qt, [ref]$bucket)) {
                foreach ($bItem in $bucket) {
                    if ($seenCand.Add($bItem)) {
                        $candidatePool.Add($bItem)
                    }
                }
            }
        }

        if ($candidatePool.Count -eq 0) {
            $lookupCache[$targetId] = $null
            return $null
        }

        $bestCandidate = $null
        $bestScore = 0
        $aliasEntries = $meta.AliasEntries
        $patternClean = $meta.PatternClean

        foreach ($item in $candidatePool) {
            $score = 0
            foreach ($ae in $aliasEntries) {
                $rawAl = $ae.Raw
                if ($item.ID.IndexOf($rawAl, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and $item.ID -match $ae.Pattern) {
                    $score = 780
                    break
                }
                if ($item.Name.IndexOf($rawAl, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and $item.Name -match $ae.Pattern) {
                    $lenRatio = [Math]::Min(40, [int](($cleanTarget.Length * 40) / [Math]::Max(1, $item.Name.Length)))
                    $candScore = 700 + $lenRatio
                    if ($candScore -gt $score) { $score = $candScore }
                }
            }
            if ($score -eq 0 -and $patternClean -and $item.CleanName.IndexOf($cleanTarget, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and $item.CleanName -match $patternClean) {
                $lenRatio = [Math]::Min(40, [int](($cleanTarget.Length * 40) / [Math]::Max(1, $item.CleanName.Length)))
                $score = 650 + $lenRatio
            }
            if ($score -gt 0) {
                if ($item.HasUpdate) { $score += 15 }
                if ($item.ID -notmatch '^(ARP|MSIX|LOCAL)\\') { $score += 10 }
                if ($score -gt $bestScore -and (Test-MatchCompatible $targetApp $item)) {
                    $bestScore = $score
                    $bestCandidate = $item
                }
            }
        }

        $lookupCache[$targetId] = $bestCandidate
        return $bestCandidate
    }

    $countInstalled = 0
    $countLatest = 0
    $countOutdated = 0

    for ($ri = 0; $ri -lt $allItemBorders.Count; $ri++) {
        $row = $allItemBorders[$ri]
        $app = $row.Tag.App
        $grid = $row.Child
        $tb = if ($row.Tag.NameText) { $row.Tag.NameText } elseif ($grid -and $grid.Children.Count -gt 2) { $grid.Children[2] } else { $null }
        $updateBadge = $row.Tag.UpdateBadge
        $updateText  = $row.Tag.UpdateText
        $idnPrefix = if ($app.IDn) { "[#$($app.IDn)] " } else { "" }

        $info = Find-InstalledAppFast $app

        if ($info) {
            $countInstalled++
            $effHasUpd = [bool]($info.HasUpdate -eq $true)
            $effAvail = [string]$info.Available
            if (-not $effHasUpd -and $prevOutdatedSnapshot -and $prevOutdatedSnapshot.ContainsKey($ri)) {
                $snapOutPs = $prevOutdatedSnapshot[$ri]
                $stillOutPs = if (-not [string]::IsNullOrWhiteSpace($snapOutPs.Available)) {
                    Test-AppUpdateGenuine -InstalledVer ([string]$info.Version) -AvailableVer ([string]$snapOutPs.Available)
                } else {
                    [string]$info.Version -eq $snapOutPs.Version
                }
                if ($stillOutPs) {
                    $effHasUpd = $true
                    $effAvail = $snapOutPs.Available
                }
            }
            $row.Tag.DetectedId = $info.ID
            $row.Tag.InstalledVersion = $info.Version
            if ($row.Tag.PSObject.Properties['AvailableVersion']) {
                $row.Tag.AvailableVersion = if ($effHasUpd) { $effAvail } else { $null }
            } else {
                Add-Member -InputObject $row.Tag -NotePropertyName AvailableVersion -NotePropertyValue $(if ($effHasUpd) { $effAvail } else { $null }) -Force
            }

            if ($effHasUpd) {
                $countOutdated++
                $row.Tag.Status = "OUTDATED"
                if ($tb) {
                    $tb.Foreground = $script:brushOutdatedFg
                    $tb.Text = $app.Name
                    $tb.TextDecorations = $null
                }
                if ($updateBadge -and $updateText) {
                    $updateText.Text = if ($effAvail) { "↑ $effAvail" } else { "↑ Mới" }
                    $updateBadge.Visibility = [System.Windows.Visibility]::Visible
                }
                $tip = "$idnPrefix$($app.Name)`nĐang cài: $($info.Version)`nCó bản mới: $effAvail`nID phát hiện: $($info.ID)"
                $row.ToolTip = $tip
            } else {
                $countLatest++
                $row.Tag.Status = "LATEST"
                if ($tb) {
                    $tb.Foreground = $script:brushLatestFg
                    $tb.Text = $app.Name
                    $tb.TextDecorations = $null
                }
                if ($updateBadge -and $updateBadge.Visibility -ne [System.Windows.Visibility]::Collapsed) {
                    $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed
                }
                $tip = "$idnPrefix$($app.Name)`nPhiên bản: $($info.Version) (Mới nhất)`nID phát hiện: $($info.ID)"
                $row.ToolTip = $tip
            }
        } else {
            $prevStatus = $row.Tag.Status
            $row.Tag.DetectedId = $null
            $row.Tag.InstalledVersion = $null
            if ($row.Tag.PSObject.Properties['AvailableVersion']) { $row.Tag.AvailableVersion = $null }
            if ($prevStatus -ne "NONE") {
                $row.Tag.Status = "NONE"
                if ($tb) {
                    $tb.Foreground = $script:brushNoneFg
                    $tb.Text = $app.Name
                    $tb.TextDecorations = $null
                }
                if ($updateBadge -and $updateBadge.Visibility -ne [System.Windows.Visibility]::Collapsed) {
                    $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed
                }
                $tip = "$idnPrefix$($app.Name)`nTrạng thái: Chưa cài đặt`nID: $($app.ID)"
                $row.ToolTip = $tip
            }
        }
    }

    return [PSCustomObject]@{
        Installed = $countInstalled
        Latest    = $countLatest
        Outdated  = $countOutdated
    }
}

function Scan-And-ColorizeApps {
    param(
        [switch]$Quiet,
        [switch]$ForceSourceRefresh
    )
    if ($script:isWindowClosing) { return }
    if ($Quiet) {
        if ($script:isScanningApps -or $script:isActionRunning -or $script:isUpdatingUninstaller -or $script:isUninstallingQueue -or $script:isAutoRefreshing) {
            return
        }
        $script:isAutoRefreshing = $true
        $script:cancelAutoScan = $false
        $script:autoScanGeneration++
        $script:activeAutoScanGen = $script:autoScanGeneration
    } else {
        if ($script:isAutoRefreshing -and (Get-Command "Stop-ActiveAutoScan" -ErrorAction SilentlyContinue)) {
            Stop-ActiveAutoScan
            $script:isAutoRefreshing = $false
            $script:cancelAutoScan = $false
        }
        if ($script:isScanningApps) {
            Log-Text "[!] Tiến trình quét ứng dụng đang chạy, bỏ qua yêu cầu trùng lặp."
            return
        }
    }

    $cancelBlock = if ($Quiet) {
        { $script:isWindowClosing -or $script:cancelAutoScan -or ($script:autoScanGeneration -ne $script:activeAutoScanGen) }
    } else {
        { $script:isWindowClosing }
    }

    $script:isScanningApps = $true
    try {
        if (-not $Quiet) {
            Log-Text "[SCAN] Đang quét hệ thống (Registry, Runtimes, CLI & WinGet)..."
            if ($txtStatus) { $txtStatus.Text = "Đang quét hệ thống..." }
            if ($btnScanInstalled) {
                $btnScanInstalled.Content = "Đang làm mới..."
                $btnScanInstalled.IsEnabled = $false
            }
            if ($progressBar) {
                $progressBar.Value = 0
                $progressBar.IsIndeterminate = $true
            }
            if ($ForceSourceRefresh) {
                Stop-PreSpawnedWinget
                if (-not $script:isUpdatingUninstaller) {
                    $script:cachedUninstallerApps = @()
                }
                if ($script:uninstallerLoadedOnce) {
                    $script:uninstallerStale = $true
                }
                $srcUpd = Invoke-WingetListCapture -Arguments "source update --disable-interactivity" -TimeoutSeconds 12 -CancelCheck $cancelBlock
                if ($srcUpd.WasCanceled -or (& $cancelBlock)) { return }
            }
        }
        if (& $cancelBlock) { return }

        $localItems = Get-LocalInstalledEntries -SkipAppx -CancelCheck $cancelBlock
        if (& $cancelBlock) { return }
        $useCsFastMatcher = ($null -ne ("DuckUtil.AppCatalogEngine" -as [type])) -and ($null -ne ([DuckUtil.AppCatalogEngine].GetMethod("MatchCatalogApps")))
        $idMap        = if (-not $useCsFastMatcher) { [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase) } else { $null }
        $nameMap      = if (-not $useCsFastMatcher) { [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase) } else { $null }
        $cleanNameMap = if (-not $useCsFastMatcher) { [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase) } else { $null }
        $installedList = [System.Collections.Generic.List[object]]::new()

        foreach ($locObj in $localItems) {
            $installedList.Add($locObj)
            if (-not $useCsFastMatcher) {
                if ($locObj.ID -and -not $idMap.ContainsKey($locObj.ID)) { $idMap[$locObj.ID] = $locObj } else { Set-PreferredMapEntry $idMap $locObj.ID $locObj }
                if ($locObj.Name -and -not $nameMap.ContainsKey($locObj.Name)) { $nameMap[$locObj.Name] = $locObj } else { Set-PreferredMapEntry $nameMap $locObj.Name $locObj }
                if ($locObj.CleanName.Length -ge 2) {
                    if (-not $cleanNameMap.ContainsKey($locObj.CleanName)) { $cleanNameMap[$locObj.CleanName] = $locObj } else { Set-PreferredMapEntry $cleanNameMap $locObj.CleanName $locObj }
                }
            }
        }

        $localSigParts = [System.Collections.Generic.List[string]]::new($installedList.Count)
        foreach ($locS in $installedList) {
            $localSigParts.Add("$($locS.ID)=$($locS.Version)")
        }
        $localSigParts.Sort([System.StringComparer]::OrdinalIgnoreCase)
        $localFingerprint = ($localSigParts -join ';')
        $localChanged = ($localFingerprint -ne $script:lastLocalScanSig)
        if ($localChanged) {
            if (-not $script:isUpdatingUninstaller) {
                $script:cachedUninstallerApps = @()
            }
            if ($script:uninstallerLoadedOnce) {
                $script:uninstallerStale = $true
            }
        }

        if (-not $Quiet -and $allItemBorders -and $allItemBorders.Count -gt 0 -and -not $script:hasCompletedAppScan) {
            $preStats = Apply-InstalledDatabaseToRows -IdMap $idMap -NameMap $nameMap -CleanNameMap $cleanNameMap -InstalledList $installedList -CancelCheck $cancelBlock
            if (& $cancelBlock) { return }
            if ($txtStatus) {
                $txtStatus.Text = "Tìm thấy $($preStats.Installed) ứng dụng • đang kiểm tra cập nhật..."
            }
        }

        $wingetItems = [System.Collections.Generic.List[object]]::new()
        $wingetOk = $false
        $wingetMissing = $false

        try {
            $wgTimeout = if ($Quiet) { 22 } else { 35 }
            $primary = Invoke-WingetListCapture -Arguments "list --source winget --disable-interactivity --accept-source-agreements" -TimeoutSeconds $wgTimeout -CancelCheck $cancelBlock -TrackAsAuto:$Quiet
            if ($primary.WasCanceled -or (& $cancelBlock)) { return }
            if (-not $primary.Available) {
                $wingetMissing = $true
                if (-not $Quiet) { Log-Text "[WARN] Chưa có WinGet; chuyển sang quét cục bộ qua Registry, Runtimes & Appx." }
            } else {
                $parsedPrimary = ConvertFrom-WingetListOutput -RawText $primary.StdOut -AllowHeaderless ($primary.ExitCode -eq 0 -and -not $primary.TimedOut)
                if (-not $primary.TimedOut -and (($primary.ExitCode -eq 0 -and $parsedPrimary.Items.Count -gt 0) -or ($parsedPrimary.HasTable -and $parsedPrimary.Items.Count -gt 0))) {
                    $wingetItems = $parsedPrimary.Items
                    $wingetOk = $true
                } elseif (-not $Quiet) {
                    if ($primary.TimedOut) {
                        Log-Text "[WARN] WinGet (--source winget) quá thời gian chờ (35s); đang thử lại toàn nguồn..."
                    } else {
                        Log-Text "[WARN] WinGet (--source winget) trả về mã $($primary.ExitCode) ($($parsedPrimary.Items.Count) dòng); đang thử lại toàn nguồn..."
                        if (-not [string]::IsNullOrWhiteSpace($primary.StdErr)) {
                            Log-Text "[stderr] $($primary.StdErr.Trim())"
                        }
                    }

                    if (& $cancelBlock) { return }
                    $fallbackWg = Invoke-WingetListCapture -Arguments "list --disable-interactivity --accept-source-agreements" -TimeoutSeconds 25 -CancelCheck $cancelBlock -TrackAsAuto:$Quiet
                    if ($fallbackWg.WasCanceled -or (& $cancelBlock)) { return }
                    $parsedFallback = ConvertFrom-WingetListOutput -RawText $fallbackWg.StdOut -AllowHeaderless ($fallbackWg.ExitCode -eq 0 -and -not $fallbackWg.TimedOut)

                    if (-not $fallbackWg.TimedOut -and $fallbackWg.ExitCode -eq 0 -and $parsedFallback.Items.Count -gt 0) {
                        $wingetItems = $parsedFallback.Items
                        $wingetOk = $true
                    } elseif ($parsedPrimary.HasTable -and $parsedPrimary.Items.Count -gt $parsedFallback.Items.Count) {
                        $wingetItems = $parsedPrimary.Items
                        $wingetOk = $true
                    } elseif ($parsedFallback.HasTable -and $parsedFallback.Items.Count -gt 0) {
                        $wingetItems = $parsedFallback.Items
                        $wingetOk = $true
                    }
                }

                if ($wingetOk -and -not (& $cancelBlock)) {
                    $msStoreCap = Invoke-WingetListCapture -Arguments "list --source msstore --disable-interactivity --accept-source-agreements" -TimeoutSeconds 10 -CancelCheck $cancelBlock -TrackAsAuto:$Quiet
                    if ($msStoreCap.WasCanceled -or (& $cancelBlock)) { return }
                    if ($msStoreCap.Available -and -not $msStoreCap.TimedOut -and -not [string]::IsNullOrWhiteSpace($msStoreCap.StdOut)) {
                        $parsedStore = ConvertFrom-WingetListOutput -RawText $msStoreCap.StdOut -AllowHeaderless ($msStoreCap.ExitCode -eq 0)
                        if ($parsedStore -and $parsedStore.Items.Count -gt 0) {
                            $seenWgIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                            foreach ($wgi in $wingetItems) {
                                if ($wgi -and -not [string]::IsNullOrWhiteSpace($wgi.ID)) { [void]$seenWgIds.Add($wgi.ID) }
                            }
                            foreach ($stItem in $parsedStore.Items) {
                                if ($stItem -and -not [string]::IsNullOrWhiteSpace($stItem.ID) -and $seenWgIds.Add($stItem.ID)) {
                                    $wingetItems.Add($stItem)
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            if (-not $Quiet) { Log-Text "[!] Lỗi khi gọi WinGet: $($_.Exception.Message)" }
        }

        if (& $cancelBlock) { return }

        if ($Quiet -and -not $wingetOk -and -not $localChanged -and $script:hasCompletedAppScan) {
            return
        }

        if ((-not $wingetOk -or $wingetItems.Count -lt 5) -and -not ("DuckUtil.AppCatalogEngine" -as [type])) {
            $appxItems = Get-LocalInstalledEntries
            if (& $cancelBlock) { return }
            foreach ($ax in $appxItems) {
                $installedList.Add($ax)
                Set-PreferredMapEntry $idMap $ax.ID $ax
                Set-PreferredMapEntry $nameMap $ax.Name $ax
                if ($ax.CleanName.Length -ge 2) { Set-PreferredMapEntry $cleanNameMap $ax.CleanName $ax }
            }
        }

        foreach ($itemObj in $wingetItems) {
            if ($itemObj.ID -eq "Microsoft.VisualStudioCode" -and $itemObj.Name -match '\(User\)' -and -not [System.IO.Directory]::Exists("$env:LOCALAPPDATA\Programs\Microsoft VS Code")) {
                continue
            }
            $installedList.Add($itemObj)
            if (-not $useCsFastMatcher) {
                if ($itemObj.ID -and -not $idMap.ContainsKey($itemObj.ID)) { $idMap[$itemObj.ID] = $itemObj } else { Set-PreferredMapEntry $idMap $itemObj.ID $itemObj }
                if ($itemObj.Name -and -not $nameMap.ContainsKey($itemObj.Name)) { $nameMap[$itemObj.Name] = $itemObj } else { Set-PreferredMapEntry $nameMap $itemObj.Name $itemObj }
                if ($itemObj.CleanName.Length -ge 2) {
                    if (-not $cleanNameMap.ContainsKey($itemObj.CleanName)) { $cleanNameMap[$itemObj.CleanName] = $itemObj } else { Set-PreferredMapEntry $cleanNameMap $itemObj.CleanName $itemObj }
                }

                if ($itemObj.ID -eq "Microsoft.VisualStudio.Community.Insiders") {
                    Set-PreferredMapEntry $idMap "Microsoft.VisualStudio.2022.Community" $itemObj
                }
            }
        }

        if ($installedList.Count -eq 0 -and -not $wingetOk) {
            if (-not $Quiet) {
                Log-Text "[!] Không nhận được danh sách ứng dụng từ cả WinGet lẫn cục bộ. Giữ nguyên trạng thái hiện tại."
                if ($txtStatus -and -not $script:hasCompletedAppScan) {
                    $txtStatus.Text = if ($wingetMissing) { "Thiếu WinGet | Quét thất bại" } else { "Lỗi quét WinGet | Hãy thử Quét lại máy" }
                }
            }
            return
        }

        if (& $cancelBlock) { return }
        $preserveOutdated = [bool]((-not $wingetOk) -and (-not $ForceSourceRefresh) -and $script:hasCompletedAppScan)
        $finalStats = Apply-InstalledDatabaseToRows -IdMap $idMap -NameMap $nameMap -CleanNameMap $cleanNameMap -InstalledList $installedList -CancelCheck $cancelBlock -PreserveOutdatedOnLocalFallback:$preserveOutdated
        if (($finalStats.PSObject.Properties['Canceled'] -and $finalStats.Canceled) -or (& $cancelBlock)) { return }
        if (-not $Quiet -and $progressBar) {
            $progressBar.IsIndeterminate = $false
            $progressBar.Value = 0
        }

        $script:lastLocalScanSig = $localFingerprint
        $prevInstalledCnt = $script:lastLocalInstalledCnt
        $script:lastLocalInstalledCnt = [int]$finalStats.Installed
        $newSig = "$($finalStats.Installed)|$($finalStats.Latest)|$($finalStats.Outdated)|$wingetOk"
        $sigChanged = ($newSig -ne $script:lastAppScanSignature)
        $script:lastAppScanSignature = $newSig

        if ($prevInstalledCnt -ge 0 -and $prevInstalledCnt -ne $finalStats.Installed) {
            $script:uninstallerStale = $true
        }

        $script:hasCompletedAppScan = $true
        if (Get-Command "Try-EnableCompletedCardCaches" -ErrorAction SilentlyContinue) {
            try { Try-EnableCompletedCardCaches } catch {}
        }
        $modeTag = if (-not $wingetOk) {
            if ($preserveOutdated) { " [WinGet lỗi - giữ trạng thái cập nhật trước đó]" } else { " [Dự phòng Registry/Appx]" }
        } else { "" }
        $summary = "Đã quét xong: $($finalStats.Installed) đã cài ($($finalStats.Latest) mới nhất, $($finalStats.Outdated) cần cập nhật)$modeTag"
        if (-not $Quiet) {
            if (-not $wingetOk -and -not $wingetMissing) {
                Log-Text "[WARN] $summary"
            } else {
                Log-Text "[OK] $summary"
            }
        } elseif ($sigChanged) {
            Log-Text "[AUTO] Làm mới: $($finalStats.Installed) đã cài ($($finalStats.Latest) mới nhất, $($finalStats.Outdated) cần cập nhật)$modeTag"
        }
        if ($txtStatus -and (-not $Quiet -or $sigChanged -or -not $script:isActionRunning)) {
            $txtStatus.Text = "$($finalStats.Installed) đã cài • $($finalStats.Latest) mới nhất • $($finalStats.Outdated) cần cập nhật" + $(if (-not $wingetOk) { " [Dự phòng]" } else { "" })
        }
    } finally {
        $autoWasPreempted = $Quiet -and ($script:autoScanGeneration -ne $script:activeAutoScanGen)
        if (-not $autoWasPreempted) {
            $script:isScanningApps = $false
        }
        if ($Quiet) {
            if (-not $autoWasPreempted) {
                $script:isAutoRefreshing = $false
                $script:cancelAutoScan = $false
            }
        } else {
            $keepWaitingLabel = ($script:pendingManualAppRefresh -and -not $script:isWindowClosing -and -not $script:isActionRunning)
            if ($btnScanInstalled) {
                $btnScanInstalled.Content = if ($keepWaitingLabel) { "Đang chờ..." } else { "Làm mới" }
                $btnScanInstalled.IsEnabled = (-not $keepWaitingLabel)
            }
            if ($progressBar) {
                $progressBar.IsIndeterminate = $false
                $progressBar.Value = 0
            }
        }
        if (-not $script:isWindowClosing -and -not $autoWasPreempted -and (Get-Command "Reset-AutoAppRefreshTimer" -ErrorAction SilentlyContinue)) {
            try { Reset-AutoAppRefreshTimer -FromAutoTick:$Quiet } catch {}
        }
        if (-not $script:isWindowClosing -and (Get-Command "Flush-PendingIconCache" -ErrorAction SilentlyContinue)) {
            Flush-PendingIconCache
        }
        if ($script:pendingManualAppRefresh -and -not $script:isWindowClosing -and -not $script:isScanningApps -and $window -and $window.Dispatcher) {
            $window.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::Background,
                [Action]{
                    if ($script:isWindowClosing) {
                        $script:pendingManualAppRefresh = $false
                        return
                    }
                    if (-not $script:isActionRunning -and -not $script:isScanningApps) {
                        $script:pendingManualAppRefresh = $false
                        Invoke-GuardedAction "Quét ứng dụng" -DeferExpand -AllowDuringUninstallerLoad {
                            Scan-And-ColorizeApps -ForceSourceRefresh
                        }
                    } else {
                        $script:pendingManualAppRefresh = $false
                        if ($btnScanInstalled) {
                            $btnScanInstalled.Content = "Làm mới"
                            $btnScanInstalled.IsEnabled = $true
                        }
                    }
                }
            ) | Out-Null
        }
    }
}
