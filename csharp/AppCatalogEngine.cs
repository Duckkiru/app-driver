using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography.X509Certificates;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace DuckUtil
{
    public class CatalogSensorItem
    {
        public string Name { get; set; }
        public string ID { get; set; }
        public string Version { get; set; }
        public string Available { get; set; }
        public bool HasUpdate { get; set; }
        public string CleanName { get; set; }
        public string Source { get; set; }
    }

    public class CatalogMatchTarget
    {
        public string ID { get; set; }
        public string Name { get; set; }
        public string Category { get; set; }
        public string[] Aliases { get; set; }
    }

    public static class AppCatalogEngine
    {
        private static readonly Regex _rxCleanParens = new Regex(@"\((?!x64|x86|arm64).*?\)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxCleanVerWord = new Regex(@"\b(version|ver|v|release)\s*\d+(\.\d+)*[^\s]*", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxCleanVerNum = new Regex(@"\b\d+(\.\d+){1,4}(-[a-z0-9.]+)?\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxMultiSpace = new Regex(@"\s+", RegexOptions.Compiled);
        private static readonly Regex _rxVerExtract = new Regex(@"\d+(?:[.+_-]\d+)*", RegexOptions.Compiled);
        private static readonly Regex _rxVerSplit = new Regex(@"[.+_-]", RegexOptions.Compiled);
        private static readonly Regex _rxAnsi = new Regex(@"\x1B\[[0-9;?]*[A-Za-z]", RegexOptions.Compiled);
        private static readonly Regex _rxPrerelease = new Regex(@"(?:^|[-.+_])(?:alpha|beta|rc|pre|preview|dev|canary|nightly)(?:$|[-.+_\d])", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly string[] _cleanTerms = new string[] { " browser", " desktop", " lts", " client", " free", " ce", " community", " end-user", " stable", " edition", " x64", " x86", " 64-bit", " 32-bit" };

        public static string CleanCatalogAppName(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return "";
            string c = _rxCleanParens.Replace(name, "").Replace("(", "").Replace(")", "").Trim().ToLowerInvariant();
            c = _rxCleanVerWord.Replace(c, "");
            c = _rxCleanVerNum.Replace(c, "");
            foreach (string term in _cleanTerms)
            {
                c = c.Replace(term, "");
            }
            c = _rxMultiSpace.Replace(c, " ").Trim();
            return c;
        }

        public static long[] GetVersionNumbers(string verStr)
        {
            if (string.IsNullOrWhiteSpace(verStr)) return new long[0];
            string s = verStr.Trim();
            if (s.StartsWith("<")) s = s.Substring(1).Trim();
            Match m = _rxVerExtract.Match(s);
            if (!m.Success) return new long[0];
            string[] parts = _rxVerSplit.Split(m.Value);
            var nums = new List<long>(parts.Length);
            foreach (string p in parts)
            {
                long v;
                if (long.TryParse(p, out v)) nums.Add(v);
            }
            return nums.ToArray();
        }

        public static int CompareAppVersions(string verA, string verB)
        {
            long[] a = GetVersionNumbers(verA);
            long[] b = GetVersionNumbers(verB);
            if (a.Length == 0 && b.Length == 0) return 0;
            if (a.Length > 0 && b.Length == 0) return 1;
            if (a.Length == 0 && b.Length > 0) return -1;
            int maxLen = Math.Max(a.Length, b.Length);
            for (int i = 0; i < maxLen; i++)
            {
                long va = i < a.Length ? a[i] : 0L;
                long vb = i < b.Length ? b[i] : 0L;
                if (va > vb) return 1;
                if (va < vb) return -1;
            }
            return 0;
        }

        public static bool TestAppUpdateGenuine(string installedVer, string availableVer)
        {
            if (string.IsNullOrWhiteSpace(availableVer)) return false;
            string av = availableVer.Trim();
            if (av.Equals("winget", StringComparison.OrdinalIgnoreCase) ||
                av.Equals("msstore", StringComparison.OrdinalIgnoreCase) ||
                av.Equals("Unknown", StringComparison.OrdinalIgnoreCase)) return false;
            bool hasDigit = false;
            foreach (char c in av) { if (c >= '0' && c <= '9') { hasDigit = true; break; } }
            if (!hasDigit) return false;
            if (string.IsNullOrWhiteSpace(installedVer)) return true;
            string iv = installedVer.Trim();
            if (iv.StartsWith("<")) return true;
            bool hasIvDigit = false;
            foreach (char c in iv) { if (c >= '0' && c <= '9') { hasIvDigit = true; break; } }
            if (iv.Equals("Unknown", StringComparison.OrdinalIgnoreCase) || iv.Equals("Installed", StringComparison.OrdinalIgnoreCase) || !hasIvDigit) return true;
            int cmp = CompareAppVersions(av, iv);
            if (cmp > 0) return true;
            if (cmp == 0 && _rxPrerelease.IsMatch(iv) && !_rxPrerelease.IsMatch(av)) return true;
            return false;
        }

        private static int GetDisplayWidthUpToIndex(string s, int charIdx)
        {
            if (string.IsNullOrEmpty(s) || charIdx <= 0) return 0;
            int limit = Math.Min(charIdx, s.Length);
            int w = 0;
            for (int i = 0; i < limit; i++)
            {
                char ch = s[i];
                if (char.IsHighSurrogate(ch) && (i + 1) < limit && char.IsLowSurrogate(s[i + 1]))
                {
                    int cp = char.ConvertToUtf32(ch, s[i + 1]);
                    w += GetCharDisplayWidth(cp);
                    i++;
                }
                else
                {
                    w += GetCharDisplayWidth((int)ch);
                }
            }
            return w;
        }

        private static int SnapWingetColumnBoundary(string line, int pos, int minPos)
        {
            if (string.IsNullOrEmpty(line) || pos <= minPos || pos >= line.Length) return pos;
            if (char.IsWhiteSpace(line[pos]) || char.IsWhiteSpace(line[pos - 1])) return pos;

            int leftCandidate = -1;
            int minLeft = Math.Max(minPos + 1, pos - 10);
            for (int j = pos - 1; j >= minLeft; j--)
            {
                if (char.IsWhiteSpace(line[j]))
                {
                    leftCandidate = j + 1;
                    break;
                }
            }

            int rightCandidate = -1;
            int maxRight = Math.Min(line.Length - 1, pos + 10);
            for (int j = pos + 1; j <= maxRight; j++)
            {
                if (char.IsWhiteSpace(line[j]))
                {
                    int k = j;
                    while (k < line.Length && char.IsWhiteSpace(line[k])) k++;
                    if (k < line.Length) rightCandidate = k;
                    break;
                }
            }

            if (leftCandidate >= 0 && rightCandidate >= 0)
            {
                return (pos - leftCandidate) <= (rightCandidate - pos) ? leftCandidate : rightCandidate;
            }
            if (leftCandidate >= 0) return leftCandidate;
            if (rightCandidate >= 0) return rightCandidate;
            return pos;
        }

        private static string[] SliceRowColumnsByPositions(string line, int cId, int cVer, int cAvail, int cSrc)
        {
            string appName = "", appId = "", version = "", avail = "";
            if (cId > 0 && line.Length > cId)
            {
                cId = SnapWingetColumnBoundary(line, cId, 0);
                appName = line.Substring(0, cId).Trim();
                if (cVer > cId && line.Length > cVer)
                {
                    cVer = SnapWingetColumnBoundary(line, cVer, cId);
                    appId = line.Substring(cId, cVer - cId).Trim();
                    if (cAvail > cVer && line.Length > cAvail)
                    {
                        cAvail = SnapWingetColumnBoundary(line, cAvail, cVer);
                        version = line.Substring(cVer, cAvail - cVer).Trim();
                        if (cSrc > cAvail && line.Length > cSrc)
                        {
                            cSrc = SnapWingetColumnBoundary(line, cSrc, cAvail);
                            avail = line.Substring(cAvail, cSrc - cAvail).Trim();
                        }
                        else
                        {
                            avail = line.Substring(cAvail).Trim();
                        }
                    }
                    else
                    {
                        version = line.Substring(cVer).Trim();
                    }
                }
                else
                {
                    appId = line.Substring(cId).Trim();
                }
            }
            return new string[] { appName, appId, version, avail };
        }

        private static int GetCharDisplayWidth(int code)
        {
            if ((code >= 0x1100 && code <= 0x115F) ||
                (code == 0x2329 || code == 0x232A) ||
                (code >= 0x2E80 && code <= 0x303E) ||
                (code >= 0x3041 && code <= 0x33FF) ||
                (code >= 0x3400 && code <= 0x4DBF) ||
                (code >= 0x4E00 && code <= 0xA4CF) ||
                (code >= 0xA960 && code <= 0xA97F) ||
                (code >= 0xAC00 && code <= 0xD7AF) ||
                (code >= 0xF900 && code <= 0xFAFF) ||
                (code >= 0xFE10 && code <= 0xFE19) ||
                (code >= 0xFE30 && code <= 0xFE6F) ||
                (code >= 0xFF01 && code <= 0xFF60) ||
                (code >= 0xFFE0 && code <= 0xFFE6) ||
                (code >= 0x1F300 && code <= 0x1FAFF))
            {
                return 2;
            }
            return 1;
        }

        private static string[] SliceByDisplayWidth(string line, int[] offsets)
        {
            int idIdx = offsets.Length >= 2 ? offsets[1] : -1;
            int verIdx = offsets.Length >= 3 ? offsets[2] : -1;
            int availIdx = offsets.Length >= 4 ? offsets[3] : -1;
            int srcIdx = offsets.Length >= 5 ? offsets[4] : -1;

            int[] targets = new int[] { idIdx, verIdx, availIdx, srcIdx };
            int[] charPos = new int[] { -1, -1, -1, -1 };
            int w = 0;
            for (int i = 0; i < line.Length; i++)
            {
                for (int t = 0; t < 4; t++)
                {
                    if (charPos[t] < 0 && targets[t] >= 0 && w >= targets[t])
                    {
                        charPos[t] = i;
                    }
                }
                char ch = line[i];
                if (char.IsHighSurrogate(ch) && (i + 1) < line.Length && char.IsLowSurrogate(line[i + 1]))
                {
                    int cp = char.ConvertToUtf32(ch, line[i + 1]);
                    w += GetCharDisplayWidth(cp);
                    i++;
                }
                else
                {
                    w += GetCharDisplayWidth((int)ch);
                }
            }

            int cId = charPos[0];
            int cVer = charPos[1];
            int cAvail = charPos[2];
            int cSrc = charPos[3];

            return SliceRowColumnsByPositions(line, cId, cVer, cAvail, cSrc);
        }

        public static List<CatalogSensorItem> ParseWingetListOutput(string rawText, bool allowHeaderless, out bool hasTable)
        {
            hasTable = false;
            var parsed = new List<CatalogSensorItem>(256);
            if (string.IsNullOrWhiteSpace(rawText)) return parsed;

            string[] rawLines = rawText.Split('\n');
            var lines = new List<string>(rawLines.Length);
            foreach (string rl in rawLines)
            {
                string cleanLine = rl.TrimEnd('\r');
                int crIdx = cleanLine.LastIndexOf('\r');
                if (crIdx >= 0) cleanLine = cleanLine.Substring(crIdx + 1);
                if (cleanLine.IndexOf((char)0x1B) >= 0)
                {
                    cleanLine = _rxAnsi.Replace(cleanLine, "");
                }
                lines.Add(cleanLine);
            }

            int separatorIndex = -1;
            for (int i = 0; i < lines.Count; i++)
            {
                if (Regex.IsMatch(lines[i], @"^\s*-{10,}"))
                {
                    separatorIndex = i;
                    break;
                }
            }

            if (separatorIndex > 0)
            {
                hasTable = true;
                string separatorLine = lines[separatorIndex];
                string headerLine = lines[separatorIndex - 1];
                var colOffsetsList = new List<int>();
                if (Regex.IsMatch(separatorLine, @"---+\s+---+"))
                {
                    MatchCollection dashMatches = Regex.Matches(separatorLine, @"-+");
                    foreach (Match dm in dashMatches) colOffsetsList.Add(dm.Index);
                }
                else if (!string.IsNullOrEmpty(headerLine))
                {
                    MatchCollection matches = Regex.Matches(headerLine, @"\S+(\s\S+)*");
                    colOffsetsList = new List<int>(matches.Count);
                    foreach (Match m in matches) colOffsetsList.Add(GetDisplayWidthUpToIndex(headerLine, m.Index));
                }
                int[] colOffsets = colOffsetsList.ToArray();

                for (int i = separatorIndex + 1; i < lines.Count; i++)
                {
                    string line = lines[i];
                    if (string.IsNullOrWhiteSpace(line)) continue;
                    string appName = "", appId = "", version = "", avail = "";

                    if (colOffsets.Length >= 3)
                    {
                        bool hasNonAscii = false;
                        for (int k = 0; k < line.Length; k++)
                        {
                            if (line[k] > 0x007F) { hasNonAscii = true; break; }
                        }
                        if (!hasNonAscii)
                        {
                            int cId = colOffsets[1];
                            int cVer = colOffsets[2];
                            int cAvail = colOffsets.Length >= 4 ? colOffsets[3] : -1;
                            int cSrc = colOffsets.Length >= 5 ? colOffsets[4] : -1;
                            string[] sliced = SliceRowColumnsByPositions(line, cId, cVer, cAvail, cSrc);
                            appName = sliced[0];
                            appId = sliced[1];
                            version = sliced[2];
                            avail = sliced[3];
                        }
                        else
                        {
                            string[] sliced = SliceByDisplayWidth(line, colOffsets);
                            appName = sliced[0];
                            appId = sliced[1];
                            version = sliced[2];
                            avail = sliced[3];
                        }
                    }

                    if (string.IsNullOrEmpty(appId) || appId.IndexOf(' ') >= 0)
                    {
                        string[] cols = Regex.Split(line.Trim(), @"\s{2,}");
                        if (cols.Length >= 2)
                        {
                            appName = cols[0].Trim();
                            appId = cols[1].Trim();
                            version = cols.Length >= 3 ? cols[2].Trim() : "";
                            avail = cols.Length >= 4 ? cols[3].Trim() : "";
                        }
                    }

                    if (!string.IsNullOrEmpty(appName) && !string.IsNullOrEmpty(appId))
                    {
                        bool hasUpdate = TestAppUpdateGenuine(version, avail);
                        parsed.Add(new CatalogSensorItem
                        {
                            Name = appName,
                            ID = appId,
                            Version = version,
                            Available = hasUpdate ? avail : "",
                            HasUpdate = hasUpdate,
                            CleanName = CleanCatalogAppName(appName),
                            Source = "winget"
                        });
                    }
                }
            }
            else if (allowHeaderless)
            {
                for (int i = 0; i < lines.Count; i++)
                {
                    string line = lines[i];
                    if (string.IsNullOrWhiteSpace(line)) continue;
                    string trimmed = line.Trim();
                    if (trimmed.StartsWith("---")) continue;
                    string[] cols = Regex.Split(trimmed, @"\s{2,}");
                    if (cols.Length >= 2)
                    {
                        string appName = cols[0].Trim();
                        string appId = cols[1].Trim();
                        if (!Regex.IsMatch(appId, @"^(ARP|MSIX)\\|\S+\.\S+")) continue;
                        string version = cols.Length >= 3 ? cols[2].Trim() : "";
                        string avail = cols.Length >= 4 ? cols[3].Trim() : "";
                        if (!string.IsNullOrEmpty(appName) && !string.IsNullOrEmpty(appId))
                        {
                            bool hasUpdate = TestAppUpdateGenuine(version, avail);
                            parsed.Add(new CatalogSensorItem
                            {
                                Name = appName,
                                ID = appId,
                                Version = version,
                                Available = hasUpdate ? avail : "",
                                HasUpdate = hasUpdate,
                                CleanName = CleanCatalogAppName(appName),
                                Source = "winget"
                            });
                        }
                    }
                }
            }
            return parsed;
        }

        private static string ResolveCliExactVersion(string exePath, string toolKey)
        {
            if (string.IsNullOrWhiteSpace(exePath) || !File.Exists(exePath)) return "Installed";
            try
            {
                var fvi = FileVersionInfo.GetVersionInfo(exePath);
                string[] cands = new string[] { fvi.ProductVersion, fvi.FileVersion };
                foreach (string cand in cands)
                {
                    if (!string.IsNullOrWhiteSpace(cand))
                    {
                        string clean = cand.Split('+')[0].Trim();
                        if (Regex.IsMatch(clean, @"\d") && !Regex.IsMatch(clean, @"^0(\.0)+$"))
                        {
                            return clean;
                        }
                    }
                }
            }
            catch {}

            try
            {
                string userProf = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                string localApp = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

                if (string.Equals(toolKey, "agy", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(userProf))
                {
                    string agyVerJson = Path.Combine(userProf, @".gemini\bin\agy.version.json");
                    if (File.Exists(agyVerJson))
                    {
                        string txt = File.ReadAllText(agyVerJson);
                        Match m = Regex.Match(txt, @"""version""\s*:\s*""([^""]+)""");
                        if (m.Success) return m.Groups[1].Value.Trim();
                    }
                }

                if (!string.IsNullOrEmpty(localApp) && !string.IsNullOrEmpty(toolKey))
                {
                    string receipt = Path.Combine(localApp, toolKey, toolKey + "-receipt.json");
                    if (File.Exists(receipt))
                    {
                        string txt = File.ReadAllText(receipt);
                        Match m = Regex.Match(txt, @"""version""\s*:\s*""([^""]+)""", RegexOptions.RightToLeft);
                        if (m.Success) return m.Groups[1].Value.Trim();
                    }
                }

                string dir = Path.GetDirectoryName(exePath);
                if (!string.IsNullOrEmpty(dir))
                {
                    string parent = Path.GetDirectoryName(dir);
                    if (!string.IsNullOrEmpty(parent))
                    {
                        string sitePkgs = Path.Combine(parent, @"Lib\site-packages");
                        if (Directory.Exists(sitePkgs))
                        {
                            string prefix = toolKey.Replace('-', '_') + "-";
                            foreach (string d in Directory.GetDirectories(sitePkgs, "*.dist-info"))
                            {
                                string dn = Path.GetFileName(d);
                                if (dn.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                                {
                                    string verPart = dn.Substring(prefix.Length);
                                    int distIdx = verPart.IndexOf(".dist-info", StringComparison.OrdinalIgnoreCase);
                                    if (distIdx > 0) return verPart.Substring(0, distIdx);
                                }
                            }
                        }

                        string scoopManifest = Path.Combine(dir, "manifest.json");
                        if (!File.Exists(scoopManifest)) scoopManifest = Path.Combine(parent, "manifest.json");
                        if (File.Exists(scoopManifest))
                        {
                            string txt = File.ReadAllText(scoopManifest);
                            Match m = Regex.Match(txt, @"""version""\s*:\s*""([^""]+)""");
                            if (m.Success) return m.Groups[1].Value.Trim();
                        }
                    }
                }
            }
            catch {}

            return "Installed";
        }

        private static string ExtractExePath(string cmd)
        {
            if (string.IsNullOrWhiteSpace(cmd)) return null;
            string raw = Environment.ExpandEnvironmentVariables(cmd).Trim();
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

        private static bool IsBrokenRegistryEntry(string uninstallString, string installLocation)
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

        public static List<CatalogSensorItem> ScanCatalogSensors()
        {
            var items = new List<CatalogSensorItem>(256);

            var regTargets = new Tuple<RegistryHive, RegistryView, string, string>[]
            {
                Tuple.Create(RegistryHive.LocalMachine, RegistryView.Registry64, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", @"ARP\Machine\X64\"),
                Tuple.Create(RegistryHive.LocalMachine, RegistryView.Registry32, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", @"ARP\Machine\X86\"),
                Tuple.Create(RegistryHive.CurrentUser, RegistryView.Default, @"Software\Microsoft\Windows\CurrentVersion\Uninstall", @"ARP\User\X64\"),
                Tuple.Create(RegistryHive.CurrentUser, RegistryView.Registry32, @"Software\Microsoft\Windows\CurrentVersion\Uninstall", @"ARP\User\X86\")
            };

            string vsCodeUserDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\Microsoft VS Code");
            bool vsCodeUserExists = Directory.Exists(vsCodeUserDir);

            foreach (var rt in regTargets)
            {
                try
                {
                    using (var baseKey = RegistryKey.OpenBaseKey(rt.Item1, rt.Item2))
                    using (var uninst = baseKey.OpenSubKey(rt.Item3))
                    {
                        if (uninst == null) continue;
                        foreach (string subName in uninst.GetSubKeyNames())
                        {
                            try
                            {
                                using (var sk = uninst.OpenSubKey(subName))
                                {
                                    if (sk == null) continue;
                                    string parentKey = sk.GetValue("ParentKeyName") as string;
                                    if (!string.IsNullOrEmpty(parentKey)) continue;

                                    string dn = (sk.GetValue("DisplayName") as string ?? "").Trim();
                                    if (string.IsNullOrEmpty(dn)) continue;

                                    var sysComp = sk.GetValue("SystemComponent");
                                    if (sysComp != null && (sysComp.ToString() == "1" || ((sysComp is int) && ((int)sysComp == 1))))
                                    {
                                        if (dn.IndexOf("Visual Studio", StringComparison.OrdinalIgnoreCase) < 0 &&
                                            dn.IndexOf("Desktop Runtime", StringComparison.OrdinalIgnoreCase) < 0 &&
                                            dn.IndexOf("Corretto", StringComparison.OrdinalIgnoreCase) < 0 &&
                                            dn.IndexOf("Temurin", StringComparison.OrdinalIgnoreCase) < 0)
                                        {
                                            continue;
                                        }
                                    }

                                    if (Regex.IsMatch(dn, @"Additional Runtime|Minimum Runtime|Debug Runtime|IntelliSense|Language Pack", RegexOptions.IgnoreCase))
                                    {
                                        continue;
                                    }

                                    string loc = (sk.GetValue("InstallLocation") as string ?? "").Trim().Trim('\"');
                                    string uStr = (sk.GetValue("UninstallString") as string ?? "").Trim();

                                    if (dn.IndexOf("Visual Studio Code (User)", StringComparison.OrdinalIgnoreCase) >= 0 && !vsCodeUserExists && string.IsNullOrEmpty(loc) && string.IsNullOrEmpty(uStr))
                                    {
                                        continue;
                                    }

                                    if (IsBrokenRegistryEntry(uStr, loc)) continue;

                                    string ver = (sk.GetValue("DisplayVersion") as string ?? "Installed").Trim();
                                    if (string.IsNullOrEmpty(ver)) ver = "Installed";
                                    string clean = CleanCatalogAppName(dn);

                                    items.Add(new CatalogSensorItem
                                    {
                                        Name = dn,
                                        ID = rt.Item4 + subName,
                                        Version = ver,
                                        Available = "",
                                        HasUpdate = false,
                                        CleanName = clean,
                                        Source = "local"
                                    });

                                    if (dn.IndexOf("Visual Studio Community", StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        items.Add(new CatalogSensorItem
                                        {
                                            Name = dn,
                                            ID = "Microsoft.VisualStudio.2022.Community",
                                            Version = ver,
                                            Available = "",
                                            HasUpdate = false,
                                            CleanName = clean,
                                            Source = "local"
                                        });
                                    }
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
                            if (Regex.IsMatch(pkgFull, @"^(Microsoft\.Windows\.|MicrosoftWindows\.|Windows\.|Microsoft\.UI\.Xaml|Microsoft\.VCLibs|Microsoft\.NET\.Native|Microsoft\.WinAppRuntime|Microsoft\.Services\.Store|Microsoft\.AAD|Microsoft\.AccountsControl|Microsoft\.AsyncTextService|Microsoft\.BioEnrollment|Microsoft\.CredDialogHost|Microsoft\.ECApp|Microsoft\.LockApp|Microsoft\.Win32WebViewHost|Microsoft\.XboxGameCallableUI|NcsiUwpApp|Microsoft\.Winget\.|Microsoft\.Ink\.|Microsoft\.LanguageExperiencePack|Microsoft\.PowerToys\.|NotepadPlusPlus_)", RegexOptions.IgnoreCase))
                            {
                                continue;
                            }

                            string[] parts = pkgFull.Split('_');
                            string pkgPrefix = parts.Length > 0 ? parts[0] : pkgFull;
                            string pkgVer = parts.Length > 1 ? parts[1] : "Installed";
                            string dispName = pkgPrefix;

                            try
                            {
                                using (var sk = pkgRoot.OpenSubKey(pkgFull))
                                {
                                    if (sk != null)
                                    {
                                        string d = (sk.GetValue("DisplayName") as string ?? "").Trim();
                                        if (!string.IsNullOrEmpty(d) && !d.StartsWith("ms-resource:", StringComparison.OrdinalIgnoreCase))
                                        {
                                            dispName = d;
                                        }
                                    }
                                }
                            }
                            catch {}

                            string mappedId = "MSIX\\" + pkgFull;
                            if (pkgPrefix.IndexOf("TelegramDesktop", StringComparison.OrdinalIgnoreCase) >= 0) mappedId = "Telegram.TelegramDesktop";
                            else if (pkgPrefix.IndexOf("OpenAI.Codex", StringComparison.OrdinalIgnoreCase) >= 0 || pkgPrefix.IndexOf("OpenAI.ChatGPT", StringComparison.OrdinalIgnoreCase) >= 0) { mappedId = "OpenAI.ChatGPT"; dispName = "ChatGPT"; }
                            else if (pkgPrefix.IndexOf("WindowsTerminal", StringComparison.OrdinalIgnoreCase) >= 0 && pkgPrefix.IndexOf("Preview", StringComparison.OrdinalIgnoreCase) < 0) mappedId = "Microsoft.WindowsTerminal";
                            else if (pkgPrefix.Equals("Microsoft.PowerShell", StringComparison.OrdinalIgnoreCase)) mappedId = "Microsoft.PowerShell";
                            else if (pkgPrefix.IndexOf("WindowsSubsystemForLinux", StringComparison.OrdinalIgnoreCase) >= 0) mappedId = "Microsoft.WSL";
                            else if (pkgPrefix.IndexOf("DirectXRuntime", StringComparison.OrdinalIgnoreCase) >= 0) mappedId = "Microsoft.DirectX";
                            else if (pkgPrefix.IndexOf("TranslucentTB", StringComparison.OrdinalIgnoreCase) >= 0) mappedId = "CharlesMilette.TranslucentTB";
                            else if (pkgPrefix.IndexOf("MicrosoftPCManager", StringComparison.OrdinalIgnoreCase) >= 0) { mappedId = "9PM860492SZD"; dispName = "Microsoft PC Manager"; }
                            else if (pkgPrefix.IndexOf("WhatsAppDesktop", StringComparison.OrdinalIgnoreCase) >= 0) { mappedId = "9NKSQGP7F2NH"; dispName = "WhatsApp"; }
                            else if (pkgPrefix.IndexOf("KaliLinux", StringComparison.OrdinalIgnoreCase) >= 0) mappedId = "OffSec.KaliLinux";

                            items.Add(new CatalogSensorItem
                            {
                                Name = dispName,
                                ID = mappedId,
                                Version = pkgVer,
                                Available = "",
                                HasUpdate = false,
                                CleanName = CleanCatalogAppName(dispName),
                                Source = "local"
                            });
                        }
                    }
                }
            }
            catch {}

            try
            {
                using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                using (var ndpKey = baseKey.OpenSubKey(@"SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"))
                {
                    if (ndpKey != null)
                    {
                        object relObj = ndpKey.GetValue("Release");
                        int rel = relObj != null ? Convert.ToInt32(relObj) : 0;
                        string ndpVer = (ndpKey.GetValue("Version") as string ?? "4.8.1").Trim();
                        if (rel >= 533320 || ndpVer.StartsWith("4.8"))
                        {
                            items.Add(new CatalogSensorItem
                            {
                                Name = "Microsoft .NET Framework 4.8.1",
                                ID = "Microsoft.DotNet.Framework.Runtime",
                                Version = ndpVer,
                                Available = "",
                                HasUpdate = false,
                                CleanName = "net framework 4 8 1",
                                Source = "local"
                            });
                        }
                    }
                }
            }
            catch {}

            try
            {
                string d3dx = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "d3dx9_43.dll");
                if (File.Exists(d3dx))
                {
                    items.Add(new CatalogSensorItem
                    {
                        Name = "DirectX End-User Runtimes",
                        ID = "Microsoft.DirectX",
                        Version = "9.29.1974.0",
                        Available = "",
                        HasUpdate = false,
                        CleanName = "directx",
                        Source = "local"
                    });
                }
            }
            catch {}

            string pf64Root = Environment.GetEnvironmentVariable("ProgramW6432");
            if (string.IsNullOrEmpty(pf64Root)) pf64Root = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            string pf86Root = Environment.GetEnvironmentVariable("ProgramFiles(x86)");
            if (string.IsNullOrEmpty(pf86Root)) pf86Root = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);

            var dotnetSharesList = new List<Tuple<string, string>>();
            if (!string.IsNullOrEmpty(pf64Root)) dotnetSharesList.Add(Tuple.Create(Path.Combine(pf64Root, @"dotnet\shared\Microsoft.WindowsDesktop.App"), "x64"));
            if (!string.IsNullOrEmpty(pf86Root)) dotnetSharesList.Add(Tuple.Create(Path.Combine(pf86Root, @"dotnet\shared\Microsoft.WindowsDesktop.App"), "x86"));
            var dotnetShares = dotnetSharesList.ToArray();

            foreach (var ds in dotnetShares)
            {
                if (!Directory.Exists(ds.Item1)) continue;
                try
                {
                    var byMajor = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    foreach (string verDir in Directory.GetDirectories(ds.Item1))
                    {
                        string verName = Path.GetFileName(verDir);
                        Match m = Regex.Match(verName ?? "", @"^(\d+)\.(\d+)\.");
                        if (!m.Success) continue;
                        string maj = m.Groups[1].Value;
                        string min = m.Groups[2].Value;
                        bool isPre = Regex.IsMatch(verName, @"preview|rc|alpha|beta", RegexOptions.IgnoreCase);
                        string trackKey = (maj == "3" && min == "1") ? "3_1" : (isPre ? "Preview" : maj);
                        string existing;
                        if (!byMajor.TryGetValue(trackKey, out existing) || CompareAppVersions(verName, existing) > 0)
                        {
                            byMajor[trackKey] = verName;
                        }
                    }

                    foreach (var kv in byMajor)
                    {
                        string tk = kv.Key;
                        if (ds.Item2 == "x86" && tk != "6" && tk != "7" && tk != "8") continue;
                        string bestV = kv.Value;
                        string archSuffix = ds.Item2 == "x86" ? ".x86" : "";
                        string archLabel = ds.Item2 == "x86" ? " (x86)" : " (x64)";
                        string wingetId = "Microsoft.DotNet.DesktopRuntime." + tk + archSuffix;
                        string disp = "Microsoft Windows Desktop Runtime - " + bestV + archLabel;
                        items.Add(new CatalogSensorItem
                        {
                            Name = disp,
                            ID = wingetId,
                            Version = bestV,
                            Available = "",
                            HasUpdate = false,
                            CleanName = CleanCatalogAppName(disp),
                            Source = "local"
                        });
                    }
                }
                catch {}
            }

            var pathDirs = new List<string>();
            var seenDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            string rawPath = Environment.GetEnvironmentVariable("PATH") ?? "";
            foreach (string p in rawPath.Split(';'))
            {
                string trimmed = p.Trim().Trim('\"');
                if (!string.IsNullOrEmpty(trimmed) && seenDirs.Add(trimmed) && Directory.Exists(trimmed))
                {
                    pathDirs.Add(trimmed);
                }
            }

            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string progFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            string progFilesW64 = Environment.GetEnvironmentVariable("ProgramW6432");
            string neovimDir = Path.Combine(!string.IsNullOrEmpty(progFilesW64) ? progFilesW64 : progFiles, @"Neovim\bin");
            var extraDirList = new List<string>
            {
                Path.Combine(localAppData, @"agy\bin"),
                Path.Combine(userProfile, @".gemini\bin"),
                Path.Combine(userProfile, @".local\bin"),
                Path.Combine(userProfile, @".cargo\bin"),
                Path.Combine(userProfile, @"scoop\shims"),
                Path.Combine(appData, "npm"),
                Path.Combine(localAppData, @"Programs\Ollama"),
                Path.Combine(localAppData, @"Microsoft\WinGet\Links"),
                Path.Combine(userProfile, @".bun\bin"),
                Path.Combine(localAppData, @"pnpm"),
                Path.Combine(localAppData, @"Programs\oh-my-posh\bin"),
                neovimDir,
                Path.Combine(localAppData, @"Android\Sdk\platform-tools")
            };
            try
            {
                string pyBase = Path.Combine(localAppData, @"Programs\Python");
                if (Directory.Exists(pyBase))
                {
                    foreach (string pySub in Directory.GetDirectories(pyBase, "Python3*"))
                    {
                        extraDirList.Add(Path.Combine(pySub, "Scripts"));
                    }
                }
            }
            catch {}
            foreach (string ed in extraDirList)
            {
                if (!string.IsNullOrEmpty(ed) && seenDirs.Add(ed) && Directory.Exists(ed))
                {
                    pathDirs.Add(ed);
                }
            }

            var cliProbes = new Tuple<string, string, string, string>[]
            {
                Tuple.Create("agy.exe", "Google.AntigravityCLI", "Antigravity CLI", "agy"),
                Tuple.Create("uv.exe", "astral-sh.uv", "uv", "uv"),
                Tuple.Create("yt-dlp.exe", "yt-dlp.yt-dlp", "yt-dlp", "yt-dlp"),
                Tuple.Create("ffmpeg.exe", "Gyan.FFmpeg", "FFmpeg", "ffmpeg"),
                Tuple.Create("aria2c.exe", "aria2.aria2", "aria2", "aria2"),
                Tuple.Create("rclone.exe", "Rclone.Rclone", "Rclone", "rclone"),
                Tuple.Create("bun.exe", "Oven-sh.Bun", "Bun", "bun"),
                Tuple.Create("pnpm.exe", "pnpm.pnpm", "pnpm", "pnpm"),
                Tuple.Create("pnpm.cmd", "pnpm.pnpm", "pnpm", "pnpm"),
                Tuple.Create("yarn.cmd", "Yarn.Yarn", "Yarn", "yarn"),
                Tuple.Create("fastfetch.exe", "Fastfetch-cli.Fastfetch", "Fastfetch", "fastfetch"),
                Tuple.Create("oh-my-posh.exe", "JanDeDobbeleer.OhMyPosh", "Oh My Posh", "oh-my-posh"),
                Tuple.Create("nvim.exe", "Neovim.Neovim", "Neovim", "nvim"),
                Tuple.Create("adb.exe", "Google.PlatformTools", "Android Platform Tools", "adb"),
                Tuple.Create("gitleaks.exe", "Gitleaks.Gitleaks", "Gitleaks", "gitleaks")
            };

            var seenCliIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var probe in cliProbes)
            {
                if (seenCliIds.Contains(probe.Item2)) continue;
                string foundExe = null;
                foreach (string pd in pathDirs)
                {
                    string cand = Path.Combine(pd, probe.Item1);
                    if (File.Exists(cand))
                    {
                        foundExe = cand;
                        break;
                    }
                }
                if (foundExe != null)
                {
                    seenCliIds.Add(probe.Item2);
                    string exeVer = ResolveCliExactVersion(foundExe, probe.Item4);
                    items.Add(new CatalogSensorItem
                    {
                        Name = probe.Item3,
                        ID = probe.Item2,
                        Version = exeVer,
                        Available = "",
                        HasUpdate = false,
                        CleanName = CleanCatalogAppName(probe.Item3),
                        Source = "local"
                    });
                }
            }

            string[] legacyPaths = new string[]
            {
                Path.Combine(appData, @".tlauncher\legacy\Minecraft\TL.exe"),
                Path.Combine(appData, @".tlauncher\legacy"),
                Path.Combine(appData, @".minecraft\LLauncher.exe"),
                Path.Combine(appData, @"Microsoft\Windows\Start Menu\Programs\Legacy Launcher.lnk")
            };
            foreach (string lp in legacyPaths)
            {
                if (!string.IsNullOrEmpty(lp) && (File.Exists(lp) || Directory.Exists(lp)))
                {
                    items.Add(new CatalogSensorItem
                    {
                        Name = "Legacy Launcher",
                        ID = "LegacyLauncher.LegacyLauncher",
                        Version = "Installed",
                        Available = "",
                        HasUpdate = false,
                        CleanName = "legacylauncher",
                        Source = "local"
                    });
                    break;
                }
            }

            return items;
        }

        private static bool HasValidAuthenticodeCert(string filePath)
        {
            object cert = null;
            try
            {
                MethodInfo m = typeof(X509Certificate).GetMethod("CreateFromSignedFile", new Type[] { typeof(string) });
                if (m == null) return false;
                cert = m.Invoke(null, new object[] { filePath });
                return cert != null;
            }
            catch
            {
                return false;
            }
            finally
            {
                IDisposable disp = cert as IDisposable;
                if (disp != null)
                {
                    try { disp.Dispose(); } catch {}
                }
            }
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

        public static bool HasCrackOrPatchIndicators(string installDir)
        {
            if (string.IsNullOrWhiteSpace(installDir)) return false;
            try
            {
                if (!Directory.Exists(installDir) || IsReparsePoint(installDir)) return false;
            }
            catch { return false; }

            var indicatorFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "steam_emu.ini", "codex.ini", "flt.ini", "goldberg.ini", "tenoke.ini",
                "rune.ini", "skidrow.ini", "cpy.ini", "rld.ini", "ali213.ini",
                "3dmgame.ini", "cream_api.ini", "koalageddon.json", "smoke_api.json",
                "smokeapi.config.json", "patcher.exe", "keygen.exe", "activator.exe",
                "crack.txt", "readme_crack.txt"
            };

            var proxyDllNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "version.dll", "winmm.dll", "winhttp.dll", "dsound.dll", "dbghelp.dll",
                "dinput8.dll", "dxgi.dll", "msimg32.dll", "wtsapi32.dll", "iphlpapi.dll",
                "uxtheme.dll", "cryptsp.dll", "userenv.dll", "bink2w64.dll",
                "steam_api64.dll", "steam_api.dll", "galaxy64.dll", "eossdk-win64-shipping.dll"
            };

            var skipScanDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache",
                "GrShaderCache", "ShaderCache", "Crashpad", "logs", "Log", "temp", "tmp",
                "blob_storage", "Service Worker", "packages", "IndexedDB", "WebStorage",
                "locales", "swiftshader", "Dictionaries", "node_modules"
            };

            var currentLevel = new List<string> { installDir };
            for (int depth = 0; depth <= 1; depth++)
            {
                var nextLevel = new List<string>();
                foreach (var dir in currentLevel)
                {
                    try
                    {
                        bool hasExe = false;
                        var candidateProxies = new List<string>();
                        foreach (var file in Directory.EnumerateFiles(dir))
                        {
                            string fn = Path.GetFileName(file) ?? "";
                            if (indicatorFiles.Contains(fn)) return true;
                            if (fn.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) hasExe = true;
                            if (proxyDllNames.Contains(fn)) candidateProxies.Add(file);
                        }

                        if (hasExe && candidateProxies.Count > 0)
                        {
                            foreach (var proxyFile in candidateProxies)
                            {
                                if (!HasValidAuthenticodeCert(proxyFile)) return true;
                            }
                        }

                        if (depth < 1)
                        {
                            foreach (var sub in Directory.EnumerateDirectories(dir))
                            {
                                if (IsReparsePoint(sub)) continue;
                                string subName = Path.GetFileName(sub) ?? "";
                                if (skipScanDirs.Contains(subName)) continue;
                                nextLevel.Add(sub);
                            }
                        }
                    }
                    catch {}
                }
                if (nextLevel.Count == 0) break;
                currentLevel = nextLevel;
            }

            return false;
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

        public static Task<List<CatalogSensorItem>> ScanCatalogSensorsAsync()
        {
            return Task.Run(delegate() { return ScanCatalogSensors(); });
        }

        private sealed class AliasPatternPair
        {
            public string Raw;
            public string Clean;
            public Regex Pattern;
        }

        private sealed class CompiledTargetMeta
        {
            public string ID;
            public string Name;
            public string CleanTarget;
            public List<AliasPatternPair> CleanAliases;
            public List<AliasPatternPair> AliasEntries;
            public Regex PatternClean;
            public List<string> QueryTokens;
            public bool AllowNoise;
            public bool IsPrev;
            public bool IsVcRedist;
            public bool IsComm;
            public bool IsPro;
            public bool IsIde;
            public bool IsAntigravity;
            public bool IsCli;
            public bool IsBt;
            public bool IsVsc;
            public bool IsVsAny;
            public bool IsEtb;
            public bool IsTemurin;
            public bool IsOracleJava;
            public bool IsCorretto;
            public bool IsJdk;
            public bool IsJre;
            public Regex RxReqPy;
            public Regex RxReqPyVer;
            public Regex RxReqJava;
            public Regex RxReqJavaVer;
            public string ReqDnRaw;
            public Regex RxReqDnId;
            public Regex RxReqDnName;
            public Regex RxReqDnVer;
            public string ReqYear;
            public string Arch;
        }

        private static readonly ConcurrentDictionary<string, CompiledTargetMeta> _metaCache =
            new ConcurrentDictionary<string, CompiledTargetMeta>(StringComparer.OrdinalIgnoreCase);

        private static readonly HashSet<string> _matchStopWords = new HashSet<string>(
            new string[] {
                "microsoft", "windows", "google", "runtime", "desktop", "client", "studio", "server",
                "edition", "community", "x64", "x86", "arm64", "arp", "msix", "machine", "user",
                "app", "pro", "free", "jdk", "jre", "lts", "cli", "ide", "gui", "vpn", "bit"
            }, StringComparer.OrdinalIgnoreCase);

        private static readonly Regex _rxTokSplit = new Regex(@"[^a-zA-Z0-9+]+", RegexOptions.Compiled);
        private static readonly Regex _rxSyntheticId = new Regex(@"^(ARP|MSIX|LOCAL)\\", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxAllowNoise = new Regex(@"(Maintenance|Control Panel|Context Menu|AddOn|Installer|Agent)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxNoiseName = new Regex(@"(Maintenance Service|Control Panels|Context Menu|SparseApp|SDK AddOn|CoreEditorFonts|Visual Studio Installer|Development Libraries|Standard Library|Test Suite|Tcl/Tk Support|pip Bootstrap)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxNoiseId = new Regex(@"(MozillaMaintenanceService|ContextMenu|SparseApp|FigmaAgent)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxPyLauncher = new Regex(@"^Python Launcher\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxWordUwp = new Regex(@"\bUWP\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxWordComm = new Regex(@"\bCommunity\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxDotComm = new Regex(@"\.Community\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxWordPro = new Regex(@"\b(Ultimate|Professional)\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxDotPro = new Regex(@"\.(Ultimate|Professional)\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxWordIde = new Regex(@"\bIDE\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxEndIde = new Regex(@"IDE$", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxWordCli = new Regex(@"\bCLI\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxEndCli = new Regex(@"(\.cli|CLI)$", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxVscName = new Regex(@"VS Code|Visual Studio Code", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxJavaUpdate = new Regex(@"^Java \d+ Update", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxWordJdk = new Regex(@"\bJDK\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxEndJdk = new Regex(@"\.JDK$", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxWordJre = new Regex(@"\bJRE\b|^Java \d+ Update", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxEndJre = new Regex(@"\.(JRE|JavaRuntimeEnvironment)$", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxTargetPy = new Regex(@"^Python\.Python\.(\d+\.\d+)$", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxTargetJava = new Regex(@"\.(Temurin|Corretto)\.(\d+)\.", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxTargetDn = new Regex(@"^Microsoft\.DotNet\.DesktopRuntime\.(\d+(?:_\d+)?)(?:\.|$)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxTargetYear = new Regex(@"^Microsoft\.VCRedist\.(\d{4})\.", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxArchX64Name = new Regex(@"\(x64\)|\.x64", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxArchX86Name = new Regex(@"\(x86\)|\.x86", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxArchArmName = new Regex(@"\(arm64\)|\.arm64", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxItemX64 = new Regex(@"(?<![a-zA-Z0-9])(x64|64-bit)(?![a-zA-Z0-9])", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxItemX86 = new Regex(@"(?<![a-zA-Z0-9])(x86|32-bit)(?![a-zA-Z0-9])", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxItemArm = new Regex(@"(?<![a-zA-Z0-9])arm64(?![a-zA-Z0-9])", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        private static CompiledTargetMeta GetOrBuildTargetMeta(CatalogMatchTarget target)
        {
            string tId = target.ID ?? "";
            CompiledTargetMeta cached;
            if (_metaCache.TryGetValue(tId, out cached)) return cached;

            string tName = target.Name ?? "";
            string tCat = target.Category ?? "";
            string cleanTarget = CleanCatalogAppName(tName);

            var cleanAliases = new List<AliasPatternPair>();
            var aliasEntries = new List<AliasPatternPair>();
            var queryTokens = new List<string>();
            var seenTokens = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            if (cleanTarget.Length >= 4)
            {
                string[] toks = _rxTokSplit.Split(cleanTarget);
                for (int i = 0; i < toks.Length; i++)
                {
                    string qt = toks[i];
                    if (qt.Length >= 3 && !_matchStopWords.Contains(qt) && seenTokens.Add(qt))
                    {
                        queryTokens.Add(qt);
                    }
                }
            }

            if (target.Aliases != null)
            {
                for (int ai = 0; ai < target.Aliases.Length; ai++)
                {
                    string alias = target.Aliases[ai];
                    if (string.IsNullOrWhiteSpace(alias)) continue;
                    string cAl = CleanCatalogAppName(alias);
                    var pair = new AliasPatternPair { Raw = alias, Clean = cAl, Pattern = null };
                    cleanAliases.Add(pair);
                    if (alias.Length >= 4)
                    {
                        pair.Pattern = new Regex(@"(?<![a-zA-Z0-9])" + Regex.Escape(alias) + @"(?![a-zA-Z0-9])", RegexOptions.IgnoreCase);
                        aliasEntries.Add(pair);
                        string[] toks = _rxTokSplit.Split(alias);
                        for (int i = 0; i < toks.Length; i++)
                        {
                            string qt = toks[i];
                            if (qt.Length >= 3 && !_matchStopWords.Contains(qt) && seenTokens.Add(qt))
                            {
                                queryTokens.Add(qt);
                            }
                        }
                    }
                }
            }

            Regex patternClean = (cleanTarget.Length >= 4)
                ? new Regex(@"(?<![a-zA-Z0-9])" + Regex.Escape(cleanTarget) + @"(?![a-zA-Z0-9])", RegexOptions.IgnoreCase)
                : null;

            Regex rxReqPy = null;
            Regex rxReqPyVer = null;
            Match mPy = _rxTargetPy.Match(tId);
            if (mPy.Success)
            {
                string esc = Regex.Escape(mPy.Groups[1].Value);
                rxReqPy = new Regex(esc, RegexOptions.IgnoreCase);
                rxReqPyVer = new Regex("^" + esc + @"(\.|$)", RegexOptions.IgnoreCase);
            }

            Regex rxReqJava = null;
            Regex rxReqJavaVer = null;
            Match mJava = _rxTargetJava.Match(tId);
            if (mJava.Success)
            {
                string jv = mJava.Groups[2].Value;
                rxReqJava = new Regex(@"\b" + jv + @"\b", RegexOptions.IgnoreCase);
                rxReqJavaVer = new Regex("^" + jv + @"(\.|$)", RegexOptions.IgnoreCase);
            }

            string reqDnRaw = "";
            Regex rxReqDnId = null;
            Regex rxReqDnName = null;
            Regex rxReqDnVer = null;
            Match mDn = _rxTargetDn.Match(tId);
            if (mDn.Success)
            {
                reqDnRaw = mDn.Groups[1].Value;
                string reqDnEsc = reqDnRaw.Replace("_", @"\.");
                rxReqDnId = new Regex(@"DesktopRuntime\." + Regex.Escape(reqDnRaw) + @"(\.|$)", RegexOptions.IgnoreCase);
                rxReqDnName = new Regex(@"\b" + reqDnEsc + @"(\.\d+|\b)", RegexOptions.IgnoreCase);
                rxReqDnVer = new Regex("^" + reqDnEsc + @"(\.|$)", RegexOptions.IgnoreCase);
            }

            string reqYear = "";
            Match mYr = _rxTargetYear.Match(tId);
            if (mYr.Success) reqYear = mYr.Groups[1].Value;

            string tArch = "";
            if (_rxArchX64Name.IsMatch(tName) || tId.EndsWith(".x64", StringComparison.OrdinalIgnoreCase)) tArch = "x64";
            else if (_rxArchX86Name.IsMatch(tName) || tId.EndsWith(".x86", StringComparison.OrdinalIgnoreCase)) tArch = "x86";
            else if (_rxArchArmName.IsMatch(tName) || tId.EndsWith(".arm64", StringComparison.OrdinalIgnoreCase)) tArch = "arm64";
            else if (Environment.Is64BitOperatingSystem && string.Equals(tCat, ".NET Runtimes", StringComparison.OrdinalIgnoreCase) && tId.IndexOf("DesktopRuntime", StringComparison.OrdinalIgnoreCase) >= 0) tArch = "x64";

            var meta = new CompiledTargetMeta
            {
                ID = tId,
                Name = tName,
                CleanTarget = cleanTarget,
                CleanAliases = cleanAliases,
                AliasEntries = aliasEntries,
                PatternClean = patternClean,
                QueryTokens = queryTokens,
                AllowNoise = _rxAllowNoise.IsMatch(tName),
                IsPrev = (tName.IndexOf("Preview", StringComparison.OrdinalIgnoreCase) >= 0) || (tId.IndexOf("Preview", StringComparison.OrdinalIgnoreCase) >= 0),
                IsVcRedist = (tId.IndexOf("VCRedist", StringComparison.OrdinalIgnoreCase) >= 0) || (tName.IndexOf("VC++", StringComparison.OrdinalIgnoreCase) >= 0),
                IsComm = _rxWordComm.IsMatch(tName) || _rxDotComm.IsMatch(tId),
                IsPro = _rxWordPro.IsMatch(tName) || _rxDotPro.IsMatch(tId),
                IsIde = _rxWordIde.IsMatch(tName) || _rxEndIde.IsMatch(tId),
                IsAntigravity = tId.IndexOf("Antigravity", StringComparison.OrdinalIgnoreCase) >= 0,
                IsCli = _rxWordCli.IsMatch(tName) || _rxEndCli.IsMatch(tId),
                IsBt = (tName.IndexOf("Build Tools", StringComparison.OrdinalIgnoreCase) >= 0) || (tId.IndexOf("BuildTools", StringComparison.OrdinalIgnoreCase) >= 0),
                IsVsc = (tId.IndexOf("VisualStudioCode", StringComparison.OrdinalIgnoreCase) >= 0) || _rxVscName.IsMatch(tName),
                IsVsAny = tId.IndexOf("VisualStudio", StringComparison.OrdinalIgnoreCase) >= 0,
                IsEtb = (tId.IndexOf("EverythingToolbar", StringComparison.OrdinalIgnoreCase) >= 0) || (tName.IndexOf("EverythingToolbar", StringComparison.OrdinalIgnoreCase) >= 0),
                IsTemurin = tId.IndexOf("Temurin", StringComparison.OrdinalIgnoreCase) >= 0,
                IsOracleJava = tId.IndexOf("Oracle.Java", StringComparison.OrdinalIgnoreCase) >= 0,
                IsCorretto = tId.IndexOf("Corretto", StringComparison.OrdinalIgnoreCase) >= 0,
                IsJdk = _rxWordJdk.IsMatch(tName) || _rxEndJdk.IsMatch(tId),
                IsJre = _rxWordJre.IsMatch(tName) || _rxEndJre.IsMatch(tId),
                RxReqPy = rxReqPy,
                RxReqPyVer = rxReqPyVer,
                RxReqJava = rxReqJava,
                RxReqJavaVer = rxReqJavaVer,
                ReqDnRaw = reqDnRaw,
                RxReqDnId = rxReqDnId,
                RxReqDnName = rxReqDnName,
                RxReqDnVer = rxReqDnVer,
                ReqYear = reqYear,
                Arch = tArch
            };

            _metaCache[tId] = meta;
            return meta;
        }

        private static bool IsMatchCompatible(CompiledTargetMeta meta, CatalogSensorItem item)
        {
            if (meta == null || item == null) return false;
            string tId = meta.ID;
            string iName = item.Name ?? "";
            string iId = item.ID ?? "";
            string iVer = item.Version ?? "";

            if (!meta.AllowNoise)
            {
                if (_rxNoiseName.IsMatch(iName) || _rxNoiseId.IsMatch(iId)) return false;
            }

            if (string.Equals(iId, "Python.Launcher", StringComparison.OrdinalIgnoreCase) || _rxPyLauncher.IsMatch(iName))
            {
                if (!string.Equals(tId, "Python.Launcher", StringComparison.OrdinalIgnoreCase)) return false;
            }

            bool iPrev = (iName.IndexOf("Preview", StringComparison.OrdinalIgnoreCase) >= 0) || (iId.IndexOf("Preview", StringComparison.OrdinalIgnoreCase) >= 0);
            if (meta.IsPrev != iPrev && !string.Equals(tId, "Microsoft.PowerToys", StringComparison.OrdinalIgnoreCase)) return false;

            if (meta.IsVcRedist && (_rxWordUwp.IsMatch(iName) || iId.IndexOf("VCLibs", StringComparison.OrdinalIgnoreCase) >= 0)) return false;

            if (meta.IsComm || meta.IsPro)
            {
                bool iComm = _rxWordComm.IsMatch(iName) || _rxDotComm.IsMatch(iId);
                bool iPro = _rxWordPro.IsMatch(iName) || _rxDotPro.IsMatch(iId);
                if ((meta.IsComm && iPro) || (meta.IsPro && iComm)) return false;
            }

            if (meta.IsAntigravity || iId.IndexOf("Antigravity", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                bool iIde = _rxWordIde.IsMatch(iName) || _rxEndIde.IsMatch(iId);
                if (meta.IsIde != iIde) return false;
            }

            bool iCli = _rxWordCli.IsMatch(iName) || _rxEndCli.IsMatch(iId);
            if (meta.IsCli != iCli) return false;

            bool iBt = (iName.IndexOf("Build Tools", StringComparison.OrdinalIgnoreCase) >= 0) || (iId.IndexOf("BuildTools", StringComparison.OrdinalIgnoreCase) >= 0);
            if (meta.IsBt != iBt) return false;

            if (meta.IsVsAny || iId.IndexOf("VisualStudio", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                bool iVsc = (iId.IndexOf("VisualStudioCode", StringComparison.OrdinalIgnoreCase) >= 0) || _rxVscName.IsMatch(iName);
                if (meta.IsVsc != iVsc) return false;
            }

            bool iEtb = (iId.IndexOf("EverythingToolbar", StringComparison.OrdinalIgnoreCase) >= 0) || (iName.IndexOf("EverythingToolbar", StringComparison.OrdinalIgnoreCase) >= 0);
            if (meta.IsEtb != iEtb) return false;

            if (meta.IsTemurin && (iId.IndexOf("Oracle", StringComparison.OrdinalIgnoreCase) >= 0 || iId.IndexOf("Corretto", StringComparison.OrdinalIgnoreCase) >= 0 || iName.IndexOf("Corretto", StringComparison.OrdinalIgnoreCase) >= 0 || _rxJavaUpdate.IsMatch(iName))) return false;
            if (meta.IsOracleJava && (iId.IndexOf("Temurin", StringComparison.OrdinalIgnoreCase) >= 0 || iId.IndexOf("Corretto", StringComparison.OrdinalIgnoreCase) >= 0 || iName.IndexOf("Temurin", StringComparison.OrdinalIgnoreCase) >= 0 || iName.IndexOf("Corretto", StringComparison.OrdinalIgnoreCase) >= 0)) return false;
            if (meta.IsCorretto && (iId.IndexOf("Temurin", StringComparison.OrdinalIgnoreCase) >= 0 || iId.IndexOf("Oracle", StringComparison.OrdinalIgnoreCase) >= 0 || iName.IndexOf("Temurin", StringComparison.OrdinalIgnoreCase) >= 0 || _rxJavaUpdate.IsMatch(iName))) return false;

            if (meta.IsJdk || meta.IsJre)
            {
                bool iJdk = _rxWordJdk.IsMatch(iName) || _rxEndJdk.IsMatch(iId);
                bool iJre = _rxWordJre.IsMatch(iName) || _rxEndJre.IsMatch(iId);
                if ((meta.IsJdk && iJre && !iJdk) || (meta.IsJre && iJdk && !iJre)) return false;
            }

            if (meta.RxReqPy != null)
            {
                if (!meta.RxReqPy.IsMatch(iId) && !meta.RxReqPy.IsMatch(iName) && !meta.RxReqPyVer.IsMatch(iVer)) return false;
            }

            if (meta.RxReqJava != null)
            {
                if (!meta.RxReqJava.IsMatch(iId) && !meta.RxReqJava.IsMatch(iName) && !meta.RxReqJavaVer.IsMatch(iVer)) return false;
            }

            if (!string.IsNullOrEmpty(meta.ReqDnRaw))
            {
                if (iId.IndexOf("DesktopRuntime", StringComparison.OrdinalIgnoreCase) < 0 && iName.IndexOf("Desktop", StringComparison.OrdinalIgnoreCase) < 0) return false;
                if (!meta.RxReqDnId.IsMatch(iId) && !meta.RxReqDnName.IsMatch(iName) && !meta.RxReqDnVer.IsMatch(iVer)) return false;
            }

            if (!string.IsNullOrEmpty(meta.ReqYear))
            {
                if (iId.IndexOf(meta.ReqYear, StringComparison.OrdinalIgnoreCase) < 0 && iName.IndexOf(meta.ReqYear, StringComparison.OrdinalIgnoreCase) < 0) return false;
            }

            if (!string.IsNullOrEmpty(meta.Arch))
            {
                string idForArch = _rxSyntheticId.IsMatch(iId) ? "" : iId;
                string iArch = "";
                if (_rxItemX64.IsMatch(iName) || idForArch.EndsWith(".x64", StringComparison.OrdinalIgnoreCase)) iArch = "x64";
                else if (_rxItemX86.IsMatch(iName) || idForArch.EndsWith(".x86", StringComparison.OrdinalIgnoreCase)) iArch = "x86";
                else if (_rxItemArm.IsMatch(iName) || idForArch.EndsWith(".arm64", StringComparison.OrdinalIgnoreCase)) iArch = "arm64";
                if (!string.IsNullOrEmpty(iArch) && !string.Equals(iArch, meta.Arch, StringComparison.OrdinalIgnoreCase)) return false;
            }

            return true;
        }

        private static void SetPreferredEntry(Dictionary<string, CatalogSensorItem> map, string key, CatalogSensorItem cand)
        {
            if (string.IsNullOrWhiteSpace(key) || cand == null) return;
            CatalogSensorItem cur;
            if (!map.TryGetValue(key, out cur))
            {
                map[key] = cand;
                return;
            }
            bool curLocal = string.Equals(cur.Source, "local", StringComparison.OrdinalIgnoreCase);
            bool candLocal = string.Equals(cand.Source, "local", StringComparison.OrdinalIgnoreCase);
            if (curLocal && !candLocal) { map[key] = cand; return; }
            if (!curLocal && candLocal) return;

            bool curSyn = _rxSyntheticId.IsMatch(cur.ID ?? "");
            bool candSyn = _rxSyntheticId.IsMatch(cand.ID ?? "");
            if (curSyn && !candSyn) { map[key] = cand; return; }
            if (!curSyn && candSyn) return;

            int verCmp = CompareAppVersions(cand.Version, cur.Version);
            string bestVer = (verCmp > 0 || string.IsNullOrWhiteSpace(cur.Version)) ? cand.Version : cur.Version;
            int availCmp = CompareAppVersions(cand.Available, cur.Available);
            string bestAvail = (availCmp > 0) ? cand.Available : cur.Available;
            bool mergedUpd = TestAppUpdateGenuine(bestVer, bestAvail);
            if (!mergedUpd) bestAvail = "";
            bool useCand = (!cur.HasUpdate && cand.HasUpdate) || (verCmp > 0);
            CatalogSensorItem baseObj = useCand ? cand : cur;
            map[key] = new CatalogSensorItem
            {
                Name = baseObj.Name,
                ID = baseObj.ID,
                Version = bestVer,
                Available = bestAvail,
                HasUpdate = mergedUpd,
                CleanName = baseObj.CleanName,
                Source = baseObj.Source
            };
        }

        public static CatalogSensorItem[] MatchCatalogApps(CatalogMatchTarget[] targets, CatalogSensorItem[] installedItems)
        {
            if (targets == null || targets.Length == 0) return new CatalogSensorItem[0];
            var results = new CatalogSensorItem[targets.Length];
            if (installedItems == null || installedItems.Length == 0) return results;

            if (_metaCache.Count < targets.Length)
            {
                Parallel.For(0, targets.Length, i =>
                {
                    CatalogMatchTarget t = targets[i];
                    if (t != null) GetOrBuildTargetMeta(t);
                });
            }

            var idMap = new Dictionary<string, CatalogSensorItem>(StringComparer.OrdinalIgnoreCase);
            var nameMap = new Dictionary<string, CatalogSensorItem>(StringComparer.OrdinalIgnoreCase);
            var cleanNameMap = new Dictionary<string, CatalogSensorItem>(StringComparer.OrdinalIgnoreCase);
            var tokenIndex = new Dictionary<string, List<CatalogSensorItem>>(StringComparer.OrdinalIgnoreCase);

            for (int i = 0; i < installedItems.Length; i++)
            {
                CatalogSensorItem it = installedItems[i];
                if (it == null) continue;
                string itId = it.ID ?? "";
                string itName = it.Name ?? "";
                string itClean = it.CleanName ?? "";

                if (!string.IsNullOrWhiteSpace(itId)) SetPreferredEntry(idMap, itId, it);
                if (!string.IsNullOrWhiteSpace(itName)) SetPreferredEntry(nameMap, itName, it);
                if (itClean.Length >= 2) SetPreferredEntry(cleanNameMap, itClean, it);
                if (string.Equals(itId, "Microsoft.VisualStudio.Community.Insiders", StringComparison.OrdinalIgnoreCase))
                {
                    SetPreferredEntry(idMap, "Microsoft.VisualStudio.2022.Community", it);
                }

                string rawText = itId + " " + itName + " " + itClean;
                string[] toks = _rxTokSplit.Split(rawText);
                var seenTok = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                for (int ti = 0; ti < toks.Length; ti++)
                {
                    string tk = toks[ti];
                    if (tk.Length >= 3 && seenTok.Add(tk))
                    {
                        List<CatalogSensorItem> bucket;
                        if (!tokenIndex.TryGetValue(tk, out bucket))
                        {
                            bucket = new List<CatalogSensorItem>();
                            tokenIndex[tk] = bucket;
                        }
                        bucket.Add(it);
                    }
                }
            }

            var lookupCache = new Dictionary<string, CatalogSensorItem>(StringComparer.OrdinalIgnoreCase);
            for (int tIdx = 0; tIdx < targets.Length; tIdx++)
            {
                CatalogMatchTarget target = targets[tIdx];
                if (target == null) continue;
                string targetId = target.ID ?? "";
                CatalogSensorItem cachedRes;
                if (lookupCache.TryGetValue(targetId, out cachedRes))
                {
                    results[tIdx] = cachedRes;
                    continue;
                }

                CompiledTargetMeta meta = GetOrBuildTargetMeta(target);
                CatalogSensorItem matched = null;
                CatalogSensorItem cand;

                if (idMap.TryGetValue(targetId, out cand) && IsMatchCompatible(meta, cand))
                {
                    matched = cand;
                }
                if (matched == null)
                {
                    for (int a = 0; a < meta.CleanAliases.Count; a++)
                    {
                        if (idMap.TryGetValue(meta.CleanAliases[a].Raw, out cand) && IsMatchCompatible(meta, cand))
                        {
                            matched = cand;
                            break;
                        }
                    }
                }
                if (matched == null && !string.IsNullOrEmpty(meta.Name) && nameMap.TryGetValue(meta.Name, out cand) && IsMatchCompatible(meta, cand))
                {
                    matched = cand;
                }
                if (matched == null)
                {
                    for (int a = 0; a < meta.CleanAliases.Count; a++)
                    {
                        AliasPatternPair ap = meta.CleanAliases[a];
                        if (nameMap.TryGetValue(ap.Raw, out cand) && IsMatchCompatible(meta, cand))
                        {
                            matched = cand;
                            break;
                        }
                        if (ap.Clean.Length >= 2 && cleanNameMap.TryGetValue(ap.Clean, out cand) && IsMatchCompatible(meta, cand))
                        {
                            matched = cand;
                            break;
                        }
                    }
                }
                if (matched == null && meta.CleanTarget.Length >= 2 && cleanNameMap.TryGetValue(meta.CleanTarget, out cand) && IsMatchCompatible(meta, cand))
                {
                    matched = cand;
                }

                if (matched == null && meta.QueryTokens.Count > 0)
                {
                    var candidatePool = new List<CatalogSensorItem>();
                    var seenCand = new HashSet<CatalogSensorItem>();
                    for (int q = 0; q < meta.QueryTokens.Count; q++)
                    {
                        List<CatalogSensorItem> bucket;
                        if (tokenIndex.TryGetValue(meta.QueryTokens[q], out bucket))
                        {
                            for (int bi = 0; bi < bucket.Count; bi++)
                            {
                                if (seenCand.Add(bucket[bi])) candidatePool.Add(bucket[bi]);
                            }
                        }
                    }

                    CatalogSensorItem bestCand = null;
                    int bestScore = 0;
                    for (int ci = 0; ci < candidatePool.Count; ci++)
                    {
                        CatalogSensorItem item = candidatePool[ci];
                        string iId = item.ID ?? "";
                        string iName = item.Name ?? "";
                        string iClean = item.CleanName ?? "";
                        int score = 0;

                        for (int aeIdx = 0; aeIdx < meta.AliasEntries.Count; aeIdx++)
                        {
                            AliasPatternPair ae = meta.AliasEntries[aeIdx];
                            if (iId.IndexOf(ae.Raw, StringComparison.OrdinalIgnoreCase) >= 0 && ae.Pattern.IsMatch(iId))
                            {
                                score = 780;
                                break;
                            }
                            if (iName.IndexOf(ae.Raw, StringComparison.OrdinalIgnoreCase) >= 0 && ae.Pattern.IsMatch(iName))
                            {
                                int lenRatio = Math.Min(40, (meta.CleanTarget.Length * 40) / Math.Max(1, iName.Length));
                                int cScore = 700 + lenRatio;
                                if (cScore > score) score = cScore;
                            }
                        }

                        if (score == 0 && meta.PatternClean != null && iClean.IndexOf(meta.CleanTarget, StringComparison.OrdinalIgnoreCase) >= 0 && meta.PatternClean.IsMatch(iClean))
                        {
                            int lenRatio = Math.Min(40, (meta.CleanTarget.Length * 40) / Math.Max(1, iClean.Length));
                            score = 650 + lenRatio;
                        }

                        if (score > 0)
                        {
                            if (item.HasUpdate) score += 15;
                            if (!_rxSyntheticId.IsMatch(iId)) score += 10;
                            if (score > bestScore && IsMatchCompatible(meta, item))
                            {
                                bestScore = score;
                                bestCand = item;
                            }
                        }
                    }
                    matched = bestCand;
                }

                lookupCache[targetId] = matched;
                results[tIdx] = matched;
            }

            return results;
        }

        public static Task<CatalogSensorItem[]> MatchCatalogAppsAsync(CatalogMatchTarget[] targets, CatalogSensorItem[] installedItems)
        {
            return Task.Run(delegate() { return MatchCatalogApps(targets, installedItems); });
        }
    }
}
