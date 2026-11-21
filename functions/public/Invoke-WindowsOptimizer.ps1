function Get-OptimizerBackupDirectory {
    $dir = Join-Path $env:LOCALAPPDATA "AppDriver\OptimizerBackups"
    if (-not [System.IO.Directory]::Exists($dir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }
    return $dir
}

function Get-OptimizerHardwareProfile {
    if ("DuckUtil.WindowsOptimizerEngine" -as [type]) {
        try { return [DuckUtil.WindowsOptimizerEngine]::DetectHardwareProfile() } catch {}
    }
    return [PSCustomObject]@{
        IsLaptop         = $false
        HasBattery       = $false
        TotalRamGb       = 0
        OsBuild          = 0
        IsWin11          = $true
        OsDisplayVersion = ""
        IsSystemDriveSsd = $true
        DiskTypeKnown    = $false
        SummaryText      = "Windows PC"
    }
}

function Get-OptimizerTweaksProbeSpecs {
    param($Catalog)
    if (-not $Catalog -or -not ("DuckUtil.TweakProbeSpec" -as [type])) { return @() }
    $list = [System.Collections.Generic.List[DuckUtil.TweakProbeSpec]]::new()
    foreach ($tw in $Catalog) {
        $sp = [DuckUtil.TweakProbeSpec]::new()
        $sp.Id = [string]$tw.Id
        $sp.MinBuild = if ($tw.PSObject.Properties['MinBuild'] -and $null -ne $tw.MinBuild) { [int]$tw.MinBuild } else { 0 }
        $sp.ActionKind = if ($tw.PSObject.Properties['ActionKind']) { [string]$tw.ActionKind } else { "" }
        $sp.ActionParam = if ($tw.PSObject.Properties['ActionParam']) { [string]$tw.ActionParam } else { "" }

        if ($tw.PSObject.Properties['Registry'] -and $tw.Registry) {
            $rList = [System.Collections.Generic.List[DuckUtil.TweakRegRule]]::new()
            foreach ($r in $tw.Registry) {
                $rr = [DuckUtil.TweakRegRule]::new()
                $rr.Path = [string]$r.Path
                $rr.Name = [string]$r.Name
                $rr.ValueType = if ($r.PSObject.Properties['ValueType']) { [string]$r.ValueType } else { "DWord" }
                $rr.ApplyValue = if ($r.PSObject.Properties['ApplyValue']) { [string]$r.ApplyValue } else { "" }
                $rr.UndoValue = if ($r.PSObject.Properties['UndoValue']) { [string]$r.UndoValue } else { "" }
                $rr.DeleteOnUndo = if ($r.PSObject.Properties['DeleteOnUndo']) { [bool]$r.DeleteOnUndo } else { $false }
                $rr.DeleteOnApply = if ($r.PSObject.Properties['DeleteOnApply']) { [bool]$r.DeleteOnApply } else { $false }
                [void]$rList.Add($rr)
            }
            $sp.RegRules = $rList.ToArray()
        }
        if ($tw.PSObject.Properties['Services'] -and $tw.Services) {
            $sp.Services = [string[]]@($tw.Services)
        }
        [void]$list.Add($sp)
    }
    return $list.ToArray()
}

function New-OptimizerRestorePoint {
    try {
        $srPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
        $prevFreq = [DuckUtil.WindowsOptimizerEngine]::CaptureRegistryValue($srPath, "SystemRestorePointCreationFrequency")
        [void][DuckUtil.WindowsOptimizerEngine]::SetRegistryValue($srPath, "SystemRestorePointCreationFrequency", "DWord", "0", $false)
        try {
            Enable-ComputerRestore -Drive "$($env:SystemDrive)\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description "AppDriver Optimizer Snapshot" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
            Log-Text "[SUCC] Đã tạo System Restore Point (AppDriver Optimizer Snapshot)."
            return $true
        } finally {
            [void][DuckUtil.WindowsOptimizerEngine]::RestoreRegistrySnapshot($prevFreq)
        }
    } catch {
        Log-Text "[WARN] Không thể tạo System Restore Point (có thể Volume Shadow Copy đang tắt): $($_.Exception.Message)"
        return $false
    }
}

function Save-OptimizerPreChangeSnapshot {
    param([object[]]$Tweaks)
    if (-not $Tweaks -or $Tweaks.Count -eq 0) { return "" }
    if (-not ("DuckUtil.WindowsOptimizerEngine" -as [type])) { return "" }

    $bkpDir = Get-OptimizerBackupDirectory
    $regRecords = [System.Collections.Generic.List[object]]::new()
    $svcRecords = [System.Collections.Generic.List[object]]::new()
    $seenReg = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $seenSvc = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($tw in $Tweaks) {
        if ($tw.PSObject.Properties['Registry'] -and $tw.Registry) {
            foreach ($r in $tw.Registry) {
                $rk = "$($r.Path)|$($r.Name)"
                if ($seenReg.Add($rk)) {
                    $rec = [DuckUtil.WindowsOptimizerEngine]::CaptureRegistryValue([string]$r.Path, [string]$r.Name)
                    [void]$regRecords.Add([PSCustomObject]@{
                        Path      = $rec.Path
                        Name      = $rec.Name
                        Existed   = $rec.Existed
                        ValueType = $rec.ValueType
                        ValueData = $rec.ValueData
                    })
                }
            }
        }
        if ($tw.PSObject.Properties['Services'] -and $tw.Services) {
            foreach ($s in $tw.Services) {
                if ($seenSvc.Add([string]$s)) {
                    $st = [DuckUtil.WindowsOptimizerEngine]::GetServiceStartType([string]$s)
                    if ($st -ge 0) {
                        [void]$svcRecords.Add([PSCustomObject]@{ Name = [string]$s; Start = $st })
                    }
                }
            }
        }
    }

    $activeScheme = ""
    try {
        $pOut = & powercfg.exe /getactivescheme 2>$null
        if ($pOut -and ($pOut -join " ") -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            $activeScheme = $Matches[1]
        }
    } catch {}

    $snapObj = [PSCustomObject]@{
        CreatedAtUtc      = [DateTime]::UtcNow.ToString("o")
        TweakIds          = @($Tweaks | ForEach-Object { [string]$_.Id })
        ActivePowerScheme = $activeScheme
        Registry          = $regRecords.ToArray()
        Services          = $svcRecords.ToArray()
    }

    $fileName = "snapshot_" + (Get-Date).ToString("yyyyMMdd_HHmmss") + ".json"
    $fullPath = Join-Path $bkpDir $fileName
    try {
        $json = $snapObj | ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText($fullPath, $json, [System.Text.UTF8Encoding]::new($false))
        # Prune older snapshots (keep latest 15)
        $allFiles = @(Get-ChildItem -Path $bkpDir -Filter "snapshot_*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
        if ($allFiles.Count -gt 15) {
            foreach ($old in ($allFiles | Select-Object -Skip 15)) {
                Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue
            }
        }
        return $fullPath
    } catch {
        return ""
    }
}

function Restore-OptimizerSnapshot {
    param([Parameter(Mandatory = $true)][string]$SnapshotPath)
    if (-not (Test-Path -LiteralPath $SnapshotPath)) {
        Log-Text "[ERR] Không tìm thấy tệp sao lưu OptimizerGuard: $SnapshotPath"
        return $false
    }
    try {
        $snap = Get-Content -Raw -Encoding UTF8 -LiteralPath $SnapshotPath | ConvertFrom-Json
        $regOk = 0; $svcOk = 0
        if ($snap.Registry) {
            foreach ($r in $snap.Registry) {
                $rec = [DuckUtil.RegSnapshotRecord]::new()
                $rec.Path = [string]$r.Path
                $rec.Name = [string]$r.Name
                $rec.Existed = [bool]$r.Existed
                $rec.ValueType = [string]$r.ValueType
                $rec.ValueData = [string]$r.ValueData
                if ([DuckUtil.WindowsOptimizerEngine]::RestoreRegistrySnapshot($rec)) { $regOk++ }
            }
        }
        if ($snap.Services) {
            foreach ($s in $snap.Services) {
                if ([DuckUtil.WindowsOptimizerEngine]::SetServiceStartType([string]$s.Name, [int]$s.Start)) { $svcOk++ }
            }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$snap.ActivePowerScheme)) {
            try { & powercfg.exe /setactive $snap.ActivePowerScheme 2>$null | Out-Null } catch {}
        }
        Log-Text "[SUCC] OptimizerGuard: Đã khôi phục nguyên bản $regOk khóa Registry và $svcOk dịch vụ từ $([System.IO.Path]::GetFileName($SnapshotPath))."
        return $true
    } catch {
        Log-Text "[ERR] Lỗi khôi phục bản sao lưu OptimizerGuard: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-OptimizerAction {
    param(
        [string]$ActionKind,
        [string]$ActionParam,
        [ValidateSet("Apply", "Undo")]
        [string]$Mode = "Apply"
    )
    $kind = if ($ActionKind) { $ActionKind.Trim().ToLowerInvariant() } else { "" }
    switch ($kind) {
        "restore_point" {
            if ($Mode -eq "Undo") { return $true }
            return (New-OptimizerRestorePoint)
        }
        "hibernation_off" {
            $arg = if ($Mode -eq "Apply") { "/hibernate off" } else { "/hibernate on" }
            $p = Start-Process -FilePath "powercfg.exe" -ArgumentList $arg -WindowStyle Hidden -Wait -PassThru
            return ($p.ExitCode -eq 0)
        }
        "clean_temp" {
            if ($Mode -eq "Undo") { return $true }
            $removed = 0
            foreach ($tDir in @($env:TEMP, (Join-Path $env:SystemRoot "Temp"))) {
                if (-not [string]::IsNullOrWhiteSpace($tDir) -and (Test-Path -LiteralPath $tDir)) {
                    foreach ($it in @(Get-ChildItem -LiteralPath $tDir -Force -ErrorAction SilentlyContinue)) {
                        try {
                            Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction Stop
                            $removed++
                        } catch {}
                    }
                }
            }
            Log-Text "   [SUCC] Đã dọn $removed mục tệp tạm."
            return $true
        }
        "disk_cleanup" {
            if ($Mode -eq "Undo") { return $true }
            Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/d C:" -ErrorAction SilentlyContinue
            return $true
        }
        "ultimate_perf" {
            if ($Mode -eq "Apply") {
                $dupOut = (& powercfg.exe -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null) -join " "
                $targetGuid = ""
                if ($dupOut -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                    $targetGuid = $Matches[1]
                } else {
                    $listOut = (& powercfg.exe /list 2>$null)
                    foreach ($ln in $listOut) {
                        if ($ln -match 'Ultimate' -and $ln -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                            $targetGuid = $Matches[1]; break
                        }
                    }
                }
                if (-not [string]::IsNullOrWhiteSpace($targetGuid)) {
                    & powercfg.exe /setactive $targetGuid 2>$null | Out-Null
                    return ($LASTEXITCODE -eq 0)
                }
                return $false
            } else {
                & powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>$null | Out-Null
                return ($LASTEXITCODE -eq 0)
            }
        }
        "classic_context_menu" {
            $clsidPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
            if ($Mode -eq "Apply") {
                return [DuckUtil.WindowsOptimizerEngine]::SetRegistryValue("$clsidPath\InprocServer32", "", "String", "", $false)
            } else {
                if (Test-Path -LiteralPath $clsidPath) {
                    Remove-Item -LiteralPath $clsidPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                return $true
            }
        }
        "remove_home_gallery" {
            $galleryKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}"
            $homeKey    = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}"
            if ($Mode -eq "Apply") {
                foreach ($k in @($galleryKey, $homeKey)) {
                    if (Test-Path -LiteralPath $k) { Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction SilentlyContinue }
                }
                return $true
            } else {
                [void][DuckUtil.WindowsOptimizerEngine]::SetRegistryValue($galleryKey, "", "String", "Gallery", $false)
                [void][DuckUtil.WindowsOptimizerEngine]::SetRegistryValue($homeKey, "", "String", "CLSID_MSGraphHomeFolder", $false)
                return $true
            }
        }
        "dns_switch" {
            $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true })
            if ($adapters.Count -eq 0) {
                $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
            }
            if ($adapters.Count -eq 0) { return $false }
            if ($Mode -eq "Undo") {
                foreach ($ad in $adapters) {
                    Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
                }
                Clear-DnsClientCache -ErrorAction SilentlyContinue
                return $true
            }
            $dnsPair = switch ($ActionParam) {
                "Cloudflare" { @("1.1.1.1", "1.0.0.1") }
                "Google"     { @("8.8.8.8", "8.8.4.4") }
                "AdGuard"    { @("94.140.14.14", "94.140.15.15") }
                "Quad9"      { @("9.9.9.9", "149.112.112.112") }
                default      { @("1.1.1.1", "1.0.0.1") }
            }
            foreach ($ad in $adapters) {
                Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ServerAddresses $dnsPair -ErrorAction SilentlyContinue
            }
            Clear-DnsClientCache -ErrorAction SilentlyContinue
            return $true
        }
        "ipv4_prefer" {
            $p = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
            if ($Mode -eq "Apply") {
                return [DuckUtil.WindowsOptimizerEngine]::SetRegistryValue($p, "DisabledComponents", "DWord", "32", $false)
            } else {
                return [DuckUtil.WindowsOptimizerEngine]::SetRegistryValue($p, "DisabledComponents", "DWord", "0", $true)
            }
        }
        "ipv6_disable" {
            $p = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
            if ($Mode -eq "Apply") {
                return [DuckUtil.WindowsOptimizerEngine]::SetRegistryValue($p, "DisabledComponents", "DWord", "255", $false)
            } else {
                return [DuckUtil.WindowsOptimizerEngine]::SetRegistryValue($p, "DisabledComponents", "DWord", "0", $true)
            }
        }
        "svchost_split_off" {
            $p = "HKLM:\SYSTEM\CurrentControlSet\Control"
            if ($Mode -eq "Apply") {
                return [DuckUtil.WindowsOptimizerEngine]::SetRegistryValue($p, "SvcHostSplitThresholdInKB", "DWord", "33554432", $false)
            } else {
                return [DuckUtil.WindowsOptimizerEngine]::SetRegistryValue($p, "SvcHostSplitThresholdInKB", "DWord", "380000", $false)
            }
        }
        "reserved_storage_off" {
            $state = if ($Mode -eq "Apply") { "Disabled" } else { "Enabled" }
            $p = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Set-ReservedStorageState /State:$state" -WindowStyle Hidden -Wait -PassThru
            return ($p.ExitCode -eq 0)
        }
        "remove_windows_ai" {
            if ($Mode -eq "Apply") {
                Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Microsoft\.Copilot|Microsoft\.Windows\.Ai\.Copilot' } | ForEach-Object {
                    try { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue } catch {}
                }
            }
            return $true
        }
        "remove_onedrive" {
            if ($Mode -eq "Undo") {
                Log-Text "   [INFO] Để cài lại OneDrive, hãy cài qua tab Ứng dụng hoặc Microsoft Store."
                return $true
            }
            Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 400
            $odSetup = Join-Path $env:SystemRoot "SysWOW64\OneDriveSetup.exe"
            if (-not (Test-Path -LiteralPath $odSetup)) { $odSetup = Join-Path $env:SystemRoot "System32\OneDriveSetup.exe" }
            if (Test-Path -LiteralPath $odSetup) {
                $p = Start-Process -FilePath $odSetup -ArgumentList "/uninstall" -WindowStyle Hidden -Wait -PassThru
                return ($p.ExitCode -eq 0)
            }
            return $true
        }
        "block_adobe_net" {
            $hostsPath = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
            $markerStart = "# AppDriver-AdobeBlock START"
            $markerEnd   = "# AppDriver-AdobeBlock END"
            $raw = if (Test-Path -LiteralPath $hostsPath) { [System.IO.File]::ReadAllText($hostsPath) } else { "" }
            $cleaned = [regex]::Replace($raw, "(?s)\r?\n?$([regex]::Escape($markerStart)).*?$([regex]::Escape($markerEnd))\r?\n?", "`r`n").TrimEnd()
            if ($Mode -eq "Undo") {
                [System.IO.File]::WriteAllText($hostsPath, ($cleaned + "`r`n"), [System.Text.UTF8Encoding]::new($false))
                Clear-DnsClientCache -ErrorAction SilentlyContinue
                return $true
            }
            $domains = @(
                "0.0.0.0 ic.adobe.io",
                "0.0.0.0 cc-api-data.adobe.io",
                "0.0.0.0 prod.adobegenuine.com",
                "0.0.0.0 genuine.adobe.com",
                "0.0.0.0 lcs-cops.adobe.io",
                "0.0.0.0 p13n.adobe.io"
            )
            $block = "`r`n$markerStart`r`n" + ($domains -join "`r`n") + "`r`n$markerEnd`r`n"
            [System.IO.File]::WriteAllText($hostsPath, ($cleaned + $block), [System.Text.UTF8Encoding]::new($false))
            Clear-DnsClientCache -ErrorAction SilentlyContinue
            return $true
        }
        default { return $true }
    }
}

function Invoke-OptimizerSingleTweak {
    param(
        [Parameter(Mandatory = $true)]$Tweak,
        [ValidateSet("Apply", "Undo")]
        [string]$Mode = "Apply"
    )
    $allOk = $true

    if ($Tweak.PSObject.Properties['Registry'] -and $Tweak.Registry) {
        foreach ($r in $Tweak.Registry) {
            if ($Mode -eq "Apply") {
                $delA = ($r.PSObject.Properties['DeleteOnApply'] -and [bool]$r.DeleteOnApply)
                $ok = [DuckUtil.WindowsOptimizerEngine]::SetRegistryValue([string]$r.Path, [string]$r.Name, [string]$r.ValueType, [string]$r.ApplyValue, $delA)
                if (-not $ok) { $allOk = $false }
            } else {
                $delU = ($r.PSObject.Properties['DeleteOnUndo'] -and [bool]$r.DeleteOnUndo)
                $ok = [DuckUtil.WindowsOptimizerEngine]::SetRegistryValue([string]$r.Path, [string]$r.Name, [string]$r.ValueType, [string]$r.UndoValue, $delU)
                if (-not $ok) { $allOk = $false }
            }
        }
    }

    if ($Tweak.PSObject.Properties['Services'] -and $Tweak.Services) {
        $isDisableSvc = ([string]$Tweak.Id -in @("opt_telemetry_off", "adv_search_index_off"))
        foreach ($svc in $Tweak.Services) {
            $curSt = [DuckUtil.WindowsOptimizerEngine]::GetServiceStartType([string]$svc)
            if ($curSt -lt 0) { continue }
            if ($Mode -eq "Apply") {
                $targetSt = if ($isDisableSvc) { 4 } else { 3 }
                [void][DuckUtil.WindowsOptimizerEngine]::SetServiceStartType([string]$svc, $targetSt)
                if ($isDisableSvc) {
                    try { Stop-Service -Name ([string]$svc) -Force -ErrorAction SilentlyContinue } catch {}
                }
            } else {
                $undoSt = if ($isDisableSvc) { 2 } else { 3 }
                [void][DuckUtil.WindowsOptimizerEngine]::SetServiceStartType([string]$svc, $undoSt)
                if ($isDisableSvc) {
                    try { Start-Service -Name ([string]$svc) -ErrorAction SilentlyContinue } catch {}
                }
            }
        }
    }

    if ($Tweak.PSObject.Properties['Tasks'] -and $Tweak.Tasks) {
        $flag = if ($Mode -eq "Apply") { "/DISABLE" } else { "/ENABLE" }
        foreach ($tk in $Tweak.Tasks) {
            try {
                Start-Process -FilePath "schtasks.exe" -ArgumentList "/Change /TN `"$tk`" $flag" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
            } catch {}
        }
    }

    if ($Tweak.PSObject.Properties['ActionKind'] -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.ActionKind)) {
        $aParam = if ($Tweak.PSObject.Properties['ActionParam']) { [string]$Tweak.ActionParam } else { "" }
        $actOk = Invoke-OptimizerAction -ActionKind ([string]$Tweak.ActionKind) -ActionParam $aParam -Mode $Mode
        if (-not $actOk) { $allOk = $false }
    }

    return $allOk
}

function Invoke-OptimizerBatch {
    param(
        [Parameter(Mandatory = $true)][object[]]$Tweaks,
        [ValidateSet("Apply", "Undo")]
        [string]$Mode = "Apply",
        [switch]$CreateSnapshot
    )
    $okCnt = 0
    $failCnt = 0
    $snapPath = ""
    $needExplorer = $false

    if ($Mode -eq "Apply" -and $CreateSnapshot) {
        $snapPath = Save-OptimizerPreChangeSnapshot -Tweaks $Tweaks
        if (-not [string]::IsNullOrWhiteSpace($snapPath)) {
            Log-Text "[SUCC] OptimizerGuard: Đã sao lưu trạng thái gốc -> $([System.IO.Path]::GetFileName($snapPath))"
        }
    }

    $total = $Tweaks.Count
    $idx = 0
    foreach ($tw in $Tweaks) {
        if ($script:cancelRequested -or $script:isWindowClosing) { break }
        $idx++
        $verb = if ($Mode -eq "Apply") { "Áp dụng" } else { "Hoàn tác" }
        Log-Text "[$idx/$total] ${verb}: $($tw.Name)..."
        try {
            $res = Invoke-OptimizerSingleTweak -Tweak $tw -Mode $Mode
            if ($res) {
                $okCnt++
                Log-Text "   [SUCC] $($tw.Name)"
                if ($tw.PSObject.Properties['RestartExplorer'] -and [bool]$tw.RestartExplorer) {
                    $needExplorer = $true
                }
            } else {
                $failCnt++
                Log-Text "   [ERR] Không thể thực thi trọn vẹn: $($tw.Name)"
            }
        } catch {
            $failCnt++
            Log-Text "   [ERR] Lỗi '$($tw.Name)': $($_.Exception.Message)"
        }
    }

    $restartedExp = $false
    if ($needExplorer -and -not $script:cancelRequested -and -not $script:isWindowClosing) {
        try {
            Log-Text "[*] Đang nạp lại Windows Explorer để áp dụng thay đổi giao diện..."
            Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 600
            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                Start-Process "explorer.exe"
            }
            $restartedExp = $true
            Log-Text "[SUCC] Đã nạp lại Windows Explorer."
        } catch {}
    }

    return [PSCustomObject]@{
        OkCount           = $okCnt
        FailCount         = $failCnt
        SnapshotPath      = $snapPath
        RestartedExplorer = $restartedExp
    }
}
