<#
.SYNOPSIS
    DuckUtil Project Compiler & Bundler (Inspired by Chris Titus WinUtil Compile.ps1)
.DESCRIPTION
    Tập hợp toàn bộ các module config/apps.json, xaml/MainWindow.xaml,
    functions/ (private & public) và scripts/ thành một file phân phối duy nhất DuckUtil.ps1.
#>

$root = $PSScriptRoot
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🦆 DUCK UTIL BUNDLER - COMPILING PROJECT ARTIFACTS..." -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Đọc các tệp thành phần
$startCode = Get-Content -Raw -Encoding utf8 (Join-Path $root "scripts\start.ps1")
$appsJson = Get-Content -Raw -Encoding utf8 (Join-Path $root "config\apps.json")
$xamlCode = Get-Content -Raw -Encoding utf8 (Join-Path $root "xaml\MainWindow.xaml")
$mainCode = Get-Content -Raw -Encoding utf8 (Join-Path $root "scripts\main.ps1")

# 2. Xây dựng cấu trúc phân phối
$sb = [System.Text.StringBuilder]::new()

# Header & Elevation
$sb.AppendLine($startCode.Trim()) | Out-Null
$sb.AppendLine() | Out-Null

# Kho dữ liệu ứng dụng chuyển đổi từ apps.json
$q = [char]39
$sb.AppendLine("# 3. KHO DỮ LIỆU ỨNG DỤNG (NHẬN TỪ CONFIG/APPS.JSON)") | Out-Null
$sb.AppendLine(('$appsRawJson = @' + $q)) | Out-Null
$sb.AppendLine($appsJson.Trim()) | Out-Null
$sb.AppendLine(($q + '@')) | Out-Null
$sb.AppendLine('$AppCatalog = ConvertFrom-Json $appsRawJson') | Out-Null
$sb.AppendLine() | Out-Null

# Giao diện XAML
$dq = [char]34
$sb.AppendLine("# 4. GIAO DIỆN XAML WPF") | Out-Null
$sb.AppendLine(('[xml]$XAML = @' + $dq)) | Out-Null
$sb.AppendLine($xamlCode.Trim()) | Out-Null
$sb.AppendLine(($dq + '@')) | Out-Null
$sb.AppendLine() | Out-Null

# Functions (Private & Public)
$sb.AppendLine("# 5. MODULES & FUNCTIONS") | Out-Null
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

# Main Script & Event Bindings
$sb.AppendLine("# 6. ENTRYPOINT & CONTROLLER") | Out-Null
$sb.AppendLine($mainCode.Trim()) | Out-Null

# 3. Xuất ra DuckUtil.ps1 (Chuẩn UTF-8 KHÔNG CÓ BOM)
$outPath = Join-Path $root "DuckUtil.ps1"
[System.IO.File]::WriteAllText($outPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))

$fileInfo = Get-Item $outPath
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "✓ COMPILATION SUCCESSFUL!" -ForegroundColor Green
Write-Host "  File output : $outPath" -ForegroundColor Green
Write-Host "  File size   : $($fileInfo.Length) bytes ($([math]::Round($fileInfo.Length / 1KB, 2)) KB)" -ForegroundColor Green
Write-Host "  Ready for   : irm is.gd/duckutil | iex" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
