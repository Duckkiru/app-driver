using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using Microsoft.Win32;

namespace DuckUtil {
    public sealed class ResourceDiskInfo {
        public string DriveName { get; set; }
        public long TotalBytes { get; set; }
        public long FreeBytes { get; set; }
        public long UsedBytes { get; set; }
        public double UsedPercent { get; set; }
        public string SummaryText { get; set; }
    }

    public sealed class ResourceDetailItem {
        public string Path { get; set; }
        public string DisplayPath { get; set; }
        public long SizeBytes { get; set; }
        public int NestedCount { get; set; }
        public bool IsDirectory { get; set; }
        public bool IsOneDrive { get; set; }
        public bool Selected { get; set; }
        public string Kind { get; set; }
        public string Note { get; set; }
    }

    public sealed class ResourceCleanCategory {
        public string Id { get; set; }
        public int Tier { get; set; }
        public string FilterGroup { get; set; }
        public string RiskLevel { get; set; }
        public string Title { get; set; }
        public string Description { get; set; }
        public string WarningNote { get; set; }
        public string StatusNote { get; set; }
        public string CleanMode { get; set; }
        public bool SupportsRecycleBin { get; set; }
        public bool DefaultSelected { get; set; }
        public bool Selected { get; set; }
        public bool SkippedBecauseRebootPending { get; set; }
        public bool IsDeliveryOptimization { get; set; }
        public long TotalBytes { get; set; }
        public int ItemCount { get; set; }
        public int FolderCount { get; set; }
        public string[] RootPaths { get; set; }
        public string[] FilePatterns { get; set; }
        public List<ResourceDetailItem> DetailItems { get; set; }
    }

    public sealed class ResourceScanReport {
        public ResourceDiskInfo DiskInfo { get; set; }
        public ResourceCleanCategory[] Categories { get; set; }
        public long TotalBytes { get; set; }
        public int TotalFiles { get; set; }
        public int TotalEmptyFolders { get; set; }
        public long ScanElapsedMs { get; set; }
        public bool WasCancelled { get; set; }
    }

    public sealed class ResourceCleanReport {
        public long FreedBytes { get; set; }
        public int DeletedFiles { get; set; }
        public int DeletedFolders { get; set; }
        public int RecycledItems { get; set; }
        public int SkippedLockedCount { get; set; }
        public int SkippedRecycleUnsupportedCount { get; set; }
        public int SkippedCloudCount { get; set; }
        public bool NeedsDeliveryOptCmdlet { get; set; }
        public bool WasCancelled { get; set; }
        public long ElapsedMs { get; set; }
        public string[] PerCategoryLogs { get; set; }
    }

    public sealed class ResourceRowVisual {
        public ResourceCleanCategory Category { get; set; }
        public System.Windows.Controls.Border Row { get; set; }
        public System.Windows.Controls.CheckBox CheckBox { get; set; }
        public System.Windows.Controls.TextBlock TitleText { get; set; }
        public System.Windows.Controls.TextBlock SubText { get; set; }
        public System.Windows.Controls.TextBlock SizeText { get; set; }
        public System.Windows.Controls.TextBlock CountText { get; set; }
        public System.Windows.Controls.Button DetailsBtn { get; set; }
        public System.Windows.Controls.Button OpenBtn { get; set; }
        public System.Windows.Controls.Border DetailsContainer { get; set; }
        public System.Windows.Controls.StackPanel DetailsHost { get; set; }
        public bool DetailsExpanded { get; set; }
        public bool DetailsPopulated { get; set; }
    }

    public static class ResourceCleanerEngine {
        private const uint FILE_ATTRIBUTE_READONLY = 0x00000001u;
        private const uint FILE_ATTRIBUTE_HIDDEN = 0x00000002u;
        private const uint FILE_ATTRIBUTE_SYSTEM = 0x00000004u;
        private const uint FILE_ATTRIBUTE_DIRECTORY = 0x00000010u;
        private const uint FILE_ATTRIBUTE_NORMAL = 0x00000080u;
        private const uint FILE_ATTRIBUTE_REPARSE_POINT = 0x00000400u;
        private const uint FILE_ATTRIBUTE_OFFLINE = 0x00001000u;
        private const uint FILE_ATTRIBUTE_RECALL_ON_OPEN = 0x00040000u;
        private const uint FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS = 0x00400000u;
        private const uint INVALID_FILE_ATTRIBUTES = 0xFFFFFFFFu;
        private const uint CLOUD_OR_REPARSE_MASK = FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_OFFLINE | FILE_ATTRIBUTE_RECALL_ON_OPEN | FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS;

        private const uint FIND_FIRST_EX_LARGE_FETCH = 0x00000002u;
        private const int FINDEX_INFO_BASIC = 1;
        private const int FINDEX_SEARCH_NAME_MATCH = 0;

        private const uint SHERB_NOCONFIRMATION = 0x00000001u;
        private const uint SHERB_NOPROGRESSUI = 0x00000002u;
        private const uint SHERB_NOSOUND = 0x00000004u;

        private const uint FOF_SILENT = 0x0004u;
        private const uint FOF_NOCONFIRMATION = 0x0010u;
        private const uint FOF_ALLOWUNDO = 0x0040u;
        private const uint FOF_NOERRORUI = 0x0400u;
        private const uint FOFX_RECYCLEONDELETE = 0x00080000u;
        private const uint FOFX_ADDUNDORECORD = 0x20000000u;
        private const uint RECYCLE_STRICT_FLAGS = FOF_SILENT | FOF_NOCONFIRMATION | FOF_ALLOWUNDO | FOF_NOERRORUI | FOFX_RECYCLEONDELETE | FOFX_ADDUNDORECORD;

        private static readonly string SID_LOCAL_SYSTEM = "S-1-5-18";
        private static readonly string SID_TRUSTED_INSTALLER = "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464";

        private static readonly Guid FOLDERID_Downloads = new Guid("374DE290-123F-4565-9164-39C4925E467B");
        private static readonly Guid FOLDERID_Desktop = new Guid("B4BFCC3A-DB2C-424C-B029-7FE99A87C641");
        private static readonly Guid CLSID_FileOperation = new Guid("3ad05575-8857-4850-9277-11b85bdb8e09");
        private static readonly Guid IID_IShellItem = new Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe");

        private const long LARGE_FILE_THRESHOLD_BYTES = 500L * 1024L * 1024L;
        private const int MAX_EMPTY_SCAN_DEPTH = 14;
        private const int MAX_EMPTY_DETAIL_ITEMS = 500;
        private const int MAX_ZERO_DETAIL_ITEMS = 300;
        private const int MAX_LARGE_DETAIL_ITEMS = 120;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct FILETIME_W32 {
            public uint dwLowDateTime;
            public uint dwHighDateTime;
            public DateTime ToUtcDateTime() {
                long ft = (((long)dwHighDateTime) << 32) | dwLowDateTime;
                if (ft <= 0) return DateTime.MinValue;
                try { return DateTime.FromFileTimeUtc(ft); } catch { return DateTime.MinValue; }
            }
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WIN32_FIND_DATAW {
            public uint dwFileAttributes;
            public FILETIME_W32 ftCreationTime;
            public FILETIME_W32 ftLastAccessTime;
            public FILETIME_W32 ftLastWriteTime;
            public uint nFileSizeHigh;
            public uint nFileSizeLow;
            public uint dwReserved0;
            public uint dwReserved1;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            public string cFileName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)]
            public string cAlternateFileName;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        private struct SHQUERYRBINFO {
            public uint cbSize;
            public long i64Size;
            public long i64NumItems;
        }

        [ComImport]
        [Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IShellItemRC {
            void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
            void GetParent(out IShellItemRC ppsi);
            void GetDisplayName(uint sigdnName, out IntPtr ppszName);
            void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
            void Compare(IShellItemRC psi, uint hint, out int piOrder);
        }

        [ComImport]
        [Guid("947aab5f-0a5c-4c13-b4d6-4bf7836fc9f8")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IFileOperationRC {
            [PreserveSig] int Advise(IntPtr pfops, out uint pdwCookie);
            [PreserveSig] int Unadvise(uint dwCookie);
            [PreserveSig] int SetOperationFlags(uint dwOperationFlags);
            [PreserveSig] int SetProgressMessage([MarshalAs(UnmanagedType.LPWStr)] string pszMessage);
            [PreserveSig] int SetProgressDialog(IntPtr popd);
            [PreserveSig] int SetProperties(IntPtr pproparray);
            [PreserveSig] int SetOwnerWindow(IntPtr hwndParent);
            [PreserveSig] int ApplyPropertiesToItem(IShellItemRC psiItem);
            [PreserveSig] int ApplyPropertiesToItems(IntPtr punkItems);
            [PreserveSig] int RenameItem(IShellItemRC psiItem, [MarshalAs(UnmanagedType.LPWStr)] string pszNewName, IntPtr pfopsItem);
            [PreserveSig] int RenameItems(IntPtr pUnkItems, [MarshalAs(UnmanagedType.LPWStr)] string pszNewName);
            [PreserveSig] int MoveItem(IShellItemRC psiItem, IShellItemRC psiDestinationFolder, [MarshalAs(UnmanagedType.LPWStr)] string pszNewName, IntPtr pfopsItem);
            [PreserveSig] int MoveItems(IntPtr punkItems, IShellItemRC psiDestinationFolder);
            [PreserveSig] int CopyItem(IShellItemRC psiItem, IShellItemRC psiDestinationFolder, [MarshalAs(UnmanagedType.LPWStr)] string pszCopyName, IntPtr pfopsItem);
            [PreserveSig] int CopyItems(IntPtr punkItems, IShellItemRC psiDestinationFolder);
            [PreserveSig] int DeleteItem(IShellItemRC psiItem, IntPtr pfopsItem);
            [PreserveSig] int DeleteItems(IntPtr punkItems);
            [PreserveSig] int NewItem(IShellItemRC psiDestinationFolder, uint dwFileAttributes, [MarshalAs(UnmanagedType.LPWStr)] string pszName, [MarshalAs(UnmanagedType.LPWStr)] string pszTemplateName, IntPtr pfopsItem);
            [PreserveSig] int PerformOperations();
            [PreserveSig] int GetAnyOperationsAborted([MarshalAs(UnmanagedType.Bool)] out bool pfAnyOperationsAborted);
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr FindFirstFileExW(string lpFileName, int fInfoLevelId, out WIN32_FIND_DATAW lpFindFileData, int fSearchOp, IntPtr lpSearchFilter, uint dwAdditionalFlags);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FindNextFileW(IntPtr hFindFile, out WIN32_FIND_DATAW lpFindFileData);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FindClose(IntPtr hFindFile);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFileAttributesW(string lpFileName);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetFileAttributesW(string lpFileName, uint dwFileAttributes);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DeleteFileW(string lpFileName);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool RemoveDirectoryW(string lpPathName);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SHGetKnownFolderPath(ref Guid rfid, uint dwFlags, IntPtr hToken, out IntPtr ppszPath);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SHQueryRecycleBinW(string pszRootPath, ref SHQUERYRBINFO pSHQueryRBInfo);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SHEmptyRecycleBinW(IntPtr hwnd, string pszRootPath, uint dwFlags);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SHCreateItemFromParsingName([MarshalAs(UnmanagedType.LPWStr)] string pszPath, IntPtr pbc, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IShellItemRC ppv);

        private static readonly HashSet<string> HardBlockedDirNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
            "windows", "$recycle.bin", "system volume information", "recovery", "perflogs", "windowsapps",
            "package cache", ".git", ".hg", ".svn", ".ssh", ".gnupg", ".vscode", ".idea", ".cursor",
            "node_modules", ".venv", "venv", "__pycache__", "onedrive", "google drive", "iclouddrive",
            "dropbox", "appdriver", "duckutil", "microsoft", "common files", "winsxs", "installer",
            "assembly", "system32", "syswow64", "boot", "efi"
        };

        private static readonly HashSet<string> ProtectedRuntimeDirNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
            "logs", "log", "staging", "queue", "spool", "incoming", "dlc", "drop", "crashreports",
            "plugins", "plugin", "mods", "mod", "extensions", "profiles", "default", "user data",
            "indexeddb", "local storage", "session storage", "databases", "cache", "temp", "tmp",
            "backups", "backup", "screenshots", "saved games", "desktop", "documents", "pictures",
            "videos", "music", "downloads", "favorites", "links", "contacts", "searches", "appdata",
            "roaming", "local", "locallow", "programdata", "program files", "program files (x86)",
            "users", "public", "bin", "obj", "dist", "build", "src", "assets", "data", "config",
            "settings", "state", "storage", "sessions", "workspaces", "zaloreceivedfiles", "zalodownloads"
        };

        private static readonly HashSet<string> DisposableZeroByteExts = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
            ".tmp", ".temp", ".bak", ".old", ".log", ".dmp",
            ".crdownload", ".part", ".download", ".partial", ".!ut", ".opdownload", ".filepart"
        };

        private static readonly HashSet<string> NeverTouchBrowserNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
            "cookies", "login data", "login data for account", "bookmarks", "bookmarks.bak",
            "history", "web data", "local storage", "session storage", "extensions",
            "extension state", "indexeddb", "preferences", "secure preferences", "places.sqlite",
            "logins.json", "key4.db", "cookies.sqlite"
        };

        public static string ToExtendedPath(string path) {
            if (string.IsNullOrWhiteSpace(path)) return path;
            string p = path.Trim();
            if (p.StartsWith(@"\\?\", StringComparison.Ordinal)) return p;
            if (p.StartsWith(@"\\", StringComparison.Ordinal)) {
                return @"\\?\UNC\" + p.Substring(2);
            }
            try {
                if (p.Length < 248) p = Path.GetFullPath(p);
            } catch {}
            return @"\\?\" + p;
        }

        public static string StripExtendedPath(string path) {
            if (string.IsNullOrWhiteSpace(path)) return path;
            if (path.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) {
                return @"\\" + path.Substring(8);
            }
            if (path.StartsWith(@"\\?\", StringComparison.Ordinal)) {
                return path.Substring(4);
            }
            return path;
        }

        public static string NormalizeCleanPath(string path) {
            if (string.IsNullOrWhiteSpace(path)) return "";
            string s = StripExtendedPath(path.Trim());
            try {
                if (s.Length < 248) s = Path.GetFullPath(s);
            } catch {}
            if (s.Length > 3) s = s.TrimEnd('\\', '/');
            return s;
        }

        public static string FormatBytes(long bytes) {
            if (bytes <= 0) return "0 B";
            double v = bytes;
            string[] units = { "B", "KB", "MB", "GB", "TB" };
            int idx = 0;
            while (v >= 1024.0 && idx < units.Length - 1) {
                v /= 1024.0;
                idx++;
            }
            if (idx <= 1) return string.Format("{0:0} {1}", v, units[idx]);
            if (v >= 100.0) return string.Format("{0:0.0} {1}", v, units[idx]);
            return string.Format("{0:0.00} {1}", v, units[idx]);
        }

        public static string GetKnownFolderPathSafe(string kind) {
            Guid g = string.Equals(kind, "Desktop", StringComparison.OrdinalIgnoreCase) ? FOLDERID_Desktop : FOLDERID_Downloads;
            IntPtr pPath = IntPtr.Zero;
            try {
                int hr = SHGetKnownFolderPath(ref g, 0, IntPtr.Zero, out pPath);
                if (hr == 0 && pPath != IntPtr.Zero) {
                    string res = Marshal.PtrToStringUni(pPath);
                    if (!string.IsNullOrWhiteSpace(res)) return NormalizeCleanPath(res);
                }
            } catch {}
            finally {
                if (pPath != IntPtr.Zero) {
                    try { Marshal.FreeCoTaskMem(pPath); } catch {}
                }
            }
            try {
                if (string.Equals(kind, "Desktop", StringComparison.OrdinalIgnoreCase)) {
                    return NormalizeCleanPath(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory));
                }
                string prof = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                if (!string.IsNullOrWhiteSpace(prof)) return NormalizeCleanPath(Path.Combine(prof, "Downloads"));
            } catch {}
            return "";
        }

        public static bool IsPathInsideOneDrive(string path) {
            if (string.IsNullOrWhiteSpace(path)) return false;
            string norm = NormalizeCleanPath(path);
            string[] envNames = { "OneDrive", "OneDriveConsumer", "OneDriveCommercial" };
            for (int i = 0; i < envNames.Length; i++) {
                string od = Environment.GetEnvironmentVariable(envNames[i]);
                if (!string.IsNullOrWhiteSpace(od)) {
                    string odNorm = NormalizeCleanPath(od);
                    if (norm.Equals(odNorm, StringComparison.OrdinalIgnoreCase) ||
                        norm.StartsWith(odNorm + @"\", StringComparison.OrdinalIgnoreCase)) {
                        return true;
                    }
                }
            }
            string lower = norm.ToLowerInvariant();
            if (lower.Contains(@"\onedrive\") || lower.EndsWith(@"\onedrive") || lower.Contains(@"\onedrive - ")) {
                return true;
            }
            return false;
        }

        public static bool IsWindowsUpdateRebootPending() {
            try {
                using (RegistryKey k1 = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired", false)) {
                    if (k1 != null) return true;
                }
            } catch {}
            try {
                using (RegistryKey k2 = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending", false)) {
                    if (k2 != null) return true;
                }
            } catch {}
            return false;
        }

        public static ResourceDiskInfo GetSystemDiskInfo() {
            var info = new ResourceDiskInfo();
            string sysRoot = Environment.GetEnvironmentVariable("SystemDrive");
            if (string.IsNullOrWhiteSpace(sysRoot)) sysRoot = "C:";
            info.DriveName = sysRoot;
            try {
                var di = new DriveInfo(sysRoot);
                if (di.IsReady) {
                    info.TotalBytes = di.TotalSize;
                    info.FreeBytes = di.AvailableFreeSpace;
                    info.UsedBytes = Math.Max(0L, di.TotalSize - di.AvailableFreeSpace);
                    info.UsedPercent = di.TotalSize > 0 ? Math.Round(((double)info.UsedBytes / (double)di.TotalSize) * 100.0, 1) : 0.0;
                    info.SummaryText = string.Format("{0} tr\u1ED1ng {1} ({2:0}%)",
                        sysRoot, FormatBytes(info.FreeBytes), info.UsedPercent);
                    return info;
                }
            } catch {}
            info.SummaryText = string.Format("\u1ED4 {0}: kh\u00F4ng \u0111\u1ECDc \u0111\u01B0\u1EE3c dung l\u01B0\u1EE3ng", sysRoot);
            return info;
        }

        public static bool IsProtectedSystemOwnerBySid(string dirPath) {
            try {
                string clean = StripExtendedPath(dirPath);
                var di = new DirectoryInfo(clean);
                DirectorySecurity sec = di.GetAccessControl(AccessControlSections.Owner);
                IdentityReference ownerRef = sec.GetOwner(typeof(SecurityIdentifier));
                if (ownerRef != null) {
                    string sid = ownerRef.Value ?? "";
                    if (string.Equals(sid, SID_TRUSTED_INSTALLER, StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(sid, SID_LOCAL_SYSTEM, StringComparison.OrdinalIgnoreCase)) {
                        return true;
                    }
                }
                return false;
            } catch (UnauthorizedAccessException) {
                return true;
            } catch {
                return true;
            }
        }

        private static bool IsHardProtectedPath(string normPath) {
            if (string.IsNullOrWhiteSpace(normPath)) return true;
            string winDir = NormalizeCleanPath(Environment.GetFolderPath(Environment.SpecialFolder.Windows));
            if (!string.IsNullOrWhiteSpace(winDir) &&
                (normPath.Equals(winDir, StringComparison.OrdinalIgnoreCase) ||
                 normPath.StartsWith(winDir + @"\", StringComparison.OrdinalIgnoreCase))) {
                return true;
            }
            string localApp = NormalizeCleanPath(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
            if (!string.IsNullOrWhiteSpace(localApp)) {
                string adSess = Path.Combine(localApp, @"AppDriver\Session");
                if (normPath.Equals(adSess, StringComparison.OrdinalIgnoreCase) ||
                    normPath.StartsWith(adSess + @"\", StringComparison.OrdinalIgnoreCase)) {
                    return true;
                }
                string duckCache = Path.Combine(localApp, @"DuckUtil\Cache");
                if (normPath.Equals(duckCache, StringComparison.OrdinalIgnoreCase) ||
                    normPath.StartsWith(duckCache + @"\", StringComparison.OrdinalIgnoreCase)) {
                    return true;
                }
            }
            return false;
        }

        private static bool IsPathSafeForEmptyFolderScan(string normPath, string leafName) {
            if (string.IsNullOrWhiteSpace(normPath) || string.IsNullOrWhiteSpace(leafName)) return false;
            if (normPath.Length <= 3) return false;
            if (HardBlockedDirNames.Contains(leafName)) return false;
            if (ProtectedRuntimeDirNames.Contains(leafName)) return false;
            if (IsHardProtectedPath(normPath)) return false;
            if (IsPathInsideOneDrive(normPath)) return false;
            string progFiles = NormalizeCleanPath(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles));
            string progFiles86 = NormalizeCleanPath(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86));
            string progData = NormalizeCleanPath(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData));
            if ((!string.IsNullOrWhiteSpace(progFiles) && normPath.Equals(progFiles, StringComparison.OrdinalIgnoreCase)) ||
                (!string.IsNullOrWhiteSpace(progFiles86) && normPath.Equals(progFiles86, StringComparison.OrdinalIgnoreCase)) ||
                (!string.IsNullOrWhiteSpace(progData) && normPath.Equals(progData, StringComparison.OrdinalIgnoreCase))) {
                return false;
            }
            return true;
        }

        private static bool DirExistsWin32(string path, out uint attr) {
            attr = GetFileAttributesW(ToExtendedPath(path));
            return attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY) != 0;
        }

        private static bool FileExistsWin32(string path, out uint attr) {
            attr = GetFileAttributesW(ToExtendedPath(path));
            return attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY) == 0;
        }

        public static string[] DeduplicateNormalizedPaths(string[] rawPaths) {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var list = new List<string>();
            if (rawPaths == null) return list.ToArray();
            for (int i = 0; i < rawPaths.Length; i++) {
                string n = NormalizeCleanPath(rawPaths[i]);
                if (string.IsNullOrWhiteSpace(n)) continue;
                if (seen.Add(n)) list.Add(n);
            }
            return list.ToArray();
        }

        public static bool IsSafeBrowserCacheLeaf(string dirPath) {
            if (string.IsNullOrWhiteSpace(dirPath)) return false;
            string leaf = Path.GetFileName(dirPath.TrimEnd('\\', '/')) ?? "";
            if (NeverTouchBrowserNames.Contains(leaf)) return false;
            string low = dirPath.ToLowerInvariant();
            if (low.Contains(@"\cookies") || low.Contains(@"\login data") || low.Contains(@"\bookmarks") ||
                low.Contains(@"\history") || low.Contains(@"\web data") || low.Contains(@"\local storage") ||
                low.Contains(@"\extensions") || low.Contains(@"\zaloreceivedfiles") || low.Contains(@"\zalodownloads")) {
                return false;
            }
            return true;
        }

        private static void MeasureDirectoryRecursive(string rootDir, string[] patterns, bool topLevelOnly, CancellationToken ct, ref long bytes, ref int files, ref int folders, int depth) {
            if (ct.IsCancellationRequested || depth > 24) return;
            uint rootAttr;
            if (!DirExistsWin32(rootDir, out rootAttr)) return;
            if ((rootAttr & CLOUD_OR_REPARSE_MASK) != 0) return;

            string normRoot = NormalizeCleanPath(rootDir);
            if (depth > 0 && IsHardProtectedPath(normRoot)) return;

            string searchSpec = ToExtendedPath(normRoot) + @"\*";
            WIN32_FIND_DATAW fd;
            IntPtr h = FindFirstFileExW(searchSpec, FINDEX_INFO_BASIC, out fd, FINDEX_SEARCH_NAME_MATCH, IntPtr.Zero, FIND_FIRST_EX_LARGE_FETCH);
            if (h == IntPtr.Zero || h == new IntPtr(-1)) return;
            try {
                do {
                    if (ct.IsCancellationRequested) break;
                    string name = fd.cFileName;
                    if (string.IsNullOrEmpty(name) || name == "." || name == "..") continue;
                    if ((fd.dwFileAttributes & CLOUD_OR_REPARSE_MASK) != 0) continue;

                    string full = normRoot + @"\" + name;
                    if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
                        if (topLevelOnly) continue;
                        if (IsHardProtectedPath(full)) continue;
                        folders++;
                        MeasureDirectoryRecursive(full, patterns, false, ct, ref bytes, ref files, ref folders, depth + 1);
                    } else {
                        if (NeverTouchBrowserNames.Contains(name)) continue;
                        if (patterns != null && patterns.Length > 0 && !MatchesAnyWildcard(name, patterns)) continue;
                        long sz = (((long)fd.nFileSizeHigh) << 32) | fd.nFileSizeLow;
                        if (sz > 0) bytes += sz;
                        files++;
                    }
                } while (FindNextFileW(h, out fd));
            } finally {
                FindClose(h);
            }
        }

        private static bool MatchesAnyWildcard(string fileName, string[] patterns) {
            if (patterns == null || patterns.Length == 0) return true;
            for (int i = 0; i < patterns.Length; i++) {
                string pat = patterns[i];
                if (string.IsNullOrEmpty(pat) || pat == "*") return true;
                if (pat.StartsWith("*", StringComparison.Ordinal) && pat.EndsWith("*", StringComparison.Ordinal) && pat.Length > 2) {
                    string mid = pat.Substring(1, pat.Length - 2);
                    if (fileName.IndexOf(mid, StringComparison.OrdinalIgnoreCase) >= 0) return true;
                } else if (pat.StartsWith("*", StringComparison.Ordinal)) {
                    if (fileName.EndsWith(pat.Substring(1), StringComparison.OrdinalIgnoreCase)) return true;
                } else if (pat.EndsWith("*", StringComparison.Ordinal)) {
                    if (fileName.StartsWith(pat.Substring(0, pat.Length - 1), StringComparison.OrdinalIgnoreCase)) return true;
                } else {
                    int star = pat.IndexOf('*');
                    if (star > 0) {
                        string pre = pat.Substring(0, star);
                        string suf = pat.Substring(star + 1);
                        if (fileName.StartsWith(pre, StringComparison.OrdinalIgnoreCase) &&
                            fileName.EndsWith(suf, StringComparison.OrdinalIgnoreCase) &&
                            fileName.Length >= pre.Length + suf.Length) {
                            return true;
                        }
                    } else if (fileName.Equals(pat, StringComparison.OrdinalIgnoreCase)) {
                        return true;
                    }
                }
            }
            return false;
        }

        private static void PopulateDirectoryCategory(ResourceCleanCategory cat, string[] rawRoots, string[] patterns, bool topLevelOnly, CancellationToken ct) {
            string[] roots = DeduplicateNormalizedPaths(rawRoots);
            var validRoots = new List<string>();
            cat.DetailItems = new List<ResourceDetailItem>();
            long totalB = 0;
            int totalF = 0;
            int totalD = 0;

            for (int i = 0; i < roots.Length; i++) {
                if (ct.IsCancellationRequested) break;
                string r = roots[i];
                uint attr;
                if (!DirExistsWin32(r, out attr)) continue;
                if ((attr & CLOUD_OR_REPARSE_MASK) != 0) continue;

                long rb = 0;
                int rf = 0;
                int rd = 0;
                MeasureDirectoryRecursive(r, patterns, topLevelOnly, ct, ref rb, ref rf, ref rd, 0);
                if (rf > 0 || rb > 0) {
                    validRoots.Add(r);
                    totalB += rb;
                    totalF += rf;
                    totalD += rd;
                    cat.DetailItems.Add(new ResourceDetailItem {
                        Path = r,
                        DisplayPath = r,
                        SizeBytes = rb,
                        NestedCount = rf,
                        IsDirectory = true,
                        IsOneDrive = IsPathInsideOneDrive(r),
                        Selected = true,
                        Kind = "CacheRoot",
                        Note = string.Format("{0} t\u1EC7p", rf)
                    });
                }
            }
            cat.RootPaths = validRoots.ToArray();
            cat.FilePatterns = patterns;
            cat.TotalBytes = totalB;
            cat.ItemCount = totalF;
            cat.FolderCount = totalD;
            if (totalB == 0 && totalF == 0) {
                cat.Selected = false;
            }
        }

        private static string[] CollectChromiumCacheDirs() {
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var results = new List<string>();
            if (string.IsNullOrWhiteSpace(local)) return results.ToArray();

            string[] userDataRoots = {
                Path.Combine(local, @"Google\Chrome\User Data"),
                Path.Combine(local, @"Microsoft\Edge\User Data"),
                Path.Combine(local, @"BraveSoftware\Brave-Browser\User Data"),
                Path.Combine(local, @"Vivaldi\User Data"),
                Path.Combine(local, @"CocCoc\Browser\User Data")
            };

            string[] cacheSubs = {
                @"Cache\Cache_Data",
                "Cache",
                "Code Cache",
                "GPUCache",
                "DawnCache",
                "GrShaderCache",
                "ShaderCache",
                @"Service Worker\CacheStorage",
                @"Service Worker\ScriptCache"
            };

            var rootList = new List<string>(userDataRoots);
            try {
                string pkgRoot = Path.Combine(local, "Packages");
                uint pAttr;
                if (DirExistsWin32(pkgRoot, out pAttr)) {
                    foreach (string pkg in Directory.GetDirectories(pkgRoot, "TheBrowserCompany.Arc_*")) {
                        rootList.Add(Path.Combine(pkg, @"LocalCache\Local\Arc\User Data"));
                    }
                }
            } catch {}

            for (int r = 0; r < rootList.Count; r++) {
                string ud = rootList[r];
                uint uAttr;
                if (!DirExistsWin32(ud, out uAttr)) continue;
                try {
                    string[] subDirs = Directory.GetDirectories(ud);
                    for (int p = 0; p < subDirs.Length; p++) {
                        string pName = Path.GetFileName(subDirs[p]) ?? "";
                        if (!pName.Equals("Default", StringComparison.OrdinalIgnoreCase) &&
                            !pName.StartsWith("Profile ", StringComparison.OrdinalIgnoreCase) &&
                            !pName.Equals("Guest Profile", StringComparison.OrdinalIgnoreCase)) {
                            continue;
                        }
                        for (int s = 0; s < cacheSubs.Length; s++) {
                            string cand = Path.Combine(subDirs[p], cacheSubs[s]);
                            if (cacheSubs[s] == "Cache" && Directory.Exists(Path.Combine(subDirs[p], @"Cache\Cache_Data"))) continue;
                            uint cAttr;
                            if (DirExistsWin32(cand, out cAttr) && IsSafeBrowserCacheLeaf(cand)) {
                                results.Add(cand);
                            }
                        }
                    }
                } catch {}
            }
            return DeduplicateNormalizedPaths(results.ToArray());
        }

        private static string[] CollectOperaCacheDirs() {
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var results = new List<string>();
            if (string.IsNullOrWhiteSpace(local)) return results.ToArray();

            string[] operaBases = {
                Path.Combine(local, @"Opera Software\Opera Stable"),
                Path.Combine(local, @"Opera Software\Opera GX Stable"),
                Path.Combine(local, @"Opera Software\Opera Air Stable")
            };
            string[] subs = { @"Cache\Cache_Data", "System Cache", "Code Cache", "GPUCache", "ShaderCache" };
            for (int i = 0; i < operaBases.Length; i++) {
                uint bAttr;
                if (!DirExistsWin32(operaBases[i], out bAttr)) continue;
                for (int s = 0; s < subs.Length; s++) {
                    string cand = Path.Combine(operaBases[i], subs[s]);
                    uint cAttr;
                    if (DirExistsWin32(cand, out cAttr) && IsSafeBrowserCacheLeaf(cand)) {
                        results.Add(cand);
                    }
                }
            }
            return DeduplicateNormalizedPaths(results.ToArray());
        }

        private static string[] CollectGeckoCacheDirs() {
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var results = new List<string>();
            if (string.IsNullOrWhiteSpace(local)) return results.ToArray();

            string[] geckoRoots = {
                Path.Combine(local, @"Mozilla\Firefox\Profiles"),
                Path.Combine(local, @"zen\Profiles"),
                Path.Combine(local, @"Floorp\Profiles"),
                Path.Combine(local, @"LibreWolf\Profiles")
            };
            string[] subs = { "cache2", "startupCache", "jumpListCache" };
            for (int i = 0; i < geckoRoots.Length; i++) {
                uint rAttr;
                if (!DirExistsWin32(geckoRoots[i], out rAttr)) continue;
                try {
                    foreach (string prof in Directory.GetDirectories(geckoRoots[i])) {
                        for (int s = 0; s < subs.Length; s++) {
                            string cand = Path.Combine(prof, subs[s]);
                            uint cAttr;
                            if (DirExistsWin32(cand, out cAttr) && IsSafeBrowserCacheLeaf(cand)) {
                                results.Add(cand);
                            }
                        }
                    }
                } catch {}
            }
            return DeduplicateNormalizedPaths(results.ToArray());
        }

        private static string[] CollectElectronAndChatCacheDirs() {
            string roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var results = new List<string>();

            string[] electronRoaming = {
                Path.Combine(roaming, "discord"),
                Path.Combine(roaming, "discordptb"),
                Path.Combine(roaming, "discordcanary"),
                Path.Combine(roaming, "Code"),
                Path.Combine(roaming, "Slack"),
                Path.Combine(roaming, "Notion")
            };
            string[] eSubs = { @"Cache\Cache_Data", "Cache", "Code Cache", "GPUCache", "DawnCache", "CachedData", "CachedExtensionVSIXs" };
            for (int i = 0; i < electronRoaming.Length; i++) {
                uint bAttr;
                if (!DirExistsWin32(electronRoaming[i], out bAttr)) continue;
                for (int s = 0; s < eSubs.Length; s++) {
                    if (eSubs[s] == "Cache" && Directory.Exists(Path.Combine(electronRoaming[i], @"Cache\Cache_Data"))) continue;
                    string cand = Path.Combine(electronRoaming[i], eSubs[s]);
                    uint cAttr;
                    if (DirExistsWin32(cand, out cAttr) && IsSafeBrowserCacheLeaf(cand)) results.Add(cand);
                }
            }

            if (!string.IsNullOrWhiteSpace(local)) {
                string spotWeb = Path.Combine(local, @"Spotify\Browser\Cache");
                uint swAttr;
                if (DirExistsWin32(spotWeb, out swAttr)) results.Add(spotWeb);

                string tgCache = Path.Combine(roaming, @"Telegram Desktop\tdata\user_data\cache");
                uint tgAttr;
                if (DirExistsWin32(tgCache, out tgAttr)) results.Add(tgCache);

                string tgMedia = Path.Combine(roaming, @"Telegram Desktop\tdata\user_data\media_cache");
                uint tgMediaAttr;
                if (DirExistsWin32(tgMedia, out tgMediaAttr)) results.Add(tgMedia);

                string zaloRoot = Path.Combine(local, "ZaloPC");
                uint zAttr;
                if (DirExistsWin32(zaloRoot, out zAttr)) {
                    try {
                        foreach (string sub in Directory.GetDirectories(zaloRoot)) {
                            string[] zSubs = { @"Cache\Cache_Data", "Cache", "Code Cache", "GPUCache" };
                            for (int zs = 0; zs < zSubs.Length; zs++) {
                                if (zSubs[zs] == "Cache" && Directory.Exists(Path.Combine(sub, @"Cache\Cache_Data"))) continue;
                                string cand = Path.Combine(sub, zSubs[zs]);
                                uint cAttr;
                                if (DirExistsWin32(cand, out cAttr) && IsSafeBrowserCacheLeaf(cand)) results.Add(cand);
                            }
                        }
                    } catch {}
                }

                try {
                    string pkgRoot = Path.Combine(local, "Packages");
                    uint pAttr;
                    if (DirExistsWin32(pkgRoot, out pAttr)) {
                        foreach (string pkg in Directory.GetDirectories(pkgRoot, "MSTeams_*")) {
                            string[] tSubs = {
                                @"LocalCache\Microsoft\MSTeams\EBWebView\Default\Cache\Cache_Data",
                                @"LocalCache\Microsoft\MSTeams\EBWebView\Default\Code Cache",
                                @"LocalCache\Microsoft\MSTeams\EBWebView\Default\GPUCache"
                            };
                            for (int ts = 0; ts < tSubs.Length; ts++) {
                                string cand = Path.Combine(pkg, tSubs[ts]);
                                uint cAttr;
                                if (DirExistsWin32(cand, out cAttr)) results.Add(cand);
                            }
                        }
                        foreach (string pkg in Directory.GetDirectories(pkgRoot, "MicrosoftWindows.Client.WebExperience_*")) {
                            string[] wSubs = {
                                @"LocalState\EBWebView\Default\Cache\Cache_Data",
                                @"LocalState\EBWebView\Default\Code Cache",
                                @"LocalState\EBWebView\Default\GPUCache"
                            };
                            for (int ws = 0; ws < wSubs.Length; ws++) {
                                string cand = Path.Combine(pkg, wSubs[ws]);
                                uint cAttr;
                                if (DirExistsWin32(cand, out cAttr)) results.Add(cand);
                            }
                        }
                    }
                } catch {}
            }
            return DeduplicateNormalizedPaths(results.ToArray());
        }

        private static string[] CollectGameLauncherCacheDirs() {
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string prog86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
            string progData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            var results = new List<string>();

            if (!string.IsNullOrWhiteSpace(local)) {
                results.Add(Path.Combine(local, @"Steam\htmlcache"));
                results.Add(Path.Combine(local, @"Riot Games\Riot Client\Data\Cache"));
                results.Add(Path.Combine(local, @"Electronic Arts\EA Desktop\cache"));
                results.Add(Path.Combine(local, @"Ubisoft Game Launcher\cache\http2"));
                string epicSaved = Path.Combine(local, @"EpicGamesLauncher\Saved");
                uint eAttr;
                if (DirExistsWin32(epicSaved, out eAttr)) {
                    try {
                        foreach (string wc in Directory.GetDirectories(epicSaved, "webcache*")) results.Add(wc);
                    } catch {}
                }
            }
            if (!string.IsNullOrWhiteSpace(prog86)) {
                results.Add(Path.Combine(prog86, @"Steam\appcache\httpcache"));
                results.Add(Path.Combine(prog86, @"Steam\package"));
                results.Add(Path.Combine(prog86, @"Steam\dumps"));
                results.Add(Path.Combine(prog86, @"Steam\logs"));
            }
            if (!string.IsNullOrWhiteSpace(progData)) {
                results.Add(Path.Combine(progData, @"Battle.net\Agent\Cache"));
            }
            return DeduplicateNormalizedPaths(results.ToArray());
        }

        private static string[] CollectGpuShaderCacheDirs() {
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string localLow = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @"AppData\LocalLow");
            var results = new List<string>();
            if (!string.IsNullOrWhiteSpace(local)) {
                results.Add(Path.Combine(local, "D3DSCache"));
                results.Add(Path.Combine(local, @"NVIDIA\DXCache"));
                results.Add(Path.Combine(local, @"NVIDIA\GLCache"));
                results.Add(Path.Combine(local, @"AMD\DxCache"));
                results.Add(Path.Combine(local, @"AMD\GLCache"));
                results.Add(Path.Combine(local, @"Intel\ShaderCache"));
            }
            if (!string.IsNullOrWhiteSpace(localLow)) {
                results.Add(Path.Combine(localLow, @"NVIDIA\PerDriverVersion\DXCache"));
                results.Add(Path.Combine(localLow, @"Intel\ShaderCache"));
            }
            return DeduplicateNormalizedPaths(results.ToArray());
        }

        private static string[] CollectDriverInstallerDirs() {
            string sysDrive = Environment.GetEnvironmentVariable("SystemDrive");
            if (string.IsNullOrWhiteSpace(sysDrive)) sysDrive = "C:";
            string progData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            var results = new List<string>();
            if (!string.IsNullOrWhiteSpace(progData)) {
                results.Add(Path.Combine(progData, @"NVIDIA Corporation\Downloader"));
            }
            results.Add(sysDrive + @"\NVIDIA");
            results.Add(sysDrive + @"\AMD");
            return DeduplicateNormalizedPaths(results.ToArray());
        }

        private static string[] CollectMediaEditorCacheDirs() {
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var results = new List<string>();
            if (!string.IsNullOrWhiteSpace(local)) {
                results.Add(Path.Combine(local, @"CapCut\User Data\Cache"));
            }
            if (!string.IsNullOrWhiteSpace(roaming)) {
                results.Add(Path.Combine(roaming, @"Adobe\Common\Media Cache"));
                results.Add(Path.Combine(roaming, @"Adobe\Common\Media Cache Files"));
                results.Add(Path.Combine(roaming, @"Adobe\Common\Peak Files"));
            }
            return DeduplicateNormalizedPaths(results.ToArray());
        }

        public static string[] GetRunningCacheLockingAppNames() {
            var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) {
                { "chrome", "Chrome" },
                { "msedge", "Edge" },
                { "brave", "Brave" },
                { "opera", "Opera" },
                { "firefox", "Firefox" },
                { "zen", "Zen" },
                { "vivaldi", "Vivaldi" },
                { "browser", "C\u1ED1c C\u1ED1c" },
                { "discord", "Discord" },
                { "telegram", "Telegram" },
                { "zalo", "Zalo" },
                { "capcut", "CapCut" }
            };
            var found = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var list = new List<string>();
            try {
                Process[] procs = Process.GetProcesses();
                for (int i = 0; i < procs.Length; i++) {
                    try {
                        string label;
                        if (map.TryGetValue(procs[i].ProcessName, out label) && found.Add(label)) {
                            list.Add(label);
                        }
                    } catch {}
                    finally { try { procs[i].Dispose(); } catch {} }
                }
            } catch {}
            list.Sort(StringComparer.OrdinalIgnoreCase);
            return list.ToArray();
        }

        private static string[] CollectDevCacheDirs() {
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string userProf = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string tempDir = Path.GetTempPath();
            var results = new List<string>();
            if (!string.IsNullOrWhiteSpace(local)) {
                results.Add(Path.Combine(local, "npm-cache"));
                results.Add(Path.Combine(local, @"pip\Cache"));
                results.Add(Path.Combine(local, @"uv\cache"));
                results.Add(Path.Combine(local, @"Yarn\Cache"));
                results.Add(Path.Combine(local, @"pnpm\cache"));
                results.Add(Path.Combine(local, @"NuGet\v3-cache"));
            }
            if (!string.IsNullOrWhiteSpace(userProf)) {
                results.Add(Path.Combine(userProf, @".gradle\caches"));
                results.Add(Path.Combine(userProf, @".nuget\packages"));
            }
            if (!string.IsNullOrWhiteSpace(tempDir)) {
                results.Add(Path.Combine(tempDir, "WinGet"));
            }
            return DeduplicateNormalizedPaths(results.ToArray());
        }

        // Returns: true if dirPath (and everything inside it) is an eligible empty subtree.
        // nestedEmptyCount counts total empty directories in this subtree (including self).
        public static bool InspectEmptyDirectorySubtree(string dirPath, DateTime cutoffUtc, bool enforceGracePeriod, bool enforceAclSidCheck, int depth, CancellationToken ct, List<ResourceDetailItem> outItems, out int nestedEmptyCount) {
            nestedEmptyCount = 0;
            if (ct.IsCancellationRequested || depth > MAX_EMPTY_SCAN_DEPTH) return false;

            string norm = NormalizeCleanPath(dirPath);
            if (string.IsNullOrWhiteSpace(norm) || norm.Length <= 3) return false;

            uint attr;
            if (!DirExistsWin32(norm, out attr)) return false;
            if ((attr & (FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM | CLOUD_OR_REPARSE_MASK)) != 0) return false;

            string leaf = Path.GetFileName(norm) ?? "";
            if (depth > 0 && !IsPathSafeForEmptyFolderScan(norm, leaf)) return false;

            string spec = ToExtendedPath(norm) + @"\*";
            WIN32_FIND_DATAW fd;
            IntPtr h = FindFirstFileExW(spec, FINDEX_INFO_BASIC, out fd, FINDEX_SEARCH_NAME_MATCH, IntPtr.Zero, FIND_FIRST_EX_LARGE_FETCH);
            if (h == IntPtr.Zero || h == new IntPtr(-1)) return false;

            var childDirs = new List<string>();
            bool hasAnyFileOrBlocked = false;
            try {
                do {
                    if (ct.IsCancellationRequested) return false;
                    string name = fd.cFileName;
                    if (string.IsNullOrEmpty(name) || name == "." || name == "..") continue;

                    if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
                        // Strict 0-entry definition: ANY file (including hidden/system desktop.ini, .gitkeep, etc.) means NOT empty!
                        hasAnyFileOrBlocked = true;
                        continue;
                    }
                    if ((fd.dwFileAttributes & (FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM | CLOUD_OR_REPARSE_MASK)) != 0) {
                        hasAnyFileOrBlocked = true;
                        continue;
                    }
                    childDirs.Add(norm + @"\" + name);
                } while (FindNextFileW(h, out fd));
            } finally {
                FindClose(h);
            }

            if (hasAnyFileOrBlocked) {
                // Still recurse into safe child directories to find isolated empty subtrees inside non-empty parents
                for (int i = 0; i < childDirs.Count; i++) {
                    if (ct.IsCancellationRequested || outItems.Count >= MAX_EMPTY_DETAIL_ITEMS) break;
                    int subCnt;
                    if (InspectEmptyDirectorySubtree(childDirs[i], cutoffUtc, enforceGracePeriod, enforceAclSidCheck, depth + 1, ct, outItems, out subCnt)) {
                        if (outItems.Count < MAX_EMPTY_DETAIL_ITEMS) {
                            outItems.Add(BuildEmptyDetailItem(childDirs[i], subCnt));
                        }
                    }
                }
                return false;
            }

            var emptyChildren = new List<ResourceDetailItem>();
            int totalChildEmpty = 0;
            bool allChildrenEmpty = true;

            for (int i = 0; i < childDirs.Count; i++) {
                if (ct.IsCancellationRequested) return false;
                int subCnt;
                bool childIsEmpty = InspectEmptyDirectorySubtree(childDirs[i], cutoffUtc, enforceGracePeriod, enforceAclSidCheck, depth + 1, ct, outItems, out subCnt);
                if (childIsEmpty) {
                    totalChildEmpty += subCnt;
                    emptyChildren.Add(BuildEmptyDetailItem(childDirs[i], subCnt));
                } else {
                    allChildrenEmpty = false;
                }
            }

            if (!allChildrenEmpty || depth == 0) {
                for (int i = 0; i < emptyChildren.Count; i++) {
                    if (outItems.Count < MAX_EMPTY_DETAIL_ITEMS) outItems.Add(emptyChildren[i]);
                }
                return false;
            }

            // Self is strictly 0-entry (or all children are empty). Now run lazy Shield checks:
            // Layer 5: Dual 24h Grace Period (CreationTimeUtc AND LastWriteTimeUtc)
            if (enforceGracePeriod) {
                try {
                    var di = new DirectoryInfo(norm);
                    if (di.CreationTimeUtc > cutoffUtc || di.LastWriteTimeUtc > cutoffUtc) {
                        for (int i = 0; i < emptyChildren.Count; i++) {
                            if (outItems.Count < MAX_EMPTY_DETAIL_ITEMS) outItems.Add(emptyChildren[i]);
                        }
                        return false;
                    }
                } catch {
                    return false;
                }
            }

            // Layer 3: Lazy SID-only ACL Owner check (SYSTEM / TrustedInstaller)
            if (enforceAclSidCheck && IsProtectedSystemOwnerBySid(norm)) {
                return false;
            }

            nestedEmptyCount = 1 + totalChildEmpty;
            return true;
        }

        private static ResourceDetailItem BuildEmptyDetailItem(string path, int nestedCount) {
            string note = nestedCount > 1
                ? string.Format("{0} th\u01B0 m\u1EE5c r\u1ED7ng l\u1ED3ng nhau", nestedCount)
                : "Th\u01B0 m\u1EE5c r\u1ED7ng (0 m\u1EE5c)";
            return new ResourceDetailItem {
                Path = path,
                DisplayPath = path,
                SizeBytes = 0,
                NestedCount = nestedCount,
                IsDirectory = true,
                IsOneDrive = IsPathInsideOneDrive(path),
                Selected = false,
                Kind = "EmptyTree",
                Note = note
            };
        }

        public static bool IsDisposableZeroByteFileName(string fileName) {
            if (string.IsNullOrWhiteSpace(fileName)) return false;
            string ext = Path.GetExtension(fileName);
            if (string.IsNullOrEmpty(ext)) return false;
            return DisposableZeroByteExts.Contains(ext);
        }

        private static void ScanZeroByteAndLargeFiles(string rootDir, bool scanZeroByte, bool scanLarge, DateTime zeroCutoffUtc, int depth, CancellationToken ct, List<ResourceDetailItem> zeroOut, List<ResourceDetailItem> largeOut) {
            if (ct.IsCancellationRequested || depth > 8) return;
            uint rAttr;
            if (!DirExistsWin32(rootDir, out rAttr)) return;
            if ((rAttr & CLOUD_OR_REPARSE_MASK) != 0) return;

            string norm = NormalizeCleanPath(rootDir);
            if (depth > 0 && IsHardProtectedPath(norm)) return;

            string spec = ToExtendedPath(norm) + @"\*";
            WIN32_FIND_DATAW fd;
            IntPtr h = FindFirstFileExW(spec, FINDEX_INFO_BASIC, out fd, FINDEX_SEARCH_NAME_MATCH, IntPtr.Zero, FIND_FIRST_EX_LARGE_FETCH);
            if (h == IntPtr.Zero || h == new IntPtr(-1)) return;
            try {
                do {
                    if (ct.IsCancellationRequested) break;
                    string name = fd.cFileName;
                    if (string.IsNullOrEmpty(name) || name == "." || name == "..") continue;
                    if ((fd.dwFileAttributes & CLOUD_OR_REPARSE_MASK) != 0) continue;

                    string full = norm + @"\" + name;
                    if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
                        if ((fd.dwFileAttributes & (FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM)) != 0) continue;
                        if (HardBlockedDirNames.Contains(name)) continue;
                        ScanZeroByteAndLargeFiles(full, scanZeroByte, scanLarge, zeroCutoffUtc, depth + 1, ct, zeroOut, largeOut);
                    } else {
                        long sz = (((long)fd.nFileSizeHigh) << 32) | fd.nFileSizeLow;
                        if (scanZeroByte && sz == 0 && zeroOut.Count < MAX_ZERO_DETAIL_ITEMS) {
                            if (IsDisposableZeroByteFileName(name)) {
                                DateTime lw = fd.ftLastWriteTime.ToUtcDateTime();
                                if (lw == DateTime.MinValue || lw <= zeroCutoffUtc) {
                                    zeroOut.Add(new ResourceDetailItem {
                                        Path = full,
                                        DisplayPath = full,
                                        SizeBytes = 0,
                                        NestedCount = 1,
                                        IsDirectory = false,
                                        IsOneDrive = IsPathInsideOneDrive(full),
                                        Selected = false,
                                        Kind = "ZeroByte",
                                        Note = "0 byte (t\u1EA3i h\u1ECFng / t\u1EA1m > 24h)"
                                    });
                                }
                            }
                        }
                        if (scanLarge && sz >= LARGE_FILE_THRESHOLD_BYTES && largeOut.Count < MAX_LARGE_DETAIL_ITEMS) {
                            bool inOd = IsPathInsideOneDrive(full);
                            largeOut.Add(new ResourceDetailItem {
                                Path = full,
                                DisplayPath = full,
                                SizeBytes = sz,
                                NestedCount = 1,
                                IsDirectory = false,
                                IsOneDrive = inOd,
                                Selected = false,
                                Kind = "LargeFile",
                                Note = inOd ? "OneDrive (Cloud) \u2022 X\u00F3a s\u1EBD \u0111\u1ED3ng b\u1ED9 l\u00EAn m\u00E2y" : FormatBytes(sz)
                            });
                        }
                    }
                } while (FindNextFileW(h, out fd));
            } finally {
                FindClose(h);
            }
        }

        public static ResourceScanReport ScanAllTiers(string[] extraEmptyScanRoots, CancellationToken ct) {
            var sw = Stopwatch.StartNew();
            var list = new List<ResourceCleanCategory>();
            string localApp = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string winDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            string progData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            string downloadsDir = GetKnownFolderPathSafe("Downloads");
            string desktopDir = GetKnownFolderPathSafe("Desktop");

            // === TIER 1: Windows Temp & System Junk ===
            var catUserTemp = new ResourceCleanCategory {
                Id = "t1_user_temp", Tier = 1, FilterGroup = "Safe", RiskLevel = "Safe",
                Title = "T\u1EC7p t\u1EA1m ng\u01B0\u1EDDi d\u00F9ng",
                Description = "T\u1EC7p t\u1EA1m \u1EE9ng d\u1EE5ng v\u00E0 b\u1ED9 c\u00E0i trong th\u01B0 m\u1EE5c Temp.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catUserTemp, new[] { Path.GetTempPath(), Path.Combine(localApp, "Temp") }, null, false, ct);
            list.Add(catUserTemp);

            var catWinTemp = new ResourceCleanCategory {
                Id = "t1_win_temp", Tier = 1, FilterGroup = "Safe", RiskLevel = "Safe",
                Title = "T\u1EC7p t\u1EA1m Windows",
                Description = "T\u1EC7p t\u1EA1m h\u1EC7 th\u1ED1ng trong C:\\Windows\\Temp.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catWinTemp, new[] { Path.Combine(winDir, "Temp") }, null, false, ct);
            list.Add(catWinTemp);

            var catWer = new ResourceCleanCategory {
                Id = "t1_wer_dumps", Tier = 1, FilterGroup = "Safe", RiskLevel = "Safe",
                Title = "B\u00E1o c\u00E1o l\u1ED7i & Crash Dumps",
                Description = "Nh\u1EADt k\u00FD l\u1ED7i h\u1EC7 th\u1ED1ng, CrashDumps v\u00E0 Minidump c\u0169.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catWer, new[] {
                Path.Combine(localApp, @"Microsoft\Windows\WER"),
                Path.Combine(progData, @"Microsoft\Windows\WER"),
                Path.Combine(localApp, "CrashDumps"),
                Path.Combine(winDir, "Minidump")
            }, null, false, ct);
            list.Add(catWer);

            var catThumb = new ResourceCleanCategory {
                Id = "t1_thumbcache", Tier = 1, FilterGroup = "Safe", RiskLevel = "Safe",
                Title = "B\u1ED9 nh\u1EDB \u0111\u1EC7m \u1EA3nh thu nh\u1ECF",
                Description = "B\u1ED9 nh\u1EDB \u0111\u1EC7m thumbnail c\u1EE7a Windows Explorer.",
                CleanMode = "FilePattern", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catThumb, new[] { Path.Combine(localApp, @"Microsoft\Windows\Explorer") }, new[] { "thumbcache_*.db" }, true, ct);
            list.Add(catThumb);

            bool wuRebootPending = IsWindowsUpdateRebootPending();
            var catWuDl = new ResourceCleanCategory {
                Id = "t1_wu_download", Tier = 1, FilterGroup = "Safe", RiskLevel = "Safe",
                Title = "B\u1ED9 nh\u1EDB \u0111\u1EC7m Windows Update",
                Description = "T\u1EC7p c\u00E0i \u0111\u1EB7t c\u0169 c\u1EE7a Windows Update.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false,
                DefaultSelected = false, Selected = false,
                SkippedBecauseRebootPending = wuRebootPending
            };
            if (wuRebootPending) {
                catWuDl.StatusNote = "\u0110ang ch\u1EDD kh\u1EDFi \u0111\u1ED9ng l\u1EA1i \u0111\u1EC3 ho\u00E0n t\u1EA5t c\u1EADp nh\u1EADt \u2014 t\u1EA1m b\u1ECF qua.";
                catWuDl.DetailItems = new List<ResourceDetailItem>();
                catWuDl.RootPaths = new string[0];
            } else {
                PopulateDirectoryCategory(catWuDl, new[] { Path.Combine(winDir, @"SoftwareDistribution\Download") }, null, false, ct);
            }
            list.Add(catWuDl);

            var catDo = new ResourceCleanCategory {
                Id = "t1_delivery_opt", Tier = 1, FilterGroup = "Safe", RiskLevel = "Safe",
                Title = "B\u1ED9 nh\u1EDB \u0111\u1EC7m Delivery Optimization",
                Description = "T\u1EC7p ph\u00E2n ph\u1ED1i c\u1EADp nh\u1EADt Windows v\u00E0 Microsoft Store.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false,
                IsDeliveryOptimization = true
            };
            PopulateDirectoryCategory(catDo, new[] { Path.Combine(winDir, @"ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache") }, null, false, ct);
            list.Add(catDo);

            var catDrvInst = new ResourceCleanCategory {
                Id = "t1_driver_installers", Tier = 1, FilterGroup = "Safe", RiskLevel = "Safe",
                Title = "B\u1ED9 c\u00E0i Driver c\u0169 (NVIDIA / AMD)",
                Description = "T\u1EC7p gi\u1EA3i n\u00E9n c\u00E0i \u0111\u1EB7t c\u0169 trong NVIDIA Downloader, C:\\NVIDIA v\u00E0 C:\\AMD (kh\u00F4ng \u1EA3nh h\u01B0\u1EDFng driver \u0111ang ch\u1EA1y).",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catDrvInst, CollectDriverInstallerDirs(), null, false, ct);
            list.Add(catDrvInst);

            var catGpu = new ResourceCleanCategory {
                Id = "t1_gpu_shader", Tier = 1, FilterGroup = "Safe", RiskLevel = "Caution",
                Title = "B\u1ED9 nh\u1EDB \u0111\u1EC7m Shader \u0111\u1ED3 h\u1ECDa",
                Description = "DirectX, NVIDIA, AMD v\u00E0 Intel Shader Cache (t\u1EF1 t\u1EA1o l\u1EA1i khi m\u1EDF game).",
                WarningNote = "Game c\u00F3 th\u1EC3 t\u1EA1o l\u1EA1i shader \u1EDF l\u1EA7n m\u1EDF \u0111\u1EA7u ti\u00EAn.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catGpu, CollectGpuShaderCacheDirs(), null, false, ct);
            list.Add(catGpu);

            var catRb = new ResourceCleanCategory {
                Id = "t1_recycle_bin", Tier = 1, FilterGroup = "Safe", RiskLevel = "Caution",
                Title = "Th\u00F9ng r\u00E1c (T\u1EA5t c\u1EA3 \u1ED5 \u0111\u0129a)",
                Description = "D\u1ECDn s\u1EA1ch to\u00E0n b\u1ED9 t\u1EC7p trong Th\u00F9ng r\u00E1c tr\u00EAn m\u1ECDi \u1ED5 \u0111\u0129a.",
                WarningNote = "X\u00F3a v\u0129nh vi\u1EC5n to\u00E0n b\u1ED9 t\u1EC7p trong Th\u00F9ng r\u00E1c.",
                CleanMode = "RecycleBinAll", SupportsRecycleBin = false, DefaultSelected = false, Selected = false,
                DetailItems = new List<ResourceDetailItem>(), RootPaths = new string[0]
            };
            try {
                SHQUERYRBINFO rbInfo = new SHQUERYRBINFO();
                rbInfo.cbSize = (uint)Marshal.SizeOf(typeof(SHQUERYRBINFO));
                if (SHQueryRecycleBinW(null, ref rbInfo) == 0) {
                    catRb.TotalBytes = Math.Max(0L, rbInfo.i64Size);
                    catRb.ItemCount = (int)Math.Min(int.MaxValue, Math.Max(0L, rbInfo.i64NumItems));
                }
            } catch {}
            list.Add(catRb);

            // === TIER 2: Browser Caches (Cookies / Logins / Bookmarks 100% Untouched) ===
            var catChromium = new ResourceCleanCategory {
                Id = "t2_chromium_cache", Tier = 2, FilterGroup = "Browser", RiskLevel = "Safe",
                Title = "B\u1ED9 nh\u1EDB \u0111\u1EC7m Chrome / Edge / Brave / Arc / C\u1ED1c C\u1ED1c",
                Description = "Ch\u1EC9 d\u1ECDn b\u1ED9 nh\u1EDB \u0111\u1EC7m web \u2014 gi\u1EEF nguy\u00EAn m\u1EADt kh\u1EA9u, cookie v\u00E0 d\u1EA5u trang.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catChromium, CollectChromiumCacheDirs(), null, false, ct);
            list.Add(catChromium);

            var catOpera = new ResourceCleanCategory {
                Id = "t2_opera_cache", Tier = 2, FilterGroup = "Browser", RiskLevel = "Safe",
                Title = "B\u1ED9 nh\u1EDB \u0111\u1EC7m Opera / Opera GX",
                Description = "Ch\u1EC9 d\u1ECDn b\u1ED9 nh\u1EDB \u0111\u1EC7m web \u2014 gi\u1EEF nguy\u00EAn phi\u00EAn \u0111\u0103ng nh\u1EADp.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catOpera, CollectOperaCacheDirs(), null, false, ct);
            list.Add(catOpera);

            var catGecko = new ResourceCleanCategory {
                Id = "t2_gecko_cache", Tier = 2, FilterGroup = "Browser", RiskLevel = "Safe",
                Title = "B\u1ED9 nh\u1EDB \u0111\u1EC7m Firefox / Zen / Floorp",
                Description = "Ch\u1EC9 d\u1ECDn b\u1ED9 nh\u1EDB \u0111\u1EC7m web \u2014 gi\u1EEF nguy\u00EAn h\u1ED3 s\u01A1 v\u00E0 \u0111\u0103ng nh\u1EADp.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catGecko, CollectGeckoCacheDirs(), null, false, ct);
            list.Add(catGecko);

            // === TIER 3: App, Electron, Game Launcher & Dev Caches ===
            var catElectron = new ResourceCleanCategory {
                Id = "t3_electron_chat", Tier = 3, FilterGroup = "AppDev", RiskLevel = "Safe",
                Title = "B\u1ED9 nh\u1EDB \u0111\u1EC7m \u1EE9ng d\u1EE5ng (Discord / VS Code / Zalo / Teams / Telegram)",
                Description = "Ch\u1EC9 d\u1ECDn b\u1ED9 nh\u1EDB \u0111\u1EC7m t\u1EA1m \u2014 gi\u1EEF nguy\u00EAn tin nh\u1EAFn v\u00E0 t\u1EC7p \u0111\u00E3 t\u1EA3i.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catElectron, CollectElectronAndChatCacheDirs(), null, false, ct);
            list.Add(catElectron);

            var catGames = new ResourceCleanCategory {
                Id = "t3_game_launchers", Tier = 3, FilterGroup = "AppDev", RiskLevel = "Safe",
                Title = "B\u1ED9 nh\u1EDB \u0111\u1EC7m Game Launcher (Steam / Epic / Riot / Battle.net)",
                Description = "Ch\u1EC9 d\u1ECDn b\u1ED9 nh\u1EDB \u0111\u1EC7m tr\u00ECnh kh\u1EDFi ch\u1EA1y \u2014 kh\u00F4ng \u1EA3nh h\u01B0\u1EDFng d\u1EEF li\u1EC7u game.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catGames, CollectGameLauncherCacheDirs(), null, false, ct);
            list.Add(catGames);

            var catMediaEd = new ResourceCleanCategory {
                Id = "t3_media_editors", Tier = 3, FilterGroup = "AppDev", RiskLevel = "Safe",
                Title = "B\u1ED9 nh\u1EDB \u0111\u1EC7m d\u1EF1ng phim (CapCut / Adobe Media Cache)",
                Description = "Ch\u1EC9 d\u1ECDn b\u1ED9 nh\u1EDB \u0111\u1EC7m t\u1EA1m \u2014 kh\u00F4ng x\u00F3a d\u1EF1 \u00E1n hay video g\u1ED1c.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catMediaEd, CollectMediaEditorCacheDirs(), null, false, ct);
            list.Add(catMediaEd);

            var catSpotOff = new ResourceCleanCategory {
                Id = "t3_spotify_offline", Tier = 3, FilterGroup = "AppDev", RiskLevel = "Caution",
                Title = "D\u1EEF li\u1EC7u ngo\u1EA1i tuy\u1EBFn Spotify",
                Description = "Nh\u1EA1c v\u00E0 podcast \u0111\u00E3 t\u1EA3i xu\u1ED1ng \u0111\u1EC3 nghe ngo\u1EA1i tuy\u1EBFn.",
                WarningNote = "Nh\u1EA1c v\u00E0 podcast t\u1EA3i ngo\u1EA1i tuy\u1EBFn s\u1EBD c\u1EA7n t\u1EA3i l\u1EA1i.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catSpotOff, new[] { Path.Combine(localApp, @"Spotify\Storage") }, null, false, ct);
            list.Add(catSpotOff);

            var catDev = new ResourceCleanCategory {
                Id = "t3_dev_caches", Tier = 3, FilterGroup = "AppDev", RiskLevel = "Advanced",
                Title = "B\u1ED9 nh\u1EDB \u0111\u1EC7m c\u00F4ng c\u1EE5 l\u1EADp tr\u00ECnh (npm / pip / uv / NuGet / Gradle)",
                Description = "B\u1ED9 nh\u1EDB \u0111\u1EC7m g\u00F3i th\u01B0 vi\u1EC7n (t\u1EF1 t\u1EA3i l\u1EA1i khi c\u00E0i \u0111\u1EB7t m\u1EDBi).",
                WarningNote = "C\u00E1c g\u00F3i th\u01B0 vi\u1EC7n s\u1EBD t\u1EA3i l\u1EA1i t\u1EEB m\u1EA1ng khi c\u1EA7n.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catDev, CollectDevCacheDirs(), null, false, ct);
            list.Add(catDev);

            // === TIER 4: Deep Empty Folders & 0-Byte Disposable Junk (Advanced, Unchecked, Recycle Bin default) ===
            var emptyRoots = new List<string>();
            if (!string.IsNullOrWhiteSpace(downloadsDir) && !IsPathInsideOneDrive(downloadsDir)) {
                emptyRoots.Add(downloadsDir);
            }
            if (extraEmptyScanRoots != null) {
                for (int i = 0; i < extraEmptyScanRoots.Length; i++) {
                    if (!string.IsNullOrWhiteSpace(extraEmptyScanRoots[i])) emptyRoots.Add(extraEmptyScanRoots[i]);
                }
            }
            string[] dedupEmptyRoots = DeduplicateNormalizedPaths(emptyRoots.ToArray());

            var emptyItems = new List<ResourceDetailItem>();
            DateTime graceCutoff = DateTime.UtcNow.AddHours(-24);
            for (int i = 0; i < dedupEmptyRoots.Length; i++) {
                if (ct.IsCancellationRequested) break;
                int dummyCnt;
                InspectEmptyDirectorySubtree(dedupEmptyRoots[i], graceCutoff, true, true, 0, ct, emptyItems, out dummyCnt);
            }
            int totalEmptyCount = 0;
            for (int i = 0; i < emptyItems.Count; i++) totalEmptyCount += Math.Max(1, emptyItems[i].NestedCount);

            var catEmpty = new ResourceCleanCategory {
                Id = "t4_empty_folders", Tier = 4, FilterGroup = "Empty", RiskLevel = "Advanced",
                Title = "Th\u01B0 m\u1EE5c r\u1ED7ng",
                Description = "Th\u01B0 m\u1EE5c tr\u1ED1ng kh\u00F4ng s\u1EED d\u1EE5ng trong Downloads v\u00E0 th\u01B0 m\u1EE5c b\u1EA1n ch\u1ECDn th\u00EAm.",
                WarningNote = "M\u1EB7c \u0111\u1ECBnh \u0111\u01B0a v\u00E0o Th\u00F9ng r\u00E1c.",
                CleanMode = "ItemsList", SupportsRecycleBin = true, DefaultSelected = false, Selected = false,
                TotalBytes = 0, ItemCount = emptyItems.Count, FolderCount = totalEmptyCount,
                RootPaths = dedupEmptyRoots, DetailItems = emptyItems
            };
            list.Add(catEmpty);

            var zeroItems = new List<ResourceDetailItem>();
            var largeItems = new List<ResourceDetailItem>();
            var dlScanRoots = new List<string>();
            if (!string.IsNullOrWhiteSpace(downloadsDir)) dlScanRoots.Add(downloadsDir);
            if (!string.IsNullOrWhiteSpace(desktopDir)) dlScanRoots.Add(desktopDir);
            if (extraEmptyScanRoots != null) {
                for (int i = 0; i < extraEmptyScanRoots.Length; i++) {
                    if (!string.IsNullOrWhiteSpace(extraEmptyScanRoots[i])) dlScanRoots.Add(extraEmptyScanRoots[i]);
                }
            }
            string[] dedupUserRoots = DeduplicateNormalizedPaths(dlScanRoots.ToArray());
            for (int i = 0; i < dedupUserRoots.Length; i++) {
                if (ct.IsCancellationRequested) break;
                bool isLargeTarget = dedupUserRoots[i].Equals(downloadsDir, StringComparison.OrdinalIgnoreCase) ||
                                     dedupUserRoots[i].Equals(desktopDir, StringComparison.OrdinalIgnoreCase);
                ScanZeroByteAndLargeFiles(dedupUserRoots[i], true, isLargeTarget, graceCutoff, 0, ct, zeroItems, largeItems);
            }

            var catZero = new ResourceCleanCategory {
                Id = "t4_zero_byte_junk", Tier = 4, FilterGroup = "Empty", RiskLevel = "Advanced",
                Title = "T\u1EC7p t\u1EA1m & t\u1EA3i l\u1ED7i (0 byte)",
                Description = "T\u1EC7p t\u1EA1m v\u00E0 t\u1EC7p t\u1EA3i d\u1EDF (.tmp, .crdownload, .part) c\u0169 h\u01A1n 24 gi\u1EDD.",
                CleanMode = "ItemsList", SupportsRecycleBin = true, DefaultSelected = false, Selected = false,
                TotalBytes = 0, ItemCount = zeroItems.Count, FolderCount = 0,
                RootPaths = dedupUserRoots, DetailItems = zeroItems
            };
            list.Add(catZero);

            // === TIER 5: Advanced System & Large File Radar (Unchecked, Recycle Bin default) ===
            var catPrefetch = new ResourceCleanCategory {
                Id = "t5_prefetch", Tier = 5, FilterGroup = "Advanced", RiskLevel = "Advanced",
                Title = "B\u1ED9 nh\u1EDB \u0111\u1EC7m Windows Prefetch",
                Description = "D\u1EEF li\u1EC7u t\u0103ng t\u1ED1c kh\u1EDFi ch\u1EA1y \u1EE9ng d\u1EE5ng (t\u1EF1 t\u1EA1o l\u1EA1i khi s\u1EED d\u1EE5ng).",
                WarningNote = "Windows s\u1EBD t\u1EF1 t\u1EA1o l\u1EA1i Prefetch trong qu\u00E1 tr\u00ECnh s\u1EED d\u1EE5ng.",
                CleanMode = "ContentsOnly", SupportsRecycleBin = false, DefaultSelected = false, Selected = false
            };
            PopulateDirectoryCategory(catPrefetch, new[] { Path.Combine(winDir, "Prefetch") }, new[] { "*.pf" }, true, ct);
            list.Add(catPrefetch);

            largeItems.Sort(delegate(ResourceDetailItem a, ResourceDetailItem b) {
                return b.SizeBytes.CompareTo(a.SizeBytes);
            });
            long largeTotal = 0;
            for (int i = 0; i < largeItems.Count; i++) largeTotal += largeItems[i].SizeBytes;
            var catLarge = new ResourceCleanCategory {
                Id = "t5_large_files", Tier = 5, FilterGroup = "Advanced", RiskLevel = "Advanced",
                Title = "T\u1EC7p dung l\u01B0\u1EE3ng l\u1EDBn (> 500 MB)",
                Description = "C\u00E1c t\u1EC7p l\u1EDBn trong Downloads v\u00E0 Desktop \u2014 ki\u1EC3m tra Chi ti\u1EBFt tr\u01B0\u1EDBc khi d\u1ECDn.",
                WarningNote = "Ki\u1EC3m tra danh s\u00E1ch Chi ti\u1EBFt tr\u01B0\u1EDBc khi x\u00F3a.",
                CleanMode = "ItemsList", SupportsRecycleBin = true, DefaultSelected = false, Selected = false,
                TotalBytes = largeTotal, ItemCount = largeItems.Count, FolderCount = 0,
                RootPaths = DeduplicateNormalizedPaths(new[] { downloadsDir, desktopDir }),
                DetailItems = largeItems
            };
            list.Add(catLarge);

            long sumBytes = 0;
            int sumFiles = 0;
            for (int i = 0; i < list.Count; i++) {
                sumBytes += list[i].TotalBytes;
                if (list[i].Id != "t4_empty_folders") sumFiles += list[i].ItemCount;
            }

            // Smart sort: heaviest items first (by TotalBytes desc), empty folders next, greyed 0 B clean items at the very bottom
            list.Sort(delegate(ResourceCleanCategory a, ResourceCleanCategory b) {
                bool aHas = (a.Id == "t4_empty_folders") ? (a.FolderCount > 0 || a.ItemCount > 0) : (a.TotalBytes > 0 || a.ItemCount > 0);
                bool bHas = (b.Id == "t4_empty_folders") ? (b.FolderCount > 0 || b.ItemCount > 0) : (b.TotalBytes > 0 || b.ItemCount > 0);
                if (aHas != bHas) return aHas ? -1 : 1;
                int cmpSz = b.TotalBytes.CompareTo(a.TotalBytes);
                if (cmpSz != 0) return cmpSz;
                int cmpCnt = (b.FolderCount + b.ItemCount).CompareTo(a.FolderCount + a.ItemCount);
                if (cmpCnt != 0) return cmpCnt;
                int aRisk = a.RiskLevel == "Safe" ? 0 : (a.RiskLevel == "Caution" ? 1 : 2);
                int bRisk = b.RiskLevel == "Safe" ? 0 : (b.RiskLevel == "Caution" ? 1 : 2);
                if (aRisk != bRisk) return aRisk.CompareTo(bRisk);
                return a.Tier.CompareTo(b.Tier);
            });

            sw.Stop();
            return new ResourceScanReport {
                DiskInfo = GetSystemDiskInfo(),
                Categories = list.ToArray(),
                TotalBytes = sumBytes,
                TotalFiles = sumFiles,
                TotalEmptyFolders = totalEmptyCount,
                ScanElapsedMs = sw.ElapsedMilliseconds,
                WasCancelled = ct.IsCancellationRequested
            };
        }

        public static Task<ResourceScanReport> ScanAllTiersAsync(string[] extraEmptyScanRoots, CancellationToken ct) {
            return Task.Run(delegate {
                return ScanAllTiers(extraEmptyScanRoots, ct);
            });
        }

        // Win32 long-path safe delete (works on .NET 4.8 / PS 5.1 for > 260 char paths)
        public static bool DeleteFileWin32(string path, out bool skippedCloud) {
            skippedCloud = false;
            string ext = ToExtendedPath(path);
            uint attr = GetFileAttributesW(ext);
            if (attr == INVALID_FILE_ATTRIBUTES) return false;
            if ((attr & CLOUD_OR_REPARSE_MASK) != 0) {
                skippedCloud = true;
                return false;
            }
            if ((attr & FILE_ATTRIBUTE_READONLY) != 0) {
                SetFileAttributesW(ext, FILE_ATTRIBUTE_NORMAL);
            }
            return DeleteFileW(ext);
        }

        public static bool RemoveDirectoryWin32(string path, out bool skippedCloud) {
            skippedCloud = false;
            string ext = ToExtendedPath(path);
            uint attr = GetFileAttributesW(ext);
            if (attr == INVALID_FILE_ATTRIBUTES) return false;
            if ((attr & CLOUD_OR_REPARSE_MASK) != 0) {
                skippedCloud = true;
                return false;
            }
            if ((attr & FILE_ATTRIBUTE_READONLY) != 0) {
                SetFileAttributesW(ext, attr & ~FILE_ATTRIBUTE_READONLY);
            }
            return RemoveDirectoryW(ext);
        }

        private static void DeleteDirectoryContentsWin32(string rootDir, string[] patterns, bool topLevelOnly, bool deleteSelf, CancellationToken ct, ref long freedBytes, ref int delFiles, ref int delFolders, ref int skippedLocked, ref int skippedCloud, int depth) {
            if (ct.IsCancellationRequested || depth > 24) return;
            string norm = NormalizeCleanPath(rootDir);
            if (depth > 0 && IsHardProtectedPath(norm)) return;

            uint rAttr;
            if (!DirExistsWin32(norm, out rAttr)) return;
            if ((rAttr & CLOUD_OR_REPARSE_MASK) != 0) { skippedCloud++; return; }

            string spec = ToExtendedPath(norm) + @"\*";
            WIN32_FIND_DATAW fd;
            IntPtr h = FindFirstFileExW(spec, FINDEX_INFO_BASIC, out fd, FINDEX_SEARCH_NAME_MATCH, IntPtr.Zero, FIND_FIRST_EX_LARGE_FETCH);
            if (h == IntPtr.Zero || h == new IntPtr(-1)) {
                skippedLocked++;
                return;
            }
            var subDirs = new List<string>();
            var fileEntries = new List<KeyValuePair<string, long>>();
            try {
                do {
                    if (ct.IsCancellationRequested) break;
                    string name = fd.cFileName;
                    if (string.IsNullOrEmpty(name) || name == "." || name == "..") continue;
                    if ((fd.dwFileAttributes & CLOUD_OR_REPARSE_MASK) != 0) { skippedCloud++; continue; }

                    string full = norm + @"\" + name;
                    if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
                        if (topLevelOnly) continue;
                        if (IsHardProtectedPath(full)) continue;
                        subDirs.Add(full);
                    } else {
                        if (NeverTouchBrowserNames.Contains(name)) continue;
                        if (patterns != null && patterns.Length > 0 && !MatchesAnyWildcard(name, patterns)) continue;
                        long sz = (((long)fd.nFileSizeHigh) << 32) | fd.nFileSizeLow;
                        fileEntries.Add(new KeyValuePair<string, long>(full, sz));
                    }
                } while (FindNextFileW(h, out fd));
            } finally {
                FindClose(h);
            }

            for (int i = 0; i < fileEntries.Count; i++) {
                if (ct.IsCancellationRequested) break;
                bool sc;
                if (DeleteFileWin32(fileEntries[i].Key, out sc)) {
                    freedBytes += fileEntries[i].Value;
                    delFiles++;
                } else if (sc) {
                    skippedCloud++;
                } else {
                    skippedLocked++;
                }
            }

            for (int i = 0; i < subDirs.Count; i++) {
                if (ct.IsCancellationRequested) break;
                DeleteDirectoryContentsWin32(subDirs[i], patterns, false, true, ct, ref freedBytes, ref delFiles, ref delFolders, ref skippedLocked, ref skippedCloud, depth + 1);
            }

            if (deleteSelf && !ct.IsCancellationRequested) {
                bool sc;
                if (RemoveDirectoryWin32(norm, out sc)) {
                    delFolders++;
                } else if (sc) {
                    skippedCloud++;
                }
            }
        }

        // Strict Recycle Bin via COM IFileOperation + FOFX_RECYCLEONDELETE (never silently permanently deletes!)
        public static bool TryRecycleItemStrict(string rawPath, out string failureReason) {
            failureReason = "";
            if (string.IsNullOrWhiteSpace(rawPath)) {
                failureReason = "EmptyPath";
                return false;
            }
            string clean = StripExtendedPath(rawPath.Trim());
            if (clean.StartsWith(@"\\", StringComparison.Ordinal)) {
                failureReason = "UncNotSupportedByRecycleBin";
                return false;
            }
            if (clean.Length >= 260) {
                failureReason = "PathTooLongForRecycleBin";
                return false;
            }
            uint attr = GetFileAttributesW(ToExtendedPath(clean));
            if (attr == INVALID_FILE_ATTRIBUTES) {
                failureReason = "NotFound";
                return false;
            }
            if ((attr & CLOUD_OR_REPARSE_MASK) != 0) {
                failureReason = "CloudOrReparseSkipped";
                return false;
            }

            bool ok = false;
            string err = "";
            Exception threadEx = null;

            Action runCom = delegate {
                IFileOperationRC fileOp = null;
                IShellItemRC shellItem = null;
                try {
                    Type opType = Type.GetTypeFromCLSID(CLSID_FileOperation, true);
                    fileOp = (IFileOperationRC)Activator.CreateInstance(opType);
                    int hrFlags = fileOp.SetOperationFlags(RECYCLE_STRICT_FLAGS);
                    if (hrFlags < 0) { err = "SetFlagsHR=" + hrFlags.ToString("X"); return; }

                    Guid iidItem = IID_IShellItem;
                    int hrItem = SHCreateItemFromParsingName(clean, IntPtr.Zero, ref iidItem, out shellItem);
                    if (hrItem < 0 || shellItem == null) { err = "CreateItemHR=" + hrItem.ToString("X"); return; }

                    int hrDel = fileOp.DeleteItem(shellItem, IntPtr.Zero);
                    if (hrDel < 0) { err = "DeleteItemHR=" + hrDel.ToString("X"); return; }

                    int hrPerf = fileOp.PerformOperations();
                    bool aborted = false;
                    try { fileOp.GetAnyOperationsAborted(out aborted); } catch {}
                    if (hrPerf < 0 || aborted) {
                        err = aborted ? "AbortedByShell" : ("PerformHR=" + hrPerf.ToString("X"));
                        return;
                    }
                    uint afterAttr = GetFileAttributesW(ToExtendedPath(clean));
                    ok = (afterAttr == INVALID_FILE_ATTRIBUTES);
                    if (!ok) err = "ItemStillExists";
                } catch (Exception ex) {
                    threadEx = ex;
                } finally {
                    if (shellItem != null) { try { Marshal.ReleaseComObject(shellItem); } catch {} }
                    if (fileOp != null) { try { Marshal.ReleaseComObject(fileOp); } catch {} }
                }
            };

            if (Thread.CurrentThread.GetApartmentState() == ApartmentState.STA) {
                runCom();
            } else {
                var sta = new Thread(new ThreadStart(runCom));
                sta.IsBackground = true;
                sta.SetApartmentState(ApartmentState.STA);
                sta.Start();
                sta.Join();
            }

            if (threadEx != null) {
                failureReason = threadEx.Message;
                return false;
            }
            failureReason = err;
            return ok;
        }

        private static void DeleteEmptySubtreeBottomUp(string rootDir, CancellationToken ct, ref int delFolders, ref int skippedLocked, ref int skippedCloud, int depth) {
            if (ct.IsCancellationRequested || depth > MAX_EMPTY_SCAN_DEPTH + 2) return;
            string norm = NormalizeCleanPath(rootDir);
            uint attr;
            if (!DirExistsWin32(norm, out attr)) return;
            if ((attr & CLOUD_OR_REPARSE_MASK) != 0) { skippedCloud++; return; }

            string spec = ToExtendedPath(norm) + @"\*";
            WIN32_FIND_DATAW fd;
            IntPtr h = FindFirstFileExW(spec, FINDEX_INFO_BASIC, out fd, FINDEX_SEARCH_NAME_MATCH, IntPtr.Zero, FIND_FIRST_EX_LARGE_FETCH);
            if (h != IntPtr.Zero && h != new IntPtr(-1)) {
                var children = new List<string>();
                bool foundFile = false;
                try {
                    do {
                        string name = fd.cFileName;
                        if (string.IsNullOrEmpty(name) || name == "." || name == "..") continue;
                        if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
                            foundFile = true;
                            break;
                        }
                        if ((fd.dwFileAttributes & CLOUD_OR_REPARSE_MASK) != 0) {
                            foundFile = true;
                            break;
                        }
                        children.Add(norm + @"\" + name);
                    } while (FindNextFileW(h, out fd));
                } finally {
                    FindClose(h);
                }
                if (foundFile) return;
                for (int i = 0; i < children.Count; i++) {
                    DeleteEmptySubtreeBottomUp(children[i], ct, ref delFolders, ref skippedLocked, ref skippedCloud, depth + 1);
                }
            }
            bool sc;
            if (RemoveDirectoryWin32(norm, out sc)) {
                delFolders++;
            } else if (sc) {
                skippedCloud++;
            } else {
                skippedLocked++;
            }
        }

        public static ResourceCleanReport CleanSelectedCategories(ResourceCleanCategory[] categories, bool useRecycleBinForTier45, CancellationToken ct) {
            var sw = Stopwatch.StartNew();
            var report = new ResourceCleanReport();
            var logs = new List<string>();
            if (categories == null) {
                report.PerCategoryLogs = new string[0];
                return report;
            }

            // STRICT EXECUTION ORDER:
            // Pass 1: Tier 1-3 ALWAYS BEFORE Tier 4-5 (so SHEmptyRecycleBinW never wipes newly recycled Tier 4-5 files!)
            var ordered = new List<ResourceCleanCategory>();
            for (int i = 0; i < categories.Length; i++) {
                if (categories[i] != null && categories[i].Selected && categories[i].Tier <= 3) ordered.Add(categories[i]);
            }
            for (int i = 0; i < categories.Length; i++) {
                if (categories[i] != null && categories[i].Selected && categories[i].Tier >= 4) ordered.Add(categories[i]);
            }

            long freedTotal = 0;
            int delFilesTotal = 0;
            int delFoldersTotal = 0;
            int recycledTotal = 0;
            int lockedTotal = 0;
            int recycleUnsupTotal = 0;
            int cloudTotal = 0;

            for (int idx = 0; idx < ordered.Count; idx++) {
                if (ct.IsCancellationRequested) break;
                var cat = ordered[idx];
                if (cat.SkippedBecauseRebootPending) {
                    logs.Add("[SKIP] " + cat.Title + " (Windows Update pending reboot)");
                    continue;
                }

                long cf = 0; int cdf = 0; int cdd = 0; int crec = 0; int clk = 0; int crun = 0; int ccld = 0;

                if (cat.CleanMode == "RecycleBinAll") {
                    long beforeSz = cat.TotalBytes;
                    int beforeItems = cat.ItemCount;
                    try {
                        int hr = SHEmptyRecycleBinW(IntPtr.Zero, null, SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND);
                        if (hr == 0) {
                            cf += beforeSz;
                            cdf += beforeItems;
                        }
                    } catch {}
                    logs.Add(string.Format("[OK] {0}: gi\u1EA3i ph\u00F3ng {1}", cat.Title, FormatBytes(cf)));
                } else if (cat.CleanMode == "ContentsOnly" || cat.CleanMode == "FilePattern") {
                    bool topOnly = (cat.CleanMode == "FilePattern");
                    if (cat.IsDeliveryOptimization) report.NeedsDeliveryOptCmdlet = true;
                    if (cat.RootPaths != null) {
                        for (int r = 0; r < cat.RootPaths.Length; r++) {
                            if (ct.IsCancellationRequested) break;
                            DeleteDirectoryContentsWin32(cat.RootPaths[r], cat.FilePatterns, topOnly, false, ct, ref cf, ref cdf, ref cdd, ref clk, ref ccld, 0);
                        }
                    }
                    logs.Add(string.Format("[OK] {0}: {1} ({2} t\u1EC7p, b\u1ECF qua {3} \u0111ang kh\u00F3a)", cat.Title, FormatBytes(cf), cdf, clk));
                } else if (cat.CleanMode == "ItemsList" && cat.DetailItems != null) {
                    bool doRecycle = useRecycleBinForTier45 && cat.SupportsRecycleBin;
                    for (int d = 0; d < cat.DetailItems.Count; d++) {
                        if (ct.IsCancellationRequested) break;
                        var it = cat.DetailItems[d];
                        if (it == null || !it.Selected) continue;
                        if (doRecycle) {
                            string failReason;
                            if (TryRecycleItemStrict(it.Path, out failReason)) {
                                crec++;
                                cf += it.SizeBytes;
                                if (it.IsDirectory) cdd += Math.Max(1, it.NestedCount);
                                else cdf++;
                            } else if (failReason == "CloudOrReparseSkipped") {
                                ccld++;
                            } else if (failReason == "UncNotSupportedByRecycleBin" || failReason == "PathTooLongForRecycleBin" || failReason == "AbortedByShell") {
                                crun++;
                            } else {
                                clk++;
                            }
                        } else {
                            if (it.IsDirectory) {
                                DeleteEmptySubtreeBottomUp(it.Path, ct, ref cdd, ref clk, ref ccld, 0);
                            } else {
                                bool sc;
                                if (DeleteFileWin32(it.Path, out sc)) {
                                    cf += it.SizeBytes;
                                    cdf++;
                                } else if (sc) {
                                    ccld++;
                                } else {
                                    clk++;
                                }
                            }
                        }
                    }
                    logs.Add(string.Format("[OK] {0}: {1} (x\u00F3a {2} t\u1EC7p / {3} th\u01B0 m\u1EE5c, Th\u00F9ng r\u00E1c: {4}, b\u1ECF qua: {5})",
                        cat.Title, FormatBytes(cf), cdf, cdd, crec, clk + crun + ccld));
                }

                freedTotal += cf;
                delFilesTotal += cdf;
                delFoldersTotal += cdd;
                recycledTotal += crec;
                lockedTotal += clk;
                recycleUnsupTotal += crun;
                cloudTotal += ccld;
            }

            sw.Stop();
            report.FreedBytes = freedTotal;
            report.DeletedFiles = delFilesTotal;
            report.DeletedFolders = delFoldersTotal;
            report.RecycledItems = recycledTotal;
            report.SkippedLockedCount = lockedTotal;
            report.SkippedRecycleUnsupportedCount = recycleUnsupTotal;
            report.SkippedCloudCount = cloudTotal;
            report.WasCancelled = ct.IsCancellationRequested;
            report.ElapsedMs = sw.ElapsedMilliseconds;
            report.PerCategoryLogs = logs.ToArray();
            return report;
        }

        public static Task<ResourceCleanReport> CleanSelectedCategoriesAsync(ResourceCleanCategory[] categories, bool useRecycleBinForTier45, CancellationToken ct) {
            return Task.Run(delegate {
                return CleanSelectedCategories(categories, useRecycleBinForTier45, ct);
            });
        }

        // === C# WPF Visual Factory (Zero-Lag Rendering matching StartupManagerEngine) ===
        private static System.Windows.Media.SolidColorBrush MakeFrozen(byte a, byte r, byte g, byte b) {
            var br = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(a, r, g, b));
            br.Freeze();
            return br;
        }

        private static readonly System.Windows.Media.SolidColorBrush BrWhite       = MakeFrozen(255, 0xF8, 0xFA, 0xFC);
        private static readonly System.Windows.Media.SolidColorBrush BrMuted       = MakeFrozen(255, 0x94, 0xA3, 0xB8);
        private static readonly System.Windows.Media.SolidColorBrush BrSub         = MakeFrozen(255, 0x64, 0x74, 0x8B);
        private static readonly System.Windows.Media.SolidColorBrush BrAccent      = MakeFrozen(255, 0x38, 0xBD, 0xF8);
        private static readonly System.Windows.Media.SolidColorBrush BrSafeBg      = MakeFrozen(255, 0x0D, 0x2B, 0x22);
        private static readonly System.Windows.Media.SolidColorBrush BrSafeBdr     = MakeFrozen(255, 0x1E, 0x56, 0x40);
        private static readonly System.Windows.Media.SolidColorBrush BrSafeFg      = MakeFrozen(255, 0x34, 0xD3, 0x99);
        private static readonly System.Windows.Media.SolidColorBrush BrCautBg      = MakeFrozen(255, 0x2F, 0x24, 0x0F);
        private static readonly System.Windows.Media.SolidColorBrush BrCautBdr     = MakeFrozen(255, 0x61, 0x4F, 0x27);
        private static readonly System.Windows.Media.SolidColorBrush BrCautFg      = MakeFrozen(255, 0xFB, 0xBF, 0x24);
        private static readonly System.Windows.Media.SolidColorBrush BrAdvBg       = MakeFrozen(255, 0x33, 0x15, 0x1B);
        private static readonly System.Windows.Media.SolidColorBrush BrAdvBdr      = MakeFrozen(255, 0x6E, 0x27, 0x34);
        private static readonly System.Windows.Media.SolidColorBrush BrAdvFg       = MakeFrozen(255, 0xFD, 0xA4, 0xAF);
        private static readonly System.Windows.Media.SolidColorBrush BrDetailBg    = MakeFrozen(255, 0x09, 0x0E, 0x17);
        private static readonly System.Windows.Media.SolidColorBrush BrDetailBdr   = MakeFrozen(255, 0x1E, 0x2B, 0x40);
        private static readonly System.Windows.Media.SolidColorBrush BrDivider     = MakeFrozen(0x1C, 0xFF, 0xFF, 0xFF);
        private static readonly System.Windows.Media.SolidColorBrush BrOneDriveBg  = MakeFrozen(255, 0x17, 0x25, 0x54);
        private static readonly System.Windows.Media.SolidColorBrush BrOneDriveFg  = MakeFrozen(255, 0x93, 0xC5, 0xFD);
        private static readonly System.Windows.Media.SolidColorBrush BrBtnBg       = MakeFrozen(255, 0x16, 0x22, 0x35);
        private static readonly System.Windows.Media.SolidColorBrush BrBtnBdr      = MakeFrozen(255, 0x2B, 0x3D, 0x57);

        public static ResourceRowVisual CreateResourceRowVisual(ResourceCleanCategory cat, Style rowStyle, Style checkStyle, Style actionBtnStyle) {
            var vis = new ResourceRowVisual();
            vis.Category = cat;

            var outer = new System.Windows.Controls.Border();
            if (rowStyle != null) outer.Style = rowStyle;
            outer.UseLayoutRounding = true;
            outer.SnapsToDevicePixels = true;

            var rootStack = new System.Windows.Controls.StackPanel();

            var grid = new System.Windows.Controls.Grid();
            grid.MinHeight = 52;
            grid.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(52) });
            grid.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(96) });
            grid.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(136) });
            grid.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(136) });

            // Col 0: CheckBox
            bool hasActionable = (cat.Id == "t4_empty_folders") ? (cat.FolderCount > 0 || cat.ItemCount > 0) : (cat.TotalBytes > 0 || cat.ItemCount > 0);
            var cb = new System.Windows.Controls.CheckBox();
            if (checkStyle != null) cb.Style = checkStyle;
            cb.HorizontalAlignment = HorizontalAlignment.Center;
            cb.VerticalAlignment = VerticalAlignment.Center;
            cb.IsChecked = hasActionable && cat.Selected;
            cb.IsEnabled = !cat.SkippedBecauseRebootPending && hasActionable;
            cb.Tag = vis;
            System.Windows.Controls.Grid.SetColumn(cb, 0);
            grid.Children.Add(cb);

            // Col 1: Title & Description
            var infoSp = new System.Windows.Controls.StackPanel();
            infoSp.Margin = new Thickness(10, 7, 10, 7);
            infoSp.VerticalAlignment = VerticalAlignment.Center;

            var titleRow = new System.Windows.Controls.StackPanel();
            titleRow.Orientation = System.Windows.Controls.Orientation.Horizontal;
            var tbTitle = new System.Windows.Controls.TextBlock();
            tbTitle.Text = cat.Title ?? "";
            tbTitle.FontSize = 12.5;
            tbTitle.FontWeight = FontWeights.SemiBold;
            tbTitle.Foreground = cb.IsEnabled ? BrWhite : BrMuted;
            tbTitle.TextTrimming = TextTrimming.CharacterEllipsis;
            titleRow.Children.Add(tbTitle);
            infoSp.Children.Add(titleRow);

            var tbSub = new System.Windows.Controls.TextBlock();
            tbSub.Text = !string.IsNullOrWhiteSpace(cat.StatusNote) ? cat.StatusNote : (cat.Description ?? "");
            tbSub.FontSize = 11;
            tbSub.Foreground = !string.IsNullOrWhiteSpace(cat.StatusNote) ? BrCautFg : BrSub;
            tbSub.Margin = new Thickness(0, 2, 0, 0);
            tbSub.TextTrimming = TextTrimming.CharacterEllipsis;
            infoSp.Children.Add(tbSub);

            System.Windows.Controls.Grid.SetColumn(infoSp, 1);
            grid.Children.Add(infoSp);

            // Col 2: Risk Badge
            var riskPill = new System.Windows.Controls.Border();
            riskPill.CornerRadius = new CornerRadius(3);
            riskPill.BorderThickness = new Thickness(1);
            riskPill.Padding = new Thickness(8, 2, 8, 2);
            riskPill.HorizontalAlignment = HorizontalAlignment.Center;
            riskPill.VerticalAlignment = VerticalAlignment.Center;
            var riskTb = new System.Windows.Controls.TextBlock();
            riskTb.FontSize = 10.5;
            riskTb.FontWeight = FontWeights.SemiBold;
            if (cat.RiskLevel == "Safe") {
                riskPill.Background = BrSafeBg; riskPill.BorderBrush = BrSafeBdr; riskTb.Foreground = BrSafeFg;
                riskTb.Text = "An to\u00E0n";
            } else if (cat.RiskLevel == "Caution") {
                riskPill.Background = BrCautBg; riskPill.BorderBrush = BrCautBdr; riskTb.Foreground = BrCautFg;
                riskTb.Text = "L\u01B0u \u00FD";
            } else {
                riskPill.Background = BrAdvBg; riskPill.BorderBrush = BrAdvBdr; riskTb.Foreground = BrAdvFg;
                riskTb.Text = "N\u00E2ng cao";
            }
            riskPill.Child = riskTb;
            System.Windows.Controls.Grid.SetColumn(riskPill, 2);
            grid.Children.Add(riskPill);

            // Col 3: Size & Count
            var statSp = new System.Windows.Controls.StackPanel();
            statSp.HorizontalAlignment = HorizontalAlignment.Right;
            statSp.VerticalAlignment = VerticalAlignment.Center;
            statSp.Margin = new Thickness(8, 0, 12, 0);

            var tbSize = new System.Windows.Controls.TextBlock();
            tbSize.Text = cat.Id == "t4_empty_folders"
                ? string.Format("{0} th\u01B0 m\u1EE5c", cat.FolderCount)
                : FormatBytes(cat.TotalBytes);
            tbSize.FontSize = 12.5;
            tbSize.FontWeight = FontWeights.Bold;
            tbSize.HorizontalAlignment = HorizontalAlignment.Right;
            tbSize.Foreground = (cat.TotalBytes >= 100L * 1024L * 1024L) ? BrCautFg : (cb.IsEnabled ? BrAccent : BrSub);
            statSp.Children.Add(tbSize);

            var tbCnt = new System.Windows.Controls.TextBlock();
            if (cat.Id == "t4_empty_folders") {
                tbCnt.Text = cat.ItemCount > 0 ? string.Format("{0} nh\u00E1nh r\u1ED7ng", cat.ItemCount) : "S\u1EA1ch s\u1EBD";
            } else if (cat.ItemCount > 0) {
                tbCnt.Text = string.Format("{0:N0} m\u1EE5c", cat.ItemCount);
            } else {
                tbCnt.Text = "S\u1EA1ch s\u1EBD";
            }
            tbCnt.FontSize = 10.5;
            tbCnt.Foreground = BrSub;
            tbCnt.HorizontalAlignment = HorizontalAlignment.Right;
            statSp.Children.Add(tbCnt);

            System.Windows.Controls.Grid.SetColumn(statSp, 3);
            grid.Children.Add(statSp);

            // Col 4: Actions (Details / Open)
            var actSp = new System.Windows.Controls.StackPanel();
            actSp.Orientation = System.Windows.Controls.Orientation.Horizontal;
            actSp.HorizontalAlignment = HorizontalAlignment.Center;
            actSp.VerticalAlignment = VerticalAlignment.Center;

            var btnDetails = new System.Windows.Controls.Button();
            if (actionBtnStyle != null) btnDetails.Style = actionBtnStyle;
            btnDetails.Content = "Chi ti\u1EBFt";
            btnDetails.Background = BrBtnBg;
            btnDetails.BorderBrush = BrBtnBdr;
            btnDetails.Foreground = BrAccent;
            btnDetails.FontSize = 11;
            btnDetails.FontWeight = FontWeights.SemiBold;
            btnDetails.Padding = new Thickness(8, 3, 8, 3);
            btnDetails.IsEnabled = (cat.DetailItems != null && cat.DetailItems.Count > 0);
            if (!btnDetails.IsEnabled) btnDetails.Opacity = 0.35;
            btnDetails.Tag = vis;
            actSp.Children.Add(btnDetails);

            var btnOpen = new System.Windows.Controls.Button();
            if (actionBtnStyle != null) btnOpen.Style = actionBtnStyle;
            btnOpen.Content = "M\u1EDF";
            btnOpen.Background = BrBtnBg;
            btnOpen.BorderBrush = BrBtnBdr;
            btnOpen.Foreground = BrAccent;
            btnOpen.FontSize = 11;
            btnOpen.FontWeight = FontWeights.SemiBold;
            btnOpen.Padding = new Thickness(8, 3, 8, 3);
            btnOpen.Margin = new Thickness(5, 0, 0, 0);
            btnOpen.IsEnabled = (cat.RootPaths != null && cat.RootPaths.Length > 0);
            if (!btnOpen.IsEnabled) btnOpen.Opacity = 0.35;
            btnOpen.Tag = vis;
            actSp.Children.Add(btnOpen);

            System.Windows.Controls.Grid.SetColumn(actSp, 4);
            grid.Children.Add(actSp);

            for (int c = 0; c < 4; c++) {
                var sep = new System.Windows.Controls.Border();
                sep.Width = 1;
                sep.HorizontalAlignment = HorizontalAlignment.Right;
                sep.VerticalAlignment = VerticalAlignment.Stretch;
                sep.Background = BrDivider;
                sep.IsHitTestVisible = false;
                System.Windows.Controls.Grid.SetColumn(sep, c);
                grid.Children.Add(sep);
            }

            rootStack.Children.Add(grid);

            var detailContainer = new System.Windows.Controls.Border();
            detailContainer.Visibility = Visibility.Collapsed;
            detailContainer.Background = BrDetailBg;
            detailContainer.BorderBrush = BrDetailBdr;
            detailContainer.BorderThickness = new Thickness(0, 1, 0, 0);
            detailContainer.Padding = new Thickness(56, 6, 14, 8);
            var detailHost = new System.Windows.Controls.StackPanel();
            detailContainer.Child = detailHost;
            rootStack.Children.Add(detailContainer);

            outer.Child = rootStack;

            vis.Row = outer;
            vis.CheckBox = cb;
            vis.TitleText = tbTitle;
            vis.SubText = tbSub;
            vis.SizeText = tbSize;
            vis.CountText = tbCnt;
            vis.DetailsBtn = btnDetails;
            vis.OpenBtn = btnOpen;
            vis.DetailsContainer = detailContainer;
            vis.DetailsHost = detailHost;
            return vis;
        }

        public static void PopulateDetailsPanel(ResourceRowVisual vis, Style checkStyle, Style actionBtnStyle, RoutedEventHandler onDetailCheckChanged, RoutedEventHandler onOpenDetailClick) {
            if (vis == null || vis.DetailsHost == null || vis.DetailsPopulated) return;
            vis.DetailsPopulated = true;
            var cat = vis.Category;
            if (cat == null || cat.DetailItems == null || cat.DetailItems.Count == 0) return;

            int cap = Math.Min(cat.DetailItems.Count, 80);
            for (int i = 0; i < cap; i++) {
                var it = cat.DetailItems[i];
                var row = new System.Windows.Controls.Grid();
                row.Margin = new Thickness(0, 2, 0, 2);
                row.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(26) });
                row.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = GridLength.Auto });
                row.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = GridLength.Auto });

                if (cat.CleanMode == "ItemsList") {
                    var dcb = new System.Windows.Controls.CheckBox();
                    if (checkStyle != null) dcb.Style = checkStyle;
                    dcb.IsChecked = it.Selected;
                    dcb.VerticalAlignment = VerticalAlignment.Center;
                    dcb.Tag = new object[] { vis, it };
                    if (onDetailCheckChanged != null) {
                        dcb.Checked += onDetailCheckChanged;
                        dcb.Unchecked += onDetailCheckChanged;
                    }
                    System.Windows.Controls.Grid.SetColumn(dcb, 0);
                    row.Children.Add(dcb);
                }

                var pathSp = new System.Windows.Controls.StackPanel();
                pathSp.Orientation = System.Windows.Controls.Orientation.Horizontal;
                pathSp.VerticalAlignment = VerticalAlignment.Center;

                var ptb = new System.Windows.Controls.TextBlock();
                ptb.Text = it.DisplayPath ?? it.Path ?? "";
                ptb.FontSize = 11;
                ptb.Foreground = BrMuted;
                ptb.TextTrimming = TextTrimming.CharacterEllipsis;
                ptb.ToolTip = it.Path;
                System.Windows.Controls.ToolTipService.SetInitialShowDelay(ptb, 5000);
                pathSp.Children.Add(ptb);

                if (it.IsOneDrive) {
                    var odBd = new System.Windows.Controls.Border();
                    odBd.Background = BrOneDriveBg;
                    odBd.CornerRadius = new CornerRadius(3);
                    odBd.Padding = new Thickness(5, 1, 5, 1);
                    odBd.Margin = new Thickness(6, 0, 0, 0);
                    var odTb = new System.Windows.Controls.TextBlock();
                    odTb.Text = "OneDrive";
                    odTb.FontSize = 9.5;
                    odTb.FontWeight = FontWeights.SemiBold;
                    odTb.Foreground = BrOneDriveFg;
                    odBd.Child = odTb;
                    pathSp.Children.Add(odBd);
                }
                System.Windows.Controls.Grid.SetColumn(pathSp, 1);
                row.Children.Add(pathSp);

                var ntb = new System.Windows.Controls.TextBlock();
                ntb.Text = it.SizeBytes > 0 ? FormatBytes(it.SizeBytes) : (it.Note ?? "");
                ntb.FontSize = 11;
                ntb.Foreground = BrAccent;
                ntb.VerticalAlignment = VerticalAlignment.Center;
                ntb.Margin = new Thickness(10, 0, 10, 0);
                System.Windows.Controls.Grid.SetColumn(ntb, 2);
                row.Children.Add(ntb);

                var ob = new System.Windows.Controls.Button();
                if (actionBtnStyle != null) ob.Style = actionBtnStyle;
                ob.Content = "M\u1EDF";
                ob.Background = BrBtnBg;
                ob.BorderBrush = BrBtnBdr;
                ob.Foreground = BrAccent;
                ob.FontWeight = FontWeights.SemiBold;
                ob.Padding = new Thickness(7, 2, 7, 2);
                ob.FontSize = 10.5;
                ob.Tag = it.Path;
                if (onOpenDetailClick != null) ob.Click += onOpenDetailClick;
                System.Windows.Controls.Grid.SetColumn(ob, 3);
                row.Children.Add(ob);

                vis.DetailsHost.Children.Add(row);
            }

            if (cat.DetailItems.Count > cap) {
                var more = new System.Windows.Controls.TextBlock();
                more.Text = string.Format("... v\u00E0 c\u00F2n {0} m\u1EE5c kh\u00E1c trong h\u1EA1ng m\u1EE5c n\u00E0y.", cat.DetailItems.Count - cap);
                more.FontSize = 10.5;
                more.Foreground = BrSub;
                more.Margin = new Thickness(26, 4, 0, 0);
                vis.DetailsHost.Children.Add(more);
            }
        }
    }
}
