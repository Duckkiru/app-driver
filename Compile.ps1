$root = $PSScriptRoot
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "APP-DRIVER BUNDLER - COMPILING PROJECT ARTIFACTS..." -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$startCode = Get-Content -Raw -Encoding utf8 (Join-Path $root "scripts\start.ps1")
$appsJson = Get-Content -Raw -Encoding utf8 (Join-Path $root "config\apps.json")
$xamlCode = Get-Content -Raw -Encoding utf8 (Join-Path $root "xaml\MainWindow.xaml")
$mainCode = Get-Content -Raw -Encoding utf8 (Join-Path $root "scripts\main.ps1")
$smoothCsCode = Get-Content -Raw -Encoding utf8 (Join-Path $root "csharp\SmoothScrollController.cs")
$deepCsCode = Get-Content -Raw -Encoding utf8 (Join-Path $root "csharp\DeepUninstallerEngine.cs")

$sb = [System.Text.StringBuilder]::new()

$sb.AppendLine($startCode.Trim()) | Out-Null
$sb.AppendLine() | Out-Null

$q = [char]39
$sb.AppendLine(('$appsRawJson = @' + $q)) | Out-Null
$sb.AppendLine($appsJson.Trim()) | Out-Null
$sb.AppendLine(($q + '@')) | Out-Null
$sb.AppendLine('$AppCatalog = ConvertFrom-Json $appsRawJson') | Out-Null
$sb.AppendLine() | Out-Null

$dq = [char]34
$sb.AppendLine(('[xml]$XAML = @' + $dq)) | Out-Null
$sb.AppendLine($xamlCode.Trim()) | Out-Null
$sb.AppendLine(($dq + '@')) | Out-Null
$sb.AppendLine() | Out-Null

$sb.AppendLine('function Import-CachedCSharpType {') | Out-Null
$sb.AppendLine('    param([string]$TypeName, [string]$SourceCode, [string]$Prefix, [string[]]$ReferencedAssemblies = @())') | Out-Null
$sb.AppendLine('    if ($TypeName -as [type]) { return }') | Out-Null
$sb.AppendLine('    try {') | Out-Null
$sb.AppendLine('        $cacheDir = Join-Path $env:LOCALAPPDATA "DuckUtil\Cache"') | Out-Null
$sb.AppendLine('        if (-not [System.IO.Directory]::Exists($cacheDir)) { [System.IO.Directory]::CreateDirectory($cacheDir) | Out-Null }') | Out-Null
$sb.AppendLine('        $sha = [System.Security.Cryptography.SHA256]::Create()') | Out-Null
$sb.AppendLine('        $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($SourceCode + "|" + $PSVersionTable.PSVersion.ToString()))') | Out-Null
$sb.AppendLine('        $sha.Dispose()') | Out-Null
$sb.AppendLine('        $hashHex = ([System.BitConverter]::ToString($hashBytes)).Replace("-", "").Substring(0, 16)') | Out-Null
$sb.AppendLine('        $dllPath = Join-Path $cacheDir "${Prefix}_${hashHex}.dll"') | Out-Null
$sb.AppendLine('        if ([System.IO.File]::Exists($dllPath)) {') | Out-Null
$sb.AppendLine('            try {') | Out-Null
$sb.AppendLine('                [System.Reflection.Assembly]::LoadFrom($dllPath) | Out-Null') | Out-Null
$sb.AppendLine('                if ($TypeName -as [type]) { return }') | Out-Null
$sb.AppendLine('            } catch {}') | Out-Null
$sb.AppendLine('        }') | Out-Null
$sb.AppendLine('        $addParams = @{ TypeDefinition = $SourceCode; OutputAssembly = $dllPath; ErrorAction = "Stop" }') | Out-Null
$sb.AppendLine('        if ($ReferencedAssemblies -and $ReferencedAssemblies.Count -gt 0) { $addParams["ReferencedAssemblies"] = $ReferencedAssemblies }') | Out-Null
$sb.AppendLine('        Add-Type @addParams | Out-Null') | Out-Null
$sb.AppendLine('        [System.Reflection.Assembly]::LoadFrom($dllPath) | Out-Null') | Out-Null
$sb.AppendLine('    } catch {}') | Out-Null
$sb.AppendLine('    if (-not ($TypeName -as [type])) {') | Out-Null
$sb.AppendLine('        try {') | Out-Null
$sb.AppendLine('            if ($ReferencedAssemblies -and $ReferencedAssemblies.Count -gt 0) {') | Out-Null
$sb.AppendLine('                Add-Type -TypeDefinition $SourceCode -ReferencedAssemblies $ReferencedAssemblies -ErrorAction SilentlyContinue') | Out-Null
$sb.AppendLine('            } else {') | Out-Null
$sb.AppendLine('                Add-Type -TypeDefinition $SourceCode -ErrorAction SilentlyContinue') | Out-Null
$sb.AppendLine('            }') | Out-Null
$sb.AppendLine('        } catch {}') | Out-Null
$sb.AppendLine('    }') | Out-Null
$sb.AppendLine('}') | Out-Null
$sb.AppendLine() | Out-Null
$sb.AppendLine('if (-not ("DuckUtil.SmoothScrollController" -as [type])) {') | Out-Null
$sb.AppendLine('    try {') | Out-Null
$sb.AppendLine('        $wpfSmoothRefs = @(') | Out-Null
$sb.AppendLine('            [System.Windows.Controls.ScrollViewer].Assembly.Location,') | Out-Null
$sb.AppendLine('            [System.Windows.UIElement].Assembly.Location,') | Out-Null
$sb.AppendLine('            [System.Windows.DependencyObject].Assembly.Location,') | Out-Null
$sb.AppendLine('            [System.Windows.Markup.IQueryAmbient].Assembly.Location,') | Out-Null
$sb.AppendLine('            [System.Diagnostics.Stopwatch].Assembly.Location,') | Out-Null
$sb.AppendLine('            [System.Object].Assembly.Location') | Out-Null
$sb.AppendLine('        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique') | Out-Null
$sb.AppendLine(('        $smoothScrollCs = @' + $q)) | Out-Null
$sb.AppendLine($smoothCsCode.Trim()) | Out-Null
$sb.AppendLine(($q + '@')) | Out-Null
$sb.AppendLine('        Import-CachedCSharpType -TypeName "DuckUtil.SmoothScrollController" -SourceCode $smoothScrollCs -Prefix "DuckSmooth" -ReferencedAssemblies $wpfSmoothRefs') | Out-Null
$sb.AppendLine('    } catch {}') | Out-Null
$sb.AppendLine('}') | Out-Null
$sb.AppendLine() | Out-Null
$sb.AppendLine('if (-not ("DuckUtil.DeepUninstallerEngine" -as [type])) {') | Out-Null
$sb.AppendLine('    try {') | Out-Null
$sb.AppendLine(('        $deepUninstCs = @' + $q)) | Out-Null
$sb.AppendLine($deepCsCode.Trim()) | Out-Null
$sb.AppendLine(($q + '@')) | Out-Null
$sb.AppendLine('        Import-CachedCSharpType -TypeName "DuckUtil.DeepUninstallerEngine" -SourceCode $deepUninstCs -Prefix "DuckDeep"') | Out-Null
$sb.AppendLine('    } catch {}') | Out-Null
$sb.AppendLine('}') | Out-Null
$sb.AppendLine() | Out-Null

$fnDirs = @("functions\private", "functions\public")
foreach ($d in $fnDirs) {
    $fullDir = Join-Path $root $d
    if (Test-Path $fullDir) {
        Get-ChildItem -Path $fullDir -Filter "*.ps1" | Sort-Object Name | ForEach-Object {
            $fnContent = (Get-Content -Raw -Encoding utf8 $_.FullName).Trim()
            $sb.AppendLine($fnContent) | Out-Null
            $sb.AppendLine() | Out-Null
        }
    }
}

$sb.AppendLine($mainCode.Trim()) | Out-Null

$outPath = Join-Path $root "App-Driver.ps1"
$finalBundle = $sb.ToString().Replace(([char]0xFEFF).ToString(), "")
[System.IO.File]::WriteAllText($outPath, $finalBundle, [System.Text.UTF8Encoding]::new($false))

$fileInfo = Get-Item $outPath
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "[OK] COMPILATION SUCCESSFUL!" -ForegroundColor Green
Write-Host "  File output : $outPath" -ForegroundColor Green
Write-Host "  File size   : $($fileInfo.Length) bytes ($([math]::Round($fileInfo.Length / 1KB, 2)) KB)" -ForegroundColor Green
Write-Host "  Ready for   : irm is.gd/appdriver | iex" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green