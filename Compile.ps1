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
$sb.AppendLine('        Add-Type -TypeDefinition $smoothScrollCs -ReferencedAssemblies $wpfSmoothRefs -ErrorAction SilentlyContinue') | Out-Null
$sb.AppendLine('    } catch {}') | Out-Null
$sb.AppendLine('}') | Out-Null
$sb.AppendLine() | Out-Null

$sb.AppendLine('if (-not ("DuckUtil.DeepUninstallerEngine" -as [type])) {') | Out-Null
$sb.AppendLine('    try {') | Out-Null
$sb.AppendLine(('        $deepUninstCs = @' + $q)) | Out-Null
$sb.AppendLine($deepCsCode.Trim()) | Out-Null
$sb.AppendLine(($q + '@')) | Out-Null
$sb.AppendLine('        Add-Type -TypeDefinition $deepUninstCs -ErrorAction SilentlyContinue') | Out-Null
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
[System.IO.File]::WriteAllText($outPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))

$fileInfo = Get-Item $outPath
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "[OK] COMPILATION SUCCESSFUL!" -ForegroundColor Green
Write-Host "  File output : $outPath" -ForegroundColor Green
Write-Host "  File size   : $($fileInfo.Length) bytes ($([math]::Round($fileInfo.Length / 1KB, 2)) KB)" -ForegroundColor Green
Write-Host "  Ready for   : irm is.gd/appdriver | iex" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green