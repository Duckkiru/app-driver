# ── FUNCTION: QUÉT & PHÂN LOẠI MÀU PHIÊN BẢN (TRẮNG / XANH / ĐỎ) ──

# Bộ nhớ đệm tĩnh lưu trữ Brush của WPF giúp tối ưu render và triệt tiêu Garbage Collection
$script:brushOutdatedFg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF8, 0x71, 0x71))
$script:brushLatestFg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x34, 0xD3, 0x99))
$script:brushNoneBg     = [System.Windows.Media.Brushes]::Transparent
$script:brushNoneFg     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF1, 0xF5, 0xF9))

$script:brushOutdatedFg.Freeze()
$script:brushLatestFg.Freeze()
$script:brushNoneFg.Freeze()

function Get-CleanAppName {
    param([string]$RawName)
    if ([string]::IsNullOrWhiteSpace($RawName)) { return "" }
    # Loại bỏ thông tin đóng ngoặc nhưng KHÔNG xóa mất định danh kiến trúc (x64), (x86), (arm64)
    $clean = ($RawName -replace '\((?!x64|x86|arm64).*?\)', '').Replace('(', '').Replace(')', '').Trim().ToLowerInvariant()
    $terms = @(" browser", " desktop", " lts", " client", " free", " ce", " community", " end-user")
    foreach ($term in $terms) {
        $clean = $clean.Replace($term, "")
    }
    return $clean.Trim()
}

function Get-CharDisplayWidth {
    param([int]$Code)
    # CJK, Hangul, Kana, Fullwidth & Emoji chiếm 2 cột hiển thị trong terminal Windows/winget
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
    # Cắt chuỗi theo độ rộng cột console để các dòng tiếng Trung/Nhật/Hàn không làm lệch cột ID/Version
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
    if ([string]::IsNullOrWhiteSpace($Key)) { return }
    if (-not $Map.ContainsKey($Key)) {
        $Map[$Key] = $Candidate
        return
    }
    $cur = $Map[$Key]
    $preferUpdate = (-not $cur.HasUpdate -and $Candidate.HasUpdate)
    $preferNativeId = ($cur.HasUpdate -eq $Candidate.HasUpdate -and $cur.ID -match '^(ARP|MSIX)\\' -and $Candidate.ID -notmatch '^(ARP|MSIX)\\')
    if ($preferUpdate -or $preferNativeId) {
        $Map[$Key] = $Candidate
    }
}

function Test-MatchCompatible {
    param($TargetApp, $Item)
    if (-not $TargetApp -or -not $Item) { return $false }

    $tName = [string]$TargetApp.Name
    $tId   = [string]$TargetApp.ID
    $iName = [string]$Item.Name
    $iId   = [string]$Item.ID

    # Chặn khớp chéo giữa bản thường và bản Preview
    $tPrev = ($tName -match 'Preview') -or ($tId -match 'Preview')
    $iPrev = ($iName -match 'Preview') -or ($iId -match 'Preview')
    if ($tPrev -ne $iPrev) { return $false }

    # Chặn gói UWP/VCLibs khớp nhầm vào Desktop Redistributable
    if (($tId -match 'VCRedist' -or $tName -match 'VC\+\+') -and ($iName -match '\bUWP\b' -or $iId -match 'VCLibs')) {
        return $false
    }

    # Chặn khớp chéo giữa bản Community và bản Ultimate / Professional (ví dụ IntelliJ IDEA, PyCharm)
    $tComm = ($tName -match '\bCommunity\b') -or ($tId -match '\.Community\b')
    $tPro  = ($tName -match '\b(Ultimate|Professional)\b') -or ($tId -match '\.(Ultimate|Professional)\b')
    $iComm = ($iName -match '\bCommunity\b') -or ($iId -match '\.Community\b')
    $iPro  = ($iName -match '\b(Ultimate|Professional)\b') -or ($iId -match '\.(Ultimate|Professional)\b')
    if (($tComm -and $iPro) -or ($tPro -and $iComm)) { return $false }

    # Chặn khớp chéo giữa bản gốc và biến thể IDE / CLI (ví dụ Antigravity vs Antigravity IDE / Antigravity CLI, GitHub Desktop vs GitHub CLI)
    $tIde = ($tName -match '\bIDE\b') -or ($tId -match 'IDE$')
    $iIde = ($iName -match '\bIDE\b') -or ($iId -match 'IDE$')
    if ($tIde -ne $iIde -and ($tId -match 'Antigravity' -or $iId -match 'Antigravity')) { return $false }

    $tCli = ($tName -match '\bCLI\b') -or ($tId -match '(\.cli|CLI)$')
    $iCli = ($iName -match '\bCLI\b') -or ($iId -match '(\.cli|CLI)$')
    if ($tCli -ne $iCli) { return $false }

    # Chặn khớp chéo giữa các nhà phân phối Java khác nhau (Temurin vs Oracle vs Corretto)
    if ($tId -match 'Temurin' -and ($iId -match 'Oracle|Corretto' -or $iName -match 'Corretto|^Java \d+ Update')) { return $false }
    if ($tId -match 'Oracle\.Java' -and ($iId -match 'Temurin|Corretto' -or $iName -match 'Temurin|Corretto')) { return $false }
    if ($tId -match 'Corretto' -and ($iId -match 'Temurin|Oracle' -or $iName -match 'Temurin|^Java \d+ Update')) { return $false }

    # Kiểm tra đồng nhất kiến trúc x64 / x86 / arm64 (KHÔNG xét nhánh registry ARP\Machine\X86 vì app x64 vẫn có thể ghi khóa WOW6432Node)
    $tArch = if ($tName -match '\(x64\)|\.x64' -or $tId -match '\.x64$') { "x64" }
             elseif ($tName -match '\(x86\)|\.x86' -or $tId -match '\.x86$') { "x86" }
             elseif ($tName -match '\(arm64\)|\.arm64' -or $tId -match '\.arm64$') { "arm64" }
             else { "" }

    if ($tArch) {
        $idForArch = if ($iId -match '^(ARP|MSIX)\\') { "" } else { $iId }
        $iArch = if ($iName -match '(?<![a-zA-Z0-9])(x64|64-bit)(?![a-zA-Z0-9])' -or $idForArch -match '\.x64$') { "x64" }
                 elseif ($iName -match '(?<![a-zA-Z0-9])(x86|32-bit)(?![a-zA-Z0-9])' -or $idForArch -match '\.x86$') { "x86" }
                 elseif ($iName -match '(?<![a-zA-Z0-9])arm64(?![a-zA-Z0-9])' -or $idForArch -match '\.arm64$') { "arm64" }
                 else { "" }
        if ($iArch -and $iArch -ne $tArch) { return $false }
    }

    return $true
}

$script:isScanningApps = $false
$script:hasCompletedAppScan = $false

function Invoke-WingetListCapture {
    param(
        [string]$Arguments = "list --disable-interactivity --accept-source-agreements",
        [int]$TimeoutSeconds = 35
    )

    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{
            Available = $false
            TimedOut  = $false
            ExitCode  = -1
            StdOut    = ""
            StdErr    = ""
        }
    }

    $rawList = ""
    $errList = ""
    $timedOut = $false
    $exitCode = -1

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

    # Đọc bất đồng bộ cả stdout và stderr để tránh deadlock buffer
    $readTask = $p.StandardOutput.ReadToEndAsync()
    $errTask  = $p.StandardError.ReadToEndAsync()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $readTask.IsCompleted -or -not $errTask.IsCompleted) {
        if ($sw.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
            $timedOut = $true
            try { if (-not $p.HasExited) { $p.Kill() } } catch {}
            break
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 30
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

    $parsed = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($RawText)) {
        return [PSCustomObject]@{ HasTable = $false; Items = $parsed }
    }

    $rawLines = $RawText -split "`n"
    $lines = [System.Collections.Generic.List[string]]::new($rawLines.Count)
    foreach ($rl in $rawLines) {
        $cleanLine = $rl.TrimEnd("`r")
        if ($cleanLine.Contains("`r")) { $cleanLine = ($cleanLine -split "`r")[-1] }
        # Loại bỏ mã màu/điều khiển ANSI nếu winget xuất ra luồng chuyển hướng
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
                    if ($availIdx -gt $verIdx -and $line.Length -gt $availIdx) {
                        $version = $line.Substring($verIdx, $availIdx - $verIdx).Trim()
                        if ($srcIdx -gt $availIdx -and $line.Length -gt $srcIdx) {
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
                $hasUpdate = (-not [string]::IsNullOrWhiteSpace($avail)) -and ($avail -ne "winget") -and ($avail -ne "msstore")
                $clean = Get-CleanAppName $appName
                $parsed.Add([PSCustomObject]@{
                    Name      = $appName
                    ID        = $appId
                    Version   = $version
                    Available = $avail
                    HasUpdate = $hasUpdate
                    CleanName = $clean
                })
            }
        }
    } elseif ($AllowHeaderless) {
        # Chỉ fallback khi winget thoát bình thường và dòng thực sự có ID hợp lệ
        foreach ($line in $lines) {
            if (-not [string]::IsNullOrWhiteSpace($line) -and -not ($line -like "---*")) {
                $cols = [System.Text.RegularExpressions.Regex]::Split($line.Trim(), '\s{2,}')
                if ($cols.Count -ge 2) {
                    $appName = $cols[0].Trim()
                    $appId   = $cols[1].Trim()
                    if ($appId -notmatch '^(ARP|MSIX)\\|\S+\.\S+') { continue }
                    $version = if ($cols.Count -ge 3) { $cols[2].Trim() } else { "" }
                    $avail   = if ($cols.Count -ge 4) { $cols[3].Trim() } else { "" }
                    $hasUpdate = ($cols.Count -ge 5 -or ($cols.Count -eq 4 -and $avail -ne "winget" -and $avail -ne "msstore" -and $avail -ne ""))
                    $clean = Get-CleanAppName $appName

                    $parsed.Add([PSCustomObject]@{
                        Name      = $appName
                        ID        = $appId
                        Version   = $version
                        Available = $avail
                        HasUpdate = $hasUpdate
                        CleanName = $clean
                    })
                }
            }
        }
    }

    return [PSCustomObject]@{ HasTable = ($separatorIndex -gt 0); Items = $parsed }
}

function Get-LocalInstalledEntries {
    $localItems = [System.Collections.Generic.List[object]]::new()
    $regRoots = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*';             Prefix = 'ARP\Machine\X64\' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Prefix = 'ARP\Machine\X86\' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*';             Prefix = 'ARP\User\X64\' },
        @{ Path = 'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Prefix = 'ARP\User\X86\' }
    )

    foreach ($root in $regRoots) {
        $entries = Get-ItemProperty $root.Path -ErrorAction SilentlyContinue
        foreach ($reg in $entries) {
            if ([string]::IsNullOrWhiteSpace($reg.DisplayName) -or $reg.SystemComponent -eq 1 -or $reg.ReleaseType) { continue }
            $appName = [string]$reg.DisplayName
            if ($appName -match 'Additional Runtime|Minimum Runtime|Debug Runtime|IntelliSense|Language Pack') { continue }

            $appId = $root.Prefix + [string]$reg.PSChildName
            $localItems.Add([PSCustomObject]@{
                Name      = $appName.Trim()
                ID        = $appId
                Version   = [string]$reg.DisplayVersion
                Available = ""
                HasUpdate = $false
                CleanName = (Get-CleanAppName $appName)
            })
        }
    }

    foreach ($pkg in (Get-AppxPackage -ErrorAction SilentlyContinue)) {
        if ($pkg.IsFramework -or [string]::IsNullOrWhiteSpace($pkg.Name)) { continue }
        $pkgName = [string]$pkg.Name
        $localItems.Add([PSCustomObject]@{
            Name      = $pkgName
            ID        = "MSIX\" + [string]$pkg.PackageFullName
            Version   = [string]$pkg.Version
            Available = ""
            HasUpdate = $false
            CleanName = (Get-CleanAppName $pkgName)
        })
    }

    return $localItems
}

function Scan-And-ColorizeApps {
    if ($script:isScanningApps) {
        Log-Text "[!] Tiến trình quét ứng dụng đang chạy, bỏ qua yêu cầu trùng lặp."
        return
    }

    $script:isScanningApps = $true
    try {
        Log-Text "[🔍] Đang quét nhận diện ứng dụng & kiểm tra cập nhật..."
        if ($txtStatus) { $txtStatus.Text = "Đang kiểm tra phiên bản app..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        [System.Windows.Forms.Application]::DoEvents()

        $wingetItems = [System.Collections.Generic.List[object]]::new()
        $wingetOk = $false
        $wingetMissing = $false

        try {
            $primary = Invoke-WingetListCapture -Arguments "list --disable-interactivity --accept-source-agreements" -TimeoutSeconds 35
            if (-not $primary.Available) {
                $wingetMissing = $true
                Log-Text "[⚠️] Chưa có WinGet; chuyển sang quét cục bộ qua Registry & Appx."
            } else {
                $parsedPrimary = ConvertFrom-WingetListOutput -RawText $primary.StdOut -AllowHeaderless ($primary.ExitCode -eq 0 -and -not $primary.TimedOut)
                if (-not $primary.TimedOut -and $primary.ExitCode -eq 0 -and $parsedPrimary.Items.Count -gt 0) {
                    $wingetItems = $parsedPrimary.Items
                    $wingetOk = $true
                } else {
                    if ($primary.TimedOut) {
                        Log-Text "[⚠️] WinGet (tất cả nguồn) quá thời gian chờ (35s); đang thử lại với nguồn --source winget..."
                    } else {
                        Log-Text "[⚠️] WinGet (tất cả nguồn) trả về mã $($primary.ExitCode) ($($parsedPrimary.Items.Count) dòng); đang thử lại --source winget..."
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

        $idMap         = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $nameMap       = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $cleanNameMap  = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $installedList = [System.Collections.Generic.List[object]]::new()

        foreach ($itemObj in $wingetItems) {
            $installedList.Add($itemObj)
            Set-PreferredMapEntry $idMap $itemObj.ID $itemObj
            Set-PreferredMapEntry $nameMap $itemObj.Name $itemObj
            if ($itemObj.CleanName.Length -ge 3) { Set-PreferredMapEntry $cleanNameMap $itemObj.CleanName $itemObj }
        }

        # Luôn bổ sung dữ liệu cục bộ từ Uninstall Registry + Appx để không bao giờ rớt app đã cài khi WinGet trục trặc
        $localItems = Get-LocalInstalledEntries
        foreach ($locObj in $localItems) {
            $installedList.Add($locObj)
            Set-PreferredMapEntry $idMap $locObj.ID $locObj
            Set-PreferredMapEntry $nameMap $locObj.Name $locObj
            if ($locObj.CleanName.Length -ge 3) { Set-PreferredMapEntry $cleanNameMap $locObj.CleanName $locObj }
        }

        if ($installedList.Count -eq 0 -and -not $wingetOk) {
            Log-Text "[!] Không nhận được danh sách ứng dụng từ cả WinGet lẫn cục bộ. Giữ nguyên trạng thái hiện tại."
            if ($txtStatus -and -not $script:hasCompletedAppScan) {
                $txtStatus.Text = if ($wingetMissing) { "Thiếu WinGet | Quét thất bại" } else { "Lỗi quét WinGet | Hãy thử Get Installed lại" }
            }
            return
        }

    # Bộ nhớ đệm tra cứu đa bí danh tốc độ cao (Multi-Alias Lookup Cache)
    $lookupCache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Find-InstalledAppFast {
        param($targetApp)

        $targetId = $targetApp.ID
        $cachedMatch = $null
        if ($lookupCache.TryGetValue($targetId, [ref]$cachedMatch)) {
            return $cachedMatch
        }

        # 1. Exact ID match (O(1))
        $match = $null
        if ($idMap.TryGetValue($targetId, [ref]$match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        # 2. Exact Name match (O(1))
        if ($targetApp.Name -and $nameMap.TryGetValue($targetApp.Name, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        # 3. Tra cứu danh sách Aliases trong O(1)
        if ($targetApp.Aliases) {
            foreach ($alias in $targetApp.Aliases) {
                if ([string]::IsNullOrWhiteSpace($alias)) { continue }
                if ($idMap.TryGetValue($alias, [ref]$match)) {
                    $lookupCache[$targetId] = $match
                    return $match
                }
                if ($nameMap.TryGetValue($alias, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
                    $lookupCache[$targetId] = $match
                    return $match
                }
                $cleanAlias = Get-CleanAppName $alias
                if ($cleanAlias.Length -ge 3 -and $cleanNameMap.TryGetValue($cleanAlias, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
                    $lookupCache[$targetId] = $match
                    return $match
                }
            }
        }

        # 4. Clean Name match (O(1))
        $cleanTarget = Get-CleanAppName $targetApp.Name
        if ($cleanTarget.Length -ge 3 -and $cleanNameMap.TryGetValue($cleanTarget, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        # 5. Fuzzy / Non-Alphanumeric Boundary Matching (khớp chuẩn cả chuỗi chứa dấu +, ., (x64), (x86))
        if ($targetApp.Aliases) {
            foreach ($alias in $targetApp.Aliases) {
                if ([string]::IsNullOrWhiteSpace($alias) -or $alias.Length -lt 4) { continue }
                $pattern = "(?<![a-zA-Z0-9])" + [System.Text.RegularExpressions.Regex]::Escape($alias) + "(?![a-zA-Z0-9])"
                foreach ($item in $installedList) {
                    if (-not (Test-MatchCompatible $targetApp $item)) { continue }
                    if ($item.ID -match $pattern -or $item.Name -match $pattern) {
                        $lookupCache[$targetId] = $item
                        return $item
                    }
                }
            }
        }

        if ($cleanTarget.Length -ge 4) {
            $patternClean = "(?<![a-zA-Z0-9])" + [System.Text.RegularExpressions.Regex]::Escape($cleanTarget) + "(?![a-zA-Z0-9])"
            foreach ($item in $installedList) {
                if (-not (Test-MatchCompatible $targetApp $item)) { continue }
                if ($item.CleanName -match $patternClean) {
                    $lookupCache[$targetId] = $item
                    return $item
                }
            }
        }

        $lookupCache[$targetId] = $null
        return $null
    }

    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    $countInstalled = 0
    $countLatest = 0
    $countOutdated = 0

    foreach ($row in $allItemBorders) {
        $app = $row.Tag.App
        $grid = $row.Child
        $tb = if ($row.Tag.NameText) { $row.Tag.NameText } else { $grid.Children[2] }
        $updateBadge = $row.Tag.UpdateBadge
        $updateText  = $row.Tag.UpdateText
        $idnPrefix = if ($app.IDn) { "[#$($app.IDn)] " } else { "" }

        $info = Find-InstalledAppFast $app

        if ($info) {
            $countInstalled++
            # Lưu lại ID phát hiện thực tế để phục vụ lệnh gỡ cài đặt chính xác
            $row.Tag.DetectedId = $info.ID
            $row.Tag.InstalledVersion = $info.Version

            if ($info.HasUpdate -eq $true) {
                # ── 🔴 BẢN CŨ: Tên ĐỎ + Pill phiên bản mới gọn gàng (không cắt mất tên App) ──
                $countOutdated++
                $row.Tag.Status = "OUTDATED"
                $row.Background = $script:brushNoneBg
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
                # ── 🟢 BẢN MỚI NHẤT: Tên XANH LÁ ──
                $countLatest++
                $row.Tag.Status = "LATEST"
                $row.Background = $script:brushNoneBg
                $tb.Foreground = $script:brushLatestFg
                $tb.Text = $app.Name
                $tb.TextDecorations = $null
                if ($updateBadge) { $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed }
                $tip = "$idnPrefix$($app.Name)`nPhiên bản: $($info.Version) (Mới nhất)`nID phát hiện: $($info.ID)"
                $tb.ToolTip = $tip
                $row.ToolTip = $tip
            }
        } else {
            # ── ⚪ CHƯA CÀI ĐẶT: Tên TRẮNG + Nền trong suốt ──
            $row.Tag.Status = "NONE"
            $row.Tag.DetectedId = $null
            $row.Tag.InstalledVersion = $null
            $row.Background = $script:brushNoneBg
            $tb.Foreground = $script:brushNoneFg
            $tb.Text = $app.Name
            $tb.TextDecorations = $null
            if ($updateBadge) { $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed }
            $tip = "$idnPrefix$($app.Name)`nTrạng thái: Chưa cài đặt`nID: $($app.ID)"
            $tb.ToolTip = $tip
            $row.ToolTip = $tip
        }
    }

        $script:hasCompletedAppScan = $true
        $modeTag = if (-not $wingetOk) { " [Chế độ dự phòng Registry/Appx]" } else { "" }
        $summary = "Đã quét xong: $countInstalled app đã cài ($countLatest bản mới nhất [🟢 XANH], $countOutdated bản cũ [🔴 ĐỎ])$modeTag"
        Log-Text "[✓] $summary"
        if ($txtStatus) {
            $txtStatus.Text = "$countInstalled app đã cài ($countLatest mới / $countOutdated cũ)" + $(if (-not $wingetOk) { " [Dự phòng]" } else { "" })
        }
    } finally {
        $script:isScanningApps = $false
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
    }
}
