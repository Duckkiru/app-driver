using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace DuckUtil {

    public sealed class HardwareProfile {
        public bool IsLaptop { get; set; }
        public bool HasBattery { get; set; }
        public int TotalRamGb { get; set; }
        public int OsBuild { get; set; }
        public bool IsWin11 { get; set; }
        public string OsDisplayVersion { get; set; }
        public bool IsSystemDriveSsd { get; set; }
        public bool DiskTypeKnown { get; set; }
        public string SummaryText { get; set; }
    }

    public sealed class TweakRegRule {
        public string Path { get; set; }
        public string Name { get; set; }
        public string ValueType { get; set; }
        public string ApplyValue { get; set; }
        public string UndoValue { get; set; }
        public bool DeleteOnUndo { get; set; }
        public bool DeleteOnApply { get; set; }
    }

    public sealed class TweakProbeSpec {
        public string Id { get; set; }
        public int MinBuild { get; set; }
        public string ActionKind { get; set; }
        public string ActionParam { get; set; }
        public TweakRegRule[] RegRules { get; set; }
        public string[] Services { get; set; }
    }

    public sealed class TweakProbeResult {
        public string Id { get; set; }
        public bool IsApplied { get; set; }
        public bool Supported { get; set; }
        public string Detail { get; set; }
    }

    public sealed class RegSnapshotRecord {
        public string Path { get; set; }
        public string Name { get; set; }
        public bool Existed { get; set; }
        public string ValueType { get; set; }
        public string ValueData { get; set; }
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
        private class MEMORYSTATUSEX {
            public uint dwLength;
            public uint dwMemoryLoad;
            public ulong ullTotalPhys;
            public ulong ullAvailPhys;
            public ulong ullTotalPageFile;
            public ulong ullAvailPageFile;
            public ulong ullTotalVirtual;
            public ulong ullAvailVirtual;
            public ulong ullAvailExtendedVirtual;
            public MEMORYSTATUSEX() {
                dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
            }
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

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS sps);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);

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
            ref STORAGE_PROPERTY_QUERY lpInBuffer,
            uint nInBufferSize,
            out DEVICE_SEEK_PENALTY_DESCRIPTOR lpOutBuffer,
            uint nOutBufferSize,
            out uint lpBytesReturned,
            IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr hObject);

        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint OPEN_EXISTING = 3;
        private const uint IOCTL_STORAGE_QUERY_PROPERTY = 0x002D1400;
        private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

        public static HardwareProfile DetectHardwareProfile() {
            var prof = new HardwareProfile();
            try {
                SYSTEM_POWER_STATUS sps;
                if (GetSystemPowerStatus(out sps)) {
                    // BatteryFlag 128 = No system battery, 255 = Unknown
                    bool hasBat = (sps.BatteryFlag != 128 && sps.BatteryFlag != 255);
                    prof.HasBattery = hasBat;
                    prof.IsLaptop = hasBat;
                }
            } catch {}

            try {
                var ms = new MEMORYSTATUSEX();
                if (GlobalMemoryStatusEx(ms)) {
                    double gb = (double)ms.ullTotalPhys / (1024.0 * 1024.0 * 1024.0);
                    prof.TotalRamGb = (int)Math.Round(gb);
                }
            } catch {}

            try {
                using (RegistryKey cv = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion", false)) {
                    if (cv != null) {
                        object bObj = cv.GetValue("CurrentBuildNumber");
                        int bNum = 0;
                        if (bObj != null && int.TryParse(bObj.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out bNum)) {
                            prof.OsBuild = bNum;
                        }
                        object dvObj = cv.GetValue("DisplayVersion");
                        if (dvObj == null) dvObj = cv.GetValue("ReleaseId");
                        prof.OsDisplayVersion = dvObj != null ? dvObj.ToString() : "";
                    }
                }
            } catch {}

            prof.IsWin11 = (prof.OsBuild >= 22000);

            try {
                string sysRoot = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
                string driveLetter = (!string.IsNullOrEmpty(sysRoot) && sysRoot.Length >= 2) ? sysRoot.Substring(0, 2) : "C:";
                IntPtr hVol = CreateFileW(@"\\.\" + driveLetter, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
                if (hVol != INVALID_HANDLE_VALUE && hVol != IntPtr.Zero) {
                    try {
                        var query = new STORAGE_PROPERTY_QUERY();
                        query.PropertyId = 7; // StorageDeviceSeekPenaltyProperty
                        query.QueryType = 0;  // PropertyStandardQuery
                        DEVICE_SEEK_PENALTY_DESCRIPTOR desc;
                        uint bytesRet = 0;
                        if (DeviceIoControl(hVol, IOCTL_STORAGE_QUERY_PROPERTY, ref query, (uint)Marshal.SizeOf(typeof(STORAGE_PROPERTY_QUERY)),
                            out desc, (uint)Marshal.SizeOf(typeof(DEVICE_SEEK_PENALTY_DESCRIPTOR)), out bytesRet, IntPtr.Zero)) {
                            prof.IsSystemDriveSsd = !desc.IncursSeekPenalty;
                            prof.DiskTypeKnown = true;
                        }
                    } finally {
                        CloseHandle(hVol);
                    }
                }
            } catch {}

            string devType = prof.IsLaptop ? "Laptop" : "PC B\u00E0n";
            string ramPart = prof.TotalRamGb > 0 ? (prof.TotalRamGb.ToString(CultureInfo.InvariantCulture) + " GB RAM") : "";
            string diskPart = prof.DiskTypeKnown ? (prof.IsSystemDriveSsd ? "SSD" : "HDD") : "";
            string osPart = (prof.IsWin11 ? "Win 11" : "Win 10") +
                            (!string.IsNullOrEmpty(prof.OsDisplayVersion) ? (" " + prof.OsDisplayVersion) : "") +
                            (prof.OsBuild > 0 ? (" (" + prof.OsBuild.ToString(CultureInfo.InvariantCulture) + ")") : "");

            var parts = new List<string>();
            parts.Add(devType);
            if (!string.IsNullOrEmpty(ramPart)) parts.Add(ramPart);
            if (!string.IsNullOrEmpty(diskPart)) parts.Add(diskPart);
            if (!string.IsNullOrEmpty(osPart)) parts.Add(osPart);
            prof.SummaryText = string.Join(" \u2022 ", parts.ToArray());
            return prof;
        }

        private static bool TryParseRegistryPath(string fullPath, out RegistryKey rootKey, out string subPath) {
            rootKey = null;
            subPath = "";
            if (string.IsNullOrWhiteSpace(fullPath)) return false;
            string p = fullPath.Trim();
            if (p.StartsWith("HKLM:\\", StringComparison.OrdinalIgnoreCase)) {
                rootKey = Registry.LocalMachine;
                subPath = p.Substring(6);
                return true;
            }
            if (p.StartsWith("HKEY_LOCAL_MACHINE\\", StringComparison.OrdinalIgnoreCase)) {
                rootKey = Registry.LocalMachine;
                subPath = p.Substring(19);
                return true;
            }
            if (p.StartsWith("HKCU:\\", StringComparison.OrdinalIgnoreCase)) {
                rootKey = Registry.CurrentUser;
                subPath = p.Substring(6);
                return true;
            }
            if (p.StartsWith("HKEY_CURRENT_USER\\", StringComparison.OrdinalIgnoreCase)) {
                rootKey = Registry.CurrentUser;
                subPath = p.Substring(18);
                return true;
            }
            if (p.StartsWith("HKCR:\\", StringComparison.OrdinalIgnoreCase)) {
                rootKey = Registry.ClassesRoot;
                subPath = p.Substring(6);
                return true;
            }
            if (p.StartsWith("HKU:\\", StringComparison.OrdinalIgnoreCase)) {
                rootKey = Registry.Users;
                subPath = p.Substring(5);
                return true;
            }
            return false;
        }

        private static RegistryValueKind ParseValueKind(string typeName) {
            string t = (typeName ?? "DWord").Trim().ToLowerInvariant();
            switch (t) {
                case "dword": return RegistryValueKind.DWord;
                case "qword": return RegistryValueKind.QWord;
                case "string": return RegistryValueKind.String;
                case "expandstring": return RegistryValueKind.ExpandString;
                case "binary": return RegistryValueKind.Binary;
                case "multistring": return RegistryValueKind.MultiString;
                default: return RegistryValueKind.DWord;
            }
        }

        private static string SerializeRegistryValue(object val, RegistryValueKind kind) {
            if (val == null) return "";
            if (kind == RegistryValueKind.Binary) {
                byte[] bytes = val as byte[];
                if (bytes == null) return "";
                return BitConverter.ToString(bytes).Replace("-", "");
            }
            if (kind == RegistryValueKind.MultiString) {
                string[] arr = val as string[];
                if (arr == null) return "";
                return string.Join("|", arr);
            }
            return Convert.ToString(val, CultureInfo.InvariantCulture) ?? "";
        }

        private static object DeserializeRegistryValue(string data, RegistryValueKind kind) {
            string s = data ?? "";
            switch (kind) {
                case RegistryValueKind.DWord: {
                    int iv;
                    if (int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out iv)) return iv;
                    uint uv;
                    if (uint.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out uv)) return unchecked((int)uv);
                    return 0;
                }
                case RegistryValueKind.QWord: {
                    long lv;
                    if (long.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out lv)) return lv;
                    return 0L;
                }
                case RegistryValueKind.Binary: {
                    string hex = s.Replace("-", "").Replace(" ", "").Trim();
                    if (hex.Length == 0 || (hex.Length % 2) != 0) return new byte[0];
                    byte[] outB = new byte[hex.Length / 2];
                    for (int i = 0; i < outB.Length; i++) {
                        outB[i] = byte.Parse(hex.Substring(i * 2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                    }
                    return outB;
                }
                case RegistryValueKind.MultiString:
                    return string.IsNullOrEmpty(s) ? new string[0] : s.Split('|');
                default:
                    return s;
            }
        }

        public static RegSnapshotRecord CaptureRegistryValue(string path, string name) {
            var rec = new RegSnapshotRecord { Path = path, Name = name, Existed = false, ValueType = "", ValueData = "" };
            RegistryKey root;
            string sub;
            if (!TryParseRegistryPath(path, out root, out sub)) return rec;
            try {
                using (RegistryKey rk = root.OpenSubKey(sub, false)) {
                    if (rk == null) return rec;
                    string valName = name ?? "";
                    object val = rk.GetValue(valName, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
                    if (val == null) return rec;
                    RegistryValueKind kind = rk.GetValueKind(valName);
                    rec.Existed = true;
                    rec.ValueType = kind.ToString();
                    rec.ValueData = SerializeRegistryValue(val, kind);
                }
            } catch {}
            return rec;
        }

        public static bool SetRegistryValue(string path, string name, string valueType, string valueData, bool deleteValue) {
            RegistryKey root;
            string sub;
            if (!TryParseRegistryPath(path, out root, out sub)) return false;
            try {
                if (deleteValue) {
                    using (RegistryKey rk = root.OpenSubKey(sub, true)) {
                        if (rk == null) return true;
                        try { rk.DeleteValue(name ?? "", false); } catch {}
                    }
                    return true;
                }
                using (RegistryKey rk = root.CreateSubKey(sub)) {
                    if (rk == null) return false;
                    RegistryValueKind kind = ParseValueKind(valueType);
                    object typedVal = DeserializeRegistryValue(valueData, kind);
                    rk.SetValue(name ?? "", typedVal, kind);
                    return true;
                }
            } catch {
                return false;
            }
        }

        public static bool RestoreRegistrySnapshot(RegSnapshotRecord rec) {
            if (rec == null) return false;
            if (!rec.Existed) {
                return SetRegistryValue(rec.Path, rec.Name, "DWord", "", true);
            }
            return SetRegistryValue(rec.Path, rec.Name, rec.ValueType, rec.ValueData, false);
        }

        public static int GetServiceStartType(string serviceName) {
            if (string.IsNullOrWhiteSpace(serviceName)) return -1;
            try {
                using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\" + serviceName.Trim(), false)) {
                    if (rk == null) return -1;
                    object v = rk.GetValue("Start");
                    if (v == null) return -1;
                    return Convert.ToInt32(v, CultureInfo.InvariantCulture);
                }
            } catch {
                return -1;
            }
        }

        public static bool SetServiceStartType(string serviceName, int startType) {
            if (string.IsNullOrWhiteSpace(serviceName)) return false;
            if (startType < 0 || startType > 4) return false;
            try {
                using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\" + serviceName.Trim(), true)) {
                    if (rk == null) return false;
                    rk.SetValue("Start", startType, RegistryValueKind.DWord);
                    return true;
                }
            } catch {
                return false;
            }
        }

        private static bool CheckRegistryRuleApplied(TweakRegRule r) {
            if (r == null || string.IsNullOrWhiteSpace(r.Path)) return false;
            RegistryKey root;
            string sub;
            if (!TryParseRegistryPath(r.Path, out root, out sub)) return false;
            try {
                using (RegistryKey rk = root.OpenSubKey(sub, false)) {
                    if (r.DeleteOnApply) {
                        if (rk == null) return true;
                        return rk.GetValue(r.Name ?? "", null, RegistryValueOptions.DoNotExpandEnvironmentNames) == null;
                    }
                    if (rk == null) return false;
                    object cur = rk.GetValue(r.Name ?? "", null, RegistryValueOptions.DoNotExpandEnvironmentNames);
                    if (cur == null) return false;
                    RegistryValueKind kind = rk.GetValueKind(r.Name ?? "");
                    string curStr = SerializeRegistryValue(cur, kind);
                    return string.Equals(curStr.Trim(), (r.ApplyValue ?? "").Trim(), StringComparison.OrdinalIgnoreCase);
                }
            } catch {
                return false;
            }
        }

        private static bool CheckActionState(string actionKind, string actionParam) {
            string kind = (actionKind ?? "").Trim().ToLowerInvariant();
            if (string.IsNullOrEmpty(kind)) return false;
            try {
                switch (kind) {
                    case "hibernation_off": {
                        using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Power", false)) {
                            if (rk != null) {
                                object v = rk.GetValue("HibernateEnabled");
                                if (v != null && Convert.ToInt32(v, CultureInfo.InvariantCulture) == 0) return true;
                            }
                        }
                        return false;
                    }
                    case "ultimate_perf": {
                        using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes", false)) {
                            if (rk != null) {
                                string active = Convert.ToString(rk.GetValue("ActivePowerScheme"), CultureInfo.InvariantCulture) ?? "";
                                if (string.Equals(active, "e9a42b02-d5df-448d-aa00-03f14749eb61", StringComparison.OrdinalIgnoreCase)) return true;
                                if (!string.IsNullOrEmpty(active)) {
                                    using (RegistryKey sk = rk.OpenSubKey(active, false)) {
                                        if (sk != null) {
                                            string fn = Convert.ToString(sk.GetValue("FriendlyName"), CultureInfo.InvariantCulture) ?? "";
                                            if (fn.IndexOf("Ultimate", StringComparison.OrdinalIgnoreCase) >= 0) return true;
                                        }
                                    }
                                }
                            }
                        }
                        return false;
                    }
                    case "classic_context_menu": {
                        using (RegistryKey rk = Registry.CurrentUser.OpenSubKey(@"Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32", false)) {
                            if (rk != null) {
                                object v = rk.GetValue("");
                                return v != null && string.Equals(v.ToString(), "", StringComparison.Ordinal);
                            }
                        }
                        return false;
                    }
                    case "remove_home_gallery": {
                        using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}", false)) {
                            return rk == null;
                        }
                    }
                    case "remove_onedrive": {
                        string od1 = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\OneDrive\OneDrive.exe");
                        string od2 = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"Microsoft OneDrive\OneDrive.exe");
                        return !File.Exists(od1) && !File.Exists(od2);
                    }
                    case "block_adobe_net": {
                        string hosts = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"drivers\etc\hosts");
                        if (File.Exists(hosts)) {
                            string txt = File.ReadAllText(hosts);
                            return txt.IndexOf("# AppDriver-AdobeBlock", StringComparison.OrdinalIgnoreCase) >= 0;
                        }
                        return false;
                    }
                    case "ipv6_disable": {
                        using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters", false)) {
                            if (rk != null) {
                                object v = rk.GetValue("DisabledComponents");
                                if (v != null && Convert.ToInt32(v, CultureInfo.InvariantCulture) == 255) return true;
                            }
                        }
                        return false;
                    }
                    case "ipv4_prefer": {
                        using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters", false)) {
                            if (rk != null) {
                                object v = rk.GetValue("DisabledComponents");
                                if (v != null && Convert.ToInt32(v, CultureInfo.InvariantCulture) == 32) return true;
                            }
                        }
                        return false;
                    }
                    case "svchost_split_off": {
                        using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control", false)) {
                            if (rk != null) {
                                object v = rk.GetValue("SvcHostSplitThresholdInKB");
                                if (v != null && Convert.ToInt64(v, CultureInfo.InvariantCulture) >= 16777216L) return true;
                            }
                        }
                        return false;
                    }
                    case "reserved_storage_off": {
                        using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager", false)) {
                            if (rk != null) {
                                object v = rk.GetValue("ShippedWithReserves");
                                if (v != null && Convert.ToInt32(v, CultureInfo.InvariantCulture) == 0) return true;
                            }
                        }
                        return false;
                    }
                    default:
                        return false;
                }
            } catch {
                return false;
            }
        }

        public static TweakProbeResult[] ProbeTweaksState(TweakProbeSpec[] specs, int currentOsBuild) {
            if (specs == null) return new TweakProbeResult[0];
            var results = new TweakProbeResult[specs.Length];
            for (int i = 0; i < specs.Length; i++) {
                TweakProbeSpec sp = specs[i];
                var r = new TweakProbeResult { Id = sp != null ? sp.Id : "", IsApplied = false, Supported = true, Detail = "" };
                if (sp == null) { results[i] = r; continue; }

                if (sp.MinBuild > 0 && currentOsBuild > 0 && currentOsBuild < sp.MinBuild) {
                    r.Supported = false;
                    r.Detail = "Y\u00EAu c\u1EA7u Windows build " + sp.MinBuild.ToString(CultureInfo.InvariantCulture) + "+";
                    results[i] = r;
                    continue;
                }

                bool hasCheck = false;
                bool allOk = true;

                if (!string.IsNullOrEmpty(sp.ActionKind)) {
                    string ak = sp.ActionKind.Trim().ToLowerInvariant();
                    if (ak != "restore_point" && ak != "clean_temp" && ak != "disk_cleanup" && ak != "dns_switch" && ak != "remove_edge" && ak != "remove_windows_ai") {
                        hasCheck = true;
                        allOk = CheckActionState(sp.ActionKind, sp.ActionParam);
                    }
                }

                if (!hasCheck && sp.RegRules != null && sp.RegRules.Length > 0) {
                    hasCheck = true;
                    for (int j = 0; j < sp.RegRules.Length; j++) {
                        if (!CheckRegistryRuleApplied(sp.RegRules[j])) {
                            allOk = false;
                            break;
                        }
                    }
                }

                if (!hasCheck && sp.Services != null && sp.Services.Length > 0) {
                    int foundSvc = 0;
                    int manualOrDisabled = 0;
                    for (int s = 0; s < sp.Services.Length; s++) {
                        int st = GetServiceStartType(sp.Services[s]);
                        if (st >= 0) {
                            foundSvc++;
                            if (st == 3 || st == 4) manualOrDisabled++;
                        }
                    }
                    if (foundSvc > 0) {
                        hasCheck = true;
                        allOk = (manualOrDisabled >= (int)Math.Ceiling(foundSvc * 0.85));
                    }
                }

                r.IsApplied = hasCheck && allOk;
                results[i] = r;
            }
            return results;
        }

        public static Task<TweakProbeResult[]> ProbeTweaksStateAsync(TweakProbeSpec[] specs, int currentOsBuild) {
            return Task.Run(() => ProbeTweaksState(specs, currentOsBuild));
        }
    }
}
