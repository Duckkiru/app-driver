using System;
using System.Collections.Concurrent;
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
        public int ClosedHandlesCount { get; set; }
        public string[] KilledNames { get; set; }
        public string[] AccessDeniedNames { get; set; }
        public string[] SkippedSystemLockers { get; set; }
        public string[] ClosedHandleNames { get; set; }

        public ForceStopReport()
        {
            KilledNames = new string[0];
            AccessDeniedNames = new string[0];
            SkippedSystemLockers = new string[0];
            ClosedHandleNames = new string[0];
        }
    }

    public class ForceDeleteResult
    {
        public bool Deleted { get; set; }
        public int RebootScheduledCount { get; set; }
    }

    public class ServiceScanEntry
    {
        public string ServiceName { get; set; }
        public string DisplayName { get; set; }
        public string ImagePath { get; set; }
        public string ResolvedImagePath { get; set; }
        public int ServiceType { get; set; }
        public bool IsKernelDriver { get; set; }
    }

    public class HollowDirResult
    {
        public string Path { get; set; }
        public string AppName { get; set; }
        public long SizeBytes { get; set; }
    }

    public class DeadShortcutResult
    {
        public string LnkPath { get; set; }
        public string AppName { get; set; }
    }

    public class ServicesAndRogueResult
    {
        public List<ServiceScanEntry> AllServices { get; set; }
        public List<ServiceScanEntry> RogueDrivers { get; set; }
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
        private const int SystemExtendedHandleInformation = 64;
        private const int STATUS_INFO_LENGTH_MISMATCH = unchecked((int)0xC0000004);
        private const uint PROCESS_DUP_HANDLE = 0x0040;
        private const uint PROCESS_QUERY_INFORMATION = 0x0400;
        private const uint PROCESS_VM_READ = 0x0010;
        private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        private const uint DUPLICATE_CLOSE_SOURCE = 0x00000001;
        private const uint DUPLICATE_SAME_ACCESS = 0x00000002;
        private const uint FILE_TYPE_DISK = 1;
        private const uint MEM_COMMIT = 0x1000;
        private const uint MEM_MAPPED = 0x40000;
        private const uint MEM_IMAGE = 0x1000000;
        private const int SE_FILE_OBJECT = 1;
        private const uint OWNER_SECURITY_INFORMATION = 0x00000001;
        private const uint DACL_SECURITY_INFORMATION = 0x00000004;
        private const uint PROTECTED_DACL_SECURITY_INFORMATION = 0x80000000;
        private const uint GENERIC_ALL = 0x10000000;
        private const uint SET_ACCESS = 2;
        private const uint NO_INHERITANCE = 0;
        private const uint SUB_CONTAINERS_AND_OBJECTS_INHERIT = 3;
        private const uint TRUSTEE_IS_SID = 0;
        private const uint TRUSTEE_IS_GROUP = 2;
        private const uint TRUSTEE_IS_USER = 1;
        private const uint SC_MANAGER_CONNECT = 0x0001;
        private const uint SC_MANAGER_ENUMERATE_SERVICE = 0x0004;
        private const uint SERVICE_QUERY_STATUS = 0x0004;
        private const uint SERVICE_ENUMERATE_DEPENDENTS = 0x0008;
        private const uint SERVICE_STOP = 0x0020;
        private const uint DELETE_ACCESS = 0x00010000;
        private const uint LIST_MODULES_ALL = 0x03;
        private const uint SERVICE_ACTIVE = 0x00000001;
        private const uint SERVICE_CONTROL_STOP = 0x00000001;
        private const uint SERVICE_STOPPED = 0x00000001;
        private const uint TOKEN_DUPLICATE = 0x0002;
        private const uint TOKEN_IMPERSONATE = 0x0004;
        private const uint TOKEN_QUERY = 0x0008;
        private const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
        private const uint MAXIMUM_ALLOWED = 0x02000000;
        private const int SecurityImpersonation = 2;
        private const int TokenImpersonation = 2;
        private static readonly object _privLock = new object();
        private static bool _privilegesEnabled = false;
        private static readonly object _sysinternalsLock = new object();
        private static bool _sysinternalsChecked = false;
        private static string _cachedSysinternalsHandleExe = "";

        public delegate void ElevatedAction();
        public delegate int ElevationPidProvider(bool wantInstaller);
        public static ElevationPidProvider CustomElevationPidProvider;

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

        [StructLayout(LayoutKind.Sequential)]
        private struct SID_IDENTIFIER_AUTHORITY
        {
            public byte Value0;
            public byte Value1;
            public byte Value2;
            public byte Value3;
            public byte Value4;
            public byte Value5;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct TRUSTEE
        {
            public IntPtr pMultipleTrustee;
            public uint MultipleTrusteeOperation;
            public uint TrusteeForm;
            public uint TrusteeType;
            public IntPtr ptstrName;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct EXPLICIT_ACCESS
        {
            public uint grfAccessPermissions;
            public uint grfAccessMode;
            public uint grfInheritance;
            public TRUSTEE Trustee;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        private struct TOKEN_PRIVILEGES_1
        {
            public uint PrivilegeCount;
            public long Luid;
            public uint Attributes;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MEMORY_BASIC_INFORMATION_X64
        {
            public IntPtr BaseAddress;
            public IntPtr AllocationBase;
            public uint AllocationProtect;
            public ushort PartitionId;
            public IntPtr RegionSize;
            public uint State;
            public uint Protect;
            public uint Type;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MEMORY_BASIC_INFORMATION_X86
        {
            public IntPtr BaseAddress;
            public IntPtr AllocationBase;
            public uint AllocationProtect;
            public IntPtr RegionSize;
            public uint State;
            public uint Protect;
            public uint Type;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SERVICE_STATUS
        {
            public uint dwServiceType;
            public uint dwCurrentState;
            public uint dwControlsAccepted;
            public uint dwWin32ExitCode;
            public uint dwServiceSpecificExitCode;
            public uint dwCheckPoint;
            public uint dwWaitHint;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct ENUM_SERVICE_STATUS
        {
            public IntPtr lpServiceName;
            public IntPtr lpDisplayName;
            public SERVICE_STATUS ServiceStatus;
        }

        private class MatchedRemoteHandle
        {
            public IntPtr RemoteHandle;
            public string DosPath;
            public uint GrantedAccess;
        }

        private class HandleWorkerState
        {
            public AutoResetEvent WorkEv = new AutoResetEvent(false);
            public AutoResetEvent DoneEv = new AutoResetEvent(false);
            public volatile IntPtr PendingHandle = IntPtr.Zero;
            public volatile string PendingPath = null;
            public volatile bool StopRequested = false;
            public volatile uint ThreadId = 0;
            public IntPtr ThreadHandle = IntPtr.Zero;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IO_STATUS_BLOCK
        {
            public IntPtr Status;
            public IntPtr Information;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FILE_DISPOSITION_INFO_EX
        {
            public uint Flags;
        }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);

        [DllImport("ntdll.dll", SetLastError = true)]
        private static extern int NtSuspendProcess(IntPtr processHandle);

        [DllImport("ntdll.dll")]
        private static extern int NtQuerySystemInformation(int SystemInformationClass, IntPtr SystemInformation, int SystemInformationLength, out int ReturnLength);

        [DllImport("ntdll.dll")]
        private static extern int NtSetInformationFile(IntPtr FileHandle, out IO_STATUS_BLOCK IoStatusBlock, ref FILE_DISPOSITION_INFO_EX FileInformation, uint Length, int FileInformationClass);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DuplicateHandle(IntPtr hSourceProcessHandle, IntPtr hSourceHandle, IntPtr hTargetProcessHandle, out IntPtr lpTargetHandle, uint dwDesiredAccess, bool bInheritHandle, uint dwOptions);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint GetFileType(IntPtr hFile);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandleW(IntPtr hFile, System.Text.StringBuilder lpszFilePath, uint cchFilePath, uint dwFlags);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr hObject);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenThread(uint dwDesiredAccess, bool bInheritHandle, uint dwThreadId);

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CancelSynchronousIo(IntPtr hThread);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint QueryDosDeviceW(string lpDeviceName, System.Text.StringBuilder lpTargetPath, uint ucchMax);

        [DllImport("kernel32.dll", EntryPoint = "VirtualQueryEx", SetLastError = true)]
        private static extern IntPtr VirtualQueryEx64(IntPtr hProcess, IntPtr lpAddress, out MEMORY_BASIC_INFORMATION_X64 lpBuffer, IntPtr dwLength);

        [DllImport("kernel32.dll", EntryPoint = "VirtualQueryEx", SetLastError = true)]
        private static extern IntPtr VirtualQueryEx86(IntPtr hProcess, IntPtr lpAddress, out MEMORY_BASIC_INFORMATION_X86 lpBuffer, IntPtr dwLength);

        [DllImport("psapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetMappedFileNameW(IntPtr hProcess, IntPtr lpv, System.Text.StringBuilder lpFilename, uint nSize);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool QueryFullProcessImageNameW(IntPtr hProcess, uint dwFlags, System.Text.StringBuilder lpExeName, ref uint lpdwSize);

        [DllImport("psapi.dll", SetLastError = true)]
        private static extern bool EnumProcessModulesEx(IntPtr hProcess, [Out] IntPtr[] lphModule, uint cb, out uint lpcbNeeded, uint dwFilterFlag);

        [DllImport("psapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetModuleFileNameExW(IntPtr hProcess, IntPtr hModule, System.Text.StringBuilder lpFilename, uint nSize);

        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr hMem);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool LookupPrivilegeValueW(string lpSystemName, string lpName, out long lpLuid);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES_1 NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool GetTokenInformation(IntPtr TokenHandle, int TokenInformationClass, IntPtr TokenInformation, uint TokenInformationLength, out uint ReturnLength);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool AllocateAndInitializeSid(
            ref SID_IDENTIFIER_AUTHORITY pIdentifierAuthority,
            byte nSubAuthorityCount,
            uint nSubAuthority0, uint nSubAuthority1,
            uint nSubAuthority2, uint nSubAuthority3,
            uint nSubAuthority4, uint nSubAuthority5,
            uint nSubAuthority6, uint nSubAuthority7,
            out IntPtr pSid);

        [DllImport("advapi32.dll")]
        private static extern IntPtr FreeSid(IntPtr pSid);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
        private static extern uint SetEntriesInAclW(uint cCountOfExplicitEntries, ref EXPLICIT_ACCESS pListOfExplicitEntries, IntPtr OldAcl, out IntPtr NewAcl);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
        private static extern uint SetNamedSecurityInfoW(string pObjectName, int ObjectType, uint SecurityInfo, IntPtr psidOwner, IntPtr psidGroup, IntPtr pDacl, IntPtr pSacl);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr OpenSCManagerW(string lpMachineName, string lpDatabaseName, uint dwDesiredAccess);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr OpenServiceW(IntPtr hSCManager, string lpServiceName, uint dwDesiredAccess);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool EnumDependentServicesW(IntPtr hService, uint dwServiceState, IntPtr lpServices, uint cbBufSize, out uint pcbBytesNeeded, out uint lpServicesReturned);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool ControlService(IntPtr hService, uint dwControl, out SERVICE_STATUS lpServiceStatus);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool QueryServiceStatus(IntPtr hService, out SERVICE_STATUS lpServiceStatus);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool DeleteService(IntPtr hService);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool CloseServiceHandle(IntPtr hSCObject);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool DuplicateTokenEx(
            IntPtr hExistingToken,
            uint dwDesiredAccess,
            IntPtr lpTokenAttributes,
            int ImpersonationLevel,
            int TokenType,
            out IntPtr phNewToken);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool ImpersonateLoggedOnUser(IntPtr hToken);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool RevertToSelf();

        [DllImport("fltlib.dll", CharSet = CharSet.Unicode)]
        private static extern int FilterDetach(string lpFilterName, string lpVolumeName, string lpInstanceName);

        [DllImport("fltlib.dll", CharSet = CharSet.Unicode)]
        private static extern int FilterUnload(string lpFilterName);

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

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WIN32_FIND_DATAW
        {
            public uint dwFileAttributes;
            public uint ftCreationTimeLow;
            public uint ftCreationTimeHigh;
            public uint ftLastAccessTimeLow;
            public uint ftLastAccessTimeHigh;
            public uint ftLastWriteTimeLow;
            public uint ftLastWriteTimeHigh;
            public uint nFileSizeHigh;
            public uint nFileSizeLow;
            public uint dwReserved0;
            public uint dwReserved1;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            public string cFileName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)]
            public string cAlternateFileName;
        }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern IntPtr FindFirstFileExW(string lpFileName, int fInfoLevelId, out WIN32_FIND_DATAW lpFindFileData, int fSearchOp, IntPtr lpSearchFilter, int dwAdditionalFlags);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool FindNextFileW(IntPtr hFindFile, out WIN32_FIND_DATAW lpFindFileData);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool FindClose(IntPtr hFindFile);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern uint GetFileAttributesW(string lpFileName);

        private static readonly IntPtr INVALID_FIND_HANDLE = new IntPtr(-1);
        private const uint W32_FILE_ATTRIBUTE_DIRECTORY = 0x10;
        private const uint W32_FILE_ATTRIBUTE_REPARSE_POINT = 0x400;
        private const uint W32_INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF;

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
                uint rootAttr = GetFileAttributesW(rootPath);
                if (rootAttr == W32_INVALID_FILE_ATTRIBUTES ||
                    (rootAttr & W32_FILE_ATTRIBUTE_DIRECTORY) == 0 ||
                    (rootAttr & W32_FILE_ATTRIBUTE_REPARSE_POINT) != 0)
                {
                    return 0L;
                }
            }
            catch { return 0L; }

            long totalSize = 0L;
            int fileCount = 0;
            var currentLevel = new List<string> { rootPath };

            for (int depth = 0; depth <= maxDepth; depth++)
            {
                var nextLevel = new List<string>();
                for (int di = 0; di < currentLevel.Count; di++)
                {
                    string dir = currentLevel[di];
                    string search = dir.EndsWith("\\", StringComparison.Ordinal) ? (dir + "*") : (dir + "\\*");
                    WIN32_FIND_DATAW fd;
                    IntPtr h = INVALID_FIND_HANDLE;
                    try
                    {
                        h = FindFirstFileExW(search, 1, out fd, 0, IntPtr.Zero, 2);
                        if (h == INVALID_FIND_HANDLE)
                        {
                            h = FindFirstFileExW(search, 0, out fd, 0, IntPtr.Zero, 0);
                        }
                        if (h == INVALID_FIND_HANDLE) continue;

                        do
                        {
                            string name = fd.cFileName;
                            if (string.IsNullOrEmpty(name) || name == "." || name == "..") continue;
                            if ((fd.dwFileAttributes & W32_FILE_ATTRIBUTE_DIRECTORY) != 0)
                            {
                                if (depth < maxDepth && (fd.dwFileAttributes & W32_FILE_ATTRIBUTE_REPARSE_POINT) == 0)
                                {
                                    nextLevel.Add(dir.EndsWith("\\", StringComparison.Ordinal) ? (dir + name) : (dir + "\\" + name));
                                }
                            }
                            else
                            {
                                totalSize += ((long)fd.nFileSizeHigh << 32) | (uint)fd.nFileSizeLow;
                                fileCount++;
                                if (fileCount >= maxFiles) return totalSize;
                            }
                        }
                        while (FindNextFileW(h, out fd));
                    }
                    catch {}
                    finally
                    {
                        if (h != INVALID_FIND_HANDLE)
                        {
                            try { FindClose(h); } catch {}
                        }
                    }
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

        private static readonly HashSet<string> _kernelCriticalProcNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "system", "idle", "registry", "memory compression", "vmmem", "vmmemwsl",
            "smss", "csrss", "wininit", "services", "lsass", "lsm", "winlogon",
            "dwm", "fontdrvhost", "audiodg"
        };

        private static readonly HashSet<string> _protectedSystemProcNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "system", "idle", "registry", "memory compression", "vmmem", "vmmemwsl",
            "smss", "csrss", "wininit", "services", "lsass", "lsm", "winlogon",
            "dwm", "fontdrvhost", "audiodg", "sihost", "ctfmon", "spoolsv", "msdtc",
            "svchost", "explorer", "conhost", "openconsole", "windowsterminal",
            "cmd", "powershell", "pwsh", "code", "antigravity"
        };

        private static bool IsKernelCriticalProcess(int pid, string procName)
        {
            if (pid <= 4) return true;
            try
            {
                if (pid == Process.GetCurrentProcess().Id) return true;
            }
            catch {}
            if (string.IsNullOrWhiteSpace(procName)) return false;
            return _kernelCriticalProcNames.Contains(procName.Trim());
        }

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

        private static void EnableUnlockPrivilegesOnToken(IntPtr hTok)
        {
            if (hTok == IntPtr.Zero) return;
            try
            {
                string[] privs = new string[]
                {
                    "SeDebugPrivilege",
                    "SeBackupPrivilege",
                    "SeRestorePrivilege",
                    "SeTakeOwnershipPrivilege",
                    "SeSecurityPrivilege",
                    "SeLoadDriverPrivilege",
                    "SeImpersonatePrivilege",
                    "SeTcbPrivilege",
                    "SeAssignPrimaryTokenPrivilege"
                };
                foreach (string priv in privs)
                {
                    long luid;
                    if (LookupPrivilegeValueW(null, priv, out luid))
                    {
                        var tp = new TOKEN_PRIVILEGES_1();
                        tp.PrivilegeCount = 1;
                        tp.Luid = luid;
                        tp.Attributes = 2;
                        AdjustTokenPrivileges(hTok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
                    }
                }
            }
            catch {}
        }

        private static void EnsureUnlockPrivileges()
        {
            lock (_privLock)
            {
                if (_privilegesEnabled) return;
                IntPtr hTok;
                if (OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out hTok))
                {
                    try
                    {
                        EnableUnlockPrivilegesOnToken(hTok);
                    }
                    finally
                    {
                        CloseHandle(hTok);
                    }
                }
                _privilegesEnabled = true;
            }
        }

        private static int FindProcessIdByNameFast(string procName)
        {
            if (string.IsNullOrWhiteSpace(procName)) return 0;
            int foundPid = 0;
            Process[] arr = null;
            try
            {
                arr = Process.GetProcessesByName(procName);
                if (arr != null)
                {
                    for (int i = 0; i < arr.Length; i++)
                    {
                        try
                        {
                            if (foundPid == 0 && arr[i] != null && arr[i].Id > 4)
                            {
                                foundPid = arr[i].Id;
                            }
                        }
                        catch {}
                        finally
                        {
                            try { if (arr[i] != null) arr[i].Dispose(); } catch {}
                        }
                    }
                }
            }
            catch {}
            return foundPid;
        }

        private static bool TryDuplicateProcessImpersonationToken(int pid, out IntPtr hDupToken)
        {
            hDupToken = IntPtr.Zero;
            if (pid <= 4) return false;
            IntPtr hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
            if (hProc == IntPtr.Zero)
            {
                hProc = OpenProcess(PROCESS_QUERY_INFORMATION, false, pid);
            }
            if (hProc == IntPtr.Zero) return false;
            try
            {
                IntPtr hTok;
                if (!OpenProcessToken(hProc, TOKEN_DUPLICATE | TOKEN_IMPERSONATE | TOKEN_QUERY, out hTok))
                {
                    if (!OpenProcessToken(hProc, TOKEN_DUPLICATE | TOKEN_QUERY, out hTok))
                    {
                        return false;
                    }
                }
                try
                {
                    if (DuplicateTokenEx(hTok, MAXIMUM_ALLOWED, IntPtr.Zero, SecurityImpersonation, TokenImpersonation, out hDupToken) && hDupToken != IntPtr.Zero)
                    {
                        EnableUnlockPrivilegesOnToken(hDupToken);
                        return true;
                    }
                    hDupToken = IntPtr.Zero;
                    return false;
                }
                finally
                {
                    CloseHandle(hTok);
                }
            }
            catch
            {
                hDupToken = IntPtr.Zero;
                return false;
            }
            finally
            {
                CloseHandle(hProc);
            }
        }

        private static readonly object _tiLock = new object();
        private static DateTime _lastTiLookupAtUtc = DateTime.MinValue;
        private static int _cachedTiPid = 0;

        private static bool IsProcessAliveFast(int pid)
        {
            if (pid <= 4) return false;
            IntPtr hp = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
            if (hp == IntPtr.Zero) return false;
            CloseHandle(hp);
            return true;
        }

        public static void PrewarmElevationCache()
        {
            ElevationPidProvider provider = CustomElevationPidProvider;
            if (provider == null) return;
            lock (_tiLock)
            {
                if (_cachedTiPid > 4 && !IsProcessAliveFast(_cachedTiPid))
                {
                    _cachedTiPid = 0;
                }
                if (_cachedTiPid <= 4 && (DateTime.UtcNow - _lastTiLookupAtUtc).TotalSeconds >= 12)
                {
                    _lastTiLookupAtUtc = DateTime.UtcNow;
                    try { _cachedTiPid = provider(true); } catch { _cachedTiPid = 0; }
                }
            }
        }

        private static IntPtr TryAcquireSystemOrTrustedInstallerToken(bool preferTrustedInstaller)
        {
            EnsureUnlockPrivileges();
            int sysPid = 0;
            int tiPid = 0;
            bool onThreadPool = false;
            try { onThreadPool = Thread.CurrentThread.IsThreadPoolThread; } catch {}

            ElevationPidProvider provider = CustomElevationPidProvider;
            if (!onThreadPool && provider != null)
            {
                try { sysPid = provider(false); } catch {}
                if (preferTrustedInstaller)
                {
                    lock (_tiLock)
                    {
                        if (_cachedTiPid > 4 && !IsProcessAliveFast(_cachedTiPid))
                        {
                            _cachedTiPid = 0;
                        }
                        if (_cachedTiPid <= 4 && (DateTime.UtcNow - _lastTiLookupAtUtc).TotalSeconds >= 12)
                        {
                            _lastTiLookupAtUtc = DateTime.UtcNow;
                            try { _cachedTiPid = provider(true); } catch { _cachedTiPid = 0; }
                        }
                        tiPid = _cachedTiPid;
                    }
                }
            }
            else if (preferTrustedInstaller)
            {
                lock (_tiLock)
                {
                    if (_cachedTiPid > 4 && !IsProcessAliveFast(_cachedTiPid))
                    {
                        _cachedTiPid = 0;
                    }
                    if (_cachedTiPid <= 4 && (DateTime.UtcNow - _lastTiLookupAtUtc).TotalSeconds >= 12)
                    {
                        _lastTiLookupAtUtc = DateTime.UtcNow;
                        _cachedTiPid = FindProcessIdByNameFast("TrustedInstaller");
                    }
                    tiPid = _cachedTiPid;
                }
            }

            if (sysPid <= 4)
            {
                sysPid = FindProcessIdByNameFast("winlogon");
                if (sysPid <= 4) sysPid = FindProcessIdByNameFast("spoolsv");
            }
            IntPtr hSysToken = IntPtr.Zero;
            if (sysPid > 4)
            {
                TryDuplicateProcessImpersonationToken(sysPid, out hSysToken);
            }

            if (!preferTrustedInstaller || tiPid <= 4)
            {
                return hSysToken;
            }

            IntPtr hTiToken = IntPtr.Zero;
            bool tempSysImp = false;
            try
            {
                if (hSysToken != IntPtr.Zero)
                {
                    tempSysImp = ImpersonateLoggedOnUser(hSysToken);
                }
                if (TryDuplicateProcessImpersonationToken(tiPid, out hTiToken) && hTiToken != IntPtr.Zero)
                {
                    if (tempSysImp)
                    {
                        try { RevertToSelf(); } catch {}
                        tempSysImp = false;
                    }
                    if (hSysToken != IntPtr.Zero)
                    {
                        try { CloseHandle(hSysToken); } catch {}
                    }
                    return hTiToken;
                }
            }
            catch {}
            finally
            {
                if (tempSysImp)
                {
                    try { RevertToSelf(); } catch {}
                }
            }

            return hSysToken;
        }

        public static bool RunWithSystemOrTrustedInstaller(bool preferTrustedInstaller, ElevatedAction action)
        {
            if (action == null) return false;
            EnsureUnlockPrivileges();
            IntPtr hImpToken = TryAcquireSystemOrTrustedInstallerToken(preferTrustedInstaller);
            bool impersonated = false;
            try
            {
                if (hImpToken != IntPtr.Zero)
                {
                    impersonated = ImpersonateLoggedOnUser(hImpToken);
                }
                action();
                return impersonated;
            }
            catch
            {
                return false;
            }
            finally
            {
                if (impersonated)
                {
                    try { RevertToSelf(); } catch {}
                }
                if (hImpToken != IntPtr.Zero)
                {
                    try { CloseHandle(hImpToken); } catch {}
                }
            }
        }

        private static string NormalizeDosOrNtPath(string rawPath)
        {
            if (string.IsNullOrWhiteSpace(rawPath)) return "";
            string p = rawPath.Trim();
            if (p.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase))
            {
                p = @"\\" + p.Substring(8);
            }
            else if (p.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase) || p.StartsWith(@"\??\", StringComparison.OrdinalIgnoreCase))
            {
                p = p.Substring(4);
            }
            return p.TrimEnd('\\');
        }

        private static Dictionary<string, string> BuildDosDeviceMap()
        {
            var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                var sb = new System.Text.StringBuilder(512);
                foreach (string driveRoot in Directory.GetLogicalDrives())
                {
                    if (string.IsNullOrEmpty(driveRoot) || driveRoot.Length < 2) continue;
                    string dosName = driveRoot.Substring(0, 2);
                    sb.Length = 0;
                    uint res = QueryDosDeviceW(dosName, sb, (uint)sb.Capacity);
                    if (res > 0)
                    {
                        string target = sb.ToString();
                        int nul = target.IndexOf('\0');
                        if (nul >= 0) target = target.Substring(0, nul);
                        target = target.TrimEnd('\\');
                        if (!string.IsNullOrEmpty(target) && !map.ContainsKey(target))
                        {
                            map[target] = dosName;
                        }
                    }
                }
            }
            catch {}
            return map;
        }

        private static string TranslateDevicePathToDos(string devicePath, Dictionary<string, string> dosMap)
        {
            if (string.IsNullOrWhiteSpace(devicePath)) return "";
            string p = devicePath.Trim();
            if (p.StartsWith(@"\Device\Mup\", StringComparison.OrdinalIgnoreCase))
            {
                return @"\\" + p.Substring(12);
            }
            if (dosMap != null)
            {
                foreach (KeyValuePair<string, string> kv in dosMap)
                {
                    if (p.StartsWith(kv.Key + "\\", StringComparison.OrdinalIgnoreCase))
                    {
                        return kv.Value + p.Substring(kv.Key.Length);
                    }
                    if (string.Equals(p, kv.Key, StringComparison.OrdinalIgnoreCase))
                    {
                        return kv.Value;
                    }
                }
            }
            return NormalizeDosOrNtPath(p);
        }

        private sealed class LockTargetSpec
        {
            public string Norm;
            public string Prefix;
            public bool IsSingleFile;
            public bool IsDirectory;
            public HashSet<string> DirExeNames;

            public bool MatchesPath(string dosPath)
            {
                if (string.IsNullOrEmpty(dosPath)) return false;
                if (IsDirectory)
                {
                    return dosPath.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase) ||
                           string.Equals(dosPath, Norm, StringComparison.OrdinalIgnoreCase);
                }
                return string.Equals(dosPath, Norm, StringComparison.OrdinalIgnoreCase);
            }
        }

        private static bool CollectProcessMappedFiles(int pid, string prefix, string exactNorm, bool isDirectory, Dictionary<string, string> dosMap, HashSet<string> matchedImagesOut, HashSet<string> matchedDataMappedOut)
        {
            var singleTarget = new LockTargetSpec
            {
                Norm = exactNorm ?? "",
                Prefix = prefix ?? "",
                IsSingleFile = !isDirectory,
                IsDirectory = isDirectory
            };
            var list = new List<LockTargetSpec>(1);
            list.Add(singleTarget);
            return CollectProcessMappedFilesMulti(pid, list, dosMap, true, matchedImagesOut, matchedDataMappedOut);
        }

        private static bool CollectProcessMappedFilesMulti(int pid, List<LockTargetSpec> targets, Dictionary<string, string> dosMap, bool includeImages, HashSet<string> matchedImagesOut, HashSet<string> matchedDataMappedOut)
        {
            IntPtr hProc = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, false, pid);
            if (hProc == IntPtr.Zero) return false;
            try
            {
                return CollectProcessMappedFilesFromHandle(hProc, targets, dosMap, includeImages, matchedImagesOut, matchedDataMappedOut);
            }
            finally
            {
                CloseHandle(hProc);
            }
        }

        private static bool CollectProcessMappedFilesFromHandle(IntPtr hProc, List<LockTargetSpec> targets, Dictionary<string, string> dosMap, bool includeImages, HashSet<string> matchedImagesOut, HashSet<string> matchedDataMappedOut)
        {
            if (hProc == IntPtr.Zero || targets == null || targets.Count == 0) return false;
            bool anyMatch = false;
            try
            {
                IntPtr addr = IntPtr.Zero;
                IntPtr mbiSz = new IntPtr(IntPtr.Size == 8 ? Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION_X64)) : Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION_X86)));
                var seenAlloc = new HashSet<long>();
                var sb = new System.Text.StringBuilder(1024);
                int regions = 0;
                while (regions < 32768)
                {
                    regions++;
                    IntPtr baseAddr;
                    IntPtr allocBase;
                    IntPtr regionSize;
                    uint state;
                    uint memType;
                    if (IntPtr.Size == 8)
                    {
                        MEMORY_BASIC_INFORMATION_X64 m64;
                        if (VirtualQueryEx64(hProc, addr, out m64, mbiSz) == IntPtr.Zero) break;
                        baseAddr = m64.BaseAddress;
                        allocBase = m64.AllocationBase;
                        regionSize = m64.RegionSize;
                        state = m64.State;
                        memType = m64.Type;
                    }
                    else
                    {
                        MEMORY_BASIC_INFORMATION_X86 m86;
                        if (VirtualQueryEx86(hProc, addr, out m86, mbiSz) == IntPtr.Zero) break;
                        baseAddr = m86.BaseAddress;
                        allocBase = m86.AllocationBase;
                        regionSize = m86.RegionSize;
                        state = m86.State;
                        memType = m86.Type;
                    }

                    bool checkRegion = (state == MEM_COMMIT) && (memType == MEM_MAPPED || (includeImages && memType == MEM_IMAGE));
                    if (checkRegion)
                    {
                        long ab = allocBase.ToInt64();
                        if (seenAlloc.Add(ab))
                        {
                            sb.Length = 0;
                            uint n = GetMappedFileNameW(hProc, baseAddr, sb, (uint)sb.Capacity);
                            if (n > 0 && n < (uint)sb.Capacity)
                            {
                                string dos = TranslateDevicePathToDos(sb.ToString(), dosMap);
                                if (!string.IsNullOrEmpty(dos))
                                {
                                    for (int ti = 0; ti < targets.Count; ti++)
                                    {
                                        if (targets[ti].MatchesPath(dos))
                                        {
                                            anyMatch = true;
                                            if (memType == MEM_IMAGE && matchedImagesOut != null) matchedImagesOut.Add(dos);
                                            if (memType == MEM_MAPPED && matchedDataMappedOut != null) matchedDataMappedOut.Add(dos);
                                            if (matchedImagesOut == null && matchedDataMappedOut == null) return true;
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    long nextAddr = unchecked(baseAddr.ToInt64() + regionSize.ToInt64());
                    if (nextAddr <= addr.ToInt64()) break;
                    addr = new IntPtr(nextAddr);
                }
            }
            catch {}
            return anyMatch;
        }

        private static Dictionary<int, List<MatchedRemoteHandle>> ScanSystemFileHandlesForTarget(string normTarget, string prefix, bool isDirectory)
        {
            if (string.IsNullOrWhiteSpace(normTarget)) return new Dictionary<int, List<MatchedRemoteHandle>>();
            var single = new LockTargetSpec
            {
                Norm = normTarget,
                Prefix = prefix ?? "",
                IsSingleFile = !isDirectory,
                IsDirectory = isDirectory
            };
            var list = new List<LockTargetSpec>(1);
            list.Add(single);
            return ScanSystemFileHandlesForTargets(list);
        }

        private static Dictionary<int, List<MatchedRemoteHandle>> ScanSystemFileHandlesForTargets(List<LockTargetSpec> targets)
        {
            var result = new Dictionary<int, List<MatchedRemoteHandle>>();
            if (targets == null || targets.Count == 0) return result;

            EnsureUnlockPrivileges();

            string probePath = Environment.SystemDirectory;
            for (int ti = 0; ti < targets.Count; ti++)
            {
                if (targets[ti].IsDirectory && Directory.Exists(targets[ti].Norm))
                {
                    probePath = targets[ti].Norm;
                    break;
                }
            }
            IntPtr hProbe = CreateFileW(probePath, 0x00100001, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero);
            if (hProbe == IntPtr.Zero || hProbe == new IntPtr(-1))
            {
                hProbe = CreateFileW(Environment.SystemDirectory, 0x00100001, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero);
            }
            if (hProbe == IntPtr.Zero || hProbe == new IntPtr(-1)) return result;

            int size = 4 * 1024 * 1024;
            IntPtr buf = Marshal.AllocHGlobal(size);
            try
            {
                int retLen = 0;
                int status;
                while ((status = NtQuerySystemInformation(SystemExtendedHandleInformation, buf, size, out retLen)) == STATUS_INFO_LENGTH_MISMATCH)
                {
                    Marshal.FreeHGlobal(buf);
                    size = Math.Max(size * 2, retLen + 65536);
                    if (size > 128 * 1024 * 1024) return result;
                    buf = Marshal.AllocHGlobal(size);
                }
                if (status != 0) return result;

                long count = (IntPtr.Size == 8) ? Marshal.ReadInt64(buf, 0) : Marshal.ReadInt32(buf, 0);
                int headerSize = IntPtr.Size * 2;
                int entrySize = (IntPtr.Size == 8) ? 40 : 28;
                int pidOff = IntPtr.Size;
                int hOff = IntPtr.Size * 2;
                int accOff = IntPtr.Size * 3;
                int typeOff = accOff + 6;
                int myPid = Process.GetCurrentProcess().Id;
                ulong myProbeVal = unchecked((ulong)hProbe.ToInt64());
                ushort fileTypeIndex = 0;
                bool foundFileType = false;

                for (long i = 0; i < count; i++)
                {
                    long baseAddr = buf.ToInt64() + headerSize + i * entrySize;
                    int p = (int)((IntPtr.Size == 8) ? Marshal.ReadInt64(new IntPtr(baseAddr + pidOff)) : Marshal.ReadInt32(new IntPtr(baseAddr + pidOff)));
                    if (p == myPid)
                    {
                        ulong hv = unchecked((ulong)((IntPtr.Size == 8) ? Marshal.ReadInt64(new IntPtr(baseAddr + hOff)) : Marshal.ReadInt32(new IntPtr(baseAddr + hOff))));
                        if (hv == myProbeVal)
                        {
                            fileTypeIndex = unchecked((ushort)Marshal.ReadInt16(new IntPtr(baseAddr + typeOff)));
                            foundFileType = true;
                            break;
                        }
                    }
                }
                if (!foundFileType) return result;

                var byPid = new Dictionary<int, List<MatchedRemoteHandle>>();
                for (long i = 0; i < count; i++)
                {
                    long baseAddr = buf.ToInt64() + headerSize + i * entrySize;
                    ushort ot = unchecked((ushort)Marshal.ReadInt16(new IntPtr(baseAddr + typeOff)));
                    if (ot != fileTypeIndex) continue;

                    int p = (int)((IntPtr.Size == 8) ? Marshal.ReadInt64(new IntPtr(baseAddr + pidOff)) : Marshal.ReadInt32(new IntPtr(baseAddr + pidOff)));
                    if (p <= 4 || p == myPid) continue;

                    uint acc = unchecked((uint)Marshal.ReadInt32(new IntPtr(baseAddr + accOff)));

                    long hv = (IntPtr.Size == 8) ? Marshal.ReadInt64(new IntPtr(baseAddr + hOff)) : Marshal.ReadInt32(new IntPtr(baseAddr + hOff));
                    List<MatchedRemoteHandle> hList;
                    if (!byPid.TryGetValue(p, out hList))
                    {
                        hList = new List<MatchedRemoteHandle>();
                        byPid[p] = hList;
                    }
                    hList.Add(new MatchedRemoteHandle { RemoteHandle = new IntPtr(hv), GrantedAccess = acc });
                }

                var pidItems = new KeyValuePair<int, List<MatchedRemoteHandle>>[byPid.Count];
                int idxCopy = 0;
                foreach (KeyValuePair<int, List<MatchedRemoteHandle>> kv in byPid)
                {
                    pidItems[idxCopy++] = kv;
                }

                IntPtr curProc = GetCurrentProcess();
                var concurrentResult = new ConcurrentDictionary<int, List<MatchedRemoteHandle>>();
                int cursor = -1;
                int workerCount = Math.Min(4, Math.Max(1, Math.Min(Environment.ProcessorCount, pidItems.Length)));
                Task[] workers = new Task[workerCount];

                for (int w = 0; w < workerCount; w++)
                {
                    workers[w] = Task.Run(delegate()
                    {
                        HandleWorkerState ws = StartHandleQueryWorker();
                        int timeouts = 0;
                        try
                        {
                            while (true)
                            {
                                int nextIdx = Interlocked.Increment(ref cursor);
                                if (nextIdx >= pidItems.Length || timeouts >= 12) break;
                                KeyValuePair<int, List<MatchedRemoteHandle>> kv = pidItems[nextIdx];
                                IntPtr hp = OpenProcess(PROCESS_DUP_HANDLE | PROCESS_QUERY_LIMITED_INFORMATION, false, kv.Key);
                                if (hp == IntPtr.Zero) continue;
                                List<MatchedRemoteHandle> localHits = null;
                                try
                                {
                                    List<MatchedRemoteHandle> list = kv.Value;
                                    for (int hi = 0; hi < list.Count; hi++)
                                    {
                                        if (timeouts >= 12) break;
                                        MatchedRemoteHandle mh = list[hi];
                                        IntPtr hDup;
                                        if (!DuplicateHandle(hp, mh.RemoteHandle, curProc, out hDup, 0, false, DUPLICATE_SAME_ACCESS)) continue;
                                        bool handleOrphaned = false;
                                        try
                                        {
                                            ws.PendingPath = null;
                                            ws.PendingHandle = hDup;
                                            ws.WorkEv.Set();
                                            if (ws.DoneEv.WaitOne(12))
                                            {
                                                string resolvedPath = ws.PendingPath;
                                                if (!string.IsNullOrEmpty(resolvedPath))
                                                {
                                                    bool hit = false;
                                                    for (int ti = 0; ti < targets.Count; ti++)
                                                    {
                                                        if (targets[ti].MatchesPath(resolvedPath))
                                                        {
                                                            hit = true;
                                                            break;
                                                        }
                                                    }
                                                    if (hit)
                                                    {
                                                        mh.DosPath = resolvedPath;
                                                        if (localHits == null) localHits = new List<MatchedRemoteHandle>();
                                                        localHits.Add(mh);
                                                    }
                                                }
                                            }
                                            else
                                            {
                                                timeouts++;
                                                if (ws.ThreadHandle != IntPtr.Zero) CancelSynchronousIo(ws.ThreadHandle);
                                                if (!ws.DoneEv.WaitOne(10))
                                                {
                                                    handleOrphaned = true;
                                                    ws.StopRequested = true;
                                                    try { if (ws.ThreadHandle != IntPtr.Zero) CloseHandle(ws.ThreadHandle); } catch {}
                                                    ws.ThreadHandle = IntPtr.Zero;
                                                    if (timeouts >= 12) break;
                                                    ws = StartHandleQueryWorker();
                                                }
                                            }
                                        }
                                        finally
                                        {
                                            if (!handleOrphaned)
                                            {
                                                CloseHandle(hDup);
                                            }
                                        }
                                    }
                                    if (localHits != null && localHits.Count > 0)
                                    {
                                        concurrentResult[kv.Key] = localHits;
                                    }
                                }
                                finally
                                {
                                    CloseHandle(hp);
                                }
                            }
                        }
                        finally
                        {
                            ws.StopRequested = true;
                            ws.WorkEv.Set();
                            if (ws.ThreadHandle != IntPtr.Zero) CloseHandle(ws.ThreadHandle);
                        }
                    });
                }
                Task.WaitAll(workers);

                foreach (KeyValuePair<int, List<MatchedRemoteHandle>> kv in concurrentResult)
                {
                    result[kv.Key] = kv.Value;
                }
            }
            catch {}
            finally
            {
                Marshal.FreeHGlobal(buf);
                CloseHandle(hProbe);
            }
            return result;
        }

        private static HandleWorkerState StartHandleQueryWorker()
        {
            HandleWorkerState state = new HandleWorkerState();
            Thread t = new Thread(delegate()
            {
                state.ThreadId = GetCurrentThreadId();
                var sb = new System.Text.StringBuilder(1024);
                try
                {
                    while (!state.StopRequested)
                    {
                        state.WorkEv.WaitOne();
                        if (state.StopRequested) break;
                        IntPtr h = state.PendingHandle;
                        string resolved = null;
                        if (h != IntPtr.Zero)
                        {
                            try
                            {
                                if (GetFileType(h) == FILE_TYPE_DISK)
                                {
                                    sb.Length = 0;
                                    uint n = GetFinalPathNameByHandleW(h, sb, (uint)sb.Capacity, 0);
                                    if (n > 0 && n < (uint)sb.Capacity)
                                    {
                                        resolved = NormalizeDosOrNtPath(sb.ToString());
                                    }
                                }
                            }
                            catch {}
                        }
                        state.PendingPath = resolved;
                        state.DoneEv.Set();
                    }
                }
                catch {}
                finally
                {
                    try { state.WorkEv.Close(); } catch {}
                    try { state.DoneEv.Close(); } catch {}
                }
            });
            t.IsBackground = true;
            t.Start();
            while (state.ThreadId == 0) Thread.Sleep(1);
            state.ThreadHandle = OpenThread(0x0001 | 0x0002, false, state.ThreadId);
            return state;
        }

        private static string ResolveSysinternalsHandleExe()
        {
            lock (_sysinternalsLock)
            {
                if (_sysinternalsChecked) return _cachedSysinternalsHandleExe;
                _sysinternalsChecked = true;
                _cachedSysinternalsHandleExe = "";

                try
                {
                    string[] exeNames = (IntPtr.Size == 8)
                        ? new string[] { "handle64.exe", "handle.exe" }
                        : new string[] { "handle.exe", "handle64.exe" };

                    string localApp = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                    if (!string.IsNullOrWhiteSpace(localApp))
                    {
                        string toolsDir = Path.Combine(localApp, @"DuckUtil\Tools");
                        foreach (string fn in exeNames)
                        {
                            string cand = Path.Combine(toolsDir, fn);
                            if (File.Exists(cand))
                            {
                                _cachedSysinternalsHandleExe = cand;
                                return _cachedSysinternalsHandleExe;
                            }
                        }
                    }

                    string pathEnv = Environment.GetEnvironmentVariable("PATH") ?? "";
                    string[] dirs = pathEnv.Split(new char[] { ';' }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (string rawDir in dirs)
                    {
                        string d = rawDir.Trim().Trim('\"');
                        if (string.IsNullOrEmpty(d)) continue;
                        foreach (string fn in exeNames)
                        {
                            try
                            {
                                string cand = Path.Combine(d, fn);
                                if (File.Exists(cand))
                                {
                                    _cachedSysinternalsHandleExe = cand;
                                    return _cachedSysinternalsHandleExe;
                                }
                            }
                            catch {}
                        }
                    }
                }
                catch {}
                return _cachedSysinternalsHandleExe;
            }
        }

        private static bool TryCloseHandleViaSysinternals(int pid, IntPtr remoteHandle)
        {
            if (pid <= 4 || remoteHandle == IntPtr.Zero) return false;
            string handleExe = ResolveSysinternalsHandleExe();
            if (string.IsNullOrEmpty(handleExe)) return false;
            try
            {
                string hexHandle = remoteHandle.ToInt64().ToString("X");
                var psi = new ProcessStartInfo(handleExe, "-accepteula -nobanner -c " + hexHandle + " -y -p " + pid.ToString());
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                using (var p = Process.Start(psi))
                {
                    if (p != null && p.WaitForExit(2000))
                    {
                        return (p.ExitCode == 0);
                    }
                }
            }
            catch {}
            return false;
        }

        private static bool TryCloseRemoteFileHandleDirect(int pid, IntPtr remoteHandle)
        {
            IntPtr hp = OpenProcess(PROCESS_DUP_HANDLE, false, pid);
            if (hp == IntPtr.Zero) return false;
            try
            {
                IntPtr hDummy;
                if (DuplicateHandle(hp, remoteHandle, GetCurrentProcess(), out hDummy, 0, false, DUPLICATE_CLOSE_SOURCE))
                {
                    if (hDummy != IntPtr.Zero) CloseHandle(hDummy);
                    return true;
                }
                return false;
            }
            catch
            {
                return false;
            }
            finally
            {
                CloseHandle(hp);
            }
        }

        private static bool TryCloseRemoteFileHandle(int pid, IntPtr remoteHandle)
        {
            if (TryCloseRemoteFileHandleDirect(pid, remoteHandle)) return true;

            bool closedAsSystem = false;
            RunWithSystemOrTrustedInstaller(false, delegate()
            {
                closedAsSystem = TryCloseRemoteFileHandleDirect(pid, remoteHandle);
            });
            if (closedAsSystem) return true;

            return TryCloseHandleViaSysinternals(pid, remoteHandle);
        }

        private static IntPtr GetCurrentTokenUserSidCopy()
        {
            IntPtr hTok;
            if (!OpenProcessToken(GetCurrentProcess(), 0x0008, out hTok)) return IntPtr.Zero;
            try
            {
                uint needed = 0;
                GetTokenInformation(hTok, 1, IntPtr.Zero, 0, out needed);
                if (needed == 0) return IntPtr.Zero;
                IntPtr tokBuf = Marshal.AllocHGlobal((int)needed);
                try
                {
                    if (!GetTokenInformation(hTok, 1, tokBuf, needed, out needed)) return IntPtr.Zero;
                    IntPtr srcSid = Marshal.ReadIntPtr(tokBuf, 0);
                    if (srcSid == IntPtr.Zero) return IntPtr.Zero;
                    int subCount = Marshal.ReadByte(srcSid, 1) & 0xFF;
                    int sidLen = 8 + subCount * 4;
                    byte[] raw = new byte[sidLen];
                    Marshal.Copy(srcSid, raw, 0, sidLen);
                    IntPtr sidCopy = Marshal.AllocHGlobal(sidLen);
                    Marshal.Copy(raw, 0, sidCopy, sidLen);
                    return sidCopy;
                }
                finally
                {
                    Marshal.FreeHGlobal(tokBuf);
                }
            }
            finally
            {
                CloseHandle(hTok);
            }
        }

        private static bool TryTakeOwnershipAndGrantAdminAccessCore(string norm, bool isDir)
        {
            var auth = new SID_IDENTIFIER_AUTHORITY { Value0 = 0, Value1 = 0, Value2 = 0, Value3 = 0, Value4 = 0, Value5 = 5 };
            IntPtr adminSid = IntPtr.Zero;
            IntPtr userSid = IntPtr.Zero;
            IntPtr newAcl = IntPtr.Zero;
            try
            {
                if (!AllocateAndInitializeSid(ref auth, 2, 32, 544, 0, 0, 0, 0, 0, 0, out adminSid))
                {
                    return false;
                }

                IntPtr grantSid = adminSid;
                uint trusteeType = TRUSTEE_IS_GROUP;
                uint ownerErr = SetNamedSecurityInfoW(norm, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION, adminSid, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
                if (ownerErr == 1307)
                {
                    userSid = GetCurrentTokenUserSidCopy();
                    if (userSid != IntPtr.Zero)
                    {
                        ownerErr = SetNamedSecurityInfoW(norm, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION, userSid, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
                        if (ownerErr == 0)
                        {
                            grantSid = userSid;
                            trusteeType = TRUSTEE_IS_USER;
                        }
                    }
                }

                var ea = new EXPLICIT_ACCESS();
                ea.grfAccessPermissions = GENERIC_ALL;
                ea.grfAccessMode = SET_ACCESS;
                ea.grfInheritance = isDir ? SUB_CONTAINERS_AND_OBJECTS_INHERIT : NO_INHERITANCE;
                ea.Trustee.TrusteeForm = TRUSTEE_IS_SID;
                ea.Trustee.TrusteeType = trusteeType;
                ea.Trustee.ptstrName = grantSid;

                if (SetEntriesInAclW(1, ref ea, IntPtr.Zero, out newAcl) != 0)
                {
                    return ownerErr == 0;
                }

                uint daclErr = SetNamedSecurityInfoW(norm, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION, IntPtr.Zero, IntPtr.Zero, newAcl, IntPtr.Zero);
                return (daclErr == 0);
            }
            catch
            {
                return false;
            }
            finally
            {
                if (newAcl != IntPtr.Zero) LocalFree(newAcl);
                if (userSid != IntPtr.Zero) Marshal.FreeHGlobal(userSid);
                if (adminSid != IntPtr.Zero) FreeSid(adminSid);
            }
        }

        public static bool TryTakeOwnershipAndGrantAdminAccess(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return false;
            string norm = path.Trim().TrimEnd('\\');
            bool isDir = Directory.Exists(norm);
            bool isFile = !isDir && File.Exists(norm);
            if (!isDir && !isFile) return false;
            if (IsReparsePoint(norm)) return false;

            string checkDir = isDir ? norm : Path.GetDirectoryName(norm);
            if (!IsSafeLockTargetDirectory(checkDir) && !(isFile && IsVerifiedRogueKernelDriverFile(norm))) return false;

            EnsureUnlockPrivileges();

            if (TryTakeOwnershipAndGrantAdminAccessCore(norm, isDir))
            {
                return true;
            }

            bool elevatedOk = false;
            RunWithSystemOrTrustedInstaller(true, delegate()
            {
                elevatedOk = TryTakeOwnershipAndGrantAdminAccessCore(norm, isDir);
            });
            return elevatedOk;
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
                string sys32 = Environment.GetFolderPath(Environment.SpecialFolder.System);
                if (!string.IsNullOrWhiteSpace(sys32))
                {
                    blocked.Add(Path.Combine(sys32, "drivers").TrimEnd('\\'));
                }
                string sys86 = Environment.GetFolderPath(Environment.SpecialFolder.SystemX86);
                if (!string.IsNullOrWhiteSpace(sys86))
                {
                    blocked.Add(Path.Combine(sys86, "drivers").TrimEnd('\\'));
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

        public static bool IsVerifiedRogueKernelDriverFile(string filePath)
        {
            if (string.IsNullOrWhiteSpace(filePath)) return false;
            try
            {
                string full = Path.GetFullPath(filePath.Trim());
                if (!full.EndsWith(".sys", StringComparison.OrdinalIgnoreCase)) return false;
                if (!File.Exists(full)) return false;

                string sysDrivers = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "drivers");
                string dir = Path.GetDirectoryName(full) ?? "";
                if (!string.Equals(dir.TrimEnd('\\'), sysDrivers.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)) return false;

                string fn = Path.GetFileName(full);
                string comp = "";
                string prod = "";
                string desc = "";
                try
                {
                    FileVersionInfo fvi = FileVersionInfo.GetVersionInfo(full);
                    comp = fvi.CompanyName ?? "";
                    prod = fvi.ProductName ?? "";
                    desc = fvi.FileDescription ?? "";
                }
                catch {}
                string cert = GetSignerSubject(full);
                string combined = fn + " | " + comp + " | " + prod + " | " + desc + " | " + cert;

                if (combined.IndexOf("Microsoft Corporation", StringComparison.OrdinalIgnoreCase) >= 0 &&
                    combined.IndexOf("360", StringComparison.OrdinalIgnoreCase) < 0 &&
                    combined.IndexOf("Qihu", StringComparison.OrdinalIgnoreCase) < 0 &&
                    combined.IndexOf("Qihoo", StringComparison.OrdinalIgnoreCase) < 0 &&
                    combined.IndexOf("2345", StringComparison.OrdinalIgnoreCase) < 0 &&
                    combined.IndexOf("Kingsoft", StringComparison.OrdinalIgnoreCase) < 0 &&
                    combined.IndexOf("Baidu", StringComparison.OrdinalIgnoreCase) < 0)
                {
                    return false;
                }

                string[] rogueTokens = new string[]
                {
                    "360.cn", "360Total", "360Safe", "360\u5B89\u5168\u536B\u58EB", "Beijing Qihu", "Qihoo 360",
                    "360FsFlt", "360disproc", "360Box", "360AntiHacker", "360netmon", "360reskit",
                    "BAPIDRV", "dsark", "360SelfProtection", "360AvFlt", "360Hvm", "360qpesv", "360Camera",
                    "2345.com", "2345Safe", "Kingsoft", "KWatch", "KisKrnl", "Baidu"
                };
                foreach (string tok in rogueTokens)
                {
                    if (combined.IndexOf(tok, StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        return true;
                    }
                }
                return false;
            }
            catch
            {
                return false;
            }
        }

        public static bool TryPosixUnlinkFile(string filePath)
        {
            if (string.IsNullOrWhiteSpace(filePath)) return false;
            string norm = filePath.Trim();
            if (!File.Exists(norm)) return true;

            EnsureUnlockPrivileges();

            IntPtr h = CreateFileW(norm, DELETE_ACCESS | 0x0100, 0x00000001 | 0x00000002 | 0x00000004, IntPtr.Zero, 3, 0x02000000 | 0x00200000, IntPtr.Zero);
            if (h == IntPtr.Zero || h == new IntPtr(-1))
            {
                h = CreateFileW(norm, DELETE_ACCESS, 0x00000001 | 0x00000002 | 0x00000004, IntPtr.Zero, 3, 0x02000000 | 0x00200000, IntPtr.Zero);
            }
            if (h == IntPtr.Zero || h == new IntPtr(-1)) return false;

            int st = -1;
            try
            {
                IO_STATUS_BLOCK iosb;
                var info = new FILE_DISPOSITION_INFO_EX { Flags = 0x00000017 };
                st = NtSetInformationFile(h, out iosb, ref info, 4, 64);
                if (st != 0)
                {
                    info.Flags = 0x00000013;
                    st = NtSetInformationFile(h, out iosb, ref info, 4, 64);
                }
            }
            catch {}
            finally
            {
                CloseHandle(h);
            }
            return (st == 0 && !File.Exists(norm));
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
                            string.Equals(ext, ".cpl", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".db", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".sqlite", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".dat", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".lock", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".log", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".asar", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".pak", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(ext, ".ttf", StringComparison.OrdinalIgnoreCase))
                        {
                            filesToCheck.Add(f);
                            if (filesToCheck.Count >= 400) break;
                        }
                        else if (secondary.Count < 120)
                        {
                            secondary.Add(f);
                        }
                    }
                }
                catch {}

                foreach (string sf in secondary)
                {
                    if (filesToCheck.Count >= 400) break;
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

                int batchSize = 80;
                for (int offset = 0; offset < filesToCheck.Count; offset += batchSize)
                {
                    int take = Math.Min(batchSize, filesToCheck.Count - offset);
                    string[] batch = new string[take];
                    filesToCheck.CopyTo(offset, batch, 0, take);
                    RmRegisterResources(session, (uint)batch.Length, batch, 0, null, 0, null);
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
            try { norm = Path.GetFullPath(norm).TrimEnd('\\'); } catch {}
            if (norm.Length <= 3) return false;
            bool isDir = Directory.Exists(norm);
            bool isFile = !isDir && File.Exists(norm);
            if (!isDir && !isFile) return true;
            if (IsReparsePoint(norm)) return false;
            if (!IsSafeLockTargetDirectory(isDir ? norm : Path.GetDirectoryName(norm))) return false;

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

        public static Task<bool> MoveToRecycleBinSilentlyAsync(string targetPath)
        {
            return Task.Run(delegate() { return MoveToRecycleBinSilently(targetPath); });
        }

        private sealed class ProcessScanOutcome
        {
            public Process Proc;
            public int Pid;
            public string ProcName;
            public bool IsCritical;
            public bool IsProtectedHost;
            public bool IsMatch;
            public bool DidModuleScan;
            public HashSet<string> LoadedImages;
            public HashSet<string> MappedData;
        }

        public static ForceStopReport ForceStopDirectoryLockers(string targetPath)
        {
            return ForceStopDirectoryLockers(targetPath, true);
        }

        public static ForceStopReport ForceStopDirectoryLockers(string targetPath, bool includeServicesAndTasks)
        {
            if (string.IsNullOrWhiteSpace(targetPath)) return new ForceStopReport();
            return ForceStopPathsLockers(new string[] { targetPath }, includeServicesAndTasks);
        }

        public static ForceStopReport ForceStopBatchDirectories(string[] targetPaths, bool includeServicesAndTasks)
        {
            return ForceStopPathsLockers(targetPaths, includeServicesAndTasks);
        }

        public static Task<ForceStopReport> ForceStopDirectoryLockersAsync(string targetPath, bool includeServicesAndTasks)
        {
            return Task.Run(delegate() { return ForceStopDirectoryLockers(targetPath, includeServicesAndTasks); });
        }

        public static Task<ForceStopReport> ForceStopBatchDirectoriesAsync(string[] targetPaths, bool includeServicesAndTasks)
        {
            return Task.Run(delegate() { return ForceStopBatchDirectories(targetPaths, includeServicesAndTasks); });
        }

        private static bool ScanProcessModulesNative(IntPtr hProc, List<LockTargetSpec> targets, bool collectAllMatched, HashSet<string> matchedImagesOut, out bool enumSucceeded)
        {
            enumSucceeded = false;
            if (hProc == IntPtr.Zero || targets == null || targets.Count == 0) return false;
            IntPtr[] hMods = new IntPtr[256];
            uint cb = (uint)(hMods.Length * IntPtr.Size);
            uint needed = 0;
            if (!EnumProcessModulesEx(hProc, hMods, cb, out needed, LIST_MODULES_ALL))
            {
                return false;
            }
            if (needed > cb)
            {
                int countNeed = Math.Min(4096, (int)(needed / (uint)IntPtr.Size) + 16);
                hMods = new IntPtr[countNeed];
                cb = (uint)(hMods.Length * IntPtr.Size);
                if (!EnumProcessModulesEx(hProc, hMods, cb, out needed, LIST_MODULES_ALL))
                {
                    return false;
                }
            }
            enumSucceeded = true;
            int modCount = Math.Min(hMods.Length, (int)(needed / (uint)IntPtr.Size));
            var sb = new System.Text.StringBuilder(1024);
            bool anyMatch = false;
            for (int i = 0; i < modCount; i++)
            {
                if (hMods[i] == IntPtr.Zero) continue;
                sb.Length = 0;
                uint len = GetModuleFileNameExW(hProc, hMods[i], sb, (uint)sb.Capacity);
                if (len > 0 && len < (uint)sb.Capacity)
                {
                    string modPath = NormalizeDosOrNtPath(sb.ToString());
                    if (string.IsNullOrEmpty(modPath)) continue;
                    for (int ti = 0; ti < targets.Count; ti++)
                    {
                        if (targets[ti].MatchesPath(modPath))
                        {
                            anyMatch = true;
                            if (matchedImagesOut != null) matchedImagesOut.Add(modPath);
                            if (!collectAllMatched) return true;
                            break;
                        }
                    }
                }
            }
            return anyMatch;
        }

        private static ForceStopReport ForceStopPathsLockers(string[] targetPaths, bool includeServicesAndTasks)
        {
            var report = new ForceStopReport();
            if (targetPaths == null || targetPaths.Length == 0) return report;

            var targets = new List<LockTargetSpec>();
            var seenNorms = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            bool hasAnyDirectory = false;

            for (int i = 0; i < targetPaths.Length; i++)
            {
                string raw = targetPaths[i];
                if (string.IsNullOrWhiteSpace(raw)) continue;
                string norm = raw.Trim().TrimEnd('\\');
                try { norm = Path.GetFullPath(norm).TrimEnd('\\'); } catch {}
                if (norm.Length <= 3 || !seenNorms.Add(norm)) continue;

                bool isSingleFile = File.Exists(norm);
                bool isDirectory = !isSingleFile && Directory.Exists(norm);
                if (!isSingleFile && !isDirectory) continue;
                if (isDirectory && !IsSafeLockTargetDirectory(norm)) continue;

                if (isDirectory) hasAnyDirectory = true;
                targets.Add(new LockTargetSpec
                {
                    Norm = norm,
                    Prefix = isDirectory ? (norm + "\\") : "",
                    IsSingleFile = isSingleFile,
                    IsDirectory = isDirectory,
                    DirExeNames = isDirectory ? CollectExeBaseNamesInDirectory(norm) : new HashSet<string>(StringComparer.OrdinalIgnoreCase)
                });
            }

            if (targets.Count == 0) return report;

            EnsureUnlockPrivileges();

            Dictionary<string, string> dosMap = BuildDosDeviceMap();
            var rmLockers = new Dictionary<int, string>();
            int svcStoppedTotal = 0;
            int taskRemovedTotal = 0;

            Task leg1ServicesAndRm = Task.Run(delegate()
            {
                for (int i = 0; i < targets.Count; i++)
                {
                    LockTargetSpec t = targets[i];
                    if (includeServicesAndTasks && t.IsDirectory)
                    {
                        svcStoppedTotal += DisableAndRemoveServicesInDirectory(t.Norm);
                        taskRemovedTotal += RemoveScheduledTasksInDirectory(t.Norm);
                    }
                    Dictionary<int, string> subRm = GetRestartManagerLockingPids(t.Norm);
                    foreach (KeyValuePair<int, string> kv in subRm)
                    {
                        if (!rmLockers.ContainsKey(kv.Key))
                        {
                            rmLockers[kv.Key] = kv.Value;
                        }
                    }
                }
            });

            Dictionary<int, List<MatchedRemoteHandle>> handleLockers = null;
            Task leg2Handles = Task.Run(delegate()
            {
                handleLockers = ScanSystemFileHandlesForTargets(targets);
            });

            Process[] procs = null;
            try { procs = Process.GetProcesses(); } catch { procs = new Process[0]; }
            var outcomes = new ProcessScanOutcome[procs.Length];

            Task leg3Processes = Task.Run(delegate()
            {
                Parallel.For(0, procs.Length, delegate(int idx)
                {
                    Process p = procs[idx];
                    if (p == null) return;
                    var outcome = new ProcessScanOutcome { Proc = p };
                    try
                    {
                        int pid = p.Id;
                        if (pid <= 4) return;
                        string pName = "";
                        try { pName = p.ProcessName ?? ""; } catch {}
                        outcome.Pid = pid;
                        outcome.ProcName = pName;
                        outcome.IsCritical = IsKernelCriticalProcess(pid, pName);
                        if (outcome.IsCritical)
                        {
                            outcomes[idx] = outcome;
                            return;
                        }
                        outcome.IsProtectedHost = IsProtectedSystemOrHostProcess(pid, pName);

                        bool scanModulesHere = !outcome.IsProtectedHost || hasAnyDirectory;
                        if (scanModulesHere)
                        {
                            IntPtr hProc = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, false, pid);
                            bool hasVmRead = (hProc != IntPtr.Zero);
                            if (hProc == IntPtr.Zero)
                            {
                                hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
                            }

                            if (hProc == IntPtr.Zero)
                            {
                                if (!outcome.IsProtectedHost && !string.IsNullOrEmpty(pName))
                                {
                                    for (int ti = 0; ti < targets.Count; ti++)
                                    {
                                        if (targets[ti].IsDirectory && targets[ti].DirExeNames.Contains(pName))
                                        {
                                            outcome.IsMatch = true;
                                            break;
                                        }
                                    }
                                }
                            }
                            else
                            {
                                try
                                {
                                    outcome.DidModuleScan = true;
                                    if (outcome.IsProtectedHost)
                                    {
                                        var loadedImgs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                                        var mappedDat = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                                        bool enumOk = false;
                                        if (hasVmRead)
                                        {
                                            ScanProcessModulesNative(hProc, targets, true, loadedImgs, out enumOk);
                                            CollectProcessMappedFilesFromHandle(hProc, targets, dosMap, !enumOk, enumOk ? null : loadedImgs, mappedDat);
                                        }
                                        outcome.LoadedImages = loadedImgs;
                                        outcome.MappedData = mappedDat;
                                    }
                                    else
                                    {
                                        var sbImg = new System.Text.StringBuilder(1024);
                                        uint sz = (uint)sbImg.Capacity;
                                        bool gotMain = QueryFullProcessImageNameW(hProc, 0, sbImg, ref sz);
                                        if (gotMain && sz > 0)
                                        {
                                            string mainPath = NormalizeDosOrNtPath(sbImg.ToString(0, (int)sz));
                                            for (int ti = 0; ti < targets.Count; ti++)
                                            {
                                                if (targets[ti].MatchesPath(mainPath))
                                                {
                                                    outcome.IsMatch = true;
                                                    break;
                                                }
                                            }
                                        }
                                        if (!outcome.IsMatch && hasVmRead && hasAnyDirectory)
                                        {
                                            bool enumOk = false;
                                            if (ScanProcessModulesNative(hProc, targets, false, null, out enumOk))
                                            {
                                                outcome.IsMatch = true;
                                            }
                                            else if (CollectProcessMappedFilesFromHandle(hProc, targets, dosMap, !enumOk, null, null))
                                            {
                                                outcome.IsMatch = true;
                                            }
                                        }
                                        else if (!outcome.IsMatch && hasVmRead && !hasAnyDirectory)
                                        {
                                            if (CollectProcessMappedFilesFromHandle(hProc, targets, dosMap, true, null, null))
                                            {
                                                outcome.IsMatch = true;
                                            }
                                        }
                                        if (!outcome.IsMatch && !gotMain && !string.IsNullOrEmpty(pName))
                                        {
                                            for (int ti = 0; ti < targets.Count; ti++)
                                            {
                                                if (targets[ti].IsDirectory && targets[ti].DirExeNames.Contains(pName))
                                                {
                                                    outcome.IsMatch = true;
                                                    break;
                                                }
                                            }
                                        }
                                    }
                                }
                                finally
                                {
                                    CloseHandle(hProc);
                                }
                            }
                        }
                        outcomes[idx] = outcome;
                    }
                    catch {}
                });
            });

            Task.WaitAll(leg1ServicesAndRm, leg2Handles, leg3Processes);

            report.ServicesStoppedCount = svcStoppedTotal;
            report.TasksRemovedCount = taskRemovedTotal;
            if (handleLockers == null) handleLockers = new Dictionary<int, List<MatchedRemoteHandle>>();

            var killedList = new List<string>();
            var deniedList = new List<string>();
            var skippedSystem = new List<string>();
            var closedHandleList = new List<string>();
            var seenNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var targetProcs = new Dictionary<int, Process>();

            for (int idx = 0; idx < procs.Length; idx++)
            {
                Process p = procs[idx];
                ProcessScanOutcome o = outcomes[idx];
                bool keepProc = false;
                try
                {
                    if (o == null || o.Pid <= 4) continue;
                    int pid = o.Pid;
                    string pName = o.ProcName ?? "";
                    bool rmMatched = rmLockers.ContainsKey(pid);
                    List<MatchedRemoteHandle> pidHandles = null;
                    handleLockers.TryGetValue(pid, out pidHandles);

                    if (o.IsCritical)
                    {
                        if (rmMatched)
                        {
                            string desc = pName + " (PID " + pid.ToString() + ")";
                            if (!skippedSystem.Contains(desc)) skippedSystem.Add(desc);
                        }
                        continue;
                    }

                    if (o.IsProtectedHost)
                    {
                        var loadedImages = o.LoadedImages ?? new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                        var mappedData = o.MappedData ?? new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                        if (!o.DidModuleScan && (rmMatched || pidHandles != null))
                        {
                            IntPtr hHost = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, false, pid);
                            if (hHost != IntPtr.Zero)
                            {
                                try
                                {
                                    bool enumOk = false;
                                    ScanProcessModulesNative(hHost, targets, true, loadedImages, out enumOk);
                                    CollectProcessMappedFilesFromHandle(hHost, targets, dosMap, !enumOk, enumOk ? null : loadedImages, mappedData);
                                }
                                finally
                                {
                                    CloseHandle(hHost);
                                }
                            }
                        }

                        int closedForPid = 0;
                        if (pidHandles != null && pidHandles.Count > 0)
                        {
                            foreach (MatchedRemoteHandle mh in pidHandles)
                            {
                                if (loadedImages.Contains(mh.DosPath)) continue;
                                if (TryCloseRemoteFileHandle(pid, mh.RemoteHandle))
                                {
                                    closedForPid++;
                                    report.ClosedHandlesCount++;
                                    string hLabel = pName + " -> " + (string.IsNullOrEmpty(mh.DosPath) ? targets[0].Norm : Path.GetFileName(mh.DosPath));
                                    if (seenNames.Add("H:" + hLabel + ":" + mh.RemoteHandle.ToString()))
                                    {
                                        if (closedHandleList.Count < 25) closedHandleList.Add(hLabel);
                                    }
                                }
                            }
                        }

                        if (loadedImages.Count > 0 || mappedData.Count > 0 || (rmMatched && closedForPid == 0 && (string.Equals(pName, "explorer", StringComparison.OrdinalIgnoreCase) || string.Equals(pName, "svchost", StringComparison.OrdinalIgnoreCase))))
                        {
                            string firstImg = "";
                            foreach (string img in loadedImages) { firstImg = img; break; }
                            if (string.IsNullOrEmpty(firstImg))
                            {
                                foreach (string md in mappedData) { firstImg = md; break; }
                            }
                            string desc = string.IsNullOrEmpty(firstImg)
                                ? (pName + " (PID " + pid.ToString() + ")")
                                : (pName + " (" + Path.GetFileName(firstImg) + ")");
                            if (!skippedSystem.Contains(desc)) skippedSystem.Add(desc);
                        }
                        continue;
                    }

                    bool isMatch = rmMatched || (pidHandles != null && pidHandles.Count > 0) || o.IsMatch;
                    if (isMatch && !targetProcs.ContainsKey(pid))
                    {
                        targetProcs[pid] = p;
                        keepProc = true;
                    }
                }
                catch {}
                finally
                {
                    if (!keepProc && p != null)
                    {
                        try { p.Dispose(); } catch {}
                    }
                }
            }

            foreach (KeyValuePair<int, Process> kvp in targetProcs)
            {
                try
                {
                    NtSuspendProcess(kvp.Value.Handle);
                }
                catch {}
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
                    mp.Kill();
                    if (mp.WaitForExit(1500) || mp.HasExited)
                    {
                        terminated = true;
                    }
                    else
                    {
                        terminated = TryTaskkillPidTree(pid);
                    }
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

            if (report.KilledCount > 0 || report.ServicesStoppedCount > 0 || report.ClosedHandlesCount > 0)
            {
                try { Thread.Sleep(180); } catch {}
            }

            report.KilledNames = killedList.ToArray();
            report.AccessDeniedNames = deniedList.ToArray();
            report.SkippedSystemLockers = skippedSystem.ToArray();
            report.ClosedHandleNames = closedHandleList.ToArray();
            return report;
        }

        public static int StopProcessesInDirectory(string targetDir)
        {
            ForceStopReport rpt = ForceStopDirectoryLockers(targetDir, false);
            return rpt.KilledCount;
        }

        private static string NormalizeServiceImagePath(string rawImgPath)
        {
            if (string.IsNullOrWhiteSpace(rawImgPath)) return "";
            string s = rawImgPath.Trim('\"', ' ');
            if (s.StartsWith(@"\??\", StringComparison.OrdinalIgnoreCase))
            {
                s = s.Substring(4);
            }
            if (s.StartsWith(@"\SystemRoot\", StringComparison.OrdinalIgnoreCase))
            {
                s = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), s.Substring(12));
            }
            try { s = Environment.ExpandEnvironmentVariables(s); } catch {}
            return s.Trim('\"', ' ');
        }

        private static void StopSingleServiceHandleAndWait(IntPtr hSvc)
        {
            if (hSvc == IntPtr.Zero) return;
            try
            {
                SERVICE_STATUS st;
                ControlService(hSvc, SERVICE_CONTROL_STOP, out st);
                int waited = 0;
                while (waited < 1200)
                {
                    SERVICE_STATUS cur;
                    if (!QueryServiceStatus(hSvc, out cur) || cur.dwCurrentState == SERVICE_STOPPED) break;
                    Thread.Sleep(80);
                    waited += 80;
                }
            }
            catch {}
        }

        private static readonly HashSet<string> _protectedWindowsFilters = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "FltMgr", "FileInfo", "Wof", "WdFilter", "MsSecFlt", "WinDefend", "Sense",
            "wcifs", "luafv", "storqosflt", "bindflt", "cldflt", "bfs", "npsvctrig",
            "FileCrypt", "tbs", "Csc", "dfsc", "mup", "mrxdav", "mrxsmb", "rdbss",
            "srv2", "namedpipe", "msfs", "ntfs", "fastfat", "exfat", "refs", "volsnap",
            "fvevol", "iorate", "rdyboost", "mountmgr", "partmgr", "disk", "acpi",
            "pci", "ksecdd", "cng", "tcpip", "afd", "ndis", "nsiproxy", "sysmondrv", "procmon24"
        };

        public static bool IsSafeNonMicrosoftFilterTarget(string svcName)
        {
            if (string.IsNullOrWhiteSpace(svcName)) return false;
            string clean = svcName.Trim();
            if (_protectedWindowsFilters.Contains(clean)) return false;

            try
            {
                using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                using (var sk = baseKey.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\" + clean, false))
                {
                    if (sk == null) return false;
                    string rawImg = sk.GetValue("ImagePath") as string;
                    string imgPath = NormalizeServiceImagePath(rawImg);
                    if (string.IsNullOrEmpty(imgPath)) return false;

                    int exePos = imgPath.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
                    if (exePos > 0) imgPath = imgPath.Substring(0, exePos + 4).Trim('\"', ' ');
                    else
                    {
                        int sysPos = imgPath.IndexOf(".sys", StringComparison.OrdinalIgnoreCase);
                        if (sysPos > 0) imgPath = imgPath.Substring(0, sysPos + 4).Trim('\"', ' ');
                    }

                    string dispName = ((sk.GetValue("DisplayName") as string) ?? "").Trim();
                    if (dispName.StartsWith("Microsoft ", StringComparison.OrdinalIgnoreCase) ||
                        dispName.StartsWith("@%SystemRoot%", StringComparison.OrdinalIgnoreCase) ||
                        dispName.StartsWith("@%windir%", StringComparison.OrdinalIgnoreCase) ||
                        dispName.StartsWith("@SystemRoot", StringComparison.OrdinalIgnoreCase))
                    {
                        return false;
                    }

                    string winDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows).TrimEnd('\\');
                    if (imgPath.StartsWith(@"system32\", StringComparison.OrdinalIgnoreCase) ||
                        imgPath.StartsWith(@"syswow64\", StringComparison.OrdinalIgnoreCase))
                    {
                        imgPath = Path.Combine(winDir, imgPath);
                    }

                    string fullImg = imgPath;
                    try { fullImg = Path.GetFullPath(imgPath); } catch {}

                    if (fullImg.IndexOf(@"\Microsoft Update Health Tools\", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        fullImg.IndexOf(@"\Windows Defender", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        fullImg.IndexOf(@"\Windows Security", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        fullImg.IndexOf(@"\Windows NT\", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        fullImg.IndexOf(@"\Microsoft.NET\", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        return false;
                    }

                    if (fullImg.StartsWith(winDir + "\\", StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(fullImg, winDir, StringComparison.OrdinalIgnoreCase))
                    {
                        return IsVerifiedRogueKernelDriverFile(fullImg);
                    }

                    string parentDir = Path.GetDirectoryName(fullImg);
                    if (!IsSafeLockTargetDirectory(parentDir)) return false;

                    if (File.Exists(fullImg))
                    {
                        string comp = "";
                        try { comp = FileVersionInfo.GetVersionInfo(fullImg).CompanyName ?? ""; } catch {}
                        string cert = GetSignerSubject(fullImg);
                        if (comp.IndexOf("Microsoft Corporation", StringComparison.OrdinalIgnoreCase) >= 0 ||
                            cert.IndexOf("Microsoft Corporation", StringComparison.OrdinalIgnoreCase) >= 0)
                        {
                            return false;
                        }
                    }
                    return true;
                }
            }
            catch
            {
                return false;
            }
        }

        private static void DetachMinifilterFromAllVolumes(string svcName)
        {
            if (!IsSafeNonMicrosoftFilterTarget(svcName)) return;
            string clean = svcName.Trim();
            EnsureUnlockPrivileges();
            const int FLT_NOT_FOUND = unchecked((int)0x801F000F);
            const int FLT_VOL_NOT_FOUND = unchecked((int)0x801F0014);
            const int FLT_INST_NOT_FOUND = unchecked((int)0x801F0015);
            try
            {
                foreach (string drv in Directory.GetLogicalDrives())
                {
                    if (string.IsNullOrEmpty(drv) || drv.Length < 2) continue;
                    string vol = drv.Substring(0, 2);
                    int hr = -1;
                    try
                    {
                        hr = FilterDetach(clean, vol, null);
                        if (hr == FLT_NOT_FOUND) break;
                        if (hr != 0 && hr != FLT_VOL_NOT_FOUND && hr != FLT_INST_NOT_FOUND)
                        {
                            hr = FilterDetach(clean, drv, null);
                            if (hr == FLT_NOT_FOUND) break;
                        }
                    }
                    catch {}
                    if (hr != 0 && hr != FLT_NOT_FOUND && hr != FLT_VOL_NOT_FOUND && hr != FLT_INST_NOT_FOUND)
                    {
                        RunHiddenProcess("fltmc.exe", "detach \"" + clean + "\" " + vol, 900);
                    }
                }
            }
            catch {}
        }

        public static bool TryUnloadMinifilterDirect(string svcName)
        {
            if (!IsSafeNonMicrosoftFilterTarget(svcName)) return false;
            string clean = svcName.Trim();
            EnsureUnlockPrivileges();
            DetachMinifilterFromAllVolumes(clean);

            int hr = -1;
            try
            {
                hr = FilterUnload(clean);
            }
            catch {}

            if (hr != 0 && hr != unchecked((int)0x801F000F))
            {
                RunWithSystemOrTrustedInstaller(true, delegate()
                {
                    DetachMinifilterFromAllVolumes(clean);
                    try { hr = FilterUnload(clean); } catch {}
                });
            }

            if (hr != 0 && hr != unchecked((int)0x801F000F))
            {
                RunHiddenProcess("fltmc.exe", "unload \"" + clean + "\"", 1500);
            }

            return (hr == 0 || hr == unchecked((int)0x801F000F));
        }

        private static bool TryStopAndDeleteViaScm(IntPtr hScm, string svcName, bool isDriver)
        {
            if (isDriver)
            {
                TryUnloadMinifilterDirect(svcName);
            }
            if (hScm == IntPtr.Zero) return false;
            IntPtr hSvc = OpenServiceW(hScm, svcName, SERVICE_STOP | SERVICE_QUERY_STATUS | SERVICE_ENUMERATE_DEPENDENTS | DELETE_ACCESS);
            if (hSvc == IntPtr.Zero)
            {
                hSvc = OpenServiceW(hScm, svcName, SERVICE_STOP | SERVICE_QUERY_STATUS | DELETE_ACCESS);
            }
            if (hSvc == IntPtr.Zero) return false;
            try
            {
                uint needed = 0;
                uint depCount = 0;
                EnumDependentServicesW(hSvc, SERVICE_ACTIVE, IntPtr.Zero, 0, out needed, out depCount);
                if (needed > 0 && needed < 1048576)
                {
                    IntPtr depBuf = Marshal.AllocHGlobal((int)needed);
                    try
                    {
                        if (EnumDependentServicesW(hSvc, SERVICE_ACTIVE, depBuf, needed, out needed, out depCount))
                        {
                            int esSz = Marshal.SizeOf(typeof(ENUM_SERVICE_STATUS));
                            for (int i = 0; i < (int)depCount; i++)
                            {
                                ENUM_SERVICE_STATUS ess = (ENUM_SERVICE_STATUS)Marshal.PtrToStructure(new IntPtr(depBuf.ToInt64() + i * esSz), typeof(ENUM_SERVICE_STATUS));
                                string depName = Marshal.PtrToStringUni(ess.lpServiceName);
                                if (!string.IsNullOrWhiteSpace(depName))
                                {
                                    IntPtr hDep = OpenServiceW(hScm, depName, SERVICE_STOP | SERVICE_QUERY_STATUS);
                                    if (hDep != IntPtr.Zero)
                                    {
                                        try { StopSingleServiceHandleAndWait(hDep); }
                                        finally { CloseServiceHandle(hDep); }
                                    }
                                }
                            }
                        }
                    }
                    finally
                    {
                        Marshal.FreeHGlobal(depBuf);
                    }
                }

                StopSingleServiceHandleAndWait(hSvc);
                bool delOk = DeleteService(hSvc);
                return delOk;
            }
            catch
            {
                return false;
            }
            finally
            {
                CloseServiceHandle(hSvc);
            }
        }

        public static Task<bool> NeutralizeSingleServiceOrDriverAsync(string svcName)
        {
            return Task.Run(delegate() { return NeutralizeSingleServiceOrDriver(svcName); });
        }

        public static bool NeutralizeSingleServiceOrDriver(string svcName)
        {
            if (string.IsNullOrWhiteSpace(svcName)) return false;
            string cleanName = svcName.Trim();
            if (!IsSafeNonMicrosoftFilterTarget(cleanName)) return false;
            EnsureUnlockPrivileges();

            bool isDriver = false;
            Action disableInReg = delegate()
            {
                try
                {
                    using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                    using (var sk = baseKey.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\" + cleanName, true))
                    {
                        if (sk != null)
                        {
                            object tObj = sk.GetValue("Type");
                            if (tObj != null)
                            {
                                int tVal = Convert.ToInt32(tObj) & 0x0F;
                                isDriver = (tVal == 1 || tVal == 2 || tVal == 8);
                            }
                            try { sk.SetValue("Start", 4, RegistryValueKind.DWord); } catch {}
                            try { sk.DeleteValue("FailureActions", false); } catch {}
                        }
                    }
                }
                catch {}
            };

            disableInReg();

            bool scmOk = false;
            IntPtr hScm = OpenSCManagerW(null, null, SC_MANAGER_CONNECT | SC_MANAGER_ENUMERATE_SERVICE);
            try
            {
                scmOk = TryStopAndDeleteViaScm(hScm, cleanName, isDriver);
                if (!scmOk)
                {
                    RunWithSystemOrTrustedInstaller(true, delegate()
                    {
                        disableInReg();
                        IntPtr hScmElev = OpenSCManagerW(null, null, SC_MANAGER_CONNECT | SC_MANAGER_ENUMERATE_SERVICE);
                        if (hScmElev != IntPtr.Zero)
                        {
                            try
                            {
                                scmOk = TryStopAndDeleteViaScm(hScmElev, cleanName, isDriver);
                            }
                            finally
                            {
                                CloseServiceHandle(hScmElev);
                            }
                        }
                    });
                }
                if (!scmOk)
                {
                    if (isDriver)
                    {
                        TryUnloadMinifilterDirect(cleanName);
                    }
                    RunHiddenSc("stop \"" + cleanName + "\"");
                    RunHiddenSc("delete \"" + cleanName + "\"");
                }
            }
            catch
            {
                return false;
            }
            finally
            {
                if (hScm != IntPtr.Zero) CloseServiceHandle(hScm);
            }

            Action deleteSvcKeyTree = delegate()
            {
                try
                {
                    using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                    using (var svcRoot = baseKey.OpenSubKey(@"SYSTEM\CurrentControlSet\Services", true))
                    {
                        if (svcRoot != null)
                        {
                            svcRoot.DeleteSubKeyTree(cleanName, false);
                        }
                    }
                }
                catch {}
            };

            deleteSvcKeyTree();
            try
            {
                using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                using (var skCheck = baseKey.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\" + cleanName, false))
                {
                    if (skCheck != null)
                    {
                        RunWithSystemOrTrustedInstaller(true, delegate()
                        {
                            deleteSvcKeyTree();
                        });
                    }
                }
            }
            catch {}

            try
            {
                using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                using (var skFinal = baseKey.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\" + cleanName, false))
                {
                    if (skFinal == null) return true;
                    object delFlag = skFinal.GetValue("DeleteFlag");
                    if (delFlag != null && Convert.ToInt32(delFlag) != 0) return true;
                    return scmOk;
                }
            }
            catch
            {
                return scmOk;
            }
        }

        private static void RunHiddenProcess(string exe, string args, int timeoutMs)
        {
            try
            {
                var psi = new ProcessStartInfo(exe, args);
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                using (var p = Process.Start(psi))
                {
                    if (p != null) p.WaitForExit(timeoutMs);
                }
            }
            catch {}
        }

        private static string DetectRogueVendorFamilyFromPath(string targetDir)
        {
            if (string.IsNullOrWhiteSpace(targetDir)) return "";
            if (targetDir.IndexOf("360", StringComparison.OrdinalIgnoreCase) >= 0 ||
                targetDir.IndexOf("Qihu", StringComparison.OrdinalIgnoreCase) >= 0 ||
                targetDir.IndexOf("Qihoo", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return "360";
            }
            if (targetDir.IndexOf("2345", StringComparison.OrdinalIgnoreCase) >= 0) return "2345";
            if (targetDir.IndexOf("Kingsoft", StringComparison.OrdinalIgnoreCase) >= 0) return "Kingsoft";
            if (targetDir.IndexOf("Baidu", StringComparison.OrdinalIgnoreCase) >= 0) return "Baidu";
            return "";
        }

        public static int DisableAndRemoveServicesInDirectory(string targetDir)
        {
            if (string.IsNullOrWhiteSpace(targetDir)) return 0;
            string norm = targetDir.Trim().TrimEnd('\\');
            try { norm = Path.GetFullPath(norm).TrimEnd('\\'); } catch {}
            if (!IsSafeLockTargetDirectory(norm)) return 0;
            string prefix = norm + "\\";
            if (prefix.Length <= 4) return 0;

            string vendorFamily = DetectRogueVendorFamilyFromPath(norm);
            int neutralized = 0;
            IntPtr hScm = OpenSCManagerW(null, null, SC_MANAGER_CONNECT | SC_MANAGER_ENUMERATE_SERVICE);
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
                            bool isDriver = false;
                            string resolvedDriverSys = "";
                            using (var sk = svcRoot.OpenSubKey(svcName, true))
                            {
                                if (sk == null) continue;
                                string rawImg = sk.GetValue("ImagePath") as string;
                                string imgPath = NormalizeServiceImagePath(rawImg);
                                if (string.IsNullOrEmpty(imgPath)) continue;

                                try
                                {
                                    object tObj = sk.GetValue("Type");
                                    if (tObj != null)
                                    {
                                        int tVal = Convert.ToInt32(tObj) & 0x0F;
                                        isDriver = (tVal == 1 || tVal == 2 || tVal == 8);
                                    }
                                }
                                catch {}

                                if (imgPath.IndexOf(prefix, StringComparison.OrdinalIgnoreCase) >= 0)
                                {
                                    matches = true;
                                }
                                else if (isDriver && !string.IsNullOrEmpty(vendorFamily))
                                {
                                    string sysCandidate = imgPath;
                                    if (sysCandidate.StartsWith(@"system32\", StringComparison.OrdinalIgnoreCase) ||
                                        sysCandidate.StartsWith(@"syswow64\", StringComparison.OrdinalIgnoreCase))
                                    {
                                        sysCandidate = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), sysCandidate);
                                    }
                                    if (File.Exists(sysCandidate) && IsVerifiedRogueKernelDriverFile(sysCandidate))
                                    {
                                        FileVersionInfo fvi = null;
                                        try { fvi = FileVersionInfo.GetVersionInfo(sysCandidate); } catch {}
                                        string meta = Path.GetFileName(sysCandidate) + " " + (fvi != null ? (fvi.CompanyName + " " + fvi.ProductName + " " + fvi.FileDescription) : "") + " " + GetSignerSubject(sysCandidate);
                                        if (meta.IndexOf(vendorFamily, StringComparison.OrdinalIgnoreCase) >= 0 ||
                                            (vendorFamily == "360" && (meta.IndexOf("Qihu", StringComparison.OrdinalIgnoreCase) >= 0 || meta.IndexOf("Qihoo", StringComparison.OrdinalIgnoreCase) >= 0)))
                                        {
                                            matches = true;
                                            resolvedDriverSys = sysCandidate;
                                        }
                                    }
                                }

                                if (matches)
                                {
                                    try { sk.SetValue("Start", 4, RegistryValueKind.DWord); } catch {}
                                    try { sk.DeleteValue("FailureActions", false); } catch {}
                                }
                            }

                            if (matches)
                            {
                                neutralized++;
                                if (!TryStopAndDeleteViaScm(hScm, svcName, isDriver))
                                {
                                    NeutralizeSingleServiceOrDriver(svcName);
                                }
                                if (!string.IsNullOrEmpty(resolvedDriverSys) && File.Exists(resolvedDriverSys))
                                {
                                    int rbDummy;
                                    ForceDeleteDirectory(resolvedDriverSys, false, out rbDummy);
                                }
                            }
                        }
                        catch {}
                    }
                }
            }
            catch {}
            finally
            {
                if (hScm != IntPtr.Zero) CloseServiceHandle(hScm);
            }
            return neutralized;
        }

        public static int RemoveScheduledTasksInDirectory(string targetDir)
        {
            if (string.IsNullOrWhiteSpace(targetDir)) return 0;
            string norm = targetDir.Trim().TrimEnd('\\');
            try { norm = Path.GetFullPath(norm).TrimEnd('\\'); } catch {}
            if (!IsSafeLockTargetDirectory(norm)) return 0;
            string prefix = norm + "\\";
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
                                if (File.Exists(taskFile))
                                {
                                    File.SetAttributes(taskFile, FileAttributes.Normal);
                                    File.Delete(taskFile);
                                }
                            }
                            catch {}
                            if (!File.Exists(taskFile))
                            {
                                removed++;
                            }
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

        private static HashSet<string> LoadPendingRebootDeleteSet()
        {
            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                using (var sm = baseKey.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Session Manager", false))
                {
                    if (sm != null)
                    {
                        string[] ops = sm.GetValue("PendingFileRenameOperations") as string[];
                        if (ops != null)
                        {
                            for (int i = 0; i + 1 < ops.Length; i += 2)
                            {
                                string src = ops[i];
                                string dst = ops[i + 1];
                                if (!string.IsNullOrEmpty(src) && string.IsNullOrEmpty(dst))
                                {
                                    set.Add(NormalizeDosOrNtPath(src));
                                }
                            }
                        }
                    }
                }
            }
            catch {}
            return set;
        }

        private static bool ScheduleMoveFileExUnique(string path, HashSet<string> existingPending)
        {
            string normPath = NormalizeDosOrNtPath(path);
            if (existingPending != null && existingPending.Contains(normPath))
            {
                return false;
            }
            if (MoveFileEx(path, null, MOVEFILE_DELAY_UNTIL_REBOOT))
            {
                if (existingPending != null) existingPending.Add(normPath);
                return true;
            }
            return false;
        }

        private static string GetOrCreateGraveyardDirectory(string sourceFilePath, HashSet<string> existingPending)
        {
            try
            {
                string srcRoot = Path.GetPathRoot(Path.GetFullPath(sourceFilePath)) ?? "";
                string tmpBase = Path.GetTempPath();
                string tmpRoot = Path.GetPathRoot(tmpBase) ?? "";
                string graveDir = string.Equals(srcRoot, tmpRoot, StringComparison.OrdinalIgnoreCase)
                    ? Path.Combine(tmpBase.TrimEnd('\\'), "DuckUtil_Graveyard")
                    : Path.Combine(srcRoot, "DuckUtil_Graveyard");

                if (!Directory.Exists(graveDir))
                {
                    Directory.CreateDirectory(graveDir);
                    try
                    {
                        File.SetAttributes(graveDir, FileAttributes.Directory | FileAttributes.Hidden);
                    }
                    catch {}
                }
                else
                {
                    try
                    {
                        foreach (string oldDead in Directory.GetFiles(graveDir, "*.dead_*"))
                        {
                            try
                            {
                                if (!TryPosixUnlinkFile(oldDead))
                                {
                                    File.SetAttributes(oldDead, FileAttributes.Normal);
                                    File.Delete(oldDead);
                                }
                            }
                            catch {}
                        }
                    }
                    catch {}
                }
                ScheduleMoveFileExUnique(graveDir, existingPending);
                return graveDir;
            }
            catch
            {
                return "";
            }
        }

        private static bool TryEvacuateLockedFileToGraveyard(string filePath, HashSet<string> existingPending, ref int rebootScheduledCount)
        {
            if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath)) return true;
            try
            {
                string graveDir = GetOrCreateGraveyardDirectory(filePath, existingPending);
                if (!string.IsNullOrEmpty(graveDir))
                {
                    string graveFile = Path.Combine(graveDir, Path.GetFileName(filePath) + ".dead_" + Guid.NewGuid().ToString("N").Substring(0, 8));
                    File.Move(filePath, graveFile);
                    if (!TryPosixUnlinkFile(graveFile) && File.Exists(graveFile))
                    {
                        if (ScheduleMoveFileExUnique(graveFile, existingPending))
                        {
                            rebootScheduledCount++;
                        }
                    }
                    return !File.Exists(filePath);
                }
            }
            catch {}
            return false;
        }

        private static bool TryDeleteSingleFileAggressively(string file, bool allowParentAclUnlock)
        {
            if (!File.Exists(file)) return true;
            try
            {
                File.SetAttributes(file, FileAttributes.Normal);
                File.Delete(file);
                if (!File.Exists(file)) return true;
            }
            catch {}

            if (TryPosixUnlinkFile(file)) return true;

            if (TryTakeOwnershipAndGrantAdminAccess(file))
            {
                try
                {
                    File.SetAttributes(file, FileAttributes.Normal);
                    File.Delete(file);
                    if (!File.Exists(file)) return true;
                }
                catch {}
                if (TryPosixUnlinkFile(file)) return true;
            }

            if (allowParentAclUnlock)
            {
                string parentDir = Path.GetDirectoryName(file);
                if (!string.IsNullOrEmpty(parentDir) && TryTakeOwnershipAndGrantAdminAccess(parentDir))
                {
                    try
                    {
                        File.SetAttributes(file, FileAttributes.Normal);
                        File.Delete(file);
                        if (!File.Exists(file)) return true;
                    }
                    catch {}
                    if (TryPosixUnlinkFile(file)) return true;
                }
            }

            if (File.Exists(file))
            {
                RunWithSystemOrTrustedInstaller(true, delegate()
                {
                    TryTakeOwnershipAndGrantAdminAccessCore(file, false);
                    if (!TryPosixUnlinkFile(file) && File.Exists(file))
                    {
                        try
                        {
                            File.SetAttributes(file, FileAttributes.Normal);
                            File.Delete(file);
                        }
                        catch {}
                    }
                });
            }
            return !File.Exists(file);
        }

        public static ForceDeleteResult ForceDeleteDirectoryWithResult(string targetDir, bool runFullLockerStop)
        {
            int rb = 0;
            bool ok = ForceDeleteDirectory(targetDir, runFullLockerStop, out rb);
            return new ForceDeleteResult { Deleted = ok, RebootScheduledCount = rb };
        }

        public static Task<ForceDeleteResult> ForceDeleteDirectoryAsync(string targetDir, bool runFullLockerStop)
        {
            return Task.Run(delegate() { return ForceDeleteDirectoryWithResult(targetDir, runFullLockerStop); });
        }

        public static Task<bool> WaitForProcessExitAsync(Process proc)
        {
            var tcs = new TaskCompletionSource<bool>();
            if (proc == null)
            {
                tcs.TrySetResult(true);
                return tcs.Task;
            }
            EventHandler handler = null;
            handler = delegate(object s, EventArgs e)
            {
                try { proc.Exited -= handler; } catch {}
                tcs.TrySetResult(true);
            };
            try
            {
                proc.EnableRaisingEvents = true;
                proc.Exited += handler;
                if (proc.HasExited)
                {
                    try { proc.Exited -= handler; } catch {}
                    tcs.TrySetResult(true);
                }
            }
            catch
            {
                try { proc.Exited -= handler; } catch {}
                tcs.TrySetResult(true);
            }
            return tcs.Task;
        }

        public static List<ServiceScanEntry> ScanServicesAndDrivers()
        {
            var result = new List<ServiceScanEntry>();
            string winDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            try
            {
                using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                using (var svcRoot = baseKey.OpenSubKey(@"SYSTEM\CurrentControlSet\Services", false))
                {
                    if (svcRoot == null) return result;
                    string[] names = svcRoot.GetSubKeyNames();
                    for (int i = 0; i < names.Length; i++)
                    {
                        string sName = names[i];
                        try
                        {
                            using (var sk = svcRoot.OpenSubKey(sName, false))
                            {
                                if (sk == null) continue;
                                string rawImg = sk.GetValue("ImagePath") as string;
                                if (string.IsNullOrWhiteSpace(rawImg)) continue;
                                int sType = 0;
                                try
                                {
                                    object tObj = sk.GetValue("Type");
                                    if (tObj != null) sType = Convert.ToInt32(tObj);
                                }
                                catch {}
                                int baseType = sType & 0x0F;
                                bool isDrv = (baseType == 1 || baseType == 2 || baseType == 8);
                                string normImg = NormalizeServiceImagePath(rawImg);
                                string resolved = normImg;
                                if (!string.IsNullOrEmpty(resolved) &&
                                    (resolved.StartsWith(@"system32\", StringComparison.OrdinalIgnoreCase) ||
                                     resolved.StartsWith(@"syswow64\", StringComparison.OrdinalIgnoreCase)) &&
                                    !string.IsNullOrEmpty(winDir))
                                {
                                    resolved = Path.Combine(winDir, resolved);
                                }
                                result.Add(new ServiceScanEntry
                                {
                                    ServiceName = sName,
                                    DisplayName = (sk.GetValue("DisplayName") as string) ?? "",
                                    ImagePath = rawImg,
                                    ResolvedImagePath = resolved,
                                    ServiceType = sType,
                                    IsKernelDriver = isDrv
                                });
                            }
                        }
                        catch {}
                    }
                }
            }
            catch {}
            return result;
        }

        public static Task<List<ServiceScanEntry>> ScanServicesAndDriversAsync()
        {
            return Task.Run(delegate() { return ScanServicesAndDrivers(); });
        }

        public static bool ForceDeleteDirectory(string targetDir, out int rebootScheduledCount)
        {
            return ForceDeleteDirectory(targetDir, true, out rebootScheduledCount);
        }

        public static bool ForceDeleteDirectory(string targetDir, bool runFullLockerStop, out int rebootScheduledCount)
        {
            rebootScheduledCount = 0;
            if (string.IsNullOrWhiteSpace(targetDir)) return false;
            string norm = targetDir.Trim().TrimEnd('\\');
            try { norm = Path.GetFullPath(norm).TrimEnd('\\'); } catch {}
            if (norm.Length <= 3) return false;

            HashSet<string> existingPending = LoadPendingRebootDeleteSet();

            if (File.Exists(norm))
            {
                bool isRogueDrv = IsVerifiedRogueKernelDriverFile(norm);
                if (!IsSafeLockTargetDirectory(Path.GetDirectoryName(norm)) && !isRogueDrv) return false;
                if (isRogueDrv)
                {
                    try
                    {
                        string drvFileName = Path.GetFileName(norm);
                        using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                        using (var svcRoot = baseKey.OpenSubKey(@"SYSTEM\CurrentControlSet\Services", false))
                        {
                            if (svcRoot != null && !string.IsNullOrEmpty(drvFileName))
                            {
                                foreach (string sName in svcRoot.GetSubKeyNames())
                                {
                                    try
                                    {
                                        using (var sk = svcRoot.OpenSubKey(sName, false))
                                        {
                                            if (sk == null) continue;
                                            string img = sk.GetValue("ImagePath") as string ?? "";
                                            if (img.IndexOf(drvFileName, StringComparison.OrdinalIgnoreCase) >= 0)
                                            {
                                                NeutralizeSingleServiceOrDriver(sName);
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
                if (TryDeleteSingleFileAggressively(norm, !isRogueDrv)) return true;
                if (runFullLockerStop)
                {
                    ForceStopDirectoryLockers(norm, false);
                    if (TryDeleteSingleFileAggressively(norm, !isRogueDrv)) return true;
                }
                if (TryEvacuateLockedFileToGraveyard(norm, existingPending, ref rebootScheduledCount))
                {
                    return true;
                }
                if (ScheduleMoveFileExUnique(norm, existingPending))
                {
                    rebootScheduledCount++;
                }
                return existingPending.Contains(NormalizeDosOrNtPath(norm));
            }

            if (!Directory.Exists(norm)) return true;
            if (!IsSafeLockTargetDirectory(norm)) return false;

            if (IsReparsePoint(norm))
            {
                try
                {
                    Directory.Delete(norm, false);
                    return true;
                }
                catch
                {
                    if (ScheduleMoveFileExUnique(norm, existingPending))
                    {
                        rebootScheduledCount++;
                    }
                    return existingPending.Contains(NormalizeDosOrNtPath(norm));
                }
            }

            if (runFullLockerStop)
            {
                ForceStopDirectoryLockers(norm, true);
            }

            try
            {
                foreach (string file in EnumerateFilesSafe(norm, "*", 10))
                {
                    if (TryDeleteSingleFileAggressively(file, true)) continue;

                    if (TryEvacuateLockedFileToGraveyard(file, existingPending, ref rebootScheduledCount))
                    {
                        continue;
                    }

                    if (file.IndexOf(".dead_", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        if (ScheduleMoveFileExUnique(file, existingPending))
                        {
                            rebootScheduledCount++;
                        }
                    }
                    else
                    {
                        string deadPath = file + ".dead_" + Guid.NewGuid().ToString("N").Substring(0, 6);
                        try
                        {
                            File.Move(file, deadPath);
                            if (ScheduleMoveFileExUnique(deadPath, existingPending))
                            {
                                rebootScheduledCount++;
                            }
                        }
                        catch
                        {
                            if (ScheduleMoveFileExUnique(file, existingPending))
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
                        bool dirRecovered = false;
                        if (!IsReparsePoint(sd) && TryTakeOwnershipAndGrantAdminAccess(sd))
                        {
                            try
                            {
                                foreach (string innerFile in Directory.GetFiles(sd))
                                {
                                    if (!TryDeleteSingleFileAggressively(innerFile, false))
                                    {
                                        TryEvacuateLockedFileToGraveyard(innerFile, existingPending, ref rebootScheduledCount);
                                    }
                                }
                            }
                            catch {}
                            try
                            {
                                File.SetAttributes(sd, FileAttributes.Normal);
                                Directory.Delete(sd, false);
                                dirRecovered = true;
                            }
                            catch {}
                        }
                        if (!dirRecovered)
                        {
                            ScheduleMoveFileExUnique(sd, existingPending);
                        }
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
                if (TryTakeOwnershipAndGrantAdminAccess(norm))
                {
                    try
                    {
                        File.SetAttributes(norm, FileAttributes.Normal);
                        Directory.Delete(norm, false);
                        return true;
                    }
                    catch {}
                }
                if (ScheduleMoveFileExUnique(norm, existingPending))
                {
                    rebootScheduledCount++;
                    return true;
                }
                return existingPending.Contains(NormalizeDosOrNtPath(norm));
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
                if (!Directory.Exists(backupDir) || IsReparsePoint(backupDir)) return 0;
                if (Directory.Exists(targetDir) && IsReparsePoint(targetDir)) return 0;
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
                                if (IsReparsePoint(file)) continue;
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
                                if (!IsReparsePoint(sub))
                                {
                                    nextLevel.Add(sub);
                                }
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

        public static Task<List<HollowDirResult>> ScanHollowProgramDirsAsync(string[] programRoots, string[] exclusions, string[] activeInstallLocs)
        {
            return Task.Run(delegate()
            {
                var candidates = new List<string>();
                if (programRoots != null)
                {
                    for (int ri = 0; ri < programRoots.Length; ri++)
                    {
                        string root = programRoots[ri];
                        if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root)) continue;
                        try
                        {
                            string[] subs = Directory.GetDirectories(root);
                            for (int si = 0; si < subs.Length; si++)
                            {
                                string sd = subs[si];
                                string dirName = Path.GetFileName(sd) ?? "";
                                bool isExcluded = false;
                                if (exclusions != null)
                                {
                                    for (int ei = 0; ei < exclusions.Length; ei++)
                                    {
                                        string ex = exclusions[ei];
                                        if (!string.IsNullOrEmpty(ex) && dirName.StartsWith(ex, StringComparison.OrdinalIgnoreCase))
                                        {
                                            isExcluded = true;
                                            break;
                                        }
                                    }
                                }
                                if (isExcluded) continue;

                                string sdNorm = sd.Trim().TrimEnd('\\');
                                string sdPrefix = sdNorm + "\\";
                                bool isUsed = false;
                                if (activeInstallLocs != null)
                                {
                                    for (int ai = 0; ai < activeInstallLocs.Length; ai++)
                                    {
                                        string actLoc = activeInstallLocs[ai];
                                        if (string.IsNullOrEmpty(actLoc)) continue;
                                        if (actLoc.Equals(sdNorm, StringComparison.OrdinalIgnoreCase) ||
                                            actLoc.StartsWith(sdPrefix, StringComparison.OrdinalIgnoreCase))
                                        {
                                            isUsed = true;
                                            break;
                                        }
                                    }
                                }
                                if (!isUsed) candidates.Add(sd);
                            }
                        }
                        catch {}
                    }
                }

                var bag = new ConcurrentBag<HollowDirResult>();
                if (candidates.Count > 0)
                {
                    Parallel.For(0, candidates.Count, delegate(int idx)
                    {
                        string sd = candidates[idx];
                        try
                        {
                            long hSize = GetHollowDirectorySize(sd, 3, 52428800L);
                            if (hSize >= 0L)
                            {
                                bag.Add(new HollowDirResult
                                {
                                    Path = sd,
                                    AppName = Path.GetFileName(sd) ?? sd,
                                    SizeBytes = hSize
                                });
                            }
                        }
                        catch {}
                    });
                }
                return new List<HollowDirResult>(bag);
            });
        }

        public static Task<List<HollowDirResult>> ScanHollowPathsWithSizesAsync(string[] paths, string[] appNames)
        {
            return Task.Run(delegate()
            {
                var bag = new ConcurrentBag<HollowDirResult>();
                int count = (paths != null) ? paths.Length : 0;
                if (count > 0)
                {
                    Parallel.For(0, count, delegate(int idx)
                    {
                        string p = paths[idx];
                        if (string.IsNullOrWhiteSpace(p)) return;
                        try
                        {
                            long hSize = GetHollowDirectorySize(p, 3, 52428800L);
                            if (hSize >= 0L)
                            {
                                long fullSz = GetDirectorySizeFast(p, 3);
                                bag.Add(new HollowDirResult
                                {
                                    Path = p,
                                    AppName = (appNames != null && idx < appNames.Length) ? (appNames[idx] ?? "") : "",
                                    SizeBytes = fullSz
                                });
                            }
                        }
                        catch {}
                    });
                }
                return new List<HollowDirResult>(bag);
            });
        }

        public static Task<List<DeadShortcutResult>> ScanDeadShortcutsAsync(string[] rootDirs)
        {
            var tcs = new TaskCompletionSource<List<DeadShortcutResult>>();
            Thread t = new Thread(delegate()
            {
                var results = new List<DeadShortcutResult>();
                object wsh = null;
                Type wshType = null;
                try
                {
                    if (rootDirs != null && rootDirs.Length > 0)
                    {
                        wshType = Type.GetTypeFromProgID("WScript.Shell");
                        if (wshType != null)
                        {
                            wsh = Activator.CreateInstance(wshType);
                        }
                        if (wsh != null)
                        {
                            for (int ri = 0; ri < rootDirs.Length; ri++)
                            {
                                string root = rootDirs[ri];
                                if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root)) continue;
                                foreach (string lnk in EnumerateFilesSafe(root, "*.lnk", 6))
                                {
                                    object sc = null;
                                    try
                                    {
                                        sc = wshType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, wsh, new object[] { lnk });
                                        if (sc != null)
                                        {
                                            string target = sc.GetType().InvokeMember("TargetPath", BindingFlags.GetProperty, null, sc, null) as string;
                                            if (!string.IsNullOrEmpty(target) &&
                                                target.Length >= 7 &&
                                                char.IsLetter(target[0]) &&
                                                target[1] == ':' &&
                                                target[2] == '\\' &&
                                                target.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) &&
                                                !File.Exists(target))
                                            {
                                                results.Add(new DeadShortcutResult
                                                {
                                                    LnkPath = lnk,
                                                    AppName = Path.GetFileNameWithoutExtension(lnk) ?? lnk
                                                });
                                            }
                                        }
                                    }
                                    catch {}
                                    finally
                                    {
                                        if (sc != null) { try { Marshal.FinalReleaseComObject(sc); } catch {} }
                                    }
                                }
                            }
                        }
                    }
                    tcs.TrySetResult(results);
                }
                catch
                {
                    tcs.TrySetResult(results);
                }
                finally
                {
                    if (wsh != null) { try { Marshal.FinalReleaseComObject(wsh); } catch {} }
                }
            });
            t.IsBackground = true;
            t.SetApartmentState(ApartmentState.STA);
            t.Start();
            return tcs.Task;
        }

        public static Task<ServicesAndRogueResult> ScanServicesAndRogueDriversAsync()
        {
            return Task.Run(delegate()
            {
                var allSvcs = ScanServicesAndDrivers();
                var bag = new ConcurrentBag<ServiceScanEntry>();
                if (allSvcs != null && allSvcs.Count > 0)
                {
                    Parallel.For(0, allSvcs.Count, delegate(int idx)
                    {
                        ServiceScanEntry se = allSvcs[idx];
                        if (se == null || !se.IsKernelDriver) return;
                        string img = se.ResolvedImagePath;
                        if (string.IsNullOrWhiteSpace(img)) return;
                        try
                        {
                            if (File.Exists(img) && IsVerifiedRogueKernelDriverFile(img))
                            {
                                bag.Add(se);
                            }
                        }
                        catch {}
                    });
                }
                return new ServicesAndRogueResult
                {
                    AllServices = allSvcs ?? new List<ServiceScanEntry>(),
                    RogueDrivers = new List<ServiceScanEntry>(bag)
                };
            });
        }

        public static Task<long> GetDirectorySizeFastAsync(string rootPath, int maxDepth)
        {
            return Task.Run(delegate() { return GetDirectorySizeFast(rootPath, maxDepth); });
        }

        public static Task<string[]> ExtractBinaryAndCertTokensAsync(string targetDir, string uninstallString, string fallbackExe)
        {
            return Task.Run(delegate() { return ExtractBinaryAndCertTokens(targetDir, uninstallString, fallbackExe); });
        }

        public static Task<List<string>> ScanAppShortcutsAsync(string[] rootDirs, string targetLocPrefix, string cleanAppName)
        {
            var tcs = new TaskCompletionSource<List<string>>();
            Thread t = new Thread(delegate()
            {
                var results = new List<string>();
                object wsh = null;
                Type wshType = null;
                try
                {
                    if (rootDirs != null && rootDirs.Length > 0)
                    {
                        wshType = Type.GetTypeFromProgID("WScript.Shell");
                        if (wshType != null) wsh = Activator.CreateInstance(wshType);
                        if (wsh != null)
                        {
                            bool hasPrefix = !string.IsNullOrEmpty(targetLocPrefix);
                            bool hasClean = !string.IsNullOrEmpty(cleanAppName);
                            for (int ri = 0; ri < rootDirs.Length; ri++)
                            {
                                string root = rootDirs[ri];
                                if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root)) continue;
                                foreach (string lnk in EnumerateFilesSafe(root, "*.lnk", 6))
                                {
                                    object sc = null;
                                    try
                                    {
                                        string lnkName = Path.GetFileNameWithoutExtension(lnk) ?? "";
                                        sc = wshType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, wsh, new object[] { lnk });
                                        if (sc != null)
                                        {
                                            string target = sc.GetType().InvokeMember("TargetPath", BindingFlags.GetProperty, null, sc, null) as string;
                                            bool matches = false;
                                            if (hasPrefix && !string.IsNullOrEmpty(target) && target.StartsWith(targetLocPrefix, StringComparison.OrdinalIgnoreCase))
                                            {
                                                matches = true;
                                            }
                                            else if (hasClean && lnkName.Equals(cleanAppName, StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(target) && !File.Exists(target) && !Directory.Exists(target))
                                            {
                                                matches = true;
                                            }
                                            if (matches) results.Add(lnk);
                                        }
                                    }
                                    catch {}
                                    finally
                                    {
                                        if (sc != null) { try { Marshal.FinalReleaseComObject(sc); } catch {} }
                                    }
                                }
                            }
                        }
                    }
                    tcs.TrySetResult(results);
                }
                catch
                {
                    tcs.TrySetResult(results);
                }
                finally
                {
                    if (wsh != null) { try { Marshal.FinalReleaseComObject(wsh); } catch {} }
                }
            });
            t.IsBackground = true;
            t.SetApartmentState(ApartmentState.STA);
            t.Start();
            return tcs.Task;
        }
    }
}
