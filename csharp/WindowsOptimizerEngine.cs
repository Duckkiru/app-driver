using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
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
        private const uint StorageDeviceSeekPenaltyProperty = 7;
        private const uint PropertyStandardQuery = 0;

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS sps);

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

        private static bool DetectSystemDriveIsSsd() {
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
                if (hDisk == INVALID_HANDLE_VALUE) return true;

                STORAGE_PROPERTY_QUERY q = new STORAGE_PROPERTY_QUERY();
                q.PropertyId = StorageDeviceSeekPenaltyProperty;
                q.QueryType = PropertyStandardQuery;

                int qSize = Marshal.SizeOf(typeof(STORAGE_PROPERTY_QUERY));
                int dSize = Marshal.SizeOf(typeof(DEVICE_SEEK_PENALTY_DESCRIPTOR));
                IntPtr qBuf = Marshal.AllocHGlobal(qSize);
                IntPtr dBuf = Marshal.AllocHGlobal(dSize);
                try {
                    Marshal.StructureToPtr(q, qBuf, false);
                    uint retBytes;
                    if (DeviceIoControl(hDisk, IOCTL_STORAGE_QUERY_PROPERTY, qBuf, (uint)qSize, dBuf, (uint)dSize, out retBytes, IntPtr.Zero)) {
                        DEVICE_SEEK_PENALTY_DESCRIPTOR desc = (DEVICE_SEEK_PENALTY_DESCRIPTOR)Marshal.PtrToStructure(dBuf, typeof(DEVICE_SEEK_PENALTY_DESCRIPTOR));
                        return !desc.IncursSeekPenalty;
                    }
                } finally {
                    Marshal.FreeHGlobal(qBuf);
                    Marshal.FreeHGlobal(dBuf);
                }
            } catch {
            } finally {
                if (hDisk != INVALID_HANDLE_VALUE) { try { CloseHandle(hDisk); } catch {} }
                if (hVol != INVALID_HANDLE_VALUE) { try { CloseHandle(hVol); } catch {} }
            }
            return true;
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

            try {
                SYSTEM_POWER_STATUS sps;
                if (GetSystemPowerStatus(out sps)) {
                    hp.IsLaptop = (sps.BatteryFlag != 128 && sps.BatteryFlag != 255);
                }
            } catch {}

            try {
                MEMORYSTATUSEX mem = new MEMORYSTATUSEX();
                mem.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
                if (GlobalMemoryStatusEx(ref mem) && mem.ullTotalPhys > 0) {
                    double gb = (double)mem.ullTotalPhys / 1073741824.0;
                    hp.TotalRamGb = Math.Max(1, (int)Math.Round(gb));
                }
            } catch {}

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
            hp.IsSystemDriveSsd = DetectSystemDriveIsSsd();

            string devType = hp.IsLaptop ? "Laptop" : "PC";
            string driveType = hp.IsSystemDriveSsd ? "SSD" : "HDD";
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
            string actStr = actual.ToString();
            return string.Equals(actStr, expectedStr ?? "", StringComparison.OrdinalIgnoreCase);
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
                    if (spec.ApplyStart == 3) return (st == 3 || st == 4);
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
                    string txt = p.StandardOutput.ReadToEnd();
                    p.WaitForExit(timeoutMs);
                    return txt ?? "";
                }
            } catch {
                return "";
            }
        }

        private static TweakProbeResult ProbeSpecialKind(TweakProbeRequest req, string activePowerScheme) {
            string kind = req.ProbeKind ?? "";
            if (string.Equals(kind, "Action", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(kind, "DnsCustom", StringComparison.OrdinalIgnoreCase)) {
                return new TweakProbeResult { Id = req.Id, State = "Action", Detail = "" };
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
                string st = (checkedIf > 0 && matchedIf == checkedIf) ? "Applied" : (matchedIf > 0 ? "Partial" : "Default");
                return new TweakProbeResult { Id = req.Id, State = st, Detail = "" };
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
                        total++;
                        try {
                            if (ProbeSingleRegSpec(req.Registry[r])) matched++;
                        } catch {}
                    }
                }
                if (req.Services != null) {
                    for (int s = 0; s < req.Services.Length; s++) {
                        bool exists;
                        bool ok = false;
                        try { ok = ProbeSingleServiceSpec(req.Services[s], out exists); } catch { exists = false; }
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
                } else if (matched > 0 && req.Services != null && req.Services.Length >= 10 && matched >= (int)(total * 0.85)) {
                    state = "Applied";
                } else if (matched > 0) {
                    state = "Partial";
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

        private static bool WriteRegistryValueTyped(RegistryKey baseKey, string path, string name, string valueType, string rawValue) {
            string vt = (valueType ?? "DWord").Trim();
            string normName = NormalizeValueName(name);

            if (string.Equals(vt, "DeleteKey", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(rawValue, "__DELETE_KEY__", StringComparison.OrdinalIgnoreCase)) {
                try {
                    baseKey.DeleteSubKeyTree(path, false);
                    return true;
                } catch { return false; }
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
                } catch { return false; }
            }

            try {
                using (RegistryKey k = baseKey.CreateSubKey(path, RegistryKeyPermissionCheck.ReadWriteSubTree)) {
                    if (k == null) return false;
                    if (string.Equals(vt, "DWord", StringComparison.OrdinalIgnoreCase)) {
                        long lv;
                        if (!TryParseInt64Flexible(rawValue, out lv)) return false;
                        k.SetValue(normName, unchecked((int)lv), RegistryValueKind.DWord);
                        return true;
                    }
                    if (string.Equals(vt, "QWord", StringComparison.OrdinalIgnoreCase)) {
                        long lv;
                        if (!TryParseInt64Flexible(rawValue, out lv)) return false;
                        k.SetValue(normName, lv, RegistryValueKind.QWord);
                        return true;
                    }
                    if (string.Equals(vt, "Binary", StringComparison.OrdinalIgnoreCase)) {
                        byte[] bytes = ParseHexBytes(rawValue);
                        k.SetValue(normName, bytes, RegistryValueKind.Binary);
                        return true;
                    }
                    if (string.Equals(vt, "ExpandString", StringComparison.OrdinalIgnoreCase)) {
                        k.SetValue(normName, rawValue ?? "", RegistryValueKind.ExpandString);
                        return true;
                    }
                    if (string.Equals(vt, "MultiString", StringComparison.OrdinalIgnoreCase)) {
                        string[] parts = string.IsNullOrEmpty(rawValue) ? new string[0] : rawValue.Split(new char[] { '\n' });
                        k.SetValue(normName, parts, RegistryValueKind.MultiString);
                        return true;
                    }
                    k.SetValue(normName, rawValue ?? "", RegistryValueKind.String);
                    return true;
                }
            } catch {
                return false;
            }
        }

        public static int ApplyRegistrySpecs(RegTweakSpec[] specs, bool undo) {
            if (specs == null || specs.Length == 0) return 0;
            int okCount = 0;
            for (int i = 0; i < specs.Length; i++) {
                RegTweakSpec s = specs[i];
                if (s == null || string.IsNullOrWhiteSpace(s.Path)) continue;
                string targetVal = undo ? s.UndoValue : s.ApplyValue;
                string targetType = s.ValueType ?? "DWord";
                if (undo && string.Equals(targetType, "DeleteKey", StringComparison.OrdinalIgnoreCase)) {
                    if (string.Equals(targetVal, "__CREATE_KEY__", StringComparison.OrdinalIgnoreCase)) {
                        try {
                            using (RegistryKey baseKey = OpenHiveBase(s.Hive))
                            using (RegistryKey k = baseKey.CreateSubKey(s.Path)) {
                                if (k != null) okCount++;
                            }
                        } catch {}
                    }
                    continue;
                }
                if (undo && string.Equals(targetVal, "__SKIP__", StringComparison.OrdinalIgnoreCase)) {
                    okCount++;
                    continue;
                }
                using (RegistryKey baseKey = OpenHiveBase(s.Hive)) {
                    if (WriteRegistryValueTyped(baseKey, s.Path, s.Name, targetType, targetVal)) {
                        okCount++;
                    }
                }
            }
            return okCount;
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
