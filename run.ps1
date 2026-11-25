$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$rawUrl = 'https://raw.githubusercontent.com/Duckkiru/app-driver/main/App-Driver.ps1'
$cacheDir = Join-Path $env:LOCALAPPDATA 'AppDriver\Cache'
try {
    if (-not [System.IO.Directory]::Exists($cacheDir)) {
        [void][System.IO.Directory]::CreateDirectory($cacheDir)
    }
} catch {
    $cacheDir = $env:TEMP
}

$scriptPath = Join-Path $cacheDir 'App-Driver.ps1'
$etagPath   = Join-Path $cacheDir 'App-Driver.etag'
$hasLocal   = [System.IO.File]::Exists($scriptPath) -and ([System.IO.FileInfo]::new($scriptPath)).Length -gt 100000
$localEtag  = if ($hasLocal -and [System.IO.File]::Exists($etagPath)) { ([System.IO.File]::ReadAllText($etagPath)).Trim() } else { '' }

try {
    $req = [System.Net.HttpWebRequest]::Create($rawUrl)
    $req.UserAgent = 'App-Driver-Loader'
    $req.Timeout = 20000
    $req.ReadWriteTimeout = 30000
    $req.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    if (-not [string]::IsNullOrWhiteSpace($localEtag)) {
        $req.Headers.Add('If-None-Match', $localEtag)
    }
    $resp = $null
    try {
        $resp = $req.GetResponse()
        Write-Host '[*] Dang tai ban moi nhat cua App-Driver...' -ForegroundColor Cyan
        $tmpFile = $scriptPath + '.tmp'
        $inStream = $resp.GetResponseStream()
        $outStream = [System.IO.File]::Create($tmpFile)
        try {
            $inStream.CopyTo($outStream)
        } finally {
            $outStream.Dispose()
            $inStream.Dispose()
        }
        if ([System.IO.File]::Exists($scriptPath)) { [System.IO.File]::Delete($scriptPath) }
        [System.IO.File]::Move($tmpFile, $scriptPath)
        $newEtag = $resp.Headers['ETag']
        if (-not [string]::IsNullOrWhiteSpace($newEtag)) {
            [System.IO.File]::WriteAllText($etagPath, $newEtag)
        }
        $hasLocal = $true
    } catch [System.Net.WebException] {
        $httpResp = $_.Exception.Response
        if ($httpResp -and ([int]$httpResp.StatusCode -eq 304) -and $hasLocal) {
            Write-Host '[*] Da co san ban moi nhat trong cache, mo ngay...' -ForegroundColor Green
        } elseif (-not $hasLocal) {
            throw
        } else {
            Write-Host '[!] Khong ket noi duoc GitHub, chay ban cache gan nhat...' -ForegroundColor Yellow
        }
    } finally {
        if ($resp) { try { $resp.Close() } catch {} }
    }
} catch {
    if (-not $hasLocal) {
        Write-Host "[ERR] Khong the tai App-Driver: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
}

$pwshPath = $null
if ($PSVersionTable.PSEdition -ne 'Core') {
    $cmd = Get-Command -Name 'pwsh.exe' -CommandType Application -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and [System.IO.File]::Exists($cmd.Source)) {
        $pwshPath = $cmd.Source
    } elseif ([System.IO.File]::Exists((Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'))) {
        $pwshPath = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    }
}

if ($pwshPath) {
    & $pwshPath -NoProfile -Sta -ExecutionPolicy Bypass -File $scriptPath @args
} else {
    & $scriptPath @args
}
