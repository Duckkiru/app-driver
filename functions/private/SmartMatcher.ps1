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
    if ($av -eq "winget" -or $av -eq "msstore" -or $av -eq "Unknown") { return $false }
    if ($av -notmatch '\d') { return $false }
    if ([string]::IsNullOrWhiteSpace($InstalledVer)) { return $true }
    $iv = $InstalledVer.Trim()
    if ($iv.StartsWith("<")) { return $true }
    if ($iv -eq "Unknown" -or $iv -eq "Installed" -or $iv -notmatch '\d') { return $true }
    return ((Compare-AppVersions $av $iv) -gt 0)
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

    $cId    = $charPos[0]
    $cVer   = $charPos[1]
    $cAvail = $charPos[2]
    $cSrc   = $charPos[3]

    $appName = ""; $appId = ""; $version = ""; $avail = ""
    if ($cId -gt 0 -and $Line.Length -gt $cId) {
        $appName = $Line.Substring(0, $cId).Trim()
        if ($cVer -gt $cId -and $Line.Length -gt $cVer) {
            $appId = $Line.Substring($cId, $cVer - $cId).Trim()
            if ($cAvail -gt $cVer -and $Line.Length -gt $cAvail) {
                $version = $Line.Substring($cVer, $cAvail - $cVer).Trim()
                if ($cSrc -gt $cAvail -and $Line.Length -gt $cSrc) {
                    $avail = $Line.Substring($cAvail, $cSrc - $cAvail).Trim()
                } else {
                    $avail = $Line.Substring($cAvail).Trim()
                }
            } else {
                $version = $Line.Substring($cVer).Trim()
            }
        } else {
            $appId = $Line.Substring($cId).Trim()
        }
    }
    return @($appName, $appId, $version, $avail)
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

    if ($curIsLocal -and -not $candIsLocal) {
        $Map[$Key] = $Candidate
        return
    }
    if (-not $curIsLocal -and $candIsLocal) {
        return
    }

    $curIsSynthetic = ($cur.ID -match '^(ARP|MSIX|LOCAL)\\')
    $candIsSynthetic = ($Candidate.ID -match '^(ARP|MSIX|LOCAL)\\')
    if ($curIsSynthetic -and -not $candIsSynthetic) {
        $Map[$Key] = $Candidate
        return
    }
    if (-not $curIsSynthetic -and $candIsSynthetic) {
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

    $tArch = if ($tName -match '\(x64\)|\.x64' -or $tId -match '\.x64$') { "x64" }
             elseif ($tName -match '\(x86\)|\.x86' -or $tId -match '\.x86$') { "x86" }
             elseif ($tName -match '\(arm64\)|\.arm64' -or $tId -match '\.arm64$') { "arm64" }
             elseif ([Environment]::Is64BitOperatingSystem -and $TargetApp.Category -eq '.NET Runtimes' -and $tId -match 'DesktopRuntime') { "x64" }
             else { "" }

    $meta = [PSCustomObject]@{
        ID             = $tId
        Name           = $tName
        CleanTarget    = $cleanTarget
        CleanAliases   = $cleanAliases
        AliasEntries   = $aliasEntries
        PatternClean   = $patternClean
        QueryTokens    = $queryTokens
        AllowNoise     = ($tName -match '(?i)(Maintenance|Control Panel|Context Menu|AddOn|Installer|Agent)')
        IsPrev         = (($tName -match 'Preview') -or ($tId -match 'Preview'))
        IsVcRedist     = (($tId -match 'VCRedist') -or ($tName -match 'VC\+\+'))
        IsComm         = (($tName -match '\bCommunity\b') -or ($tId -match '\.Community\b'))
        IsPro          = (($tName -match '\b(Ultimate|Professional)\b') -or ($tId -match '\.(Ultimate|Professional)\b'))
        IsIde          = (($tName -match '\bIDE\b') -or ($tId -match 'IDE$'))
        IsAntigravity  = ($tId -match 'Antigravity')
        IsCli          = (($tName -match '\bCLI\b') -or ($tId -match '(\.cli|CLI)$'))
        IsBt           = (($tName -match 'Build Tools') -or ($tId -match 'BuildTools'))
        IsVsc          = (($tId -match 'VisualStudioCode') -or ($tName -match 'VS Code|Visual Studio Code'))
        IsVsAny        = ($tId -match 'VisualStudio')
        IsEtb          = (($tId -match 'EverythingToolbar') -or ($tName -match 'EverythingToolbar'))
        IsTemurin      = ($tId -match 'Temurin')
        IsOracleJava   = ($tId -match 'Oracle\.Java')
        IsCorretto     = ($tId -match 'Corretto')
        IsJdk          = (($tName -match '\bJDK\b') -or ($tId -match '\.JDK$'))
        IsJre          = (($tName -match '\bJRE\b') -or ($tId -match '\.(JRE|JavaRuntimeEnvironment)$'))
        ReqPy          = $reqPy
        ReqJava        = $reqJava
        ReqDnRaw       = $reqDnRaw
        ReqDnEsc       = $reqDnEsc
        ReqYear        = $reqYear
        Arch           = $tArch
    }
    $script:targetAppMetaCache[$tId] = $meta
    return $meta
}

function Test-MatchCompatible {
    param($TargetApp, $Item)
    if (-not $TargetApp -or -not $Item) { return $false }

    $meta  = Get-TargetAppMeta $TargetApp
    $tId   = $meta.ID
    $iName = [string]$Item.Name
    $iId   = [string]$Item.ID

    if (-not $meta.AllowNoise) {
        if ($iName -match '(?i)(Maintenance Service|Control Panels|Context Menu|SparseApp|SDK AddOn|CoreEditorFonts|Visual Studio Installer)' -or
            $iId   -match '(?i)(MozillaMaintenanceService|ContextMenu|SparseApp|FigmaAgent)') {
            return $false
        }
    }

    if ($iId -eq 'Python.Launcher' -or $iName -match '^Python Launcher\b') {
        if ($tId -ne 'Python.Launcher') { return $false }
    }

    $iPrev = ($iName.IndexOf('Preview', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($iId.IndexOf('Preview', [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
    if ($meta.IsPrev -ne $iPrev -and $tId -ne 'Microsoft.PowerToys') { return $false }

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

$script:isScanningApps = $false
$script:hasCompletedAppScan = $false

function Start-WingetBackgroundPreScan {
    if ($null -ne $script:preSpawnedWinget) { return }
    try {
        if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) { return }
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "winget"
        $pinfo.Arguments = "list --disable-interactivity --accept-source-agreements"
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
                Arguments = "list --disable-interactivity --accept-source-agreements"
            }
        }
    } catch {
        $script:preSpawnedWinget = $null
    }
}

function Invoke-WingetListCapture {
    param(
        [string]$Arguments = "list --disable-interactivity --accept-source-agreements",
        [int]$TimeoutSeconds = 35
    )

    $p = $null
    $readTask = $null
    $errTask = $null
    $sw = $null

    if ($null -ne $script:preSpawnedWinget -and $script:preSpawnedWinget.Arguments -eq $Arguments -and $script:preSpawnedWinget.Stopwatch.Elapsed.TotalSeconds -lt 30) {
        $job = $script:preSpawnedWinget
        $script:preSpawnedWinget = $null
        $p = $job.Process
        $readTask = $job.ReadTask
        $errTask = $job.ErrTask
        $sw = $job.Stopwatch
    } else {
        if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]@{
                Available = $false
                TimedOut  = $false
                ExitCode  = -1
                StdOut    = ""
                StdErr    = ""
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
        $readTask = $p.StandardOutput.ReadToEndAsync()
        $errTask  = $p.StandardError.ReadToEndAsync()
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
    }

    $rawList = ""
    $errList = ""
    $timedOut = $false
    $exitCode = -1

    while (-not $readTask.IsCompleted -or -not $errTask.IsCompleted) {
        if ($sw.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
            $timedOut = $true
            try { if (-not $p.HasExited) { $p.Kill() } } catch {}
            break
        }
        try {
            if (Get-Command "Flush-PendingIconCache" -ErrorAction SilentlyContinue) {
                Flush-PendingIconCache
            }
            [System.Windows.Forms.Application]::DoEvents()
        } catch {}
        Start-Sleep -Milliseconds 10
    }

    try { if (-not $p.HasExited) { $p.WaitForExit(1000) | Out-Null } } catch {}
    if ($readTask.IsCompleted) { $rawList = $readTask.Result }
    if ($errTask.IsCompleted)  { $errList = $errTask.Result }
    if ($p.HasExited) { $exitCode = $p.ExitCode }

    return [PSCustomObject]@{
        Available = $true
        TimedOut  = $timedOut
        ExitCode  = $exitCode
        StdOut    = $rawList
        StdErr    = $errList
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
        if ($lines[$i] -match '^---+(\s+---+)*\s*$') {
            $separatorIndex = $i
            break
        }
    }

    if ($separatorIndex -gt 0) {
        $separatorLine = $lines[$separatorIndex]
        $headerLine    = $lines[$separatorIndex - 1]

        $colOffsets = @()
        if ($separatorLine -match '---+\s+---+') {
            $dashMatches = [System.Text.RegularExpressions.Regex]::Matches($separatorLine, '-+')
            foreach ($dm in $dashMatches) { $colOffsets += $dm.Index }
        } elseif ($headerLine) {
            $headerMatches = [System.Text.RegularExpressions.Regex]::Matches($headerLine, '[^\s]+(?:\s[^\s]+)*(?=\s{2,}|\s*$)')
            foreach ($hm in $headerMatches) { $colOffsets += $hm.Index }
        }

        $idIdx    = if ($colOffsets.Count -ge 2) { $colOffsets[1] } else { -1 }
        $verIdx   = if ($colOffsets.Count -ge 3) { $colOffsets[2] } else { -1 }
        $availIdx = if ($colOffsets.Count -ge 4) { $colOffsets[3] } else { -1 }
        $srcIdx   = if ($colOffsets.Count -ge 5) { $colOffsets[4] } else { -1 }

        for ($j = $separatorIndex + 1; $j -lt $lines.Count; $j++) {
            $line = $lines[$j]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $appName = ""; $appId = ""; $version = ""; $avail = ""

            if ($idIdx -gt 0 -and $line -match '[^\x00-\xFF]') {
                $sliced = Get-SliceByDisplayWidth -Line $line -Offsets $colOffsets
                $appName = $sliced[0]; $appId = $sliced[1]; $version = $sliced[2]; $avail = $sliced[3]
            } elseif ($idIdx -gt 0 -and $line.Length -gt $idIdx) {
                $appName = $line.Substring(0, $idIdx).Trim()
                if ($verIdx -gt $idIdx -and $line.Length -gt $verIdx) {
                    $appId = $line.Substring($idIdx, $verIdx - $idIdx).Trim()
                    if ($availIdx -gt $verIdx -and $Line.Length -gt $availIdx) {
                        $version = $line.Substring($verIdx, $availIdx - $verIdx).Trim()
                        if ($srcIdx -gt $availIdx -and $Line.Length -gt $srcIdx) {
                            $avail = $line.Substring($availIdx, $srcIdx - $availIdx).Trim()
                        } else {
                            $avail = $line.Substring($availIdx).Trim()
                        }
                    } else {
                        $version = $line.Substring($verIdx).Trim()
                    }
                } else {
                    $appId = $line.Substring($idIdx).Trim()
                }
            } else {
                $cols = [System.Text.RegularExpressions.Regex]::Split($line.Trim(), '\s{2,}')
                if ($cols.Count -ge 2) {
                    $appName = $cols[0].Trim()
                    $appId   = $cols[1].Trim()
                    $version = if ($cols.Count -ge 3) { $cols[2].Trim() } else { "" }
                    $avail   = if ($cols.Count -ge 4) { $cols[3].Trim() } else { "" }
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($appId)) {
                $hasUpdate = Test-AppUpdateGenuine -InstalledVer $version -AvailableVer $avail
                $clean = Get-CleanAppName $appName
                $parsed.Add([PSCustomObject]@{
                    Name      = $appName
                    ID        = $appId
                    Version   = $version
                    Available = $(if ($hasUpdate) { $avail } else { "" })
                    HasUpdate = $hasUpdate
                    CleanName = $clean
                })
            }
        }
    } elseif ($AllowHeaderless) {
        foreach ($line in $lines) {
            if (-not [string]::IsNullOrWhiteSpace($line) -and -not ($line -like "---*")) {
                $cols = [System.Text.RegularExpressions.Regex]::Split($line.Trim(), '\s{2,}')
                if ($cols.Count -ge 2) {
                    $appName = $cols[0].Trim()
                    $appId   = $cols[1].Trim()
                    if ($appId -notmatch '^(ARP|MSIX)\\|\S+\.\S+') { continue }
                    $version = if ($cols.Count -ge 3) { $cols[2].Trim() } else { "" }
                    $avail   = if ($cols.Count -ge 4) { $cols[3].Trim() } else { "" }
                    $hasUpdate = Test-AppUpdateGenuine -InstalledVer $version -AvailableVer $avail
                    $clean = Get-CleanAppName $appName

                    $parsed.Add([PSCustomObject]@{
                        Name      = $appName
                        ID        = $appId
                        Version   = $version
                        Available = $(if ($hasUpdate) { $avail } else { "" })
                        HasUpdate = $hasUpdate
                        CleanName = $clean
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
    param([switch]$SkipAppx)
    if ("DuckUtil.AppCatalogEngine" -as [type]) {
        try {
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

    $dotnetSharedConfigs = @(
        @{ Path = "C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App";       Suffix = "";     ArchLabel = "(x64)" },
        @{ Path = "C:\Program Files (x86)\dotnet\shared\Microsoft.WindowsDesktop.App"; Suffix = ".x86"; ArchLabel = "(x86)" }
    )
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

    $cliProbes = @(
        @{ ID = "Google.AntigravityCLI";     Name = "Antigravity CLI";       Cmd = "agy.exe";         Paths = @("$env:LOCALAPPDATA\agy\bin\agy.exe") },
        @{ ID = "astral-sh.uv";              Name = "uv (Python Manager)";   Cmd = "uv.exe";          Paths = @("$env:USERPROFILE\.local\bin\uv.exe", "$env:USERPROFILE\.cargo\bin\uv.exe") },
        @{ ID = "yt-dlp.yt-dlp";             Name = "yt-dlp";                Cmd = "yt-dlp.exe";      Paths = @("$env:LOCALAPPDATA\Programs\Python\Python313\Scripts\yt-dlp.exe", "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts\yt-dlp.exe") },
        @{ ID = "Gyan.FFmpeg";               Name = "FFmpeg";                Cmd = "ffmpeg.exe";      Paths = @() },
        @{ ID = "aria2.aria2";               Name = "aria2";                 Cmd = "aria2c.exe";      Paths = @() },
        @{ ID = "Rclone.Rclone";             Name = "Rclone";                Cmd = "rclone.exe";      Paths = @() },
        @{ ID = "Oven-sh.Bun";               Name = "Bun";                   Cmd = "bun.exe";         Paths = @("$env:USERPROFILE\.bun\bin\bun.exe") },
        @{ ID = "pnpm.pnpm";                 Name = "pnpm";                  Cmd = "pnpm.exe";        Paths = @("$env:LOCALAPPDATA\pnpm\pnpm.exe", "$env:APPDATA\npm\pnpm.cmd") },
        @{ ID = "Yarn.Yarn";                 Name = "Yarn";                  Cmd = "yarn.cmd";        Paths = @("$env:APPDATA\npm\yarn.cmd") },
        @{ ID = "Fastfetch-cli.Fastfetch";   Name = "Fastfetch";             Cmd = "fastfetch.exe";   Paths = @() },
        @{ ID = "JanDeDobbeleer.OhMyPosh";   Name = "Oh My Posh";            Cmd = "oh-my-posh.exe";  Paths = @("$env:LOCALAPPDATA\Programs\oh-my-posh\bin\oh-my-posh.exe") },
        @{ ID = "Neovim.Neovim";             Name = "Neovim";                Cmd = "nvim.exe";        Paths = @("C:\Program Files\Neovim\bin\nvim.exe") },
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
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}
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

function Apply-InstalledDatabaseToRows {
    param(
        $IdMap,
        $NameMap,
        $CleanNameMap,
        $InstalledList
    )

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
            if ($cleanAlias.Length -ge 3 -and $CleanNameMap.TryGetValue($cleanAlias, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
                $lookupCache[$targetId] = $match
                return $match
            }
        }

        $cleanTarget = $meta.CleanTarget
        if ($cleanTarget.Length -ge 3 -and $CleanNameMap.TryGetValue($cleanTarget, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
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

    foreach ($row in $allItemBorders) {
        $app = $row.Tag.App
        $grid = $row.Child
        $tb = if ($row.Tag.NameText) { $row.Tag.NameText } elseif ($grid -and $grid.Children.Count -gt 2) { $grid.Children[2] } else { $null }
        $updateBadge = $row.Tag.UpdateBadge
        $updateText  = $row.Tag.UpdateText
        $idnPrefix = if ($app.IDn) { "[#$($app.IDn)] " } else { "" }

        $info = Find-InstalledAppFast $app

        if ($info) {
            $countInstalled++
            $row.Tag.DetectedId = $info.ID
            $row.Tag.InstalledVersion = $info.Version

            if ($info.HasUpdate -eq $true) {
                $countOutdated++
                $row.Tag.Status = "OUTDATED"
                $tb.Foreground = $script:brushOutdatedFg
                $tb.Text = $app.Name
                $tb.TextDecorations = $null
                if ($updateBadge -and $updateText) {
                    $updateText.Text = if ($info.Available) { "↑ $($info.Available)" } else { "↑ Mới" }
                    $updateBadge.Visibility = [System.Windows.Visibility]::Visible
                }
                $tip = "$idnPrefix$($app.Name)`nĐang cài: $($info.Version)`nCó bản mới: $($info.Available)`nID phát hiện: $($info.ID)"
                $tb.ToolTip = $tip
                $row.ToolTip = $tip
            } else {
                $countLatest++
                $row.Tag.Status = "LATEST"
                $tb.Foreground = $script:brushLatestFg
                $tb.Text = $app.Name
                $tb.TextDecorations = $null
                if ($updateBadge) { $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed }
                $tip = "$idnPrefix$($app.Name)`nPhiên bản: $($info.Version) (Mới nhất)`nID phát hiện: $($info.ID)"
                $tb.ToolTip = $tip
                $row.ToolTip = $tip
            }
        } else {
            $row.Tag.Status = "NONE"
            $row.Tag.DetectedId = $null
            $row.Tag.InstalledVersion = $null
            $tb.Foreground = $script:brushNoneFg
            $tb.Text = $app.Name
            $tb.TextDecorations = $null
            if ($updateBadge) { $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed }
            $tip = "$idnPrefix$($app.Name)`nTrạng thái: Chưa cài đặt`nID: $($app.ID)"
            $tb.ToolTip = $tip
            $row.ToolTip = $tip
        }
    }

    return [PSCustomObject]@{
        Installed = $countInstalled
        Latest    = $countLatest
        Outdated  = $countOutdated
    }
}

function Scan-And-ColorizeApps {
    if ($script:isScanningApps) {
        Log-Text "[!] Tiến trình quét ứng dụng đang chạy, bỏ qua yêu cầu trùng lặp."
        return
    }

    $script:isScanningApps = $true
    try {
        Log-Text "[SCAN] Đang quét đa tầng (Registry, Runtimes, CLI/PATH & WinGet)..."
        if ($txtStatus) { $txtStatus.Text = "Đang quét nhanh hệ thống..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}

        $localItems = Get-LocalInstalledEntries -SkipAppx
        $idMap        = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $nameMap      = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $cleanNameMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $installedList = [System.Collections.Generic.List[object]]::new()

        foreach ($locObj in $localItems) {
            $installedList.Add($locObj)
            if ($locObj.ID -and -not $idMap.ContainsKey($locObj.ID)) { $idMap[$locObj.ID] = $locObj } else { Set-PreferredMapEntry $idMap $locObj.ID $locObj }
            if ($locObj.Name -and -not $nameMap.ContainsKey($locObj.Name)) { $nameMap[$locObj.Name] = $locObj } else { Set-PreferredMapEntry $nameMap $locObj.Name $locObj }
            if ($locObj.CleanName.Length -ge 3) {
                if (-not $cleanNameMap.ContainsKey($locObj.CleanName)) { $cleanNameMap[$locObj.CleanName] = $locObj } else { Set-PreferredMapEntry $cleanNameMap $locObj.CleanName $locObj }
            }
        }

        if ($allItemBorders -and $allItemBorders.Count -gt 0 -and -not $script:hasCompletedAppScan) {
            $preStats = Apply-InstalledDatabaseToRows -IdMap $idMap -NameMap $nameMap -CleanNameMap $cleanNameMap -InstalledList $installedList
            if ($txtStatus) {
                $txtStatus.Text = "Phát hiện nhanh $($preStats.Installed) app | Đang kiểm tra bản cập nhật..."
            }
            try { [System.Windows.Forms.Application]::DoEvents() } catch {}
        }

        $wingetItems = [System.Collections.Generic.List[object]]::new()
        $wingetOk = $false
        $wingetMissing = $false

        try {
            $primary = Invoke-WingetListCapture -Arguments "list --disable-interactivity --accept-source-agreements" -TimeoutSeconds 35
            if (-not $primary.Available) {
                $wingetMissing = $true
                Log-Text "[WARN] Chưa có WinGet; chuyển sang quét cục bộ qua Registry, Runtimes & Appx."
            } else {
                $parsedPrimary = ConvertFrom-WingetListOutput -RawText $primary.StdOut -AllowHeaderless ($primary.ExitCode -eq 0 -and -not $primary.TimedOut)
                if (-not $primary.TimedOut -and $primary.ExitCode -eq 0 -and $parsedPrimary.Items.Count -gt 0) {
                    $wingetItems = $parsedPrimary.Items
                    $wingetOk = $true
                } else {
                    if ($primary.TimedOut) {
                        Log-Text "[WARN] WinGet (tất cả nguồn) quá thời gian chờ (35s); đang thử lại với nguồn --source winget..."
                    } else {
                        Log-Text "[WARN] WinGet (tất cả nguồn) trả về mã $($primary.ExitCode) ($($parsedPrimary.Items.Count) dòng); đang thử lại --source winget..."
                        if (-not [string]::IsNullOrWhiteSpace($primary.StdErr)) {
                            Log-Text "[stderr] $($primary.StdErr.Trim())"
                        }
                    }

                    $fallbackWg = Invoke-WingetListCapture -Arguments "list --source winget --disable-interactivity --accept-source-agreements" -TimeoutSeconds 20
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
            }
        } catch {
            Log-Text "[!] Lỗi khi gọi WinGet: $($_.Exception.Message)"
        }

        if (-not $wingetOk -or $wingetItems.Count -lt 5) {
            $appxItems = Get-LocalInstalledEntries
            foreach ($ax in $appxItems) {
                $installedList.Add($ax)
                Set-PreferredMapEntry $idMap $ax.ID $ax
                Set-PreferredMapEntry $nameMap $ax.Name $ax
                if ($ax.CleanName.Length -ge 3) { Set-PreferredMapEntry $cleanNameMap $ax.CleanName $ax }
            }
        }

        foreach ($itemObj in $wingetItems) {
            if ($itemObj.ID -eq "Microsoft.VisualStudioCode" -and $itemObj.Name -match '\(User\)' -and -not [System.IO.Directory]::Exists("$env:LOCALAPPDATA\Programs\Microsoft VS Code")) {
                continue
            }
            $installedList.Add($itemObj)
            if ($itemObj.ID -and -not $idMap.ContainsKey($itemObj.ID)) { $idMap[$itemObj.ID] = $itemObj } else { Set-PreferredMapEntry $idMap $itemObj.ID $itemObj }
            if ($itemObj.Name -and -not $nameMap.ContainsKey($itemObj.Name)) { $nameMap[$itemObj.Name] = $itemObj } else { Set-PreferredMapEntry $nameMap $itemObj.Name $itemObj }
            if ($itemObj.CleanName.Length -ge 3) {
                if (-not $cleanNameMap.ContainsKey($itemObj.CleanName)) { $cleanNameMap[$itemObj.CleanName] = $itemObj } else { Set-PreferredMapEntry $cleanNameMap $itemObj.CleanName $itemObj }
            }

            if ($itemObj.ID -eq "Microsoft.VisualStudio.Community.Insiders") {
                Set-PreferredMapEntry $idMap "Microsoft.VisualStudio.2022.Community" $itemObj
            }
        }

        if ($installedList.Count -eq 0 -and -not $wingetOk) {
            Log-Text "[!] Không nhận được danh sách ứng dụng từ cả WinGet lẫn cục bộ. Giữ nguyên trạng thái hiện tại."
            if ($txtStatus -and -not $script:hasCompletedAppScan) {
                $txtStatus.Text = if ($wingetMissing) { "Thiếu WinGet | Quét thất bại" } else { "Lỗi quét WinGet | Hãy thử Quét lại máy" }
            }
            return
        }

        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        $finalStats = Apply-InstalledDatabaseToRows -IdMap $idMap -NameMap $nameMap -CleanNameMap $cleanNameMap -InstalledList $installedList

        $script:hasCompletedAppScan = $true
        $modeTag = if (-not $wingetOk) { " [Chế độ dự phòng Registry/Appx]" } else { "" }
        $summary = "Đã quét xong: $($finalStats.Installed) app đã cài ($($finalStats.Latest) bản mới nhất [XANH], $($finalStats.Outdated) bản cũ [ĐỎ])$modeTag"
        Log-Text "[OK] $summary"
        if ($txtStatus) {
            $txtStatus.Text = "$($finalStats.Installed) app đã cài ($($finalStats.Latest) mới / $($finalStats.Outdated) cũ)" + $(if (-not $wingetOk) { " [Dự phòng]" } else { "" })
        }
    } finally {
        $script:isScanningApps = $false
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if (Get-Command "Flush-PendingIconCache" -ErrorAction SilentlyContinue) {
            Flush-PendingIconCache
        }
    }
}
