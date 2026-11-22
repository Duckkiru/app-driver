$ErrorActionPreference = "Stop"
$script:pass = 0
$script:fail = 0

function Assert-Check {
    param([string]$Name, [bool]$Condition, [string]$Detail = "")
    if ($Condition) {
        $script:pass++
        Write-Output "[PASS] $Name - $Detail"
    } else {
        $script:fail++
        Write-Output "[FAIL] $Name - $Detail"
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$bundlePath = Join-Path $repoRoot "App-Driver.ps1"
if (-not (Test-Path -LiteralPath $bundlePath)) {
    throw "Compiled bundle not found at: $bundlePath"
}

# 1. Pure 7-bit ASCII & Syntax Check
$rawBytes = [System.IO.File]::ReadAllBytes($bundlePath)
$nonAsciiCount = @($rawBytes | Where-Object { $_ -gt 127 }).Count
Assert-Check "BundlePureAscii" ($nonAsciiCount -eq 0) "Bytes=$($rawBytes.Length) NonAscii=$nonAsciiCount"

$raw = [System.IO.File]::ReadAllText($bundlePath, [System.Text.Encoding]::UTF8)
$parseTokens = $null; $parseErrs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($bundlePath, [ref]$parseTokens, [ref]$parseErrs)
Assert-Check "BundleParseFileClean" ($null -eq $parseErrs -or $parseErrs.Count -eq 0) "Errors=$(if ($parseErrs) { $parseErrs.Count } else { 0 })"

# 2. Verify Zero C# Engine Duplication inside App-Driver.ps1
$dupMarkers = @(
    "public sealed class SmoothScrollController",
    "public static class AppCatalogEngine",
    "public static class DeepUninstallerEngine",
    "public static class WindowsOptimizerEngine",
    "public static class StartupManagerEngine"
)
$allSingle = $true
$markerCounts = @()
foreach ($mk in $dupMarkers) {
    $cnt = ([regex]::Matches($raw, [regex]::Escape($mk))).Count
    $markerCounts += ("{0}={1}" -f ($mk -replace 'public (?:static|sealed) class ', ''), $cnt)
    if ($cnt -ne 1) { $allSingle = $false }
}
Assert-Check "ZeroCSharpDuplication" $allSingle ($markerCounts -join ", ")

# 3. Load compiled C# engines + PowerShell functions from App-Driver.ps1 (before ShowDialog)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms
$startMarker = "try {`r`n    [Console]::OutputEncoding"
$startIdx = $raw.IndexOf($startMarker)
if ($startIdx -lt 0) {
    $startMarker = "try {`n    [Console]::OutputEncoding"
    $startIdx = $raw.IndexOf($startMarker)
}
if ($startIdx -lt 0) { throw "Cannot locate start marker in App-Driver.ps1" }
$idxShow = $raw.LastIndexOf('$window.ShowDialog()')
if ($idxShow -lt 0) { throw "Cannot locate ShowDialog marker in App-Driver.ps1" }

$script:SkipHostExit = $true
$loadCode = $raw.Substring($startIdx, $idxShow - $startIdx)
$loadCode = $loadCode -replace '(?m)^\s*try\s*\{\s*Clear-Host\s*\}\s*catch\s*\{\}\s*$', ''
Invoke-Expression $loadCode

$expectedTypes = @(
    "DuckUtil.SmoothScrollController",
    "DuckUtil.UiAssetPipeline",
    "DuckUtil.AppCatalogEngine",
    "DuckUtil.DeepUninstallerEngine",
    "DuckUtil.WindowsOptimizerEngine",
    "DuckUtil.StartupManagerEngine"
)
$missingTypes = @($expectedTypes | Where-Object { $null -eq ($_ -as [type]) })
Assert-Check "AllCSharpEnginesLoaded" ($missingTypes.Count -eq 0) "PS=$($PSVersionTable.PSVersion) Missing=$($missingTypes -join ',')"

# 4. AppCatalogEngine Version Comparison & Update Genuineness
$verOk = (
    [DuckUtil.AppCatalogEngine]::CompareAppVersions("2.0.0", "1.9.9") -gt 0 -and
    [DuckUtil.AppCatalogEngine]::CompareAppVersions("1.10.0", "1.2.0") -gt 0 -and
    [DuckUtil.AppCatalogEngine]::CompareAppVersions("1.2.3.0", "1.2.3") -eq 0 -and
    [DuckUtil.AppCatalogEngine]::CompareAppVersions("1.0.0", "1.0.1") -lt 0
)
Assert-Check "AppVersionComparison" $verOk "SemVer & 4-part comparison"

$updCSharpOk = (
    -not [DuckUtil.AppCatalogEngine]::TestAppUpdateGenuine("", "2.0.0") -and
    -not [DuckUtil.AppCatalogEngine]::TestAppUpdateGenuine("Unknown", "2.0.0") -and
    -not [DuckUtil.AppCatalogEngine]::TestAppUpdateGenuine("Installed", "2.0.0") -and
    -not [DuckUtil.AppCatalogEngine]::TestAppUpdateGenuine("2.0.0", "2.0.0") -and
    -not [DuckUtil.AppCatalogEngine]::TestAppUpdateGenuine("2.1.0", "2.0.0") -and
    [DuckUtil.AppCatalogEngine]::TestAppUpdateGenuine("1.9.0", "2.0.0") -and
    [DuckUtil.AppCatalogEngine]::TestAppUpdateGenuine("< 2.0.0", "2.0.0")
)
Assert-Check "AppUpdateGenuineCSharp" $updCSharpOk "C# edge cases"

# Verify SmartMatcher.ps1 fallback logic matches C# when C# branch is bypassed
$smartMatcherPath = Join-Path $repoRoot "functions\private\SmartMatcher.ps1"
$smRaw = [System.IO.File]::ReadAllText($smartMatcherPath, [System.Text.Encoding]::UTF8)
$smFallbackOnly = $smRaw -replace 'if \("DuckUtil\.AppCatalogEngine" -as \[type\]\)', 'if ($false)'
$smFallbackOnly = $smFallbackOnly -replace 'function Test-AppUpdateGenuine', 'function Test-AppUpdateGenuineFallbackOnly'
$mFn = [regex]::Match($smFallbackOnly, '(?s)function Test-AppUpdateGenuineFallbackOnly\s*\{.*?\r?\n\}')
if (-not $mFn.Success) { throw "Could not extract fallback Test-AppUpdateGenuine" }
Invoke-Expression $mFn.Value

$updFallbackOk = (
    -not (Test-AppUpdateGenuineFallbackOnly "" "2.0.0") -and
    -not (Test-AppUpdateGenuineFallbackOnly "Unknown" "2.0.0") -and
    -not (Test-AppUpdateGenuineFallbackOnly "Installed" "2.0.0") -and
    -not (Test-AppUpdateGenuineFallbackOnly "2.0.0" "2.0.0") -and
    (Test-AppUpdateGenuineFallbackOnly "1.9.0" "2.0.0") -and
    (Test-AppUpdateGenuineFallbackOnly "< 2.0.0" "2.0.0")
)
Assert-Check "AppUpdateGenuineParity" $updFallbackOk "PS fallback matches C# engine"

# 5. DeepUninstallerEngine 4-Layer Windows Protected Directory Shield
$tmpNormalDir = Join-Path ([System.IO.Path]::GetTempPath()) ("DuckUtilShieldTest_" + [Guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($tmpNormalDir)
try {
    $shieldCases = @(
        @{ Path = "C:\Windows"; Expect = $true },
        @{ Path = "C:\Windows\System32"; Expect = $true },
        @{ Path = "C:\Program Files"; Expect = $true },
        @{ Path = "C:\Program Files (x86)"; Expect = $true },
        @{ Path = "C:\ProgramData"; Expect = $true },
        @{ Path = "C:\ProgramData\Microsoft"; Expect = $true },
        @{ Path = "C:\Users"; Expect = $true },
        @{ Path = "C:\Users\Public"; Expect = $true },
        @{ Path = $tmpNormalDir; Expect = $false }
    )
    $shieldOk = $true
    $shieldFails = @()
    foreach ($sc in $shieldCases) {
        $got = [DuckUtil.DeepUninstallerEngine]::IsProtectedWindowsDirectory($sc.Path, $true)
        if ($got -ne $sc.Expect) {
            $shieldOk = $false
            $shieldFails += "$($sc.Path):got=$got/exp=$($sc.Expect)"
        }
    }
    Assert-Check "WindowsDirectoryShield" $shieldOk $(if ($shieldOk) { "9/9 cases exact" } else { $shieldFails -join "; " })
} finally {
    try { [System.IO.Directory]::Delete($tmpNormalDir, $true) } catch {}
}

# 6. StartupManagerEngine Precision & Headless WPF Row Factory
$protOk = (
    [string]::IsNullOrEmpty([DuckUtil.StartupManagerEngine]::IsProtectedOemOrSystemStartup("Intelligent StandbyList Cleaner", "D:\ISLC.exe", "Wagnardsoft")) -and
    [string]::IsNullOrEmpty([DuckUtil.StartupManagerEngine]::IsProtectedOemOrSystemStartup("Spacer Utility", "C:\Apps\spacer.exe", "Acme")) -and
    [string]::IsNullOrEmpty([DuckUtil.StartupManagerEngine]::IsProtectedOemOrSystemStartup("Moment Notes", "C:\Apps\moment.exe", "Acme")) -and
    ([DuckUtil.StartupManagerEngine]::IsProtectedOemOrSystemStartup("Windows Security", "C:\Windows\System32\SecurityHealthSystray.exe", "Microsoft") -eq "System") -and
    ([DuckUtil.StartupManagerEngine]::IsProtectedOemOrSystemStartup("AMD Noise Suppression", "C:\Program Files\AMD\app.exe", "AMD") -eq "Oem")
)
Assert-Check "StartupWordBoundaryProtection" $protOk "Zero false positives, system/OEM guarded"

$fastEntries = [DuckUtil.StartupManagerEngine]::ScanFastCore()
Assert-Check "StartupFastCoreScan" ($null -ne $fastEntries) "Count=$($fastEntries.Count)"

$synth = [DuckUtil.StartupEntry]::new()
$synth.Id = "test::row1"
$synth.Name = "SmokeTestApp"
$synth.DisplayName = "Smoke Test App"
$synth.Publisher = "DuckUtil QA"
$synth.SourceKind = "Registry"
$synth.Enabled = $true
$synth.CanToggle = $true
$synth.CanDelete = $true
$synth.ImpactLevel = "Medium"
$rowVis = [DuckUtil.StartupManagerEngine]::CreateRowVisual($synth, $null, $null, $null)
Assert-Check "StartupCSharpRowFactory" ($null -ne $rowVis -and $null -ne $rowVis.Row -and $null -ne $rowVis.Toggle -and $rowVis.Toggle.IsChecked -eq $true) "C# WPF visual factory OK"

try { Stop-AllBackgroundWork } catch {}
Write-Output ("CORE_VERIFY_SUMMARY: PS={0} PASSED={1} FAILED={2}" -f $PSVersionTable.PSVersion, $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0
