# ── FUNCTION: QUÉT & PHÂN LOẠI MÀU PHIÊN BẢN (TRẮNG / XANH / ĐỎ) ──

# Bộ nhớ đệm tĩnh lưu trữ Brush của WPF giúp tối ưu render và triệt tiêu Garbage Collection
$script:brushOutdatedBg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x2A, 0x12, 0x15))
$script:brushOutdatedFg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF8, 0x71, 0x71))
$script:brushLatestBg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x0D, 0x28, 0x18))
$script:brushLatestFg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x34, 0xD3, 0x99))
$script:brushNoneBg     = [System.Windows.Media.Brushes]::Transparent
$script:brushNoneFg     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xFF, 0xFF, 0xFF))

$script:brushOutdatedBg.Freeze()
$script:brushOutdatedFg.Freeze()
$script:brushLatestBg.Freeze()
$script:brushLatestFg.Freeze()
$script:brushNoneFg.Freeze()

function Get-CleanAppName {
    param([string]$RawName)
    if ([string]::IsNullOrWhiteSpace($RawName)) { return "" }
    $clean = ($RawName -replace '\(.*?\)', '').Trim().ToLowerInvariant()
    $terms = @(" browser", " desktop", " lts", " client", " free", " ce", " community", " end-user")
    foreach ($term in $terms) {
        $clean = $clean.Replace($term, "")
    }
    return $clean.Trim()
}

function Scan-And-ColorizeApps {
    Log-Text "[🔍] Đang chạy quét nhận diện ứng dụng & phân tích phiên bản (winget list)..."
    if ($txtStatus) { $txtStatus.Text = "Đang kiểm tra phiên bản app..." }
    if ($progressBar) { $progressBar.IsIndeterminate = $true }
    Update-WpfUi

    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        Log-Text "[⚠️] Máy tính của bạn chưa có WinGet (Windows Package Manager)."
        Log-Text "[*] Vui lòng cài/cập nhật gói 'App Installer' từ Microsoft Store để kích hoạt tính năng App."
        if ($txtStatus) { $txtStatus.Text = "Thiếu WinGet | Cần cài App Installer" }
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        return
    }

    $rawList = ""
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

        # Đọc dữ liệu bất đồng bộ kèm bơm Update-WpfUi để thanh tiến trình & UI luôn mượt mà
        $readTask = $p.StandardOutput.ReadToEndAsync()
        while (-not $readTask.IsCompleted) {
            Update-WpfUi
            Start-Sleep -Milliseconds 25
        }
        $rawList = $readTask.Result
        $p.WaitForExit()
    } catch {
        Log-Text "[!] Lỗi khi quét danh sách ứng dụng qua WinGet: $($_.Exception.Message)"
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        return
    }

    # Phân tích danh sách đã cài đặt từ winget với bộ tách cột theo tọa độ Header chuẩn xác
    $lines = $rawList -split "`r?`n"
    $separatorIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^---\s*---') {
            $separatorIndex = $i
            break
        }
    }

    $idMap        = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $nameMap      = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $cleanNameMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $installedList = [System.Collections.Generic.List[object]]::new()

    if ($separatorIndex -gt 0) {
        $headerLine = $lines[$separatorIndex - 1]
        $idIdx    = $headerLine.IndexOf("Id")
        if ($idIdx -lt 0) { $idIdx = $headerLine.IndexOf("ID") }
        $verIdx   = $headerLine.IndexOf("Version")
        $availIdx = $headerLine.IndexOf("Available")
        $srcIdx   = $headerLine.IndexOf("Source")

        for ($j = $separatorIndex + 1; $j -lt $lines.Count; $j++) {
            $line = $lines[$j]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $appName  = ""
            $appId    = ""
            $version  = ""
            $avail    = ""

            if ($idIdx -gt 0 -and $line.Length -gt $idIdx) {
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
                # Fallback tách cột bằng khoảng trắng nếu độ dài chuỗi không khớp
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
                $itemObj = [PSCustomObject]@{
                    Name      = $appName
                    ID        = $appId
                    Version   = $version
                    Available = $avail
                    HasUpdate = $hasUpdate
                }

                $installedList.Add($itemObj)
                if (-not $idMap.ContainsKey($appId)) { $idMap[$appId] = $itemObj }
                if (-not [string]::IsNullOrWhiteSpace($appName) -and -not $nameMap.ContainsKey($appName)) { $nameMap[$appName] = $itemObj }
                $clean = Get-CleanAppName $appName
                if ($clean.Length -ge 3 -and -not $cleanNameMap.ContainsKey($clean)) { $cleanNameMap[$clean] = $itemObj }
            }
        }
    } else {
        # Fallback hoàn toàn cho phiên bản winget không in header tiêu chuẩn
        foreach ($line in $lines) {
            if (-not [string]::IsNullOrWhiteSpace($line) -and -not ($line -like "---*")) {
                $cols = [System.Text.RegularExpressions.Regex]::Split($line.Trim(), '\s{2,}')
                if ($cols.Count -ge 2) {
                    $appName = $cols[0].Trim()
                    $appId   = $cols[1].Trim()
                    $version = if ($cols.Count -ge 3) { $cols[2].Trim() } else { "" }
                    $avail   = if ($cols.Count -ge 4) { $cols[3].Trim() } else { "" }
                    $hasUpdate = ($cols.Count -ge 5 -or ($cols.Count -eq 4 -and $avail -ne "winget" -and $avail -ne "msstore" -and $avail -ne ""))

                    $itemObj = [PSCustomObject]@{
                        Name      = $appName
                        ID        = $appId
                        Version   = $version
                        Available = $avail
                        HasUpdate = $hasUpdate
                    }

                    $installedList.Add($itemObj)
                    if (-not $idMap.ContainsKey($appId)) { $idMap[$appId] = $itemObj }
                    if (-not [string]::IsNullOrWhiteSpace($appName) -and -not $nameMap.ContainsKey($appName)) { $nameMap[$appName] = $itemObj }
                    $clean = Get-CleanAppName $appName
                    if ($clean.Length -ge 3 -and -not $cleanNameMap.ContainsKey($clean)) { $cleanNameMap[$clean] = $itemObj }
                }
            }
        }
    }

    # Bộ nhớ đệm tra cứu đa bí danh (Multi-Alias Lookup Cache)
    $lookupCache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Find-InstalledAppFast {
        param($targetApp)

        $targetId = $targetApp.ID
        $cachedMatch = $null
        if ($lookupCache.TryGetValue($targetId, [ref]$cachedMatch)) {
            return $cachedMatch
        }

        # 1. Exact ID
        $match = $null
        if ($idMap.TryGetValue($targetId, [ref]$match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        # 2. Exact Name
        if ($targetApp.Name -and $nameMap.TryGetValue($targetApp.Name, [ref]$match)) {
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
                if ($nameMap.TryGetValue($alias, [ref]$match)) {
                    $lookupCache[$targetId] = $match
                    return $match
                }
                $cleanAlias = Get-CleanAppName $alias
                if ($cleanAlias.Length -ge 3 -and $cleanNameMap.TryGetValue($cleanAlias, [ref]$match)) {
                    $lookupCache[$targetId] = $match
                    return $match
                }
            }
        }

        # 4. Clean Name match
        $cleanTarget = Get-CleanAppName $targetApp.Name
        if ($cleanTarget.Length -ge 3 -and $cleanNameMap.TryGetValue($cleanTarget, [ref]$match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        # 5. Fuzzy / Substring fallback quét nhanh trên danh sách
        if ($targetApp.Aliases) {
            foreach ($alias in $targetApp.Aliases) {
                $al = $alias.ToLowerInvariant()
                foreach ($item in $installedList) {
                    if ($item.ID.ToLowerInvariant().Contains($al) -or $item.Name.ToLowerInvariant().StartsWith($al)) {
                        $lookupCache[$targetId] = $item
                        return $item
                    }
                }
            }
        }

        if ($cleanTarget.Length -ge 3) {
            foreach ($item in $installedList) {
                $cleanItem = Get-CleanAppName $item.Name
                if ($cleanItem -eq $cleanTarget -or $cleanItem.StartsWith("$cleanTarget ") -or $cleanItem.StartsWith($cleanTarget)) {
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
        $tb = $grid.Children[2]

        $info = Find-InstalledAppFast $app

        if ($info) {
            $countInstalled++

            if ($info.HasUpdate -eq $true) {
                # ── 🔴 BẢN CŨ: Tên ĐỎ rực rỡ + Nền đỏ sẫm ──
                $countOutdated++
                $row.Tag.Status = "OUTDATED"
                $row.Background = $script:brushOutdatedBg
                $tb.Foreground = $script:brushOutdatedFg
                $updateBadge = if ($info.Available) { " (Có bản: $($info.Available))" } else { " (Có bản mới)" }
                $tb.Text = "$($app.Name)  ⚠️$updateBadge"
                $tb.ToolTip = "$($app.Name)`nĐang cài: $($info.Version)`nCó bản mới: $($info.Available)`nID phát hiện: $($info.ID)"
            } else {
                # ── 🟢 BẢN MỚI NHẤT: Tên XANH LÁ + Nền xanh sẫm ──
                $countLatest++
                $row.Tag.Status = "LATEST"
                $row.Background = $script:brushLatestBg
                $tb.Foreground = $script:brushLatestFg
                $tb.Text = "$($app.Name)  ✓ (Mới nhất)"
                $tb.ToolTip = "$($app.Name)`nPhiên bản: $($info.Version) (Mới nhất)`nID phát hiện: $($info.ID)"
            }
        } else {
            # ── ⚪ CHƯA CÀI ĐẶT: Tên TRẮNG + Nền trong suốt ──
            $row.Tag.Status = "NONE"
            $row.Background = $script:brushNoneBg
            $tb.Foreground = $script:brushNoneFg
            $tb.Text = $app.Name
            $tb.ToolTip = "$($app.Name)`nTrạng thái: Chưa cài đặt`nID: $($app.ID)`n$($app.Desc)"
        }
    }

    $summary = "Đã quét xong: $countInstalled app đã cài ($countLatest bản mới nhất [🟢 XANH], $countOutdated bản cũ [🔴 ĐỎ])"
    Log-Text "[✓] $summary"
    if ($txtStatus) {
        $txtStatus.Text = "$countInstalled app đã cài ($countLatest mới / $countOutdated cũ)"
    }
}
