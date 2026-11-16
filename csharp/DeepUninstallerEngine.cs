using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace DuckUtil
{
    public class ForceStopReport
    {
        public int KilledCount { get; set; }
        public int ServicesStoppedCount { get; set; }
        public int TasksRemovedCount { get; set; }
        public int AccessDeniedCount { get; set; }
        public string[] KilledNames { get; set; }
        public string[] AccessDeniedNames { get; set; }
        public string[] SkippedSystemLockers { get; set; }

        public ForceStopReport()
        {
            KilledNames = new string[0];
            AccessDeniedNames = new string[0];
            SkippedSystemLockers = new string[0];
        }
    }
    public class InstalledAppInfo
    {
        public string Id { get; set; }
        public string DisplayName { get; set; }
        public string DisplayVersion { get; set; }
        public string Publisher { get; set; }
        public string InstallDate { get; set; }
        public string InstallLocation { get; set; }
        public string DataLocation { get; set; }
        public string DisplayIcon { get; set; }
        public string IconSourcePath { get; set; }
        public string UninstallString { get; set; }
        public string QuietUninstallString { get; set; }
        public string RegistryPath { get; set; }
        public string RawRegPath { get; set; }
        public string Scope { get; set; }
        public long SizeBytes { get; set; }
        public bool IsBrokenOrphan { get; set; }
        public string TargetFolder { get; set; }
        public string SearchIndex { get; set; }
    }

    public struct ScanTarget
    {
        public RegistryHive Hive;
        public RegistryView View;
        public string SubKey;
        public string Scope;
        public ScanTarget(RegistryHive h, RegistryView v, string k, string s)
        {
            Hive = h;
            View = v;
            SubKey = k;
            Scope = s;
        }
    }

    public static class DeepUninstallerEngine
    {
        private const int MOVEFILE_DELAY_UNTIL_REBOOT = 0x00000004;
        private const int ERROR_MORE_DATA = 234;
        private const int FO_DELETE = 0x0003;
        private const ushort FOF_SILENT = 0x0004;
        private const ushort FOF_NOCONFIRMATION = 0x0010;
        private const ushort FOF_ALLOWUNDO = 0x0040;
        private const ushort FOF_NOERRORUI = 0x0400;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct RM_UNIQUE_PROCESS
        {
            public int dwProcessId;
            public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct RM_PROCESS_INFO
        {
            public RM_UNIQUE_PROCESS Process;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
            public string strAppName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
            public string strServiceShortName;
            public int ApplicationType;
            public uint AppStatus;
            public uint TSSessionId;
            [MarshalAs(UnmanagedType.Bool)]
            public bool bRestartable;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode, Pack = 1)]
        private struct SHFILEOPSTRUCT_X86
        {
            public IntPtr hwnd;
            public uint wFunc;
            public string pFrom;
            public string pTo;
            public ushort fFlags;
            [MarshalAs(UnmanagedType.Bool)]
            public bool fAnyOperationsAborted;
            public IntPtr hNameMappings;
            public string lpszProgressTitle;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct SHFILEOPSTRUCT_X64
        {
            public IntPtr hwnd;
            public uint wFunc;
            public string pFrom;
            public string pTo;
            public ushort fFlags;
            [MarshalAs(UnmanagedType.Bool)]
            public bool fAnyOperationsAborted;
            public IntPtr hNameMappings;
            public string lpszProgressTitle;
        }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);

        [DllImport("ntdll.dll", SetLastError = true)]
        private static extern int NtSuspendProcess(IntPtr processHandle);

        [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
        private static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, string strSessionKey);

        [DllImport("rstrtmgr.dll")]
        private static extern int RmEndSession(uint pSessionHandle);

        [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
        private static extern int RmRegisterResources(uint pSessionHandle, uint nFiles, string[] rgsFilenames, uint nApplications, [In] RM_UNIQUE_PROCESS[] rgApplications, uint nServices, string[] rgsServiceNames);

        [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
        private static extern int RmGetList(uint dwSessionHandle, out uint pnProcInfoNeeded, ref uint pnProcInfo, [In, Out] RM_PROCESS_INFO[] rgAffectedApps, ref uint lpdwRebootReasons);

        [DllImport("shell32.dll", EntryPoint = "SHFileOperationW", CharSet = CharSet.Unicode)]
        private static extern int SHFileOperationX86(ref SHFILEOPSTRUCT_X86 lpFileOp);

        [DllImport("shell32.dll", EntryPoint = "SHFileOperationW", CharSet = CharSet.Unicode)]
        private static extern int SHFileOperationX64(ref SHFILEOPSTRUCT_X64 lpFileOp);
        private static Dictionary<string, string> _cachedDirIndex;
        private static DateTime _dirIndexBuiltAt = DateTime.MinValue;
        private static readonly object _dirIndexLock = new object();
        private static readonly Regex _ignoredAppxRegex = new Regex(
            @"^(Microsoft\.Windows\.|MicrosoftWindows\.|Windows\.|Microsoft\.UI\.Xaml|Microsoft\.VCLibs|Microsoft\.NET\.Native|Microsoft\.WinAppRuntime|Microsoft\.WindowsAppRuntime|MicrosoftCorporationII\.WinAppRuntime|Microsoft\.Services\.Store|Microsoft\.AAD|Microsoft\.AccountsControl|Microsoft\.AsyncTextService|Microsoft\.BioEnrollment|Microsoft\.CredDialogHost|Microsoft\.ECApp|Microsoft\.LockApp|Microsoft\.Win32WebViewHost|Microsoft\.XboxGame|NcsiUwpApp|Microsoft\.Winget\.|Microsoft\.Ink\.|Microsoft\.LanguageExperiencePack|Microsoft\.DirectXRuntime|Microsoft\.AV1VideoExtension|Microsoft\.HEIFImageExtension|Microsoft\.HEVCVideoExtension|Microsoft\.MPEG2VideoExtension|Microsoft\.RawImageExtension|Microsoft\.VP9VideoExtensions|Microsoft\.WebMediaExtensions|Microsoft\.WebpImageExtension|Microsoft\.SecHealthUI|Microsoft\.StorePurchaseApp|Microsoft\.WindowsStore|Microsoft\.DesktopAppInstaller|Microsoft\.Getstarted|Microsoft\.People|Microsoft\.Paint|Microsoft\.WindowsCalculator|Microsoft\.WindowsCamera|Microsoft\.WindowsMaps|Microsoft\.WindowsNotepad|Microsoft\.YourPhone|Microsoft\.ZuneVideo|microsoft\.windowscommunicationsapps|Microsoft\.549981C3F5F10|Microsoft\.6365217CE6EB4|Microsoft\.CommandPalette|Microsoft\.MicrosoftStickyNotes|Microsoft\.Office\.|Microsoft\.OfficePushNotificationUtility|Microsoft\.OneDriveSync|Microsoft\.MicrosoftEdge|Microsoft\.PowerToys\.|NotepadPlusPlus_|aimgr_|1527c705-|c5e2524a-|E2A4F912-|F46D4000-)",
            RegexOptions.IgnoreCase | RegexOptions.Compiled
        );

        private static Dictionary<string, string> BuildInstallDirectoryIndex()
        {
            lock (_dirIndexLock)
            {
                if (_cachedDirIndex != null && (DateTime.UtcNow - _dirIndexBuiltAt).TotalSeconds < 20)
                {
                    return _cachedDirIndex;
                }

                var index = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

                RegistryHive[] hives = new RegistryHive[] { RegistryHive.LocalMachine, RegistryHive.CurrentUser };
                foreach (var hive in hives)
                {
                    try
                    {
                        using (var baseKey = RegistryKey.OpenBaseKey(hive, RegistryView.Registry64))
                        using (var appPaths = baseKey.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths"))
                        {
                            if (appPaths != null)
                            {
                                foreach (string sub in appPaths.GetSubKeyNames())
                                {
                                    try
                                    {
                                        using (var sk = appPaths.OpenSubKey(sub))
                                        {
                                            if (sk == null) continue;
                                            string defVal = CleanIconFilePath(sk.GetValue("") as string);
                                            string pathVal = (sk.GetValue("Path") as string ?? "").Trim().Trim('\"');
                                            string dir = "";
                                            if (!string.IsNullOrEmpty(defVal) && File.Exists(defVal))
                                            {
                                                dir = Path.GetDirectoryName(defVal);
                                            }
                                            else if (!string.IsNullOrEmpty(pathVal) && Directory.Exists(pathVal))
                                            {
                                                dir = pathVal;
                                            }
                                            if (!string.IsNullOrEmpty(dir) && dir.IndexOf("\\Windows\\", StringComparison.OrdinalIgnoreCase) < 0)
                                            {
                                                string exeKey = Path.GetFileNameWithoutExtension(sub).ToLowerInvariant();
                                                if (!string.IsNullOrEmpty(exeKey) && !index.ContainsKey(exeKey))
                                                {
                                                    index[exeKey] = dir.TrimEnd('\\');
                                                }
                                            }
                                        }
                                    }
                                    catch {}
                                }
                            }
                        }
                    }
                    catch {}
                }

                var roots = new List<string>();
                string pf64 = Environment.GetEnvironmentVariable("ProgramW6432");
                string pf86 = Environment.GetEnvironmentVariable("ProgramFiles(x86)");
                string pf   = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
                string localApp = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                if (!string.IsNullOrEmpty(pf64)) roots.Add(pf64);
                if (!string.IsNullOrEmpty(pf) && !roots.Contains(pf)) roots.Add(pf);
                if (!string.IsNullOrEmpty(pf86)) roots.Add(pf86);
                if (!string.IsNullOrEmpty(localApp))
                {
                    roots.Add(Path.Combine(localApp, "Programs"));
                    roots.Add(localApp);
                }

                foreach (string root in roots)
                {
                    if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) continue;
                    bool isRawLocal = string.Equals(root, localApp, StringComparison.OrdinalIgnoreCase);
                    try
                    {
                        foreach (string dir in Directory.GetDirectories(root))
                        {
                            string folderName = Path.GetFileName(dir);
                            if (string.IsNullOrEmpty(folderName)) continue;
                            if (folderName.Equals("WindowsApps", StringComparison.OrdinalIgnoreCase) ||
                                folderName.Equals("Temp", StringComparison.OrdinalIgnoreCase) ||
                                folderName.Equals("Microsoft", StringComparison.OrdinalIgnoreCase) ||
                                folderName.Equals("Package Cache", StringComparison.OrdinalIgnoreCase) ||
                                folderName.Equals("Common Files", StringComparison.OrdinalIgnoreCase))
                            {
                                continue;
                            }

                            string norm = NormalizeLookupToken(folderName);
                            if (norm.Length >= 3 && !index.ContainsKey(norm))
                            {
                                index[norm] = dir;
                            }

                            if (!isRawLocal)
                            {
                                try
                                {
                                    foreach (string subDir in Directory.GetDirectories(dir))
                                    {
                                        string subName = Path.GetFileName(subDir);
                                        if (string.IsNullOrEmpty(subName)) continue;
                                        string normSub = NormalizeLookupToken(subName);
                                        if (normSub.Length >= 4 && !index.ContainsKey(normSub))
                                        {
                                            index[normSub] = subDir;
                                        }
                                        string normCombined = NormalizeLookupToken(folderName + subName);
                                        if (normCombined.Length >= 4 && !index.ContainsKey(normCombined))
                                        {
                                            index[normCombined] = subDir;
                                        }
                                    }
                                }
                                catch {}
                            }
                        }
                    }
                    catch {}
                }

                _cachedDirIndex = index;
                _dirIndexBuiltAt = DateTime.UtcNow;
                return index;
            }
        }

        private static string NormalizeLookupToken(string s)
        {
            if (string.IsNullOrWhiteSpace(s)) return "";
            var sb = new System.Text.StringBuilder(s.Length);
            foreach (char c in s)
            {
                if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
                {
                    sb.Append(c);
                }
                else if (c >= 'A' && c <= 'Z')
                {
                    sb.Append((char)(c + 32));
                }
            }
            return sb.ToString();
        }

        private static string CleanDisplayNameForDedup(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return "";
            string c = Regex.Replace(name, @"\((?!x64|x86|arm64).*?\)", "", RegexOptions.IgnoreCase).Replace("(", "").Replace(")", "").Trim().ToLowerInvariant();
            c = Regex.Replace(c, @"\b(version|ver|v|release)\s*\d+(\.\d+)*[^\s]*", "", RegexOptions.IgnoreCase);
            c = Regex.Replace(c, @"\b\d+(\.\d+){1,4}(-[a-z0-9.]+)?\b", "", RegexOptions.IgnoreCase);
            string[] terms = new string[] { " browser", " desktop", " lts", " client", " free", " ce", " community", " end-user", " stable", " edition", " x64", " x86", " 64-bit", " 32-bit" };
            foreach (string term in terms)
            {
                c = c.Replace(term, "");
            }
            return Regex.Replace(c, @"\s+", " ").Trim();
        }

        public static List<InstalledAppInfo> GetInstalledApps()
        {
            var list = new List<InstalledAppInfo>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var seenCleanNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var dirIndex = BuildInstallDirectoryIndex();

            var targets = new ScanTarget[]
            {
                new ScanTarget(RegistryHive.LocalMachine, RegistryView.Registry64, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "System"),
                new ScanTarget(RegistryHive.LocalMachine, RegistryView.Registry32, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "System"),
                new ScanTarget(RegistryHive.CurrentUser, RegistryView.Default, @"Software\Microsoft\Windows\CurrentVersion\Uninstall", "User"),
                new ScanTarget(RegistryHive.CurrentUser, RegistryView.Registry32, @"Software\Microsoft\Windows\CurrentVersion\Uninstall", "User")
            };

            foreach (var target in targets)
            {
                try
                {
                    using (var baseKey = RegistryKey.OpenBaseKey(target.Hive, target.View))
                    using (var uninstallKey = baseKey.OpenSubKey(target.SubKey))
                    {
                        if (uninstallKey == null) continue;
                        foreach (var subKeyName in uninstallKey.GetSubKeyNames())
                        {
                            try
                            {
                                using (var appKey = uninstallKey.OpenSubKey(subKeyName))
                                {
                                    if (appKey == null) continue;

                                    var sysComp = appKey.GetValue("SystemComponent");
                                    if (sysComp != null && (sysComp.ToString() == "1" || ((sysComp is int) && ((int)sysComp == 1))))
                                        continue;

                                    var parentKey = appKey.GetValue("ParentKeyName") as string;
                                    if (!string.IsNullOrEmpty(parentKey)) continue;

                                    var releaseType = appKey.GetValue("ReleaseType") as string;
                                    if (!string.IsNullOrEmpty(releaseType) && (releaseType.IndexOf("Update", StringComparison.OrdinalIgnoreCase) >= 0 || releaseType.IndexOf("Hotfix", StringComparison.OrdinalIgnoreCase) >= 0))
                                        continue;

                                    var displayName = appKey.GetValue("DisplayName") as string;
                                    if (string.IsNullOrWhiteSpace(displayName)) continue;
                                    displayName = displayName.Trim();

                                    if (displayName.Equals("vs_CoreEditorFonts", StringComparison.OrdinalIgnoreCase) ||
                                        displayName.Equals("Windows SDK AddOn", StringComparison.OrdinalIgnoreCase))
                                    {
                                        continue;
                                    }

                                    string dispVer = (appKey.GetValue("DisplayVersion") as string ?? "").Trim();
                                    string dedupKey = displayName + "|" + dispVer;
                                    if (seen.Contains(dedupKey)) continue;
                                    seen.Add(dedupKey);
                                    seenCleanNames.Add(NormalizeLookupToken(CleanDisplayNameForDedup(displayName)));

                                    var info = new InstalledAppInfo();
                                    info.Id = subKeyName;
                                    info.DisplayName = displayName;
                                    info.DisplayVersion = dispVer;
                                    info.Publisher = (appKey.GetValue("Publisher") as string ?? "").Trim();
                                    info.InstallDate = (appKey.GetValue("InstallDate") as string ?? "").Trim();
                                    info.InstallLocation = (appKey.GetValue("InstallLocation") as string ?? "").Trim().Trim('\"');
                                    info.DataLocation = ResolveExternalDataLocation(appKey, info.InstallLocation);
                                    info.UninstallString = (appKey.GetValue("UninstallString") as string ?? "").Trim();
                                    info.QuietUninstallString = (appKey.GetValue("QuietUninstallString") as string ?? "").Trim();
                                    info.DisplayIcon = (appKey.GetValue("DisplayIcon") as string ?? "").Trim();
                                    info.Scope = target.Scope;

                                    string hivePrefix = target.Hive == RegistryHive.LocalMachine ? @"HKLM:\" : @"HKCU:\";
                                    string fullSub = target.SubKey + @"\" + subKeyName;
                                    if (target.Hive == RegistryHive.LocalMachine && target.View == RegistryView.Registry32 &&
                                        fullSub.StartsWith(@"SOFTWARE\", StringComparison.OrdinalIgnoreCase) &&
                                        fullSub.IndexOf(@"WOW6432Node\", StringComparison.OrdinalIgnoreCase) < 0)
                                    {
                                        fullSub = @"SOFTWARE\WOW6432Node\" + fullSub.Substring(@"SOFTWARE\".Length);
                                    }
                                    info.RegistryPath = hivePrefix + fullSub;
                                    info.RawRegPath = (target.Hive == RegistryHive.LocalMachine ? "HKEY_LOCAL_MACHINE\\" : "HKEY_CURRENT_USER\\") + fullSub;

                                    long size = 0;
                                    var estSize = appKey.GetValue("EstimatedSize");
                                    if (estSize != null)
                                    {
                                        long esVal;
                                        if (long.TryParse(estSize.ToString(), out esVal))
                                        {
                                            size = esVal * 1024L;
                                        }
                                    }
                                    info.SizeBytes = size;

                                    list.Add(info);
                                }
                            }
                            catch {}
                        }
                    }
                }
                catch {}
            }

            try
            {
                using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64))
                using (var pkgRoot = baseKey.OpenSubKey(@"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages"))
                {
                    if (pkgRoot != null)
                    {
                        foreach (string pkgFull in pkgRoot.GetSubKeyNames())
                        {
                            if (string.IsNullOrWhiteSpace(pkgFull)) continue;
                            if (_ignoredAppxRegex.IsMatch(pkgFull))
                            {
                                continue;
                            }

                            try
                            {
                                using (var sk = pkgRoot.OpenSubKey(pkgFull))
                                {
                                    if (sk == null) continue;
                                    string rootFolder = (sk.GetValue("PackageRootFolder") as string ?? "").Trim();
                                    string rawDisp = (sk.GetValue("DisplayName") as string ?? "").Trim();
                                    string[] parts = pkgFull.Split('_');
                                    string pkgIdPrefix = parts.Length > 0 ? parts[0] : pkgFull;
                                    string pkgVer = parts.Length > 1 ? parts[1] : "";

                                    string friendlyName = rawDisp;
                                    string publisher = "Microsoft Store (MSIX)";
                                    if (pkgIdPrefix.IndexOf("MicrosoftPCManager", StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        friendlyName = "Microsoft PC Manager";
                                        publisher = "Microsoft Corporation";
                                    }
                                    else if (pkgIdPrefix.IndexOf("WindowsTerminal", StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        friendlyName = "Windows Terminal";
                                        publisher = "Microsoft Corporation";
                                    }
                                    else if (pkgIdPrefix.IndexOf("WindowsSubsystemForLinux", StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        friendlyName = "Windows Subsystem for Linux";
                                        publisher = "Microsoft Corporation";
                                    }
                                    else if (pkgIdPrefix.IndexOf("TranslucentTB", StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        friendlyName = "TranslucentTB";
                                        publisher = "Charles Milette";
                                    }
                                    else if (pkgIdPrefix.IndexOf("TelegramDesktop", StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        friendlyName = "Telegram Desktop";
                                        publisher = "Telegram Messenger LLP";
                                    }
                                    else if (pkgIdPrefix.IndexOf("OpenAI.Codex", StringComparison.OrdinalIgnoreCase) >= 0 || pkgIdPrefix.IndexOf("OpenAI.ChatGPT", StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        friendlyName = "ChatGPT";
                                        publisher = "OpenAI";
                                    }
                                    else if (pkgIdPrefix.IndexOf("LenovoCompanion", StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        friendlyName = "Lenovo Vantage";
                                        publisher = "Lenovo Group Ltd.";
                                    }
                                    else if (pkgIdPrefix.IndexOf("KaliLinux", StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        friendlyName = "Kali Linux";
                                        publisher = "Offensive Security";
                                    }
                                    else if (pkgIdPrefix.IndexOf("NVIDIAControlPanel", StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        friendlyName = "NVIDIA Control Panel";
                                        publisher = "NVIDIA Corporation";
                                    }
                                    else if (pkgIdPrefix.IndexOf("WhatsAppDesktop", StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        friendlyName = "WhatsApp";
                                        publisher = "WhatsApp Inc.";
                                    }
                                    else if (string.IsNullOrWhiteSpace(friendlyName) || friendlyName.StartsWith("ms-resource:", StringComparison.OrdinalIgnoreCase))
                                    {
                                        continue;
                                    }

                                    string normClean = NormalizeLookupToken(CleanDisplayNameForDedup(friendlyName));
                                    if (seenCleanNames.Contains(normClean)) continue;
                                    seenCleanNames.Add(normClean);

                                    string escapedPkg = pkgFull.Replace("'", "''");
                                    string uninstCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command \"Remove-AppxPackage -Package '" + escapedPkg + "'\"";
                                    var msixInfo = new InstalledAppInfo
                                    {
                                        Id = "MSIX\\" + pkgFull,
                                        DisplayName = friendlyName,
                                        DisplayVersion = pkgVer,
                                        Publisher = publisher,
                                        InstallDate = "",
                                        InstallLocation = rootFolder,
                                        DataLocation = "",
                                        DisplayIcon = "",
                                        UninstallString = uninstCmd,
                                        QuietUninstallString = uninstCmd,
                                        RegistryPath = @"HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages\" + pkgFull,
                                        RawRegPath = @"HKEY_CURRENT_USER\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages\" + pkgFull,
                                        Scope = "User",
                                        SizeBytes = 0
                                    };
                                    list.Add(msixInfo);
                                }
                            }
                            catch {}
                        }
                    }
                }
            }
            catch {}

            Parallel.ForEach(list, info =>
            {
                try
                {
                    info.InstallLocation = InferInstallLocation(info.Id, info.DisplayName, info.InstallLocation, info.UninstallString, info.DisplayIcon, dirIndex);
                    if (string.IsNullOrEmpty(info.DataLocation) && !string.IsNullOrEmpty(info.InstallLocation))
                    {
                        info.DataLocation = ResolveConfigDataLocation(info.InstallLocation);
                    }
                    if (!string.IsNullOrEmpty(info.DataLocation) && !string.IsNullOrEmpty(info.InstallLocation) &&
                        info.DataLocation.Equals(info.InstallLocation.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
                    {
                        info.DataLocation = "";
                    }
                    info.IconSourcePath = ResolveBestIconPath(info.Id, info.DisplayName, info.DisplayIcon, info.InstallLocation, info.UninstallString);
                    if (string.IsNullOrWhiteSpace(info.Publisher))
                    {
                        info.Publisher = InferPublisher(info);
                    }
                    if (!string.IsNullOrEmpty(info.InstallLocation))
                    {
                        long instDiskSize = GetDirectorySizeCapped(info.InstallLocation, 4, 2500);
                        if (instDiskSize > info.SizeBytes) info.SizeBytes = instDiskSize;
                    }
                    if (!string.IsNullOrEmpty(info.DataLocation))
                    {
                        bool isSubOfInstall = !string.IsNullOrEmpty(info.InstallLocation) &&
                            info.DataLocation.StartsWith(info.InstallLocation.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase);
                        if (!isSubOfInstall)
                        {
                            long dataDiskSize = GetDirectorySizeCapped(info.DataLocation, 4, 2500);
                            if (dataDiskSize > 0) info.SizeBytes += dataDiskSize;
                        }
                    }
                    info.IsBrokenOrphan = CheckIsBrokenOrphan(info.UninstallString, info.InstallLocation);
                    if (!string.IsNullOrEmpty(info.InstallLocation) && Directory.Exists(info.InstallLocation))
                    {
                        info.TargetFolder = info.InstallLocation;
                    }
                    else if (!string.IsNullOrEmpty(info.DataLocation) && Directory.Exists(info.DataLocation))
                    {
                        info.TargetFolder = info.DataLocation;
                    }
                    else
                    {
                        info.TargetFolder = "";
                    }
                    info.SearchIndex = ((info.DisplayName ?? "") + " " + (info.Publisher ?? "") + " " + (info.DisplayVersion ?? "")).ToLowerInvariant();
                }
                catch {}
            });

            return list;
        }

        public static Task<List<InstalledAppInfo>> GetInstalledAppsAsync()
        {
            return Task.Run(() => GetInstalledApps());
        }

        private static bool IsValidExternalDataPath(string candidate, string installLocation)
        {
            if (string.IsNullOrWhiteSpace(candidate)) return false;
            try
            {
                string cleaned = Environment.ExpandEnvironmentVariables(candidate).Trim().Trim('\"', '\'', ' ').TrimEnd('\\');
                if (cleaned.Length <= 3) return false;
                if (!Regex.IsMatch(cleaned, @"^[a-zA-Z]:\\[^<>|""?*]+$")) return false;
                if (!string.IsNullOrEmpty(installLocation) && cleaned.Equals(installLocation.Trim().TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
                    return false;

                string leaf = Path.GetFileName(cleaned) ?? "";
                if (string.IsNullOrEmpty(leaf)) return false;
                var genericRoots = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
                {
                    "Windows", "System32", "SysWOW64", "Program Files", "Program Files (x86)",
                    "ProgramData", "Users", "AppData", "Local", "Roaming", "LocalLow", "Games", "Game", "Programs"
                };
                if (genericRoots.Contains(leaf)) return false;
                return Directory.Exists(cleaned);
            }
            catch { return false; }
        }

        private static string ResolveExternalDataLocation(RegistryKey appKey, string installLocation)
        {
            if (appKey == null) return "";
            string[] valueNames = new string[]
            {
                "GameInstallPath", "GamePath", "DataPath", "ResourcePath", "InstallPath", "AppPath", "TargetDir"
            };
            foreach (string vn in valueNames)
            {
                try
                {
                    string raw = appKey.GetValue(vn) as string;
                    if (!string.IsNullOrWhiteSpace(raw) && IsValidExternalDataPath(raw, installLocation))
                    {
                        return Environment.ExpandEnvironmentVariables(raw).Trim().Trim('\"', '\'', ' ').TrimEnd('\\');
                    }
                }
                catch {}
            }
            return "";
        }

        public static string ResolveConfigDataLocation(string installLocation)
        {
            if (string.IsNullOrWhiteSpace(installLocation)) return "";
            try
            {
                if (!Directory.Exists(installLocation)) return "";
            }
            catch { return ""; }

            string[] cfgNames = new string[] { "config.ini", "config.json", "launcher_config.ini", "settings.json" };
            foreach (string cfg in cfgNames)
            {
                try
                {
                    string cfgPath = Path.Combine(installLocation, cfg);
                    if (!File.Exists(cfgPath)) continue;
                    var fi = new FileInfo(cfgPath);
                    if (fi.Length <= 0 || fi.Length > 262144L) continue;
                    string txt = File.ReadAllText(cfgPath);
                    MatchCollection matches = Regex.Matches(txt, @"(?:game_install_path|install_path|game_path|data_path|resource_path|game_biz_path)\s*[=:]\s*[""']?([A-Za-z]:\\(?:\\\\|[^""'\r\n,;}])+)", RegexOptions.IgnoreCase);
                    foreach (Match m in matches)
                    {
                        if (m.Groups.Count < 2) continue;
                        string cand = m.Groups[1].Value.Replace("\\\\", "\\").Trim('\"', '\'', ' ').TrimEnd('\\');
                        if (IsValidExternalDataPath(cand, installLocation))
                        {
                            return cand;
                        }
                    }
                }
                catch {}
            }
            return "";
        }

        private static string InferInstallLocation(string subKeyName, string displayName, string installLocation, string uninstallString, string displayIcon, Dictionary<string, string> dirIndex)
        {
            if (!string.IsNullOrWhiteSpace(installLocation))
            {
                string trimmed = installLocation.Trim().TrimEnd('\\');
                if (trimmed.Length > 3) return trimmed;
            }

            if (!string.IsNullOrWhiteSpace(subKeyName) && subKeyName.StartsWith("{"))
            {
                string packed = ConvertToPackedGuid(subKeyName);
                if (!string.IsNullOrEmpty(packed))
                {
                    try
                    {
                        using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                        using (var propKey = baseKey.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\" + packed + @"\InstallProperties"))
                        {
                            if (propKey != null)
                            {
                                string msiLoc = (propKey.GetValue("InstallLocation") as string ?? "").Trim().Trim('\"').TrimEnd('\\');
                                if (!string.IsNullOrEmpty(msiLoc) && msiLoc.Length > 3 && Directory.Exists(msiLoc))
                                {
                                    return msiLoc;
                                }
                            }
                        }
                    }
                    catch {}
                }
            }

            string[] candidates = new string[] { uninstallString, displayIcon };
            foreach (string cand in candidates)
            {
                if (string.IsNullOrWhiteSpace(cand)) continue;
                if (cand.IndexOf("msiexec", StringComparison.OrdinalIgnoreCase) >= 0) continue;

                string exePath = ExtractExePath(cand);
                if (string.IsNullOrWhiteSpace(exePath)) continue;
                if (exePath.IndexOf("\\Windows\\", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    exePath.IndexOf("\\Package Cache\\", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    exePath.IndexOf("\\Temp\\", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    continue;
                }

                try
                {
                    string dir = Path.GetDirectoryName(exePath);
                    if (!string.IsNullOrWhiteSpace(dir) && dir.Length > 3)
                    {
                        return dir.TrimEnd('\\');
                    }
                }
                catch {}
            }

            if (!string.IsNullOrWhiteSpace(displayName))
            {
                string dotnetRoot = displayName.IndexOf("(x86)", StringComparison.OrdinalIgnoreCase) >= 0
                    ? @"C:\Program Files (x86)\dotnet"
                    : @"C:\Program Files\dotnet";

                Match mSdk = Regex.Match(displayName, @"\.NET SDK\s+(\d+\.\d+\.\d+[^\s\(]*)", RegexOptions.IgnoreCase);
                if (mSdk.Success)
                {
                    string sdkDir = Path.Combine(dotnetRoot, "sdk", mSdk.Groups[1].Value);
                    if (Directory.Exists(sdkDir)) return sdkDir;
                    if (Directory.Exists(dotnetRoot)) return dotnetRoot;
                }

                Match mDesk = Regex.Match(displayName, @"Windows Desktop Runtime\s*(?:-\s*)?(\d+\.\d+\.\d+[^\s\(]*)", RegexOptions.IgnoreCase);
                if (mDesk.Success)
                {
                    string deskDir = Path.Combine(dotnetRoot, @"shared\Microsoft.WindowsDesktop.App", mDesk.Groups[1].Value);
                    if (Directory.Exists(deskDir)) return deskDir;
                }

                Match mAsp = Regex.Match(displayName, @"ASP\.NET Core Runtime\s*(?:-\s*)?(\d+\.\d+\.\d+[^\s\(]*)", RegexOptions.IgnoreCase);
                if (mAsp.Success)
                {
                    string aspDir = Path.Combine(dotnetRoot, @"shared\Microsoft.AspNetCore.App", mAsp.Groups[1].Value);
                    if (Directory.Exists(aspDir)) return aspDir;
                }

                if (displayName.IndexOf("Windows Software Development Kit", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    string kitDir = @"C:\Program Files (x86)\Windows Kits\10";
                    if (Directory.Exists(kitDir)) return kitDir;
                }

                if (displayName.IndexOf("DaVinci Resolve Control Panels", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    string dvPanel = @"C:\Program Files (x86)\Blackmagic Design\DaVinci Control Panels";
                    if (Directory.Exists(dvPanel)) return dvPanel;
                }
            }

            if (dirIndex != null && !string.IsNullOrWhiteSpace(displayName))
            {
                if (displayName.IndexOf("Redistributable", StringComparison.OrdinalIgnoreCase) < 0 &&
                    displayName.IndexOf("Runtime", StringComparison.OrdinalIgnoreCase) < 0 &&
                    displayName.IndexOf(".NET SDK", StringComparison.OrdinalIgnoreCase) < 0 &&
                    displayName.IndexOf("AddOn", StringComparison.OrdinalIgnoreCase) < 0 &&
                    displayName.IndexOf("CoreEditorFonts", StringComparison.OrdinalIgnoreCase) < 0)
                {
                    string cleanName = Regex.Replace(displayName, @"\(.*?\)|\b(version|v)?\s*\d+(\.\d+)+[^\s]*|\b(x64|x86|64-bit|32-bit|Common Components|System Software)\b", "", RegexOptions.IgnoreCase).Trim();
                    string normFull = NormalizeLookupToken(cleanName);
                    string matchedDir;
                    if (normFull.Length >= 3 && dirIndex.TryGetValue(normFull, out matchedDir) && Directory.Exists(matchedDir))
                    {
                        return matchedDir;
                    }
                    string normRaw = NormalizeLookupToken(displayName);
                    if (normRaw.Length >= 3 && dirIndex.TryGetValue(normRaw, out matchedDir) && Directory.Exists(matchedDir))
                    {
                        return matchedDir;
                    }
                    if (normFull.Contains("cloudflareone") && dirIndex.TryGetValue("cloudflarewarp", out matchedDir)) return matchedDir;
                    if (normFull.Contains("chromeremotedesktop") && dirIndex.TryGetValue("chromeremotedesktop", out matchedDir)) return matchedDir;
                }
            }

            return "";
        }

        public static string ConvertToPackedGuid(string guidStr)
        {
            if (string.IsNullOrWhiteSpace(guidStr)) return "";
            string g = guidStr.Trim().Trim('{', '}').Replace("-", "");
            if (g.Length != 32) return "";
            for (int k = 0; k < 32; k++)
            {
                char c = g[k];
                bool isHex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
                if (!isHex) return "";
            }
            char[] chars = new char[32];
            for (int i = 0; i < 8; i++) chars[i] = g[7 - i];
            for (int i = 0; i < 4; i++) chars[8 + i] = g[11 - i];
            for (int i = 0; i < 4; i++) chars[12 + i] = g[15 - i];
            for (int i = 0; i < 8; i++)
            {
                chars[16 + (i * 2)] = g[16 + (i * 2) + 1];
                chars[16 + (i * 2) + 1] = g[16 + (i * 2)];
            }
            return new string(chars);
        }

        public static string CleanIconFilePath(string raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return "";
            string s = Environment.ExpandEnvironmentVariables(raw.Trim()).Replace('/', '\\');
            if (s.StartsWith("\""))
            {
                int q = s.IndexOf('\"', 1);
                if (q > 1) s = s.Substring(1, q - 1).Trim();
                else s = s.Trim('\"');
            }
            else
            {
                int lastComma = s.LastIndexOf(',');
                if (lastComma > 2)
                {
                    string after = s.Substring(lastComma + 1).Trim();
                    int dummy;
                    if (int.TryParse(after, out dummy))
                    {
                        s = s.Substring(0, lastComma).Trim();
                    }
                }
            }
            s = s.Trim('\"', ' ');
            while (s.Contains("\\\\") && !s.StartsWith("\\\\"))
            {
                s = s.Replace("\\\\", "\\");
            }
            try
            {
                if (File.Exists(s)) return s;
            }
            catch {}

            string[] exts = new string[] { ".ico", ".exe", ".dll" };
            foreach (string ext in exts)
            {
                int idx = s.IndexOf(ext, StringComparison.OrdinalIgnoreCase);
                if (idx > 0)
                {
                    string cand = s.Substring(0, idx + ext.Length).Trim('\"', ' ');
                    try
                    {
                        if (File.Exists(cand)) return cand;
                    }
                    catch {}
                }
            }
            return "";
        }

        private static string FindBestExeOrIcoInDirectory(string dirPath, string displayName)
        {
            if (string.IsNullOrWhiteSpace(dirPath)) return "";
            try
            {
                if (!Directory.Exists(dirPath)) return "";
            }
            catch { return ""; }

            try
            {
                string appIco = Path.Combine(dirPath, "app.ico");
                if (File.Exists(appIco)) return appIco;
                string iconIco = Path.Combine(dirPath, "icon.ico");
                if (File.Exists(iconIco)) return iconIco;
                string[] icos = Directory.GetFiles(dirPath, "*.ico", SearchOption.TopDirectoryOnly);
                if (icos != null && icos.Length > 0) return icos[0];
            }
            catch {}

            var dirsToScan = new List<string>();
            dirsToScan.Add(dirPath);
            string[] commonSubDirs = new string[] { "bin", "bin\\64bit", "64bit", "app", "Application", "Client" };
            foreach (string sub in commonSubDirs)
            {
                try
                {
                    string sp = Path.Combine(dirPath, sub);
                    if (Directory.Exists(sp)) dirsToScan.Add(sp);
                }
                catch {}
            }
            try
            {
                string[] subFolders = Directory.GetDirectories(dirPath, "app-*", SearchOption.TopDirectoryOnly);
                if (subFolders != null && subFolders.Length > 0)
                {
                    for (int i = subFolders.Length - 1; i >= 0; i--)
                    {
                        dirsToScan.Add(subFolders[i]);
                    }
                }
            }
            catch {}

            string cleanDisp = "";
            if (!string.IsNullOrWhiteSpace(displayName))
            {
                cleanDisp = displayName.Replace(" ", "").ToLowerInvariant();
            }

            string bestExe = "";
            int bestScore = -1;

            foreach (string d in dirsToScan)
            {
                string[] exes = null;
                try { exes = Directory.GetFiles(d, "*.exe", SearchOption.TopDirectoryOnly); } catch {}
                if (exes == null || exes.Length == 0) continue;

                foreach (string exe in exes)
                {
                    string nameNoExt = "";
                    try { nameNoExt = Path.GetFileNameWithoutExtension(exe).ToLowerInvariant(); } catch { continue; }
                    if (string.IsNullOrEmpty(nameNoExt)) continue;

                    if (nameNoExt.Contains("unins") || nameNoExt.Contains("setup") || nameNoExt.Contains("update") ||
                        nameNoExt.Contains("crash") || nameNoExt.Contains("helper") || nameNoExt.Contains("repair") ||
                        nameNoExt.Contains("patch") || nameNoExt.Contains("createdump") || nameNoExt.Contains("eclipsec"))
                    {
                        continue;
                    }

                    int score = 10;
                    string compactExe = nameNoExt.Replace(" ", "").Replace("-", "").Replace("_", "");
                    if (!string.IsNullOrEmpty(cleanDisp) && compactExe.Length >= 3)
                    {
                        if (cleanDisp.Contains(compactExe) || compactExe.Contains(cleanDisp))
                        {
                            score += 50;
                        }
                    }
                    if (score > bestScore)
                    {
                        bestScore = score;
                        bestExe = exe;
                    }
                }
                if (bestScore >= 50) return bestExe;
            }

            return bestExe;
        }

        public static string ResolveBestIconPath(string subKeyName, string displayName, string displayIcon, string installLocation, string uninstallString)
        {
            string cleanedIcon = CleanIconFilePath(displayIcon);
            if (!string.IsNullOrEmpty(cleanedIcon))
            {
                string fn = "";
                try { fn = Path.GetFileNameWithoutExtension(cleanedIcon).ToLowerInvariant(); } catch {}
                if (!fn.Contains("unins"))
                {
                    return cleanedIcon;
                }
            }

            if (!string.IsNullOrWhiteSpace(subKeyName) && subKeyName.StartsWith("{"))
            {
                string packed = ConvertToPackedGuid(subKeyName);
                if (!string.IsNullOrEmpty(packed))
                {
                    try
                    {
                        using (var k = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Classes\Installer\Products\" + packed))
                        {
                            if (k != null)
                            {
                                string pi = CleanIconFilePath(k.GetValue("ProductIcon") as string);
                                if (!string.IsNullOrEmpty(pi)) return pi;
                            }
                        }
                    }
                    catch {}
                    try
                    {
                        using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Installer\Products\" + packed))
                        {
                            if (k != null)
                            {
                                string pi = CleanIconFilePath(k.GetValue("ProductIcon") as string);
                                if (!string.IsNullOrEmpty(pi)) return pi;
                            }
                        }
                    }
                    catch {}
                }

                try
                {
                    string wiDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Installer", subKeyName);
                    if (Directory.Exists(wiDir))
                    {
                        string[] wiFiles = Directory.GetFiles(wiDir);
                        if (wiFiles != null && wiFiles.Length > 0)
                        {
                            foreach (string wf in wiFiles)
                            {
                                string wfn = Path.GetFileName(wf).ToLowerInvariant();
                                if (wfn.EndsWith(".ico") || wfn.Contains("icon") || wfn.Contains("logo"))
                                {
                                    return wf;
                                }
                            }
                            return wiFiles[0];
                        }
                    }
                }
                catch {}
            }

            string fromDir = FindBestExeOrIcoInDirectory(installLocation, displayName);
            if (!string.IsNullOrEmpty(fromDir)) return fromDir;

            if (!string.IsNullOrEmpty(cleanedIcon))
            {
                try
                {
                    string iconDir = Path.GetDirectoryName(cleanedIcon);
                    string sibling = FindBestExeOrIcoInDirectory(iconDir, displayName);
                    if (!string.IsNullOrEmpty(sibling)) return sibling;
                }
                catch {}
                return cleanedIcon;
            }

            if (!string.IsNullOrWhiteSpace(uninstallString) && uninstallString.IndexOf("msiexec", StringComparison.OrdinalIgnoreCase) < 0)
            {
                string uExe = CleanIconFilePath(uninstallString);
                if (!string.IsNullOrEmpty(uExe))
                {
                    try
                    {
                        string uDir = Path.GetDirectoryName(uExe);
                        string uSibling = FindBestExeOrIcoInDirectory(uDir, displayName);
                        if (!string.IsNullOrEmpty(uSibling)) return uSibling;
                    }
                    catch {}
                    return uExe;
                }
            }

            return "";
        }

        private static bool IsUsablePublisherCandidate(string raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return false;
            string s = raw.Trim().Trim('\"', ' ');
            if (s.Length < 2 || s.Length > 100) return false;
            string lower = s.ToLowerInvariant();
            string[] invalid = new string[]
            {
                "n/a", "none", "null", "unknown", "default", "todo", "company",
                "my company", "my company, inc.", "your company", "your company name",
                "publisher", "author", "developer", "vendor", "jordan russell",
                "inno setup", "nullsoft", "nsis", "localhost", "test"
            };
            foreach (string inv in invalid)
            {
                if (lower == inv) return false;
            }
            return true;
        }

        private static string ExtractOrganizationFromCertSubject(string subject)
        {
            if (string.IsNullOrWhiteSpace(subject)) return "";
            string org = "";
            string cn = "";
            try
            {
                MatchCollection matches = Regex.Matches(subject, @"(?:^|,\s*)(?<k>O|CN)=(?:""(?<vq>[^""]+)""|(?<vp>[^,]+))", RegexOptions.IgnoreCase);
                foreach (Match m in matches)
                {
                    string k = m.Groups["k"].Value.ToUpperInvariant();
                    string v = (m.Groups["vq"].Success ? m.Groups["vq"].Value : m.Groups["vp"].Value).Trim();
                    if (!IsUsablePublisherCandidate(v)) continue;
                    if (k == "O" && string.IsNullOrEmpty(org)) org = v;
                    else if (k == "CN" && string.IsNullOrEmpty(cn)) cn = v;
                }
            }
            catch {}
            return !string.IsNullOrEmpty(org) ? org : cn;
        }

        public static string InferPublisher(InstalledAppInfo info)
        {
            if (info == null) return "";
            if (!string.IsNullOrWhiteSpace(info.Publisher)) return info.Publisher.Trim();

            if (!string.IsNullOrWhiteSpace(info.Id) && info.Id.StartsWith("{"))
            {
                string packed = ConvertToPackedGuid(info.Id);
                if (!string.IsNullOrEmpty(packed))
                {
                    try
                    {
                        using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                        using (var propKey = baseKey.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\" + packed + @"\InstallProperties"))
                        {
                            if (propKey != null)
                            {
                                string msiPub = (propKey.GetValue("Publisher") as string ?? "").Trim();
                                if (IsUsablePublisherCandidate(msiPub)) return msiPub;
                            }
                        }
                    }
                    catch {}
                }
            }

            var candidateExes = new List<string>();
            var seenExes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            string iconExe = CleanIconFilePath(info.IconSourcePath);
            if (!string.IsNullOrEmpty(iconExe) && iconExe.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && seenExes.Add(iconExe))
            {
                candidateExes.Add(iconExe);
            }

            string dispExe = CleanIconFilePath(info.DisplayIcon);
            if (!string.IsNullOrEmpty(dispExe) && dispExe.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && seenExes.Add(dispExe))
            {
                candidateExes.Add(dispExe);
            }

            if (!string.IsNullOrWhiteSpace(info.InstallLocation))
            {
                try
                {
                    if (Directory.Exists(info.InstallLocation))
                    {
                        int count = 0;
                        foreach (string exe in Directory.EnumerateFiles(info.InstallLocation, "*.exe", SearchOption.TopDirectoryOnly))
                        {
                            string fn = Path.GetFileNameWithoutExtension(exe).ToLowerInvariant();
                            if (fn.Contains("unins") || fn.Contains("uninst") || fn.Contains("setup") ||
                                fn.Contains("repair") || fn.Contains("crash") || fn.Contains("update"))
                            {
                                continue;
                            }
                            if (seenExes.Add(exe))
                            {
                                candidateExes.Add(exe);
                                count++;
                                if (count >= 10) break;
                            }
                        }
                    }
                }
                catch {}
            }

            if (!string.IsNullOrWhiteSpace(info.UninstallString) &&
                info.UninstallString.IndexOf("msiexec", StringComparison.OrdinalIgnoreCase) < 0)
            {
                string uninstExe = CleanIconFilePath(info.UninstallString);
                if (!string.IsNullOrEmpty(uninstExe) && uninstExe.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && seenExes.Add(uninstExe))
                {
                    candidateExes.Add(uninstExe);
                }
            }

            foreach (string exe in candidateExes)
            {
                try
                {
                    if (!File.Exists(exe)) continue;
                    FileVersionInfo fvi = FileVersionInfo.GetVersionInfo(exe);
                    string company = (fvi.CompanyName ?? "").Trim();
                    if (IsUsablePublisherCandidate(company)) return company;
                }
                catch {}
            }

            foreach (string exe in candidateExes)
            {
                try
                {
                    if (!File.Exists(exe)) continue;
                    string certOrg = ExtractOrganizationFromCertSubject(GetSignerSubject(exe));
                    if (IsUsablePublisherCandidate(certOrg)) return certOrg;
                }
                catch {}
            }

            if ((!string.IsNullOrWhiteSpace(info.Id) && info.Id.Equals("Rustup", StringComparison.OrdinalIgnoreCase)) ||
                (!string.IsNullOrWhiteSpace(info.DisplayName) && info.DisplayName.StartsWith("Rustup", StringComparison.OrdinalIgnoreCase)))
            {
                return "The Rust Project Developers";
            }

            return "";
        }

        private static bool CheckIsBrokenOrphan(string uninstallString, string installLocation)
        {
            if (string.IsNullOrWhiteSpace(uninstallString)) return false;
            string u = Environment.ExpandEnvironmentVariables(uninstallString).Trim();
            if (u.IndexOf("msiexec", StringComparison.OrdinalIgnoreCase) >= 0) return false;

            string exePath = ExtractExePath(u);
            if (string.IsNullOrEmpty(exePath)) return false;
            exePath = exePath.Trim('\"', ' ');
            if (!Regex.IsMatch(exePath, @"^[a-zA-Z]:\\")) return false;

            bool exeExists = false;
            try { exeExists = File.Exists(exePath); } catch {}

            if (!exeExists)
            {
                bool locExists = false;
                try
                {
                    if (!string.IsNullOrWhiteSpace(installLocation))
                    {
                        string expLoc = Environment.ExpandEnvironmentVariables(installLocation).Trim('\"', ' ');
                        if (!string.IsNullOrEmpty(expLoc) && Directory.Exists(expLoc))
                        {
                            locExists = true;
                        }
                    }
                }
                catch {}

                if (!locExists) return true;
            }

            return false;
        }

        private static string ExtractExePath(string raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return null;
            raw = Environment.ExpandEnvironmentVariables(raw).Trim();
            if (raw.StartsWith("\""))
            {
                int nextQuote = raw.IndexOf('\"', 1);
                if (nextQuote > 1)
                {
                    return raw.Substring(1, nextQuote - 1).Trim();
                }
            }

            int exeIdx = raw.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
            if (exeIdx > 0)
            {
                return raw.Substring(0, exeIdx + 4).Trim('\"', ' ');
            }

            int spaceIdx = raw.IndexOf(' ');
            if (spaceIdx > 0)
            {
                return raw.Substring(0, spaceIdx).Trim('\"', ' ');
            }

            return raw.Trim('\"', ' ');
        }

        private static bool IsReparsePoint(string path)
        {
            if (string.IsNullOrEmpty(path)) return false;
            try
            {
                return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
            }
            catch { return false; }
        }

        public static long GetHollowDirectorySize(string rootPath, int maxDepth, long maxSizeLimit)
        {
            if (string.IsNullOrEmpty(rootPath)) return -1L;
            try
            {
                if (!Directory.Exists(rootPath) || IsReparsePoint(rootPath)) return -1L;
            }
            catch { return -1L; }

            long totalSize = 0L;
            var currentLevel = new List<string> { rootPath };

            for (int depth = 0; depth <= maxDepth; depth++)
            {
                var nextLevel = new List<string>();
                foreach (var dir in currentLevel)
                {
                    try
                    {
                        foreach (var file in Directory.EnumerateFiles(dir))
                        {
                            string ext = Path.GetExtension(file);
                            if (string.Equals(ext, ".exe", StringComparison.OrdinalIgnoreCase) ||
                                string.Equals(ext, ".dll", StringComparison.OrdinalIgnoreCase) ||
                                string.Equals(ext, ".sys", StringComparison.OrdinalIgnoreCase))
                            {
                                return -1L;
                            }
                            try
                            {
                                var fi = new FileInfo(file);
                                totalSize += fi.Length;
                                if (totalSize >= maxSizeLimit) return -1L;
                            }
                            catch {}
                        }

                        if (depth < maxDepth)
                        {
                            foreach (var sub in Directory.EnumerateDirectories(dir))
                            {
                                if (!IsReparsePoint(sub)) nextLevel.Add(sub);
                            }
                        }
                    }
                    catch {}
                }
                if (nextLevel.Count == 0) break;
                currentLevel = nextLevel;
            }

            return totalSize < maxSizeLimit ? totalSize : -1L;
        }

        public static long GetDirectorySizeCapped(string rootPath, int maxDepth, int maxFiles)
        {
            if (string.IsNullOrEmpty(rootPath)) return 0L;
            try
            {
                if (!Directory.Exists(rootPath) || IsReparsePoint(rootPath)) return 0L;
            }
            catch { return 0L; }

            long totalSize = 0L;
            int fileCount = 0;
            var currentLevel = new List<string> { rootPath };

            for (int depth = 0; depth <= maxDepth; depth++)
            {
                var nextLevel = new List<string>();
                foreach (var dir in currentLevel)
                {
                    try
                    {
                        foreach (var file in Directory.EnumerateFiles(dir))
                        {
                            try
                            {
                                var fi = new FileInfo(file);
                                totalSize += fi.Length;
                                fileCount++;
                                if (fileCount >= maxFiles) return totalSize;
                            }
                            catch {}
                        }

                        if (depth < maxDepth)
                        {
                            foreach (var sub in Directory.EnumerateDirectories(dir))
                            {
                                if (!IsReparsePoint(sub)) nextLevel.Add(sub);
                            }
                        }
                    }
                    catch {}
                }
                if (nextLevel.Count == 0) break;
                currentLevel = nextLevel;
            }

            return totalSize;
        }

        public static long GetDirectorySizeFast(string rootPath, int maxDepth)
        {
            return GetDirectorySizeCapped(rootPath, maxDepth, 10000);
        }

        private static List<string> EnumerateFilesSafe(string rootDir, string pattern, int maxDepth)
        {
            var results = new List<string>();
            if (string.IsNullOrEmpty(rootDir)) return results;
            try
            {
                if (!Directory.Exists(rootDir) || IsReparsePoint(rootDir)) return results;
            }
            catch { return results; }

            var currentLevel = new List<string> { rootDir };

            for (int depth = 0; depth <= maxDepth; depth++)
            {
                var nextLevel = new List<string>();
                foreach (var dir in currentLevel)
                {
                    try
                    {
                        foreach (var file in Directory.EnumerateFiles(dir, pattern))
                        {
                            results.Add(file);
                        }

                        if (depth < maxDepth)
                        {
                            foreach (var sub in Directory.EnumerateDirectories(dir))
                            {
                                if (!IsReparsePoint(sub)) nextLevel.Add(sub);
                            }
                        }
                    }
                    catch {}
                }
                if (nextLevel.Count == 0) break;
                currentLevel = nextLevel;
            }

            return results;
        }

        private static List<string> EnumerateDirectoriesSafe(string rootDir, int maxDepth)
        {
            var results = new List<string>();
            if (string.IsNullOrEmpty(rootDir)) return results;
            try
            {
                if (!Directory.Exists(rootDir) || IsReparsePoint(rootDir)) return results;
            }
            catch { return results; }

            var currentLevel = new List<string> { rootDir };

            for (int depth = 0; depth <= maxDepth; depth++)
            {
                var nextLevel = new List<string>();
                foreach (var dir in currentLevel)
                {
                    try
                    {
                        foreach (var sub in Directory.EnumerateDirectories(dir))
                        {
                            results.Add(sub);
                            if (depth < maxDepth && !IsReparsePoint(sub))
                            {
                                nextLevel.Add(sub);
                            }
                        }
                    }
                    catch {}
                }
                if (nextLevel.Count == 0) break;
                currentLevel = nextLevel;
            }

            return results;
        }

        private static string GetSignerSubject(string filePath)
        {
            if (string.IsNullOrEmpty(filePath)) return "";
            object cert = null;
            try
            {
                MethodInfo method = typeof(X509Certificate).GetMethod("CreateFromSignedFile", new Type[] { typeof(string) });
                if (method != null)
                {
                    cert = method.Invoke(null, new object[] { filePath });
                    if (cert != null)
                    {
                        PropertyInfo prop = cert.GetType().GetProperty("Subject");
                        if (prop != null)
                        {
                            return prop.GetValue(cert, null) as string ?? "";
                        }
                    }
                }
            }
            catch {}
            finally
            {
                IDisposable disp = cert as IDisposable;
                if (disp != null)
                {
                    try { disp.Dispose(); } catch {}
                }
            }
            return "";
        }

        private static readonly HashSet<string> _protectedSystemProcNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "system", "idle", "registry", "memory compression", "vmmem", "vmmemwsl",
            "smss", "csrss", "wininit", "services", "lsass", "lsm", "winlogon",
            "dwm", "fontdrvhost", "audiodg", "sihost", "ctfmon", "spoolsv", "msdtc",
            "svchost", "explorer", "conhost", "openconsole", "windowsterminal",
            "cmd", "powershell", "pwsh", "code", "antigravity"
        };

        private static bool IsProtectedSystemOrHostProcess(int pid, string procName)
        {
            if (pid <= 4) return true;
            try
            {
                if (pid == Process.GetCurrentProcess().Id) return true;
            }
            catch {}
            if (string.IsNullOrWhiteSpace(procName)) return false;
            return _protectedSystemProcNames.Contains(procName.Trim());
        }

        private static bool IsSafeLockTargetDirectory(string norm)
        {
            if (string.IsNullOrWhiteSpace(norm) || norm.Length <= 3) return false;
            try
            {
                string full = Path.GetFullPath(norm).TrimEnd('\\');
                if (full.Length <= 3) return false;
                var blocked = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                string[] envPaths = new string[]
                {
                    Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                    Environment.GetFolderPath(Environment.SpecialFolder.System),
                    Environment.GetFolderPath(Environment.SpecialFolder.SystemX86),
                    Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                    Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                    Environment.GetEnvironmentVariable("ProgramW6432"),
                    Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)
                };
                foreach (string ep in envPaths)
                {
                    if (!string.IsNullOrWhiteSpace(ep))
                    {
                        blocked.Add(ep.Trim().TrimEnd('\\'));
                    }
                }
                string localProg = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                if (!string.IsNullOrWhiteSpace(localProg))
                {
                    blocked.Add(Path.Combine(localProg, "Programs").TrimEnd('\\'));
                }
                string sysDrive = Path.GetPathRoot(full);
                if (!string.IsNullOrWhiteSpace(sysDrive))
                {
                    blocked.Add(Path.Combine(sysDrive, "Users").TrimEnd('\\'));
                }
                return !blocked.Contains(full);
            }
            catch
            {
                return false;
            }
        }

        private static Dictionary<int, string> GetRestartManagerLockingPids(string targetPath)
        {
            var result = new Dictionary<int, string>();
            if (string.IsNullOrWhiteSpace(targetPath)) return result;

            var filesToCheck = new List<string>();
            if (File.Exists(targetPath))
            {
                filesToCheck.Add(targetPath);
            }
            else if (Directory.Exists(targetPath))
            {
                var secondary = new List<string>();
                try
                {
                    foreach (string f in EnumerateFilesSafe(targetPath, "*", 6))
                    {
                        string ext = Path.GetExtension(f) ?? "";
                        if (string.Equals(ext, ".exe", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".dll", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".sys", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".ocx", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".db", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".sqlite", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".dat", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".lock", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".log", StringComparison.OrdinalIgnoreCase))
                        {
                            filesToCheck.Add(f);
                            if (filesToCheck.Count >= 80) break;
                        }
                        else if (secondary.Count < 40)
                        {
                            secondary.Add(f);
                        }
                    }
                }
                catch {}

                foreach (string sf in secondary)
                {
                    if (filesToCheck.Count >= 80) break;
                    filesToCheck.Add(sf);
                }
            }

            if (filesToCheck.Count == 0) return result;

            uint session = 0;
            bool sessionStarted = false;
            try
            {
                string key = Guid.NewGuid().ToString("N");
                if (RmStartSession(out session, 0, key) != 0)
                {
                    return result;
                }
                sessionStarted = true;

                string[] arr = filesToCheck.ToArray();
                if (RmRegisterResources(session, (uint)arr.Length, arr, 0, null, 0, null) != 0)
                {
                    return result;
                }

                uint procInfoNeeded = 0;
                uint procInfo = 0;
                uint rebootReasons = 0;
                int rmRes = RmGetList(session, out procInfoNeeded, ref procInfo, null, ref rebootReasons);
                if (rmRes == ERROR_MORE_DATA && procInfoNeeded > 0)
                {
                    RM_PROCESS_INFO[] infos = new RM_PROCESS_INFO[procInfoNeeded];
                    procInfo = procInfoNeeded;
                    rmRes = RmGetList(session, out procInfoNeeded, ref procInfo, infos, ref rebootReasons);
                    if (rmRes == 0)
                    {
                        for (int i = 0; i < (int)procInfo && i < infos.Length; i++)
                        {
                            int pid = infos[i].Process.dwProcessId;
                            if (pid > 4 && !result.ContainsKey(pid))
                            {
                                result[pid] = infos[i].strAppName ?? "";
                            }
                        }
                    }
                }
            }
            catch {}
            finally
            {
                if (sessionStarted)
                {
                    try { RmEndSession(session); } catch {}
                }
            }
            return result;
        }

        private static HashSet<string> CollectExeBaseNamesInDirectory(string dir)
        {
            var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var genericNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "setup", "install", "installer", "uninstall", "uninst", "unins000", "unins001",
                "update", "updater", "helper", "launcher", "crashhandler", "reporter", "service"
            };
            try
            {
                int seen = 0;
                foreach (string exeFile in EnumerateFilesSafe(dir, "*.exe", 4))
                {
                    string bn = Path.GetFileNameWithoutExtension(exeFile);
                    if (!string.IsNullOrWhiteSpace(bn) && bn.Length >= 3 && !genericNames.Contains(bn))
                    {
                        names.Add(bn);
                    }
                    seen++;
                    if (seen >= 40) break;
                }
            }
            catch {}
            return names;
        }

        private static bool TryTaskkillPidTree(int pid)
        {
            try
            {
                var psi = new ProcessStartInfo("taskkill.exe", "/F /T /PID " + pid.ToString());
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                using (var tp = Process.Start(psi))
                {
                    if (tp != null)
                    {
                        tp.WaitForExit(2500);
                        if (tp.ExitCode == 0) return true;
                    }
                }
            }
            catch {}
            try
            {
                using (Process checkP = Process.GetProcessById(pid))
                {
                    return checkP.HasExited;
                }
            }
            catch
            {
                return true;
            }
        }

        public static bool MoveToRecycleBinSilently(string targetPath)
        {
            if (string.IsNullOrWhiteSpace(targetPath)) return false;
            string norm = targetPath.Trim().TrimEnd('\\');
            if (norm.Length <= 3) return false;
            if (!File.Exists(norm) && !Directory.Exists(norm)) return true;

            try
            {
                ushort flags = (ushort)(FOF_SILENT | FOF_NOCONFIRMATION | FOF_ALLOWUNDO | FOF_NOERRORUI);
                string doubleNullFrom = norm + "\0\0";
                int res;
                bool aborted;

                if (IntPtr.Size == 8)
                {
                    var op64 = new SHFILEOPSTRUCT_X64();
                    op64.hwnd = IntPtr.Zero;
                    op64.wFunc = FO_DELETE;
                    op64.pFrom = doubleNullFrom;
                    op64.pTo = null;
                    op64.fFlags = flags;
                    op64.fAnyOperationsAborted = false;
                    op64.hNameMappings = IntPtr.Zero;
                    op64.lpszProgressTitle = null;
                    res = SHFileOperationX64(ref op64);
                    aborted = op64.fAnyOperationsAborted;
                }
                else
                {
                    var op86 = new SHFILEOPSTRUCT_X86();
                    op86.hwnd = IntPtr.Zero;
                    op86.wFunc = FO_DELETE;
                    op86.pFrom = doubleNullFrom;
                    op86.pTo = null;
                    op86.fFlags = flags;
                    op86.fAnyOperationsAborted = false;
                    op86.hNameMappings = IntPtr.Zero;
                    op86.lpszProgressTitle = null;
                    res = SHFileOperationX86(ref op86);
                    aborted = op86.fAnyOperationsAborted;
                }

                return (res == 0 && !aborted && !File.Exists(norm) && !Directory.Exists(norm));
            }
            catch
            {
                return false;
            }
        }

        public static ForceStopReport ForceStopDirectoryLockers(string targetPath)
        {
            return ForceStopDirectoryLockers(targetPath, true);
        }

        public static ForceStopReport ForceStopDirectoryLockers(string targetPath, bool includeServicesAndTasks)
        {
            var report = new ForceStopReport();
            if (string.IsNullOrWhiteSpace(targetPath)) return report;

            string norm = targetPath.Trim().TrimEnd('\\');
            if (norm.Length <= 3) return report;

            bool isSingleFile = File.Exists(norm);
            bool isDirectory = !isSingleFile && Directory.Exists(norm);
            if (!isSingleFile && !isDirectory) return report;

            if (isDirectory && !IsSafeLockTargetDirectory(norm)) return report;

            string prefix = isDirectory ? (norm + "\\") : "";
            if (includeServicesAndTasks && isDirectory)
            {
                report.ServicesStoppedCount = DisableAndRemoveServicesInDirectory(norm);
                report.TasksRemovedCount = RemoveScheduledTasksInDirectory(norm);
            }

            Dictionary<int, string> rmLockers = GetRestartManagerLockingPids(norm);
            HashSet<string> dirExeNames = isDirectory ? CollectExeBaseNamesInDirectory(norm) : new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            var killedList = new List<string>();
            var deniedList = new List<string>();
            var skippedSystem = new List<string>();
            var seenNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var targetProcs = new Dictionary<int, Process>();

            Process[] procs = null;
            try { procs = Process.GetProcesses(); } catch { procs = new Process[0]; }

            foreach (Process p in procs)
            {
                bool keepProc = false;
                try
                {
                    int pid = p.Id;
                    string pName = "";
                    try { pName = p.ProcessName ?? ""; } catch {}

                    if (pid <= 4) { p.Dispose(); continue; }

                    bool rmMatched = rmLockers.ContainsKey(pid);
                    if (IsProtectedSystemOrHostProcess(pid, pName))
                    {
                        if (rmMatched && (string.Equals(pName, "explorer", StringComparison.OrdinalIgnoreCase) || string.Equals(pName, "svchost", StringComparison.OrdinalIgnoreCase)))
                        {
                            string desc = pName + " (PID " + pid.ToString() + ")";
                            if (!skippedSystem.Contains(desc)) skippedSystem.Add(desc);
                        }
                        else if (isDirectory && !rmMatched)
                        {
                            try
                            {
                                foreach (ProcessModule pm in p.Modules)
                                {
                                    string modPath = pm.FileName ?? "";
                                    if (modPath.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                                    {
                                        string desc = pName + " (" + Path.GetFileName(modPath) + ")";
                                        if (!skippedSystem.Contains(desc)) skippedSystem.Add(desc);
                                        break;
                                    }
                                }
                            }
                            catch {}
                        }
                        p.Dispose();
                        continue;
                    }

                    bool isMatch = rmMatched;
                    bool mainModAccessDenied = false;

                    if (!isMatch)
                    {
                        try
                        {
                            if (p.MainModule != null)
                            {
                                string mainPath = p.MainModule.FileName ?? "";
                                if (isSingleFile)
                                {
                                    isMatch = string.Equals(mainPath, norm, StringComparison.OrdinalIgnoreCase);
                                }
                                else if (isDirectory)
                                {
                                    isMatch = mainPath.StartsWith(prefix, StringComparison.OrdinalIgnoreCase);
                                }
                            }
                        }
                        catch (Win32Exception)
                        {
                            mainModAccessDenied = true;
                        }
                        catch {}
                    }

                    if (!isMatch && isDirectory && !mainModAccessDenied)
                    {
                        try
                        {
                            foreach (ProcessModule pm in p.Modules)
                            {
                                string modPath = pm.FileName ?? "";
                                if (modPath.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                                {
                                    isMatch = true;
                                    break;
                                }
                            }
                        }
                        catch {}
                    }

                    if (!isMatch && mainModAccessDenied && isDirectory && dirExeNames.Count > 0 && dirExeNames.Contains(pName))
                    {
                        isMatch = true;
                    }

                    if (isMatch && !targetProcs.ContainsKey(pid))
                    {
                        targetProcs[pid] = p;
                        keepProc = true;
                    }
                }
                catch {}
                finally
                {
                    if (!keepProc)
                    {
                        try { p.Dispose(); } catch {}
                    }
                }
            }

            foreach (KeyValuePair<int, Process> kvp in targetProcs)
            {
                int pid = kvp.Key;
                Process mp = kvp.Value;
                string pLabel = "PID " + pid.ToString();
                try
                {
                    if (!string.IsNullOrWhiteSpace(mp.ProcessName))
                    {
                        pLabel = mp.ProcessName + ".exe (PID " + pid.ToString() + ")";
                    }
                }
                catch {}

                bool terminated = false;
                try
                {
                    try
                    {
                        IntPtr h = mp.Handle;
                        NtSuspendProcess(h);
                    }
                    catch {}

                    mp.Kill();
                    mp.WaitForExit(1500);
                    terminated = true;
                }
                catch
                {
                    terminated = TryTaskkillPidTree(pid);
                }
                finally
                {
                    try { mp.Dispose(); } catch {}
                }

                if (terminated)
                {
                    report.KilledCount++;
                    if (seenNames.Add("K:" + pLabel)) killedList.Add(pLabel);
                }
                else
                {
                    report.AccessDeniedCount++;
                    if (seenNames.Add("D:" + pLabel)) deniedList.Add(pLabel);
                }
            }

            if (report.KilledCount > 0 || report.ServicesStoppedCount > 0)
            {
                try { Thread.Sleep(180); } catch {}
            }

            report.KilledNames = killedList.ToArray();
            report.AccessDeniedNames = deniedList.ToArray();
            report.SkippedSystemLockers = skippedSystem.ToArray();
            return report;
        }

        public static int StopProcessesInDirectory(string targetDir)
        {
            ForceStopReport rpt = ForceStopDirectoryLockers(targetDir, false);
            return rpt.KilledCount;
        }

        public static int DisableAndRemoveServicesInDirectory(string targetDir)
        {
            if (string.IsNullOrWhiteSpace(targetDir)) return 0;
            string prefix = targetDir.Trim().TrimEnd('\\') + "\\";
            if (prefix.Length <= 4) return 0;

            int neutralized = 0;
            try
            {
                using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                using (var svcRoot = baseKey.OpenSubKey(@"SYSTEM\CurrentControlSet\Services", true))
                {
                    if (svcRoot == null) return 0;
                    foreach (string svcName in svcRoot.GetSubKeyNames())
                    {
                        try
                        {
                            bool matches = false;
                            using (var sk = svcRoot.OpenSubKey(svcName, true))
                            {
                                if (sk == null) continue;
                                string imgPath = (sk.GetValue("ImagePath") as string ?? "").Trim('\"', ' ');
                                if (string.IsNullOrEmpty(imgPath)) continue;
                                if (imgPath.StartsWith(@"\??\", StringComparison.OrdinalIgnoreCase))
                                {
                                    imgPath = imgPath.Substring(4);
                                }
                                if (imgPath.IndexOf(prefix, StringComparison.OrdinalIgnoreCase) >= 0)
                                {
                                    matches = true;
                                    try { sk.SetValue("Start", 4, RegistryValueKind.DWord); } catch {}
                                    try { sk.DeleteValue("FailureActions", false); } catch {}
                                }
                            }

                            if (matches)
                            {
                                neutralized++;
                                RunHiddenSc("stop \"" + svcName + "\"");
                                RunHiddenSc("delete \"" + svcName + "\"");
                            }
                        }
                        catch {}
                    }
                }
            }
            catch {}
            return neutralized;
        }

        public static int RemoveScheduledTasksInDirectory(string targetDir)
        {
            if (string.IsNullOrWhiteSpace(targetDir)) return 0;
            string prefix = targetDir.Trim().TrimEnd('\\') + "\\";
            if (prefix.Length <= 4) return 0;

            int removed = 0;
            string tasksRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "Tasks");
            if (!Directory.Exists(tasksRoot)) return 0;

            try
            {
                foreach (string taskFile in EnumerateFilesSafe(tasksRoot, "*", 6))
                {
                    try
                    {
                        if (taskFile.IndexOf(@"\Tasks\Microsoft\Windows\", StringComparison.OrdinalIgnoreCase) >= 0)
                            continue;

                        string xml = File.ReadAllText(taskFile);
                        if (xml.IndexOf(prefix, StringComparison.OrdinalIgnoreCase) >= 0)
                        {
                            string relTaskName = taskFile.Substring(tasksRoot.Length);
                            try
                            {
                                var psi = new ProcessStartInfo("schtasks.exe", "/Delete /TN \"" + relTaskName + "\" /F");
                                psi.CreateNoWindow = true;
                                psi.UseShellExecute = false;
                                using (var p = Process.Start(psi))
                                {
                                    if (p != null) p.WaitForExit(2000);
                                }
                            }
                            catch {}
                            try
                            {
                                File.SetAttributes(taskFile, FileAttributes.Normal);
                                File.Delete(taskFile);
                            }
                            catch {}
                            removed++;
                        }
                    }
                    catch {}
                }
            }
            catch {}
            return removed;
        }

        private static void RunHiddenSc(string args)
        {
            try
            {
                var psi = new ProcessStartInfo("sc.exe", args);
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                using (var p = Process.Start(psi))
                {
                    if (p != null) p.WaitForExit(2000);
                }
            }
            catch {}
        }

        public static bool VerifyDirectoryExeOwnership(string targetDir, string[] expectedKeywords)
        {
            if (string.IsNullOrWhiteSpace(targetDir) || expectedKeywords == null || expectedKeywords.Length == 0)
                return false;
            try
            {
                if (!Directory.Exists(targetDir)) return false;
                int checkedCount = 0;
                foreach (string file in EnumerateFilesSafe(targetDir, "*", 4))
                {
                    string ext = Path.GetExtension(file);
                    if (!string.Equals(ext, ".exe", StringComparison.OrdinalIgnoreCase) &&
                        !string.Equals(ext, ".dll", StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    checkedCount++;
                    if (checkedCount > 15) break;

                    try
                    {
                        FileVersionInfo fvi = FileVersionInfo.GetVersionInfo(file);
                        string certSubj = GetSignerSubject(file);

                        string combined = (fvi.ProductName ?? "") + " | " + (fvi.CompanyName ?? "") + " | " + (fvi.FileDescription ?? "") + " | " + (fvi.InternalName ?? "") + " | " + (fvi.OriginalFilename ?? "") + " | " + certSubj;
                        foreach (string kw in expectedKeywords)
                        {
                            if (string.IsNullOrWhiteSpace(kw) || kw.Length < 2) continue;
                            if (combined.IndexOf(kw, StringComparison.OrdinalIgnoreCase) >= 0)
                            {
                                return true;
                            }
                        }
                    }
                    catch {}
                }
            }
            catch {}
            return false;
        }

        public static string[] ExtractBinaryAndCertTokens(string targetDir, string uninstallString, string displayIcon)
        {
            var results = new List<string>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var ignoreWords = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "uninstall", "uninst", "unins000", "unins001", "setup", "install", "installer",
                "update", "updater", "helper", "launcher", "client", "app", "application",
                "main", "bin", "x64", "x86", "win32", "win64", "release", "debug", "program files",
                "program files (x86)", "common files", "programs", "appdata", "local", "roaming",
                "windows", "system32", "temp", "microsoft", "corporation", "company", "limited",
                "ltd", "inc", "llc", "corp", "co", "technology", "software", "network", "beijing",
                "shenzhen", "guangzhou", "shanghai", "hangzhou", "china"
            };

            string[] exeSources = new string[] { uninstallString, displayIcon };
            foreach (string src in exeSources)
            {
                string exe = ExtractExePath(src);
                if (!string.IsNullOrWhiteSpace(exe))
                {
                    try
                    {
                        string baseName = Path.GetFileNameWithoutExtension(exe);
                        if (!string.IsNullOrWhiteSpace(baseName) && baseName.Length >= 3 && !ignoreWords.Contains(baseName))
                        {
                            if (seen.Add(baseName)) results.Add(baseName);
                        }
                    }
                    catch {}
                }
            }

            if (!string.IsNullOrWhiteSpace(targetDir) && Directory.Exists(targetDir))
            {
                try
                {
                    int count = 0;
                    foreach (string file in EnumerateFilesSafe(targetDir, "*.exe", 4))
                    {
                        count++;
                        if (count > 8) break;
                        string fn = Path.GetFileNameWithoutExtension(file);
                        if (!string.IsNullOrWhiteSpace(fn) && fn.Length >= 3 && !ignoreWords.Contains(fn))
                        {
                            if (seen.Add(fn)) results.Add(fn);
                        }

                        try
                        {
                            FileVersionInfo fvi = FileVersionInfo.GetVersionInfo(file);
                            string[] fields = new string[] { fvi.ProductName, fvi.CompanyName, fvi.InternalName };
                            foreach (string f in fields)
                            {
                                if (string.IsNullOrWhiteSpace(f)) continue;
                                string clean = f.Replace(".exe", "").Replace(".dll", "").Trim();
                                if (clean.Length >= 3 && clean.Length <= 30 && !ignoreWords.Contains(clean))
                                {
                                    if (seen.Add(clean)) results.Add(clean);
                                }
                            }
                        }
                        catch {}

                        try
                        {
                            string certSubj = GetSignerSubject(file);
                            if (!string.IsNullOrWhiteSpace(certSubj))
                            {
                                string[] parts = certSubj.Split(',');
                                foreach (string part in parts)
                                {
                                    string p = part.Trim();
                                    if (p.StartsWith("CN=", StringComparison.OrdinalIgnoreCase) ||
                                        p.StartsWith("O=", StringComparison.OrdinalIgnoreCase))
                                    {
                                        string val = p.Substring(p.IndexOf('=') + 1).Trim('\"', ' ');
                                        string[] words = val.Split(new char[] { ' ', '(', ')', '.', ',', '-' }, StringSplitOptions.RemoveEmptyEntries);
                                        foreach (string w in words)
                                        {
                                            if (w.Length >= 4 && !ignoreWords.Contains(w))
                                            {
                                                if (seen.Add(w)) results.Add(w);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        catch {}
                    }
                }
                catch {}
            }

            return results.ToArray();
        }

        public static bool ForceDeleteDirectory(string targetDir, out int rebootScheduledCount)
        {
            rebootScheduledCount = 0;
            if (string.IsNullOrWhiteSpace(targetDir)) return false;
            string norm = targetDir.Trim().TrimEnd('\\');
            if (norm.Length <= 3) return false;

            if (File.Exists(norm))
            {
                try
                {
                    File.SetAttributes(norm, FileAttributes.Normal);
                    File.Delete(norm);
                    return true;
                }
                catch
                {
                    ForceStopDirectoryLockers(norm, false);
                    try
                    {
                        File.SetAttributes(norm, FileAttributes.Normal);
                        File.Delete(norm);
                        return true;
                    }
                    catch
                    {
                        if (MoveFileEx(norm, null, MOVEFILE_DELAY_UNTIL_REBOOT))
                        {
                            rebootScheduledCount++;
                            return true;
                        }
                        return false;
                    }
                }
            }

            if (!Directory.Exists(norm)) return true;

            if (IsReparsePoint(norm))
            {
                try
                {
                    Directory.Delete(norm, false);
                    return true;
                }
                catch
                {
                    if (MoveFileEx(norm, null, MOVEFILE_DELAY_UNTIL_REBOOT))
                    {
                        rebootScheduledCount++;
                        return true;
                    }
                    return false;
                }
            }

            ForceStopDirectoryLockers(norm, true);

            try
            {
                foreach (string file in EnumerateFilesSafe(norm, "*", 10))
                {
                    try
                    {
                        File.SetAttributes(file, FileAttributes.Normal);
                        File.Delete(file);
                    }
                    catch
                    {
                        string deadPath = file + ".dead_" + Guid.NewGuid().ToString("N").Substring(0, 6);
                        try
                        {
                            File.Move(file, deadPath);
                            if (MoveFileEx(deadPath, null, MOVEFILE_DELAY_UNTIL_REBOOT))
                            {
                                rebootScheduledCount++;
                            }
                        }
                        catch
                        {
                            if (MoveFileEx(file, null, MOVEFILE_DELAY_UNTIL_REBOOT))
                            {
                                rebootScheduledCount++;
                            }
                        }
                    }
                }
            }
            catch {}

            try
            {
                List<string> subDirs = EnumerateDirectoriesSafe(norm, 10);
                subDirs.Sort(delegate(string a, string b) { return b.Length.CompareTo(a.Length); });
                foreach (string sd in subDirs)
                {
                    try
                    {
                        if (IsReparsePoint(sd))
                        {
                            Directory.Delete(sd, false);
                        }
                        else
                        {
                            File.SetAttributes(sd, FileAttributes.Normal);
                            Directory.Delete(sd, false);
                        }
                    }
                    catch
                    {
                        MoveFileEx(sd, null, MOVEFILE_DELAY_UNTIL_REBOOT);
                    }
                }
            }
            catch {}

            try
            {
                File.SetAttributes(norm, FileAttributes.Normal);
                Directory.Delete(norm, false);
                return true;
            }
            catch
            {
                if (MoveFileEx(norm, null, MOVEFILE_DELAY_UNTIL_REBOOT))
                {
                    rebootScheduledCount++;
                    return true;
                }
                return false;
            }
        }

        public static long BackupDirectorySnapshot(string sourceDir, string backupDir, long maxTotalBytes)
        {
            return BackupDirectorySnapshot(sourceDir, backupDir, maxTotalBytes, false);
        }

        public static long BackupDirectorySnapshot(string sourceDir, string backupDir, long maxTotalBytes, bool isInstallDir)
        {
            if (string.IsNullOrWhiteSpace(sourceDir) || string.IsNullOrWhiteSpace(backupDir))
                return 0L;
            try
            {
                if (!Directory.Exists(sourceDir) || IsReparsePoint(sourceDir)) return 0L;
            }
            catch { return 0L; }

            if (maxTotalBytes <= 0) maxTotalBytes = 104857600L;

            var skipExts = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                ".exe", ".dll", ".sys", ".pdb", ".pak", ".node", ".obj", ".iso", ".vmdk", ".asar", ".msi", ".cab", ".manifest", ".cat", ".mum"
            };
            var skipFileNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "icudtl.dat", "v8_context_snapshot.bin", "snapshot_blob.bin",
                "chrome_100_percent.pak", "chrome_200_percent.pak", "resources.pak",
                "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml"
            };
            var installAllowExts = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                ".ini", ".cfg", ".conf", ".config", ".toml", ".yaml", ".yml",
                ".lic", ".license", ".key", ".reg", ".db", ".sqlite", ".sqlite3",
                ".json", ".xml", ".txt", ".dat", ".bin", ".properties", ".prefs"
            };
            var skipDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache",
                "GrShaderCache", "ShaderCache", "Crashpad", "logs", "Log", "temp", "tmp",
                "blob_storage", "Service Worker", "packages", "IndexedDB", "WebStorage",
                "locales", "swiftshader", "Dictionaries", "node_modules"
            };

            long totalBytes = 0L;
            int srcLen = sourceDir.TrimEnd('\\').Length;

            var currentLevel = new List<string> { sourceDir };
            for (int depth = 0; depth <= 8; depth++)
            {
                var nextLevel = new List<string>();
                foreach (var dir in currentLevel)
                {
                    try
                    {
                        foreach (var file in Directory.EnumerateFiles(dir))
                        {
                            try
                            {
                                string fn = Path.GetFileName(file) ?? "";
                                if (skipFileNames.Contains(fn)) continue;
                                if (fn.EndsWith(".deps.json", StringComparison.OrdinalIgnoreCase) ||
                                    fn.EndsWith(".runtimeconfig.json", StringComparison.OrdinalIgnoreCase) ||
                                    fn.EndsWith(".runtimeconfig.dev.json", StringComparison.OrdinalIgnoreCase))
                                {
                                    continue;
                                }

                                string ext = Path.GetExtension(file);
                                if (!string.IsNullOrEmpty(ext) && skipExts.Contains(ext))
                                    continue;

                                if (isInstallDir)
                                {
                                    if (string.IsNullOrEmpty(ext) || !installAllowExts.Contains(ext))
                                        continue;
                                }

                                var fi = new FileInfo(file);
                                if (fi.Length > 20971520L) continue;
                                if (totalBytes + fi.Length > maxTotalBytes) continue;

                                string relPath = file.Substring(srcLen).TrimStart('\\');
                                string destFile = Path.Combine(backupDir, relPath);
                                string destDir = Path.GetDirectoryName(destFile);
                                if (!string.IsNullOrEmpty(destDir) && !Directory.Exists(destDir))
                                {
                                    Directory.CreateDirectory(destDir);
                                }

                                File.Copy(file, destFile, true);
                                totalBytes += fi.Length;
                            }
                            catch {}
                        }

                        if (depth < 8)
                        {
                            foreach (var sub in Directory.EnumerateDirectories(dir))
                            {
                                if (IsReparsePoint(sub)) continue;
                                string subName = Path.GetFileName(sub) ?? "";
                                if (skipDirs.Contains(subName)) continue;
                                if (Regex.IsMatch(subName, @"^(app-\d+(\.\d+)+|\d+\.\d+\.\d+(\.\d+)?)$", RegexOptions.IgnoreCase)) continue;
                                nextLevel.Add(sub);
                            }
                        }
                    }
                    catch {}
                }
                if (nextLevel.Count == 0) break;
                currentLevel = nextLevel;
            }

            return totalBytes;
        }

        public static int RestoreDirectorySnapshot(string backupDir, string targetDir)
        {
            if (string.IsNullOrWhiteSpace(backupDir) || string.IsNullOrWhiteSpace(targetDir))
                return 0;
            try
            {
                if (!Directory.Exists(backupDir)) return 0;
            }
            catch { return 0; }

            int restoredCount = 0;
            int bkpLen = backupDir.TrimEnd('\\').Length;

            var currentLevel = new List<string> { backupDir };
            for (int depth = 0; depth <= 8; depth++)
            {
                var nextLevel = new List<string>();
                foreach (var dir in currentLevel)
                {
                    try
                    {
                        foreach (var file in Directory.EnumerateFiles(dir))
                        {
                            try
                            {
                                string relPath = file.Substring(bkpLen).TrimStart('\\');
                                string destFile = Path.Combine(targetDir, relPath);
                                if (File.Exists(destFile)) continue;
                                string destDir = Path.GetDirectoryName(destFile);
                                if (!string.IsNullOrEmpty(destDir) && !Directory.Exists(destDir))
                                {
                                    Directory.CreateDirectory(destDir);
                                }

                                File.Copy(file, destFile, false);
                                restoredCount++;
                            }
                            catch {}
                        }

                        if (depth < 8)
                        {
                            foreach (var sub in Directory.EnumerateDirectories(dir))
                            {
                                nextLevel.Add(sub);
                            }
                        }
                    }
                    catch {}
                }
                if (nextLevel.Count == 0) break;
                currentLevel = nextLevel;
            }

            return restoredCount;
        }

        public static string DetectInstallerFramework(string exePath)
        {
            if (string.IsNullOrWhiteSpace(exePath)) return "";
            try
            {
                if (!File.Exists(exePath)) return "";

                try
                {
                    string datPath = Path.ChangeExtension(exePath, ".dat");
                    if (!string.IsNullOrEmpty(datPath) && File.Exists(datPath))
                    {
                        using (var dfs = new FileStream(datPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                        {
                            byte[] hdr = new byte[(int)Math.Min(64L, dfs.Length)];
                            int read = dfs.Read(hdr, 0, hdr.Length);
                            if (read > 0)
                            {
                                string hdrAscii = System.Text.Encoding.ASCII.GetString(hdr, 0, read);
                                if (hdrAscii.IndexOf("Inno Setup Uninstall Log", StringComparison.OrdinalIgnoreCase) >= 0)
                                    return "InnoSetup";
                            }
                        }
                    }
                }
                catch {}

                string fileName = Path.GetFileName(exePath) ?? "";
                if (fileName.Equals("Update.exe", StringComparison.OrdinalIgnoreCase))
                    return "Squirrel";

                using (var fs = new FileStream(exePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                {
                    int headLen = (int)Math.Min(1048576L, fs.Length);
                    byte[] headBuf = new byte[headLen];
                    int headRead = fs.Read(headBuf, 0, headLen);
                    string matched = DetectFrameworkFromBuffer(headBuf, headRead);
                    if (!string.IsNullOrEmpty(matched)) return matched;

                    if (fs.Length > 1048576L)
                    {
                        int tailLen = (int)Math.Min(524288L, fs.Length - headLen);
                        if (tailLen > 0)
                        {
                            fs.Seek(-tailLen, SeekOrigin.End);
                            byte[] tailBuf = new byte[tailLen];
                            int tailRead = fs.Read(tailBuf, 0, tailLen);
                            matched = DetectFrameworkFromBuffer(tailBuf, tailRead);
                            if (!string.IsNullOrEmpty(matched)) return matched;
                        }
                    }
                }

                try
                {
                    var fvi = FileVersionInfo.GetVersionInfo(exePath);
                    string desc = (fvi.FileDescription ?? "") + " " + (fvi.ProductName ?? "");
                    if (desc.IndexOf("Inno Setup", StringComparison.OrdinalIgnoreCase) >= 0)
                        return "InnoSetup";
                }
                catch {}
            }
            catch {}
            return "";
        }

        private static string DetectFrameworkFromBuffer(byte[] buf, int len)
        {
            if (buf == null || len <= 0) return "";
            string ascii = System.Text.Encoding.ASCII.GetString(buf, 0, len);
            string uni = System.Text.Encoding.Unicode.GetString(buf, 0, len);

            if (ascii.IndexOf("NullsoftInst", StringComparison.Ordinal) >= 0 ||
                ascii.IndexOf("Nullsoft Install System", StringComparison.OrdinalIgnoreCase) >= 0 ||
                uni.IndexOf("Nullsoft Install System", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return "NSIS";
            }
            if (ascii.IndexOf(".wixburn", StringComparison.OrdinalIgnoreCase) >= 0 ||
                ascii.IndexOf("WiX Toolset", StringComparison.OrdinalIgnoreCase) >= 0 ||
                uni.IndexOf("WiX Toolset", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return "WiX";
            }
            if (ascii.IndexOf("BitRock InstallBuilder", StringComparison.OrdinalIgnoreCase) >= 0 ||
                uni.IndexOf("BitRock InstallBuilder", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return "BitRock";
            }
            if (ascii.IndexOf("Inno Setup", StringComparison.OrdinalIgnoreCase) >= 0 ||
                ascii.IndexOf("InnoSetup", StringComparison.OrdinalIgnoreCase) >= 0 ||
                uni.IndexOf("Inno Setup", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return "InnoSetup";
            }
            return "";
        }
    }
}
