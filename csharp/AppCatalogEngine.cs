using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
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

    public static class AppCatalogEngine
    {
        private static readonly Regex _rxCleanParens = new Regex(@"\((?!x64|x86|arm64).*?\)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxCleanVerWord = new Regex(@"\b(version|ver|v|release)\s*\d+(\.\d+)*[^\s]*", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxCleanVerNum = new Regex(@"\b\d+(\.\d+){1,4}(-[a-z0-9.]+)?\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxMultiSpace = new Regex(@"\s+", RegexOptions.Compiled);
        private static readonly Regex _rxVerExtract = new Regex(@"\d+(?:[.+_-]\d+)*", RegexOptions.Compiled);
        private static readonly Regex _rxVerSplit = new Regex(@"[.+_-]", RegexOptions.Compiled);
        private static readonly Regex _rxAnsi = new Regex(@"\x1B\[[0-9;?]*[A-Za-z]", RegexOptions.Compiled);
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
            if (iv.Equals("Unknown", StringComparison.OrdinalIgnoreCase) || iv.Equals("Installed", StringComparison.OrdinalIgnoreCase)) return true;
            return CompareAppVersions(av, iv) > 0;
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

            string appName = "", appId = "", version = "", avail = "";
            if (cId > 0 && line.Length > cId)
            {
                appName = line.Substring(0, cId).Trim();
                if (cVer > cId && line.Length > cVer)
                {
                    appId = line.Substring(cId, cVer - cId).Trim();
                    if (cAvail > cVer && line.Length > cAvail)
                    {
                        version = line.Substring(cVer, cAvail - cVer).Trim();
                        if (cSrc > cAvail && line.Length > cSrc)
                        {
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
                string headerLine = lines[separatorIndex - 1];
                MatchCollection matches = Regex.Matches(headerLine, @"\S+(\s\S+)*");
                var colOffsetsList = new List<int>(matches.Count);
                foreach (Match m in matches) colOffsetsList.Add(m.Index);
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
                            if (cId > 0 && line.Length > cId)
                            {
                                appName = line.Substring(0, cId).Trim();
                                if (cVer > cId && line.Length > cVer)
                                {
                                    appId = line.Substring(cId, cVer - cId).Trim();
                                    if (cAvail > cVer && line.Length > cAvail)
                                    {
                                        version = line.Substring(cVer, cAvail - cVer).Trim();
                                        avail = (cSrc > cAvail && line.Length > cSrc) ? line.Substring(cAvail, cSrc - cAvail).Trim() : line.Substring(cAvail).Trim();
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
            string raw = cmd.Trim();
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
            string u = uninstallString.Trim();
            if (u.IndexOf("msiexec", StringComparison.OrdinalIgnoreCase) >= 0) return false;

            string exePath = ExtractExePath(u);
            if (string.IsNullOrEmpty(exePath)) return false;

            bool exeExists = false;
            try { exeExists = File.Exists(exePath); } catch {}

            if (!exeExists)
            {
                bool locExists = false;
                try
                {
                    if (!string.IsNullOrEmpty(installLocation) && Directory.Exists(installLocation))
                    {
                        locExists = true;
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
                Tuple.Create(RegistryHive.CurrentUser, RegistryView.Default, @"Software\Microsoft\Windows\CurrentVersion\Uninstall", @"ARP\User\X64\")
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

                                    if (dn.IndexOf("Visual Studio Code (User)", StringComparison.OrdinalIgnoreCase) >= 0 && !vsCodeUserExists)
                                    {
                                        continue;
                                    }

                                    string loc = (sk.GetValue("InstallLocation") as string ?? "").Trim();
                                    string uStr = (sk.GetValue("UninstallString") as string ?? "").Trim();
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

            var dotnetShares = new Tuple<string, string>[]
            {
                Tuple.Create(@"C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App", "x64"),
                Tuple.Create(@"C:\Program Files (x86)\dotnet\shared\Microsoft.WindowsDesktop.App", "x86")
            };

            foreach (var ds in dotnetShares)
            {
                if (!Directory.Exists(ds.Item1)) continue;
                try
                {
                    foreach (string verDir in Directory.GetDirectories(ds.Item1))
                    {
                        string verName = Path.GetFileName(verDir);
                        Match m = Regex.Match(verName ?? "", @"^(\d+)\.(\d+)\.");
                        if (!m.Success) continue;
                        string maj = m.Groups[1].Value;
                        string min = m.Groups[2].Value;
                        string archSuffix = ds.Item2 == "x86" ? ".x86" : "";
                        string archLabel = ds.Item2 == "x86" ? " (x86)" : " (x64)";
                        string idBand = (maj == "3" && min == "1") ? "3_1" : (maj == "11" ? "Preview" : maj);
                        string wingetId = "Microsoft.DotNet.DesktopRuntime." + idBand + archSuffix;
                        string disp = "Microsoft Windows Desktop Runtime - " + verName + archLabel;
                        items.Add(new CatalogSensorItem
                        {
                            Name = disp,
                            ID = wingetId,
                            Version = verName,
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
            string[] extraDirs = new string[]
            {
                Path.Combine(localAppData, @"agy\bin"),
                Path.Combine(userProfile, @".gemini\bin"),
                Path.Combine(userProfile, @".local\bin"),
                Path.Combine(userProfile, @".cargo\bin"),
                Path.Combine(userProfile, @"scoop\shims"),
                Path.Combine(appData, "npm"),
                Path.Combine(localAppData, @"Programs\Ollama"),
                Path.Combine(localAppData, @"Microsoft\WinGet\Links")
            };
            foreach (string ed in extraDirs)
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
                Tuple.Create("yarn.cmd", "Yarn.Yarn", "Yarn", "yarn"),
                Tuple.Create("fastfetch.exe", "Fastfetch-cli.Fastfetch", "Fastfetch", "fastfetch"),
                Tuple.Create("oh-my-posh.exe", "JanDeDobbeleer.OhMyPosh", "Oh My Posh", "oh-my-posh"),
                Tuple.Create("nvim.exe", "Neovim.Neovim", "Neovim", "nvim"),
                Tuple.Create("adb.exe", "Google.PlatformTools", "Android Platform Tools", "adb"),
                Tuple.Create("gitleaks.exe", "Gitleaks.Gitleaks", "Gitleaks", "gitleaks")
            };

            foreach (var probe in cliProbes)
            {
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

            return items;
        }
    }
}
