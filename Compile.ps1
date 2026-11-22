$root = $PSScriptRoot
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "APP-DRIVER BUNDLER - COMPILING PROJECT ARTIFACTS..." -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

function ConvertTo-AsciiJson {
    param([string]$JsonText)
    if ([string]::IsNullOrEmpty($JsonText)) { return "" }
    $clean = $JsonText.Replace(([char]0xFEFF).ToString(), "")
    $sb = [System.Text.StringBuilder]::new($clean.Length + 256)
    foreach ($ch in $clean.ToCharArray()) {
        $code = [int]$ch
        if ($code -gt 127) {
            [void]$sb.AppendFormat("\u{0:X4}", $code)
        } else {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString()
}

function ConvertTo-AsciiXml {
    param([string]$XmlText)
    if ([string]::IsNullOrEmpty($XmlText)) { return "" }
    $clean = $XmlText.Replace(([char]0xFEFF).ToString(), "")
    $sb = [System.Text.StringBuilder]::new($clean.Length + 512)
    foreach ($ch in $clean.ToCharArray()) {
        $code = [int]$ch
        if ($code -gt 127) {
            [void]$sb.AppendFormat("&#x{0:X4};", $code)
        } else {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString()
}

function ConvertTo-AsciiPowerShellCode {
    param([string]$Code)
    if ([string]::IsNullOrEmpty($Code)) { return "" }
    $cleanCode = $Code.Replace(([char]0xFEFF).ToString(), "")
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($cleanCode, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "Source PowerShell code has parse errors: $($errors[0].Message)"
    }

    $targetTokens = New-Object System.Collections.Generic.List[object]
    foreach ($t in $tokens) {
        if ([string]::IsNullOrEmpty($t.Text)) { continue }
        $hasHi = $false
        foreach ($ch in $t.Text.ToCharArray()) {
            if ([int]$ch -gt 127) { $hasHi = $true; break }
        }
        if ($hasHi) { $targetTokens.Add($t) }
    }
    if ($targetTokens.Count -eq 0) { return $cleanCode }

    $sb = [System.Text.StringBuilder]::new($cleanCode)
    for ($idx = $targetTokens.Count - 1; $idx -ge 0; $idx--) {
        $tok = $targetTokens[$idx]
        $start = $tok.Extent.StartOffset
        $len   = $tok.Extent.EndOffset - $start
        $orig  = $tok.Text
        $repl  = [System.Text.StringBuilder]::new($orig.Length * 2)

        if ($tok.Kind -eq 'HereStringLiteral') {
            foreach ($ch in $orig.ToCharArray()) {
                $c = [int]$ch
                if ($c -gt 127) {
                    [void]$repl.AppendFormat("&#x{0:X4};", $c)
                } else {
                    [void]$repl.Append($ch)
                }
            }
        } elseif ($tok.Kind -eq 'StringLiteral') {
            $val = $tok.Value
            [void]$repl.Append('"')
            foreach ($ch in $val.ToCharArray()) {
                $c = [int]$ch
                if ($c -gt 127) {
                    [void]$repl.AppendFormat("`$([char]0x{0:X4})", $c)
                } elseif ($ch -eq '"') {
                    [void]$repl.Append('`"')
                } elseif ($ch -eq '$') {
                    [void]$repl.Append('`$')
                } elseif ($ch -eq '`') {
                    [void]$repl.Append('``')
                } else {
                    [void]$repl.Append($ch)
                }
            }
            [void]$repl.Append('"')
        } elseif ($tok.Kind -eq 'StringExpandable') {
            foreach ($ch in $orig.ToCharArray()) {
                $c = [int]$ch
                if ($c -gt 127) {
                    [void]$repl.AppendFormat("`$([char]0x{0:X4})", $c)
                } else {
                    [void]$repl.Append($ch)
                }
            }
        } else {
            throw "Unexpected non-ASCII token kind: $($tok.Kind) at line $($tok.Extent.StartLineNumber)"
        }

        [void]$sb.Remove($start, $len)
        [void]$sb.Insert($start, $repl.ToString())
    }
    return $sb.ToString()
}

$startCode  = ConvertTo-AsciiPowerShellCode (Get-Content -Raw -Encoding utf8 (Join-Path $root "scripts\start.ps1"))
$appsJson   = ConvertTo-AsciiJson (Get-Content -Raw -Encoding utf8 (Join-Path $root "config\apps.json"))
$tweaksJson = ConvertTo-AsciiJson (Get-Content -Raw -Encoding utf8 (Join-Path $root "config\tweaks.json"))
$xamlCode   = ConvertTo-AsciiXml (Get-Content -Raw -Encoding utf8 (Join-Path $root "xaml\MainWindow.xaml"))
$mainCode   = ConvertTo-AsciiPowerShellCode (Get-Content -Raw -Encoding utf8 (Join-Path $root "scripts\main.ps1"))
function Merge-CSharpCoreSources {
    param([string[]]$Sources)
    $usings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $bodies = [System.Collections.Generic.List[string]]::new()
    foreach ($src in $Sources) {
        $lines = $src -split "`r?`n"
        $bodyLines = [System.Collections.Generic.List[string]]::new()
        $inHdr = $true
        foreach ($ln in $lines) {
            if ($inHdr -and $ln -match '^\s*using\s+[^;]+;\s*$') {
                [void]$usings.Add($ln.Trim())
            } elseif ($inHdr -and [string]::IsNullOrWhiteSpace($ln)) {
            } else {
                $inHdr = $false
                $bodyLines.Add($ln)
            }
        }
        $bodies.Add(($bodyLines -join "`r`n"))
    }
    $sortedUsings = New-Object string[] $usings.Count
    $usings.CopyTo($sortedUsings)
    [System.Array]::Sort($sortedUsings, [System.StringComparer]::Ordinal)
    return (($sortedUsings -join "`r`n") + "`r`n`r`n" + ($bodies -join "`r`n`r`n"))
}

$smoothCsCode = Get-Content -Raw -Encoding utf8 (Join-Path $root "csharp\SmoothScrollController.cs")
$appCatalogCsCode = Get-Content -Raw -Encoding utf8 (Join-Path $root "csharp\AppCatalogEngine.cs")
$deepCsCode = Get-Content -Raw -Encoding utf8 (Join-Path $root "csharp\DeepUninstallerEngine.cs")
$optCsCode = Get-Content -Raw -Encoding utf8 (Join-Path $root "csharp\WindowsOptimizerEngine.cs")
$startupCsCode = Get-Content -Raw -Encoding utf8 (Join-Path $root "csharp\StartupManagerEngine.cs")
$combinedCoreCsCode = Merge-CSharpCoreSources -Sources @($smoothCsCode, $appCatalogCsCode, $deepCsCode, $optCsCode, $startupCsCode)

$sb = [System.Text.StringBuilder]::new()

$sb.AppendLine($startCode.Trim()) | Out-Null
$sb.AppendLine() | Out-Null

$q = [char]39
$sb.AppendLine(('$appsRawJson = @' + $q)) | Out-Null
$sb.AppendLine($appsJson.Trim()) | Out-Null
$sb.AppendLine(($q + '@')) | Out-Null
$sb.AppendLine('$AppCatalog = ConvertFrom-Json $appsRawJson') | Out-Null
$sb.AppendLine() | Out-Null

$sb.AppendLine(('$tweaksRawJson = @' + $q)) | Out-Null
$sb.AppendLine($tweaksJson.Trim()) | Out-Null
$sb.AppendLine(($q + '@')) | Out-Null
$sb.AppendLine('$TweakCatalog = ConvertFrom-Json $tweaksRawJson') | Out-Null
$sb.AppendLine() | Out-Null

$dq = [char]34
$sb.AppendLine(('[xml]$XAML = @' + $dq)) | Out-Null
$sb.AppendLine($xamlCode.Trim()) | Out-Null
$sb.AppendLine(($dq + '@')) | Out-Null
$sb.AppendLine() | Out-Null

$sb.AppendLine('function Import-CachedCSharpType {') | Out-Null
$sb.AppendLine('    param([string]$TypeName, [string]$SourceCode, [string]$Prefix, [string[]]$ReferencedAssemblies = @(), [string]$RequiredMethod = "", [scriptblock]$RefsResolver = $null)') | Out-Null
$sb.AppendLine('    $existingType = $TypeName -as [type]') | Out-Null
$sb.AppendLine('    if ($existingType -and ([string]::IsNullOrWhiteSpace($RequiredMethod) -or $null -ne $existingType.GetMethod($RequiredMethod))) { return }') | Out-Null
$sb.AppendLine('    try {') | Out-Null
$sb.AppendLine('        $cacheDir = Join-Path $env:LOCALAPPDATA "DuckUtil\Cache"') | Out-Null
$sb.AppendLine('        if (-not [System.IO.Directory]::Exists($cacheDir)) { [System.IO.Directory]::CreateDirectory($cacheDir) | Out-Null }') | Out-Null
$sb.AppendLine('        $sha = [System.Security.Cryptography.SHA256]::Create()') | Out-Null
$sb.AppendLine('        $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($SourceCode + "|" + $PSVersionTable.PSVersion.ToString()))') | Out-Null
$sb.AppendLine('        $sha.Dispose()') | Out-Null
$sb.AppendLine('        $hashHex = ([System.BitConverter]::ToString($hashBytes)).Replace("-", "").Substring(0, 16)') | Out-Null
$sb.AppendLine('        $rtTag = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { "Desktop" }') | Out-Null
$sb.AppendLine('        $rtPrefix = "${Prefix}_${rtTag}"') | Out-Null
$sb.AppendLine('        $dllName = "${rtPrefix}_${hashHex}.dll"') | Out-Null
$sb.AppendLine('        $dllPath = Join-Path $cacheDir $dllName') | Out-Null
$sb.AppendLine('        try {') | Out-Null
$sb.AppendLine('            foreach ($oldDll in [System.IO.Directory]::GetFiles($cacheDir, "${rtPrefix}_*.dll")) {') | Out-Null
$sb.AppendLine('                if (-not [System.IO.Path]::GetFileName($oldDll).Equals($dllName, [System.StringComparison]::OrdinalIgnoreCase)) {') | Out-Null
$sb.AppendLine('                    try { [System.IO.File]::Delete($oldDll) } catch {}') | Out-Null
$sb.AppendLine('                }') | Out-Null
$sb.AppendLine('            }') | Out-Null
$sb.AppendLine('        } catch {}') | Out-Null
$sb.AppendLine('        if ([System.IO.File]::Exists($dllPath) -and ([System.IO.FileInfo]::new($dllPath)).Length -gt 0) {') | Out-Null
$sb.AppendLine('            try {') | Out-Null
$sb.AppendLine('                [System.Reflection.Assembly]::LoadFrom($dllPath) | Out-Null') | Out-Null
$sb.AppendLine('                $loadedType = $TypeName -as [type]') | Out-Null
$sb.AppendLine('                if ($loadedType -and ([string]::IsNullOrWhiteSpace($RequiredMethod) -or $null -ne $loadedType.GetMethod($RequiredMethod))) { return }') | Out-Null
$sb.AppendLine('                try { [System.IO.File]::Delete($dllPath) } catch {}') | Out-Null
$sb.AppendLine('            } catch {}') | Out-Null
$sb.AppendLine('        }') | Out-Null
$sb.AppendLine('        $resolvedRefs = $ReferencedAssemblies') | Out-Null
$sb.AppendLine('        if ((-not $resolvedRefs -or $resolvedRefs.Count -eq 0) -and $RefsResolver) { $resolvedRefs = @(& $RefsResolver) }') | Out-Null
$sb.AppendLine('        $addParams = @{ TypeDefinition = $SourceCode; OutputAssembly = $dllPath; ErrorAction = "Stop" }') | Out-Null
$sb.AppendLine('        if ($resolvedRefs -and $resolvedRefs.Count -gt 0) { $addParams["ReferencedAssemblies"] = $resolvedRefs }') | Out-Null
$sb.AppendLine('        Add-Type @addParams | Out-Null') | Out-Null
$sb.AppendLine('        [System.Reflection.Assembly]::LoadFrom($dllPath) | Out-Null') | Out-Null
$sb.AppendLine('    } catch { try { if ([System.IO.File]::Exists($dllPath)) { [System.IO.File]::Delete($dllPath) } } catch {} }') | Out-Null
$sb.AppendLine('    if (-not ($TypeName -as [type])) {') | Out-Null
$sb.AppendLine('        try {') | Out-Null
$sb.AppendLine('            $resolvedRefs = $ReferencedAssemblies') | Out-Null
$sb.AppendLine('            if ((-not $resolvedRefs -or $resolvedRefs.Count -eq 0) -and $RefsResolver) { $resolvedRefs = @(& $RefsResolver) }') | Out-Null
$sb.AppendLine('            if ($resolvedRefs -and $resolvedRefs.Count -gt 0) {') | Out-Null
$sb.AppendLine('                Add-Type -TypeDefinition $SourceCode -ReferencedAssemblies $resolvedRefs -ErrorAction SilentlyContinue') | Out-Null
$sb.AppendLine('            } else {') | Out-Null
$sb.AppendLine('                Add-Type -TypeDefinition $SourceCode -ErrorAction SilentlyContinue') | Out-Null
$sb.AppendLine('            }') | Out-Null
$sb.AppendLine('        } catch {}') | Out-Null
$sb.AppendLine('    }') | Out-Null
$sb.AppendLine('}') | Out-Null
$sb.AppendLine() | Out-Null
$sb.AppendLine('$resolveCoreRefs = {') | Out-Null
$sb.AppendLine('    $wpfSmoothRefs = @(') | Out-Null
$sb.AppendLine('        [System.Windows.Controls.ScrollViewer].Assembly.Location,') | Out-Null
$sb.AppendLine('        [System.Windows.UIElement].Assembly.Location,') | Out-Null
$sb.AppendLine('        [System.Windows.DependencyObject].Assembly.Location,') | Out-Null
$sb.AppendLine('        [System.Windows.Markup.IQueryAmbient].Assembly.Location,') | Out-Null
$sb.AppendLine('        [System.Diagnostics.Stopwatch].Assembly.Location,') | Out-Null
$sb.AppendLine('        [System.Drawing.Icon].Assembly.Location,') | Out-Null
$sb.AppendLine('        [System.Net.Http.HttpClient].Assembly.Location,') | Out-Null
$sb.AppendLine('        [System.Object].Assembly.Location') | Out-Null
$sb.AppendLine('    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique') | Out-Null
$sb.AppendLine('    if ($PSVersionTable.PSEdition -eq "Core") {') | Out-Null
$sb.AppendLine('        try {') | Out-Null
$sb.AppendLine('            $refDllsCore = @([System.IO.Directory]::GetFiles((Join-Path $PSHOME "ref"), "*.dll"))') | Out-Null
$sb.AppendLine('            $loadedExtraCore = @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { -not $_.IsDynamic -and -not [string]::IsNullOrWhiteSpace($_.Location) -and $_.GetName().Name -match "^(Presentation|WindowsBase|System\.Drawing|System\.Private\.Windows|DirectWriteForwarder|ReachFramework|UIAutomation)" } | ForEach-Object { $_.Location })') | Out-Null
$sb.AppendLine('            return @($refDllsCore + $loadedExtraCore + $wpfSmoothRefs | Select-Object -Unique)') | Out-Null
$sb.AppendLine('        } catch { return $wpfSmoothRefs }') | Out-Null
$sb.AppendLine('    }') | Out-Null
$sb.AppendLine('    return $wpfSmoothRefs') | Out-Null
$sb.AppendLine('}') | Out-Null
$sb.AppendLine() | Out-Null
$sb.AppendLine('if (-not ("DuckUtil.SmoothScrollController" -as [type]) -and -not ("DuckUtil.AppCatalogEngine" -as [type]) -and -not ("DuckUtil.DeepUninstallerEngine" -as [type]) -and -not ("DuckUtil.WindowsOptimizerEngine" -as [type]) -and -not ("DuckUtil.StartupManagerEngine" -as [type])) {') | Out-Null
$sb.AppendLine('    try {') | Out-Null
$sb.AppendLine(('        $duckCoreCs = @' + $q)) | Out-Null
$sb.AppendLine($combinedCoreCsCode.Trim()) | Out-Null
$sb.AppendLine(($q + '@')) | Out-Null
$sb.AppendLine('        Import-CachedCSharpType -TypeName "DuckUtil.UiAssetPipeline" -SourceCode $duckCoreCs -Prefix "DuckCore" -RequiredMethod "RestoreRowsFromColumns" -RefsResolver $resolveCoreRefs') | Out-Null
$sb.AppendLine('    } catch {}') | Out-Null
$sb.AppendLine('}') | Out-Null
$sb.AppendLine() | Out-Null
$sb.AppendLine('if (-not ("DuckUtil.SmoothScrollController" -as [type])) {') | Out-Null
$sb.AppendLine('    try {') | Out-Null
$sb.AppendLine(('        $smoothScrollCs = @' + $q)) | Out-Null
$sb.AppendLine($smoothCsCode.Trim()) | Out-Null
$sb.AppendLine(($q + '@')) | Out-Null
$sb.AppendLine('        Import-CachedCSharpType -TypeName "DuckUtil.SmoothScrollController" -SourceCode $smoothScrollCs -Prefix "DuckSmooth" -RequiredMethod "AttachFrameWake" -RefsResolver $resolveCoreRefs') | Out-Null
$sb.AppendLine('    } catch {}') | Out-Null
$sb.AppendLine('}') | Out-Null
$sb.AppendLine() | Out-Null
$sb.AppendLine('if ("DuckUtil.ConsoleHelper" -as [type]) { try { [DuckUtil.ConsoleHelper]::DisableQuickEdit() } catch {} }') | Out-Null
$sb.AppendLine() | Out-Null
$sb.AppendLine('if (-not ("DuckUtil.AppCatalogEngine" -as [type])) {') | Out-Null
$sb.AppendLine('    try {') | Out-Null
$sb.AppendLine(('        $appCatalogCs = @' + $q)) | Out-Null
$sb.AppendLine($appCatalogCsCode.Trim()) | Out-Null
$sb.AppendLine(($q + '@')) | Out-Null
$sb.AppendLine('        Import-CachedCSharpType -TypeName "DuckUtil.AppCatalogEngine" -SourceCode $appCatalogCs -Prefix "DuckApp" -RequiredMethod "ScanCatalogSensorsAsync"') | Out-Null
$sb.AppendLine('    } catch {}') | Out-Null
$sb.AppendLine('}') | Out-Null
$sb.AppendLine() | Out-Null
$sb.AppendLine('if (-not ("DuckUtil.DeepUninstallerEngine" -as [type])) {') | Out-Null
$sb.AppendLine('    try {') | Out-Null
$sb.AppendLine(('        $deepUninstCs = @' + $q)) | Out-Null
$sb.AppendLine($deepCsCode.Trim()) | Out-Null
$sb.AppendLine(($q + '@')) | Out-Null
$sb.AppendLine('        Import-CachedCSharpType -TypeName "DuckUtil.DeepUninstallerEngine" -SourceCode $deepUninstCs -Prefix "DuckDeep" -RequiredMethod "ForceStopBatchDirectoriesAsync"') | Out-Null
$sb.AppendLine('    } catch {}') | Out-Null
$sb.AppendLine('}') | Out-Null
$sb.AppendLine() | Out-Null
$sb.AppendLine('if (-not ("DuckUtil.WindowsOptimizerEngine" -as [type])) {') | Out-Null
$sb.AppendLine('    try {') | Out-Null
$sb.AppendLine(('        $winOptCs = @' + $q)) | Out-Null
$sb.AppendLine($optCsCode.Trim()) | Out-Null
$sb.AppendLine(($q + '@')) | Out-Null
$sb.AppendLine('        Import-CachedCSharpType -TypeName "DuckUtil.WindowsOptimizerEngine" -SourceCode $winOptCs -Prefix "DuckOpt" -RequiredMethod "ProbeTweaksStateAsync"') | Out-Null
$sb.AppendLine('    } catch {}') | Out-Null
$sb.AppendLine('}') | Out-Null
$sb.AppendLine() | Out-Null
$sb.AppendLine('if (-not ("DuckUtil.StartupManagerEngine" -as [type])) {') | Out-Null
$sb.AppendLine('    try {') | Out-Null
$sb.AppendLine(('        $startupMgrCs = @' + $q)) | Out-Null
$sb.AppendLine($startupCsCode.Trim()) | Out-Null
$sb.AppendLine(($q + '@')) | Out-Null
$sb.AppendLine('        Import-CachedCSharpType -TypeName "DuckUtil.StartupManagerEngine" -SourceCode $startupMgrCs -Prefix "DuckStart" -RequiredMethod "ScanFastCoreAsync" -RefsResolver $resolveCoreRefs') | Out-Null
$sb.AppendLine('    } catch {}') | Out-Null
$sb.AppendLine('}') | Out-Null
$sb.AppendLine() | Out-Null

$fnDirs = @("functions\private", "functions\public")
foreach ($d in $fnDirs) {
    $fullDir = Join-Path $root $d
    if (Test-Path $fullDir) {
        $psFiles = @(Get-ChildItem -Path $fullDir -Filter "*.ps1")
        [System.Array]::Sort($psFiles, [System.Comparison[System.IO.FileInfo]]{
            param($a, $b)
            [System.StringComparer]::Ordinal.Compare($a.Name, $b.Name)
        })
        foreach ($psFile in $psFiles) {
            $fnContent = (ConvertTo-AsciiPowerShellCode (Get-Content -Raw -Encoding utf8 $psFile.FullName)).Trim()
            $sb.AppendLine($fnContent) | Out-Null
            $sb.AppendLine() | Out-Null
        }
    }
}

$sb.AppendLine($mainCode.Trim()) | Out-Null

$outPath = Join-Path $root "App-Driver.ps1"
$finalBundle = $sb.ToString().Replace(([char]0xFEFF).ToString(), "")
[System.IO.File]::WriteAllText($outPath, $finalBundle, [System.Text.UTF8Encoding]::new($false))

$writtenBytes = [System.IO.File]::ReadAllBytes($outPath)
$nonAsciiCount = 0
foreach ($b in $writtenBytes) {
    if ($b -gt 127) { $nonAsciiCount++ }
}
if ($nonAsciiCount -gt 0) {
    throw "Compiled App-Driver.ps1 contains $nonAsciiCount non-ASCII byte(s); expected pure 7-bit ASCII!"
}
$parseTokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($outPath, [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors -and $parseErrors.Count -gt 0) {
    throw "Compiled App-Driver.ps1 failed ParseFile validation with $($parseErrors.Count) error(s): $($parseErrors[0].Message)"
}

$fileInfo = Get-Item $outPath
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "[OK] COMPILATION SUCCESSFUL!" -ForegroundColor Green
Write-Host "  File output : $outPath" -ForegroundColor Green
Write-Host "  File size   : $($fileInfo.Length) bytes ($([math]::Round($fileInfo.Length / 1KB, 2)) KB)" -ForegroundColor Green
Write-Host "  ASCII check : 0 non-ASCII bytes | ParseFile errors = 0" -ForegroundColor Green
Write-Host "  Ready for   : irm is.gd/appdriver | iex" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green