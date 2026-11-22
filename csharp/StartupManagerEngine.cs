using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
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
        public string LogoPath { get; set; }
        public bool Enabled { get; set; }
        public bool IsPolicyLocked { get; set; }
        public bool IsOrphan { get; set; }
        public string ProtectionKind { get; set; }
        public string ImpactLevel { get; set; }
        public bool RequiresAdmin { get; set; }
        public bool CanDelete { get; set; }
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

    public static class StartupManagerEngine {
        private const string RegRunPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string RegRunWow32Path = @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";
        private const string RegApprovedRunPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
        private const string RegApprovedRun32Path = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32";
        private const string RegApprovedFolderPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder";
        private const string RegSystemAppDataPath = @"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData";
        private const string RegRepoPackagesPath = @"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages";

        private static readonly ConcurrentDictionary<string, BitmapSource> _iconCache =
            new ConcurrentDictionary<string, BitmapSource>(StringComparer.OrdinalIgnoreCase);

        private static readonly string[] ValidStartupExtensions = new string[] {
            ".lnk", ".exe", ".bat", ".cmd", ".vbs", ".ps1"
        };

        private static readonly string[] CommandExecExtensions = new string[] {
            ".exe", ".com", ".bat", ".cmd", ".vbs", ".msc", ".ps1", ".scr"
        };

        private static readonly Regex RxStartupTask = new Regex(
            @"<(?:\w+:)?StartupTask\b[^>]*\bTaskId\s*=\s*[""']([^""']+)[""']",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

        private static readonly Regex RxDisplayName = new Regex(
            @"<DisplayName>\s*([^<]+?)\s*</DisplayName>",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

        private static readonly Regex RxPublisherName = new Regex(
            @"<PublisherDisplayName>\s*([^<]+?)\s*</PublisherDisplayName>",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

        private static readonly Regex RxLogo = new Regex(
            @"(?:Square44x44Logo|Square150x150Logo)\s*=\s*[""']([^""']+)[""']|<Logo>\s*([^<]+?)\s*</Logo>",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

        private static readonly string[] HighImpactPatterns = new string[] {
            "docker", "discord", "slack", "teams", "ms-teams", "spotify", "figma", "notion",
            "vscode", "code.exe", "steam", "epicgames", "riot", "vanguard", "battle.net",
            "ea desktop", "eadesktop", "ubisoft", "wargaming", "curseforge", "overwolf",
            "onedrive", "googledrive", "dropbox", "creative cloud", "ccxprocess", "adobe",
            "wallpaper32", "wallpaper64", "wallpaperengine", "blitz", "porofessor", "medal",
            "obs64", "streamlabs", "icue", "lghub"
        };

        private static readonly string[] MediumImpactPatterns = new string[] {
            "msedge", "chrome", "brave", "firefox", "opera", "zalo", "telegram", "viber",
            "messenger", "whatsapp", "cloudflare", "warp", "proton", "radmin", "tailscale",
            "zerotier", "nordvpn", "surfshark", "vantage", "legion", "armoury", "myasus",
            "msicenter", "dragoncenter", "nitrosense", "predatorsense", "awcc", "alienware",
            "omen", "synapse", "razer", "nvidia", "amd", "radeon", "yourphone", "crossdevice",
            "pcmanager", "windowsmaster", "codex", "freedownloadmanager", "fdm", "idm",
            "qbittorrent", "utorrent", "java", "jusched"
        };

        private static readonly string[] SystemProtectionPatterns = new string[] {
            "securityhealth", "windows defender", "windowsdefender", "ctfmon", "sechealth"
        };

        private static readonly string[] OemProtectionPatterns = new string[] {
            "rtkaud", "realtek", "dolby", "nahimic", "waves", "dtsx", "dtsaudio",
            "lenovo", "vantage", "legion", "thinkpad", "asus", "armoury", "myasus", "atkex",
            "msicenter", "dragoncenter", "nitrosense", "predatorsense", "acer",
            "alienware", "awcc", "dellpower", "hpomen", "hpsystemevent", "gigabyte", "aorus",
            "nvdisplay", "nvcontainer", "amdnoise", "amdrsserv", "radeon", "igfx", "intel",
            "syntpenh", "synaptics", "etdctrl", "elan", "fxsound"
        };

        [DllImport("shell32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern IntPtr CommandLineToArgvW(string lpCmdLine, out int pNumArgs);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LocalFree(IntPtr hMem);

        [DllImport("shlwapi.dll", BestFitMapping = false, CharSet = CharSet.Unicode, ExactSpelling = true, ThrowOnUnmappableChar = true)]
        private static extern int SHLoadIndirectString(string pszSource, StringBuilder pszOutBuf, int cchOutBuf, IntPtr ppvReserved);

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

        private static bool HasCommandExecExtension(string path) {
            if (string.IsNullOrWhiteSpace(path)) return false;
            string ext = "";
            try { ext = Path.GetExtension(path); } catch { return false; }
            for (int i = 0; i < CommandExecExtensions.Length; i++) {
                if (string.Equals(ext, CommandExecExtensions[i], StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
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
                        if (File.Exists(full)) return full;
                    } catch {}
                }
            }

            try {
                using (RegistryKey baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)) {
                    for (int cIdx = 0; cIdx < candidates.Length; cIdx++) {
                        using (RegistryKey ap = baseKey.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\" + candidates[cIdx], false)) {
                            if (ap != null) {
                                string p = Convert.ToString(ap.GetValue(""), CultureInfo.InvariantCulture) ?? "";
                                p = Environment.ExpandEnvironmentVariables(p).Trim().Trim('"');
                                if (!string.IsNullOrEmpty(p) && File.Exists(p)) return p;
                            }
                        }
                    }
                }
            } catch {}

            return "";
        }

        public static string ResolveExecutablePath(string rawCommand, out bool isExplicitMissingFile) {
            isExplicitMissingFile = false;
            if (string.IsNullOrWhiteSpace(rawCommand)) return "";

            string expanded = Environment.ExpandEnvironmentVariables(rawCommand).Trim();
            if (string.IsNullOrEmpty(expanded)) return "";

            if (expanded.StartsWith("\"", StringComparison.Ordinal)) {
                int endQ = expanded.IndexOf('"', 1);
                if (endQ > 1) {
                    string quoted = expanded.Substring(1, endQ - 1).Trim();
                    if (File.Exists(quoted)) return quoted;
                    if (!quoted.Contains("\\") && !quoted.Contains("/")) {
                        string found = TryFindInSystemPaths(quoted);
                        if (!string.IsNullOrEmpty(found)) return found;
                    }
                    if (Path.IsPathRooted(quoted)) {
                        isExplicitMissingFile = true;
                        return quoted;
                    }
                }
            }

            if (File.Exists(expanded)) return expanded;

            int argc;
            IntPtr argvPtr = CommandLineToArgvW(expanded, out argc);
            string firstArg = "";
            string[] argv = new string[0];
            if (argvPtr != IntPtr.Zero) {
                try {
                    if (argc > 0) {
                        argv = new string[argc];
                        for (int i = 0; i < argc; i++) {
                            IntPtr pStr = Marshal.ReadIntPtr(argvPtr, i * IntPtr.Size);
                            argv[i] = Marshal.PtrToStringUni(pStr) ?? "";
                        }
                        firstArg = argv[0].Trim();
                    }
                } finally {
                    LocalFree(argvPtr);
                }
            }

            if (!string.IsNullOrEmpty(firstArg)) {
                if (File.Exists(firstArg)) return firstArg;
                if (!firstArg.Contains("\\") && !firstArg.Contains("/")) {
                    string foundInPath = TryFindInSystemPaths(firstArg);
                    if (!string.IsNullOrEmpty(foundInPath)) return foundInPath;
                }
            }

            if (argv.Length > 1 && Path.IsPathRooted(firstArg)) {
                var sb = new StringBuilder(firstArg);
                string bestRootedExec = HasCommandExecExtension(firstArg) ? firstArg : "";
                for (int i = 1; i < argv.Length; i++) {
                    sb.Append(' ').Append(argv[i]);
                    string candidate = sb.ToString();
                    if (File.Exists(candidate)) return candidate;
                    if (string.IsNullOrEmpty(bestRootedExec) && HasCommandExecExtension(candidate)) {
                        bestRootedExec = candidate;
                    }
                }
                if (!string.IsNullOrEmpty(bestRootedExec)) {
                    isExplicitMissingFile = !File.Exists(bestRootedExec);
                    return bestRootedExec;
                }
            }

            if (!string.IsNullOrEmpty(firstArg) && Path.IsPathRooted(firstArg)) {
                if (!HasCommandExecExtension(firstArg) && File.Exists(firstArg + ".exe")) {
                    return firstArg + ".exe";
                }
                isExplicitMissingFile = true;
                return firstArg;
            }

            return firstArg;
        }

        private static void ResolveShortcutLnk(string lnkPath, out string targetPath, out string arguments, out bool isNonFileTarget) {
            targetPath = "";
            arguments = "";
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

                if (string.IsNullOrEmpty(p)) {
                    isNonFileTarget = true;
                } else {
                    targetPath = Environment.ExpandEnvironmentVariables(p);
                }
            } catch {
                isNonFileTarget = true;
            } finally {
                if (link != null) {
                    try { Marshal.ReleaseComObject(link); } catch {}
                }
            }
        }

        public static string IsProtectedOemOrSystemStartup(string name, string command, string publisher) {
            string hay = ((name ?? "") + " " + (command ?? "") + " " + (publisher ?? "")).ToLowerInvariant();
            for (int i = 0; i < SystemProtectionPatterns.Length; i++) {
                if (hay.Contains(SystemProtectionPatterns[i])) return "System";
            }
            for (int i = 0; i < OemProtectionPatterns.Length; i++) {
                if (hay.Contains(OemProtectionPatterns[i])) return "Oem";
            }
            return "";
        }

        public static string EstimateImpact(string name, string command, string publisher) {
            string hay = ((name ?? "") + " " + (command ?? "") + " " + (publisher ?? "")).ToLowerInvariant();
            for (int i = 0; i < HighImpactPatterns.Length; i++) {
                if (hay.Contains(HighImpactPatterns[i])) return "High";
            }
            for (int i = 0; i < MediumImpactPatterns.Length; i++) {
                if (hay.Contains(MediumImpactPatterns[i])) return "Medium";
            }
            return "Low";
        }

        private static string MakeFriendlyName(string rawName, string exePath) {
            string n = (rawName ?? "").Trim();
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

        private static void ScanRegistryRunKey(
            List<StartupEntry> list,
            string hive,
            string runPath,
            string approvedPath,
            string sourceKind,
            bool requiresAdmin) {
            Dictionary<string, byte[]> approvedMap = ReadApprovedMap(hive, approvedPath);
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
                        string exePath = ResolveExecutablePath(rawCmd, out isMissing);
                        byte[] apBytes;
                        bool enabled = !approvedMap.TryGetValue(vn, out apBytes) || IsEnabledFromApprovedBytes(apBytes);

                        var entry = new StartupEntry();
                        entry.Id = sourceKind + "|" + vn;
                        entry.Name = vn;
                        entry.DisplayName = MakeFriendlyName(vn, exePath);
                        entry.Publisher = "";
                        entry.RawCommand = rawCmd;
                        entry.ResolvedExePath = exePath;
                        entry.SourceKind = sourceKind;
                        entry.RegistryHive = hive;
                        entry.RegistryPath = runPath;
                        entry.RegistryValueName = vn;
                        entry.ApprovedHive = hive;
                        entry.ApprovedPath = approvedPath;
                        entry.ApprovedValueName = vn;
                        entry.Enabled = enabled;
                        entry.IsPolicyLocked = false;
                        entry.IsOrphan = isMissing;
                        entry.ProtectionKind = IsProtectedOemOrSystemStartup(entry.DisplayName, rawCmd, "");
                        entry.ImpactLevel = EstimateImpact(entry.DisplayName, rawCmd, "");
                        entry.RequiresAdmin = requiresAdmin;
                        entry.CanDelete = true;
                        entry.MetadataHydrated = false;
                        list.Add(entry);
                    }
                }
            } catch {}
        }

        private static void ScanStartupFolder(
            List<StartupEntry> list,
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
                    bool validExt = false;
                    for (int eIdx = 0; eIdx < ValidStartupExtensions.Length; eIdx++) {
                        if (string.Equals(ext, ValidStartupExtensions[eIdx], StringComparison.OrdinalIgnoreCase)) {
                            validExt = true;
                            break;
                        }
                    }
                    if (!validExt) continue;

                    string exePath = fp;
                    string rawCmd = fp;
                    bool isOrphan = false;

                    if (string.Equals(ext, ".lnk", StringComparison.OrdinalIgnoreCase)) {
                        string lnkTarget;
                        string lnkArgs;
                        bool isNonFile;
                        ResolveShortcutLnk(fp, out lnkTarget, out lnkArgs, out isNonFile);
                        if (isNonFile) {
                            exePath = fp;
                            rawCmd = fp;
                            isOrphan = false;
                        } else {
                            exePath = lnkTarget;
                            rawCmd = string.IsNullOrEmpty(lnkArgs) ? lnkTarget : ("\"" + lnkTarget + "\" " + lnkArgs);
                            isOrphan = !string.IsNullOrEmpty(lnkTarget) && Path.IsPathRooted(lnkTarget) && !File.Exists(lnkTarget);
                        }
                    }

                    byte[] apBytes;
                    bool enabled = !approvedMap.TryGetValue(fileName, out apBytes) || IsEnabledFromApprovedBytes(apBytes);
                    string disp = Path.GetFileNameWithoutExtension(fileName);

                    var entry = new StartupEntry();
                    entry.Id = sourceKind + "|" + fileName;
                    entry.Name = fileName;
                    entry.DisplayName = disp;
                    entry.Publisher = "";
                    entry.RawCommand = rawCmd;
                    entry.ResolvedExePath = exePath;
                    entry.SourceKind = sourceKind;
                    entry.ApprovedHive = approvedHive;
                    entry.ApprovedPath = RegApprovedFolderPath;
                    entry.ApprovedValueName = fileName;
                    entry.FolderFilePath = fp;
                    entry.Enabled = enabled;
                    entry.IsPolicyLocked = false;
                    entry.IsOrphan = isOrphan;
                    entry.ProtectionKind = IsProtectedOemOrSystemStartup(disp, rawCmd, "");
                    entry.ImpactLevel = EstimateImpact(disp, rawCmd, "");
                    entry.RequiresAdmin = requiresAdmin;
                    entry.CanDelete = true;
                    entry.MetadataHydrated = false;
                    list.Add(entry);
                }
            } catch {}
        }

        public static StartupEntry[] ScanFastCore() {
            var list = new List<StartupEntry>(32);
            ScanRegistryRunKey(list, "HKCU", RegRunPath, RegApprovedRunPath, "RegUser", false);
            ScanRegistryRunKey(list, "HKLM", RegRunPath, RegApprovedRunPath, "RegSystem", true);
            ScanRegistryRunKey(list, "HKLM", RegRunWow32Path, RegApprovedRun32Path, "RegWow32", true);

            try {
                string userFolder = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
                ScanStartupFolder(list, userFolder, "HKCU", "FolderUser", false);
            } catch {}
            try {
                string commonFolder = Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup);
                ScanStartupFolder(list, commonFolder, "HKLM", "FolderAll", true);
            } catch {}

            return list.ToArray();
        }

        public static Task<StartupEntry[]> ScanFastCoreAsync() {
            return Task.Run(delegate() { return ScanFastCore(); });
        }

        private sealed class PackageRepoInfo {
            public string PackageFullName;
            public string PackageRootFolder;
        }

        private static string ExtractPackageFamilyFromFullName(string fullName) {
            if (string.IsNullOrEmpty(fullName)) return "";
            int firstUs = fullName.IndexOf('_');
            int lastDoubleUs = fullName.LastIndexOf("__", StringComparison.Ordinal);
            if (firstUs <= 0 || lastDoubleUs <= firstUs || lastDoubleUs + 2 >= fullName.Length) return "";
            return fullName.Substring(0, firstUs) + "_" + fullName.Substring(lastDoubleUs + 2);
        }

        private static Dictionary<string, PackageRepoInfo> BuildUwpFamilyMap() {
            var map = new Dictionary<string, PackageRepoInfo>(StringComparer.OrdinalIgnoreCase);
            try {
                using (RegistryKey hkcu = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64))
                using (RegistryKey pkgs = hkcu.OpenSubKey(RegRepoPackagesPath, false)) {
                    if (pkgs == null) return map;
                    string[] subNames = pkgs.GetSubKeyNames();
                    for (int i = 0; i < subNames.Length; i++) {
                        string fullName = subNames[i];
                        string family = ExtractPackageFamilyFromFullName(fullName);
                        if (string.IsNullOrEmpty(family)) continue;
                        try {
                            using (RegistryKey pk = pkgs.OpenSubKey(fullName, false)) {
                                if (pk == null) continue;
                                string root = Convert.ToString(pk.GetValue("PackageRootFolder"), CultureInfo.InvariantCulture) ?? "";
                                if (string.IsNullOrEmpty(root)) continue;
                                string manifestPath = Path.Combine(root, "AppxManifest.xml");
                                if (!File.Exists(manifestPath)) continue;
                                PackageRepoInfo existing;
                                if (!map.TryGetValue(family, out existing) ||
                                    string.CompareOrdinal(fullName, existing.PackageFullName) > 0) {
                                    map[family] = new PackageRepoInfo {
                                        PackageFullName = fullName,
                                        PackageRootFolder = root
                                    };
                                }
                            }
                        } catch {}
                    }
                }
            } catch {}
            return map;
        }

        private static string ResolveIndirectResource(string packageFullName, string rawValue, string fallbackName) {
            if (string.IsNullOrWhiteSpace(rawValue)) return fallbackName;
            string v = rawValue.Trim();
            if (!v.StartsWith("ms-resource:", StringComparison.OrdinalIgnoreCase)) {
                return v;
            }
            try {
                string normalized = v;
                if (!normalized.StartsWith("ms-resource://", StringComparison.OrdinalIgnoreCase)) {
                    string tail = normalized.Substring("ms-resource:".Length).TrimStart('/');
                    if (tail.StartsWith("Resources/", StringComparison.OrdinalIgnoreCase)) {
                        normalized = "ms-resource:///" + tail;
                    } else {
                        normalized = "ms-resource:///Resources/" + tail;
                    }
                }
                string query = "@{" + packageFullName + "?" + normalized + "}";
                var sb = new StringBuilder(512);
                int hr = SHLoadIndirectString(query, sb, sb.Capacity, IntPtr.Zero);
                if (hr == 0 && sb.Length > 0) {
                    string resolved = sb.ToString().Trim();
                    if (!string.IsNullOrEmpty(resolved)) return resolved;
                }
                if (v.StartsWith("ms-resource:", StringComparison.OrdinalIgnoreCase) &&
                    !v.StartsWith("ms-resource://", StringComparison.OrdinalIgnoreCase)) {
                    string query2 = "@{" + packageFullName + "?" + v + "}";
                    var sb2 = new StringBuilder(512);
                    if (SHLoadIndirectString(query2, sb2, sb2.Capacity, IntPtr.Zero) == 0 && sb2.Length > 0) {
                        string resolved2 = sb2.ToString().Trim();
                        if (!string.IsNullOrEmpty(resolved2)) return resolved2;
                    }
                }
            } catch {}
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

        private static void ScanUwpStartupTasks(List<StartupEntry> list) {
            Dictionary<string, PackageRepoInfo> familyMap = BuildUwpFamilyMap();
            if (familyMap.Count == 0) return;

            try {
                using (RegistryKey hkcu = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64))
                using (RegistryKey appDataRoot = hkcu.OpenSubKey(RegSystemAppDataPath, false)) {
                    if (appDataRoot == null) return;
                    string[] families = appDataRoot.GetSubKeyNames();
                    for (int fIdx = 0; fIdx < families.Length; fIdx++) {
                        string family = families[fIdx];
                        PackageRepoInfo repo;
                        if (!familyMap.TryGetValue(family, out repo)) continue;

                        string manifestPath = Path.Combine(repo.PackageRootFolder, "AppxManifest.xml");
                        string manifestXml = "";
                        try { manifestXml = File.ReadAllText(manifestPath, Encoding.UTF8); } catch { continue; }
                        if (string.IsNullOrEmpty(manifestXml)) continue;

                        var validTaskIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                        MatchCollection taskMatches = RxStartupTask.Matches(manifestXml);
                        for (int t = 0; t < taskMatches.Count; t++) {
                            string tid = taskMatches[t].Groups[1].Value.Trim();
                            if (!string.IsNullOrEmpty(tid)) validTaskIds.Add(tid);
                        }
                        if (validTaskIds.Count == 0) continue;

                        string fallbackName = FriendlyFamilyFallback(family);
                        Match mDisp = RxDisplayName.Match(manifestXml);
                        string dispRaw = mDisp.Success ? mDisp.Groups[1].Value.Trim() : "";
                        string dispName = ResolveIndirectResource(repo.PackageFullName, dispRaw, fallbackName);

                        Match mPub = RxPublisherName.Match(manifestXml);
                        string pubRaw = mPub.Success ? mPub.Groups[1].Value.Trim() : "";
                        string publisher = ResolveIndirectResource(repo.PackageFullName, pubRaw, "");

                        Match mLogo = RxLogo.Match(manifestXml);
                        string logoRel = "";
                        if (mLogo.Success) {
                            logoRel = !string.IsNullOrEmpty(mLogo.Groups[1].Value) ? mLogo.Groups[1].Value : mLogo.Groups[2].Value;
                        }
                        string logoPath = ResolveUwpLogoPath(repo.PackageRootFolder, logoRel);

                        try {
                            using (RegistryKey famKey = appDataRoot.OpenSubKey(family, false)) {
                                if (famKey == null) continue;
                                string[] subNames = famKey.GetSubKeyNames();
                                for (int sIdx = 0; sIdx < subNames.Length; sIdx++) {
                                    string taskId = subNames[sIdx];
                                    if (!validTaskIds.Contains(taskId)) continue;
                                    try {
                                        using (RegistryKey tk = famKey.OpenSubKey(taskId, false)) {
                                            if (tk == null) continue;
                                            object stObj = tk.GetValue("State");
                                            if (stObj == null) continue;
                                            int state = Convert.ToInt32(stObj, CultureInfo.InvariantCulture);
                                            bool enabled = (state == 2 || state == 4);
                                            bool policyLocked = (state == 3 || state == 4);

                                            var entry = new StartupEntry();
                                            entry.Id = "Store|" + family + "|" + taskId;
                                            entry.Name = taskId;
                                            entry.DisplayName = dispName;
                                            entry.Publisher = publisher;
                                            entry.RawCommand = family + " (" + taskId + ")";
                                            entry.ResolvedExePath = repo.PackageRootFolder;
                                            entry.SourceKind = "Store";
                                            entry.PackageFamilyName = family;
                                            entry.PackageFullName = repo.PackageFullName;
                                            entry.TaskId = taskId;
                                            entry.UwpState = state;
                                            entry.LogoPath = logoPath;
                                            entry.Enabled = enabled;
                                            entry.IsPolicyLocked = policyLocked;
                                            entry.IsOrphan = false;
                                            entry.ProtectionKind = IsProtectedOemOrSystemStartup(dispName, family + " " + taskId, publisher);
                                            entry.ImpactLevel = EstimateImpact(dispName, family + " " + taskId, publisher);
                                            entry.RequiresAdmin = false;
                                            entry.CanDelete = false;
                                            entry.MetadataHydrated = true;
                                            list.Add(entry);
                                        }
                                    } catch {}
                                }
                            }
                        } catch {}
                    }
                }
            } catch {}
        }

        private static object ComGet(object target, string propName) {
            return target.GetType().InvokeMember(propName, BindingFlags.GetProperty, null, target, null);
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

        private static void TraverseScheduledTaskFolder(object folder, List<StartupEntry> list) {
            string folderPath = "";
            try { folderPath = Convert.ToString(ComGet(folder, "Path"), CultureInfo.InvariantCulture) ?? ""; } catch { return; }

            if (folderPath.Equals(@"\Microsoft\Windows", StringComparison.OrdinalIgnoreCase) ||
                folderPath.StartsWith(@"\Microsoft\Windows\", StringComparison.OrdinalIgnoreCase) ||
                folderPath.Equals(@"\Microsoft\Office", StringComparison.OrdinalIgnoreCase) ||
                folderPath.StartsWith(@"\Microsoft\Office\", StringComparison.OrdinalIgnoreCase)) {
                return;
            }

            try {
                object tasksCol = ComCall(folder, "GetTasks", 1);
                int count = Convert.ToInt32(ComGet(tasksCol, "Count"), CultureInfo.InvariantCulture);
                for (int i = 1; i <= count; i++) {
                    object task = null;
                    try {
                        task = ComGet(tasksCol, "Item");
                    } catch {
                        try { task = tasksCol.GetType().InvokeMember("Item", BindingFlags.GetProperty, null, tasksCol, new object[] { i }); } catch { task = null; }
                    }
                    if (task == null) {
                        try { task = ComCall(tasksCol, "Item", i); } catch { continue; }
                    }
                    try {
                        string taskName = Convert.ToString(ComGet(task, "Name"), CultureInfo.InvariantCulture) ?? "";
                        string taskFullPath = Convert.ToString(ComGet(task, "Path"), CultureInfo.InvariantCulture) ?? "";
                        if (string.IsNullOrEmpty(taskFullPath)) continue;
                        if (taskFullPath.StartsWith(@"\Microsoft\Windows\", StringComparison.OrdinalIgnoreCase)) continue;

                        bool enabled = Convert.ToBoolean(ComGet(task, "Enabled"), CultureInfo.InvariantCulture);
                        object def = ComGet(task, "Definition");
                        if (def == null) continue;

                        bool hasStartupTrigger = false;
                        object triggers = ComGet(def, "Triggers");
                        if (triggers != null) {
                            int tCount = Convert.ToInt32(ComGet(triggers, "Count"), CultureInfo.InvariantCulture);
                            for (int ti = 1; ti <= tCount; ti++) {
                                try {
                                    object trig = triggers.GetType().InvokeMember("Item", BindingFlags.GetProperty, null, triggers, new object[] { ti });
                                    int trigType = Convert.ToInt32(ComGet(trig, "Type"), CultureInfo.InvariantCulture);
                                    if (trigType == 9 || trigType == 8) {
                                        hasStartupTrigger = true;
                                        break;
                                    }
                                } catch {}
                            }
                        }
                        if (!hasStartupTrigger) continue;

                        string execPath = "";
                        string execArgs = "";
                        object actions = ComGet(def, "Actions");
                        if (actions != null) {
                            int aCount = Convert.ToInt32(ComGet(actions, "Count"), CultureInfo.InvariantCulture);
                            for (int ai = 1; ai <= aCount; ai++) {
                                try {
                                    object act = actions.GetType().InvokeMember("Item", BindingFlags.GetProperty, null, actions, new object[] { ai });
                                    int actType = Convert.ToInt32(ComGet(act, "Type"), CultureInfo.InvariantCulture);
                                    if (actType == 0) {
                                        execPath = Convert.ToString(ComGet(act, "Path"), CultureInfo.InvariantCulture) ?? "";
                                        execArgs = Convert.ToString(ComGet(act, "Arguments"), CultureInfo.InvariantCulture) ?? "";
                                        break;
                                    }
                                } catch {}
                            }
                        }
                        if (string.IsNullOrWhiteSpace(execPath)) continue;

                        string rawCmd = string.IsNullOrWhiteSpace(execArgs) ? execPath : (execPath + " " + execArgs);
                        bool isMissing;
                        string resolvedExe = ResolveExecutablePath(execPath, out isMissing);
                        string author = "";
                        try {
                            object regInfo = ComGet(def, "RegistrationInfo");
                            if (regInfo != null) author = Convert.ToString(ComGet(regInfo, "Author"), CultureInfo.InvariantCulture) ?? "";
                        } catch {}

                        var entry = new StartupEntry();
                        entry.Id = "Task|" + taskFullPath;
                        entry.Name = taskName;
                        entry.DisplayName = MakeFriendlyName(taskName, resolvedExe);
                        entry.Publisher = author;
                        entry.RawCommand = rawCmd;
                        entry.ResolvedExePath = resolvedExe;
                        entry.SourceKind = "Task";
                        entry.ScheduledTaskPath = taskFullPath;
                        entry.Enabled = enabled;
                        entry.IsPolicyLocked = false;
                        entry.IsOrphan = isMissing;
                        entry.ProtectionKind = IsProtectedOemOrSystemStartup(entry.DisplayName, rawCmd, author);
                        entry.ImpactLevel = EstimateImpact(entry.DisplayName, rawCmd, author);
                        entry.RequiresAdmin = true;
                        entry.CanDelete = true;
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
                        object sf = subFolders.GetType().InvokeMember("Item", BindingFlags.GetProperty, null, subFolders, new object[] { fi });
                        if (sf != null) TraverseScheduledTaskFolder(sf, list);
                    } catch {}
                }
            } catch {}
        }

        private static void ScanScheduledTasks(List<StartupEntry> list) {
            object svc = null;
            try {
                svc = ConnectTaskService();
                if (svc == null) return;
                object root = ComCall(svc, "GetFolder", @"\");
                if (root != null) {
                    TraverseScheduledTaskFolder(root, list);
                }
            } catch {
            } finally {
                if (svc != null) {
                    try { Marshal.ReleaseComObject(svc); } catch {}
                }
            }
        }

        public static StartupEntry[] ScanExtended() {
            var list = new List<StartupEntry>(32);
            ScanUwpStartupTasks(list);
            ScanScheduledTasks(list);
            return list.ToArray();
        }

        public static Task<StartupEntry[]> ScanExtendedAsync() {
            return Task.Run(delegate() { return ScanExtended(); });
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

        public static StartupHydratedPatch[] HydrateEntriesAndIcons(StartupEntry[] entries) {
            if (entries == null || entries.Length == 0) return new StartupHydratedPatch[0];
            var patches = new List<StartupHydratedPatch>(entries.Length);
            for (int i = 0; i < entries.Length; i++) {
                StartupEntry e = entries[i];
                if (e == null) continue;
                string disp = e.DisplayName ?? "";
                string pub = e.Publisher ?? "";
                if (!e.MetadataHydrated && !string.IsNullOrWhiteSpace(e.ResolvedExePath) && File.Exists(e.ResolvedExePath)) {
                    try {
                        string ext = Path.GetExtension(e.ResolvedExePath) ?? "";
                        if (ext.Equals(".exe", StringComparison.OrdinalIgnoreCase) || ext.Equals(".dll", StringComparison.OrdinalIgnoreCase)) {
                            FileVersionInfo fvi = FileVersionInfo.GetVersionInfo(e.ResolvedExePath);
                            if (fvi != null) {
                                string fd = (fvi.FileDescription ?? "").Trim();
                                string pn = (fvi.ProductName ?? "").Trim();
                                string cn = (fvi.CompanyName ?? "").Trim();
                                if (!string.IsNullOrEmpty(cn) && string.IsNullOrEmpty(pub)) pub = cn;
                                if (!string.IsNullOrEmpty(fd) && fd.Length >= 3 && fd.Length <= 64 &&
                                    (string.IsNullOrEmpty(disp) || disp.IndexOf("AutoLaunch", StringComparison.OrdinalIgnoreCase) >= 0 || disp.Equals(Path.GetFileNameWithoutExtension(e.ResolvedExePath), StringComparison.OrdinalIgnoreCase))) {
                                    disp = fd;
                                } else if (!string.IsNullOrEmpty(pn) && pn.Length >= 3 && pn.Length <= 64 &&
                                    (string.IsNullOrEmpty(disp) || disp.IndexOf("AutoLaunch", StringComparison.OrdinalIgnoreCase) >= 0)) {
                                    disp = pn;
                                }
                            }
                        }
                    } catch {}
                }

                string iconSource = !string.IsNullOrWhiteSpace(e.LogoPath) ? e.LogoPath : e.ResolvedExePath;
                if (string.IsNullOrWhiteSpace(iconSource) || !File.Exists(iconSource)) {
                    if (!string.IsNullOrWhiteSpace(e.FolderFilePath) && File.Exists(e.FolderFilePath)) {
                        iconSource = e.FolderFilePath;
                    }
                }
                BitmapSource bmp = ExtractStartupIcon(iconSource);

                var patch = new StartupHydratedPatch();
                patch.Id = e.Id;
                patch.DisplayName = disp;
                patch.Publisher = pub;
                patch.ProtectionKind = IsProtectedOemOrSystemStartup(disp + " " + e.Name, e.RawCommand, pub);
                patch.ImpactLevel = EstimateImpact(disp + " " + e.Name, e.RawCommand, pub);
                patch.IconBitmap = bmp;
                patches.Add(patch);
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

        public static StartupOpResult SetStartupEnabled(StartupEntry entry, bool enable) {
            var res = new StartupOpResult { Success = false, RequiresAdminError = false, Message = "" };
            if (entry == null) { res.Message = "Invalid entry"; return res; }
            if (entry.IsPolicyLocked) {
                res.Message = "PolicyLocked";
                return res;
            }

            if (string.Equals(entry.SourceKind, "Store", StringComparison.OrdinalIgnoreCase)) {
                try {
                    string subPath = RegSystemAppDataPath + @"\" + entry.PackageFamilyName + @"\" + entry.TaskId;
                    using (RegistryKey hkcu = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64))
                    using (RegistryKey k = hkcu.OpenSubKey(subPath, true)) {
                        if (k == null) { res.Message = "KeyNotFound"; return res; }
                        int targetState = enable ? 2 : 1;
                        k.SetValue("State", targetState, RegistryValueKind.DWord);
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
                ComCall(folder, "RegisterTask", taskName, xml, 6, null, null, 3, null);
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

        public static StartupOpResult AddStartupEntry(string name, string exePath, string args) {
            var res = new StartupOpResult { Success = false, RequiresAdminError = false, Message = "" };
            if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(exePath)) {
                res.Message = "InvalidInput";
                return res;
            }
            try {
                string cleanName = name.Trim();
                string cleanExe = exePath.Trim().Trim('"');
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
    }
}
