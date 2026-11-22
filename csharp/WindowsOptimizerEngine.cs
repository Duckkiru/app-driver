using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace DuckUtil {
    public sealed class HardwareProfile {
        public bool IsLaptop { get; set; }
        public int TotalRamGb { get; set; }
        public int OsBuild { get; set; }
        public int OsUbr { get; set; }
        public string DisplayVersion { get; set; }
        public bool IsWindows11 { get; set; }
        public bool IsSystemDriveSsd { get; set; }
        public string SummaryText { get; set; }
    }

    public sealed class RegTweakSpec {
        public string Hive { get; set; }
        public string Path { get; set; }
        public string Name { get; set; }
        public string ValueType { get; set; }
        public string ApplyValue { get; set; }
        public string UndoValue { get; set; }
    }

    public sealed class ServiceTweakSpec {
        public string Name { get; set; }
        public int ApplyStart { get; set; }
        public int UndoStart { get; set; }
    }

    public sealed class TweakProbeRequest {
        public string Id { get; set; }
        public RegTweakSpec[] Registry { get; set; }
        public ServiceTweakSpec[] Services { get; set; }
        public string ProbeKind { get; set; }
    }

    public sealed class TweakProbeResult {
        public string Id { get; set; }
        public string State { get; set; }
        public string Detail { get; set; }
    }

    public sealed class RegistrySnapshotEntry {
        public string Hive { get; set; }
        public string Path { get; set; }
        public string Name { get; set; }
        public bool Existed { get; set; }
        public bool KeyExisted { get; set; }
        public string Kind { get; set; }
        public string ValueData { get; set; }
    }

    public sealed class ServiceSnapshotEntry {
        public string Name { get; set; }
        public bool Existed { get; set; }
        public int OriginalStart { get; set; }
    }

    public sealed class ApplyRegBatchResult {
        public int OkCount { get; set; }
        public int TotalCount { get; set; }
        public string[] Errors { get; set; }
    }

    public static class WindowsOptimizerEngine {
        [StructLayout(LayoutKind.Sequential)]
        private struct SYSTEM_POWER_STATUS {
            public byte ACLineStatus;
            public byte BatteryFlag;
            public byte BatteryLifePercent;
            public byte SystemStatusFlag;
            public int BatteryLifeTime;
            public int BatteryFullLifeTime;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        private struct MEMORYSTATUSEX {
            public uint dwLength;
            public uint dwMemoryLoad;
            public ulong ullTotalPhys;
            public ulong ullAvailPhys;
            public ulong ullTotalPageFile;
            public ulong ullAvailPageFile;
            public ulong ullTotalVirtual;
            public ulong ullAvailVirtual;
            public ulong ullAvailExtendedVirtual;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct STORAGE_PROPERTY_QUERY {
            public uint PropertyId;
            public uint QueryType;
            public byte AdditionalParameters;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DEVICE_SEEK_PENALTY_DESCRIPTOR {
            public uint Version;
            public uint Size;
            [MarshalAs(UnmanagedType.U1)]
            public bool IncursSeekPenalty;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct VOLUME_DISK_EXTENTS {
            public uint NumberOfDiskExtents;
            public uint DiskNumber;
            public long StartingOffset;
            public long ExtentLength;
        }

        private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint OPEN_EXISTING = 3;
        private const uint IOCTL_STORAGE_QUERY_PROPERTY = 0x002D1400;
        private const uint IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS = 0x00560000;
        private const uint StorageDeviceProperty = 0;
        private const uint StorageDeviceSeekPenaltyProperty = 7;
        private const uint PropertyStandardQuery = 0;

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS sps);

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern int PowerDeterminePlatformRoleEx(uint Version);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetPhysicallyInstalledSystemMemory(out ulong totalMemoryInKilobytes);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateFileW(
            string lpFileName,
            uint dwDesiredAccess,
            uint dwShareMode,
            IntPtr lpSecurityAttributes,
            uint dwCreationDisposition,
            uint dwFlagsAndAttributes,
            IntPtr hTemplateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DeviceIoControl(
            IntPtr hDevice,
            uint dwIoControlCode,
            IntPtr lpInBuffer,
            uint nInBufferSize,
            IntPtr lpOutBuffer,
            uint nOutBufferSize,
            out uint lpBytesReturned,
            IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr hObject);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr SendMessageTimeoutW(
            IntPtr hWnd,
            uint Msg,
            UIntPtr wParam,
            string lParam,
            uint fuFlags,
            uint uTimeout,
            out UIntPtr lpdwResult);

        [DllImport("shell32.dll")]
        private static extern void SHChangeNotify(uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);

        public static bool IsCurrentProcessAdmin() {
            try {
                using (WindowsIdentity id = WindowsIdentity.GetCurrent()) {
                    var pr = new WindowsPrincipal(id);
                    return pr.IsInRole(WindowsBuiltInRole.Administrator);
                }
            } catch {
                return false;
            }
        }

        public static void BroadcastSettingsChange() {
            try {
                IntPtr hwndBroadcast = new IntPtr(0xFFFF);
                UIntPtr res;
                SendMessageTimeoutW(hwndBroadcast, 0x001A, UIntPtr.Zero, "ImmersiveColorSet", 0x0002, 500, out res);
                SendMessageTimeoutW(hwndBroadcast, 0x001A, UIntPtr.Zero, "Environment", 0x0002, 500, out res);
                SendMessageTimeoutW(hwndBroadcast, 0x001A, UIntPtr.Zero, "Policy", 0x0002, 500, out res);
            } catch {}
            try {
                SHChangeNotify(0x08000000u, 0x0000u, IntPtr.Zero, IntPtr.Zero);
            } catch {}
        }

        public static Task BroadcastSettingsChangeAsync() {
            return Task.Run(delegate() { BroadcastSettingsChange(); });
        }

        private static string DetectSystemDriveType(out bool isSsd) {
            isSsd = true;
            bool isNvme = false;
            IntPtr hVol = INVALID_HANDLE_VALUE;
            IntPtr hDisk = INVALID_HANDLE_VALUE;
            try {
                string sysDrive = Environment.GetEnvironmentVariable("SystemDrive");
                if (string.IsNullOrEmpty(sysDrive)) sysDrive = "C:";
                string volPath = "\\\\.\\" + sysDrive.TrimEnd('\\');
                int diskNum = 0;

                hVol = CreateFileW(volPath, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
                if (hVol != INVALID_HANDLE_VALUE) {
                    int extSize = Marshal.SizeOf(typeof(VOLUME_DISK_EXTENTS));
                    IntPtr extBuf = Marshal.AllocHGlobal(extSize);
                    try {
                        uint retBytes;
                        if (DeviceIoControl(hVol, IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS, IntPtr.Zero, 0, extBuf, (uint)extSize, out retBytes, IntPtr.Zero)) {
                            VOLUME_DISK_EXTENTS ext = (VOLUME_DISK_EXTENTS)Marshal.PtrToStructure(extBuf, typeof(VOLUME_DISK_EXTENTS));
                            if (ext.NumberOfDiskExtents > 0) diskNum = (int)ext.DiskNumber;
                        }
                    } finally {
                        Marshal.FreeHGlobal(extBuf);
                    }
                }

                string diskPath = "\\\\.\\PhysicalDrive" + diskNum.ToString(CultureInfo.InvariantCulture);
                hDisk = CreateFileW(diskPath, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
                if (hDisk == INVALID_HANDLE_VALUE) return "SSD";

                int qSize = Marshal.SizeOf(typeof(STORAGE_PROPERTY_QUERY));
                IntPtr qBuf = Marshal.AllocHGlobal(qSize);
                try {
                    STORAGE_PROPERTY_QUERY qDev = new STORAGE_PROPERTY_QUERY();
                    qDev.PropertyId = StorageDeviceProperty;
                    qDev.QueryType = PropertyStandardQuery;
                    Marshal.StructureToPtr(qDev, qBuf, false);
                    int devBufSize = 256;
                    IntPtr devBuf = Marshal.AllocHGlobal(devBufSize);
                    try {
                        uint retDev;
                        if (DeviceIoControl(hDisk, IOCTL_STORAGE_QUERY_PROPERTY, qBuf, (uint)qSize, devBuf, (uint)devBufSize, out retDev, IntPtr.Zero) && retDev >= 32) {
                            int busType = Marshal.ReadInt32(devBuf, 28);
                            if (busType == 17) isNvme = true;
                        }
                    } finally {
                        Marshal.FreeHGlobal(devBuf);
                    }

                    STORAGE_PROPERTY_QUERY q = new STORAGE_PROPERTY_QUERY();
                    q.PropertyId = StorageDeviceSeekPenaltyProperty;
                    q.QueryType = PropertyStandardQuery;
                    Marshal.StructureToPtr(q, qBuf, false);
                    int dSize = Marshal.SizeOf(typeof(DEVICE_SEEK_PENALTY_DESCRIPTOR));
                    IntPtr dBuf = Marshal.AllocHGlobal(dSize);
                    try {
                        uint retBytes;
                        if (DeviceIoControl(hDisk, IOCTL_STORAGE_QUERY_PROPERTY, qBuf, (uint)qSize, dBuf, (uint)dSize, out retBytes, IntPtr.Zero)) {
                            DEVICE_SEEK_PENALTY_DESCRIPTOR desc = (DEVICE_SEEK_PENALTY_DESCRIPTOR)Marshal.PtrToStructure(dBuf, typeof(DEVICE_SEEK_PENALTY_DESCRIPTOR));
                            isSsd = !desc.IncursSeekPenalty;
                        }
                    } finally {
                        Marshal.FreeHGlobal(dBuf);
                    }
                } finally {
                    Marshal.FreeHGlobal(qBuf);
                }
            } catch {
            } finally {
                if (hDisk != INVALID_HANDLE_VALUE) { try { CloseHandle(hDisk); } catch {} }
                if (hVol != INVALID_HANDLE_VALUE) { try { CloseHandle(hVol); } catch {} }
            }
            if (isNvme) { isSsd = true; return "NVMe SSD"; }
            return isSsd ? "SSD" : "HDD";
        }

        public static HardwareProfile DetectHardwareProfile() {
            var hp = new HardwareProfile();
            hp.IsLaptop = false;
            hp.TotalRamGb = 16;
            hp.OsBuild = 0;
            hp.OsUbr = 0;
            hp.DisplayVersion = "";
            hp.IsWindows11 = false;
            hp.IsSystemDriveSsd = true;

            bool roleResolved = false;
            try {
                int role = PowerDeterminePlatformRoleEx(2);
                if (role == 2 || role == 8) {
                    hp.IsLaptop = true;
                    roleResolved = true;
                } else if (role == 1 || role == 3 || role == 4 || role == 5 || role == 6 || role == 7) {
                    hp.IsLaptop = false;
                    roleResolved = true;
                }
            } catch {}

            if (!roleResolved) {
                try {
                    SYSTEM_POWER_STATUS sps;
                    if (GetSystemPowerStatus(out sps)) {
                        hp.IsLaptop = (sps.BatteryFlag != 128 && sps.BatteryFlag != 255);
                    }
                } catch {}
            }

            bool ramResolved = false;
            try {
                ulong installedKb;
                if (GetPhysicallyInstalledSystemMemory(out installedKb) && installedKb > 0) {
                    double gb = (double)installedKb / 1048576.0;
                    hp.TotalRamGb = Math.Max(1, (int)Math.Round(gb));
                    ramResolved = true;
                }
            } catch {}

            if (!ramResolved) {
                try {
                    MEMORYSTATUSEX mem = new MEMORYSTATUSEX();
                    mem.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
                    if (GlobalMemoryStatusEx(ref mem) && mem.ullTotalPhys > 0) {
                        double gb = (double)mem.ullTotalPhys / 1073741824.0;
                        hp.TotalRamGb = Math.Max(1, (int)Math.Ceiling(gb));
                    }
                } catch {}
            }

            try {
                using (RegistryKey baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                using (RegistryKey cv = baseKey.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion", false)) {
                    if (cv != null) {
                        object bObj = cv.GetValue("CurrentBuildNumber");
                        if (bObj != null) {
                            int bNum;
                            if (int.TryParse(bObj.ToString(), out bNum)) hp.OsBuild = bNum;
                        }
                        object uObj = cv.GetValue("UBR");
                        if (uObj != null) {
                            int uNum;
                            if (int.TryParse(uObj.ToString(), out uNum)) hp.OsUbr = uNum;
                        }
                        object dvObj = cv.GetValue("DisplayVersion");
                        if (dvObj != null) hp.DisplayVersion = dvObj.ToString().Trim();
                        if (string.IsNullOrEmpty(hp.DisplayVersion)) {
                            object ridObj = cv.GetValue("ReleaseId");
                            if (ridObj != null) hp.DisplayVersion = ridObj.ToString().Trim();
                        }
                    }
                }
            } catch {}

            hp.IsWindows11 = (hp.OsBuild >= 22000);
            bool isSsdDrive;
            string driveType = DetectSystemDriveType(out isSsdDrive);
            hp.IsSystemDriveSsd = isSsdDrive;

            string devType = hp.IsLaptop ? "Laptop" : "PC";
            string osTag = (hp.IsWindows11 ? "Win 11" : "Win 10") + (string.IsNullOrEmpty(hp.DisplayVersion) ? "" : (" " + hp.DisplayVersion));
            hp.SummaryText = devType + " | " + hp.TotalRamGb.ToString(CultureInfo.InvariantCulture) + " GB RAM | " + driveType + " | " + osTag;
            return hp;
        }

        private static RegistryKey OpenHiveBase(string hive) {
            if (string.Equals(hive, "HKCU", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(hive, "HKEY_CURRENT_USER", StringComparison.OrdinalIgnoreCase)) {
                return RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64);
            }
            if (string.Equals(hive, "HKU", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(hive, "HKEY_USERS", StringComparison.OrdinalIgnoreCase)) {
                return RegistryKey.OpenBaseKey(RegistryHive.Users, RegistryView.Registry64);
            }
            if (string.Equals(hive, "HKCR", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(hive, "HKEY_CLASSES_ROOT", StringComparison.OrdinalIgnoreCase)) {
                return RegistryKey.OpenBaseKey(RegistryHive.ClassesRoot, RegistryView.Registry64);
            }
            return RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
        }

        private static string NormalizeValueName(string name) {
            if (string.IsNullOrEmpty(name) || string.Equals(name, "(Default)", StringComparison.OrdinalIgnoreCase)) {
                return "";
            }
            return name;
        }

        private static byte[] ParseHexBytes(string hexCsv) {
            if (string.IsNullOrWhiteSpace(hexCsv)) return new byte[0];
            string[] parts = hexCsv.Split(new char[] { ',', ' ', '-' }, StringSplitOptions.RemoveEmptyEntries);
            byte[] res = new byte[parts.Length];
            for (int i = 0; i < parts.Length; i++) {
                res[i] = byte.Parse(parts[i].Trim(), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
            }
            return res;
        }

        private static string FormatHexBytes(byte[] data) {
            if (data == null || data.Length == 0) return "";
            var sb = new StringBuilder(data.Length * 3);
            for (int i = 0; i < data.Length; i++) {
                if (i > 0) sb.Append(',');
                sb.Append(data[i].ToString("X2", CultureInfo.InvariantCulture));
            }
            return sb.ToString();
        }

        private static bool ValuesMatch(object actual, RegistryValueKind actualKind, string expectedType, string expectedStr) {
            if (actual == null) return false;
            string t = (expectedType ?? "DWord").Trim();
            if (string.Equals(t, "DWord", StringComparison.OrdinalIgnoreCase)) {
                long expVal;
                if (!TryParseInt64Flexible(expectedStr, out expVal)) return false;
                try {
                    long actVal = Convert.ToInt64(actual, CultureInfo.InvariantCulture);
                    return unchecked((uint)actVal) == unchecked((uint)expVal);
                } catch { return false; }
            }
            if (string.Equals(t, "QWord", StringComparison.OrdinalIgnoreCase)) {
                long expVal;
                if (!TryParseInt64Flexible(expectedStr, out expVal)) return false;
                try {
                    long actVal = Convert.ToInt64(actual, CultureInfo.InvariantCulture);
                    return actVal == expVal;
                } catch { return false; }
            }
            if (string.Equals(t, "Binary", StringComparison.OrdinalIgnoreCase)) {
                byte[] actBytes = actual as byte[];
                if (actBytes == null) return false;
                try {
                    byte[] expBytes = ParseHexBytes(expectedStr);
                    if (actBytes.Length != expBytes.Length) return false;
                    for (int i = 0; i < actBytes.Length; i++) {
                        if (actBytes[i] != expBytes[i]) return false;
                    }
                    return true;
                } catch { return false; }
            }
            string actStr = (actual.ToString() ?? "").Trim();
            string expStr = (expectedStr ?? "").Trim();
            if (string.Equals(actStr, expStr, StringComparison.OrdinalIgnoreCase)) return true;
            if (string.Equals(expStr, "506", StringComparison.OrdinalIgnoreCase)) {
                long fVal;
                if (TryParseInt64Flexible(actStr, out fVal) && fVal > 0 && (fVal & 4L) == 0L) return true;
            }
            if (string.Equals(expStr, "2", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(expStr, "2147483650", StringComparison.OrdinalIgnoreCase)) {
                long nVal;
                if (TryParseInt64Flexible(actStr, out nVal) && (nVal & 2L) == 2L) return true;
            }
            if (string.Equals(expStr, "hide:home", StringComparison.OrdinalIgnoreCase)) {
                if (actStr.IndexOf("hide:home", StringComparison.OrdinalIgnoreCase) >= 0) return true;
            }
            return false;
        }

        private static bool TryParseInt64Flexible(string raw, out long val) {
            val = 0;
            if (string.IsNullOrWhiteSpace(raw)) return false;
            string s = raw.Trim();
            if (s.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) {
                ulong u;
                if (ulong.TryParse(s.Substring(2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out u)) {
                    val = unchecked((long)u);
                    return true;
                }
                return false;
            }
            if (long.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out val)) return true;
            ulong u2;
            if (ulong.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out u2)) {
                val = unchecked((long)u2);
                return true;
            }
            return false;
        }

        private static bool ProbeSingleRegSpec(RegTweakSpec spec) {
            if (spec == null || string.IsNullOrWhiteSpace(spec.Path)) return false;
            string vt = (spec.ValueType ?? "DWord").Trim();
            using (RegistryKey baseKey = OpenHiveBase(spec.Hive)) {
                if (string.Equals(vt, "DeleteKey", StringComparison.OrdinalIgnoreCase)) {
                    using (RegistryKey k = baseKey.OpenSubKey(spec.Path, false)) {
                        return (k == null);
                    }
                }
                using (RegistryKey k = baseKey.OpenSubKey(spec.Path, false)) {
                    if (k == null) {
                        return string.Equals(vt, "DeleteValue", StringComparison.OrdinalIgnoreCase) ||
                               string.Equals(spec.ApplyValue, "__DELETE__", StringComparison.OrdinalIgnoreCase);
                    }
                    string valName = NormalizeValueName(spec.Name);
                    object val = k.GetValue(valName, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
                    if (string.Equals(vt, "DeleteValue", StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(spec.ApplyValue, "__DELETE__", StringComparison.OrdinalIgnoreCase)) {
                        return (val == null);
                    }
                    if (valName.Length == 0 && string.IsNullOrEmpty(spec.ApplyValue) &&
                        string.Equals(spec.UndoValue, "__DELETE_KEY__", StringComparison.OrdinalIgnoreCase)) {
                        return (val == null || val.ToString().Length == 0);
                    }
                    if (val == null) return false;
                    RegistryValueKind kind = k.GetValueKind(valName);
                    return ValuesMatch(val, kind, vt, spec.ApplyValue);
                }
            }
        }

        private static bool ProbeSingleServiceSpec(ServiceTweakSpec spec, out bool exists) {
            exists = false;
            if (spec == null || string.IsNullOrWhiteSpace(spec.Name)) return false;
            using (RegistryKey baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
            using (RegistryKey k = baseKey.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\" + spec.Name, false)) {
                if (k == null) return false;
                exists = true;
                object stObj = k.GetValue("Start");
                if (stObj == null) return false;
                try {
                    int st = Convert.ToInt32(stObj, CultureInfo.InvariantCulture);
                    return (st == spec.ApplyStart);
                } catch { return false; }
            }
        }

        private static string RunQuickCmdOut(string exe, string args, int timeoutMs) {
            try {
                var psi = new ProcessStartInfo();
                psi.FileName = exe;
                psi.Arguments = args;
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                using (Process p = Process.Start(psi)) {
                    if (p == null) return "";
                    Task<string> tOut = p.StandardOutput.ReadToEndAsync();
                    Task<string> tErr = p.StandardError.ReadToEndAsync();
                    if (!p.WaitForExit(timeoutMs)) {
                        try { p.Kill(); } catch {}
                        return "";
                    }
                    return tOut.Wait(500) ? (tOut.Result ?? "") : "";
                }
            } catch {
                return "";
            }
        }

        private static TweakProbeResult ProbeSpecialKind(TweakProbeRequest req, string activePowerScheme) {
            string kind = req.ProbeKind ?? "";
            if (string.Equals(kind, "Action", StringComparison.OrdinalIgnoreCase)) {
                return new TweakProbeResult { Id = req.Id, State = "Action", Detail = "" };
            }
            if (string.Equals(kind, "DnsCustom", StringComparison.OrdinalIgnoreCase)) {
                string detectedProvider = "";
                try {
                    using (RegistryKey b = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                    using (RegistryKey root = b.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces", false)) {
                        if (root != null) {
                            foreach (string sub in root.GetSubKeyNames()) {
                                using (RegistryKey sk = root.OpenSubKey(sub, false)) {
                                    if (sk == null) continue;
                                    string dhIp = (sk.GetValue("DhcpIPAddress") ?? "").ToString();
                                    string stIp = "";
                                    object ipObj = sk.GetValue("IPAddress");
                                    if (ipObj is string[]) {
                                        string[] arr = (string[])ipObj;
                                        if (arr.Length > 0) stIp = arr[0] ?? "";
                                    } else if (ipObj != null) {
                                        stIp = ipObj.ToString();
                                    }
                                    bool hasIp = (!string.IsNullOrWhiteSpace(dhIp) && dhIp != "0.0.0.0") ||
                                                 (!string.IsNullOrWhiteSpace(stIp) && stIp != "0.0.0.0");
                                    if (!hasIp) continue;
                                    string ns = (sk.GetValue("NameServer") ?? "").ToString().Trim();
                                    if (string.IsNullOrEmpty(ns)) continue;
                                    if (ns.IndexOf("1.1.1.1", StringComparison.Ordinal) >= 0) { detectedProvider = "Cloudflare (1.1.1.1)"; break; }
                                    if (ns.IndexOf("94.140.14.14", StringComparison.Ordinal) >= 0) { detectedProvider = "AdGuard Ch\u1EB7n QC (94.140.14.14)"; break; }
                                    if (ns.IndexOf("8.8.8.8", StringComparison.Ordinal) >= 0) { detectedProvider = "Google (8.8.8.8)"; break; }
                                    if (ns.IndexOf("9.9.9.9", StringComparison.Ordinal) >= 0) { detectedProvider = "Quad9 (9.9.9.9)"; break; }
                                }
                            }
                        }
                    }
                } catch {}
                if (!string.IsNullOrEmpty(detectedProvider)) {
                    return new TweakProbeResult { Id = req.Id, State = "Applied", Detail = detectedProvider };
                }
                return new TweakProbeResult { Id = req.Id, State = "Default", Detail = "M\u1EB7c \u0111\u1ECBnh (DHCP)" };
            }
            if (string.Equals(kind, "Hibernation", StringComparison.OrdinalIgnoreCase)) {
                bool hiberOff = false;
                try {
                    using (RegistryKey b = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                    using (RegistryKey k = b.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Power", false)) {
                        if (k != null) {
                            object v = k.GetValue("HibernateEnabled");
                            if (v != null && Convert.ToInt32(v, CultureInfo.InvariantCulture) == 0) hiberOff = true;
                        }
                    }
                } catch {}
                return new TweakProbeResult { Id = req.Id, State = hiberOff ? "Applied" : "Default", Detail = "" };
            }
            if (string.Equals(kind, "UltimatePerf", StringComparison.OrdinalIgnoreCase)) {
                bool isUlt = !string.IsNullOrEmpty(activePowerScheme) &&
                             (activePowerScheme.IndexOf("Ultimate Performance", StringComparison.OrdinalIgnoreCase) >= 0 ||
                              activePowerScheme.IndexOf("Hi\u1EC7u su\u1EA5t t\u1ED1i \u0111a", StringComparison.OrdinalIgnoreCase) >= 0 ||
                              activePowerScheme.IndexOf("Hi\u1EC7u n\u0103ng t\u1ED1i \u0111a", StringComparison.OrdinalIgnoreCase) >= 0 ||
                              activePowerScheme.IndexOf("e9a42b02-d5df-448d-aa00-03f14749eb61", StringComparison.OrdinalIgnoreCase) >= 0);
                return new TweakProbeResult { Id = req.Id, State = isUlt ? "Applied" : "Default", Detail = "" };
            }
            if (string.Equals(kind, "AdobeBlocked", StringComparison.OrdinalIgnoreCase)) {
                bool blocked = false;
                try {
                    string hosts = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"drivers\etc\hosts");
                    if (File.Exists(hosts)) {
                        string content = File.ReadAllText(hosts);
                        blocked = content.IndexOf("# AppDriver-AdobeBlock-Start", StringComparison.OrdinalIgnoreCase) >= 0;
                    }
                } catch {}
                return new TweakProbeResult { Id = req.Id, State = blocked ? "Applied" : "Default", Detail = "" };
            }
            if (string.Equals(kind, "OneDriveRemoved", StringComparison.OrdinalIgnoreCase)) {
                bool removed = true;
                try {
                    string p1 = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\OneDrive\OneDrive.exe");
                    string p2 = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"Microsoft OneDrive\OneDrive.exe");
                    string p3 = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"Microsoft OneDrive\OneDrive.exe");
                    if (File.Exists(p1) || File.Exists(p2) || File.Exists(p3)) removed = false;
                } catch {}
                return new TweakProbeResult { Id = req.Id, State = removed ? "Applied" : "Default", Detail = "" };
            }
            if (string.Equals(kind, "EdgeRemoved", StringComparison.OrdinalIgnoreCase)) {
                bool removed = true;
                try {
                    string p1 = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"Microsoft\Edge\Application\msedge.exe");
                    string p2 = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"Microsoft\Edge\Application\msedge.exe");
                    if (File.Exists(p1) || File.Exists(p2)) removed = false;
                } catch {}
                return new TweakProbeResult { Id = req.Id, State = removed ? "Applied" : "Default", Detail = "" };
            }
            if (string.Equals(kind, "NagleDisabled", StringComparison.OrdinalIgnoreCase)) {
                int checkedIf = 0;
                int matchedIf = 0;
                try {
                    using (RegistryKey b = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                    using (RegistryKey root = b.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces", false)) {
                        if (root != null) {
                            foreach (string sub in root.GetSubKeyNames()) {
                                using (RegistryKey sk = root.OpenSubKey(sub, false)) {
                                    if (sk == null) continue;
                                    string dhIp = (sk.GetValue("DhcpIPAddress") ?? "").ToString();
                                    string stIp = "";
                                    object ipObj = sk.GetValue("IPAddress");
                                    if (ipObj is string[]) {
                                        string[] arr = (string[])ipObj;
                                        if (arr.Length > 0) stIp = arr[0] ?? "";
                                    } else if (ipObj != null) {
                                        stIp = ipObj.ToString();
                                    }
                                    bool hasIp = (!string.IsNullOrWhiteSpace(dhIp) && dhIp != "0.0.0.0") ||
                                                 (!string.IsNullOrWhiteSpace(stIp) && stIp != "0.0.0.0");
                                    if (!hasIp) continue;
                                    checkedIf++;
                                    object a1 = sk.GetValue("TcpAckFrequency");
                                    object a2 = sk.GetValue("TCPNoDelay");
                                    if (a1 != null && a2 != null &&
                                        Convert.ToInt32(a1, CultureInfo.InvariantCulture) == 1 &&
                                        Convert.ToInt32(a2, CultureInfo.InvariantCulture) == 1) {
                                        matchedIf++;
                                    }
                                }
                            }
                        }
                    }
                } catch {}
                string st = (checkedIf > 0 && matchedIf == checkedIf) ? "Applied" : "Default";
                return new TweakProbeResult { Id = req.Id, State = st, Detail = "" };
            }
            if (string.Equals(kind, "WuPaused", StringComparison.OrdinalIgnoreCase)) {
                bool paused = false;
                try {
                    using (RegistryKey b = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                    using (RegistryKey k = b.OpenSubKey(@"SOFTWARE\Microsoft\WindowsUpdate\UX\Settings", false)) {
                        if (k != null) {
                            string p1 = (k.GetValue("PauseUpdatesExpiryTime") ?? "").ToString().Trim();
                            string p2 = (k.GetValue("PauseFeatureUpdatesEndTime") ?? "").ToString().Trim();
                            paused = (!string.IsNullOrEmpty(p1) || !string.IsNullOrEmpty(p2));
                        }
                    }
                } catch {}
                return new TweakProbeResult { Id = req.Id, State = paused ? "Applied" : "Default", Detail = "" };
            }
            if (string.Equals(kind, "ReservedStorageDisabled", StringComparison.OrdinalIgnoreCase)) {
                bool disabled = false;
                try {
                    using (RegistryKey b = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                    using (RegistryKey k = b.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager", false)) {
                        if (k != null) {
                            object pp = k.GetValue("PassedPolicy");
                            object bh = k.GetValue("BaseHardReserveSize");
                            if ((pp != null && Convert.ToInt64(pp, CultureInfo.InvariantCulture) == 0L) ||
                                (bh != null && Convert.ToInt64(bh, CultureInfo.InvariantCulture) == 0L)) {
                                disabled = true;
                            }
                        }
                    }
                } catch {}
                return new TweakProbeResult { Id = req.Id, State = disabled ? "Applied" : "Default", Detail = "" };
            }
            return null;
        }

        public static TweakProbeResult[] ProbeTweaksState(TweakProbeRequest[] requests) {
            if (requests == null || requests.Length == 0) return new TweakProbeResult[0];
            bool needPowerScheme = false;
            for (int i = 0; i < requests.Length; i++) {
                if (requests[i] != null && string.Equals(requests[i].ProbeKind, "UltimatePerf", StringComparison.OrdinalIgnoreCase)) {
                    needPowerScheme = true;
                    break;
                }
            }
            string activeScheme = needPowerScheme ? RunQuickCmdOut("powercfg.exe", "/getactivescheme", 2500) : "";

            var results = new TweakProbeResult[requests.Length];
            for (int i = 0; i < requests.Length; i++) {
                TweakProbeRequest req = requests[i];
                if (req == null) {
                    results[i] = new TweakProbeResult { Id = "", State = "Default", Detail = "" };
                    continue;
                }
                if (!string.IsNullOrEmpty(req.ProbeKind)) {
                    TweakProbeResult sp = ProbeSpecialKind(req, activeScheme);
                    if (sp != null) {
                        results[i] = sp;
                        continue;
                    }
                }

                int total = 0;
                int matched = 0;
                if (req.Registry != null) {
                    for (int r = 0; r < req.Registry.Length; r++) {
                        RegTweakSpec rs = req.Registry[r];
                        if (rs == null) continue;
                        if (string.Equals(rs.ApplyValue ?? "", rs.UndoValue ?? "", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(rs.UndoValue ?? "", "__SKIP__", StringComparison.OrdinalIgnoreCase)) {
                            continue;
                        }
                        total++;
                        try {
                            if (ProbeSingleRegSpec(rs)) matched++;
                        } catch {}
                    }
                }
                if (req.Services != null) {
                    for (int s = 0; s < req.Services.Length; s++) {
                        ServiceTweakSpec ss = req.Services[s];
                        if (ss == null || ss.ApplyStart == ss.UndoStart) continue;
                        bool exists;
                        bool ok = false;
                        try { ok = ProbeSingleServiceSpec(ss, out exists); } catch { exists = false; }
                        if (exists) {
                            total++;
                            if (ok) matched++;
                        }
                    }
                }

                string state;
                if (total == 0) {
                    state = "Action";
                } else if (matched == total) {
                    state = "Applied";
                } else {
                    state = "Default";
                }
                results[i] = new TweakProbeResult {
                    Id = req.Id,
                    State = state,
                    Detail = total > 0 ? (matched.ToString(CultureInfo.InvariantCulture) + "/" + total.ToString(CultureInfo.InvariantCulture)) : ""
                };
            }
            return results;
        }

        public static Task<TweakProbeResult[]> ProbeTweaksStateAsync(TweakProbeRequest[] requests) {
            return Task.Run(new Func<TweakProbeResult[]>(() => ProbeTweaksState(requests)));
        }

        public static RegistrySnapshotEntry[] CaptureRegistrySnapshots(RegTweakSpec[] specs) {
            var list = new List<RegistrySnapshotEntry>();
            if (specs == null || specs.Length == 0) return list.ToArray();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            for (int i = 0; i < specs.Length; i++) {
                RegTweakSpec s = specs[i];
                if (s == null || string.IsNullOrWhiteSpace(s.Path)) continue;
                string normName = NormalizeValueName(s.Name);
                string dedupKey = (s.Hive ?? "HKLM") + "|" + s.Path + "|" + normName;
                if (!seen.Add(dedupKey)) continue;

                var entry = new RegistrySnapshotEntry();
                entry.Hive = string.IsNullOrWhiteSpace(s.Hive) ? "HKLM" : s.Hive;
                entry.Path = s.Path;
                entry.Name = normName;
                entry.Existed = false;
                entry.KeyExisted = false;
                entry.Kind = "String";
                entry.ValueData = "";

                try {
                    using (RegistryKey baseKey = OpenHiveBase(entry.Hive))
                    using (RegistryKey k = baseKey.OpenSubKey(entry.Path, false)) {
                        if (k != null) {
                            entry.KeyExisted = true;
                            if (!string.Equals(s.ValueType, "DeleteKey", StringComparison.OrdinalIgnoreCase)) {
                                object val = k.GetValue(normName, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
                                if (val != null) {
                                    entry.Existed = true;
                                    RegistryValueKind kind = k.GetValueKind(normName);
                                    entry.Kind = kind.ToString();
                                    if (kind == RegistryValueKind.Binary && val is byte[]) {
                                        entry.ValueData = FormatHexBytes((byte[])val);
                                    } else if (kind == RegistryValueKind.MultiString && val is string[]) {
                                        entry.ValueData = string.Join("\n", (string[])val);
                                    } else {
                                        entry.ValueData = Convert.ToString(val, CultureInfo.InvariantCulture) ?? "";
                                    }
                                }
                            }
                        }
                    }
                } catch {}
                list.Add(entry);
            }
            return list.ToArray();
        }

        public static ServiceSnapshotEntry[] CaptureServiceSnapshots(ServiceTweakSpec[] specs) {
            var list = new List<ServiceSnapshotEntry>();
            if (specs == null || specs.Length == 0) return list.ToArray();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            using (RegistryKey baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)) {
                for (int i = 0; i < specs.Length; i++) {
                    ServiceTweakSpec s = specs[i];
                    if (s == null || string.IsNullOrWhiteSpace(s.Name)) continue;
                    if (!seen.Add(s.Name)) continue;

                    var entry = new ServiceSnapshotEntry();
                    entry.Name = s.Name;
                    entry.Existed = false;
                    entry.OriginalStart = 3;
                    try {
                        using (RegistryKey k = baseKey.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\" + s.Name, false)) {
                            if (k != null) {
                                object stObj = k.GetValue("Start");
                                if (stObj != null) {
                                    entry.Existed = true;
                                    entry.OriginalStart = Convert.ToInt32(stObj, CultureInfo.InvariantCulture);
                                }
                            }
                        }
                    } catch {}
                    if (entry.Existed) list.Add(entry);
                }
            }
            return list.ToArray();
        }

        private static bool WriteRegistryValueTyped(RegistryKey baseKey, string path, string name, string valueType, string rawValue, out string errMsg) {
            errMsg = "";
            string vt = (valueType ?? "DWord").Trim();
            string normName = NormalizeValueName(name);

            if (string.Equals(vt, "DeleteKey", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(rawValue, "__DELETE_KEY__", StringComparison.OrdinalIgnoreCase)) {
                try {
                    string delPath = path;
                    if (delPath.EndsWith(@"\InprocServer32", StringComparison.OrdinalIgnoreCase)) {
                        delPath = delPath.Substring(0, delPath.Length - @"\InprocServer32".Length);
                    }
                    baseKey.DeleteSubKeyTree(delPath, false);
                    return true;
                } catch (Exception ex) { errMsg = ex.Message; return false; }
            }

            if (string.Equals(vt, "DeleteValue", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(rawValue, "__DELETE__", StringComparison.OrdinalIgnoreCase)) {
                try {
                    using (RegistryKey k = baseKey.OpenSubKey(path, true)) {
                        if (k != null) {
                            k.DeleteValue(normName, false);
                        }
                    }
                    return true;
                } catch (Exception ex) { errMsg = ex.Message; return false; }
            }

            RegistryKey targetKey = null;
            try {
                try {
                    targetKey = baseKey.OpenSubKey(path, true);
                } catch (Exception openEx) {
                    errMsg = openEx.Message;
                    targetKey = null;
                }
                if (targetKey == null) {
                    targetKey = baseKey.CreateSubKey(path, RegistryKeyPermissionCheck.ReadWriteSubTree);
                }
                if (targetKey == null) {
                    if (string.IsNullOrEmpty(errMsg)) errMsg = "CreateSubKey returned null";
                    return false;
                }
                if (string.Equals(vt, "DWord", StringComparison.OrdinalIgnoreCase)) {
                    long lv;
                    if (!TryParseInt64Flexible(rawValue, out lv)) { errMsg = "Invalid DWord: " + rawValue; return false; }
                    targetKey.SetValue(normName, unchecked((int)lv), RegistryValueKind.DWord);
                    return true;
                }
                if (string.Equals(vt, "QWord", StringComparison.OrdinalIgnoreCase)) {
                    long lv;
                    if (!TryParseInt64Flexible(rawValue, out lv)) { errMsg = "Invalid QWord: " + rawValue; return false; }
                    targetKey.SetValue(normName, lv, RegistryValueKind.QWord);
                    return true;
                }
                if (string.Equals(vt, "Binary", StringComparison.OrdinalIgnoreCase)) {
                    byte[] bytes = ParseHexBytes(rawValue);
                    targetKey.SetValue(normName, bytes, RegistryValueKind.Binary);
                    return true;
                }
                if (string.Equals(vt, "ExpandString", StringComparison.OrdinalIgnoreCase)) {
                    targetKey.SetValue(normName, rawValue ?? "", RegistryValueKind.ExpandString);
                    return true;
                }
                if (string.Equals(vt, "MultiString", StringComparison.OrdinalIgnoreCase)) {
                    string[] parts = string.IsNullOrEmpty(rawValue) ? new string[0] : rawValue.Split(new char[] { '\n' });
                    targetKey.SetValue(normName, parts, RegistryValueKind.MultiString);
                    return true;
                }
                targetKey.SetValue(normName, rawValue ?? "", RegistryValueKind.String);
                return true;
            } catch (Exception ex) {
                errMsg = ex.Message;
                return false;
            } finally {
                if (targetKey != null) { try { targetKey.Dispose(); } catch {} }
            }
        }

        private static bool WriteRegistryValueTyped(RegistryKey baseKey, string path, string name, string valueType, string rawValue) {
            string ignored;
            return WriteRegistryValueTyped(baseKey, path, name, valueType, rawValue, out ignored);
        }

        private static readonly string[] ExactProtectedServices = new string[] {
            "Power", "PlugPlay", "SystemEventsBroker", "TimeBrokerSvc", "BrokerInfrastructure",
            "WpnService", "ShellHWDetection", "HidServ", "AudioSrv", "AudioEndpointBuilder",
            "MMCSS", "CDPSvc", "DPS", "FontCache", "iphlpsvc", "PcaSvc", "SysMain", "TrkWks",
            "BthAvctpSvc", "bthserv", "WlanSvc", "Dhcp", "Dnscache", "NlaSvc", "netprofm",
            "nsi", "RpcSs", "DcomLaunch", "LSM", "SamSs", "Schedule", "EventLog", "Winmgmt",
            "ProfSvc", "UserManager", "StateRepository", "AppXSvc", "ClipSVC", "LicenseManager",
            "MsKeyboardFilter", "DialogBlockingService", "IBMPMSVC", "LITSSVC", "LightingService",
            "AcPowerNotification", "AsHidSrv", "AsSysCtrlService", "accSvc", "QAAdminAgent",
            "DPMService", "FvSvc", "esifsvc"
        };

        private static readonly string[] ProtectedServicePrefixes = new string[] {
            "Lenovo", "Legion", "ImController", "TPHK", "LZService", "PcManager",
            "ASUS", "Armoury", "ROG", "Aura", "ATK",
            "MSI", "Micro Star", "DragonCenter", "Mystic_Light", "NTIOLib", "SCM",
            "Acer", "Nitro", "Predator", "PSService", "PSAgent", "UePM", "DtsApo",
            "Dell", "Alienware", "AWCC", "DDV", "SupportAssist",
            "HP", "Omen", "HpTouchpoint",
            "Gigabyte", "Aorus", "GCC", "GvBios", "SmartManager",
            "Razer", "RzAction", "Logi", "LGHUB", "Corsair", "iCUE", "SteelSeries",
            "Samsung", "LG", "Huawei", "MBAE", "Xiaomi", "Surface",
            "NVDisplay", "NVIDIA", "NvContainer", "AMD", "Ati", "Intel", "igfx", "dptf", "ipf",
            "Rtk", "Realtek", "Dolby", "DAX3", "Nahimic", "Waves", "DTS", "SynTP", "ETD", "ELAN",
            "WpnUserService", "CDPUserSvc"
        };

        public static bool IsProtectedCriticalOrOemService(string serviceName) {
            if (string.IsNullOrWhiteSpace(serviceName)) return false;
            string sn = serviceName.Trim();
            for (int i = 0; i < ExactProtectedServices.Length; i++) {
                if (string.Equals(sn, ExactProtectedServices[i], StringComparison.OrdinalIgnoreCase)) {
                    return true;
                }
            }
            for (int i = 0; i < ProtectedServicePrefixes.Length; i++) {
                if (sn.StartsWith(ProtectedServicePrefixes[i], StringComparison.OrdinalIgnoreCase)) {
                    return true;
                }
            }
            return false;
        }

        public static ApplyRegBatchResult ApplyRegistrySpecsDetailed(RegTweakSpec[] specs, bool undo) {
            var errs = new List<string>();
            if (specs == null || specs.Length == 0) {
                return new ApplyRegBatchResult { OkCount = 0, TotalCount = 0, Errors = new string[0] };
            }
            int okCount = 0;
            for (int i = 0; i < specs.Length; i++) {
                RegTweakSpec s = specs[i];
                if (s == null || string.IsNullOrWhiteSpace(s.Path)) continue;
                string targetVal = undo ? s.UndoValue : s.ApplyValue;
                string targetType = s.ValueType ?? "DWord";
                if (!undo) {
                    if (string.Equals(s.Name, "GlobalUserDisabled", StringComparison.OrdinalIgnoreCase) &&
                        s.Path.IndexOf("BackgroundAccessApplications", StringComparison.OrdinalIgnoreCase) >= 0) {
                        targetVal = "0";
                    }
                    if (string.Equals(s.Name, "LetAppsRunInBackground", StringComparison.OrdinalIgnoreCase) &&
                        s.Path.IndexOf("AppPrivacy", StringComparison.OrdinalIgnoreCase) >= 0 &&
                        string.Equals(targetVal, "2", StringComparison.OrdinalIgnoreCase)) {
                        okCount++;
                        continue;
                    }
                }
                if (undo && string.Equals(s.Name, "SvcHostSplitThresholdInKB", StringComparison.OrdinalIgnoreCase)) {
                    try {
                        ulong installedKb;
                        if (GetPhysicallyInstalledSystemMemory(out installedKb) && installedKb > 0) {
                            targetVal = installedKb.ToString(CultureInfo.InvariantCulture);
                        } else {
                            MEMORYSTATUSEX mem = new MEMORYSTATUSEX();
                            mem.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
                            if (GlobalMemoryStatusEx(ref mem) && mem.ullTotalPhys > 0) {
                                ulong kb = mem.ullTotalPhys / 1024UL;
                                targetVal = kb.ToString(CultureInfo.InvariantCulture);
                            }
                        }
                    } catch {}
                }
                if (undo && string.Equals(targetType, "DeleteKey", StringComparison.OrdinalIgnoreCase)) {
                    if (string.Equals(targetVal, "__CREATE_KEY__", StringComparison.OrdinalIgnoreCase)) {
                        try {
                            using (RegistryKey baseKey = OpenHiveBase(s.Hive))
                            using (RegistryKey k = baseKey.CreateSubKey(s.Path)) {
                                if (k != null) okCount++;
                            }
                        } catch (Exception ex) { errs.Add((s.Hive ?? "HKLM") + "\\" + s.Path + ": " + ex.Message); }
                    }
                    continue;
                }
                if (undo && string.Equals(targetVal, "__SKIP__", StringComparison.OrdinalIgnoreCase)) {
                    okCount++;
                    continue;
                }
                using (RegistryKey baseKey = OpenHiveBase(s.Hive)) {
                    string writeErr;
                    if (WriteRegistryValueTyped(baseKey, s.Path, s.Name, targetType, targetVal, out writeErr)) {
                        okCount++;
                    } else {
                        errs.Add((s.Hive ?? "HKLM") + "\\" + s.Path + " [" + (s.Name ?? "") + "]: " + writeErr);
                    }
                }
            }
            return new ApplyRegBatchResult {
                OkCount = okCount,
                TotalCount = specs.Length,
                Errors = errs.ToArray()
            };
        }

        public static Task<ApplyRegBatchResult> ApplyRegistrySpecsDetailedAsync(RegTweakSpec[] specs, bool undo) {
            return Task.Run(delegate() { return ApplyRegistrySpecsDetailed(specs, undo); });
        }

        public static int ApplyRegistrySpecs(RegTweakSpec[] specs, bool undo) {
            return ApplyRegistrySpecsDetailed(specs, undo).OkCount;
        }

        public static Task<int> ApplyServiceSpecsAsync(ServiceTweakSpec[] specs, bool undo) {
            return Task.Run(delegate() { return ApplyServiceSpecs(specs, undo); });
        }

        public static Task<int> SetScheduledTasksEnabledAsync(string[] tasks, bool enable) {
            return Task.Run(delegate() {
                if (tasks == null || tasks.Length == 0) return 0;
                int done = 0;
                string flag = enable ? "/Enable" : "/Disable";
                for (int i = 0; i < tasks.Length; i++) {
                    string tk = tasks[i];
                    if (string.IsNullOrWhiteSpace(tk)) continue;
                    try {
                        var psi = new ProcessStartInfo();
                        psi.FileName = "schtasks.exe";
                        psi.Arguments = "/Change /TN \"" + tk.Replace("\"", "") + "\" " + flag;
                        psi.CreateNoWindow = true;
                        psi.UseShellExecute = false;
                        psi.RedirectStandardOutput = true;
                        psi.RedirectStandardError = true;
                        using (Process p = Process.Start(psi)) {
                            if (p != null) {
                                var tOut = p.StandardOutput.ReadToEndAsync();
                                var tErr = p.StandardError.ReadToEndAsync();
                                if (!p.WaitForExit(5000)) { try { p.Kill(); } catch {} }
                                else if (p.ExitCode == 0) { done++; }
                                GC.KeepAlive(tOut); GC.KeepAlive(tErr);
                            }
                        }
                    } catch {}
                }
                return done;
            });
        }

        public static Task<bool> ApplyDnsAsync(string primaryDns, string secondaryDns, bool resetDhcp) {
            return Task.Run(delegate() {
                try {
                    var targetIndices = new List<int>();
                    var fallbackIndices = new List<int>();
                    NetworkInterface[] nics = NetworkInterface.GetAllNetworkInterfaces();
                    for (int i = 0; i < nics.Length; i++) {
                        NetworkInterface ni = nics[i];
                        if (ni == null || ni.OperationalStatus != OperationalStatus.Up) continue;
                        if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback ||
                            ni.NetworkInterfaceType == NetworkInterfaceType.Tunnel) continue;
                        try {
                            IPInterfaceProperties props = ni.GetIPProperties();
                            if (props == null) continue;
                            IPv4InterfaceProperties v4 = props.GetIPv4Properties();
                            if (v4 == null || v4.Index <= 0) continue;
                            string desc = ni.Description ?? "";
                            bool isVirtual = desc.IndexOf("Virtual", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                             desc.IndexOf("Hyper-V", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                             desc.IndexOf("VMware", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                             desc.IndexOf("VirtualBox", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                             desc.IndexOf("TAP-", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                             desc.IndexOf("Wintun", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                             desc.IndexOf("Loopback", StringComparison.OrdinalIgnoreCase) >= 0;
                            if (!isVirtual) targetIndices.Add(v4.Index);
                            else fallbackIndices.Add(v4.Index);
                        } catch {}
                    }
                    if (targetIndices.Count == 0) targetIndices = fallbackIndices;
                    if (targetIndices.Count == 0) return false;

                    int okNics = 0;
                    for (int i = 0; i < targetIndices.Count; i++) {
                        int idx = targetIndices[i];
                        string idxStr = idx.ToString(CultureInfo.InvariantCulture);
                        if (resetDhcp || string.IsNullOrWhiteSpace(primaryDns)) {
                            if (RunHiddenNetsh("interface ipv4 set dnsservers name=" + idxStr + " source=dhcp", 8000)) okNics++;
                        } else {
                            if (RunHiddenNetsh("interface ipv4 set dnsservers name=" + idxStr + " source=static address=" + primaryDns + " register=primary validate=no", 8000)) {
                                okNics++;
                                if (!string.IsNullOrWhiteSpace(secondaryDns)) {
                                    RunHiddenNetsh("interface ipv4 add dnsservers name=" + idxStr + " address=" + secondaryDns + " index=2 validate=no", 8000);
                                }
                            }
                        }
                    }
                    RunQuickCmdOut("ipconfig.exe", "/flushdns", 4000);
                    return okNics > 0;
                } catch {
                    return false;
                }
            });
        }

        private static bool RunHiddenNetsh(string args, int timeoutMs) {
            try {
                var psi = new ProcessStartInfo();
                psi.FileName = "netsh.exe";
                psi.Arguments = args;
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                using (Process p = Process.Start(psi)) {
                    if (p == null) return false;
                    var tOut = p.StandardOutput.ReadToEndAsync();
                    var tErr = p.StandardError.ReadToEndAsync();
                    if (!p.WaitForExit(timeoutMs)) {
                        try { p.Kill(); } catch {}
                        return false;
                    }
                    GC.KeepAlive(tOut); GC.KeepAlive(tErr);
                    return p.ExitCode == 0;
                }
            } catch {
                return false;
            }
        }

        public static Task RestartExplorerSoftAsync() {
            return Task.Run(delegate() {
                try {
                    Process[] procs = Process.GetProcessesByName("explorer");
                    for (int i = 0; i < procs.Length; i++) {
                        try { procs[i].Kill(); } catch {}
                        try { procs[i].Dispose(); } catch {}
                    }
                    Thread.Sleep(650);
                    Process[] after = Process.GetProcessesByName("explorer");
                    bool anyAlive = after != null && after.Length > 0;
                    if (after != null) {
                        for (int i = 0; i < after.Length; i++) { try { after[i].Dispose(); } catch {} }
                    }
                    if (!anyAlive) {
                        Process.Start("explorer.exe");
                    }
                } catch {}
            });
        }

        public static int RestoreRegistrySnapshots(RegistrySnapshotEntry[] entries) {
            if (entries == null || entries.Length == 0) return 0;
            int restored = 0;
            for (int i = 0; i < entries.Length; i++) {
                RegistrySnapshotEntry e = entries[i];
                if (e == null || string.IsNullOrWhiteSpace(e.Path)) continue;
                using (RegistryKey baseKey = OpenHiveBase(e.Hive)) {
                    if (!e.KeyExisted) {
                        try { baseKey.DeleteSubKeyTree(e.Path, false); restored++; } catch {}
                    } else if (!e.Existed) {
                        if (WriteRegistryValueTyped(baseKey, e.Path, e.Name, "DeleteValue", "__DELETE__")) restored++;
                    } else {
                        if (WriteRegistryValueTyped(baseKey, e.Path, e.Name, e.Kind ?? "String", e.ValueData ?? "")) restored++;
                    }
                }
            }
            return restored;
        }

        public static int ApplyServiceSpecs(ServiceTweakSpec[] specs, bool undo) {
            if (specs == null || specs.Length == 0) return 0;
            int changed = 0;
            using (RegistryKey baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)) {
                for (int i = 0; i < specs.Length; i++) {
                    ServiceTweakSpec s = specs[i];
                    if (s == null || string.IsNullOrWhiteSpace(s.Name)) continue;
                    if (!undo && IsProtectedCriticalOrOemService(s.Name)) {
                        continue;
                    }
                    int targetStart = undo ? s.UndoStart : s.ApplyStart;
                    if (targetStart < 2 || targetStart > 4) continue;
                    try {
                        using (RegistryKey k = baseKey.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\" + s.Name, true)) {
                            if (k == null) continue;
                            object curObj = k.GetValue("Start");
                            if (curObj == null) continue;
                            int curStart = Convert.ToInt32(curObj, CultureInfo.InvariantCulture);
                            if (curStart <= 1) continue;
                            if (curStart != targetStart) {
                                k.SetValue("Start", targetStart, RegistryValueKind.DWord);
                            }
                            changed++;
                        }
                    } catch {}
                }
            }
            return changed;
        }

        public static int RestoreServiceSnapshots(ServiceSnapshotEntry[] entries) {
            if (entries == null || entries.Length == 0) return 0;
            int restored = 0;
            using (RegistryKey baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)) {
                for (int i = 0; i < entries.Length; i++) {
                    ServiceSnapshotEntry e = entries[i];
                    if (e == null || !e.Existed || string.IsNullOrWhiteSpace(e.Name)) continue;
                    if (e.OriginalStart < 2 || e.OriginalStart > 4) continue;
                    try {
                        using (RegistryKey k = baseKey.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\" + e.Name, true)) {
                            if (k == null) continue;
                            object curObj = k.GetValue("Start");
                            if (curObj == null) continue;
                            int curStart = Convert.ToInt32(curObj, CultureInfo.InvariantCulture);
                            if (curStart <= 1) continue;
                            k.SetValue("Start", e.OriginalStart, RegistryValueKind.DWord);
                            restored++;
                        }
                    } catch {}
                }
            }
            return restored;
        }
    }
}
