function Get-OptimizerBackupDirectory {
    return (Join-Path $env:LOCALAPPDATA "AppDriver\OptimizerBackups")
}

function Get-OptimizerBackupsList {
    $dir = Get-OptimizerBackupDirectory
    if (-not [System.IO.Directory]::Exists($dir)) { return @() }
    $files = @(Get-ChildItem -LiteralPath $dir -Filter "snapshot_*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $files) {
        try {
            $raw = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
            $obj = ConvertFrom-Json $raw
            if ($obj) {
                $list.Add([PSCustomObject]@{
                    Path        = $f.FullName
                    FileName    = $f.Name
                    CreatedAt   = [string]$obj.CreatedAt
                    TweakCount  = if ($obj.TweakIds) { @($obj.TweakIds).Count } else { 0 }
                    TweakNames  = if ($obj.TweakNames) { @($obj.TweakNames) } else { @() }
                    RegCount    = if ($obj.Registry) { @($obj.Registry).Count } else { 0 }
                    SvcCount    = if ($obj.Services) { @($obj.Services).Count } else { 0 }
                })
            }
        } catch {}
    }
    return $list.ToArray()
}

function ConvertTo-RegTweakSpecs {
    param($TweakObjects)
    $list = [System.Collections.Generic.List[DuckUtil.RegTweakSpec]]::new()
    foreach ($tw in @($TweakObjects)) {
        if (-not $tw -or -not $tw.Registry) { continue }
        foreach ($r in @($tw.Registry)) {
            if (-not $r -or [string]::IsNullOrWhiteSpace([string]$r.Path)) { continue }
            $spec = [DuckUtil.RegTweakSpec]::new()
            $spec.Hive = if ([string]::IsNullOrWhiteSpace([string]$r.Hive)) { "HKLM" } else { [string]$r.Hive }
            $spec.Path = [string]$r.Path
            $spec.Name = [string]$r.Name
            $spec.ValueType = if ([string]::IsNullOrWhiteSpace([string]$r.ValueType)) { "DWord" } else { [string]$r.ValueType }
            $spec.ApplyValue = [string]$r.ApplyValue
            $spec.UndoValue = [string]$r.UndoValue
            [void]$list.Add($spec)
        }
    }
    return $list.ToArray()
}

function ConvertTo-ServiceTweakSpecs {
    param($TweakObjects)
    $list = [System.Collections.Generic.List[DuckUtil.ServiceTweakSpec]]::new()
    foreach ($tw in @($TweakObjects)) {
        if (-not $tw -or -not $tw.Services) { continue }
        foreach ($s in @($tw.Services)) {
            if (-not $s -or [string]::IsNullOrWhiteSpace([string]$s.Name)) { continue }
            $spec = [DuckUtil.ServiceTweakSpec]::new()
            $spec.Name = [string]$s.Name
            $spec.ApplyStart = [int]$s.ApplyStart
            $spec.UndoStart = [int]$s.UndoStart
            [void]$list.Add($spec)
        }
    }
    return $list.ToArray()
}

function Build-TweakProbeRequests {
    param($Tweaks)
    $reqs = [System.Collections.Generic.List[DuckUtil.TweakProbeRequest]]::new()
    foreach ($tw in @($Tweaks)) {
        if (-not $tw) { continue }
        $req = [DuckUtil.TweakProbeRequest]::new()
        $req.Id = [string]$tw.Id
        $req.ProbeKind = [string]$tw.ProbeKind
        $req.Registry = ConvertTo-RegTweakSpecs @($tw)
        $req.Services = ConvertTo-ServiceTweakSpecs @($tw)
        [void]$reqs.Add($req)
    }
    return $reqs.ToArray()
}

function New-OptimizerRestorePoint {
    $freqPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    $hadFreq = $false
    $oldFreq = $null
    try {
        if (Test-Path -LiteralPath $freqPath) {
            $prop = Get-ItemProperty -LiteralPath $freqPath -Name "SystemRestorePointCreationFrequency" -ErrorAction SilentlyContinue
            if ($null -ne $prop -and $null -ne $prop.SystemRestorePointCreationFrequency) {
                $hadFreq = $true
                $oldFreq = $prop.SystemRestorePointCreationFrequency
            }
            Set-ItemProperty -LiteralPath $freqPath -Name "SystemRestorePointCreationFrequency" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        }
        try { Enable-ComputerRestore -Drive ($env:SystemDrive + "\") -ErrorAction SilentlyContinue } catch {}
        Checkpoint-Computer -Description ("App-Driver Optimizer " + (Get-Date -Format "yyyy-MM-dd HH:mm")) -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Log-Text "[OK] Đã tạo điểm khôi phục hệ thống (System Restore Point)."
        return $true
    } catch {
        Log-Text "[WARN] Không thể tạo Restore Point: $($_.Exception.Message)"
        return $false
    } finally {
        try {
            if (Test-Path -LiteralPath $freqPath) {
                if ($hadFreq) {
                    Set-ItemProperty -LiteralPath $freqPath -Name "SystemRestorePointCreationFrequency" -Value $oldFreq -Type DWord -ErrorAction SilentlyContinue
                } else {
                    Remove-ItemProperty -LiteralPath $freqPath -Name "SystemRestorePointCreationFrequency" -ErrorAction SilentlyContinue
                }
            }
        } catch {}
    }
}

function Get-ActivePowerSchemeGuid {
    try {
        $out = & powercfg.exe /getactivescheme 2>$null
        if ($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            return $Matches[1]
        }
    } catch {}
    return ""
}

function Save-OptimizerGuardSnapshot {
    param(
        $Tweaks,
        $HardwareProfile = $null
    )
    if (-not ("DuckUtil.WindowsOptimizerEngine" -as [type])) { return $null }
    $regSpecs = ConvertTo-RegTweakSpecs $Tweaks
    $svcSpecs = ConvertTo-ServiceTweakSpecs $Tweaks

    $hasPowerTweak = $false
    $taskNames = [System.Collections.Generic.List[string]]::new()
    $tweakIds = [System.Collections.Generic.List[string]]::new()
    $tweakNames = [System.Collections.Generic.List[string]]::new()
    $needsExplorer = $false

    foreach ($tw in @($Tweaks)) {
        if (-not $tw) { continue }
        [void]$tweakIds.Add([string]$tw.Id)
        [void]$tweakNames.Add([string]$tw.Name)
        if ($tw.NeedsExplorerRestart) { $needsExplorer = $true }
        if ($tw.Action -eq "UltimatePerf") { $hasPowerTweak = $true }
        if ($tw.Tasks) {
            foreach ($tk in @($tw.Tasks)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$tk) -and -not $taskNames.Contains([string]$tk)) {
                    [void]$taskNames.Add([string]$tk)
                }
            }
        }
    }

    if ($regSpecs.Length -eq 0 -and $svcSpecs.Length -eq 0 -and $taskNames.Count -eq 0 -and -not $hasPowerTweak) {
        return $null
    }

    $regSnaps = [DuckUtil.WindowsOptimizerEngine]::CaptureRegistrySnapshots($regSpecs)
    $svcSnaps = [DuckUtil.WindowsOptimizerEngine]::CaptureServiceSnapshots($svcSpecs)
    $powerGuid = if ($hasPowerTweak) { Get-ActivePowerSchemeGuid } else { "" }

    $dir = Get-OptimizerBackupDirectory
    if (-not [System.IO.Directory]::Exists($dir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $snapPath = Join-Path $dir "snapshot_$stamp.json"

    $payload = [PSCustomObject]@{
        CreatedAt            = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        HardwareSummary      = if ($HardwareProfile) { [string]$HardwareProfile.SummaryText } else { "" }
        TweakIds             = @($tweakIds)
        TweakNames           = @($tweakNames)
        NeedsExplorerRestart = $needsExplorer
        PowerSchemeGuid      = $powerGuid
        Tasks                = @($taskNames)
        Registry             = @($regSnaps)
        Services             = @($svcSnaps)
    }

    $json = $payload | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($snapPath, $json, [System.Text.UTF8Encoding]::new($false))
    Log-Text "[OK] OptimizerGuard: Đã sao lưu trạng thái gốc ($($regSnaps.Length) Registry, $($svcSnaps.Length) Service) -> $([System.IO.Path]::GetFileName($snapPath))"
    return $snapPath
}

function Restore-OptimizerGuardSnapshot {
    param([Parameter(Mandatory = $true)][string]$SnapshotPath)
    if (-not (Test-Path -LiteralPath $SnapshotPath)) {
        Log-Text "[ERR] Không tìm thấy tệp sao lưu: $SnapshotPath"
        return $false
    }
    if (-not ("DuckUtil.WindowsOptimizerEngine" -as [type])) { return $false }
    try {
        $raw = [System.IO.File]::ReadAllText($SnapshotPath, [System.Text.Encoding]::UTF8)
        $obj = ConvertFrom-Json $raw
        if (-not $obj) { return $false }

        $regRestored = 0
        if ($obj.Registry) {
            $arr = [System.Collections.Generic.List[DuckUtil.RegistrySnapshotEntry]]::new()
            foreach ($r in @($obj.Registry)) {
                $e = [DuckUtil.RegistrySnapshotEntry]::new()
                $e.Hive = [string]$r.Hive
                $e.Path = [string]$r.Path
                $e.Name = [string]$r.Name
                $e.Existed = [bool]$r.Existed
                $e.KeyExisted = [bool]$r.KeyExisted
                $e.Kind = [string]$r.Kind
                $e.ValueData = [string]$r.ValueData
                [void]$arr.Add($e)
            }
            $regRestored = [DuckUtil.WindowsOptimizerEngine]::RestoreRegistrySnapshots($arr.ToArray())
        }

        $svcRestored = 0
        if ($obj.Services) {
            $arrS = [System.Collections.Generic.List[DuckUtil.ServiceSnapshotEntry]]::new()
            foreach ($s in @($obj.Services)) {
                $e = [DuckUtil.ServiceSnapshotEntry]::new()
                $e.Name = [string]$s.Name
                $e.Existed = [bool]$s.Existed
                $e.OriginalStart = [int]$s.OriginalStart
                [void]$arrS.Add($e)
            }
            $svcRestored = [DuckUtil.WindowsOptimizerEngine]::RestoreServiceSnapshots($arrS.ToArray())
        }

        if ($obj.Tasks) {
            foreach ($tk in @($obj.Tasks)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$tk)) {
                    try { & schtasks.exe /Change /TN "$tk" /Enable 2>$null | Out-Null } catch {}
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$obj.PowerSchemeGuid)) {
            try { & powercfg.exe /setactive "$($obj.PowerSchemeGuid)" 2>$null | Out-Null } catch {}
        }

        if ($obj.NeedsExplorerRestart) {
            Restart-ExplorerSoft
        }

        Log-Text "[OK] OptimizerGuard: Đã khôi phục hoàn chỉnh ($regRestored Registry, $svcRestored Service) từ bản lưu $($obj.CreatedAt)."
        return $true
    } catch {
        Log-Text "[ERR] Lỗi khôi phục bản sao lưu: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-SafeBackgroundAppsTweak {
    param([ValidateSet("Apply", "Undo")][string]$Mode = "Apply")
    try {
        $isUndo = ($Mode -eq "Undo")
        $bgPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
        if (-not (Test-Path -LiteralPath $bgPath)) {
            [void](New-Item -Path $bgPath -Force -ErrorAction SilentlyContinue)
        }
        Set-ItemProperty -LiteralPath $bgPath -Name "GlobalUserDisabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        if ($isUndo) {
            Remove-ItemProperty -LiteralPath $bgPath -Name "AppDriverSafeBgFilter" -ErrorAction SilentlyContinue
        } else {
            Set-ItemProperty -LiteralPath $bgPath -Name "AppDriverSafeBgFilter" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        }

        $apPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
        if (Test-Path -LiteralPath $apPath) {
            Remove-ItemProperty -LiteralPath $apPath -Name "LetAppsRunInBackground" -ErrorAction SilentlyContinue
        }

        $oemAndSystemRegex = 'Lenovo|Vantage|Legion|ThinkPad|IdeaPad|ASUS|Armoury|ROG|MyASUS|ATK|Acer|Nitro|Predator|MSI|Dragon|MicroStar|Dell|Alienware|HP|OMEN|Victus|Gigabyte|AORUS|Razer|Logitech|Corsair|SteelSeries|Samsung|LG|Huawei|Xiaomi|Surface|NVIDIA|AMD|Radeon|Intel|Thunderbolt|Realtek|Dolby|Nahimic|DTS|Waves|SoundResearch|Synaptics|ELAN|Wacom|SecHealth|WindowsDefender|WindowsStore|DesktopAppInstaller|WindowsTerminal|ShellExperience|StartMenuExperience|Client\.CBS|LockApp|AAD\.Broker'
        $bloatAppRegex = 'BingNews|BingWeather|BingFinance|BingSports|Solitaire|FeedbackHub|WindowsMaps|ZuneVideo|ZuneMusic|People|GetHelp|Getstarted|Clipchamp|SkypeApp|MixedReality|3DViewer|MicrosoftOfficeHub|Cortana|549981C3F5F10'

        foreach ($sub in @(Get-ChildItem -LiteralPath $bgPath -ErrorAction SilentlyContinue)) {
            $pkgName = [string]$sub.PSChildName
            if ($pkgName -match $oemAndSystemRegex) {
                Set-ItemProperty -LiteralPath $sub.PSPath -Name "Disabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -LiteralPath $sub.PSPath -Name "DisabledByUser" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            } elseif ($pkgName -match $bloatAppRegex) {
                $targetVal = if ($isUndo) { 0 } else { 1 }
                Set-ItemProperty -LiteralPath $sub.PSPath -Name "Disabled" -Value $targetVal -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -LiteralPath $sub.PSPath -Name "DisabledByUser" -Value $targetVal -Type DWord -ErrorAction SilentlyContinue
            }
        }
        return $true
    } catch {
        return $false
    }
}

function Repair-OemPowerAndLegionThermalMode {
    param([switch]$Silent)
    try {
        $bgPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
        if (Test-Path -LiteralPath $bgPath) {
            Set-ItemProperty -LiteralPath $bgPath -Name "GlobalUserDisabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            $oemAndSystemRegex = 'Lenovo|Vantage|Legion|ThinkPad|IdeaPad|ASUS|Armoury|ROG|MyASUS|ATK|Acer|Nitro|Predator|MSI|Dragon|MicroStar|Dell|Alienware|HP|OMEN|Victus|Gigabyte|AORUS|Razer|Logitech|Corsair|SteelSeries|Samsung|LG|Huawei|Xiaomi|Surface|NVIDIA|AMD|Radeon|Intel|Thunderbolt|Realtek|Dolby|Nahimic|DTS|Waves|SoundResearch|Synaptics|ELAN|Wacom|SecHealth|WindowsDefender|WindowsStore|DesktopAppInstaller|WindowsTerminal|ShellExperience|StartMenuExperience|Client\.CBS|LockApp|AAD\.Broker'
            foreach ($sub in @(Get-ChildItem -LiteralPath $bgPath -ErrorAction SilentlyContinue)) {
                if ([string]$sub.PSChildName -match $oemAndSystemRegex) {
                    Set-ItemProperty -LiteralPath $sub.PSPath -Name "Disabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                    Set-ItemProperty -LiteralPath $sub.PSPath -Name "DisabledByUser" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                }
            }
        }
        $apPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
        if (Test-Path -LiteralPath $apPath) {
            Remove-ItemProperty -LiteralPath $apPath -Name "LetAppsRunInBackground" -ErrorAction SilentlyContinue
        }

        $smPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        if (Test-Path -LiteralPath $smPath) {
            Remove-ItemProperty -LiteralPath $smPath -Name "DisableWpbtExecution" -ErrorAction SilentlyContinue
        }

        foreach ($legacyPol in @(
            @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"; Name = "DisableNotificationCenter" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"; Name = "DisableLocation" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching"; Name = "DontPromptForWindowsUpdate" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata"; Name = "PreventDeviceMetadataFromNetwork" }
        )) {
            if (Test-Path -LiteralPath $legacyPol.Path) {
                Remove-ItemProperty -LiteralPath $legacyPol.Path -Name $legacyPol.Name -ErrorAction SilentlyContinue
            }
        }

        $ctrlPath = "HKLM:\SYSTEM\CurrentControlSet\Control"
        if (Test-Path -LiteralPath $ctrlPath) {
            $curSplit = (Get-ItemProperty -LiteralPath $ctrlPath -Name "SvcHostSplitThresholdInKB" -ErrorAction SilentlyContinue).SvcHostSplitThresholdInKB
            if (($curSplit -eq 3670016 -or $curSplit -eq 380000000) -and ("DuckUtil.WindowsOptimizerEngine" -as [type])) {
                $hw = [DuckUtil.WindowsOptimizerEngine]::DetectHardwareProfile()
                if ($hw -and $hw.TotalRamGb -gt 4) {
                    $ramKb = [int]($hw.TotalRamGb * 1048576)
                    Set-ItemProperty -LiteralPath $ctrlPath -Name "SvcHostSplitThresholdInKB" -Value $ramKb -Type DWord -ErrorAction SilentlyContinue
                }
            }
        }

        $curScheme = (& powercfg.exe /getactivescheme 2>$null) -join " "
        if ($curScheme -match 'Ultimate Performance|e9a42b02-d5df-448d-aa00-03f14749eb61') {
            $balGuid = "381b4222-f694-41f0-9685-ff5bb260df2e"
            try { & powercfg.exe /setactive $balGuid 2>$null | Out-Null } catch {}
        }
        $psRoot = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes"
        if (Test-Path -LiteralPath $psRoot) {
            $curOv = (Get-ItemProperty -LiteralPath $psRoot -Name "ActiveOverlayAcPowerScheme" -ErrorAction SilentlyContinue).ActiveOverlayAcPowerScheme
            if ($curOv -eq "961cc777-2547-4f9d-8174-7d86181b8a7a") {
                Set-ItemProperty -LiteralPath $psRoot -Name "ActiveOverlayAcPowerScheme" -Value "00000000-0000-0000-0000-000000000000" -ErrorAction SilentlyContinue
            }
        }

        $coreAutoServices = @("WpnService", "ShellHWDetection", "CDPSvc", "DPS", "FontCache", "iphlpsvc", "PcaSvc", "SysMain", "TrkWks")
        foreach ($sn in $coreAutoServices) {
            $svcReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$sn"
            if (Test-Path -LiteralPath $svcReg) {
                $curSt = (Get-ItemProperty -LiteralPath $svcReg -Name "Start" -ErrorAction SilentlyContinue).Start
                if ($curSt -eq 3 -or $curSt -eq 4) {
                    Set-ItemProperty -LiteralPath $svcReg -Name "Start" -Value 2 -Type DWord -ErrorAction SilentlyContinue
                }
                if ($sn -in @("WpnService", "ShellHWDetection", "SysMain", "PcaSvc")) {
                    try { Start-Service -Name $sn -ErrorAction SilentlyContinue } catch {}
                }
            }
        }
        foreach ($sn in @("HidServ", "MsKeyboardFilter", "DialogBlockingService", "AppVClient", "tzautoupdate")) {
            $svcReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$sn"
            if (Test-Path -LiteralPath $svcReg) {
                $curSt = (Get-ItemProperty -LiteralPath $svcReg -Name "Start" -ErrorAction SilentlyContinue).Start
                if ($curSt -eq 4) {
                    Set-ItemProperty -LiteralPath $svcReg -Name "Start" -Value 3 -Type DWord -ErrorAction SilentlyContinue
                }
                if ($sn -eq "HidServ") {
                    try { Start-Service -Name $sn -ErrorAction SilentlyContinue } catch {}
                }
            }
        }

        $oemPattern = '^(Lenovo|Legion|ImController|IBMPMSVC|LITSSVC|TPHK|LZService|ASUS|Armoury|ROG|Aura|ATK|LightingService|AsHidSrv|AsSysCtrlService|MSI|Micro Star|DragonCenter|Mystic_Light|Acer|Nitro|Predator|PSService|PSAgent|accSvc|QAAdminAgent|Dell|Alienware|AWCC|DPMService|DDV|HP|Omen|Gigabyte|Aorus|GCC|GvBios|Razer|RzAction|NVDisplay|NvContainer|AMD|AmdPpkgSvc|RtkAudio|Dolby|DAX3|Nahimic)'
        foreach ($sv in @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $oemPattern })) {
            $svcReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$($sv.Name)"
            $curSt = (Get-ItemProperty -LiteralPath $svcReg -Name "Start" -ErrorAction SilentlyContinue).Start
            if ($curSt -eq 4) {
                Set-ItemProperty -LiteralPath $svcReg -Name "Start" -Value 2 -Type DWord -ErrorAction SilentlyContinue
            }
            if ($sv.Status -ne 'Running' -and ($curSt -eq 2 -or $sv.Name -match 'LenovoFn|LenovoVantage|Armoury|AsusSystemControl|ATKGFNEX|MSI_Center|NitroSense|PredatorSense|AWCC|HPOmenCap')) {
                try { Start-Service -Name $sv.Name -ErrorAction SilentlyContinue } catch {}
            }
        }

        $hasLegion = (Test-Path -LiteralPath "HKLM:\SOFTWARE\Lenovo\VantageService") -or ($null -ne (Get-Service -Name "LenovoVantageService" -ErrorAction SilentlyContinue))
        if ($hasLegion) {
            try {
                $wmiOther = Get-CimInstance -Namespace "root\WMI" -ClassName "LENOVO_OTHER_METHOD" -ErrorAction SilentlyContinue
                if ($wmiOther) {
                    [void](Invoke-CimMethod -InputObject $wmiOther -MethodName "SetFeatureValue" -Arguments @{ IDs = [int]1048576; value = [int]1 } -ErrorAction SilentlyContinue)
                }
            } catch {}
            foreach ($svcName in @("LenovoFnAndFunctionKeys", "LenovoVantageService")) {
                $sv = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                if ($sv) {
                    try { Set-Service -Name $svcName -StartupType Automatic -ErrorAction SilentlyContinue } catch {}
                    try {
                        if (-not $Silent) {
                            Restart-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                        } elseif ($sv.Status -ne 'Running') {
                            Start-Service -Name $svcName -ErrorAction SilentlyContinue
                        }
                    } catch {}
                }
            }
            if (-not $Silent) {
                Log-Text "[OK] Đã đồng bộ lại dịch vụ phím nóng hãng & bật lại chế độ Custom trong vòng lặp Fn+Q."
            }
        }
    } catch {}
}

function Invoke-OemAndCriticalServiceSelfHeal {
    try {
        $bgUser = (Get-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -ErrorAction SilentlyContinue).GlobalUserDisabled
        $bgPol = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsRunInBackground" -ErrorAction SilentlyContinue).LetAppsRunInBackground
        $curSplit = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "SvcHostSplitThresholdInKB" -ErrorAction SilentlyContinue).SvcHostSplitThresholdInKB
        $curOv = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes" -Name "ActiveOverlayAcPowerScheme" -ErrorAction SilentlyContinue).ActiveOverlayAcPowerScheme
        $sysMainSt = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\SysMain" -Name "Start" -ErrorAction SilentlyContinue).Start
        $kbFiltSt = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\MsKeyboardFilter" -Name "Start" -ErrorAction SilentlyContinue).Start
        $notifPol = (Get-ItemProperty -LiteralPath "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableNotificationCenter" -ErrorAction SilentlyContinue).DisableNotificationCenter
        $drvPol = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -ErrorAction SilentlyContinue).DontPromptForWindowsUpdate

        if ($bgUser -eq 1 -or $bgPol -eq 2 -or $curSplit -eq 3670016 -or $curSplit -eq 380000000 -or $curOv -eq "961cc777-2547-4f9d-8174-7d86181b8a7a" -or $sysMainSt -eq 4 -or $kbFiltSt -eq 4 -or $notifPol -eq 1 -or $drvPol -eq 1) {
            Repair-OemPowerAndLegionThermalMode -Silent
        }
    } catch {}
}

function Restore-AllOptimizerGuardSnapshots {
    param([string[]]$FilterTweakIds = $null)
    if (-not ("DuckUtil.WindowsOptimizerEngine" -as [type])) { return $false }
    $dir = Get-OptimizerBackupDirectory
    if (-not [System.IO.Directory]::Exists($dir)) {
        Repair-OemPowerAndLegionThermalMode
        return $true
    }
    $files = @(Get-ChildItem -LiteralPath $dir -Filter "snapshot_*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    if ($files.Count -eq 0) {
        Repair-OemPowerAndLegionThermalMode
        return $true
    }

    $earliestReg = @{}
    $earliestSvc = @{}
    $allTasks = [System.Collections.Generic.List[string]]::new()
    $needsExplorer = $false

    foreach ($f in $files) {
        try {
            $raw = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
            $obj = ConvertFrom-Json $raw
            if (-not $obj) { continue }
            if ($FilterTweakIds -and $FilterTweakIds.Count -gt 0 -and $obj.TweakIds) {
                $hasMatch = $false
                foreach ($tid in @($obj.TweakIds)) {
                    if ($FilterTweakIds -contains [string]$tid) { $hasMatch = $true; break }
                }
                if (-not $hasMatch) { continue }
            }
            if ($obj.NeedsExplorerRestart) { $needsExplorer = $true }
            if ($obj.Tasks) {
                foreach ($tk in @($obj.Tasks)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$tk) -and -not $allTasks.Contains([string]$tk)) {
                        [void]$allTasks.Add([string]$tk)
                    }
                }
            }
            if ($obj.Registry) {
                foreach ($r in @($obj.Registry)) {
                    $dedup = "$($r.Hive)|$($r.Path)|$($r.Name)"
                    if (-not $earliestReg.ContainsKey($dedup)) {
                        $e = [DuckUtil.RegistrySnapshotEntry]::new()
                        $e.Hive = [string]$r.Hive
                        $e.Path = [string]$r.Path
                        $e.Name = [string]$r.Name
                        $e.Existed = [bool]$r.Existed
                        $e.KeyExisted = [bool]$r.KeyExisted
                        $e.Kind = [string]$r.Kind
                        $e.ValueData = [string]$r.ValueData
                        $earliestReg[$dedup] = $e
                    }
                }
            }
            if ($obj.Services) {
                foreach ($s in @($obj.Services)) {
                    $sn = [string]$s.Name
                    if (-not $earliestSvc.ContainsKey($sn)) {
                        $e = [DuckUtil.ServiceSnapshotEntry]::new()
                        $e.Name = $sn
                        $e.Existed = [bool]$s.Existed
                        $e.OriginalStart = [int]$s.OriginalStart
                        $earliestSvc[$sn] = $e
                    }
                }
            }
        } catch {}
    }

    $regArr = [System.Collections.Generic.List[DuckUtil.RegistrySnapshotEntry]]::new()
    foreach ($v in $earliestReg.Values) { [void]$regArr.Add($v) }
    $regRestored = if ($regArr.Count -gt 0) { [DuckUtil.WindowsOptimizerEngine]::RestoreRegistrySnapshots($regArr.ToArray()) } else { 0 }

    $svcArr = [System.Collections.Generic.List[DuckUtil.ServiceSnapshotEntry]]::new()
    foreach ($v in $earliestSvc.Values) { [void]$svcArr.Add($v) }
    $svcRestored = if ($svcArr.Count -gt 0) { [DuckUtil.WindowsOptimizerEngine]::RestoreServiceSnapshots($svcArr.ToArray()) } else { 0 }

    foreach ($tk in $allTasks) {
        try { & schtasks.exe /Change /TN "$tk" /Enable 2>$null | Out-Null } catch {}
    }

    Repair-OemPowerAndLegionThermalMode

    if ($needsExplorer) {
        Restart-ExplorerSoft
    }

    Log-Text "[OK] OptimizerGuard: Đã khôi phục hoàn chỉnh trạng thái gốc ban đầu ($regRestored Registry, $svcRestored Service, $($allTasks.Count) Task) từ $($files.Count) bản lưu."
    return $true
}

function Restart-ExplorerSoft {
    try {
        Log-Text "[*] Đang khởi động lại nhanh Windows Explorer để áp dụng thay đổi giao diện..."
        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 700
        if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
            Start-Process "explorer.exe"
        }
    } catch {}
}

function Invoke-OptimizerSpecialAction {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [ValidateSet("Apply", "Undo")][string]$Mode = "Apply",
        [string]$ComboValue = ""
    )
    $isUndo = ($Mode -eq "Undo")
    switch ($Action) {
        "RestorePoint" {
            if ($isUndo) { return $true }
            return (New-OptimizerRestorePoint)
        }
        "DeleteTempFiles" {
            if ($isUndo) { return $true }
            $removed = 0
            foreach ($dir in @($env:TEMP, (Join-Path $env:SystemRoot "Temp"))) {
                if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) { continue }
                Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                        $removed++
                    } catch {}
                }
            }
            Log-Text "[OK] Đã dọn $removed mục tệp rác tạm."
            return $true
        }
        "DiskCleanup" {
            if ($isUndo) { return $true }
            try {
                Start-Process "cleanmgr.exe" -ArgumentList "/d $($env:SystemDrive) /VERYLOWDISK" -WindowStyle Hidden -ErrorAction Stop
                Log-Text "[OK] Đã khởi chạy Disk Cleanup dọn ổ $($env:SystemDrive)."
                return $true
            } catch {
                Log-Text "[WARN] Không thể chạy cleanmgr.exe: $($_.Exception.Message)"
                return $false
            }
        }
        "Hibernation" {
            $arg = if ($isUndo) { "/hibernate on" } else { "/hibernate off" }
            $code = Run-CliStream "powercfg.exe" $arg -IsolateStdin -AllowCancel
            return ($code -eq 0)
        }
        "SafeDisableBgApps" {
            return (Invoke-SafeBackgroundAppsTweak -Mode $Mode)
        }
        "UltimatePerf" {
            if ($isUndo) {
                $curScheme = (& powercfg.exe /getactivescheme 2>$null) -join " "
                if ($curScheme -match 'Ultimate Performance|e9a42b02-d5df-448d-aa00-03f14749eb61') {
                    $balGuid = "381b4222-f694-41f0-9685-ff5bb260df2e"
                    [void](Run-CliStream "powercfg.exe" "/setactive $balGuid" -IsolateStdin -AllowCancel)
                }
                Repair-OemPowerAndLegionThermalMode -Silent
                return $true
            }
            $listOut = (& powercfg.exe /list 2>$null) -join "`n"
            $ultGuid = ""
            if ($listOut -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*\([^)]*Ultimate Performance[^)]*\)') {
                $ultGuid = $Matches[1]
            } else {
                $dupOut = (& powercfg.exe -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null) -join "`n"
                if ($dupOut -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                    $ultGuid = $Matches[1]
                }
            }
            if ([string]::IsNullOrWhiteSpace($ultGuid)) {
                Log-Text "[WARN] Không tìm thấy hoặc không hỗ trợ gói nguồn Ultimate Performance trên thiết bị này."
                return $false
            }
            $c = Run-CliStream "powercfg.exe" "/setactive $ultGuid" -IsolateStdin -AllowCancel
            return ($c -eq 0)
        }
        "ReservedStorage" {
            $stateArg = if ($isUndo) { "Enabled" } else { "Disabled" }
            $code = Run-CliStream "dism.exe" "/Online /Set-ReservedStorageState /State:$stateArg" -IsolateStdin -AllowCancel
            return ($code -eq 0)
        }
        "DnsApply" {
            $dnsChoice = if ($isUndo) { "Mặc định (DHCP)" } else { $ComboValue }
            $servers = @()
            switch -Regex ($dnsChoice) {
                'Cloudflare|1\.1\.1\.1' { $servers = @("1.1.1.1", "1.0.0.1") }
                'AdGuard|94\.140'       { $servers = @("94.140.14.14", "94.140.15.15") }
                'Google|8\.8\.8\.8'     { $servers = @("8.8.8.8", "8.8.4.4") }
                'Quad9|9\.9\.9\.9'      { $servers = @("9.9.9.9", "149.112.112.112") }
                default                 { $servers = @() }
            }
            try {
                $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
                if ($adapters.Count -eq 0) {
                    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Loopback|Virtual' })
                }
                foreach ($ad in $adapters) {
                    if ($servers.Count -gt 0) {
                        Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ServerAddresses $servers -ErrorAction SilentlyContinue
                    } else {
                        Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
                    }
                }
                & ipconfig.exe /flushdns 2>$null | Out-Null
                Log-Text "[OK] Đã cập nhật DNS ($dnsChoice) và làm mới DNS cache."
                return $true
            } catch {
                Log-Text "[ERR] Lỗi đổi DNS: $($_.Exception.Message)"
                return $false
            }
        }
        "NagleDisable" {
            try {
                $ifRoot = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
                if (Test-Path -LiteralPath $ifRoot) {
                    foreach ($sub in Get-ChildItem -LiteralPath $ifRoot -ErrorAction SilentlyContinue) {
                        $props = Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue
                        if (-not $props) { continue }
                        $dhIp = [string]$props.DhcpIPAddress
                        $stIp = if ($props.IPAddress -is [array] -and $props.IPAddress.Count -gt 0) { [string]$props.IPAddress[0] } else { [string]$props.IPAddress }
                        $hasIp = (-not [string]::IsNullOrWhiteSpace($dhIp) -and $dhIp -ne "0.0.0.0") -or (-not [string]::IsNullOrWhiteSpace($stIp) -and $stIp -ne "0.0.0.0")
                        if (-not $hasIp) { continue }
                        if ($isUndo) {
                            Remove-ItemProperty -LiteralPath $sub.PSPath -Name "TcpAckFrequency" -ErrorAction SilentlyContinue
                            Remove-ItemProperty -LiteralPath $sub.PSPath -Name "TCPNoDelay" -ErrorAction SilentlyContinue
                        } else {
                            Set-ItemProperty -LiteralPath $sub.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -ErrorAction SilentlyContinue
                            Set-ItemProperty -LiteralPath $sub.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -ErrorAction SilentlyContinue
                        }
                    }
                }
                return $true
            } catch {
                return $false
            }
        }
        "RemoveWidgets" {
            return $true
        }
        "RemoveOneDrive" {
            if ($isUndo) {
                Log-Text "[INFO] Đã bỏ chính sách khóa OneDrive (có thể cài lại OneDrive từ tab Ứng dụng nếu cần)."
                return $true
            }
            try {
                Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
                foreach ($odSetup in @(
                    (Join-Path $env:SystemRoot "System32\OneDriveSetup.exe"),
                    (Join-Path $env:SystemRoot "SysWOW64\OneDriveSetup.exe")
                )) {
                    if (Test-Path -LiteralPath $odSetup) {
                        [void](Run-CliStream $odSetup "/uninstall" -IsolateStdin -AllowCancel)
                        break
                    }
                }
                return $true
            } catch {
                return $false
            }
        }
        "RemoveEdge" {
            if ($isUndo) {
                Log-Text "[INFO] Nếu cần cài lại Edge, bạn có thể cài trực tiếp ở tab Ứng dụng."
                return $true
            }
            try {
                Stop-Process -Name "msedge" -Force -ErrorAction SilentlyContinue
                foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
                    if ([string]::IsNullOrWhiteSpace($base)) { continue }
                    $instRoot = Join-Path $base "Microsoft\Edge\Application"
                    if (-not (Test-Path -LiteralPath $instRoot)) { continue }
                    $setupExe = Get-ChildItem -LiteralPath $instRoot -Filter "setup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($setupExe) {
                        [void](Run-CliStream $setupExe.FullName "--uninstall --system-level --verbose-logging --force-uninstall" -IsolateStdin -AllowCancel)
                        return $true
                    }
                }
                Log-Text "[WARN] Không tìm thấy trình gỡ cài đặt Microsoft Edge trên máy."
                return $false
            } catch {
                return $false
            }
        }
        "AdobeBlock" {
            $hostsPath = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
            $markerStart = "# AppDriver-AdobeBlock-Start"
            $markerEnd = "# AppDriver-AdobeBlock-End"
            try {
                $existing = if (Test-Path -LiteralPath $hostsPath) { [System.IO.File]::ReadAllText($hostsPath, [System.Text.Encoding]::UTF8) } else { "" }
                $cleaned = [regex]::Replace($existing, "(?s)\r?\n?$([regex]::Escape($markerStart)).*?$([regex]::Escape($markerEnd))\r?\n?", "")
                if ($isUndo) {
                    [System.IO.File]::WriteAllText($hostsPath, $cleaned.TrimEnd() + "`r`n", [System.Text.Encoding]::UTF8)
                    return $true
                }
                $domains = @(
                    "0.0.0.0 ic.adobe.io",
                    "0.0.0.0 cc-api-data.adobe.io",
                    "0.0.0.0 p13n.adobe.io",
                    "0.0.0.0 genuine.adobe.com",
                    "0.0.0.0 prod.adobegenuine.com",
                    "0.0.0.0 lmlicenses.wip4.adobe.com",
                    "0.0.0.0 lm.licenses.adobe.com",
                    "0.0.0.0 na1r.services.adobe.com",
                    "0.0.0.0 hlrcv.stage.adobe.com",
                    "0.0.0.0 practivate.adobe.com"
                )
                $block = "`r`n$markerStart`r`n" + ($domains -join "`r`n") + "`r`n$markerEnd`r`n"
                [System.IO.File]::WriteAllText($hostsPath, $cleaned.TrimEnd() + $block, [System.Text.Encoding]::UTF8)
                return $true
            } catch {
                Log-Text "[ERR] Không thể ghi file hosts: $($_.Exception.Message)"
                return $false
            }
        }
        "DisableBitLocker" {
            if ($isUndo) { return $true }
            try {
                $code = Run-CliStream "manage-bde.exe" "-off $($env:SystemDrive)" -IsolateStdin -AllowCancel
                return ($code -eq 0 -or $code -eq -2147024891)
            } catch {
                return $false
            }
        }
        "PauseWindowsUpdate35d" {
            $uxPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
            try {
                if (-not (Test-Path -LiteralPath $uxPath)) { New-Item -Path $uxPath -Force | Out-Null }
                if ($isUndo) {
                    foreach ($vn in @("PauseFeatureUpdatesStartTime","PauseFeatureUpdatesEndTime","PauseQualityUpdatesStartTime","PauseQualityUpdatesEndTime","PauseUpdatesExpiryTime")) {
                        Remove-ItemProperty -LiteralPath $uxPath -Name $vn -ErrorAction SilentlyContinue
                    }
                    return $true
                }
                $nowIso = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                $endIso = (Get-Date).AddDays(35).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                Set-ItemProperty -LiteralPath $uxPath -Name "PauseFeatureUpdatesStartTime" -Value $nowIso -Type String
                Set-ItemProperty -LiteralPath $uxPath -Name "PauseFeatureUpdatesEndTime" -Value $endIso -Type String
                Set-ItemProperty -LiteralPath $uxPath -Name "PauseQualityUpdatesStartTime" -Value $nowIso -Type String
                Set-ItemProperty -LiteralPath $uxPath -Name "PauseQualityUpdatesEndTime" -Value $endIso -Type String
                Set-ItemProperty -LiteralPath $uxPath -Name "PauseUpdatesExpiryTime" -Value $endIso -Type String
                return $true
            } catch {
                return $false
            }
        }
        "DisableWindowsUpdateAll" {
            $uxPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
            try {
                if (-not (Test-Path -LiteralPath $uxPath)) { New-Item -Path $uxPath -Force | Out-Null }
                if ($isUndo) {
                    foreach ($vn in @("FlightSettingsMaxPauseDays","PauseFeatureUpdatesStartTime","PauseFeatureUpdatesEndTime","PauseQualityUpdatesStartTime","PauseQualityUpdatesEndTime","PauseUpdatesExpiryTime")) {
                        Remove-ItemProperty -LiteralPath $uxPath -Name $vn -ErrorAction SilentlyContinue
                    }
                    return $true
                }
                $nowIso = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                $endIso = "2099-12-31T23:59:59Z"
                Set-ItemProperty -LiteralPath $uxPath -Name "FlightSettingsMaxPauseDays" -Value 36500 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -LiteralPath $uxPath -Name "PauseFeatureUpdatesStartTime" -Value $nowIso -Type String
                Set-ItemProperty -LiteralPath $uxPath -Name "PauseFeatureUpdatesEndTime" -Value $endIso -Type String
                Set-ItemProperty -LiteralPath $uxPath -Name "PauseQualityUpdatesStartTime" -Value $nowIso -Type String
                Set-ItemProperty -LiteralPath $uxPath -Name "PauseQualityUpdatesEndTime" -Value $endIso -Type String
                Set-ItemProperty -LiteralPath $uxPath -Name "PauseUpdatesExpiryTime" -Value $endIso -Type String
                return $true
            } catch {
                return $false
            }
        }
        "ResetWindowsUpdateDefault" {
            try {
                $wuPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
                if (Test-Path -LiteralPath $wuPol) {
                    Remove-Item -LiteralPath $wuPol -Recurse -Force -ErrorAction SilentlyContinue
                }
                $uxPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
                if (Test-Path -LiteralPath $uxPath) {
                    foreach ($vn in @("FlightSettingsMaxPauseDays","PauseFeatureUpdatesStartTime","PauseFeatureUpdatesEndTime","PauseQualityUpdatesStartTime","PauseQualityUpdatesEndTime","PauseUpdatesExpiryTime")) {
                        Remove-ItemProperty -LiteralPath $uxPath -Name $vn -ErrorAction SilentlyContinue
                    }
                }
                return $true
            } catch {
                return $false
            }
        }
    }
    return $true
}

function Invoke-OptimizerBatch {
    param(
        [Parameter(Mandatory = $true)]$Tweaks,
        [ValidateSet("Apply", "Undo")][string]$Mode = "Apply",
        [hashtable]$ComboSelections = @{},
        $HardwareProfile = $null,
        [scriptblock]$ProgressCallback = $null
    )
    $tweakList = @($Tweaks)
    if ($tweakList.Count -eq 0) {
        return [PSCustomObject]@{ Applied = 0; Failed = 0; NeedsExplorerRestart = $false; NeedsReboot = $false; SnapshotPath = "" }
    }

    $snapPath = Save-OptimizerGuardSnapshot -Tweaks $tweakList -HardwareProfile $HardwareProfile

    $applied = 0
    $failed = 0
    $needsExplorer = $false
    $needsReboot = $false
    $total = $tweakList.Count
    $idx = 0

    foreach ($tw in $tweakList) {
        if ($script:cancelRequested -or $script:isWindowClosing) { break }
        $idx++
        if ($ProgressCallback) {
            try { & $ProgressCallback $idx $total ([string]$tw.Name) } catch {}
        }

        $ok = $true
        $isUndo = ($Mode -eq "Undo")

        $regSpecs = ConvertTo-RegTweakSpecs @($tw)
        if ($regSpecs.Length -gt 0 -and ("DuckUtil.WindowsOptimizerEngine" -as [type])) {
            $regDone = [DuckUtil.WindowsOptimizerEngine]::ApplyRegistrySpecs($regSpecs, $isUndo)
            if ($regDone -lt $regSpecs.Length) { $ok = $false }
        }

        $svcSpecs = ConvertTo-ServiceTweakSpecs @($tw)
        if ($svcSpecs.Length -gt 0 -and ("DuckUtil.WindowsOptimizerEngine" -as [type])) {
            [void][DuckUtil.WindowsOptimizerEngine]::ApplyServiceSpecs($svcSpecs, $isUndo)
        }

        if ($tw.Tasks) {
            foreach ($tk in @($tw.Tasks)) {
                if ([string]::IsNullOrWhiteSpace([string]$tk)) { continue }
                try {
                    $taskFlag = if ($isUndo) { "/Enable" } else { "/Disable" }
                    & schtasks.exe /Change /TN "$tk" $taskFlag 2>$null | Out-Null
                } catch {}
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$tw.Action)) {
            $comboVal = if ($ComboSelections -and $ComboSelections.ContainsKey([string]$tw.Id)) { [string]$ComboSelections[[string]$tw.Id] } else { "" }
            $actOk = Invoke-OptimizerSpecialAction -Action ([string]$tw.Action) -Mode $Mode -ComboValue $comboVal
            if (-not $actOk) { $ok = $false }
        }

        if ($ok) {
            $applied++
            if ($tw.NeedsExplorerRestart) { $needsExplorer = $true }
            if ($tw.NeedsReboot) { $needsReboot = $true }
            $actLabel = if ($isUndo) { "Đã hoàn tác" } else { "Đã áp dụng" }
            Log-Text "   [OK] ${actLabel}: $($tw.Name)"
        } else {
            $failed++
            Log-Text "   [ERR] Không thể xử lý: $($tw.Name)"
        }
    }

    if ($needsExplorer -and -not $script:cancelRequested -and -not $script:isWindowClosing) {
        Restart-ExplorerSoft
    }

    if ($needsReboot) {
        Log-Text "[WARN] Một số tùy chỉnh yêu cầu khởi động lại Windows để có hiệu lực hoàn toàn."
    }

    return [PSCustomObject]@{
        Applied              = $applied
        Failed               = $failed
        NeedsExplorerRestart = $needsExplorer
        NeedsReboot          = $needsReboot
        SnapshotPath         = $snapPath
    }
}
