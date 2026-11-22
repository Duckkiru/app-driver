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
            if ($sk -eq "RegUser" -or $sk -eq "RegSystem" -or $sk -eq "RegWow32") {
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
        "RegUser"    { return "Registry" }
        "RegSystem"  { return "Registry" }
        "RegWow32"   { return "Registry" }
        "FolderUser" { return "Thư mục" }
        "FolderAll"  { return "Thư mục" }
        "Store"      { return "Store" }
        "Task"       { return "Task" }
        default      { return "Khác" }
    }
}

function Get-StartupSourceDetail {
    param([string]$SourceKind)
    switch ($SourceKind) {
        "RegUser"    { return "Registry User (HKCU\Run)" }
        "RegSystem"  { return "Registry System (HKLM\Run)" }
        "RegWow32"   { return "Registry System 32-bit (WOW6432Node\Run)" }
        "FolderUser" { return "Thư mục Startup (User)" }
        "FolderAll"  { return "Thư mục Startup (All Users)" }
        "Store"      { return "Ứng dụng Microsoft Store (UWP)" }
        "Task"       { return "Task Scheduler (@Logon / @Boot)" }
        default      { return "Khởi chạy Windows" }
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
    try {
        $target = [string]$Entry.ResolvedExePath
        if ([string]::IsNullOrWhiteSpace($target) -or (-not (Test-Path -LiteralPath $target))) {
            $target = [string]$Entry.FolderFilePath
        }
        if ([string]::IsNullOrWhiteSpace($target) -or (-not (Test-Path -LiteralPath $target))) {
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
    } elseif ($Entry.SourceKind -eq "Store" -and -not [string]::IsNullOrWhiteSpace([string]$Entry.PackageFamilyName)) {
        $regFull = "Computer\HKEY_CURRENT_USER\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$($Entry.PackageFamilyName)\$($Entry.TaskId)"
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
