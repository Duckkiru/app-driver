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

function Scan-And-ColorizeApps {
    Log-Text "[🔍] Đang chạy quét nhận diện ứng dụng & phân tích phiên bản (winget list)..."
    if ($txtStatus) { $txtStatus.Text = "Đang kiểm tra phiên bản app..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    [System.Windows.Forms.Application]::DoEvents()

    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        Log-Text "[⚠️] Máy tính của bạn chưa có WinGet (Windows Package Manager)."
        Log-Text "[*] Vui lòng cài/cập nhật gói 'App Installer' từ Microsoft Store để kích hoạt tính năng App."
        if ($txtStatus) { $txtStatus.Text = "Thiếu WinGet | Cần cài App Installer" }
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        return
    }

    $rawList = ""
    $errList = ""
    try {
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
        if ($null -eq $p) {
            throw "Không thể khởi động tiến trình winget."
        }

        # Đọc dữ liệu bất đồng bộ đồng thời cả 2 luồng stdout và stderr để tránh tràn buffer gây deadlock
        $readTask = $p.StandardOutput.ReadToEndAsync()
        $errTask  = $p.StandardError.ReadToEndAsync()
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $readTask.IsCompleted -or -not $errTask.IsCompleted) {
            if ($sw.Elapsed.TotalSeconds -gt 45) {
                try { if (-not $p.HasExited) { $p.Kill() } } catch {}
                Log-Text "[⚠️] Lệnh winget list vượt quá thời gian chờ (45s)."
                break
            }
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 30
        }
        if ($readTask.IsCompleted) { $rawList = $readTask.Result }
        if ($errTask.IsCompleted) { $errList = $errTask.Result }
        try { if (-not $p.HasExited) { $p.WaitForExit(1000) | Out-Null } } catch {}

        # Kiểm tra ExitCode của winget list
        if ($p.HasExited -and $p.ExitCode -ne 0) {
            Log-Text "[⚠️] WinGet list kết thúc với mã $($p.ExitCode)."
            if (-not [string]::IsNullOrWhiteSpace($errList)) {
                Log-Text "[stderr] $errList"
            }
            if ([string]::IsNullOrWhiteSpace($rawList)) {
                Log-Text "[!] Không nhận được dữ liệu từ WinGet. Giữ nguyên trạng thái quét hiện tại."
                if ($progressBar) { $progressBar.IsIndeterminate = $false }
                if ($txtStatus) { $txtStatus.Text = "Lỗi quét WinGet (Mã $($p.ExitCode))" }
                return
            }
        }
    } catch {
        Log-Text "[!] Lỗi khi quét danh sách ứng dụng qua WinGet: $($_.Exception.Message)"
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        return
    }

    # Chuẩn hóa từng dòng (loại bỏ \r cuối dòng \r\n, đồng thời loại bỏ thanh spinner \r trước nội dung thực)
    $rawLines = $rawList -split "`n"
    $lines = [System.Collections.Generic.List[string]]::new($rawLines.Count)
    foreach ($rl in $rawLines) {
        $cleanLine = $rl.TrimEnd("`r")
        if ($cleanLine.Contains("`r")) { $cleanLine = ($cleanLine -split "`r")[-1] }
        $lines.Add($cleanLine)
    }

    $separatorIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^---\s*---' -or $lines[$i] -match '^---+$') {
            $separatorIndex = $i
            break
        }
    }

    $idMap         = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $nameMap       = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $cleanNameMap  = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $installedList = [System.Collections.Generic.List[object]]::new()

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
                $itemObj = [PSCustomObject]@{
                    Name      = $appName
                    ID        = $appId
                    Version   = $version
                    Available = $avail
                    HasUpdate = $hasUpdate
                    CleanName = $clean
                }

                $installedList.Add($itemObj)
                Set-PreferredMapEntry $idMap $appId $itemObj
                Set-PreferredMapEntry $nameMap $appName $itemObj
                if ($clean.Length -ge 3) { Set-PreferredMapEntry $cleanNameMap $clean $itemObj }
            }
        }
    } else {
        # Fallback hoàn toàn cho winget không in header tiêu chuẩn
        foreach ($line in $lines) {
            if (-not [string]::IsNullOrWhiteSpace($line) -and -not ($line -like "---*")) {
                $cols = [System.Text.RegularExpressions.Regex]::Split($line.Trim(), '\s{2,}')
                if ($cols.Count -ge 2) {
                    $appName = $cols[0].Trim()
                    $appId   = $cols[1].Trim()
                    $version = if ($cols.Count -ge 3) { $cols[2].Trim() } else { "" }
                    $avail   = if ($cols.Count -ge 4) { $cols[3].Trim() } else { "" }
                    $hasUpdate = ($cols.Count -ge 5 -or ($cols.Count -eq 4 -and $avail -ne "winget" -and $avail -ne "msstore" -and $avail -ne ""))
                    $clean = Get-CleanAppName $appName

                    $itemObj = [PSCustomObject]@{
                        Name      = $appName
                        ID        = $appId
                        Version   = $version
                        Available = $avail
                        HasUpdate = $hasUpdate
                        CleanName = $clean
                    }

                    $installedList.Add($itemObj)
                    Set-PreferredMapEntry $idMap $appId $itemObj
                    Set-PreferredMapEntry $nameMap $appName $itemObj
                    if ($clean.Length -ge 3) { Set-PreferredMapEntry $cleanNameMap $clean $itemObj }
                }
            }
        }
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

    $summary = "Đã quét xong: $countInstalled app đã cài ($countLatest bản mới nhất [🟢 XANH], $countOutdated bản cũ [🔴 ĐỎ])"
    Log-Text "[✓] $summary"
    if ($txtStatus) {
        $txtStatus.Text = "$countInstalled app đã cài ($countLatest mới / $countOutdated cũ)"
    }
}
