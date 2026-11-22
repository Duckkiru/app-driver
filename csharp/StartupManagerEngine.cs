using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using Microsoft.Win32;

namespace DuckUtil {
    public sealed class StartupEntry {
        public string Id { get; set; }
        public string Name { get; set; }
        public string DisplayName { get; set; }
        public string Publisher { get; set; }
        public string RawCommand { get; set; }
        public string ResolvedExePath { get; set; }
        public string SecondaryTargetPath { get; set; }
        public string SourceKind { get; set; }
        public string RegistryHive { get; set; }
        public string RegistryPath { get; set; }
        public string RegistryValueName { get; set; }
        public string ApprovedHive { get; set; }
        public string ApprovedPath { get; set; }
        public string ApprovedValueName { get; set; }
        public string FolderFilePath { get; set; }
        public string PackageFamilyName { get; set; }
        public string PackageFullName { get; set; }
        public string TaskId { get; set; }
        public int UwpState { get; set; }
        public string ScheduledTaskPath { get; set; }
        public string ServiceName { get; set; }
        public int ServiceOrigStart { get; set; }
        public bool ServiceDelayedAuto { get; set; }
        public string TriggerInfo { get; set; }
        public string OrphanReason { get; set; }
        public bool IsOrphanApprovedGhost { get; set; }
        public string LogoPath { get; set; }
        public string IconHintPath { get; set; }
        public bool Enabled { get; set; }
        public bool IsPolicyLocked { get; set; }
        public string LockKind { get; set; }
        public bool IsOrphan { get; set; }
        public string ProtectionKind { get; set; }
        public string ImpactLevel { get; set; }
        public bool RequiresAdmin { get; set; }
        public bool CanDelete { get; set; }
        public bool CanToggle { get; set; }
        public bool MetadataHydrated { get; set; }
    }

    public sealed class StartupOpResult {
        public bool Success { get; set; }
        public bool RequiresAdminError { get; set; }
        public string Message { get; set; }
    }

    public sealed class StartupOrphanCleanupResult {
        public int RemovedCount { get; set; }
        public int SkippedAdminCount { get; set; }
        public string[] RemovedKeys { get; set; }
    }

    public sealed class StartupHydratedPatch {
        public string Id { get; set; }
        public string DisplayName { get; set; }
        public string Publisher { get; set; }
        public string ProtectionKind { get; set; }
        public string ImpactLevel { get; set; }
        public BitmapSource IconBitmap { get; set; }
    }

    public sealed class StartupRowVisual {
        public StartupEntry Entry { get; set; }
        public System.Windows.Controls.Border Row { get; set; }
        public System.Windows.Controls.Primitives.ToggleButton Toggle { get; set; }
        public System.Windows.Controls.Image IconImage { get; set; }
        public System.Windows.Controls.TextBlock TitleText { get; set; }
        public System.Windows.Controls.StackPanel BadgePanel { get; set; }
        public System.Windows.Controls.TextBlock SubText { get; set; }
        public System.Windows.Controls.TextBlock ImpactText { get; set; }
        public System.Windows.Controls.Button OpenButton { get; set; }
        public System.Windows.Controls.Button DeleteButton { get; set; }
        public string SearchText { get; set; }
    }

    public static class StartupManagerEngine {
        private const string RegRunPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string RegRunWow32Path = @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";
        private const string RegRunOncePath = @"Software\Microsoft\Windows\CurrentVersion\RunOnce";
        private const string RegRunOnceWow32Path = @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce";
        private const string RegPolicyRunPath = @"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run";
        private const string RegApprovedRunPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
        private const string RegApprovedRun32Path = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32";
        private const string RegApprovedFolderPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder";
        private const string RegSystemAppDataPath = @"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData";
        private const string RegRepoPackagesUserPath = @"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages";
        private const string RegRepoPackagesMachPath = @"SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages";
        private const string RegServicesPath = @"SYSTEM\CurrentControlSet\Services";

        private const uint SC_MANAGER_CONNECT = 0x0001u;
        private const uint SERVICE_QUERY_CONFIG = 0x0001u;
        private const uint SERVICE_CHANGE_CONFIG = 0x0002u;
        private const uint SERVICE_DELETE = 0x00010000u;
        private const uint SERVICE_NO_CHANGE = 0xFFFFFFFFu;
        private const uint SERVICE_AUTO_START = 2u;
        private const uint SERVICE_DEMAND_START = 3u;

        private static readonly ConcurrentDictionary<string, BitmapSource> _iconCache =
            new ConcurrentDictionary<string, BitmapSource>(StringComparer.OrdinalIgnoreCase);

        private static readonly ConcurrentDictionary<string, string> _certOrgCache =
            new ConcurrentDictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        private static readonly string[] ValidStartupExtensions = new string[] {
            ".lnk", ".url", ".exe", ".bat", ".cmd", ".vbs", ".ps1", ".js", ".wsf", ".hta", ".msc"
        };

        private static readonly string[] CommandExecExtensions = new string[] {
            ".exe", ".com", ".bat", ".cmd", ".vbs", ".msc", ".ps1", ".scr", ".js", ".wsf", ".hta"
        };

        private static readonly string[] SecondaryTargetExtensions = new string[] {
            ".dll", ".ocx", ".cpl", ".vbs", ".vbe", ".js", ".jse", ".wsf", ".ps1", ".bat", ".cmd", ".hta", ".py", ".pyw", ".jar", ".exe"
        };

        private static readonly Regex RxStartupTaskEl = new Regex(
            @"<(?:\w+:)?StartupTask\b([^>]*)/?>",
            RegexOptions.IgnoreCase);

        private static readonly Regex RxAttrTaskId = new Regex(
            @"\bTaskId\s*=\s*[""']([^""']+)[""']",
            RegexOptions.IgnoreCase);

        private static readonly Regex RxAttrDisplayName = new Regex(
            @"\bDisplayName\s*=\s*[""']([^""']+)[""']",
            RegexOptions.IgnoreCase);

        private static readonly Regex RxAttrEnabled = new Regex(
            @"\bEnabled\s*=\s*[""']([^""']+)[""']",
            RegexOptions.IgnoreCase);

        private static readonly Regex RxAttrExecutable = new Regex(
            @"\bExecutable\s*=\s*[""']([^""']+\.exe)[""']",
            RegexOptions.IgnoreCase);

        private static readonly Regex RxDisplayName = new Regex(
            @"<DisplayName>\s*([^<]+?)\s*</DisplayName>",
            RegexOptions.IgnoreCase);

        private static readonly Regex RxPublisherName = new Regex(
            @"<PublisherDisplayName>\s*([^<]+?)\s*</PublisherDisplayName>",
            RegexOptions.IgnoreCase);

        private static readonly Regex RxLogo = new Regex(
            @"(?:Square44x44Logo|Square150x150Logo)\s*=\s*[""']([^""']+)[""']|<Logo>\s*([^<]+?)\s*</Logo>",
            RegexOptions.IgnoreCase);

        private static readonly Regex RxTrailingUrl = new Regex(
            @"\s*-\s*https?://\S+\s*$",
            RegexOptions.IgnoreCase);

        private static readonly Regex RxSidSuffix = new Regex(
            @"-S-1-5-[0-9-]+$",
            RegexOptions.IgnoreCase);

        private static readonly Regex RxXmlLogonType = new Regex(
            @"<LogonType>\s*([^<]+?)\s*</LogonType>",
            RegexOptions.IgnoreCase);

        private static readonly Regex RxSystemProtection = new Regex(
            @"(?:securityhealth|sechealth|windows\s*defender|microsoft\s*defender|msascuil|\bctfmon\b|" +
            @"kaspersky|bitdefender|malwarebytes|avast|\bavg\b|\beset\b|\bekrn\b|norton|mcafee|sophos|trendmicro|crowdstrike|sentinel)",
            RegexOptions.IgnoreCase);

        private static readonly Regex RxOemProtection = new Regex(
            @"(?:rtkaud|realtek|\bdolby\b|nahimic|waves\s*maxx|dtsx|dtsaudio|" +
            @"lenovo|vantage|legion|thinkpad|\basus\b|armoury|myasus|atkex|" +
            @"msicenter|msi\s*center|dragoncenter|dragon\s*center|nitrosense|predatorsense|\bacer\b|" +
            @"alienware|\bawcc\b|dellpower|dell\s*support|hpomen|hp\s*omen|hpsystemevent|gigabyte|\baorus\b|" +
            @"nvdisplay|nvcontainer|nvidia|advanced\s*micro\s*devices|\bamd\b|amdnoise|amdrsserv|rsservcmd|\bcncmd\b|radeon|" +
            @"igfx|intel\(r\)|intel\s+corp|intel\s+graphics|intel\s+rapid|" +
            @"syntpenh|synaptics|etdctrl|\belan\s*touch|fxsound|vanguard|\bvgtray\b|officeclicktorun)",
            RegexOptions.IgnoreCase);

        private static readonly Regex RxHighImpact = new Regex(
            @"(?:docker|discord|\bslack\b|\bteams\b|ms-teams|spotify|figma|notion|" +
            @"vscode|\bcode\.exe\b|\bsteam\b|epicgames|\briot\b|vanguard|battle\.net|" +
            @"ea\s*desktop|eadesktop|ubisoft|wargaming|curseforge|overwolf|" +
            @"onedrive|googledrive|dropbox|creative\s*cloud|ccxprocess|adobe|" +
            @"wallpaper32|wallpaper64|wallpaperengine|\bblitz\b|porofessor|\bmedal\b|" +
            @"obs64|streamlabs|\bicue\b|lghub|powertoys|httpd\.exe|apache2|mysqld\.exe|" +
            @"nvcontainer|officeclicktorun|chromoting|codex|chatgpt)",
            RegexOptions.IgnoreCase);

        private static readonly Regex RxMediumImpact = new Regex(
            @"(?:msedge|edgeupdate|chrome|\bbrave\b|firefox|opera|\bzalo\b|telegram|viber|" +
            @"messenger|whatsapp|cloudflare|\bwarp\b|proton|radmin|rvcontrol|tailscale|" +
            @"zerotier|nordvpn|surfshark|vantage|legion|armoury|myasus|" +
            @"msicenter|dragoncenter|nitrosense|predatorsense|\bawcc\b|alienware|" +
            @"hp\s*omen|synapse|razer|nvidia|advanced\s*micro\s*devices|radeon|cncmd|rsservcmd|" +
            @"yourphone|crossdevice|pcmanager|windowsmaster|freedownloadmanager|\bfdm\b|\bidm\b|" +
            @"qbittorrent|utorrent|\bjava\b|jusched|rustdesk|commandpalette|foxit|updater\.exe|rtkaud|officec2rclient)",
            RegexOptions.IgnoreCase);

        [DllImport("shell32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern IntPtr CommandLineToArgvW(string lpCmdLine, out int pNumArgs);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LocalFree(IntPtr hMem);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern uint GetLongPathNameW(string lpszShortPath, StringBuilder lpszLongPath, uint cchBuffer);

        [DllImport("shlwapi.dll", BestFitMapping = false, CharSet = CharSet.Unicode, ExactSpelling = true, ThrowOnUnmappableChar = true)]
        private static extern int SHLoadIndirectString(string pszSource, StringBuilder pszOutBuf, int cchOutBuf, IntPtr ppvReserved);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern IntPtr OpenSCManagerW(string lpMachineName, string lpDatabaseName, uint dwDesiredAccess);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern IntPtr OpenServiceW(IntPtr hSCManager, string lpServiceName, uint dwDesiredAccess);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ChangeServiceConfigW(
            IntPtr hService,
            uint dwServiceType,
            uint dwStartType,
            uint dwErrorControl,
            string lpBinaryPathName,
            string lpLoadOrderGroup,
            IntPtr lpdwTagId,
            string lpDependencies,
            string lpServiceStartName,
            string lpPassword,
            string lpDisplayName);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DeleteService(IntPtr hService);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseServiceHandle(IntPtr hSCObject);

        [ComImport]
        [Guid("00021401-0000-0000-C000-000000000046")]
        private class ShellLinkCoClass {
        }

        [ComImport]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        [Guid("000214F9-0000-0000-C000-000000000046")]
        private interface IShellLinkW {
            void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cchMaxPath, IntPtr pfd, uint fFlags);
            void GetIDList(out IntPtr ppidl);
            void SetIDList(IntPtr pidl);
            void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cchMaxName);
            void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
            void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cchMaxPath);
            void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
            void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cchMaxPath);
            void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
            void GetHotkey(out ushort pwHotkey);
            void SetHotkey(ushort wHotkey);
            void GetShowCmd(out int piShowCmd);
            void SetShowCmd(int iShowCmd);
            void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cchIconPath, out int piIcon);
            void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
            void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
            void Resolve(IntPtr hwnd, uint fFlags);
            void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
        }

        [ComImport]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        [Guid("0000010b-0000-0000-C000-000000000046")]
        private interface IPersistFile {
            void GetClassID(out Guid pClassID);
            [PreserveSig]
            int IsDirty();
            void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
            void Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, [MarshalAs(UnmanagedType.Bool)] bool fRemember);
            void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
            void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
        }

        private static RegistryKey OpenBase64(string hive) {
            if (string.Equals(hive, "HKCU", StringComparison.OrdinalIgnoreCase)) {
                return RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64);
            }
            return RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
        }

        public static bool IsCurrentProcessAdmin() {
            try {
                using (var id = System.Security.Principal.WindowsIdentity.GetCurrent()) {
                    var pr = new System.Security.Principal.WindowsPrincipal(id);
                    return pr.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
                }
            } catch {
                return false;
            }
        }

        private static HashSet<string> GetMountedFixedDriveRoots() {
            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try {
                DriveInfo[] drives = DriveInfo.GetDrives();
                for (int i = 0; i < drives.Length; i++) {
                    try {
                        if (drives[i].IsReady && drives[i].DriveType == DriveType.Fixed) {
                            string root = (drives[i].RootDirectory.FullName ?? "").TrimEnd('\\');
                            if (root.Length == 2 && root[1] == ':') {
                                set.Add(root);
                            }
                        }
                    } catch {}
                }
            } catch {}
            return set;
        }

        private static bool IsOnMountedFixedDrive(string path, HashSet<string> fixedRoots) {
            if (string.IsNullOrWhiteSpace(path) || path.Length < 3) return false;
            if (path.StartsWith(@"\\", StringComparison.Ordinal)) return false;
            if (path[1] != ':' || (path[2] != '\\' && path[2] != '/')) return false;
            string drive = path.Substring(0, 2);
            if (fixedRoots == null || fixedRoots.Count == 0) {
                try {
                    var di = new DriveInfo(drive);
                    return di.IsReady && di.DriveType == DriveType.Fixed;
                } catch {
                    return false;
                }
            }
            return fixedRoots.Contains(drive);
        }

        private static string NormalizeCleanPath(string path) {
            if (string.IsNullOrWhiteSpace(path)) return "";
            string p = path.Trim().Trim('"');
            if (string.IsNullOrEmpty(p)) return "";
            if (p.StartsWith(@"\??\", StringComparison.Ordinal)) {
                p = p.Substring(4);
            }
            if (p.StartsWith(@"\SystemRoot\", StringComparison.OrdinalIgnoreCase)) {
                string winDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
                p = Path.Combine(winDir, p.Substring(@"\SystemRoot\".Length));
            } else if (p.StartsWith(@"System32\", StringComparison.OrdinalIgnoreCase)) {
                string winDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
                p = Path.Combine(winDir, p);
            }
            p = Environment.ExpandEnvironmentVariables(p).Trim().Trim('"');
            try {
                if (Path.IsPathRooted(p) && !p.StartsWith(@"\\", StringComparison.Ordinal)) {
                    p = Path.GetFullPath(p);
                } else {
                    while (p.IndexOf(@"\\", StringComparison.Ordinal) >= 0 && !p.StartsWith(@"\\", StringComparison.Ordinal)) {
                        p = p.Replace(@"\\", @"\");
                    }
                }
            } catch {
                while (p.IndexOf(@"\\", StringComparison.Ordinal) >= 0 && !p.StartsWith(@"\\", StringComparison.Ordinal)) {
                    p = p.Replace(@"\\", @"\");
                }
            }
            if (p.IndexOf('~') >= 0 && File.Exists(p)) {
                try {
                    var sb = new StringBuilder(1024);
                    uint len = GetLongPathNameW(p, sb, (uint)sb.Capacity);
                    if (len > 0 && len < sb.Capacity) {
                        p = sb.ToString();
                    }
                } catch {}
            }
            return p;
        }

        private static bool IsEnabledFromApprovedBytes(byte[] data) {
            if (data == null || data.Length == 0) return true;
            return (data[0] & 1) == 0;
        }

        private static byte[] BuildApprovedBytes(bool enable) {
            byte[] buf = new byte[12];
            if (enable) {
                buf[0] = 0x02;
                return buf;
            }
            buf[0] = 0x03;
            byte[] ft = BitConverter.GetBytes(DateTime.UtcNow.ToFileTimeUtc());
            Buffer.BlockCopy(ft, 0, buf, 4, 8);
            return buf;
        }

        private static Dictionary<string, byte[]> ReadApprovedMap(string hive, string subPath) {
            var map = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
            try {
                using (RegistryKey baseKey = OpenBase64(hive))
                using (RegistryKey k = baseKey.OpenSubKey(subPath, false)) {
                    if (k == null) return map;
                    string[] names = k.GetValueNames();
                    for (int i = 0; i < names.Length; i++) {
                        string vn = names[i];
                        if (string.IsNullOrEmpty(vn)) continue;
                        byte[] val = k.GetValue(vn) as byte[];
                        if (val != null && val.Length > 0) {
                            map[vn] = val;
                        }
                    }
                }
            } catch {}
            return map;
        }

        private static bool HasExtensionInList(string path, string[] exts) {
            if (string.IsNullOrWhiteSpace(path)) return false;
            string ext = "";
            try { ext = Path.GetExtension(path); } catch { return false; }
            for (int i = 0; i < exts.Length; i++) {
                if (string.Equals(ext, exts[i], StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        private static bool HasCommandExecExtension(string path) {
            return HasExtensionInList(path, CommandExecExtensions);
        }

        private static string TryFindInSystemPaths(string fileName) {
            if (string.IsNullOrWhiteSpace(fileName)) return "";
            string fn = fileName.Trim().Trim('"');
            if (string.IsNullOrEmpty(fn)) return "";

            string[] candidates = HasCommandExecExtension(fn)
                ? new string[] { fn }
                : new string[] { fn, fn + ".exe", fn + ".cmd", fn + ".bat" };

            var dirs = new List<string>();
            try { dirs.Add(Environment.GetFolderPath(Environment.SpecialFolder.System)); } catch {}
            try { dirs.Add(Environment.GetFolderPath(Environment.SpecialFolder.SystemX86)); } catch {}
            try { dirs.Add(Environment.GetFolderPath(Environment.SpecialFolder.Windows)); } catch {}

            string envPath = Environment.GetEnvironmentVariable("PATH") ?? "";
            if (!string.IsNullOrEmpty(envPath)) {
                string[] parts = envPath.Split(new char[] { ';' }, StringSplitOptions.RemoveEmptyEntries);
                for (int i = 0; i < parts.Length; i++) {
                    string d = parts[i].Trim().Trim('"');
                    if (!string.IsNullOrEmpty(d)) dirs.Add(d);
                }
            }

            for (int dIdx = 0; dIdx < dirs.Count; dIdx++) {
                string dir = dirs[dIdx];
                for (int cIdx = 0; cIdx < candidates.Length; cIdx++) {
                    try {
                        string full = Path.Combine(dir, candidates[cIdx]);
                        if (File.Exists(full)) return NormalizeCleanPath(full);
                    } catch {}
                }
            }

            try {
                using (RegistryKey baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)) {
                    for (int cIdx = 0; cIdx < candidates.Length; cIdx++) {
                        using (RegistryKey ap = baseKey.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\" + candidates[cIdx], false)) {
                            if (ap != null) {
                                string p = Convert.ToString(ap.GetValue(""), CultureInfo.InvariantCulture) ?? "";
                                p = NormalizeCleanPath(p);
                                if (!string.IsNullOrEmpty(p) && File.Exists(p)) return p;
                            }
                        }
                    }
                }
            } catch {}

            return "";
        }

        private static string[] SplitCommandArgs(string expandedCmd) {
            if (string.IsNullOrWhiteSpace(expandedCmd)) return new string[0];
            int argc;
            IntPtr argvPtr = CommandLineToArgvW(expandedCmd, out argc);
            if (argvPtr == IntPtr.Zero) return new string[0];
            try {
                if (argc <= 0) return new string[0];
                string[] argv = new string[argc];
                for (int i = 0; i < argc; i++) {
                    IntPtr pStr = Marshal.ReadIntPtr(argvPtr, i * IntPtr.Size);
                    argv[i] = Marshal.PtrToStringUni(pStr) ?? "";
                }
                return argv;
            } finally {
                LocalFree(argvPtr);
            }
        }

        public static string ResolveExecutablePath(string rawCommand, out bool isExplicitMissingFile) {
            return ResolveExecutablePathInternal(rawCommand, null, out isExplicitMissingFile);
        }

        private static string ResolveExecutablePathInternal(string rawCommand, HashSet<string> fixedRoots, out bool isExplicitMissingFile) {
            isExplicitMissingFile = false;
            if (string.IsNullOrWhiteSpace(rawCommand)) return "";

            string expanded = Environment.ExpandEnvironmentVariables(rawCommand).Trim();
            if (string.IsNullOrEmpty(expanded)) return "";

            if (expanded.StartsWith("\"", StringComparison.Ordinal)) {
                int endQ = expanded.IndexOf('"', 1);
                if (endQ > 1) {
                    string quoted = NormalizeCleanPath(expanded.Substring(1, endQ - 1));
                    if (File.Exists(quoted)) return quoted;
                    if (!quoted.Contains("\\") && !quoted.Contains("/")) {
                        string found = TryFindInSystemPaths(quoted);
                        if (!string.IsNullOrEmpty(found)) return found;
                    }
                    if (Path.IsPathRooted(quoted)) {
                        isExplicitMissingFile = IsOnMountedFixedDrive(quoted, fixedRoots);
                        return quoted;
                    }
                }
            }

            string directNorm = NormalizeCleanPath(expanded);
            if (File.Exists(directNorm)) return directNorm;

            string[] argv = SplitCommandArgs(expanded);
            string firstArg = argv.Length > 0 ? NormalizeCleanPath(argv[0]) : "";

            if (!string.IsNullOrEmpty(firstArg)) {
                if (File.Exists(firstArg)) return firstArg;
                if (!firstArg.Contains("\\") && !firstArg.Contains("/")) {
                    string foundInPath = TryFindInSystemPaths(firstArg);
                    if (!string.IsNullOrEmpty(foundInPath)) return foundInPath;
                }
            }

            if (argv.Length > 1 && Path.IsPathRooted(firstArg)) {
                var sb = new StringBuilder(argv[0].Trim());
                string bestRootedExec = HasCommandExecExtension(firstArg) ? firstArg : "";
                for (int i = 1; i < argv.Length; i++) {
                    sb.Append(' ').Append(argv[i]);
                    string candidate = NormalizeCleanPath(sb.ToString());
                    if (File.Exists(candidate)) return candidate;
                    if (string.IsNullOrEmpty(bestRootedExec) && HasCommandExecExtension(candidate)) {
                        bestRootedExec = candidate;
                    }
                }
                if (!string.IsNullOrEmpty(bestRootedExec)) {
                    isExplicitMissingFile = !File.Exists(bestRootedExec) && IsOnMountedFixedDrive(bestRootedExec, fixedRoots);
                    return bestRootedExec;
                }
            }

            if (!string.IsNullOrEmpty(firstArg) && Path.IsPathRooted(firstArg)) {
                if (!HasCommandExecExtension(firstArg) && File.Exists(firstArg + ".exe")) {
                    return firstArg + ".exe";
                }
                isExplicitMissingFile = IsOnMountedFixedDrive(firstArg, fixedRoots);
                return firstArg;
            }

            return firstArg;
        }

        private static bool IsGenericHostProcess(string exePath) {
            if (string.IsNullOrWhiteSpace(exePath)) return false;
            string winDir = "";
            try { winDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows).TrimEnd('\\') + "\\"; } catch {}
            if (!string.IsNullOrEmpty(winDir) && exePath.StartsWith(winDir, StringComparison.OrdinalIgnoreCase)) {
                string fn = Path.GetFileNameWithoutExtension(exePath) ?? "";
                if (fn.Equals("explorer", StringComparison.OrdinalIgnoreCase) ||
                    fn.Equals("SecurityHealthSystray", StringComparison.OrdinalIgnoreCase) ||
                    fn.Equals("ctfmon", StringComparison.OrdinalIgnoreCase)) {
                    return false;
                }
                return true;
            }
            string stem = (Path.GetFileNameWithoutExtension(exePath) ?? "").ToLowerInvariant();
            return stem == "pwsh" || stem == "python" || stem == "pythonw" || stem == "node" || stem == "java" || stem == "javaw";
        }

        private static void InspectSecondaryTargets(
            string rawCommand,
            string resolvedExe,
            HashSet<string> fixedRoots,
            ref bool isOrphan,
            ref string orphanReason,
            out string secondaryTargetPath) {
            secondaryTargetPath = "";
            if (isOrphan || string.IsNullOrWhiteSpace(rawCommand) || string.IsNullOrWhiteSpace(resolvedExe)) return;

            string expanded = Environment.ExpandEnvironmentVariables(rawCommand).Trim();
            string[] argv = SplitCommandArgs(expanded);
            if (argv.Length < 2) return;

            string exeName = Path.GetFileName(resolvedExe) ?? "";

            // 1) Squirrel / Electron launcher: Update.exe --processStart App.exe
            if (exeName.Equals("Update.exe", StringComparison.OrdinalIgnoreCase)) {
                string targetAppExe = "";
                for (int i = 1; i < argv.Length - 1; i++) {
                    if (argv[i].Equals("--processStart", StringComparison.OrdinalIgnoreCase) ||
                        argv[i].Equals("--processStartAndWait", StringComparison.OrdinalIgnoreCase)) {
                        targetAppExe = argv[i + 1].Trim().Trim('"');
                        break;
                    }
                }
                if (!string.IsNullOrEmpty(targetAppExe)) {
                    string baseDir = Path.GetDirectoryName(resolvedExe) ?? "";
                    if (!string.IsNullOrEmpty(baseDir) && Directory.Exists(baseDir)) {
                        string bestReal = "";
                        try {
                            string directSibling = Path.Combine(baseDir, targetAppExe);
                            if (File.Exists(directSibling)) bestReal = directSibling;
                            string[] appDirs = Directory.GetDirectories(baseDir, "app-*");
                            Array.Sort(appDirs, StringComparer.OrdinalIgnoreCase);
                            for (int di = appDirs.Length - 1; di >= 0; di--) {
                                string cand = Path.Combine(appDirs[di], targetAppExe);
                                if (File.Exists(cand)) {
                                    bestReal = cand;
                                    break;
                                }
                            }
                            if (!string.IsNullOrEmpty(bestReal)) {
                                secondaryTargetPath = NormalizeCleanPath(bestReal);
                            } else if (appDirs.Length == 0 && IsOnMountedFixedDrive(baseDir, fixedRoots)) {
                                isOrphan = true;
                                orphanReason = "T\u1EC7p \u1EE9ng d\u1EE5ng \u0111\u00EDch c\u1EE7a tr\u00ECnh kh\u1EDFi ch\u1EA1y Squirrel kh\u00F4ng c\u00F2n t\u1ED3n t\u1EA1i (" + targetAppExe + ")";
                            }
                        } catch {}
                    }
                }
                return;
            }

            // 2) Generic host process running an external script/DLL/binary path
            if (!IsGenericHostProcess(resolvedExe)) return;
            string winRoot = "";
            try { winRoot = Environment.GetFolderPath(Environment.SpecialFolder.Windows).TrimEnd('\\') + "\\"; } catch {}

            for (int i = 1; i < argv.Length; i++) {
                string tok = (argv[i] ?? "").Trim().Trim('"');
                if (tok.Length < 5) continue;
                if (tok.StartsWith("-", StringComparison.Ordinal) || tok.StartsWith("/", StringComparison.Ordinal)) {
                    int eq = tok.IndexOf('=');
                    if (eq > 0 && eq + 1 < tok.Length) {
                        tok = tok.Substring(eq + 1).Trim().Trim('"');
                    } else {
                        continue;
                    }
                }
                // Handle DLL entrypoint syntax: C:\path\mod.dll,EntryPoint
                int comma = tok.IndexOf(',');
                if (comma > 3) {
                    string beforeComma = tok.Substring(0, comma).Trim().Trim('"');
                    if (HasExtensionInList(beforeComma, SecondaryTargetExtensions)) {
                        tok = beforeComma;
                    }
                }
                string normTok = NormalizeCleanPath(tok);
                if (!Path.IsPathRooted(normTok)) continue;
                if (!HasExtensionInList(normTok, SecondaryTargetExtensions)) continue;
                if (!string.IsNullOrEmpty(winRoot) && normTok.StartsWith(winRoot, StringComparison.OrdinalIgnoreCase)) continue;

                secondaryTargetPath = normTok;
                if (!File.Exists(normTok) && IsOnMountedFixedDrive(normTok, fixedRoots)) {
                    isOrphan = true;
                    orphanReason = "T\u1EC7p k\u1ECBch b\u1EA3n / DLL \u0111\u00EDch kh\u00F4ng c\u00F2n t\u1ED3n t\u1EA1i tr\u00EAn \u1ED5 \u0111\u0129a";
                }
                return;
            }
        }

        private static void ResolveShortcutLnk(
            string lnkPath,
            out string targetPath,
            out string arguments,
            out string iconLocation,
            out bool isNonFileTarget) {
            targetPath = "";
            arguments = "";
            iconLocation = "";
            isNonFileTarget = false;
            IShellLinkW link = null;
            try {
                link = (IShellLinkW)new ShellLinkCoClass();
                IPersistFile pf = (IPersistFile)link;
                pf.Load(lnkPath, 0);

                var pathBuf = new StringBuilder(1024);
                link.GetPath(pathBuf, pathBuf.Capacity, IntPtr.Zero, 0);
                string p = pathBuf.ToString().Trim();

                var argsBuf = new StringBuilder(1024);
                link.GetArguments(argsBuf, argsBuf.Capacity);
                arguments = argsBuf.ToString().Trim();

                try {
                    var iconBuf = new StringBuilder(1024);
                    int iconIdx;
                    link.GetIconLocation(iconBuf, iconBuf.Capacity, out iconIdx);
                    string ic = NormalizeCleanPath(iconBuf.ToString());
                    if (!string.IsNullOrEmpty(ic) && File.Exists(ic)) {
                        iconLocation = ic;
                    }
                } catch {}

                if (string.IsNullOrEmpty(p)) {
                    isNonFileTarget = true;
                } else {
                    targetPath = NormalizeCleanPath(p);
                }
            } catch {
                isNonFileTarget = true;
            } finally {
                if (link != null) {
                    try { Marshal.ReleaseComObject(link); } catch {}
                }
            }
        }

        private static void ResolveInternetShortcutUrl(string urlFilePath, out string urlTarget, out string iconFile) {
            urlTarget = "";
            iconFile = "";
            try {
                string[] lines = File.ReadAllLines(urlFilePath);
                for (int i = 0; i < lines.Length; i++) {
                    string ln = (lines[i] ?? "").Trim();
                    if (ln.StartsWith("URL=", StringComparison.OrdinalIgnoreCase)) {
                        urlTarget = ln.Substring(4).Trim();
                    } else if (ln.StartsWith("IconFile=", StringComparison.OrdinalIgnoreCase)) {
                        iconFile = NormalizeCleanPath(ln.Substring(9));
                    }
                }
            } catch {}
        }

        public static string IsProtectedOemOrSystemStartup(string name, string command, string publisher) {
            string hay = ((name ?? "") + " " + (command ?? "") + " " + (publisher ?? ""));
            if (RxSystemProtection.IsMatch(hay)) return "System";
            if (RxOemProtection.IsMatch(hay)) return "Oem";
            return "";
        }

        public static string EstimateImpact(string name, string command, string publisher) {
            string hay = ((name ?? "") + " " + (command ?? "") + " " + (publisher ?? ""));
            if (RxHighImpact.IsMatch(hay)) return "High";
            if (RxMediumImpact.IsMatch(hay)) return "Medium";
            return "Low";
        }

        private static string RefineImpactFromFootprint(string currentImpact, string exePath) {
            if (string.Equals(currentImpact, "High", StringComparison.OrdinalIgnoreCase)) return "High";
            if (string.IsNullOrWhiteSpace(exePath) || !File.Exists(exePath)) return currentImpact;
            try {
                var fi = new FileInfo(exePath);
                long sz = fi.Length;
                string dir = fi.DirectoryName ?? "";
                bool isElectron = !string.IsNullOrEmpty(dir) &&
                    (File.Exists(Path.Combine(dir, @"resources\app.asar")) ||
                     File.Exists(Path.Combine(dir, "electron.exe")));
                bool isCef = !string.IsNullOrEmpty(dir) &&
                    (File.Exists(Path.Combine(dir, "libcef.dll")) ||
                     File.Exists(Path.Combine(dir, "chrome_elf.dll")));
                if ((isElectron || isCef) && sz >= 40L * 1024L * 1024L) {
                    return "High";
                }
                if (isElectron || isCef || sz >= 35L * 1024L * 1024L) {
                    return "Medium";
                }
                if (string.Equals(currentImpact, "Low", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(dir)) {
                    if (File.Exists(Path.Combine(dir, "WebView2Loader.dll")) ||
                        File.Exists(Path.Combine(dir, "Qt6Core.dll")) ||
                        File.Exists(Path.Combine(dir, "Qt5Core.dll")) ||
                        sz >= 12L * 1024L * 1024L) {
                        return "Medium";
                    }
                }
            } catch {}
            return currentImpact;
        }

        private static string CleanDisplayName(string raw) {
            if (string.IsNullOrWhiteSpace(raw)) return "";
            string s = raw.Trim();
            s = RxTrailingUrl.Replace(s, "").Trim();
            s = RxSidSuffix.Replace(s, "").Trim();
            return s;
        }

        private static string MakeFriendlyName(string rawName, string exePath) {
            string n = CleanDisplayName(rawName);
            if (n.StartsWith("MicrosoftEdgeAutoLaunch_", StringComparison.OrdinalIgnoreCase)) {
                return "Microsoft Edge";
            }
            if (n.StartsWith("electron.app.", StringComparison.OrdinalIgnoreCase)) {
                return n.Substring("electron.app.".Length);
            }
            if (n.StartsWith("com.squirrel.", StringComparison.OrdinalIgnoreCase)) {
                string[] parts = n.Split('.');
                if (parts.Length >= 3) return parts[parts.Length - 1];
            }
            if (string.IsNullOrEmpty(n) && !string.IsNullOrEmpty(exePath)) {
                try { return Path.GetFileNameWithoutExtension(exePath); } catch {}
            }
            return n;
        }

        private static bool IsJunkPublisher(string pub) {
            if (string.IsNullOrWhiteSpace(pub)) return true;
            string p = pub.Trim();
            if (p.IndexOf('\\') >= 0) return true;
            if (p.StartsWith("S-1-5-", StringComparison.OrdinalIgnoreCase)) return true;
            if (p.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
                p.Equals("Default Company Name", StringComparison.OrdinalIgnoreCase) ||
                p.Equals("TODO: <Company name>", StringComparison.OrdinalIgnoreCase)) {
                return true;
            }
            return false;
        }

        private static string ExtractCertRdnField(string subject, string fieldName) {
            if (string.IsNullOrWhiteSpace(subject)) return "";
            string key = fieldName + "=";
            int idx = 0;
            while (idx < subject.Length) {
                while (idx < subject.Length && (subject[idx] == ' ' || subject[idx] == ',')) idx++;
                if (idx >= subject.Length) break;
                bool match = (idx + key.Length <= subject.Length) &&
                             string.Compare(subject, idx, key, 0, key.Length, StringComparison.OrdinalIgnoreCase) == 0;
                int eq = subject.IndexOf('=', idx);
                if (eq < 0) break;
                int valStart = eq + 1;
                string val;
                if (valStart < subject.Length && subject[valStart] == '"') {
                    valStart++;
                    int endQ = subject.IndexOf('"', valStart);
                    if (endQ < 0) endQ = subject.Length;
                    val = subject.Substring(valStart, endQ - valStart).Trim();
                    idx = endQ + 1;
                } else {
                    int nextComma = subject.IndexOf(',', valStart);
                    if (nextComma < 0) nextComma = subject.Length;
                    val = subject.Substring(valStart, nextComma - valStart).Trim();
                    idx = nextComma + 1;
                }
                if (match && !string.IsNullOrWhiteSpace(val)) {
                    return val;
                }
            }
            return "";
        }

        private static readonly MethodInfo _miCreateCertFromSignedFile =
            typeof(X509Certificate).GetMethod("CreateFromSignedFile", new Type[] { typeof(string) });

        public static string ExtractSignerOrganization(string filePath) {
            if (string.IsNullOrWhiteSpace(filePath)) return "";
            string cached;
            if (_certOrgCache.TryGetValue(filePath, out cached)) return cached;
            string org = "";
            try {
                if (_miCreateCertFromSignedFile != null && File.Exists(filePath)) {
                    X509Certificate cert = _miCreateCertFromSignedFile.Invoke(null, new object[] { filePath }) as X509Certificate;
                    if (cert != null) {
                        try {
                            string subj = cert.Subject ?? "";
                            org = ExtractCertRdnField(subj, "O");
                            if (string.IsNullOrWhiteSpace(org)) {
                                org = ExtractCertRdnField(subj, "CN");
                            }
                        } finally {
                            try { cert.Reset(); } catch {}
                        }
                    }
                }
            } catch {
                org = "";
            }
            _certOrgCache[filePath] = org;
            return org;
        }

        private static void ScanRegistryRunKey(
            List<StartupEntry> list,
            HashSet<string> fixedRoots,
            string hive,
            string runPath,
            string approvedPath,
            string sourceKind,
            string triggerInfo,
            bool requiresAdmin,
            bool canToggle,
            bool isPolicyLocked) {
            Dictionary<string, byte[]> approvedMap = string.IsNullOrEmpty(approvedPath)
                ? new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase)
                : ReadApprovedMap(hive, approvedPath);
            try {
                using (RegistryKey baseKey = OpenBase64(hive))
                using (RegistryKey k = baseKey.OpenSubKey(runPath, false)) {
                    if (k == null) return;
                    string[] names = k.GetValueNames();
                    for (int i = 0; i < names.Length; i++) {
                        string vn = names[i];
                        if (string.IsNullOrEmpty(vn)) continue;
                        string rawCmd = Convert.ToString(k.GetValue(vn), CultureInfo.InvariantCulture) ?? "";
                        if (string.IsNullOrWhiteSpace(rawCmd)) continue;

                        bool isMissing;
                        string exePath = ResolveExecutablePathInternal(rawCmd, fixedRoots, out isMissing);
                        string orphanReason = isMissing ? "T\u1EC7p th\u1EF1c thi kh\u00F4ng c\u00F2n t\u1ED3n t\u1EA1i tr\u00EAn \u1ED5 \u0111\u0129a" : "";
                        string secTarget;
                        InspectSecondaryTargets(rawCmd, exePath, fixedRoots, ref isMissing, ref orphanReason, out secTarget);

                        byte[] apBytes;
                        bool enabled = true;
                        if (!string.IsNullOrEmpty(approvedPath)) {
                            enabled = !approvedMap.TryGetValue(vn, out apBytes) || IsEnabledFromApprovedBytes(apBytes);
                        }

                        var entry = new StartupEntry();
                        entry.Id = sourceKind + "|" + hive + "|" + vn;
                        entry.Name = vn;
                        entry.DisplayName = MakeFriendlyName(vn, !string.IsNullOrEmpty(secTarget) ? secTarget : exePath);
                        entry.Publisher = "";
                        entry.RawCommand = rawCmd;
                        entry.ResolvedExePath = exePath;
                        entry.SecondaryTargetPath = secTarget;
                        entry.SourceKind = sourceKind;
                        entry.RegistryHive = hive;
                        entry.RegistryPath = runPath;
                        entry.RegistryValueName = vn;
                        entry.ApprovedHive = hive;
                        entry.ApprovedPath = approvedPath ?? "";
                        entry.ApprovedValueName = string.IsNullOrEmpty(approvedPath) ? "" : vn;
                        entry.TriggerInfo = triggerInfo;
                        entry.OrphanReason = orphanReason;
                        entry.Enabled = enabled;
                        entry.IsPolicyLocked = isPolicyLocked;
                        entry.LockKind = isPolicyLocked ? "Policy" : "";
                        entry.IsOrphan = isMissing;
                        entry.ProtectionKind = IsProtectedOemOrSystemStartup(entry.DisplayName, rawCmd + " " + secTarget, "");
                        entry.ImpactLevel = EstimateImpact(entry.DisplayName, rawCmd + " " + secTarget, "");
                        entry.RequiresAdmin = requiresAdmin;
                        entry.CanDelete = true;
                        entry.CanToggle = canToggle && !isPolicyLocked;
                        entry.MetadataHydrated = false;
                        list.Add(entry);
                    }
                }
            } catch {}
        }

        private static void ScanStartupFolder(
            List<StartupEntry> list,
            HashSet<string> fixedRoots,
            string folderPath,
            string approvedHive,
            string sourceKind,
            bool requiresAdmin) {
            if (string.IsNullOrWhiteSpace(folderPath) || !Directory.Exists(folderPath)) return;
            Dictionary<string, byte[]> approvedMap = ReadApprovedMap(approvedHive, RegApprovedFolderPath);
            try {
                string[] files = Directory.GetFiles(folderPath);
                for (int i = 0; i < files.Length; i++) {
                    string fp = files[i];
                    string fileName = Path.GetFileName(fp);
                    if (string.IsNullOrEmpty(fileName)) continue;
                    if (string.Equals(fileName, "desktop.ini", StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(fileName, "thumbs.db", StringComparison.OrdinalIgnoreCase)) {
                        continue;
                    }
                    try {
                        FileAttributes attrs = File.GetAttributes(fp);
                        if ((attrs & FileAttributes.System) != 0) continue;
                    } catch {}

                    string ext = Path.GetExtension(fp) ?? "";
                    if (!HasExtensionInList(fp, ValidStartupExtensions)) continue;

                    string exePath = NormalizeCleanPath(fp);
                    string rawCmd = exePath;
                    string iconHint = "";
                    string secTarget = "";
                    bool isOrphan = false;
                    string orphanReason = "";

                    if (string.Equals(ext, ".lnk", StringComparison.OrdinalIgnoreCase)) {
                        string lnkTarget;
                        string lnkArgs;
                        string lnkIcon;
                        bool isNonFile;
                        ResolveShortcutLnk(fp, out lnkTarget, out lnkArgs, out lnkIcon, out isNonFile);
                        iconHint = lnkIcon;
                        if (isNonFile) {
                            exePath = NormalizeCleanPath(fp);
                            rawCmd = exePath;
                            isOrphan = false;
                        } else {
                            exePath = lnkTarget;
                            rawCmd = string.IsNullOrEmpty(lnkArgs) ? lnkTarget : ("\"" + lnkTarget + "\" " + lnkArgs);
                            if (!string.IsNullOrEmpty(lnkTarget) && Path.IsPathRooted(lnkTarget) && !File.Exists(lnkTarget) && IsOnMountedFixedDrive(lnkTarget, fixedRoots)) {
                                isOrphan = true;
                                orphanReason = "Shortcut tr\u1ECF t\u1EDBi t\u1EC7p \u0111\u00E3 b\u1ECB x\u00F3a kh\u1ECFi \u1ED5 \u0111\u0129a";
                            } else {
                                InspectSecondaryTargets(rawCmd, exePath, fixedRoots, ref isOrphan, ref orphanReason, out secTarget);
                            }
                        }
                    } else if (string.Equals(ext, ".url", StringComparison.OrdinalIgnoreCase)) {
                        string urlTarget;
                        string urlIcon;
                        ResolveInternetShortcutUrl(fp, out urlTarget, out urlIcon);
                        iconHint = urlIcon;
                        if (!string.IsNullOrEmpty(urlTarget)) {
                            rawCmd = urlTarget;
                            if (urlTarget.StartsWith("file:///", StringComparison.OrdinalIgnoreCase)) {
                                string localP = NormalizeCleanPath(Uri.UnescapeDataString(urlTarget.Substring(8).Replace('/', '\\')));
                                exePath = localP;
                                if (!File.Exists(localP) && IsOnMountedFixedDrive(localP, fixedRoots)) {
                                    isOrphan = true;
                                    orphanReason = "Shortcut URL tr\u1ECF t\u1EDBi t\u1EC7p n\u1ED9i b\u1ED9 kh\u00F4ng t\u1ED3n t\u1EA1i";
                                }
                            }
                        }
                    }

                    byte[] apBytes;
                    bool enabled = !approvedMap.TryGetValue(fileName, out apBytes) || IsEnabledFromApprovedBytes(apBytes);
                    string disp = CleanDisplayName(Path.GetFileNameWithoutExtension(fileName));

                    var entry = new StartupEntry();
                    entry.Id = sourceKind + "|" + fileName;
                    entry.Name = fileName;
                    entry.DisplayName = disp;
                    entry.Publisher = "";
                    entry.RawCommand = rawCmd;
                    entry.ResolvedExePath = exePath;
                    entry.SecondaryTargetPath = secTarget;
                    entry.IconHintPath = iconHint;
                    entry.SourceKind = sourceKind;
                    entry.ApprovedHive = approvedHive;
                    entry.ApprovedPath = RegApprovedFolderPath;
                    entry.ApprovedValueName = fileName;
                    entry.FolderFilePath = fp;
                    entry.TriggerInfo = requiresAdmin
                        ? "Th\u01B0 m\u1EE5c Startup (All Users)"
                        : "Th\u01B0 m\u1EE5c Startup (User)";
                    entry.OrphanReason = orphanReason;
                    entry.Enabled = enabled;
                    entry.IsPolicyLocked = false;
                    entry.IsOrphan = isOrphan;
                    entry.ProtectionKind = IsProtectedOemOrSystemStartup(disp, rawCmd + " " + secTarget, "");
                    entry.ImpactLevel = EstimateImpact(disp, rawCmd + " " + secTarget, "");
                    entry.RequiresAdmin = requiresAdmin;
                    entry.CanDelete = true;
                    entry.CanToggle = true;
                    entry.MetadataHydrated = false;
                    list.Add(entry);
                }
            } catch {}
        }

        public static StartupEntry[] ScanFastCore() {
            var list = new List<StartupEntry>(48);
            HashSet<string> fixedRoots = GetMountedFixedDriveRoots();

            ScanRegistryRunKey(list, fixedRoots, "HKCU", RegRunPath, RegApprovedRunPath, "RegUser", "Registry User (HKCU\\Run)", false, true, false);
            ScanRegistryRunKey(list, fixedRoots, "HKCU", RegRunWow32Path, RegApprovedRun32Path, "RegUser32", "Registry User 32-bit (HKCU\\WOW6432Node\\Run)", false, true, false);
            ScanRegistryRunKey(list, fixedRoots, "HKLM", RegRunPath, RegApprovedRunPath, "RegSystem", "Registry System (HKLM\\Run)", true, true, false);
            ScanRegistryRunKey(list, fixedRoots, "HKLM", RegRunWow32Path, RegApprovedRun32Path, "RegWow32", "Registry System 32-bit (HKLM\\WOW6432Node\\Run)", true, true, false);

            ScanRegistryRunKey(list, fixedRoots, "HKCU", RegRunOncePath, "", "RegRunOnce", "Ch\u1EA1y 1 l\u1EA7n (HKCU\\RunOnce)", false, false, false);
            ScanRegistryRunKey(list, fixedRoots, "HKLM", RegRunOncePath, "", "RegRunOnce", "Ch\u1EA1y 1 l\u1EA7n (HKLM\\RunOnce)", true, false, false);
            ScanRegistryRunKey(list, fixedRoots, "HKLM", RegRunOnceWow32Path, "", "RegRunOnce", "Ch\u1EA1y 1 l\u1EA7n 32-bit (HKLM\\WOW6432Node\\RunOnce)", true, false, false);

            ScanRegistryRunKey(list, fixedRoots, "HKCU", RegPolicyRunPath, "", "RegPolicy", "Group Policy (HKCU\\Policies\\Explorer\\Run)", false, false, true);
            ScanRegistryRunKey(list, fixedRoots, "HKLM", RegPolicyRunPath, "", "RegPolicy", "Group Policy (HKLM\\Policies\\Explorer\\Run)", true, false, true);

            try {
                string userFolder = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
                ScanStartupFolder(list, fixedRoots, userFolder, "HKCU", "FolderUser", false);
            } catch {}
            try {
                string commonFolder = Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup);
                ScanStartupFolder(list, fixedRoots, commonFolder, "HKLM", "FolderAll", true);
            } catch {}

            return list.ToArray();
        }

        public static Task<StartupEntry[]> ScanFastCoreAsync() {
            return Task.Run(delegate() { return ScanFastCore(); });
        }

        private sealed class PackageRepoInfo {
            public string PackageFullName;
            public string PackageRootFolder;
            public Version ParsedVersion;
        }

        private static string ExtractPackageFamilyFromFullName(string fullName) {
            if (string.IsNullOrEmpty(fullName)) return "";
            int firstUs = fullName.IndexOf('_');
            int lastDoubleUs = fullName.LastIndexOf("__", StringComparison.Ordinal);
            if (firstUs <= 0 || lastDoubleUs <= firstUs || lastDoubleUs + 2 >= fullName.Length) return "";
            return fullName.Substring(0, firstUs) + "_" + fullName.Substring(lastDoubleUs + 2);
        }

        private static bool IsResourceOrSplitPackage(string fullName) {
            if (string.IsNullOrEmpty(fullName)) return true;
            if (fullName.IndexOf("_split.", StringComparison.OrdinalIgnoreCase) >= 0) return true;
            if (fullName.IndexOf("_neutral_~_", StringComparison.OrdinalIgnoreCase) >= 0) return true;
            string[] parts = fullName.Split('_');
            // Format: Name_Version_Arch_ResourceId_PublisherId (5 segments -> parts[3] is ResourceId; main pkg has empty ResourceId!)
            if (parts.Length >= 5 && !string.IsNullOrEmpty(parts[3]) && !parts[3].Equals("~", StringComparison.Ordinal)) {
                return true;
            }
            return false;
        }

        private static Version ExtractPackageVersion(string fullName) {
            if (string.IsNullOrEmpty(fullName)) return new Version(0, 0, 0, 0);
            string[] parts = fullName.Split('_');
            if (parts.Length >= 2) {
                Version v;
                if (Version.TryParse(parts[1], out v)) return v;
            }
            return new Version(0, 0, 0, 0);
        }

        private static void PopulateUwpFamilyMapFromKey(Dictionary<string, PackageRepoInfo> map, RegistryHive hiveEnum, string repoPath) {
            try {
                using (RegistryKey rootKey = RegistryKey.OpenBaseKey(hiveEnum, RegistryView.Registry64))
                using (RegistryKey pkgs = rootKey.OpenSubKey(repoPath, false)) {
                    if (pkgs == null) return;
                    string[] subNames = pkgs.GetSubKeyNames();
                    for (int i = 0; i < subNames.Length; i++) {
                        string fullName = subNames[i];
                        if (IsResourceOrSplitPackage(fullName)) continue;
                        string family = ExtractPackageFamilyFromFullName(fullName);
                        if (string.IsNullOrEmpty(family)) continue;
                        try {
                            using (RegistryKey pk = pkgs.OpenSubKey(fullName, false)) {
                                if (pk == null) continue;
                                string root = Convert.ToString(pk.GetValue("PackageRootFolder"), CultureInfo.InvariantCulture) ?? "";
                                if (string.IsNullOrEmpty(root)) continue;
                                string manifestPath = Path.Combine(root, "AppxManifest.xml");
                                if (!File.Exists(manifestPath)) continue;
                                Version ver = ExtractPackageVersion(fullName);
                                PackageRepoInfo existing;
                                if (!map.TryGetValue(family, out existing) ||
                                    ver.CompareTo(existing.ParsedVersion) > 0) {
                                    map[family] = new PackageRepoInfo {
                                        PackageFullName = fullName,
                                        PackageRootFolder = root,
                                        ParsedVersion = ver
                                    };
                                }
                            }
                        } catch {}
                    }
                }
            } catch {}
        }

        private static Dictionary<string, PackageRepoInfo> BuildUwpFamilyMap() {
            var map = new Dictionary<string, PackageRepoInfo>(StringComparer.OrdinalIgnoreCase);
            PopulateUwpFamilyMapFromKey(map, RegistryHive.CurrentUser, RegRepoPackagesUserPath);
            PopulateUwpFamilyMapFromKey(map, RegistryHive.LocalMachine, RegRepoPackagesMachPath);
            return map;
        }

        private static string TryLoadIndirect(string query) {
            try {
                var sb = new StringBuilder(512);
                int hr = SHLoadIndirectString(query, sb, sb.Capacity, IntPtr.Zero);
                if (hr == 0 && sb.Length > 0) {
                    string resolved = sb.ToString().Trim();
                    if (!string.IsNullOrEmpty(resolved) && !resolved.StartsWith("ms-resource:", StringComparison.OrdinalIgnoreCase)) {
                        return resolved;
                    }
                }
            } catch {}
            return "";
        }

        private static string ResolveIndirectResource(string packageFullName, string rawValue, string fallbackName) {
            if (string.IsNullOrWhiteSpace(rawValue)) return fallbackName;
            string v = rawValue.Trim();
            if (!v.StartsWith("ms-resource:", StringComparison.OrdinalIgnoreCase)) {
                return v;
            }
            string pkgName = packageFullName ?? "";
            int us = pkgName.IndexOf('_');
            if (us > 0) pkgName = pkgName.Substring(0, us);

            var candidates = new List<string>();
            if (v.StartsWith("ms-resource://", StringComparison.OrdinalIgnoreCase)) {
                candidates.Add("@{" + packageFullName + "?" + v + "}");
            } else {
                string tail = v.Substring("ms-resource:".Length).TrimStart('/');
                if (tail.StartsWith("Resources/", StringComparison.OrdinalIgnoreCase)) {
                    candidates.Add("@{" + packageFullName + "?ms-resource:///" + tail + "}");
                } else {
                    candidates.Add("@{" + packageFullName + "?ms-resource:///Resources/" + tail + "}");
                    candidates.Add("@{" + packageFullName + "?ms-resource:///" + tail + "}");
                }
                if (!string.IsNullOrEmpty(pkgName)) {
                    candidates.Add("@{" + packageFullName + "?ms-resource://" + pkgName + "/Resources/" + tail + "}");
                }
                candidates.Add("@{" + packageFullName + "?" + v + "}");
            }

            for (int i = 0; i < candidates.Count; i++) {
                string r = TryLoadIndirect(candidates[i]);
                if (!string.IsNullOrEmpty(r)) return r;
            }
            return fallbackName;
        }

        private static string ResolveUwpLogoPath(string packageRoot, string manifestLogoRel) {
            if (string.IsNullOrWhiteSpace(packageRoot) || string.IsNullOrWhiteSpace(manifestLogoRel)) return "";
            try {
                string rel = manifestLogoRel.Trim().Replace('/', '\\').TrimStart('\\');
                string direct = Path.Combine(packageRoot, rel);
                string dir = Path.GetDirectoryName(direct);
                string stem = Path.GetFileNameWithoutExtension(direct);
                string ext = Path.GetExtension(direct);
                if (string.IsNullOrEmpty(ext)) ext = ".png";

                if (!string.IsNullOrEmpty(dir) && Directory.Exists(dir) && !string.IsNullOrEmpty(stem)) {
                    string[] preferred = new string[] {
                        stem + ".targetsize-32_altform-unplated" + ext,
                        stem + ".targetsize-32" + ext,
                        stem + ".targetsize-24_altform-unplated" + ext,
                        stem + ".targetsize-24" + ext,
                        stem + ".scale-100" + ext,
                        stem + ".scale-125" + ext,
                        stem + ".scale-150" + ext,
                        stem + ".scale-200" + ext,
                        stem + ext
                    };
                    for (int i = 0; i < preferred.Length; i++) {
                        string cand = Path.Combine(dir, preferred[i]);
                        if (File.Exists(cand)) return cand;
                    }
                    string[] matches = Directory.GetFiles(dir, stem + ".*" + ext);
                    if (matches != null && matches.Length > 0) return matches[0];
                }
                if (File.Exists(direct)) return direct;
            } catch {}
            return "";
        }

        private static string FriendlyFamilyFallback(string packageFamilyName) {
            if (string.IsNullOrEmpty(packageFamilyName)) return "";
            int us = packageFamilyName.LastIndexOf('_');
            string core = us > 0 ? packageFamilyName.Substring(0, us) : packageFamilyName;
            int dot = core.LastIndexOf('.');
            if (dot > 0 && dot + 1 < core.Length) {
                string tail = core.Substring(dot + 1);
                if (tail.Length >= 3) return tail;
            }
            return core;
        }

        private sealed class ManifestStartupTaskInfo {
            public string TaskId;
            public string TaskDisplayNameRaw;
            public bool DefaultEnabled;
        }

        private static void ScanUwpStartupTasks(List<StartupEntry> list) {
            Dictionary<string, PackageRepoInfo> familyMap = BuildUwpFamilyMap();
            if (familyMap.Count == 0) return;

            var sysAppStates = new Dictionary<string, Dictionary<string, int>>(StringComparer.OrdinalIgnoreCase);
            try {
                using (RegistryKey hkcu = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64))
                using (RegistryKey appDataRoot = hkcu.OpenSubKey(RegSystemAppDataPath, false)) {
                    if (appDataRoot != null) {
                        string[] families = appDataRoot.GetSubKeyNames();
                        for (int fIdx = 0; fIdx < families.Length; fIdx++) {
                            string fam = families[fIdx];
                            try {
                                using (RegistryKey famKey = appDataRoot.OpenSubKey(fam, false)) {
                                    if (famKey == null) continue;
                                    string[] subNames = famKey.GetSubKeyNames();
                                    Dictionary<string, int> taskMap = null;
                                    for (int sIdx = 0; sIdx < subNames.Length; sIdx++) {
                                        string tid = subNames[sIdx];
                                        try {
                                            using (RegistryKey tk = famKey.OpenSubKey(tid, false)) {
                                                if (tk == null) continue;
                                                object stObj = tk.GetValue("State");
                                                if (stObj == null) continue;
                                                if (taskMap == null) taskMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                                                taskMap[tid] = Convert.ToInt32(stObj, CultureInfo.InvariantCulture);
                                            }
                                        } catch {}
                                    }
                                    if (taskMap != null && taskMap.Count > 0) {
                                        sysAppStates[fam] = taskMap;
                                    }
                                }
                            } catch {}
                        }
                    }
                }
            } catch {}

            foreach (KeyValuePair<string, PackageRepoInfo> kv in familyMap) {
                string family = kv.Key;
                PackageRepoInfo repo = kv.Value;

                string manifestPath = Path.Combine(repo.PackageRootFolder, "AppxManifest.xml");
                string manifestXml = "";
                try { manifestXml = File.ReadAllText(manifestPath, Encoding.UTF8); } catch { continue; }
                if (string.IsNullOrEmpty(manifestXml)) continue;
                if (manifestXml.IndexOf("StartupTask", StringComparison.OrdinalIgnoreCase) < 0) continue;

                var manifestTasks = new List<ManifestStartupTaskInfo>();
                var seenTaskIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                MatchCollection elMatches = RxStartupTaskEl.Matches(manifestXml);
                for (int t = 0; t < elMatches.Count; t++) {
                    string attrs = elMatches[t].Groups[1].Value;
                    Match mId = RxAttrTaskId.Match(attrs);
                    if (!mId.Success) continue;
                    string tid = mId.Groups[1].Value.Trim();
                    if (string.IsNullOrEmpty(tid) || !seenTaskIds.Add(tid)) continue;

                    Match mTd = RxAttrDisplayName.Match(attrs);
                    Match mEn = RxAttrEnabled.Match(attrs);
                    bool defEn = mEn.Success && mEn.Groups[1].Value.Trim().Equals("true", StringComparison.OrdinalIgnoreCase);
                    manifestTasks.Add(new ManifestStartupTaskInfo {
                        TaskId = tid,
                        TaskDisplayNameRaw = mTd.Success ? mTd.Groups[1].Value.Trim() : "",
                        DefaultEnabled = defEn
                    });
                }
                if (manifestTasks.Count == 0) continue;

                string fallbackName = FriendlyFamilyFallback(family);
                Match mDisp = RxDisplayName.Match(manifestXml);
                string dispRaw = mDisp.Success ? mDisp.Groups[1].Value.Trim() : "";
                string pkgDispName = ResolveIndirectResource(repo.PackageFullName, dispRaw, fallbackName);

                Match mPub = RxPublisherName.Match(manifestXml);
                string pubRaw = mPub.Success ? mPub.Groups[1].Value.Trim() : "";
                string publisher = ResolveIndirectResource(repo.PackageFullName, pubRaw, "");

                Match mLogo = RxLogo.Match(manifestXml);
                string logoRel = "";
                if (mLogo.Success) {
                    logoRel = !string.IsNullOrEmpty(mLogo.Groups[1].Value) ? mLogo.Groups[1].Value : mLogo.Groups[2].Value;
                }
                string logoPath = ResolveUwpLogoPath(repo.PackageRootFolder, logoRel);

                string pkgExe = "";
                Match mExe = RxAttrExecutable.Match(manifestXml);
                if (mExe.Success) {
                    string relExe = mExe.Groups[1].Value.Trim().Replace('/', '\\').TrimStart('\\');
                    string fullExe = Path.Combine(repo.PackageRootFolder, relExe);
                    if (File.Exists(fullExe)) pkgExe = NormalizeCleanPath(fullExe);
                }

                Dictionary<string, int> regTaskMap = null;
                sysAppStates.TryGetValue(family, out regTaskMap);

                for (int ti = 0; ti < manifestTasks.Count; ti++) {
                    ManifestStartupTaskInfo mti = manifestTasks[ti];
                    int state;
                    if (regTaskMap != null && regTaskMap.TryGetValue(mti.TaskId, out state)) {
                        // Use Windows recorded State value
                    } else {
                        state = mti.DefaultEnabled ? 2 : 0;
                    }

                    bool enabled = (state == 2 || state == 4 || state == 5);
                    bool policyLocked = (state == 3 || state == 4);
                    string taskDisp = pkgDispName;
                    if (!string.IsNullOrWhiteSpace(mti.TaskDisplayNameRaw)) {
                        string resolvedTaskDisp = ResolveIndirectResource(repo.PackageFullName, mti.TaskDisplayNameRaw, "");
                        if (!string.IsNullOrEmpty(resolvedTaskDisp)) taskDisp = resolvedTaskDisp;
                    }

                    var entry = new StartupEntry();
                    entry.Id = "Store|" + family + "|" + mti.TaskId;
                    entry.Name = mti.TaskId;
                    entry.DisplayName = taskDisp;
                    entry.Publisher = publisher;
                    entry.RawCommand = family + " (" + mti.TaskId + ")";
                    entry.ResolvedExePath = !string.IsNullOrEmpty(pkgExe) ? pkgExe : repo.PackageRootFolder;
                    entry.SourceKind = "Store";
                    entry.PackageFamilyName = family;
                    entry.PackageFullName = repo.PackageFullName;
                    entry.TaskId = mti.TaskId;
                    entry.UwpState = state;
                    entry.LogoPath = logoPath;
                    entry.TriggerInfo = "Microsoft Store / MSIX StartupTask";
                    entry.OrphanReason = "";
                    entry.Enabled = enabled;
                    entry.IsPolicyLocked = policyLocked;
                    entry.LockKind = policyLocked ? "Policy" : "";
                    entry.IsOrphan = false;
                    entry.ProtectionKind = IsProtectedOemOrSystemStartup(taskDisp, family + " " + mti.TaskId, publisher);
                    entry.ImpactLevel = EstimateImpact(taskDisp, family + " " + mti.TaskId, publisher);
                    entry.RequiresAdmin = false;
                    entry.CanDelete = false;
                    entry.CanToggle = !policyLocked;
                    entry.MetadataHydrated = true;
                    list.Add(entry);
                }
            }
        }

        private static object ComGet(object target, string propName) {
            return target.GetType().InvokeMember(propName, BindingFlags.GetProperty, null, target, null);
        }

        private static object ComGetIndexed(object target, string propName, int index) {
            return target.GetType().InvokeMember(propName, BindingFlags.GetProperty, null, target, new object[] { index });
        }

        private static void ComSet(object target, string propName, object value) {
            target.GetType().InvokeMember(propName, BindingFlags.SetProperty, null, target, new object[] { value });
        }

        private static object ComCall(object target, string methodName, params object[] args) {
            return target.GetType().InvokeMember(methodName, BindingFlags.InvokeMethod, null, target, args);
        }

        private static object ConnectTaskService() {
            Type t = Type.GetTypeFromProgID("Schedule.Service");
            if (t == null) return null;
            object svc = Activator.CreateInstance(t);
            ComCall(svc, "Connect", Type.Missing, Type.Missing, Type.Missing, Type.Missing);
            return svc;
        }

        private static string ResolveComClsidPath(string clsid) {
            if (string.IsNullOrWhiteSpace(clsid)) return "";
            string id = clsid.Trim();
            if (!id.StartsWith("{", StringComparison.Ordinal)) id = "{" + id + "}";
            string[] subKeys = new string[] {
                @"SOFTWARE\Classes\CLSID\" + id + @"\LocalServer32",
                @"SOFTWARE\Classes\CLSID\" + id + @"\InprocServer32",
                @"SOFTWARE\Classes\WOW6432Node\CLSID\" + id + @"\LocalServer32",
                @"SOFTWARE\Classes\WOW6432Node\CLSID\" + id + @"\InprocServer32"
            };
            RegistryHive[] hives = new RegistryHive[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine };
            for (int h = 0; h < hives.Length; h++) {
                try {
                    using (RegistryKey baseKey = RegistryKey.OpenBaseKey(hives[h], RegistryView.Registry64)) {
                        for (int s = 0; s < subKeys.Length; s++) {
                            using (RegistryKey k = baseKey.OpenSubKey(subKeys[s], false)) {
                                if (k == null) continue;
                                string val = Convert.ToString(k.GetValue(""), CultureInfo.InvariantCulture) ?? "";
                                if (!string.IsNullOrWhiteSpace(val)) return val.Trim();
                            }
                        }
                    }
                } catch {}
            }
            return "";
        }

        private static void TraverseScheduledTaskFolder(object folder, List<StartupEntry> list, HashSet<string> fixedRoots, string currentUserName) {
            string folderPath = "";
            try { folderPath = Convert.ToString(ComGet(folder, "Path"), CultureInfo.InvariantCulture) ?? ""; } catch { return; }

            if (folderPath.Equals(@"\Microsoft\Windows", StringComparison.OrdinalIgnoreCase) ||
                folderPath.StartsWith(@"\Microsoft\Windows\", StringComparison.OrdinalIgnoreCase) ||
                folderPath.Equals(@"\Microsoft\XblGameSave", StringComparison.OrdinalIgnoreCase) ||
                folderPath.StartsWith(@"\Microsoft\XblGameSave\", StringComparison.OrdinalIgnoreCase)) {
                return;
            }

            try {
                object tasksCol = ComCall(folder, "GetTasks", 1);
                int count = Convert.ToInt32(ComGet(tasksCol, "Count"), CultureInfo.InvariantCulture);
                for (int i = 1; i <= count; i++) {
                    object task = null;
                    try {
                        task = ComGetIndexed(tasksCol, "Item", i);
                    } catch {
                        try { task = ComCall(tasksCol, "Item", i); } catch { continue; }
                    }
                    if (task == null) continue;
                    try {
                        string taskName = Convert.ToString(ComGet(task, "Name"), CultureInfo.InvariantCulture) ?? "";
                        string taskFullPath = Convert.ToString(ComGet(task, "Path"), CultureInfo.InvariantCulture) ?? "";
                        if (string.IsNullOrEmpty(taskFullPath)) continue;
                        if (taskFullPath.StartsWith(@"\Microsoft\Windows\", StringComparison.OrdinalIgnoreCase)) continue;
                        if (taskName.Equals("CreateExplorerShellUnelevatedTask", StringComparison.OrdinalIgnoreCase)) continue;

                        bool taskEnabled = Convert.ToBoolean(ComGet(task, "Enabled"), CultureInfo.InvariantCulture);
                        object def = ComGet(task, "Definition");
                        if (def == null) continue;

                        bool hasStartupTrigger = false;
                        bool anyStartupTrigEnabled = false;
                        string triggerDesc = "";
                        object triggers = ComGet(def, "Triggers");
                        if (triggers != null) {
                            int tCount = Convert.ToInt32(ComGet(triggers, "Count"), CultureInfo.InvariantCulture);
                            for (int ti = 1; ti <= tCount; ti++) {
                                try {
                                    object trig = ComGetIndexed(triggers, "Item", ti);
                                    int trigType = Convert.ToInt32(ComGet(trig, "Type"), CultureInfo.InvariantCulture);
                                    bool isMatch = false;
                                    string label = "";
                                    if (trigType == 8) {
                                        isMatch = true;
                                        label = "Task Scheduler (@Boot)";
                                    } else if (trigType == 9) {
                                        isMatch = true;
                                        label = "Task Scheduler (@Logon)";
                                    } else if (trigType == 11) {
                                        int stChg = 0;
                                        try { stChg = Convert.ToInt32(ComGet(trig, "StateChange"), CultureInfo.InvariantCulture); } catch {}
                                        // 1=ConsoleConnect, 8=SessionUnlock
                                        if (stChg == 1 || stChg == 8) {
                                            isMatch = true;
                                            label = "Task Scheduler (@Unlock)";
                                        }
                                    }
                                    if (isMatch) {
                                        hasStartupTrigger = true;
                                        if (string.IsNullOrEmpty(triggerDesc)) triggerDesc = label;
                                        bool trigEn = true;
                                        try { trigEn = Convert.ToBoolean(ComGet(trig, "Enabled"), CultureInfo.InvariantCulture); } catch {}
                                        if (trigEn) anyStartupTrigEnabled = true;
                                    }
                                } catch {}
                            }
                        }
                        if (!hasStartupTrigger) continue;

                        string execPath = "";
                        string execArgs = "";
                        string comClsid = "";
                        object actions = ComGet(def, "Actions");
                        if (actions != null) {
                            int aCount = Convert.ToInt32(ComGet(actions, "Count"), CultureInfo.InvariantCulture);
                            for (int ai = 1; ai <= aCount; ai++) {
                                try {
                                    object act = ComGetIndexed(actions, "Item", ai);
                                    int actType = Convert.ToInt32(ComGet(act, "Type"), CultureInfo.InvariantCulture);
                                    if (actType == 0) {
                                        execPath = Convert.ToString(ComGet(act, "Path"), CultureInfo.InvariantCulture) ?? "";
                                        execArgs = Convert.ToString(ComGet(act, "Arguments"), CultureInfo.InvariantCulture) ?? "";
                                        break;
                                    } else if (actType == 5 && string.IsNullOrEmpty(comClsid)) {
                                        comClsid = Convert.ToString(ComGet(act, "ClassId"), CultureInfo.InvariantCulture) ?? "";
                                    }
                                } catch {}
                            }
                        }

                        if (string.IsNullOrWhiteSpace(execPath) && !string.IsNullOrWhiteSpace(comClsid)) {
                            string comResolved = ResolveComClsidPath(comClsid);
                            if (!string.IsNullOrWhiteSpace(comResolved)) {
                                execPath = comResolved;
                            }
                        }
                        if (string.IsNullOrWhiteSpace(execPath)) continue;

                        string rawCmd = string.IsNullOrWhiteSpace(execArgs) ? execPath : (execPath + " " + execArgs);
                        bool isMissing;
                        string resolvedExe = ResolveExecutablePathInternal(execPath, fixedRoots, out isMissing);
                        string orphanReason = isMissing ? "T\u1EC7p th\u1EF1c thi c\u1EE7a Task kh\u00F4ng c\u00F2n t\u1ED3n t\u1EA1i tr\u00EAn \u1ED5 \u0111\u0129a" : "";
                        string secTarget;
                        InspectSecondaryTargets(rawCmd, resolvedExe, fixedRoots, ref isMissing, ref orphanReason, out secTarget);

                        string author = "";
                        try {
                            object regInfo = ComGet(def, "RegistrationInfo");
                            if (regInfo != null) author = Convert.ToString(ComGet(regInfo, "Author"), CultureInfo.InvariantCulture) ?? "";
                        } catch {}
                        if (IsJunkPublisher(author)) author = "";

                        bool reqAdmin = true;
                        try {
                            object principal = ComGet(def, "Principal");
                            if (principal != null) {
                                int runLvl = 0;
                                try { runLvl = Convert.ToInt32(ComGet(principal, "RunLevel"), CultureInfo.InvariantCulture); } catch {}
                                string uid = Convert.ToString(ComGet(principal, "UserId"), CultureInfo.InvariantCulture) ?? "";
                                if (runLvl == 0 && !string.IsNullOrEmpty(uid) && !string.IsNullOrEmpty(currentUserName)) {
                                    if (uid.Equals(currentUserName, StringComparison.OrdinalIgnoreCase) ||
                                        uid.EndsWith("\\" + currentUserName, StringComparison.OrdinalIgnoreCase)) {
                                        reqAdmin = false;
                                    }
                                }
                            }
                        } catch {}

                        var entry = new StartupEntry();
                        entry.Id = "Task|" + taskFullPath;
                        entry.Name = taskName;
                        entry.DisplayName = MakeFriendlyName(taskName, !string.IsNullOrEmpty(secTarget) ? secTarget : resolvedExe);
                        entry.Publisher = author;
                        entry.RawCommand = rawCmd;
                        entry.ResolvedExePath = resolvedExe;
                        entry.SecondaryTargetPath = secTarget;
                        entry.SourceKind = "Task";
                        entry.ScheduledTaskPath = taskFullPath;
                        entry.TriggerInfo = triggerDesc;
                        entry.OrphanReason = orphanReason;
                        entry.Enabled = taskEnabled && anyStartupTrigEnabled;
                        entry.IsPolicyLocked = false;
                        entry.IsOrphan = isMissing;
                        entry.ProtectionKind = IsProtectedOemOrSystemStartup(entry.DisplayName, rawCmd + " " + taskFullPath + " " + author, author);
                        entry.ImpactLevel = EstimateImpact(entry.DisplayName, rawCmd + " " + taskFullPath, author);
                        entry.RequiresAdmin = reqAdmin;
                        entry.CanDelete = true;
                        entry.CanToggle = true;
                        entry.MetadataHydrated = false;
                        list.Add(entry);
                    } catch {}
                }
            } catch {}

            try {
                object subFolders = ComCall(folder, "GetFolders", 0);
                int fCount = Convert.ToInt32(ComGet(subFolders, "Count"), CultureInfo.InvariantCulture);
                for (int fi = 1; fi <= fCount; fi++) {
                    try {
                        object sf = ComGetIndexed(subFolders, "Item", fi);
                        if (sf != null) TraverseScheduledTaskFolder(sf, list, fixedRoots, currentUserName);
                    } catch {}
                }
            } catch {}
        }

        private static void ScanScheduledTasks(List<StartupEntry> list, HashSet<string> fixedRoots) {
            object svc = null;
            string curUser = "";
            try { curUser = Environment.UserName ?? ""; } catch {}
            try {
                svc = ConnectTaskService();
                if (svc == null) return;
                object root = ComCall(svc, "GetFolder", @"\");
                if (root != null) {
                    TraverseScheduledTaskFolder(root, list, fixedRoots, curUser);
                }
            } catch {
            } finally {
                if (svc != null) {
                    try { Marshal.ReleaseComObject(svc); } catch {}
                }
            }
        }

        private static string GetServiceStateStorePath() {
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(Path.Combine(local, "AppDriver"), "StartupServiceState.txt");
        }

        private sealed class TrackedServiceInfo {
            public int OrigStart;
            public bool DelayedAuto;
        }

        private static Dictionary<string, TrackedServiceInfo> LoadTrackedDisabledServices() {
            var map = new Dictionary<string, TrackedServiceInfo>(StringComparer.OrdinalIgnoreCase);
            try {
                string path = GetServiceStateStorePath();
                if (!File.Exists(path)) return map;
                string[] lines = File.ReadAllLines(path, Encoding.UTF8);
                for (int i = 0; i < lines.Length; i++) {
                    string ln = (lines[i] ?? "").Trim();
                    if (string.IsNullOrEmpty(ln)) continue;
                    string[] parts = ln.Split('|');
                    if (parts.Length >= 3 && !string.IsNullOrWhiteSpace(parts[0])) {
                        int origStart;
                        if (!int.TryParse(parts[1], out origStart)) origStart = 2;
                        bool delayed = parts[2] == "1";
                        map[parts[0].Trim()] = new TrackedServiceInfo { OrigStart = origStart, DelayedAuto = delayed };
                    }
                }
            } catch {}
            return map;
        }

        private static void SaveTrackedDisabledServices(Dictionary<string, TrackedServiceInfo> map) {
            try {
                string path = GetServiceStateStorePath();
                string dir = Path.GetDirectoryName(path);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir)) Directory.CreateDirectory(dir);
                var lines = new List<string>(map.Count);
                foreach (KeyValuePair<string, TrackedServiceInfo> kv in map) {
                    lines.Add(kv.Key + "|" + kv.Value.OrigStart + "|" + (kv.Value.DelayedAuto ? "1" : "0"));
                }
                File.WriteAllLines(path, lines.ToArray(), new UTF8Encoding(false));
            } catch {}
        }

        private static bool IsBuiltInWindowsServiceImage(string resolvedExe, string rawImg, string serviceName) {
            if (string.IsNullOrWhiteSpace(rawImg)) return true;
            string lowRaw = rawImg.ToLowerInvariant();
            if (lowRaw.Contains("svchost.exe") || lowRaw.Contains("services.exe") || lowRaw.Contains("lsass.exe") ||
                lowRaw.Contains("wininit.exe") || lowRaw.Contains("spoolsv.exe") || lowRaw.Contains("searchindexer.exe")) {
                return true;
            }
            string winDir = "";
            try { winDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows).TrimEnd('\\') + "\\"; } catch {}
            if (!string.IsNullOrEmpty(winDir) && !string.IsNullOrEmpty(resolvedExe) &&
                resolvedExe.StartsWith(winDir, StringComparison.OrdinalIgnoreCase)) {
                return true;
            }
            string lowExe = (resolvedExe ?? "").ToLowerInvariant();
            if (lowExe.Contains(@"\windows defender") ||
                lowExe.Contains(@"\windows media player\") ||
                lowExe.Contains(@"\microsoft update health tools\") ||
                lowExe.Contains(@"\windowsapps\microsoft.") ||
                lowExe.Contains(@"\windowsapps\microsoftcorporationii.windowssubsystemforlinux") ||
                lowExe.Contains(@"\microsoft gameinput\") ||
                lowExe.Contains(@"\wsl\wslservice.exe")) {
                return true;
            }
            if (string.Equals(serviceName, "Sense", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(serviceName, "WinDefend", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(serviceName, "MDCoreSvc", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(serviceName, "WdNisSvc", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(serviceName, "WMPNetworkSvc", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(serviceName, "uhssvc", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(serviceName, "WSLService", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(serviceName, "WslInstaller", StringComparison.OrdinalIgnoreCase)) {
                return true;
            }
            return false;
        }

        private static string ResolveServiceDisplayName(string rawDisp, string serviceName) {
            if (string.IsNullOrWhiteSpace(rawDisp)) return serviceName;
            string d = rawDisp.Trim();
            if (d.StartsWith("@", StringComparison.Ordinal)) {
                string loaded = TryLoadIndirect(d);
                return !string.IsNullOrEmpty(loaded) ? loaded : serviceName;
            }
            return d;
        }

        private static bool CanChangeServiceConfig(IntPtr scmHandle, string serviceName) {
            if (scmHandle == IntPtr.Zero || string.IsNullOrWhiteSpace(serviceName)) return true;
            IntPtr hSvc = IntPtr.Zero;
            try {
                hSvc = OpenServiceW(scmHandle, serviceName, SERVICE_CHANGE_CONFIG);
                if (hSvc != IntPtr.Zero) return true;
                int err = Marshal.GetLastWin32Error();
                return (err != 5);
            } catch {
                return true;
            } finally {
                if (hSvc != IntPtr.Zero) CloseServiceHandle(hSvc);
            }
        }

        private static void ScanThirdPartyStartupServices(List<StartupEntry> list, HashSet<string> fixedRoots) {
            Dictionary<string, TrackedServiceInfo> tracked = LoadTrackedDisabledServices();
            bool isAdmin = IsCurrentProcessAdmin();
            IntPtr scm = IntPtr.Zero;
            if (isAdmin) {
                try { scm = OpenSCManagerW(null, null, SC_MANAGER_CONNECT); } catch { scm = IntPtr.Zero; }
            }
            try {
                using (RegistryKey hklm = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                using (RegistryKey svcsRoot = hklm.OpenSubKey(RegServicesPath, false)) {
                    if (svcsRoot == null) return;
                    string[] names = svcsRoot.GetSubKeyNames();
                    for (int i = 0; i < names.Length; i++) {
                        string svcName = names[i];
                        if (string.IsNullOrEmpty(svcName)) continue;
                        try {
                            using (RegistryKey sk = svcsRoot.OpenSubKey(svcName, false)) {
                                if (sk == null) continue;
                                object typeObj = sk.GetValue("Type");
                                object startObj = sk.GetValue("Start");
                                if (typeObj == null || startObj == null) continue;
                                int svcType = Convert.ToInt32(typeObj, CultureInfo.InvariantCulture);
                                // Win32 OwnProcess (0x10) or ShareProcess (0x20) only; skip kernel/FS drivers
                                if ((svcType & 0x30) == 0) continue;

                                int startType = Convert.ToInt32(startObj, CultureInfo.InvariantCulture);
                                if (startType < 2 || startType > 4) continue;

                                string rawImg = Convert.ToString(sk.GetValue("ImagePath"), CultureInfo.InvariantCulture) ?? "";
                                if (string.IsNullOrWhiteSpace(rawImg)) continue;

                                bool isMissing;
                                string resolvedExe = ResolveExecutablePathInternal(rawImg, fixedRoots, out isMissing);
                                if (IsBuiltInWindowsServiceImage(resolvedExe, rawImg, svcName)) continue;

                                TrackedServiceInfo trackedInfo;
                                bool isTracked = tracked.TryGetValue(svcName, out trackedInfo);

                                // Include Auto-start (2), previously disabled by App-Driver, or Orphan services (missing binary)
                                if (startType != 2 && !isTracked && !isMissing) continue;

                                bool delayed = false;
                                try {
                                    object delObj = sk.GetValue("DelayedAutostart");
                                    if (delObj != null) delayed = Convert.ToInt32(delObj, CultureInfo.InvariantCulture) == 1;
                                } catch {}
                                if (isTracked && trackedInfo.DelayedAuto) delayed = true;

                                bool isPackagedSvc = (svcType & 0x200) != 0;
                                bool isProtectedLock = false;
                                if (!isMissing && !isPackagedSvc && isAdmin && scm != IntPtr.Zero) {
                                    isProtectedLock = !CanChangeServiceConfig(scm, svcName);
                                }

                                string rawDisp = Convert.ToString(sk.GetValue("DisplayName"), CultureInfo.InvariantCulture) ?? "";
                                string dispName = CleanDisplayName(ResolveServiceDisplayName(rawDisp, svcName));
                                if (isPackagedSvc &&
                                    dispName.IndexOf("Service", StringComparison.OrdinalIgnoreCase) < 0 &&
                                    dispName.IndexOf("D\u1ECBch v\u1EE5", StringComparison.OrdinalIgnoreCase) < 0) {
                                    dispName = dispName + " (D\u1ECBch v\u1EE5 MSIX)";
                                }

                                bool enabled = (startType == 2);
                                string lockKind = isPackagedSvc ? "Msix" : (isProtectedLock ? "Protected" : "");
                                string trigInfo;
                                if (isPackagedSvc) {
                                    trigInfo = "D\u1ECBch v\u1EE5 \u0111\u00F3ng g\u00F3i MSIX (Windows AppXSvc kh\u00F3a - qu\u1EA3n l\u00FD qua m\u1EE5c Store)";
                                } else if (isProtectedLock) {
                                    trigInfo = "D\u1ECBch v\u1EE5 \u0111\u01B0\u1EE3c b\u1EA3o v\u1EC7 ch\u1ED1ng can thi\u1EC7p (Self-Defense / H\u1EC7 th\u1ED1ng)";
                                } else {
                                    trigInfo = enabled
                                        ? (delayed ? "D\u1ECBch v\u1EE5 t\u1EF1 \u0111\u1ED9ng tr\u1EC5 (Auto-Delayed)" : "D\u1ECBch v\u1EE5 t\u1EF1 \u0111\u1ED9ng (Auto)")
                                        : (startType == 3 ? "D\u1ECBch v\u1EE5 th\u1EE7 c\u00F4ng (Manual)" : "D\u1ECBch v\u1EE5 \u0111\u00E3 v\u00F4 hi\u1EC7u h\u00F3a (Disabled)");
                                }

                                var entry = new StartupEntry();
                                entry.Id = "Service|" + svcName;
                                entry.Name = svcName;
                                entry.DisplayName = dispName;
                                entry.Publisher = "";
                                entry.RawCommand = rawImg;
                                entry.ResolvedExePath = resolvedExe;
                                entry.SourceKind = "Service";
                                entry.RegistryHive = "HKLM";
                                entry.RegistryPath = RegServicesPath + @"\" + svcName;
                                entry.RegistryValueName = "ImagePath";
                                entry.ServiceName = svcName;
                                entry.ServiceOrigStart = isTracked ? trackedInfo.OrigStart : startType;
                                entry.ServiceDelayedAuto = delayed;
                                entry.TriggerInfo = trigInfo;
                                entry.OrphanReason = isMissing ? "D\u1ECBch v\u1EE5 ch\u1EA1y ng\u1EA7m tr\u1ECF t\u1EDBi t\u1EC7p \u0111\u00E3 b\u1ECB x\u00F3a" : "";
                                entry.Enabled = enabled;
                                entry.IsPolicyLocked = false;
                                entry.LockKind = lockKind;
                                entry.IsOrphan = isMissing;
                                entry.ProtectionKind = IsProtectedOemOrSystemStartup(dispName + " " + svcName, rawImg, "");
                                entry.ImpactLevel = EstimateImpact(dispName + " " + svcName, rawImg, "");
                                entry.RequiresAdmin = true;
                                entry.CanDelete = isMissing && !isPackagedSvc && !isProtectedLock;
                                entry.CanToggle = !isMissing && !isPackagedSvc && !isProtectedLock;
                                entry.MetadataHydrated = false;
                                list.Add(entry);
                            }
                        } catch {}
                    }
                }
            } catch {
            } finally {
                if (scm != IntPtr.Zero) CloseServiceHandle(scm);
            }
        }

        public static StartupEntry[] ScanExtended() {
            var list = new List<StartupEntry>(64);
            HashSet<string> fixedRoots = GetMountedFixedDriveRoots();
            ScanUwpStartupTasks(list);
            ScanScheduledTasks(list, fixedRoots);
            ScanThirdPartyStartupServices(list, fixedRoots);
            return list.ToArray();
        }

        public static Task<StartupEntry[]> ScanExtendedAsync() {
            return Task.Run(delegate() { return ScanExtended(); });
        }

        private static void CollectOrphanApprovedEntries(
            List<StartupEntry> list,
            string hive,
            string approvedPath,
            string detailLabel,
            HashSet<string> liveNames,
            bool requiresAdmin) {
            try {
                using (RegistryKey baseKey = OpenBase64(hive))
                using (RegistryKey apKey = baseKey.OpenSubKey(approvedPath, false)) {
                    if (apKey == null) return;
                    string[] apNames = apKey.GetValueNames();
                    for (int i = 0; i < apNames.Length; i++) {
                        string vn = apNames[i];
                        if (string.IsNullOrEmpty(vn)) continue;
                        if (!liveNames.Contains(vn)) {
                            var entry = new StartupEntry();
                            entry.Id = "OrphanApproved|" + hive + "|" + approvedPath + "|" + vn;
                            entry.Name = vn;
                            entry.DisplayName = MakeFriendlyName(vn, "");
                            entry.Publisher = "StartupApproved (" + hive + ")";
                            entry.RawCommand = hive + @"\" + approvedPath + " [" + vn + "]";
                            entry.ResolvedExePath = "";
                            entry.SourceKind = "OrphanApproved";
                            entry.RegistryHive = hive;
                            entry.RegistryPath = approvedPath;
                            entry.RegistryValueName = vn;
                            entry.ApprovedHive = hive;
                            entry.ApprovedPath = approvedPath;
                            entry.ApprovedValueName = vn;
                            entry.TriggerInfo = detailLabel;
                            entry.OrphanReason = "Kh\u00F3a r\u00E1c StartupApproved c\u1EE7a \u1EE9ng d\u1EE5ng \u0111\u00E3 g\u1EE1 ho\u1EB7c \u0111\u00E3 t\u1EAFt kh\u1EDFi ch\u1EA1y";
                            entry.IsOrphanApprovedGhost = true;
                            entry.Enabled = false;
                            entry.IsPolicyLocked = false;
                            entry.IsOrphan = true;
                            entry.ProtectionKind = "";
                            entry.ImpactLevel = "Low";
                            entry.RequiresAdmin = requiresAdmin;
                            entry.CanDelete = true;
                            entry.CanToggle = false;
                            entry.MetadataHydrated = true;
                            list.Add(entry);
                        }
                    }
                }
            } catch {}
        }

        public static StartupEntry[] ScanOrphanApprovedEntries() {
            var list = new List<StartupEntry>(16);
            CollectOrphanApprovedEntries(list, "HKCU", RegApprovedRunPath, "R\u00E1c StartupApproved (HKCU\\Run)", GetRegValueNameSet("HKCU", RegRunPath), false);
            CollectOrphanApprovedEntries(list, "HKCU", RegApprovedRun32Path, "R\u00E1c StartupApproved (HKCU\\Run32)", GetRegValueNameSet("HKCU", RegRunWow32Path), false);
            CollectOrphanApprovedEntries(list, "HKLM", RegApprovedRunPath, "R\u00E1c StartupApproved (HKLM\\Run)", GetRegValueNameSet("HKLM", RegRunPath), true);
            CollectOrphanApprovedEntries(list, "HKLM", RegApprovedRun32Path, "R\u00E1c StartupApproved (HKLM\\Run32)", GetRegValueNameSet("HKLM", RegRunWow32Path), true);
            try {
                string uDir = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
                CollectOrphanApprovedEntries(list, "HKCU", RegApprovedFolderPath, "R\u00E1c StartupApproved (User Folder)", GetFolderFileNameSet(uDir), false);
            } catch {}
            try {
                string cDir = Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup);
                CollectOrphanApprovedEntries(list, "HKLM", RegApprovedFolderPath, "R\u00E1c StartupApproved (All Users Folder)", GetFolderFileNameSet(cDir), true);
            } catch {}
            return list.ToArray();
        }

        public static Task<StartupEntry[]> ScanOrphanApprovedEntriesAsync() {
            return Task.Run(delegate() { return ScanOrphanApprovedEntries(); });
        }

        public static BitmapSource ExtractStartupIcon(string path) {
            if (string.IsNullOrWhiteSpace(path)) return null;
            BitmapSource cached;
            if (_iconCache.TryGetValue(path, out cached)) return cached;
            if (!File.Exists(path)) return null;

            BitmapSource res = null;
            try {
                string ext = Path.GetExtension(path) ?? "";
                if (ext.Equals(".png", StringComparison.OrdinalIgnoreCase) ||
                    ext.Equals(".jpg", StringComparison.OrdinalIgnoreCase) ||
                    ext.Equals(".jpeg", StringComparison.OrdinalIgnoreCase) ||
                    ext.Equals(".bmp", StringComparison.OrdinalIgnoreCase)) {
                    byte[] bytes = File.ReadAllBytes(path);
                    using (var ms = new MemoryStream(bytes)) {
                        var bi = new BitmapImage();
                        bi.BeginInit();
                        bi.CacheOption = BitmapCacheOption.OnLoad;
                        bi.DecodePixelWidth = 32;
                        bi.StreamSource = ms;
                        bi.EndInit();
                        bi.Freeze();
                        res = bi;
                    }
                } else {
                    using (Icon assoc = Icon.ExtractAssociatedIcon(path)) {
                        if (assoc != null) {
                            BitmapSource bs = Imaging.CreateBitmapSourceFromHIcon(
                                assoc.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                            bs.Freeze();
                            res = bs;
                        }
                    }
                }
            } catch {}

            if (res != null) {
                _iconCache[path] = res;
            }
            return res;
        }

        private static bool ShouldReplaceDisplayName(string currentDisp, string exePath, string sourceKind) {
            if (string.IsNullOrWhiteSpace(currentDisp)) return true;
            if (currentDisp.IndexOf("AutoLaunch", StringComparison.OrdinalIgnoreCase) >= 0) return true;
            if (currentDisp.StartsWith("Autorun for ", StringComparison.OrdinalIgnoreCase)) return true;
            if (currentDisp.Equals("Update", StringComparison.OrdinalIgnoreCase)) return true;
            if (!string.IsNullOrEmpty(exePath)) {
                string stem = Path.GetFileNameWithoutExtension(exePath) ?? "";
                if (currentDisp.Equals(stem, StringComparison.OrdinalIgnoreCase)) return true;
            }
            if (string.Equals(sourceKind, "Task", StringComparison.OrdinalIgnoreCase)) {
                if (currentDisp.Equals("StartCN", StringComparison.OrdinalIgnoreCase) ||
                    currentDisp.Equals("StartDVR", StringComparison.OrdinalIgnoreCase) ||
                    currentDisp.IndexOf("Startup Task", StringComparison.OrdinalIgnoreCase) >= 0) {
                    return true;
                }
            }
            return false;
        }

        public static StartupHydratedPatch[] HydrateEntriesAndIcons(StartupEntry[] entries) {
            if (entries == null || entries.Length == 0) return new StartupHydratedPatch[0];
            var results = new StartupHydratedPatch[entries.Length];
            var pOpts = new ParallelOptions { MaxDegreeOfParallelism = 4 };
            Parallel.For(0, entries.Length, pOpts, delegate(int i) {
                StartupEntry e = entries[i];
                if (e == null) return;
                string disp = CleanDisplayName(e.DisplayName ?? "");
                string pub = IsJunkPublisher(e.Publisher) ? "" : (e.Publisher ?? "").Trim();

                string metaTarget = (!string.IsNullOrWhiteSpace(e.SecondaryTargetPath) && File.Exists(e.SecondaryTargetPath))
                    ? e.SecondaryTargetPath
                    : e.ResolvedExePath;

                if (!e.MetadataHydrated && !string.IsNullOrWhiteSpace(metaTarget) && File.Exists(metaTarget)) {
                    try {
                        string ext = Path.GetExtension(metaTarget) ?? "";
                        if (ext.Equals(".exe", StringComparison.OrdinalIgnoreCase) || ext.Equals(".dll", StringComparison.OrdinalIgnoreCase)) {
                            FileVersionInfo fvi = FileVersionInfo.GetVersionInfo(metaTarget);
                            if (fvi != null) {
                                string fd = CleanDisplayName(fvi.FileDescription ?? "");
                                string pn = CleanDisplayName(fvi.ProductName ?? "");
                                string cn = (fvi.CompanyName ?? "").Trim();
                                if (!IsJunkPublisher(cn) && string.IsNullOrEmpty(pub)) {
                                    pub = cn;
                                }
                                if (ShouldReplaceDisplayName(disp, metaTarget, e.SourceKind)) {
                                    string better = "";
                                    if (!string.IsNullOrEmpty(pn) && pn.Length >= 3 && pn.Length <= 64 &&
                                        !pn.Equals("Operating System", StringComparison.OrdinalIgnoreCase) &&
                                        !pn.StartsWith("Microsoft Windows", StringComparison.OrdinalIgnoreCase)) {
                                        better = pn;
                                    }
                                    if (string.IsNullOrEmpty(better) && !string.IsNullOrEmpty(fd) && fd.Length >= 3 && fd.Length <= 64) {
                                        better = fd;
                                    }
                                    if (!string.IsNullOrEmpty(better)) {
                                        if (string.Equals(e.SourceKind, "Task", StringComparison.OrdinalIgnoreCase) &&
                                            !string.IsNullOrEmpty(e.Name) &&
                                            (e.Name.Equals("StartCN", StringComparison.OrdinalIgnoreCase) ||
                                             e.Name.Equals("StartDVR", StringComparison.OrdinalIgnoreCase))) {
                                            disp = better + " (" + e.Name + ")";
                                        } else {
                                            disp = better;
                                        }
                                    }
                                }
                            }
                            if (string.IsNullOrEmpty(pub)) {
                                string certOrg = ExtractSignerOrganization(metaTarget);
                                if (!IsJunkPublisher(certOrg)) pub = certOrg;
                            }
                        }
                    } catch {}
                }

                string iconSource = "";
                if (!string.IsNullOrWhiteSpace(e.LogoPath) && File.Exists(e.LogoPath)) {
                    iconSource = e.LogoPath;
                } else if (!string.IsNullOrWhiteSpace(e.SecondaryTargetPath) && File.Exists(e.SecondaryTargetPath)) {
                    iconSource = e.SecondaryTargetPath;
                } else if (!string.IsNullOrWhiteSpace(e.IconHintPath) && File.Exists(e.IconHintPath)) {
                    iconSource = e.IconHintPath;
                } else if (!string.IsNullOrWhiteSpace(e.ResolvedExePath) && File.Exists(e.ResolvedExePath)) {
                    iconSource = e.ResolvedExePath;
                } else if (!string.IsNullOrWhiteSpace(e.FolderFilePath) && File.Exists(e.FolderFilePath)) {
                    iconSource = e.FolderFilePath;
                }
                BitmapSource bmp = ExtractStartupIcon(iconSource);

                string prot = e.IsOrphanApprovedGhost
                    ? ""
                    : IsProtectedOemOrSystemStartup(disp + " " + e.Name, e.RawCommand + " " + e.SecondaryTargetPath, pub);
                string imp = e.IsOrphanApprovedGhost
                    ? "Low"
                    : RefineImpactFromFootprint(
                        EstimateImpact(disp + " " + e.Name, e.RawCommand + " " + e.SecondaryTargetPath, pub),
                        metaTarget);

                var patch = new StartupHydratedPatch();
                patch.Id = e.Id;
                patch.DisplayName = disp;
                patch.Publisher = pub;
                patch.ProtectionKind = prot;
                patch.ImpactLevel = imp;
                patch.IconBitmap = bmp;
                results[i] = patch;
            });

            var patches = new List<StartupHydratedPatch>(entries.Length);
            for (int i = 0; i < results.Length; i++) {
                if (results[i] != null) patches.Add(results[i]);
            }
            return patches.ToArray();
        }

        public static Task<StartupHydratedPatch[]> HydrateEntriesAndIconsAsync(StartupEntry[] entries) {
            return Task.Run(delegate() { return HydrateEntriesAndIcons(entries); });
        }

        public static byte[] ReadStartupApprovedBytes(StartupEntry entry) {
            if (entry == null || string.IsNullOrWhiteSpace(entry.ApprovedPath) || string.IsNullOrWhiteSpace(entry.ApprovedValueName)) {
                return null;
            }
            try {
                using (RegistryKey baseKey = OpenBase64(entry.ApprovedHive))
                using (RegistryKey k = baseKey.OpenSubKey(entry.ApprovedPath, false)) {
                    if (k == null) return null;
                    return k.GetValue(entry.ApprovedValueName) as byte[];
                }
            } catch {
                return null;
            }
        }

        public static bool WriteStartupApprovedBytes(string hive, string path, string valueName, byte[] data) {
            if (string.IsNullOrWhiteSpace(path) || string.IsNullOrWhiteSpace(valueName)) return false;
            try {
                using (RegistryKey baseKey = OpenBase64(hive)) {
                    if (data == null || data.Length == 0) {
                        using (RegistryKey k = baseKey.OpenSubKey(path, true)) {
                            if (k != null) k.DeleteValue(valueName, false);
                        }
                        return true;
                    }
                    using (RegistryKey k = baseKey.CreateSubKey(path, RegistryKeyPermissionCheck.ReadWriteSubTree)) {
                        if (k == null) return false;
                        k.SetValue(valueName, data, RegistryValueKind.Binary);
                        return true;
                    }
                }
            } catch {
                return false;
            }
        }

        private static void PopulateAccessDeniedResult(StartupOpResult res, string fallbackMsg) {
            if (IsCurrentProcessAdmin()) {
                res.RequiresAdminError = false;
                res.Message = "M\u1EE5c n\u00E0y \u0111\u01B0\u1EE3c b\u1EA3o v\u1EC7 ch\u1ED1ng can thi\u1EC7p (Self-Defense / H\u1EC7 th\u1ED1ng) n\u00EAn Windows t\u1EEB ch\u1ED1i thay \u0111\u1ED5i.";
            } else {
                res.RequiresAdminError = true;
                res.Message = fallbackMsg;
            }
        }

        private static StartupOpResult SetServiceStartupEnabled(StartupEntry entry, bool enable) {
            var res = new StartupOpResult { Success = false, RequiresAdminError = false, Message = "" };
            if (string.IsNullOrWhiteSpace(entry.ServiceName)) {
                res.Message = "InvalidServiceName";
                return res;
            }
            IntPtr scm = IntPtr.Zero;
            IntPtr svc = IntPtr.Zero;
            try {
                scm = OpenSCManagerW(null, null, SC_MANAGER_CONNECT);
                if (scm == IntPtr.Zero) {
                    int err = Marshal.GetLastWin32Error();
                    if (err == 5) PopulateAccessDeniedResult(res, "OpenSCManagerFailed:5");
                    else res.Message = "OpenSCManagerFailed:" + err;
                    return res;
                }
                svc = OpenServiceW(scm, entry.ServiceName, SERVICE_CHANGE_CONFIG | SERVICE_QUERY_CONFIG);
                if (svc == IntPtr.Zero) {
                    int err = Marshal.GetLastWin32Error();
                    if (err == 5) PopulateAccessDeniedResult(res, "OpenServiceFailed:5");
                    else res.Message = "OpenServiceFailed:" + err;
                    return res;
                }
                uint targetStart = enable ? SERVICE_AUTO_START : SERVICE_DEMAND_START;
                bool ok = ChangeServiceConfigW(
                    svc,
                    SERVICE_NO_CHANGE,
                    targetStart,
                    SERVICE_NO_CHANGE,
                    null,
                    null,
                    IntPtr.Zero,
                    null,
                    null,
                    null,
                    null);
                if (!ok) {
                    int err = Marshal.GetLastWin32Error();
                    if (err == 5) PopulateAccessDeniedResult(res, "ChangeServiceConfigFailed:5");
                    else res.Message = "ChangeServiceConfigFailed:" + err;
                    return res;
                }

                Dictionary<string, TrackedServiceInfo> tracked = LoadTrackedDisabledServices();
                if (enable) {
                    if (entry.ServiceDelayedAuto) {
                        try {
                            using (RegistryKey hklm = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                            using (RegistryKey sk = hklm.OpenSubKey(RegServicesPath + @"\" + entry.ServiceName, true)) {
                                if (sk != null) sk.SetValue("DelayedAutostart", 1, RegistryValueKind.DWord);
                            }
                        } catch {}
                    }
                    tracked.Remove(entry.ServiceName);
                    SaveTrackedDisabledServices(tracked);
                    entry.TriggerInfo = entry.ServiceDelayedAuto
                        ? "D\u1ECBch v\u1EE5 t\u1EF1 \u0111\u1ED9ng tr\u1EC5 (Auto-Delayed)"
                        : "D\u1ECBch v\u1EE5 t\u1EF1 \u0111\u1ED9ng (Auto)";
                } else {
                    tracked[entry.ServiceName] = new TrackedServiceInfo {
                        OrigStart = entry.ServiceOrigStart > 0 ? entry.ServiceOrigStart : 2,
                        DelayedAuto = entry.ServiceDelayedAuto
                    };
                    SaveTrackedDisabledServices(tracked);
                    entry.TriggerInfo = "D\u1ECBch v\u1EE5 th\u1EE7 c\u00F4ng (Manual)";
                }

                entry.Enabled = enable;
                res.Success = true;
                return res;
            } catch (UnauthorizedAccessException) {
                res.RequiresAdminError = true;
                res.Message = "AccessDenied";
                return res;
            } catch (Exception ex) {
                res.RequiresAdminError = true;
                res.Message = ex.Message;
                return res;
            } finally {
                if (svc != IntPtr.Zero) CloseServiceHandle(svc);
                if (scm != IntPtr.Zero) CloseServiceHandle(scm);
            }
        }

        public static StartupOpResult SetStartupEnabled(StartupEntry entry, bool enable) {
            var res = new StartupOpResult { Success = false, RequiresAdminError = false, Message = "" };
            if (entry == null) { res.Message = "Invalid entry"; return res; }
            if (entry.IsPolicyLocked) {
                res.Message = "PolicyLocked";
                return res;
            }
            if (!entry.CanToggle) {
                res.Message = "ToggleNotSupported";
                return res;
            }

            if (string.Equals(entry.SourceKind, "Service", StringComparison.OrdinalIgnoreCase)) {
                return SetServiceStartupEnabled(entry, enable);
            }

            if (string.Equals(entry.SourceKind, "Store", StringComparison.OrdinalIgnoreCase)) {
                try {
                    string subPath = RegSystemAppDataPath + @"\" + entry.PackageFamilyName + @"\" + entry.TaskId;
                    using (RegistryKey hkcu = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64))
                    using (RegistryKey k = hkcu.CreateSubKey(subPath, RegistryKeyPermissionCheck.ReadWriteSubTree)) {
                        if (k == null) { res.Message = "CannotCreateStoreKey"; return res; }
                        int targetState = enable ? 2 : 1;
                        k.SetValue("State", targetState, RegistryValueKind.DWord);
                        if (enable) {
                            k.SetValue("UserEnabledStartupOnce", 1, RegistryValueKind.DWord);
                        }
                        entry.UwpState = targetState;
                        entry.Enabled = enable;
                        res.Success = true;
                        return res;
                    }
                } catch (Exception ex) {
                    res.Message = ex.Message;
                    return res;
                }
            }

            if (string.Equals(entry.SourceKind, "Task", StringComparison.OrdinalIgnoreCase)) {
                object svc = null;
                try {
                    svc = ConnectTaskService();
                    if (svc == null) { res.Message = "TaskServiceUnavailable"; return res; }
                    string tp = entry.ScheduledTaskPath ?? "";
                    int lastSlash = tp.LastIndexOf('\\');
                    string folderPath = lastSlash > 0 ? tp.Substring(0, lastSlash) : @"\";
                    string taskName = lastSlash >= 0 ? tp.Substring(lastSlash + 1) : tp;
                    object folder = ComCall(svc, "GetFolder", folderPath);
                    object task = ComCall(folder, "GetTask", taskName);
                    ComSet(task, "Enabled", enable);
                    if (enable) {
                        try {
                            object def = ComGet(task, "Definition");
                            object triggers = def != null ? ComGet(def, "Triggers") : null;
                            if (triggers != null) {
                                int tCount = Convert.ToInt32(ComGet(triggers, "Count"), CultureInfo.InvariantCulture);
                                bool needSave = false;
                                for (int ti = 1; ti <= tCount; ti++) {
                                    object trig = ComGetIndexed(triggers, "Item", ti);
                                    int trigType = Convert.ToInt32(ComGet(trig, "Type"), CultureInfo.InvariantCulture);
                                    if (trigType == 8 || trigType == 9 || trigType == 11) {
                                        bool tEn = true;
                                        try { tEn = Convert.ToBoolean(ComGet(trig, "Enabled"), CultureInfo.InvariantCulture); } catch {}
                                        if (!tEn) {
                                            ComSet(trig, "Enabled", true);
                                            needSave = true;
                                        }
                                    }
                                }
                                if (needSave) {
                                    string updatedXml = Convert.ToString(ComGet(def, "XmlText"), CultureInfo.InvariantCulture) ?? "";
                                    if (!string.IsNullOrWhiteSpace(updatedXml)) {
                                        int logonType = InferLogonTypeFromXml(updatedXml);
                                        ComCall(folder, "RegisterTask", taskName, updatedXml, 6, null, null, logonType, null);
                                    }
                                }
                            }
                        } catch {}
                    }
                    entry.Enabled = enable;
                    res.Success = true;
                    return res;
                } catch (UnauthorizedAccessException) {
                    res.RequiresAdminError = true;
                    res.Message = "AccessDenied";
                    return res;
                } catch (Exception ex) {
                    if (ex.InnerException is UnauthorizedAccessException ||
                        (ex.Message != null && ex.Message.IndexOf("Access", StringComparison.OrdinalIgnoreCase) >= 0)) {
                        res.RequiresAdminError = true;
                    }
                    res.Message = ex.Message;
                    return res;
                } finally {
                    if (svc != null) { try { Marshal.ReleaseComObject(svc); } catch {} }
                }
            }

            try {
                byte[] bytes = BuildApprovedBytes(enable);
                using (RegistryKey baseKey = OpenBase64(entry.ApprovedHive))
                using (RegistryKey k = baseKey.CreateSubKey(entry.ApprovedPath, RegistryKeyPermissionCheck.ReadWriteSubTree)) {
                    if (k == null) { res.RequiresAdminError = entry.RequiresAdmin; res.Message = "CannotOpenApprovedKey"; return res; }
                    k.SetValue(entry.ApprovedValueName, bytes, RegistryValueKind.Binary);
                    entry.Enabled = enable;
                    res.Success = true;
                    return res;
                }
            } catch (UnauthorizedAccessException) {
                res.RequiresAdminError = true;
                res.Message = "AccessDenied";
                return res;
            } catch (Exception ex) {
                res.RequiresAdminError = entry.RequiresAdmin;
                res.Message = ex.Message;
                return res;
            }
        }

        private static int InferLogonTypeFromXml(string xml) {
            if (string.IsNullOrWhiteSpace(xml)) return 3;
            Match m = RxXmlLogonType.Match(xml);
            if (!m.Success) return 0;
            string lt = m.Groups[1].Value.Trim();
            if (lt.Equals("InteractiveToken", StringComparison.OrdinalIgnoreCase)) return 3;
            if (lt.Equals("Group", StringComparison.OrdinalIgnoreCase)) return 4;
            if (lt.Equals("ServiceAccount", StringComparison.OrdinalIgnoreCase)) return 5;
            if (lt.Equals("S4U", StringComparison.OrdinalIgnoreCase)) return 2;
            if (lt.Equals("InteractiveTokenOrPassword", StringComparison.OrdinalIgnoreCase)) return 6;
            if (lt.Equals("Password", StringComparison.OrdinalIgnoreCase)) return 1;
            return 0;
        }

        public static string GetScheduledTaskXml(string taskFullPath) {
            if (string.IsNullOrWhiteSpace(taskFullPath)) return "";
            object svc = null;
            try {
                svc = ConnectTaskService();
                if (svc == null) return "";
                int lastSlash = taskFullPath.LastIndexOf('\\');
                string folderPath = lastSlash > 0 ? taskFullPath.Substring(0, lastSlash) : @"\";
                string taskName = lastSlash >= 0 ? taskFullPath.Substring(lastSlash + 1) : taskFullPath;
                object folder = ComCall(svc, "GetFolder", folderPath);
                object task = ComCall(folder, "GetTask", taskName);
                return Convert.ToString(ComGet(task, "Xml"), CultureInfo.InvariantCulture) ?? "";
            } catch {
                return "";
            } finally {
                if (svc != null) { try { Marshal.ReleaseComObject(svc); } catch {} }
            }
        }

        public static StartupOpResult RegisterScheduledTaskFromXml(string taskFullPath, string xml) {
            var res = new StartupOpResult { Success = false, RequiresAdminError = false, Message = "" };
            if (string.IsNullOrWhiteSpace(taskFullPath) || string.IsNullOrWhiteSpace(xml)) {
                res.Message = "InvalidXml";
                return res;
            }
            object svc = null;
            try {
                svc = ConnectTaskService();
                if (svc == null) { res.Message = "TaskServiceUnavailable"; return res; }
                int lastSlash = taskFullPath.LastIndexOf('\\');
                string folderPath = lastSlash > 0 ? taskFullPath.Substring(0, lastSlash) : @"\";
                string taskName = lastSlash >= 0 ? taskFullPath.Substring(lastSlash + 1) : taskFullPath;
                object folder = ComCall(svc, "GetFolder", folderPath);
                int logonType = InferLogonTypeFromXml(xml);
                ComCall(folder, "RegisterTask", taskName, xml, 6, null, null, logonType, null);
                res.Success = true;
                return res;
            } catch (Exception ex) {
                res.Message = (ex.InnerException != null ? ex.InnerException.Message : ex.Message);
                return res;
            } finally {
                if (svc != null) { try { Marshal.ReleaseComObject(svc); } catch {} }
            }
        }

        public static StartupOpResult DeleteStartupEntry(StartupEntry entry) {
            var res = new StartupOpResult { Success = false, RequiresAdminError = false, Message = "" };
            if (entry == null) { res.Message = "InvalidEntry"; return res; }
            if (!entry.CanDelete || string.Equals(entry.SourceKind, "Store", StringComparison.OrdinalIgnoreCase)) {
                res.Message = "DeleteNotAllowed";
                return res;
            }

            if (string.Equals(entry.SourceKind, "OrphanApproved", StringComparison.OrdinalIgnoreCase)) {
                try {
                    using (RegistryKey baseKey = OpenBase64(entry.ApprovedHive))
                    using (RegistryKey k = baseKey.OpenSubKey(entry.ApprovedPath, true)) {
                        if (k != null) {
                            k.DeleteValue(entry.ApprovedValueName, false);
                        }
                    }
                    res.Success = true;
                    return res;
                } catch (UnauthorizedAccessException) {
                    res.RequiresAdminError = true;
                    res.Message = "AccessDenied";
                    return res;
                } catch (Exception ex) {
                    res.RequiresAdminError = entry.RequiresAdmin;
                    res.Message = ex.Message;
                    return res;
                }
            }

            if (string.Equals(entry.SourceKind, "Service", StringComparison.OrdinalIgnoreCase)) {
                if (!entry.IsOrphan) {
                    res.Message = "HealthyServiceDeleteBlocked";
                    return res;
                }
                IntPtr scm = IntPtr.Zero;
                IntPtr svc = IntPtr.Zero;
                try {
                    scm = OpenSCManagerW(null, null, SC_MANAGER_CONNECT);
                    if (scm == IntPtr.Zero) {
                        int err = Marshal.GetLastWin32Error();
                        res.RequiresAdminError = (err == 5);
                        res.Message = "OpenSCManagerFailed:" + err;
                        return res;
                    }
                    svc = OpenServiceW(scm, entry.ServiceName, SERVICE_DELETE);
                    if (svc == IntPtr.Zero) {
                        int err = Marshal.GetLastWin32Error();
                        res.RequiresAdminError = (err == 5);
                        res.Message = "OpenServiceFailed:" + err;
                        return res;
                    }
                    if (!DeleteService(svc)) {
                        int err = Marshal.GetLastWin32Error();
                        res.RequiresAdminError = (err == 5);
                        res.Message = "DeleteServiceFailed:" + err;
                        return res;
                    }
                    Dictionary<string, TrackedServiceInfo> tracked = LoadTrackedDisabledServices();
                    if (tracked.Remove(entry.ServiceName)) SaveTrackedDisabledServices(tracked);
                    res.Success = true;
                    return res;
                } catch (UnauthorizedAccessException) {
                    res.RequiresAdminError = true;
                    res.Message = "AccessDenied";
                    return res;
                } catch (Exception ex) {
                    res.RequiresAdminError = true;
                    res.Message = ex.Message;
                    return res;
                } finally {
                    if (svc != IntPtr.Zero) CloseServiceHandle(svc);
                    if (scm != IntPtr.Zero) CloseServiceHandle(scm);
                }
            }

            if (string.Equals(entry.SourceKind, "Task", StringComparison.OrdinalIgnoreCase)) {
                object svc = null;
                try {
                    svc = ConnectTaskService();
                    if (svc == null) { res.Message = "TaskServiceUnavailable"; return res; }
                    string tp = entry.ScheduledTaskPath ?? "";
                    int lastSlash = tp.LastIndexOf('\\');
                    string folderPath = lastSlash > 0 ? tp.Substring(0, lastSlash) : @"\";
                    string taskName = lastSlash >= 0 ? tp.Substring(lastSlash + 1) : tp;
                    object folder = ComCall(svc, "GetFolder", folderPath);
                    ComCall(folder, "DeleteTask", taskName, 0);
                    res.Success = true;
                    return res;
                } catch (UnauthorizedAccessException) {
                    res.RequiresAdminError = true;
                    res.Message = "AccessDenied";
                    return res;
                } catch (Exception ex) {
                    if (ex.InnerException is UnauthorizedAccessException) res.RequiresAdminError = true;
                    res.Message = (ex.InnerException != null ? ex.InnerException.Message : ex.Message);
                    return res;
                } finally {
                    if (svc != null) { try { Marshal.ReleaseComObject(svc); } catch {} }
                }
            }

            if (string.Equals(entry.SourceKind, "FolderUser", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(entry.SourceKind, "FolderAll", StringComparison.OrdinalIgnoreCase)) {
                try {
                    if (!string.IsNullOrWhiteSpace(entry.FolderFilePath) && File.Exists(entry.FolderFilePath)) {
                        File.Delete(entry.FolderFilePath);
                    }
                    WriteStartupApprovedBytes(entry.ApprovedHive, entry.ApprovedPath, entry.ApprovedValueName, null);
                    res.Success = true;
                    return res;
                } catch (UnauthorizedAccessException) {
                    res.RequiresAdminError = true;
                    res.Message = "AccessDenied";
                    return res;
                } catch (Exception ex) {
                    res.RequiresAdminError = entry.RequiresAdmin;
                    res.Message = ex.Message;
                    return res;
                }
            }

            try {
                using (RegistryKey baseKey = OpenBase64(entry.RegistryHive))
                using (RegistryKey k = baseKey.OpenSubKey(entry.RegistryPath, true)) {
                    if (k != null) {
                        k.DeleteValue(entry.RegistryValueName, false);
                    }
                }
                if (!string.IsNullOrWhiteSpace(entry.ApprovedPath)) {
                    WriteStartupApprovedBytes(entry.ApprovedHive, entry.ApprovedPath, entry.ApprovedValueName, null);
                }
                res.Success = true;
                return res;
            } catch (UnauthorizedAccessException) {
                res.RequiresAdminError = true;
                res.Message = "AccessDenied";
                return res;
            } catch (Exception ex) {
                res.RequiresAdminError = entry.RequiresAdmin;
                res.Message = ex.Message;
                return res;
            }
        }

        public static StartupOpResult AddStartupEntry(string name, string exePath, string args) {
            var res = new StartupOpResult { Success = false, RequiresAdminError = false, Message = "" };
            if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(exePath)) {
                res.Message = "InvalidInput";
                return res;
            }
            try {
                string cleanName = name.Trim();
                string cleanExe = NormalizeCleanPath(exePath);
                if (cleanExe.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase)) {
                    string lnkT, lnkA, lnkIc;
                    bool nonFile;
                    ResolveShortcutLnk(cleanExe, out lnkT, out lnkA, out lnkIc, out nonFile);
                    if (!nonFile && !string.IsNullOrWhiteSpace(lnkT) && File.Exists(lnkT)) {
                        cleanExe = lnkT;
                        if (string.IsNullOrWhiteSpace(args) && !string.IsNullOrWhiteSpace(lnkA)) {
                            args = lnkA;
                        }
                    }
                }
                string cmd = "\"" + cleanExe + "\"" + (string.IsNullOrWhiteSpace(args) ? "" : (" " + args.Trim()));
                using (RegistryKey hkcu = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64)) {
                    using (RegistryKey runKey = hkcu.CreateSubKey(RegRunPath, RegistryKeyPermissionCheck.ReadWriteSubTree)) {
                        if (runKey == null) { res.Message = "CannotOpenRunKey"; return res; }
                        runKey.SetValue(cleanName, cmd, RegistryValueKind.String);
                    }
                    using (RegistryKey apKey = hkcu.CreateSubKey(RegApprovedRunPath, RegistryKeyPermissionCheck.ReadWriteSubTree)) {
                        if (apKey != null) {
                            apKey.SetValue(cleanName, BuildApprovedBytes(true), RegistryValueKind.Binary);
                        }
                    }
                }
                res.Success = true;
                return res;
            } catch (Exception ex) {
                res.Message = ex.Message;
                return res;
            }
        }

        private static HashSet<string> GetRegValueNameSet(string hive, string path) {
            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try {
                using (RegistryKey baseKey = OpenBase64(hive))
                using (RegistryKey k = baseKey.OpenSubKey(path, false)) {
                    if (k == null) return set;
                    string[] names = k.GetValueNames();
                    for (int i = 0; i < names.Length; i++) {
                        if (!string.IsNullOrEmpty(names[i])) set.Add(names[i]);
                    }
                }
            } catch {}
            return set;
        }

        private static HashSet<string> GetFolderFileNameSet(string folderPath) {
            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try {
                if (!string.IsNullOrWhiteSpace(folderPath) && Directory.Exists(folderPath)) {
                    string[] files = Directory.GetFiles(folderPath);
                    for (int i = 0; i < files.Length; i++) {
                        string fn = Path.GetFileName(files[i]);
                        if (!string.IsNullOrEmpty(fn)) set.Add(fn);
                    }
                }
            } catch {}
            return set;
        }

        private static void ProcessOrphanApprovedPair(
            string hive,
            string approvedPath,
            HashSet<string> liveNames,
            bool deleteOrphans,
            List<string> foundOrRemoved,
            ref int skippedAdmin) {
            try {
                using (RegistryKey baseKey = OpenBase64(hive))
                using (RegistryKey apKey = baseKey.OpenSubKey(approvedPath, deleteOrphans)) {
                    if (apKey == null) return;
                    string[] apNames = apKey.GetValueNames();
                    for (int i = 0; i < apNames.Length; i++) {
                        string vn = apNames[i];
                        if (string.IsNullOrEmpty(vn)) continue;
                        if (!liveNames.Contains(vn)) {
                            if (deleteOrphans) {
                                try {
                                    apKey.DeleteValue(vn, false);
                                    foundOrRemoved.Add(hive + @"\" + approvedPath + " [" + vn + "]");
                                } catch (UnauthorizedAccessException) {
                                    skippedAdmin++;
                                } catch {}
                            } else {
                                foundOrRemoved.Add(hive + @"\" + approvedPath + " [" + vn + "]");
                            }
                        }
                    }
                }
            } catch (UnauthorizedAccessException) {
                skippedAdmin++;
            } catch {}
        }

        public static int CountOrphanApprovedEntries() {
            var found = new List<string>();
            int skipped = 0;
            ProcessOrphanApprovedPair("HKCU", RegApprovedRunPath, GetRegValueNameSet("HKCU", RegRunPath), false, found, ref skipped);
            ProcessOrphanApprovedPair("HKCU", RegApprovedRun32Path, GetRegValueNameSet("HKCU", RegRunWow32Path), false, found, ref skipped);
            ProcessOrphanApprovedPair("HKLM", RegApprovedRunPath, GetRegValueNameSet("HKLM", RegRunPath), false, found, ref skipped);
            ProcessOrphanApprovedPair("HKLM", RegApprovedRun32Path, GetRegValueNameSet("HKLM", RegRunWow32Path), false, found, ref skipped);
            try {
                string uDir = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
                ProcessOrphanApprovedPair("HKCU", RegApprovedFolderPath, GetFolderFileNameSet(uDir), false, found, ref skipped);
            } catch {}
            try {
                string cDir = Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup);
                ProcessOrphanApprovedPair("HKLM", RegApprovedFolderPath, GetFolderFileNameSet(cDir), false, found, ref skipped);
            } catch {}
            return found.Count;
        }

        public static StartupOrphanCleanupResult CleanupOrphanApprovedEntries() {
            var removed = new List<string>();
            int skipped = 0;
            ProcessOrphanApprovedPair("HKCU", RegApprovedRunPath, GetRegValueNameSet("HKCU", RegRunPath), true, removed, ref skipped);
            ProcessOrphanApprovedPair("HKCU", RegApprovedRun32Path, GetRegValueNameSet("HKCU", RegRunWow32Path), true, removed, ref skipped);
            ProcessOrphanApprovedPair("HKLM", RegApprovedRunPath, GetRegValueNameSet("HKLM", RegRunPath), true, removed, ref skipped);
            ProcessOrphanApprovedPair("HKLM", RegApprovedRun32Path, GetRegValueNameSet("HKLM", RegRunWow32Path), true, removed, ref skipped);
            try {
                string uDir = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
                ProcessOrphanApprovedPair("HKCU", RegApprovedFolderPath, GetFolderFileNameSet(uDir), true, removed, ref skipped);
            } catch {}
            try {
                string cDir = Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup);
                ProcessOrphanApprovedPair("HKLM", RegApprovedFolderPath, GetFolderFileNameSet(cDir), true, removed, ref skipped);
            } catch {}
            return new StartupOrphanCleanupResult {
                RemovedCount = removed.Count,
                SkippedAdminCount = skipped,
                RemovedKeys = removed.ToArray()
            };
        }

        private static System.Windows.Media.SolidColorBrush MakeFrozenBrush(byte a, byte r, byte g, byte b) {
            var br = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(a, r, g, b));
            br.Freeze();
            return br;
        }

        private static readonly System.Windows.Media.SolidColorBrush BrTextWhite     = MakeFrozenBrush(255, 0xF8, 0xFA, 0xFC);
        private static readonly System.Windows.Media.SolidColorBrush BrDisabledFg    = MakeFrozenBrush(255, 0x94, 0xA3, 0xB8);
        private static readonly System.Windows.Media.SolidColorBrush BrSubFg         = MakeFrozenBrush(255, 0x64, 0x74, 0x8B);
        private static readonly System.Windows.Media.SolidColorBrush BrNavActive     = MakeFrozenBrush(255, 0x38, 0xBD, 0xF8);
        private static readonly System.Windows.Media.SolidColorBrush BrNavInactive   = MakeFrozenBrush(255, 0xCB, 0xD5, 0xE1);
        private static readonly System.Windows.Media.SolidColorBrush BrPillBg        = MakeFrozenBrush(255, 0x16, 0x22, 0x35);
        private static readonly System.Windows.Media.SolidColorBrush BrPillBdr       = MakeFrozenBrush(255, 0x2B, 0x3D, 0x57);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcFolderBg   = MakeFrozenBrush(255, 0x0F, 0x29, 0x2E);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcFolderBdr  = MakeFrozenBrush(255, 0x1D, 0x4D, 0x57);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcFolderFg   = MakeFrozenBrush(255, 0x5E, 0xEA, 0xD4);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcStoreBg    = MakeFrozenBrush(255, 0x1A, 0x1E, 0x3B);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcStoreBdr   = MakeFrozenBrush(255, 0x37, 0x3E, 0x73);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcStoreFg    = MakeFrozenBrush(255, 0xA5, 0xB4, 0xFC);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcTaskBg     = MakeFrozenBrush(255, 0x2B, 0x21, 0x10);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcTaskBdr    = MakeFrozenBrush(255, 0x5A, 0x44, 0x1F);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcTaskFg     = MakeFrozenBrush(255, 0xFC, 0xD3, 0x4D);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcSvcBg      = MakeFrozenBrush(255, 0x23, 0x19, 0x38);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcSvcBdr     = MakeFrozenBrush(255, 0x49, 0x34, 0x73);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcSvcFg      = MakeFrozenBrush(255, 0xC4, 0xB5, 0xFD);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcGhostBg    = MakeFrozenBrush(255, 0x33, 0x15, 0x1B);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcGhostBdr   = MakeFrozenBrush(255, 0x6E, 0x27, 0x34);
        private static readonly System.Windows.Media.SolidColorBrush BrSrcGhostFg    = MakeFrozenBrush(255, 0xFD, 0xA4, 0xAF);
        private static readonly System.Windows.Media.SolidColorBrush BrSysBg         = MakeFrozenBrush(255, 0x17, 0x25, 0x54);
        private static readonly System.Windows.Media.SolidColorBrush BrSysFg         = MakeFrozenBrush(255, 0x93, 0xC5, 0xFD);
        private static readonly System.Windows.Media.SolidColorBrush BrOemBg         = MakeFrozenBrush(255, 0x1E, 0x1B, 0x4B);
        private static readonly System.Windows.Media.SolidColorBrush BrOemFg         = MakeFrozenBrush(255, 0xA5, 0xB4, 0xFC);
        private static readonly System.Windows.Media.SolidColorBrush BrWarnBg        = MakeFrozenBrush(255, 0x3B, 0x28, 0x06);
        private static readonly System.Windows.Media.SolidColorBrush BrErrBg         = MakeFrozenBrush(255, 0x3B, 0x12, 0x19);
        private static readonly System.Windows.Media.SolidColorBrush BrErrBdr        = MakeFrozenBrush(255, 0x7F, 0x1D, 0x1D);
        private static readonly System.Windows.Media.SolidColorBrush BrRiskSafeFg    = MakeFrozenBrush(255, 0x34, 0xD3, 0x99);
        private static readonly System.Windows.Media.SolidColorBrush BrRiskModFg     = MakeFrozenBrush(255, 0xFB, 0xBF, 0x24);
        private static readonly System.Windows.Media.SolidColorBrush BrRiskCautFg    = MakeFrozenBrush(255, 0xF8, 0x71, 0x71);
        private static readonly System.Windows.Media.SolidColorBrush BrColDivider    = MakeFrozenBrush(0x1C, 0xFF, 0xFF, 0xFF);

        private static readonly Thickness ThkZero     = new Thickness(0);
        private static readonly Thickness ThkOne      = new Thickness(1);
        private static readonly Thickness ThkBadgePad = new Thickness(5, 1, 5, 1);
        private static readonly Thickness ThkBadgeMgn = new Thickness(6, 0, 0, 0);
        private static readonly Thickness ThkAppMgn   = new Thickness(10, 6, 10, 6);
        private static readonly Thickness ThkInfoMgn  = new Thickness(9, 0, 0, 0);
        private static readonly Thickness ThkSubMgn   = new Thickness(0, 1, 0, 0);
        private static readonly Thickness ThkSrcPad   = new Thickness(8, 2, 8, 2);
        private static readonly Thickness ThkBtnPad   = new Thickness(8, 3, 8, 3);
        private static readonly Thickness ThkDelMgn   = new Thickness(5, 0, 0, 0);
        private static readonly CornerRadius Cr3      = new CornerRadius(3);
        private static readonly CornerRadius Cr4      = new CornerRadius(4);

        private static System.Windows.Controls.Border MakeBadgePill(string text, System.Windows.Media.Brush bg, System.Windows.Media.Brush fg) {
            var bd = new System.Windows.Controls.Border();
            bd.Background = bg;
            bd.CornerRadius = Cr3;
            bd.Padding = ThkBadgePad;
            bd.Margin = ThkBadgeMgn;
            bd.VerticalAlignment = VerticalAlignment.Center;
            var tb = new System.Windows.Controls.TextBlock();
            tb.Text = text;
            tb.FontSize = 9.5;
            tb.FontWeight = FontWeights.SemiBold;
            tb.Foreground = fg;
            bd.Child = tb;
            return bd;
        }

        private static string GetSourceLabelFast(string sourceKind) {
            if (string.IsNullOrEmpty(sourceKind)) return "Kh\u00E1c";
            switch (sourceKind) {
                case "RegUser":
                case "RegUser32":
                case "RegSystem":
                case "RegWow32":       return "Registry";
                case "RegRunOnce":     return "RunOnce";
                case "RegPolicy":      return "Policy";
                case "FolderUser":
                case "FolderAll":      return "Th\u01B0 m\u1EE5c";
                case "Store":          return "Store";
                case "Task":           return "Task";
                case "Service":        return "D\u1ECBch v\u1EE5";
                case "OrphanApproved": return "R\u00E1c Reg";
                default:               return "Kh\u00E1c";
            }
        }

        public static void UpdateRowVisual(StartupRowVisual v) {
            if (v == null || v.Entry == null) return;
            StartupEntry e = v.Entry;

            if (v.BadgePanel != null) {
                v.BadgePanel.Children.Clear();
                if (e.ProtectionKind == "System") {
                    v.BadgePanel.Children.Add(MakeBadgePill("H\u1EC7 th\u1ED1ng", BrSysBg, BrSysFg));
                } else if (e.ProtectionKind == "Oem") {
                    v.BadgePanel.Children.Add(MakeBadgePill("H\u00E3ng", BrOemBg, BrOemFg));
                }
                string lk = e.LockKind ?? "";
                if (e.IsPolicyLocked || lk == "Policy") {
                    v.BadgePanel.Children.Add(MakeBadgePill("Kh\u00F3a ch\u00EDnh s\u00E1ch", BrWarnBg, BrRiskModFg));
                } else if (lk == "Msix") {
                    v.BadgePanel.Children.Add(MakeBadgePill("Kh\u00F3a MSIX", BrWarnBg, BrRiskModFg));
                } else if (lk == "Protected") {
                    v.BadgePanel.Children.Add(MakeBadgePill("Kh\u00F3a b\u1EA3o v\u1EC7", BrWarnBg, BrRiskModFg));
                }
                if (e.SourceKind == "RegRunOnce") {
                    v.BadgePanel.Children.Add(MakeBadgePill("Ch\u1EA1y 1 l\u1EA7n", BrWarnBg, BrRiskModFg));
                }
                if (e.IsOrphanApprovedGhost) {
                    v.BadgePanel.Children.Add(MakeBadgePill("R\u00E1c Approved", BrErrBg, BrRiskCautFg));
                } else if (e.IsOrphan) {
                    string errLbl = (e.SourceKind == "Service") ? "D\u1ECBch v\u1EE5 l\u1ED7i" : "T\u1EC7p kh\u00F4ng t\u1ED3n t\u1EA1i";
                    v.BadgePanel.Children.Add(MakeBadgePill(errLbl, BrErrBg, BrRiskCautFg));
                }
            }

            if (v.ImpactText != null) {
                if (e.IsOrphanApprovedGhost) {
                    v.ImpactText.Text = "R\u00E1c";
                    v.ImpactText.Foreground = BrRiskCautFg;
                } else if (e.ImpactLevel == "High") {
                    v.ImpactText.Text = "N\u1EB7ng";
                    v.ImpactText.Foreground = BrRiskCautFg;
                } else if (e.ImpactLevel == "Medium") {
                    v.ImpactText.Text = "Trung b\u00ECnh";
                    v.ImpactText.Foreground = BrRiskModFg;
                } else {
                    v.ImpactText.Text = "Nh\u1EB9";
                    v.ImpactText.Foreground = BrRiskSafeFg;
                }
            }

            if (v.TitleText != null) {
                v.TitleText.Text = e.DisplayName ?? "";
                v.TitleText.Foreground = e.Enabled ? BrTextWhite : BrDisabledFg;
            }

            if (v.SubText != null) {
                if (e.IsOrphanApprovedGhost) {
                    v.SubText.Text = (e.TriggerInfo ?? "") + "  \u2022  " + (e.RawCommand ?? "");
                } else {
                    string pubPart = !string.IsNullOrWhiteSpace(e.Publisher) ? (e.Publisher + "  \u2022  ") : "";
                    string cmdPart = !string.IsNullOrWhiteSpace(e.SecondaryTargetPath)
                        ? e.SecondaryTargetPath
                        : (!string.IsNullOrWhiteSpace(e.ResolvedExePath) ? e.ResolvedExePath : (e.RawCommand ?? ""));
                    v.SubText.Text = pubPart + cmdPart;
                }
            }

            v.SearchText = (
                (e.DisplayName ?? "") + " " +
                (e.Name ?? "") + " " +
                (e.Publisher ?? "") + " " +
                (e.RawCommand ?? "") + " " +
                (e.ResolvedExePath ?? "") + " " +
                (e.SecondaryTargetPath ?? "") + " " +
                (e.SourceKind ?? "") + " " +
                (e.TriggerInfo ?? "") + " " +
                (e.OrphanReason ?? "")
            ).ToLowerInvariant();
        }

        public static StartupRowVisual CreateRowVisual(StartupEntry entry, Style rowStyle, Style toggleStyle, Style actionBtnStyle) {
            var rowBorder = new System.Windows.Controls.Border();
            if (rowStyle != null) rowBorder.Style = rowStyle;
            rowBorder.Padding = ThkZero;
            rowBorder.Margin = ThkZero;
            rowBorder.MinHeight = 46;
            rowBorder.UseLayoutRounding = true;
            if (entry.IsOrphanApprovedGhost) {
                rowBorder.Visibility = Visibility.Collapsed;
            }
            System.Windows.Controls.ToolTipService.SetInitialShowDelay(rowBorder, 450);
            System.Windows.Controls.ToolTipService.SetShowDuration(rowBorder, 12000);
            rowBorder.ToolTip = "";

            var g = new System.Windows.Controls.Grid();
            g.UseLayoutRounding = true;
            g.SnapsToDevicePixels = true;
            g.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(64) });
            g.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(98) });
            g.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(104) });
            g.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(128) });

            var toggle = new System.Windows.Controls.Primitives.ToggleButton();
            if (toggleStyle != null) toggle.Style = toggleStyle;
            toggle.HorizontalAlignment = HorizontalAlignment.Center;
            toggle.VerticalAlignment = VerticalAlignment.Center;
            toggle.IsChecked = entry.Enabled;
            bool canTgl = entry.CanToggle && !entry.IsPolicyLocked;
            toggle.IsEnabled = canTgl;
            if (!canTgl) {
                toggle.Opacity = 0.35;
                System.Windows.Controls.ToolTipService.SetShowOnDisabled(toggle, true);
                string lk = entry.LockKind ?? "";
                if (lk == "Msix") {
                    toggle.ToolTip = "D\u1ECBch v\u1EE5 \u0111\u00F3ng g\u00F3i MSIX (AppXSvc) - Windows kh\u00F3a kh\u00F4ng cho t\u1EAFt tr\u1EF1c ti\u1EBFp. H\u00E3y \u0111i\u1EC1u ch\u1EC9nh \u1EDF m\u1EE5c Store ho\u1EB7c g\u1EE1 \u1EE9ng d\u1EE5ng.";
                } else if (lk == "Protected") {
                    toggle.ToolTip = "D\u1ECBch v\u1EE5 c\u00F3 b\u1EA3o v\u1EC7 ch\u1ED1ng can thi\u1EC7p (Self-Defense / H\u1EC7 th\u1ED1ng) - kh\u00F4ng th\u1EC3 g\u1EA1t t\u1EAFt.";
                } else if (lk == "Policy" || entry.IsPolicyLocked) {
                    toggle.ToolTip = "M\u1EE5c n\u00E0y \u0111ang b\u1ECB kh\u00F3a b\u1EDFi Group Policy.";
                } else {
                    toggle.ToolTip = "Kh\u00F4ng h\u1ED7 tr\u1EE3 b\u1EADt/t\u1EAFt tr\u1EF1c ti\u1EBFp m\u1EE5c n\u00E0y.";
                }
            }
            System.Windows.Controls.Grid.SetColumn(toggle, 0);
            g.Children.Add(toggle);

            var appCellGrid = new System.Windows.Controls.Grid();
            appCellGrid.Margin = ThkAppMgn;
            appCellGrid.VerticalAlignment = VerticalAlignment.Center;
            appCellGrid.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(28) });
            appCellGrid.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var iconBorder = new System.Windows.Controls.Border();
            iconBorder.Width = 28;
            iconBorder.Height = 28;
            iconBorder.CornerRadius = Cr4;
            iconBorder.Background = entry.IsOrphanApprovedGhost ? BrSrcGhostBg : BrPillBg;
            iconBorder.HorizontalAlignment = HorizontalAlignment.Center;
            iconBorder.VerticalAlignment = VerticalAlignment.Center;
            var iconImg = new System.Windows.Controls.Image();
            iconImg.Width = 20;
            iconImg.Height = 20;
            iconImg.Stretch = System.Windows.Media.Stretch.Uniform;
            System.Windows.Media.RenderOptions.SetBitmapScalingMode(iconImg, System.Windows.Media.BitmapScalingMode.HighQuality);
            iconBorder.Child = iconImg;
            System.Windows.Controls.Grid.SetColumn(iconBorder, 0);
            appCellGrid.Children.Add(iconBorder);

            var infoStack = new System.Windows.Controls.StackPanel();
            infoStack.VerticalAlignment = VerticalAlignment.Center;
            infoStack.Margin = ThkInfoMgn;

            var line1 = new System.Windows.Controls.StackPanel();
            line1.Orientation = System.Windows.Controls.Orientation.Horizontal;
            var titleTb = new System.Windows.Controls.TextBlock();
            titleTb.FontSize = 12;
            titleTb.FontWeight = FontWeights.SemiBold;
            titleTb.TextTrimming = TextTrimming.CharacterEllipsis;
            titleTb.VerticalAlignment = VerticalAlignment.Center;
            line1.Children.Add(titleTb);

            var badgePanel = new System.Windows.Controls.StackPanel();
            badgePanel.Orientation = System.Windows.Controls.Orientation.Horizontal;
            badgePanel.VerticalAlignment = VerticalAlignment.Center;
            line1.Children.Add(badgePanel);
            infoStack.Children.Add(line1);

            var subTb = new System.Windows.Controls.TextBlock();
            subTb.FontSize = 10.5;
            subTb.Foreground = BrSubFg;
            subTb.TextTrimming = TextTrimming.CharacterEllipsis;
            subTb.Margin = ThkSubMgn;
            infoStack.Children.Add(subTb);

            System.Windows.Controls.Grid.SetColumn(infoStack, 1);
            appCellGrid.Children.Add(infoStack);

            System.Windows.Controls.Grid.SetColumn(appCellGrid, 1);
            g.Children.Add(appCellGrid);

            System.Windows.Media.Brush srcBg = BrPillBg;
            System.Windows.Media.Brush srcBdr = BrPillBdr;
            System.Windows.Media.Brush srcFg = BrNavInactive;
            string sk = entry.SourceKind ?? "";
            if (sk == "FolderUser" || sk == "FolderAll") {
                srcBg = BrSrcFolderBg; srcBdr = BrSrcFolderBdr; srcFg = BrSrcFolderFg;
            } else if (sk == "Store") {
                srcBg = BrSrcStoreBg; srcBdr = BrSrcStoreBdr; srcFg = BrSrcStoreFg;
            } else if (sk == "Task") {
                srcBg = BrSrcTaskBg; srcBdr = BrSrcTaskBdr; srcFg = BrSrcTaskFg;
            } else if (sk == "Service") {
                srcBg = BrSrcSvcBg; srcBdr = BrSrcSvcBdr; srcFg = BrSrcSvcFg;
            } else if (sk == "OrphanApproved") {
                srcBg = BrSrcGhostBg; srcBdr = BrSrcGhostBdr; srcFg = BrSrcGhostFg;
            }

            var srcPill = new System.Windows.Controls.Border();
            srcPill.Background = srcBg;
            srcPill.BorderBrush = srcBdr;
            srcPill.BorderThickness = ThkOne;
            srcPill.CornerRadius = Cr3;
            srcPill.Padding = ThkSrcPad;
            srcPill.HorizontalAlignment = HorizontalAlignment.Center;
            srcPill.VerticalAlignment = VerticalAlignment.Center;
            var srcTb = new System.Windows.Controls.TextBlock();
            srcTb.Text = GetSourceLabelFast(sk);
            srcTb.FontSize = 10.5;
            srcTb.FontWeight = FontWeights.SemiBold;
            srcTb.Foreground = srcFg;
            srcPill.Child = srcTb;
            System.Windows.Controls.Grid.SetColumn(srcPill, 2);
            g.Children.Add(srcPill);

            var impTb = new System.Windows.Controls.TextBlock();
            impTb.FontSize = 11;
            impTb.FontWeight = FontWeights.SemiBold;
            impTb.HorizontalAlignment = HorizontalAlignment.Center;
            impTb.VerticalAlignment = VerticalAlignment.Center;
            System.Windows.Controls.Grid.SetColumn(impTb, 3);
            g.Children.Add(impTb);

            var actPanel = new System.Windows.Controls.StackPanel();
            actPanel.Orientation = System.Windows.Controls.Orientation.Horizontal;
            actPanel.HorizontalAlignment = HorizontalAlignment.Center;
            actPanel.VerticalAlignment = VerticalAlignment.Center;

            var btnOpen = new System.Windows.Controls.Button();
            if (actionBtnStyle != null) btnOpen.Style = actionBtnStyle;
            btnOpen.Content = entry.IsOrphanApprovedGhost ? "Registry" : "M\u1EDF t\u1EC7p";
            btnOpen.FontSize = 10.5;
            btnOpen.FontWeight = FontWeights.SemiBold;
            btnOpen.Padding = ThkBtnPad;
            btnOpen.Background = BrPillBg;
            btnOpen.Foreground = BrNavActive;
            btnOpen.BorderBrush = BrPillBdr;
            btnOpen.BorderThickness = ThkOne;
            actPanel.Children.Add(btnOpen);

            System.Windows.Controls.Button btnDel = null;
            if (entry.CanDelete) {
                btnDel = new System.Windows.Controls.Button();
                if (actionBtnStyle != null) btnDel.Style = actionBtnStyle;
                btnDel.Content = "X\u00F3a";
                btnDel.FontSize = 10.5;
                btnDel.FontWeight = FontWeights.SemiBold;
                btnDel.Padding = ThkBtnPad;
                btnDel.Margin = ThkDelMgn;
                btnDel.Background = BrErrBg;
                btnDel.Foreground = BrRiskCautFg;
                btnDel.BorderBrush = BrErrBdr;
                btnDel.BorderThickness = ThkOne;
                actPanel.Children.Add(btnDel);
            }

            System.Windows.Controls.Grid.SetColumn(actPanel, 4);
            g.Children.Add(actPanel);

            for (int divCol = 0; divCol < 4; divCol++) {
                var colDiv = new System.Windows.Controls.Border();
                colDiv.Width = 1;
                colDiv.Background = BrColDivider;
                colDiv.HorizontalAlignment = HorizontalAlignment.Right;
                colDiv.VerticalAlignment = VerticalAlignment.Stretch;
                colDiv.SnapsToDevicePixels = true;
                colDiv.IsHitTestVisible = false;
                System.Windows.Controls.Grid.SetColumn(colDiv, divCol);
                g.Children.Add(colDiv);
            }

            rowBorder.Child = g;

            var vis = new StartupRowVisual {
                Entry = entry,
                Row = rowBorder,
                Toggle = toggle,
                IconImage = iconImg,
                TitleText = titleTb,
                BadgePanel = badgePanel,
                SubText = subTb,
                ImpactText = impTb,
                OpenButton = btnOpen,
                DeleteButton = btnDel,
                SearchText = ""
            };
            rowBorder.Tag = vis;
            toggle.Tag = vis;
            btnOpen.Tag = vis;
            if (btnDel != null) btnDel.Tag = vis;

            UpdateRowVisual(vis);
            return vis;
        }

        private static int GetImpactRank(string level) {
            if (level == "High") return 0;
            if (level == "Medium") return 1;
            return 2;
        }

        public static int CompareStartupEntries(StartupEntry a, StartupEntry b) {
            if (ReferenceEquals(a, b)) return 0;
            if (a == null) return 1;
            if (b == null) return -1;
            int gA = a.IsOrphanApprovedGhost ? 2 : (a.IsOrphan ? 1 : 0);
            int gB = b.IsOrphanApprovedGhost ? 2 : (b.IsOrphan ? 1 : 0);
            if (gA != gB) return gA.CompareTo(gB);
            int eA = a.Enabled ? 0 : 1;
            int eB = b.Enabled ? 0 : 1;
            if (eA != eB) return eA.CompareTo(eB);
            int tA = a.CanToggle ? 0 : 1;
            int tB = b.CanToggle ? 0 : 1;
            if (tA != tB) return tA.CompareTo(tB);
            int iA = GetImpactRank(a.ImpactLevel);
            int iB = GetImpactRank(b.ImpactLevel);
            if (iA != iB) return iA.CompareTo(iB);
            return string.Compare(a.DisplayName ?? "", b.DisplayName ?? "", StringComparison.OrdinalIgnoreCase);
        }

        public static StartupRowVisual[] SortRowVisuals(StartupRowVisual[] rows) {
            if (rows == null || rows.Length <= 1) return rows ?? new StartupRowVisual[0];
            var copy = new StartupRowVisual[rows.Length];
            Array.Copy(rows, copy, rows.Length);
            Array.Sort(copy, delegate(StartupRowVisual x, StartupRowVisual y) {
                return CompareStartupEntries(x != null ? x.Entry : null, y != null ? y.Entry : null);
            });
            return copy;
        }
    }
}
