# ── FUNCTION: QUÉT & PHÂN LOẠI MÀU PHIÊN BẢN (TRẮNG / XANH / ĐỎ) ──
function Scan-And-ColorizeApps {
    Log-Text "[🔍] Đang chạy quét nhận diện ứng dụng & phân tích phiên bản (winget list)..."
    $txtStatus.Text = "Đang kiểm tra phiên bản app..."
    $progressBar.IsIndeterminate = $true
    [System.Windows.Forms.Application]::DoEvents()

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
        $pinfo.Arguments = "list"
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($pinfo)
        $rawList = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
    } catch {
        Log-Text "[!] Lỗi khi quét danh sách ứng dụng qua WinGet: $($_.Exception.Message)"
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        return
    }

    # Phân tích danh sách đã cài đặt từ winget
    $lines = $rawList -split "`r?`n"
    $start = $false
    $installedItems = @()

    foreach ($line in $lines) {
        if ($line -like "---*") { $start = $true; continue }
        if ($start -and -not [string]::IsNullOrWhiteSpace($line)) {
            $cols = [System.Text.RegularExpressions.Regex]::Split($line.Trim(), "\s{2,}")
            if ($cols.Count -ge 2) {
                $installedItems += [PSCustomObject]@{
                    Name      = $cols[0].Trim()
                    ID        = $cols[1].Trim()
                    Version   = if ($cols.Count -ge 3) { $cols[2].Trim() } else { "" }
                    Available = if ($cols.Count -ge 4) { $cols[3].Trim() } else { "" }
                    HasUpdate = ($cols.Count -ge 5 -or ($cols.Count -eq 4 -and $cols[3].Trim() -ne "winget" -and $cols[3].Trim() -ne "msstore" -and $cols[3].Trim() -ne ""))
                }
            }
        }
    }

    # Hàm khớp thông minh (Exact ID -> Aliases -> Clean Name)
    function Find-InstalledAppInfo {
        param($targetApp, $items)
        
        # 1. Exact ID
        $match = $items | Where-Object { $_.ID -eq $targetApp.ID } | Select-Object -First 1
        if ($match) { return $match }

        # 2. Check Aliases (Brave, Zalo, Telegram, WinSCP, ProtonVPN...)
        if ($targetApp.Aliases) {
            foreach ($alias in $targetApp.Aliases) {
                $al = $alias.ToLower()
                $match = $items | Where-Object {
                    $_.ID.ToLower() -eq $al -or
                    $_.Name.ToLower() -eq $al -or
                    $_.ID.ToLower().Contains($al) -or
                    $_.Name.ToLower().StartsWith($al)
                } | Select-Object -First 1
                if ($match) { return $match }
            }
        }

        # 3. Clean Name match
        $clean = ($targetApp.Name -replace '\(.*?\)', '').Trim().ToLower()
        foreach ($term in @(" browser", " desktop", " lts", " client", " free", " ce", " community", " end-user")) {
            $clean = $clean.Replace($term, "")
        }
        if ($clean.Length -ge 3) {
            $match = $items | Where-Object {
                $n = ($_.Name -replace '\(.*?\)', '').Trim().ToLower()
                $n -eq $clean -or $n.StartsWith("$clean ") -or $n.StartsWith($clean)
            } | Select-Object -First 1
            if ($match) { return $match }
        }

        return $null
    }

    $progressBar.IsIndeterminate = $false
    $countInstalled = 0
    $countLatest = 0
    $countOutdated = 0

    foreach ($row in $allItemBorders) {
        $app = $row.Tag.App
        $grid = $row.Child
        $tb = $grid.Children[2]

        $info = Find-InstalledAppInfo $app $installedItems

        if ($info) {
            $countInstalled++

            if ($info.HasUpdate -eq $true) {
                # ── 🔴 BẢN CŨ: Tên ĐỎ rực rỡ + Nền đỏ sẫm ──
                $countOutdated++
                $row.Tag.Status = "OUTDATED"
                $row.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2A1215")
                $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
                $updateBadge = if ($info.Available) { " (Có bản: $($info.Available))" } else { " (Có bản mới)" }
                $tb.Text = "$($app.Name)  ⚠️$updateBadge"
                $tb.ToolTip = "$($app.Name)`nĐang cài: $($info.Version)`nCó bản mới: $($info.Available)`nID phát hiện: $($info.ID)"
            } else {
                # ── 🟢 BẢN MỚI NHẤT: Tên XANH LÁ + Nền xanh sẫm ──
                $countLatest++
                $row.Tag.Status = "LATEST"
                $row.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0D2818")
                $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
                $tb.Text = "$($app.Name)  ✓ (Mới nhất)"
                $tb.ToolTip = "$($app.Name)`nPhiên bản: $($info.Version) (Mới nhất)`nID phát hiện: $($info.ID)"
            }
        } else {
            # ── ⚪ CHƯA CÀI ĐẶT: Tên TRẮNG + Nền trong suốt ──
            $row.Tag.Status = "NONE"
            $row.Background = [System.Windows.Media.Brushes]::Transparent
            $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
            $tb.Text = $app.Name
            $tb.ToolTip = "$($app.Name)`nTrạng thái: Chưa cài đặt`nID: $($app.ID)`n$($app.Desc)"
        }
    }

    $summary = "Đã quét xong: $countInstalled app đã cài ($countLatest bản mới nhất [🟢 XANH], $countOutdated bản cũ [🔴 ĐỎ])"
    Log-Text "[✓] $summary"
    $txtStatus.Text = "$countInstalled app đã cài ($countLatest mới / $countOutdated cũ)"
}
