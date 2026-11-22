function Get-StartupBackupDirectory {
    return (Join-Path $env:LOCALAPPDATA "AppDriver\StartupBackups")
}

function Get-StartupBackupsList {
    $dir = Get-StartupBackupDirectory
    if (-not [System.IO.Directory]::Exists($dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -Filter "batch_*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
}

function Save-StartupGuardBatchBackup {
    param([Parameter(Mandatory = $true)]$Entries)
    $entryArr = @($Entries | Where-Object { $_ -and $_.CanDelete })
    if ($entryArr.Count -eq 0) { return "" }

    $dir = Get-StartupBackupDirectory
    if (-not [System.IO.Directory]::Exists($dir)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $entryArr) {
        $apB64 = ""
        try {
            $apBytes = [DuckUtil.StartupManagerEngine]::ReadStartupApprovedBytes($e)
            if ($apBytes -and $apBytes.Length -gt 0) {
                $apB64 = [Convert]::ToBase64String($apBytes)
            }
        } catch {}

        $fileB64 = ""
        if (($e.SourceKind -eq "FolderUser" -or $e.SourceKind -eq "FolderAll") -and
            -not [string]::IsNullOrWhiteSpace([string]$e.FolderFilePath) -and
            (Test-Path -LiteralPath $e.FolderFilePath)) {
            try {
                $rawBytes = [System.IO.File]::ReadAllBytes($e.FolderFilePath)
                $fileB64 = [Convert]::ToBase64String($rawBytes)
            } catch {}
        }

        $taskXml = ""
        if ($e.SourceKind -eq "Task" -and -not [string]::IsNullOrWhiteSpace([string]$e.ScheduledTaskPath)) {
            try {
                $taskXml = [DuckUtil.StartupManagerEngine]::GetScheduledTaskXml([string]$e.ScheduledTaskPath)
            } catch {}
        }

        $svcMeta = $null
        if ($e.SourceKind -eq "Service" -and -not [string]::IsNullOrWhiteSpace([string]$e.ServiceName)) {
            try {
                $svcReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$($e.ServiceName)"
                if (Test-Path -LiteralPath $svcReg) {
                    $sp = Get-ItemProperty -LiteralPath $svcReg -ErrorAction SilentlyContinue
                    if ($sp) {
                        $svcMeta = [PSCustomObject]@{
                            ServiceName      = [string]$e.ServiceName
                            DisplayName      = [string]$sp.DisplayName
                            ImagePath        = [string]$sp.ImagePath
                            Description      = [string]$sp.Description
                            ObjectName       = [string]$sp.ObjectName
                            Start            = if ($null -ne $sp.Start) { [int]$sp.Start } else { 3 }
                            Type             = if ($null -ne $sp.Type) { [int]$sp.Type } else { 16 }
                            ErrorControl     = if ($null -ne $sp.ErrorControl) { [int]$sp.ErrorControl } else { 1 }
                            DelayedAutostart = if ($null -ne $sp.DelayedAutostart) { [int]$sp.DelayedAutostart } else { 0 }
                        }
                    }
                }
            } catch {}
        }

        [void]$items.Add([PSCustomObject]@{
            Id                = [string]$e.Id
            Name              = [string]$e.Name
            DisplayName       = [string]$e.DisplayName
            SourceKind        = [string]$e.SourceKind
            RegistryHive      = [string]$e.RegistryHive
            RegistryPath      = [string]$e.RegistryPath
            RegistryValueName = [string]$e.RegistryValueName
            RawCommand        = [string]$e.RawCommand
            ApprovedHive      = [string]$e.ApprovedHive
            ApprovedPath      = [string]$e.ApprovedPath
            ApprovedValueName = [string]$e.ApprovedValueName
            ApprovedBase64    = $apB64
            FolderFilePath    = [string]$e.FolderFilePath
            FileContentBase64 = $fileB64
            ScheduledTaskPath = [string]$e.ScheduledTaskPath
            ScheduledTaskXml  = $taskXml
            ServiceMeta       = $svcMeta
        })
    }

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $uid = [Guid]::NewGuid().ToString("N").Substring(0, 8)
    $path = Join-Path $dir "batch_${stamp}_${uid}.json"

    $payload = [PSCustomObject]@{
        CreatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Count     = $items.Count
        Items     = @($items)
    }

    $json = $payload | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
    Log-Text "[OK] StartupGuard: Đã sao lưu lô $($items.Count) mục khởi chạy -> $([System.IO.Path]::GetFileName($path))"
    return $path
}

function Restore-LastStartupGuardBatch {
    $files = @(Get-StartupBackupsList)
    if ($files.Count -eq 0) {
        return [PSCustomObject]@{ Success = $false; Restored = 0; Failed = 0; Message = "Không có bản sao lưu mục đã xóa nào." }
    }
    $latest = $files[0]
    $restored = 0
    $failed = 0

    try {
        $raw = [System.IO.File]::ReadAllText($latest.FullName, [System.Text.Encoding]::UTF8)
        $obj = ConvertFrom-Json $raw
        if (-not $obj -or -not $obj.Items) {
            return [PSCustomObject]@{ Success = $false; Restored = 0; Failed = 1; Message = "Tệp sao lưu không hợp lệ." }
        }

        foreach ($it in @($obj.Items)) {
            $ok = $false
            $sk = [string]$it.SourceKind
            if ($sk -in @("RegUser", "RegUser32", "RegSystem", "RegWow32", "RegRunOnce", "RegPolicy")) {
                try {
                    $hiveEnum = if ($it.RegistryHive -eq "HKCU") { [Microsoft.Win32.RegistryHive]::CurrentUser } else { [Microsoft.Win32.RegistryHive]::LocalMachine }
                    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hiveEnum, [Microsoft.Win32.RegistryView]::Registry64)
                    try {
                        $subKey = $baseKey.CreateSubKey([string]$it.RegistryPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
                        if ($subKey) {
                            try {
                                $subKey.SetValue([string]$it.RegistryValueName, [string]$it.RawCommand, [Microsoft.Win32.RegistryValueKind]::String)
                                $ok = $true
                            } finally { $subKey.Dispose() }
                        }
                    } finally { $baseKey.Dispose() }

                    if ($ok -and -not [string]::IsNullOrWhiteSpace([string]$it.ApprovedBase64)) {
                        $apBytes = [Convert]::FromBase64String([string]$it.ApprovedBase64)
                        [void][DuckUtil.StartupManagerEngine]::WriteStartupApprovedBytes([string]$it.ApprovedHive, [string]$it.ApprovedPath, [string]$it.ApprovedValueName, $apBytes)
                    }
                } catch {
                    Log-Text "[WARN] Không thể khôi phục mục Registry '$($it.DisplayName)': $($_.Exception.Message)"
                }
            } elseif ($sk -eq "OrphanApproved") {
                try {
                    if (-not [string]::IsNullOrWhiteSpace([string]$it.ApprovedBase64)) {
                        $apBytes = [Convert]::FromBase64String([string]$it.ApprovedBase64)
                        $ok = [DuckUtil.StartupManagerEngine]::WriteStartupApprovedBytes([string]$it.ApprovedHive, [string]$it.ApprovedPath, [string]$it.ApprovedValueName, $apBytes)
                    }
                } catch {
                    Log-Text "[WARN] Không thể khôi phục khóa StartupApproved '$($it.DisplayName)': $($_.Exception.Message)"
                }
            } elseif ($sk -eq "FolderUser" -or $sk -eq "FolderAll") {
                try {
                    if (-not [string]::IsNullOrWhiteSpace([string]$it.FolderFilePath) -and -not [string]::IsNullOrWhiteSpace([string]$it.FileContentBase64)) {
                        $parent = Split-Path -Path $it.FolderFilePath -Parent
                        if (-not [System.IO.Directory]::Exists($parent)) {
                            [void][System.IO.Directory]::CreateDirectory($parent)
                        }
                        $bytes = [Convert]::FromBase64String([string]$it.FileContentBase64)
                        [System.IO.File]::WriteAllBytes([string]$it.FolderFilePath, $bytes)
                        $ok = $true
                        if (-not [string]::IsNullOrWhiteSpace([string]$it.ApprovedBase64)) {
                            $apBytes = [Convert]::FromBase64String([string]$it.ApprovedBase64)
                            [void][DuckUtil.StartupManagerEngine]::WriteStartupApprovedBytes([string]$it.ApprovedHive, [string]$it.ApprovedPath, [string]$it.ApprovedValueName, $apBytes)
                        }
                    }
                } catch {
                    Log-Text "[WARN] Không thể khôi phục tệp Startup '$($it.DisplayName)': $($_.Exception.Message)"
                }
            } elseif ($sk -eq "Task") {
                try {
                    if (-not [string]::IsNullOrWhiteSpace([string]$it.ScheduledTaskXml)) {
                        $regRes = [DuckUtil.StartupManagerEngine]::RegisterScheduledTaskFromXml([string]$it.ScheduledTaskPath, [string]$it.ScheduledTaskXml)
                        if ($regRes.Success) {
                            $ok = $true
                        } else {
                            Log-Text "[WARN] Không thể khôi phục tác vụ '$($it.DisplayName)' (có thể yêu cầu mật khẩu tài khoản TASK_LOGON_PASSWORD): $($regRes.Message)"
                        }
                    }
                } catch {
                    Log-Text "[WARN] Lỗi khôi phục tác vụ '$($it.DisplayName)': $($_.Exception.Message)"
                }
            } elseif ($sk -eq "Service") {
                try {
                    $sm = $it.ServiceMeta
                    if ($sm -and -not [string]::IsNullOrWhiteSpace([string]$sm.ServiceName)) {
                        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
                        try {
                            $subKey = $baseKey.CreateSubKey("SYSTEM\CurrentControlSet\Services\$($sm.ServiceName)", [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
                            if ($subKey) {
                                try {
                                    if ($sm.DisplayName) { $subKey.SetValue("DisplayName", [string]$sm.DisplayName, [Microsoft.Win32.RegistryValueKind]::String) }
                                    if ($sm.ImagePath)   { $subKey.SetValue("ImagePath", [string]$sm.ImagePath, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
                                    if ($sm.Description) { $subKey.SetValue("Description", [string]$sm.Description, [Microsoft.Win32.RegistryValueKind]::String) }
                                    if ($sm.ObjectName)  { $subKey.SetValue("ObjectName", [string]$sm.ObjectName, [Microsoft.Win32.RegistryValueKind]::String) }
                                    $subKey.SetValue("Start", [int]$sm.Start, [Microsoft.Win32.RegistryValueKind]::DWord)
                                    $subKey.SetValue("Type", [int]$sm.Type, [Microsoft.Win32.RegistryValueKind]::DWord)
                                    $subKey.SetValue("ErrorControl", [int]$sm.ErrorControl, [Microsoft.Win32.RegistryValueKind]::DWord)
                                    if ([int]$sm.DelayedAutostart -eq 1) {
                                        $subKey.SetValue("DelayedAutostart", 1, [Microsoft.Win32.RegistryValueKind]::DWord)
                                    }
                                    $ok = $true
                                } finally { $subKey.Dispose() }
                            }
                        } finally { $baseKey.Dispose() }
                    }
                } catch {
                    Log-Text "[WARN] Không thể khôi phục dịch vụ '$($it.DisplayName)': $($_.Exception.Message)"
                }
            }

            if ($ok) { $restored++ } else { $failed++ }
        }

        $restoredDir = Join-Path (Get-StartupBackupDirectory) "Restored"
        if (-not [System.IO.Directory]::Exists($restoredDir)) {
            [void][System.IO.Directory]::CreateDirectory($restoredDir)
        }
        $destFile = Join-Path $restoredDir $latest.Name
        try {
            if (Test-Path -LiteralPath $destFile) { Remove-Item -LiteralPath $destFile -Force -ErrorAction SilentlyContinue }
            Move-Item -LiteralPath $latest.FullName -Destination $destFile -Force -ErrorAction SilentlyContinue
        } catch {}

        Log-Text "[OK] StartupGuard: Đã khôi phục $restored mục khởi chạy từ bản lưu $($obj.CreatedAt) ($failed lỗi)."
        return [PSCustomObject]@{ Success = ($restored -gt 0); Restored = $restored; Failed = $failed; Message = "Đã khôi phục $restored mục ($failed lỗi)." }
    } catch {
        Log-Text "[ERR] Lỗi khôi phục StartupGuard: $($_.Exception.Message)"
        return [PSCustomObject]@{ Success = $false; Restored = $restored; Failed = ($failed + 1); Message = $_.Exception.Message }
    }
}

function Get-StartupSourceLabel {
    param([string]$SourceKind)
    switch ($SourceKind) {
        "RegUser"        { return "Registry" }
        "RegUser32"      { return "Registry" }
        "RegSystem"      { return "Registry" }
        "RegWow32"       { return "Registry" }
        "RegRunOnce"     { return "RunOnce" }
        "RegPolicy"      { return "Policy" }
        "FolderUser"     { return "Thư mục" }
        "FolderAll"      { return "Thư mục" }
        "Store"          { return "Store" }
        "Task"           { return "Task" }
        "Service"        { return "Dịch vụ" }
        "OrphanApproved" { return "Rác Reg" }
        default          { return "Khác" }
    }
}

function Get-StartupSourceDetail {
    param([string]$SourceKind, [string]$TriggerInfo = "")
    if (-not [string]::IsNullOrWhiteSpace($TriggerInfo)) {
        return $TriggerInfo
    }
    switch ($SourceKind) {
        "RegUser"        { return "Registry User (HKCU\Run)" }
        "RegUser32"      { return "Registry User 32-bit (HKCU\WOW6432Node\Run)" }
        "RegSystem"      { return "Registry System (HKLM\Run)" }
        "RegWow32"       { return "Registry System 32-bit (WOW6432Node\Run)" }
        "RegRunOnce"     { return "Registry RunOnce (Chạy 1 lần)" }
        "RegPolicy"      { return "Group Policy (Policies\Explorer\Run)" }
        "FolderUser"     { return "Thư mục Startup (User)" }
        "FolderAll"      { return "Thư mục Startup (All Users)" }
        "Store"          { return "Ứng dụng Microsoft Store (MSIX/UWP)" }
        "Task"           { return "Task Scheduler (@Logon / @Boot / @Unlock)" }
        "Service"        { return "Dịch vụ Windows chạy nền (Auto-Start)" }
        "OrphanApproved" { return "Khóa rác StartupApproved" }
        default          { return "Khởi chạy Windows" }
    }
}

function Get-StartupImpactLabel {
    param([string]$ImpactLevel)
    switch ($ImpactLevel) {
        "High"   { return "Nặng" }
        "Medium" { return "Trung bình" }
        default  { return "Nhẹ" }
    }
}

function Open-StartupEntryLocation {
    param($Entry)
    if (-not $Entry) { return }
    if ($Entry.SourceKind -eq "OrphanApproved") {
        Open-StartupEntryRegistry -Entry $Entry
        return
    }
    try {
        $candidates = @(
            [string]$Entry.SecondaryTargetPath,
            [string]$Entry.ResolvedExePath,
            [string]$Entry.FolderFilePath
        )
        $target = ""
        foreach ($c in $candidates) {
            if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath $c)) {
                $target = $c
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($target) -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ResolvedExePath)) {
            $parentDir = Split-Path -Path ([string]$Entry.ResolvedExePath) -Parent -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($parentDir) -and (Test-Path -LiteralPath $parentDir -PathType Container)) {
                $target = $parentDir
            }
        }
        if ([string]::IsNullOrWhiteSpace($target)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$Entry.RegistryPath) -or $Entry.SourceKind -eq "Store" -or $Entry.SourceKind -eq "Service") {
                Open-StartupEntryRegistry -Entry $Entry
                return
            }
            Log-Text "[WARN] Không tìm thấy đường dẫn tệp trên ổ đĩa để mở."
            return
        }
        if (Test-Path -LiteralPath $target -PathType Container) {
            Start-Process "explorer.exe" -ArgumentList "`"$target`""
        } else {
            Start-Process "explorer.exe" -ArgumentList "/select,`"$target`""
        }
    } catch {
        Log-Text "[ERR] Không thể mở thư mục tệp: $($_.Exception.Message)"
    }
}

function Open-StartupEntryRegistry {
    param($Entry)
    if (-not $Entry) { return }
    $regFull = ""
    if (-not [string]::IsNullOrWhiteSpace([string]$Entry.RegistryPath)) {
        $rootName = if ($Entry.RegistryHive -eq "HKCU") { "HKEY_CURRENT_USER" } else { "HKEY_LOCAL_MACHINE" }
        $regFull = "Computer\$rootName\$($Entry.RegistryPath)"
    } elseif ($Entry.SourceKind -eq "OrphanApproved" -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ApprovedPath)) {
        $rootName = if ($Entry.ApprovedHive -eq "HKCU") { "HKEY_CURRENT_USER" } else { "HKEY_LOCAL_MACHINE" }
        $regFull = "Computer\$rootName\$($Entry.ApprovedPath)"
    } elseif ($Entry.SourceKind -eq "Store" -and -not [string]::IsNullOrWhiteSpace([string]$Entry.PackageFamilyName)) {
        $regFull = "Computer\HKEY_CURRENT_USER\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$($Entry.PackageFamilyName)\$($Entry.TaskId)"
    } elseif ($Entry.SourceKind -eq "Service" -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ServiceName)) {
        $regFull = "Computer\HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$($Entry.ServiceName)"
    }
    if ([string]::IsNullOrWhiteSpace($regFull)) { return }
    try {
        $rePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit"
        if (-not (Test-Path -LiteralPath $rePath)) { [void](New-Item -Path $rePath -Force) }
        Set-ItemProperty -LiteralPath $rePath -Name "LastKey" -Value $regFull -Type String -ErrorAction SilentlyContinue
        Start-Process "regedit.exe" -ArgumentList "-m"
    } catch {
        Log-Text "[ERR] Không thể mở Registry Editor: $($_.Exception.Message)"
    }
}
