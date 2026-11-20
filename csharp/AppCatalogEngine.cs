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
        private static readonly Regex _rxCleanVerWord = new Regex(@"(?:\b(?:version|ver|release)\s*\d+(?:\.\d+)*[^\s]*|\bv\.?\d+(?:\.\d+)*\b)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxCleanVerNum = new Regex(@"\b\d+(\.\d+){1,4}(-[a-z0-9.]+)?\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxCleanTrailingTerms = new Regex(@"(?<=\s)(?:browser|desktop|lts|client|free|ce|community|end-user|stable|edition|x64|x86|arm64|64-bit|32-bit)(?=\s|$)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxMultiSpace = new Regex(@"\s+", RegexOptions.Compiled);
        private static readonly Regex _rxDottedVer = new Regex(@"(?<![a-zA-Z0-9])v?(\d+(?:\.\d+)+)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxSingleVer = new Regex(@"(?<![a-zA-Z0-9])v?(\d+)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxAnyDigits = new Regex(@"\d+", RegexOptions.Compiled);
        private static readonly Regex _rxAnsi = new Regex(@"\x1B\[[0-9;?]*[A-Za-z]", RegexOptions.Compiled);
        private static readonly Regex _rxPrereleaseTag = new Regex(@"(?:^|[-.+_\s])?(canary|nightly|dev|alpha|beta|preview|pre|rc|insiders?|experimental|exp|snapshot)(?![a-z])(?:[.+_-]*(\d+(?:\.\d+)*))?", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxNumericPrerelease = new Regex(@"^-(\d+(?:\.\d+)*)(?=$|[\s(])", RegexOptions.Compiled);
        private static readonly Regex _rxTrailingLetter = new Regex(@"^([a-z])(?:\s|$|\()", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxBracketBuildVer = new Regex(@"^\s*(?:[a-zA-Z]+\s+)?\[(\d+(?:\.\d+)+)\]\s*$", RegexOptions.Compiled);

        public static string CleanCatalogAppName(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return "";
            string c = _rxCleanParens.Replace(name, "").Replace("(", "").Replace(")", "").Trim().ToLowerInvariant();
            c = _rxCleanVerWord.Replace(c, "");
            c = _rxCleanVerNum.Replace(c, "");
            c = _rxCleanTrailingTerms.Replace(c, "");
            c = _rxMultiSpace.Replace(c, " ").Trim();
            return c;
        }

        private static string CompactAlnumKey(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            var sb = new System.Text.StringBuilder(s.Length);
            for (int i = 0; i < s.Length; i++)
            {
                char ch = s[i];
                if ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9')) sb.Append(ch);
                else if (ch >= 'A' && ch <= 'Z') sb.Append((char)(ch + 32));
                else if (ch == '+') sb.Append('p');
            }
            return sb.ToString();
        }

        private static string StripBuildMetadata(string verStr)
        {
            if (string.IsNullOrWhiteSpace(verStr)) return "";
            string s = verStr.Trim();
            if (s.StartsWith("<")) s = s.Substring(1).Trim();
            int plusIdx = s.IndexOf('+');
            if (plusIdx > 0) s = s.Substring(0, plusIdx).Trim();
            return s;
        }

        private static Match MatchCoreVersionSpan(string cleanVer)
        {
            if (string.IsNullOrEmpty(cleanVer)) return Match.Empty;
            Match m = _rxDottedVer.Match(cleanVer);
            if (m.Success) return m;
            m = _rxSingleVer.Match(cleanVer);
            if (m.Success) return m;
            return _rxAnyDigits.Match(cleanVer);
        }

        private static long[] ParseNumericSegments(string dotStr)
        {
            if (string.IsNullOrEmpty(dotStr)) return new long[0];
            string[] parts = dotStr.Split('.');
            var nums = new List<long>(parts.Length);
            foreach (string p in parts)
            {
                long v;
                if (long.TryParse(p, out v)) nums.Add(v);
            }
            return nums.ToArray();
        }

        private static int GetPrereleaseRankAndNumbers(string verStr, out long[] preNums, out int trailingLetter)
        {
            preNums = new long[0];
            trailingLetter = 0;
            string s = StripBuildMetadata(verStr);
            if (string.IsNullOrEmpty(s)) return 100;

            Match mCore = MatchCoreVersionSpan(s);
            string prefix = mCore.Success ? s.Substring(0, mCore.Index) : "";
            string suffix = mCore.Success ? s.Substring(mCore.Index + mCore.Length) : s;

            Match mPre = !string.IsNullOrEmpty(suffix) ? _rxPrereleaseTag.Match(suffix) : Match.Empty;
            if (!mPre.Success && !string.IsNullOrEmpty(prefix))
            {
                mPre = _rxPrereleaseTag.Match(prefix);
                if (mPre.Success)
                {
                    // Do not steal digits from a preceding token if prefix ends right before core version
                    string tagOnly = mPre.Groups[1].Value.ToLowerInvariant();
                    return MapPrereleaseTagRank(tagOnly);
                }
            }
            if (mPre.Success)
            {
                string tag = mPre.Groups[1].Value.ToLowerInvariant();
                if (mPre.Groups[2].Success) preNums = ParseNumericSegments(mPre.Groups[2].Value);
                return MapPrereleaseTagRank(tag);
            }

            if (!string.IsNullOrEmpty(suffix))
            {
                Match mNumPre = _rxNumericPrerelease.Match(suffix.TrimEnd());
                if (mNumPre.Success)
                {
                    preNums = ParseNumericSegments(mNumPre.Groups[1].Value);
                    return 0;
                }
                Match mLet = _rxTrailingLetter.Match(suffix);
                if (mLet.Success)
                {
                    char ch = char.ToLowerInvariant(mLet.Groups[1].Value[0]);
                    trailingLetter = (ch >= 'a' && ch <= 'z') ? (ch - 'a' + 1) : 0;
                }
            }

            return 100;
        }

        private static int MapPrereleaseTagRank(string tag)
        {
            if (tag == "canary" || tag == "nightly" || tag == "dev" || tag == "insider" || tag == "insiders" || tag == "snapshot") return 1;
            if (tag == "alpha" || tag == "exp" || tag == "experimental") return 2;
            if (tag == "beta") return 3;
            if (tag == "pre" || tag == "preview") return 4;
            if (tag == "rc") return 5;
            return 10;
        }

        public static long[] GetVersionNumbers(string verStr)
        {
            string s = StripBuildMetadata(verStr);
            if (string.IsNullOrEmpty(s)) return new long[0];
            Match m = MatchCoreVersionSpan(s);
            if (!m.Success) return new long[0];
            string cap = m.Groups.Count > 1 && m.Groups[1].Success ? m.Groups[1].Value : m.Value;
            return ParseNumericSegments(cap);
        }

        private static bool TryGetBracketBuildNumbers(string cleanVer, out long[] brNums)
        {
            brNums = new long[0];
            if (string.IsNullOrEmpty(cleanVer)) return false;
            Match m = _rxBracketBuildVer.Match(cleanVer);
            if (!m.Success) return false;
            brNums = ParseNumericSegments(m.Groups[1].Value);
            return brNums.Length >= 2 && brNums.Length <= 3 && brNums[0] >= 1000;
        }

        public static int CompareAppVersions(string verA, string verB)
        {
            long[] a = GetVersionNumbers(verA);
            long[] b = GetVersionNumbers(verB);
            if (a.Length == 0 && b.Length == 0) return 0;
            if (a.Length > 0 && b.Length == 0) return 1;
            if (a.Length == 0 && b.Length > 0) return -1;

            long[] brA, brB;
            bool isBrA = TryGetBracketBuildNumbers(StripBuildMetadata(verA), out brA);
            bool isBrB = TryGetBracketBuildNumbers(StripBuildMetadata(verB), out brB);
            if (isBrA != isBrB)
            {
                long[] br = isBrA ? brA : brB;
                long[] full = isBrA ? b : a;
                if (full.Length > 0 && full[0] < 1000)
                {
                    int cmpFullVsBr = 0;
                    if (full.Length >= 3 && full[2] >= 1000)
                    {
                        int tailLen = full.Length - 2;
                        int maxSeg = Math.Max(tailLen, br.Length);
                        for (int i = 0; i < maxSeg; i++)
                        {
                            long fv = i < tailLen ? full[2 + i] : 0L;
                            long bv = i < br.Length ? br[i] : 0L;
                            if (fv > bv) { cmpFullVsBr = 1; break; }
                            if (fv < bv) { cmpFullVsBr = -1; break; }
                        }
                    }
                    else
                    {
                        cmpFullVsBr = 1;
                    }
                    return isBrA ? -cmpFullVsBr : cmpFullVsBr;
                }
            }
            int maxLen = Math.Max(a.Length, b.Length);
            for (int i = 0; i < maxLen; i++)
            {
                long va = i < a.Length ? a[i] : 0L;
                long vb = i < b.Length ? b[i] : 0L;
                if (va > vb) return 1;
                if (va < vb) return -1;
            }
            long[] preNumsA, preNumsB;
            int sufA, sufB;
            int rankA = GetPrereleaseRankAndNumbers(verA, out preNumsA, out sufA);
            int rankB = GetPrereleaseRankAndNumbers(verB, out preNumsB, out sufB);
            if (rankA > rankB) return 1;
            if (rankA < rankB) return -1;
            if (rankA < 100)
            {
                int maxPre = Math.Max(preNumsA.Length, preNumsB.Length);
                for (int i = 0; i < maxPre; i++)
                {
                    long pa = i < preNumsA.Length ? preNumsA[i] : 0L;
                    long pb = i < preNumsB.Length ? preNumsB[i] : 0L;
                    if (pa > pb) return 1;
                    if (pa < pb) return -1;
                }
            }
            if (sufA > sufB) return 1;
            if (sufA < sufB) return -1;
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
            if (string.IsNullOrWhiteSpace(installedVer)) return false;
            string iv = installedVer.Trim();
            if (iv.Equals("Unknown", StringComparison.OrdinalIgnoreCase) || iv.Equals("Installed", StringComparison.OrdinalIgnoreCase)) return false;
            bool hasIvDigit = false;
            foreach (char c in iv) { if (c >= '0' && c <= '9') { hasIvDigit = true; break; } }
            if (!hasIvDigit) return false;
            int cmp = CompareAppVersions(av, iv);
            if (iv.StartsWith("<")) return cmp >= 0;
            return cmp > 0;
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

        private static int FindNextColumnStartOrEnd(string line, int pos, int maxEnd)
        {
            int limit = (maxEnd > pos && maxEnd <= line.Length) ? maxEnd : line.Length;
            if (pos < 0 || pos >= limit) return limit;
            if (char.IsWhiteSpace(line[pos]) || (pos > 0 && char.IsWhiteSpace(line[pos - 1]))) return pos;
            int j = pos;
            while (j < limit && !char.IsWhiteSpace(line[j])) j++;
            while (j < limit && char.IsWhiteSpace(line[j])) j++;
            return j;
        }

        private static void SplitTailAvailAndSource(string tail, out string avail, out string src)
        {
            avail = "";
            src = "";
            if (string.IsNullOrWhiteSpace(tail)) return;
            string t = tail.Trim();
            if (IsWingetSourceToken(t))
            {
                src = t;
                return;
            }
            int lastSpace = -1;
            for (int i = t.Length - 1; i >= 0; i--)
            {
                if (char.IsWhiteSpace(t[i])) { lastSpace = i; break; }
            }
            if (lastSpace > 0)
            {
                string lastTok = t.Substring(lastSpace + 1).Trim();
                if (IsWingetSourceToken(lastTok))
                {
                    src = lastTok;
                    avail = t.Substring(0, lastSpace).Trim();
                    return;
                }
            }
            avail = t;
        }

        private static string[] SliceRowColumnsByPositions(string line, int cId, int cVer, int cAvail, int cSrc)
        {
            string appName = "", appId = "", version = "", avail = "", src = "";
            if (cId > 0 && line.Length > cId)
            {
                cId = SnapWingetColumnBoundary(line, cId, 0);
                appName = line.Substring(0, cId).Trim();
                if (cVer > cId && line.Length > cVer)
                {
                    cVer = SnapWingetColumnBoundary(line, cVer, cId);
                    if (cVer > cId && cVer < line.Length && !char.IsWhiteSpace(line[cVer]) && !char.IsWhiteSpace(line[cVer - 1]))
                    {
                        cVer = FindNextColumnStartOrEnd(line, cVer, line.Length);
                    }
                    appId = (cVer < line.Length) ? line.Substring(cId, cVer - cId).Trim() : line.Substring(cId).Trim();
                    if (cVer < line.Length)
                    {
                        if (cAvail > cVer && line.Length > cAvail)
                        {
                            // Never cut a contiguous Version token at cAvail; advance past any overflowing Version token
                            int availStart = FindNextColumnStartOrEnd(line, cAvail, line.Length);
                            if (availStart <= cVer) availStart = cAvail;
                            if (availStart < line.Length)
                            {
                                string verSlice = line.Substring(cVer, availStart - cVer).Trim();
                                if (verSlice == "<" || verSlice == ">")
                                {
                                    while (availStart < line.Length && char.IsWhiteSpace(line[availStart])) availStart++;
                                    availStart = FindNextColumnStartOrEnd(line, availStart, line.Length);
                                }
                            }
                            if (availStart >= line.Length)
                            {
                                version = line.Substring(cVer).Trim();
                            }
                            else
                            {
                                version = line.Substring(cVer, availStart - cVer).Trim();
                                if (cSrc > availStart && line.Length > cSrc)
                                {
                                    int srcStart = FindNextColumnStartOrEnd(line, cSrc, line.Length);
                                    avail = line.Substring(availStart, srcStart - availStart).Trim();
                                    if (srcStart < line.Length) src = line.Substring(srcStart).Trim();
                                }
                                else if (cSrc > 0 && cSrc <= availStart && line.Length > availStart)
                                {
                                    SplitTailAvailAndSource(line.Substring(availStart), out avail, out src);
                                }
                                else
                                {
                                    avail = line.Substring(availStart).Trim();
                                }
                            }
                        }
                        else if (cAvail > 0 && cVer >= cAvail)
                        {
                            // Id overflowed past cAvail: slice Version cleanly first, then split remaining Available/Source
                            int verEnd = cVer;
                            while (verEnd < line.Length && !char.IsWhiteSpace(line[verEnd])) verEnd++;
                            string tok = line.Substring(cVer, verEnd - cVer);
                            if ((tok == "<" || tok == ">") && verEnd < line.Length)
                            {
                                int p = verEnd;
                                while (p < line.Length && char.IsWhiteSpace(line[p])) p++;
                                while (p < line.Length && !char.IsWhiteSpace(line[p])) p++;
                                verEnd = p;
                            }
                            version = line.Substring(cVer, verEnd - cVer).Trim();
                            int availStart = verEnd;
                            while (availStart < line.Length && char.IsWhiteSpace(line[availStart])) availStart++;
                            if (availStart < line.Length)
                            {
                                string tail = line.Substring(availStart).Trim();
                                if (cSrc > 0) SplitTailAvailAndSource(tail, out avail, out src);
                                else avail = tail;
                            }
                        }
                        else
                        {
                            version = line.Substring(cVer).Trim();
                        }
                    }
                }
                else
                {
                    appId = line.Substring(cId).Trim();
                }
            }
            return new string[] { appName, appId, version, avail, src };
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

        private static string ResolveWingetRowSource(string appId, string srcCol)
        {
            if (!string.IsNullOrWhiteSpace(srcCol))
            {
                string s = srcCol.Trim();
                if (s.Equals("msstore", StringComparison.OrdinalIgnoreCase)) return "msstore";
                return "winget";
            }
            if (!string.IsNullOrWhiteSpace(appId) &&
                (appId.StartsWith("ARP\\", StringComparison.OrdinalIgnoreCase) || appId.StartsWith("MSIX\\", StringComparison.OrdinalIgnoreCase)))
            {
                return "local";
            }
            return "winget";
        }

        private static bool IsWingetSourceToken(string tok)
        {
            if (string.IsNullOrWhiteSpace(tok)) return false;
            return tok.Equals("winget", StringComparison.OrdinalIgnoreCase) ||
                   tok.Equals("msstore", StringComparison.OrdinalIgnoreCase);
        }

        private static readonly HashSet<string> _wingetHeaderTokens = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Name", "Id", "Version", "Available", "Source", "Match", "Tag", "Command", "Moniker"
        };

        private static List<int> ParseWingetHeaderOffsets(string headerLine)
        {
            var offsets = new List<int>();
            if (string.IsNullOrEmpty(headerLine)) return offsets;

            MatchCollection singleTokens = Regex.Matches(headerLine, @"\S+");
            if (singleTokens.Count >= 3)
            {
                bool allKnown = true;
                for (int i = 0; i < singleTokens.Count; i++)
                {
                    if (!_wingetHeaderTokens.Contains(singleTokens[i].Value))
                    {
                        allKnown = false;
                        break;
                    }
                }
                if (allKnown)
                {
                    for (int i = 0; i < singleTokens.Count; i++)
                    {
                        offsets.Add(GetDisplayWidthUpToIndex(headerLine, singleTokens[i].Index));
                    }
                    return offsets;
                }
            }

            MatchCollection groupedMatches = Regex.Matches(headerLine, @"\S+(\s\S+)*");
            for (int i = 0; i < groupedMatches.Count; i++)
            {
                Match gm = groupedMatches[i];
                MatchCollection subTokens = Regex.Matches(gm.Value, @"\S+");
                for (int j = 0; j < subTokens.Count; j++)
                {
                    if (j == 0 ||
                        _wingetHeaderTokens.Contains(subTokens[j].Value) ||
                        _wingetHeaderTokens.Contains(subTokens[j - 1].Value))
                    {
                        offsets.Add(GetDisplayWidthUpToIndex(headerLine, gm.Index + subTokens[j].Index));
                    }
                }
            }

            if (offsets.Count < 3 && singleTokens.Count >= 3)
            {
                offsets.Clear();
                for (int i = 0; i < singleTokens.Count; i++)
                {
                    offsets.Add(GetDisplayWidthUpToIndex(headerLine, singleTokens[i].Index));
                }
            }
            return offsets;
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
                    colOffsetsList = ParseWingetHeaderOffsets(headerLine);
                }
                int[] colOffsets = colOffsetsList.ToArray();

                for (int i = separatorIndex + 1; i < lines.Count; i++)
                {
                    string line = lines[i];
                    if (string.IsNullOrWhiteSpace(line)) continue;
                    string appName = "", appId = "", version = "", avail = "", srcCol = "";

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
                            srcCol = sliced.Length >= 5 ? sliced[4] : "";
                        }
                        else
                        {
                            string[] sliced = SliceByDisplayWidth(line, colOffsets);
                            appName = sliced[0];
                            appId = sliced[1];
                            version = sliced[2];
                            avail = sliced[3];
                            srcCol = sliced.Length >= 5 ? sliced[4] : "";
                        }
                    }

                    if (string.IsNullOrEmpty(appId) || appId.IndexOf(' ') >= 0)
                    {
                        string[] tailCols = null;
                        if (!string.IsNullOrEmpty(appName) && colOffsets.Length >= 3)
                        {
                            int nameEnd = line.IndexOf(appName, StringComparison.Ordinal);
                            int searchFrom = (nameEnd >= 0) ? (nameEnd + appName.Length) : 0;
                            while (searchFrom < line.Length && char.IsWhiteSpace(line[searchFrom])) searchFrom++;
                            if (searchFrom < line.Length)
                            {
                                string[] tCols = Regex.Split(line.Substring(searchFrom).Trim(), @"\s{2,}");
                                if (tCols.Length >= 1 && !string.IsNullOrWhiteSpace(tCols[0]))
                                {
                                    tailCols = tCols;
                                }
                            }
                        }
                        if (tailCols != null)
                        {
                            appId = tailCols[0].Trim();
                            version = tailCols.Length >= 2 ? tailCols[1].Trim() : "";
                            string c3 = tailCols.Length >= 3 ? tailCols[2].Trim() : "";
                            string c4 = tailCols.Length >= 4 ? tailCols[3].Trim() : "";
                            if (IsWingetSourceToken(c3) && string.IsNullOrEmpty(c4))
                            {
                                srcCol = c3;
                                avail = "";
                            }
                            else
                            {
                                avail = c3;
                                if (!string.IsNullOrEmpty(c4)) srcCol = c4;
                            }
                        }
                        else
                        {
                            string[] cols = Regex.Split(line.Trim(), @"\s{2,}");
                            if (cols.Length >= 2)
                            {
                                appName = cols[0].Trim();
                                appId = cols[1].Trim();
                                version = cols.Length >= 3 ? cols[2].Trim() : "";
                                string c3 = cols.Length >= 4 ? cols[3].Trim() : "";
                                string c4 = cols.Length >= 5 ? cols[4].Trim() : "";
                                if (IsWingetSourceToken(c3) && string.IsNullOrEmpty(c4))
                                {
                                    srcCol = c3;
                                    avail = "";
                                }
                                else
                                {
                                    avail = c3;
                                    if (!string.IsNullOrEmpty(c4)) srcCol = c4;
                                }
                            }
                        }
                    }

                    if (!string.IsNullOrEmpty(appName) && !string.IsNullOrEmpty(appId))
                    {
                        if (appId.StartsWith("MSIX\\NotepadPlusPlus_", StringComparison.OrdinalIgnoreCase)) continue;
                        if (IsWingetSourceToken(avail)) { srcCol = avail; avail = ""; }
                        bool hasUpdate = TestAppUpdateGenuine(version, avail);
                        string rowSrc = (colOffsets.Length < 5 && string.IsNullOrEmpty(srcCol)) ? "winget" : ResolveWingetRowSource(appId, srcCol);
                        parsed.Add(new CatalogSensorItem
                        {
                            Name = appName,
                            ID = appId,
                            Version = version,
                            Available = hasUpdate ? avail : "",
                            HasUpdate = hasUpdate,
                            CleanName = CleanCatalogAppName(appName),
                            Source = rowSrc
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
                        if (appId.StartsWith("MSIX\\NotepadPlusPlus_", StringComparison.OrdinalIgnoreCase)) continue;
                        string version = cols.Length >= 3 ? cols[2].Trim() : "";
                        string c3 = cols.Length >= 4 ? cols[3].Trim() : "";
                        string c4 = cols.Length >= 5 ? cols[4].Trim() : "";
                        string avail = IsWingetSourceToken(c3) ? "" : c3;
                        string srcCol = IsWingetSourceToken(c3) ? c3 : c4;
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
                                Source = ResolveWingetRowSource(appId, srcCol)
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

                if (string.Equals(toolKey, "agy", StringComparison.OrdinalIgnoreCase))
                {
                    string exeDir = Path.GetDirectoryName(exePath);
                    string localVerJson = !string.IsNullOrEmpty(exeDir) ? Path.Combine(exeDir, "agy.version.json") : "";
                    string agyVerJson = (!string.IsNullOrEmpty(localVerJson) && File.Exists(localVerJson))
                        ? localVerJson
                        : (!string.IsNullOrEmpty(userProf) ? Path.Combine(userProf, @".gemini\bin\agy.version.json") : "");
                    if (!string.IsNullOrEmpty(agyVerJson) && File.Exists(agyVerJson))
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

        private static string NormalizeRegistryDisplayVersion(string displayName, string displayVersion)
        {
            if (string.IsNullOrWhiteSpace(displayName) || string.IsNullOrWhiteSpace(displayVersion)) return displayVersion;
            if (displayName.StartsWith("Python ", StringComparison.OrdinalIgnoreCase) &&
                Regex.IsMatch(displayVersion, @"^\d+\.\d+\.\d{4,}(?:\.\d+)?$"))
            {
                Match mPy = Regex.Match(displayName, @"^Python\s+(\d+\.\d+\.\d+(?:\.\d+)?)\b", RegexOptions.IgnoreCase);
                if (mPy.Success) return mPy.Groups[1].Value;
            }
            if ((displayName.IndexOf("Windows Desktop Runtime", StringComparison.OrdinalIgnoreCase) >= 0 ||
                 displayName.IndexOf(".NET SDK", StringComparison.OrdinalIgnoreCase) >= 0) &&
                Regex.IsMatch(displayVersion, @"^\d+\.\d+\.\d+"))
            {
                long[] dvNums = GetVersionNumbers(displayVersion);
                Match mDn = Regex.Match(displayName, @"\b(\d+\.\d+\.\d+(?:\.\d+)?)\b");
                if (mDn.Success && dvNums.Length > 0 && dvNums[0] >= 24)
                {
                    long[] dnNums = GetVersionNumbers(mDn.Groups[1].Value);
                    if (dnNums.Length > 0 && dnNums[0] <= 20) return mDn.Groups[1].Value;
                }
            }
            return displayVersion;
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
            var seenUserKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

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
                                if (rt.Item1 == RegistryHive.CurrentUser && !seenUserKeys.Add(subName)) continue;
                                using (var sk = uninst.OpenSubKey(subName))
                                {
                                    if (sk == null) continue;
                                    string parentKey = sk.GetValue("ParentKeyName") as string;
                                    if (!string.IsNullOrEmpty(parentKey)) continue;

                                    string relType = (sk.GetValue("ReleaseType") as string ?? "").Trim();
                                    if (!string.IsNullOrEmpty(relType) && Regex.IsMatch(relType, @"Update|Hotfix", RegexOptions.IgnoreCase)) continue;

                                    string dn = (sk.GetValue("DisplayName") as string ?? "").Trim();
                                    if (string.IsNullOrEmpty(dn)) continue;

                                    var sysComp = sk.GetValue("SystemComponent");
                                    if (sysComp != null && (sysComp.ToString() == "1" || ((sysComp is int) && ((int)sysComp == 1))))
                                    {
                                        if (dn.IndexOf("Visual Studio Community", StringComparison.OrdinalIgnoreCase) < 0 &&
                                            dn.IndexOf("Visual Studio Professional", StringComparison.OrdinalIgnoreCase) < 0 &&
                                            dn.IndexOf("Visual Studio Enterprise", StringComparison.OrdinalIgnoreCase) < 0 &&
                                            dn.IndexOf("Visual Studio Build Tools", StringComparison.OrdinalIgnoreCase) < 0 &&
                                            dn.IndexOf("Visual Studio Code", StringComparison.OrdinalIgnoreCase) < 0 &&
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

                                    string rawVer = (sk.GetValue("DisplayVersion") as string ?? "Installed").Trim();
                                    if (string.IsNullOrEmpty(rawVer)) rawVer = "Installed";
                                    string ver = NormalizeRegistryDisplayVersion(dn, rawVer);
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

                                    if (dn.IndexOf("Visual Studio Community 2022", StringComparison.OrdinalIgnoreCase) >= 0)
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
                            Match mMsixVer = Regex.Match(pkgFull, @"_(\d+(?:\.\d+){1,3})_");
                            string pkgVer = mMsixVer.Success ? mMsixVer.Groups[1].Value : (parts.Length > 1 ? parts[1] : "Installed");
                            if (mMsixVer.Success && mMsixVer.Index > 0) pkgPrefix = pkgFull.Substring(0, mMsixVer.Index);
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

        public class UpgradeGuardSnapshotResult
        {
            public bool HasSnapshots { get; set; }
            public string[] CopiedAppDataDirs { get; set; }
            public string[] CopiedAppDataBackups { get; set; }
            public int[] ExportedRegIndices { get; set; }
        }

        public class UpgradeGuardRestoreResult
        {
            public int RestoredLocFiles { get; set; }
            public int[] RestoredAppDataCounts { get; set; }
            public int[] RestoredRegIndices { get; set; }
        }

        public static Task<UpgradeGuardSnapshotResult> UpgradeGuardSnapshotAsync(
            string backupRoot,
            string existingLoc,
            string locBkp,
            bool canSnapshotLoc,
            string[] appDataDirs,
            string[] appDataBkps,
            string[] hkcuRawKeys,
            string[] regFiles,
            long maxBytes)
        {
            return Task.Run(delegate()
            {
                var res = new UpgradeGuardSnapshotResult();
                var copiedDirs = new List<string>();
                var copiedBkps = new List<string>();
                var exportedIdx = new List<int>();
                bool hasAny = false;

                try
                {
                    if (!string.IsNullOrWhiteSpace(backupRoot))
                    {
                        if (Directory.Exists(backupRoot))
                        {
                            try { Directory.Delete(backupRoot, true); } catch {}
                        }
                        Directory.CreateDirectory(backupRoot);
                    }

                    if (canSnapshotLoc && !string.IsNullOrWhiteSpace(existingLoc) && !string.IsNullOrWhiteSpace(locBkp))
                    {
                        long bLoc = BackupDirectorySnapshot(existingLoc, locBkp, maxBytes, true);
                        if (bLoc > 0) hasAny = true;
                    }

                    if (appDataDirs != null && appDataBkps != null)
                    {
                        int nAd = Math.Min(appDataDirs.Length, appDataBkps.Length);
                        for (int i = 0; i < nAd; i++)
                        {
                            string adDir = appDataDirs[i];
                            string adBkp = appDataBkps[i];
                            if (string.IsNullOrWhiteSpace(adDir) || string.IsNullOrWhiteSpace(adBkp)) continue;
                            long bAd = BackupDirectorySnapshot(adDir, adBkp, maxBytes, false);
                            if (bAd > 0)
                            {
                                hasAny = true;
                                copiedDirs.Add(adDir);
                                copiedBkps.Add(adBkp);
                            }
                        }
                    }

                    if (hkcuRawKeys != null && regFiles != null)
                    {
                        int nReg = Math.Min(hkcuRawKeys.Length, regFiles.Length);
                        for (int i = 0; i < nReg; i++)
                        {
                            string rawKey = hkcuRawKeys[i];
                            string regFile = regFiles[i];
                            if (string.IsNullOrWhiteSpace(rawKey) || string.IsNullOrWhiteSpace(regFile)) continue;
                            try
                            {
                                var psi = new ProcessStartInfo();
                                psi.FileName = "reg.exe";
                                psi.Arguments = "export \"" + rawKey + "\" \"" + regFile + "\" /y";
                                psi.CreateNoWindow = true;
                                psi.UseShellExecute = false;
                                using (Process p = Process.Start(psi))
                                {
                                    if (p != null && p.WaitForExit(10000) && p.ExitCode == 0 && File.Exists(regFile))
                                    {
                                        hasAny = true;
                                        exportedIdx.Add(i);
                                    }
                                }
                            }
                            catch {}
                        }
                    }
                }
                catch {}

                res.HasSnapshots = hasAny;
                res.CopiedAppDataDirs = copiedDirs.ToArray();
                res.CopiedAppDataBackups = copiedBkps.ToArray();
                res.ExportedRegIndices = exportedIdx.ToArray();
                return res;
            });
        }

        public static Task<UpgradeGuardRestoreResult> UpgradeGuardRestoreAsync(
            string backupRoot,
            bool shouldRestore,
            string existingLoc,
            string locBkp,
            bool canSnapshotLoc,
            string[] appDataDirs,
            string[] appDataBkps,
            string[] regFilesToImport,
            int[] regImportIndices)
        {
            return Task.Run(delegate()
            {
                var res = new UpgradeGuardRestoreResult();
                var adCounts = new List<int>();
                var impDone = new List<int>();

                try
                {
                    if (shouldRestore)
                    {
                        if (canSnapshotLoc && !string.IsNullOrWhiteSpace(locBkp) && !string.IsNullOrWhiteSpace(existingLoc) && Directory.Exists(locBkp))
                        {
                            res.RestoredLocFiles = RestoreDirectorySnapshot(locBkp, existingLoc);
                        }

                        if (appDataDirs != null && appDataBkps != null)
                        {
                            int nAd = Math.Min(appDataDirs.Length, appDataBkps.Length);
                            for (int i = 0; i < nAd; i++)
                            {
                                int cnt = 0;
                                if (!string.IsNullOrWhiteSpace(appDataBkps[i]) && !string.IsNullOrWhiteSpace(appDataDirs[i]) && Directory.Exists(appDataBkps[i]))
                                {
                                    cnt = RestoreDirectorySnapshot(appDataBkps[i], appDataDirs[i]);
                                }
                                adCounts.Add(cnt);
                            }
                        }

                        if (regFilesToImport != null && regImportIndices != null)
                        {
                            int nImp = Math.Min(regFilesToImport.Length, regImportIndices.Length);
                            for (int i = 0; i < nImp; i++)
                            {
                                string rf = regFilesToImport[i];
                                if (string.IsNullOrWhiteSpace(rf) || !File.Exists(rf)) continue;
                                try
                                {
                                    var psi = new ProcessStartInfo();
                                    psi.FileName = "reg.exe";
                                    psi.Arguments = "import \"" + rf + "\"";
                                    psi.CreateNoWindow = true;
                                    psi.UseShellExecute = false;
                                    using (Process p = Process.Start(psi))
                                    {
                                        if (p != null && p.WaitForExit(10000) && p.ExitCode == 0)
                                        {
                                            impDone.Add(regImportIndices[i]);
                                        }
                                    }
                                }
                                catch {}
                            }
                        }
                    }

                    if (!string.IsNullOrWhiteSpace(backupRoot) && Directory.Exists(backupRoot))
                    {
                        try { Directory.Delete(backupRoot, true); } catch {}
                    }
                }
                catch {}

                res.RestoredAppDataCounts = adCounts.ToArray();
                res.RestoredRegIndices = impDone.ToArray();
                return res;
            });
        }

        public static Task<List<CatalogSensorItem>> ScanCatalogSensorsAsync()
        {
            return Task.Run(delegate() { return ScanCatalogSensors(); });
        }

        private sealed class AliasPatternPair
        {
            public string Raw;
            public string Clean;
            public string Compact;
            public Regex Pattern;
        }

        private sealed class CompiledTargetMeta
        {
            public string ID;
            public string Name;
            public string CleanTarget;
            public string CompactTarget;
            public string PublisherPrefix;
            public string SecondSegment;
            public bool HasThreePlusIdParts;
            public HashSet<string> AliasIdSet;
            public List<AliasPatternPair> CleanAliases;
            public List<AliasPatternPair> AliasEntries;
            public Regex PatternClean;
            public List<string> QueryTokens;
            public HashSet<string> TargetTokenSet;
            public bool AllowNoise;
            public bool IsPrev;
            public bool IsBeta;
            public bool IsCanary;
            public bool IsDevChannel;
            public bool IsNightly;
            public bool IsAlpha;
            public bool IsPtb;
            public bool IsEsr;
            public bool IsInsiders;
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
                "microsoft", "windows", "google", "runtime", "desktop", "client", "server",
                "edition", "community", "x64", "x86", "arm64", "arp", "msix", "machine", "user",
                "app", "pro", "jdk", "jre", "lts", "cli", "ide", "gui", "vpn", "bit"
            }, StringComparer.OrdinalIgnoreCase);

        private static readonly Regex _rxTokSplit = new Regex(@"[^a-zA-Z0-9+]+", RegexOptions.Compiled);
        private static readonly Regex _rxSyntheticId = new Regex(@"^(ARP|MSIX|LOCAL)\\", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxAllowNoise = new Regex(@"(Maintenance|Control Panel|Context Menu|AddOn|Installer|Agent)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxNoiseName = new Regex(@"(Maintenance Service|Control Panels|Context Menu|SparseApp|SDK AddOn|CoreEditorFonts|Visual Studio Installer|Development Libraries|Standard Library|Test Suite|Tcl/Tk Support|pip Bootstrap)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxNoiseId = new Regex(@"(MozillaMaintenanceService|ContextMenu|SparseApp|FigmaAgent|NotepadPlusPlus_)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
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
        private static readonly Regex _rxWordBeta = new Regex(@"\bBeta\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxDotBeta = new Regex(@"\.Beta(?:\.|$)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxWordCanary = new Regex(@"\bCanary\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxDotCanary = new Regex(@"\.Canary(?:\.|$)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxWordDevCh = new Regex(@"\b(?:Dev|Developer\s*Edition)\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxDotDevCh = new Regex(@"\.(?:Dev|DeveloperEdition)(?:\.|$)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxWordNightly = new Regex(@"\bNightly\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxDotNightly = new Regex(@"\.Nightly(?:\.|$)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxWordAlpha = new Regex(@"\bAlpha\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxDotAlpha = new Regex(@"\.Alpha(?:\.|$)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxWordPtb = new Regex(@"\bPTB\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxDotPtb = new Regex(@"\.PTB(?:\.|$)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxWordEsr = new Regex(@"\bESR\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxDotEsr = new Regex(@"\.ESR(?:\.|$)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxWordInsiders = new Regex(@"\bInsiders?\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxDotInsiders = new Regex(@"\.Insiders?(?:\.|$)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
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
            string tNameNoParens = _rxCleanParens.Replace(tName, "").Trim();
            string tCat = target.Category ?? "";
            string cleanTarget = CleanCatalogAppName(tName);

            var cleanAliases = new List<AliasPatternPair>();
            var aliasEntries = new List<AliasPatternPair>();
            var queryTokens = new List<string>();
            var seenTokens = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var targetTokenSet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var aliasIdSet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (!string.IsNullOrWhiteSpace(tId)) aliasIdSet.Add(tId);

            if (cleanTarget.Length >= 4)
            {
                string[] toks = _rxTokSplit.Split(cleanTarget);
                for (int i = 0; i < toks.Length; i++)
                {
                    string qt = toks[i];
                    if (qt.Length >= 2 && !_matchStopWords.Contains(qt))
                    {
                        if ((qt.Length >= 3 || string.Equals(qt, "7z", StringComparison.OrdinalIgnoreCase)) && seenTokens.Add(qt))
                        {
                            queryTokens.Add(qt);
                        }
                        targetTokenSet.Add(qt);
                    }
                }
            }

            if (target.Aliases != null)
            {
                for (int ai = 0; ai < target.Aliases.Length; ai++)
                {
                    string alias = target.Aliases[ai];
                    if (string.IsNullOrWhiteSpace(alias)) continue;
                    if (alias.IndexOf('.') >= 0 || Regex.IsMatch(alias, @"^9[A-Z0-9]{11}$")) aliasIdSet.Add(alias);
                    string cAl = CleanCatalogAppName(alias);
                    string cmpAl = CompactAlnumKey(cAl.Length > 0 ? cAl : alias);
                    var pair = new AliasPatternPair { Raw = alias, Clean = cAl, Compact = cmpAl, Pattern = null };
                    cleanAliases.Add(pair);
                    if (alias.Length >= 4)
                    {
                        pair.Pattern = new Regex(@"(?<![a-zA-Z0-9])" + Regex.Escape(alias) + @"(?![a-zA-Z0-9])", RegexOptions.IgnoreCase);
                        aliasEntries.Add(pair);
                        string[] toks = _rxTokSplit.Split(alias);
                        for (int i = 0; i < toks.Length; i++)
                        {
                            string qt = toks[i];
                            if ((qt.Length >= 3 || string.Equals(qt, "7z", StringComparison.OrdinalIgnoreCase)) && !_matchStopWords.Contains(qt) && seenTokens.Add(qt))
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
            string compactTarget = CompactAlnumKey(cleanTarget);
            if (compactTarget.Length >= 4 && seenTokens.Add(compactTarget))
            {
                queryTokens.Add(compactTarget);
            }

            string[] idSegs = tId.Split('.');
            string pubPref = idSegs.Length >= 2 ? idSegs[0] : "";
            string secSeg = idSegs.Length >= 2 ? idSegs[1] : "";
            bool hasThreePlus = idSegs.Length >= 3;

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
                CompactTarget = compactTarget,
                PublisherPrefix = pubPref,
                SecondSegment = secSeg,
                HasThreePlusIdParts = hasThreePlus,
                AliasIdSet = aliasIdSet,
                CleanAliases = cleanAliases,
                AliasEntries = aliasEntries,
                PatternClean = patternClean,
                QueryTokens = queryTokens,
                TargetTokenSet = targetTokenSet,
                AllowNoise = _rxAllowNoise.IsMatch(tName),
                // Strip parenthetical UI notes (e.g. "QuickLook (Space Preview)", "aria2 (Multi-Protocol CLI)") before inferring channel/CLI flags
                IsPrev = (tNameNoParens.IndexOf("Preview", StringComparison.OrdinalIgnoreCase) >= 0) || (tId.IndexOf("Preview", StringComparison.OrdinalIgnoreCase) >= 0),
                IsBeta = _rxWordBeta.IsMatch(tNameNoParens) || _rxDotBeta.IsMatch(tId),
                IsCanary = _rxWordCanary.IsMatch(tNameNoParens) || _rxDotCanary.IsMatch(tId),
                IsDevChannel = _rxWordDevCh.IsMatch(tNameNoParens) || _rxDotDevCh.IsMatch(tId),
                IsNightly = _rxWordNightly.IsMatch(tNameNoParens) || _rxDotNightly.IsMatch(tId),
                IsAlpha = _rxWordAlpha.IsMatch(tNameNoParens) || _rxDotAlpha.IsMatch(tId),
                IsPtb = _rxWordPtb.IsMatch(tNameNoParens) || _rxDotPtb.IsMatch(tId),
                IsEsr = _rxWordEsr.IsMatch(tNameNoParens) || _rxDotEsr.IsMatch(tId),
                IsInsiders = _rxWordInsiders.IsMatch(tNameNoParens) || _rxDotInsiders.IsMatch(tId),
                IsVcRedist = (tId.IndexOf("VCRedist", StringComparison.OrdinalIgnoreCase) >= 0) || (tName.IndexOf("VC++", StringComparison.OrdinalIgnoreCase) >= 0),
                IsComm = _rxWordComm.IsMatch(tNameNoParens) || _rxDotComm.IsMatch(tId),
                IsPro = _rxWordPro.IsMatch(tNameNoParens) || _rxDotPro.IsMatch(tId),
                IsIde = _rxWordIde.IsMatch(tNameNoParens) || _rxEndIde.IsMatch(tId),
                IsAntigravity = tId.IndexOf("Antigravity", StringComparison.OrdinalIgnoreCase) >= 0,
                IsCli = _rxWordCli.IsMatch(tNameNoParens) || _rxEndCli.IsMatch(tId),
                IsBt = (tNameNoParens.IndexOf("Build Tools", StringComparison.OrdinalIgnoreCase) >= 0) || (tId.IndexOf("BuildTools", StringComparison.OrdinalIgnoreCase) >= 0),
                IsVsc = (tId.IndexOf("VisualStudioCode", StringComparison.OrdinalIgnoreCase) >= 0) || _rxVscName.IsMatch(tNameNoParens),
                IsVsAny = tId.IndexOf("VisualStudio", StringComparison.OrdinalIgnoreCase) >= 0,
                IsEtb = (tId.IndexOf("EverythingToolbar", StringComparison.OrdinalIgnoreCase) >= 0) || (tNameNoParens.IndexOf("EverythingToolbar", StringComparison.OrdinalIgnoreCase) >= 0),
                IsTemurin = tId.IndexOf("Temurin", StringComparison.OrdinalIgnoreCase) >= 0,
                IsOracleJava = tId.IndexOf("Oracle.Java", StringComparison.OrdinalIgnoreCase) >= 0,
                IsCorretto = tId.IndexOf("Corretto", StringComparison.OrdinalIgnoreCase) >= 0,
                IsJdk = _rxWordJdk.IsMatch(tNameNoParens) || _rxEndJdk.IsMatch(tId),
                IsJre = _rxWordJre.IsMatch(tNameNoParens) || _rxEndJre.IsMatch(tId),
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
            string iNameNoParens = _rxCleanParens.Replace(iName, "").Trim();
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

            bool iPrev = (iNameNoParens.IndexOf("Preview", StringComparison.OrdinalIgnoreCase) >= 0) || (iId.IndexOf("Preview", StringComparison.OrdinalIgnoreCase) >= 0);
            if (meta.IsPrev != iPrev && !string.Equals(tId, "Microsoft.PowerToys", StringComparison.OrdinalIgnoreCase)) return false;

            if (meta.IsBeta != (_rxWordBeta.IsMatch(iNameNoParens) || _rxDotBeta.IsMatch(iId))) return false;
            if (meta.IsCanary != (_rxWordCanary.IsMatch(iNameNoParens) || _rxDotCanary.IsMatch(iId))) return false;
            if (meta.IsDevChannel != (_rxWordDevCh.IsMatch(iNameNoParens) || _rxDotDevCh.IsMatch(iId))) return false;
            if (meta.IsNightly != (_rxWordNightly.IsMatch(iNameNoParens) || _rxDotNightly.IsMatch(iId))) return false;
            if (meta.IsAlpha != (_rxWordAlpha.IsMatch(iNameNoParens) || _rxDotAlpha.IsMatch(iId))) return false;
            if (meta.IsPtb != (_rxWordPtb.IsMatch(iNameNoParens) || _rxDotPtb.IsMatch(iId))) return false;
            if (meta.IsEsr != (_rxWordEsr.IsMatch(iNameNoParens) || _rxDotEsr.IsMatch(iId))) return false;
            if (meta.IsInsiders != (_rxWordInsiders.IsMatch(iNameNoParens) || _rxDotInsiders.IsMatch(iId))) return false;

            if (!_rxSyntheticId.IsMatch(iId) && !meta.AliasIdSet.Contains(iId) && !iId.StartsWith(tId + ".", StringComparison.OrdinalIgnoreCase))
            {
                if (string.Equals(tId, "OpenJS.NodeJS.LTS", StringComparison.OrdinalIgnoreCase) &&
                    iId.StartsWith("OpenJS.NodeJS", StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }
                if (meta.PublisherPrefix.Length >= 3 && iId.StartsWith(meta.PublisherPrefix + ".", StringComparison.OrdinalIgnoreCase))
                {
                    string[] iSegs = iId.Split('.');
                    if (iSegs.Length >= 2)
                    {
                        if (!string.Equals(iSegs[1], meta.SecondSegment, StringComparison.OrdinalIgnoreCase)) return false;
                        if (meta.HasThreePlusIdParts) return false;
                    }
                }
            }

            if (meta.IsVcRedist && (_rxWordUwp.IsMatch(iName) || iId.IndexOf("VCLibs", StringComparison.OrdinalIgnoreCase) >= 0)) return false;

            if (meta.IsComm || meta.IsPro)
            {
                bool iComm = _rxWordComm.IsMatch(iNameNoParens) || _rxDotComm.IsMatch(iId);
                bool iPro = _rxWordPro.IsMatch(iNameNoParens) || _rxDotPro.IsMatch(iId);
                if ((meta.IsComm && iPro) || (meta.IsPro && iComm)) return false;
            }

            if (meta.IsAntigravity || iId.IndexOf("Antigravity", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                bool iIde = _rxWordIde.IsMatch(iNameNoParens) || _rxEndIde.IsMatch(iId);
                if (meta.IsIde != iIde) return false;
            }

            bool iCli = _rxWordCli.IsMatch(iNameNoParens) || _rxEndCli.IsMatch(iId);
            if (meta.IsCli != iCli) return false;

            bool iBt = (iNameNoParens.IndexOf("Build Tools", StringComparison.OrdinalIgnoreCase) >= 0) || (iId.IndexOf("BuildTools", StringComparison.OrdinalIgnoreCase) >= 0);
            if (meta.IsBt != iBt) return false;

            if (meta.IsVsAny || iId.IndexOf("VisualStudio", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                bool iVsc = (iId.IndexOf("VisualStudioCode", StringComparison.OrdinalIgnoreCase) >= 0) || _rxVscName.IsMatch(iNameNoParens);
                if (meta.IsVsc != iVsc) return false;
                if (meta.IsVsAny && (meta.IsComm || meta.IsPro))
                {
                    bool iComm = _rxWordComm.IsMatch(iNameNoParens) || _rxDotComm.IsMatch(iId);
                    bool iPro = _rxWordPro.IsMatch(iNameNoParens) || _rxDotPro.IsMatch(iId);
                    if ((meta.IsComm && !iComm) || (meta.IsPro && !iPro)) return false;
                }
            }

            bool iEtb = (iId.IndexOf("EverythingToolbar", StringComparison.OrdinalIgnoreCase) >= 0) || (iNameNoParens.IndexOf("EverythingToolbar", StringComparison.OrdinalIgnoreCase) >= 0);
            if (meta.IsEtb != iEtb) return false;

            if (meta.IsTemurin && (iId.IndexOf("Oracle", StringComparison.OrdinalIgnoreCase) >= 0 || iId.IndexOf("Corretto", StringComparison.OrdinalIgnoreCase) >= 0 || iName.IndexOf("Oracle", StringComparison.OrdinalIgnoreCase) >= 0 || iName.IndexOf("Corretto", StringComparison.OrdinalIgnoreCase) >= 0 || _rxJavaUpdate.IsMatch(iName))) return false;
            if (meta.IsOracleJava && (iId.IndexOf("Temurin", StringComparison.OrdinalIgnoreCase) >= 0 || iId.IndexOf("Corretto", StringComparison.OrdinalIgnoreCase) >= 0 || iName.IndexOf("Temurin", StringComparison.OrdinalIgnoreCase) >= 0 || iName.IndexOf("Corretto", StringComparison.OrdinalIgnoreCase) >= 0 || (_rxWordJre.IsMatch(iName) && !_rxJavaUpdate.IsMatch(iName) && iName.IndexOf("Oracle", StringComparison.OrdinalIgnoreCase) < 0 && iId.IndexOf("Oracle", StringComparison.OrdinalIgnoreCase) < 0))) return false;
            if (meta.IsCorretto && (iId.IndexOf("Temurin", StringComparison.OrdinalIgnoreCase) >= 0 || iId.IndexOf("Oracle", StringComparison.OrdinalIgnoreCase) >= 0 || iName.IndexOf("Temurin", StringComparison.OrdinalIgnoreCase) >= 0 || _rxJavaUpdate.IsMatch(iName))) return false;

            if (meta.IsJdk || meta.IsJre)
            {
                bool iJdk = _rxWordJdk.IsMatch(iNameNoParens) || _rxEndJdk.IsMatch(iId);
                bool iJre = _rxWordJre.IsMatch(iNameNoParens) || _rxEndJre.IsMatch(iId);
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
                if (string.IsNullOrEmpty(iArch) && string.Equals(meta.Arch, "x86", StringComparison.OrdinalIgnoreCase)) return false;
            }

            return true;
        }

        private static bool HasNumericVersion(string ver)
        {
            if (string.IsNullOrWhiteSpace(ver)) return false;
            string v = ver.Trim();
            if (v.Equals("Installed", StringComparison.OrdinalIgnoreCase) || v.Equals("Unknown", StringComparison.OrdinalIgnoreCase)) return false;
            for (int i = 0; i < v.Length; i++)
            {
                if (v[i] >= '0' && v[i] <= '9') return true;
            }
            return false;
        }

        public static bool IsVersionAtLeastAvailable(string installedVer, string wgVer, string wgAvail)
        {
            if (!HasNumericVersion(installedVer)) return false;
            if (!HasNumericVersion(wgAvail)) return false;
            if (CompareAppVersions(installedVer, wgAvail) >= 0) return true;

            // Truncated Registry DisplayVersion (e.g. "24.09" vs WinGet Available "24.09.1" when WinGet Installed was "24.08")
            long[] locNums = GetVersionNumbers(installedVer);
            long[] availNums = GetVersionNumbers(wgAvail);
            if (locNums.Length >= 2 && locNums.Length < availNums.Length)
            {
                bool isPrefix = true;
                for (int i = 0; i < locNums.Length; i++)
                {
                    if (locNums[i] != availNums[i]) { isPrefix = false; break; }
                }
                if (isPrefix && HasNumericVersion(wgVer) && CompareAppVersions(installedVer, wgVer) > 0)
                {
                    return true;
                }
            }
            return false;
        }

        private static CatalogSensorItem SelectPreferredSensorPair(CatalogSensorItem cur, CatalogSensorItem cand)
        {
            if (cur == null) return cand;
            if (cand == null) return cur;

            bool curLocal = string.Equals(cur.Source, "local", StringComparison.OrdinalIgnoreCase);
            bool candLocal = string.Equals(cand.Source, "local", StringComparison.OrdinalIgnoreCase);
            int verCmp = CompareAppVersions(cand.Version, cur.Version);

            if (curLocal != candLocal)
            {
                CatalogSensorItem locItem = curLocal ? cur : cand;
                CatalogSensorItem wgItem = curLocal ? cand : cur;
                if (HasNumericVersion(locItem.Version))
                {
                    if (wgItem.HasUpdate && HasNumericVersion(wgItem.Available))
                    {
                        if (IsVersionAtLeastAvailable(locItem.Version, wgItem.Version, wgItem.Available)) return locItem;
                        return wgItem;
                    }
                    if (!HasNumericVersion(wgItem.Version) || CompareAppVersions(locItem.Version, wgItem.Version) > 0)
                    {
                        return locItem;
                    }
                }
                return wgItem;
            }

            bool curSyn = _rxSyntheticId.IsMatch(cur.ID ?? "");
            bool candSyn = _rxSyntheticId.IsMatch(cand.ID ?? "");
            if (curSyn != candSyn)
            {
                CatalogSensorItem synItem = curSyn ? cur : cand;
                CatalogSensorItem realItem = curSyn ? cand : cur;
                if (HasNumericVersion(synItem.Version))
                {
                    if (realItem.HasUpdate && HasNumericVersion(realItem.Available))
                    {
                        if (IsVersionAtLeastAvailable(synItem.Version, realItem.Version, realItem.Available)) return synItem;
                        return realItem;
                    }
                    if (!HasNumericVersion(realItem.Version) || CompareAppVersions(synItem.Version, realItem.Version) > 0)
                    {
                        return synItem;
                    }
                }
                return realItem;
            }

            // Only merge Version/Available when both entries share the same real package ID
            if (string.Equals(cur.ID ?? "", cand.ID ?? "", StringComparison.OrdinalIgnoreCase))
            {
                string bestVer = (verCmp > 0 || string.IsNullOrWhiteSpace(cur.Version)) ? cand.Version : cur.Version;
                int availCmp = CompareAppVersions(cand.Available, cur.Available);
                string bestAvail = (availCmp > 0) ? cand.Available : cur.Available;
                bool mergedUpd = TestAppUpdateGenuine(bestVer, bestAvail);
                if (!mergedUpd) bestAvail = "";
                bool useCand = (!cur.HasUpdate && cand.HasUpdate) || (verCmp > 0);
                CatalogSensorItem baseObj = useCand ? cand : cur;
                return new CatalogSensorItem
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

            if (verCmp > 0) return cand;
            if (verCmp < 0) return cur;
            return (!cur.HasUpdate && cand.HasUpdate) ? cand : cur;
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
            map[key] = SelectPreferredSensorPair(cur, cand);
        }

        private static void AddBucketEntry(Dictionary<string, List<CatalogSensorItem>> map, string key, CatalogSensorItem cand)
        {
            if (string.IsNullOrWhiteSpace(key) || cand == null) return;
            List<CatalogSensorItem> list;
            if (!map.TryGetValue(key, out list))
            {
                list = new List<CatalogSensorItem>(2);
                map[key] = list;
            }
            list.Add(cand);
        }

        private static CatalogSensorItem FindBestCompatibleInBucket(CompiledTargetMeta meta, Dictionary<string, List<CatalogSensorItem>> map, string key)
        {
            if (string.IsNullOrWhiteSpace(key)) return null;
            List<CatalogSensorItem> bucket;
            if (!map.TryGetValue(key, out bucket)) return null;
            CatalogSensorItem best = null;
            for (int i = 0; i < bucket.Count; i++)
            {
                CatalogSensorItem cand = bucket[i];
                if (IsMatchCompatible(meta, cand))
                {
                    best = SelectPreferredSensorPair(best, cand);
                }
            }
            return best;
        }

        public static double ComputeJaroWinkler(string a, string b)
        {
            if (string.IsNullOrEmpty(a) || string.IsNullOrEmpty(b)) return 0.0;
            if (string.Equals(a, b, StringComparison.Ordinal)) return 1.0;
            int lenA = a.Length;
            int lenB = b.Length;
            int matchDist = Math.Max(0, (Math.Max(lenA, lenB) / 2) - 1);
            bool[] matchedA = new bool[lenA];
            bool[] matchedB = new bool[lenB];
            int matches = 0;
            for (int i = 0; i < lenA; i++)
            {
                int start = Math.Max(0, i - matchDist);
                int end = Math.Min(i + matchDist + 1, lenB);
                for (int j = start; j < end; j++)
                {
                    if (matchedB[j] || a[i] != b[j]) continue;
                    matchedA[i] = true;
                    matchedB[j] = true;
                    matches++;
                    break;
                }
            }
            if (matches == 0) return 0.0;
            int t = 0;
            int k = 0;
            for (int i = 0; i < lenA; i++)
            {
                if (!matchedA[i]) continue;
                while (!matchedB[k]) k++;
                if (a[i] != b[k]) t++;
                k++;
            }
            double m = matches;
            double jaro = ((m / lenA) + (m / lenB) + ((m - (t / 2.0)) / m)) / 3.0;
            int prefix = 0;
            int maxPref = Math.Min(4, Math.Min(lenA, lenB));
            while (prefix < maxPref && a[prefix] == b[prefix]) prefix++;
            return jaro + (prefix * 0.1 * (1.0 - jaro));
        }

        private static bool IsLocalOrSyntheticCandidate(CatalogSensorItem item)
        {
            if (item == null) return false;
            if (string.Equals(item.Source, "local", StringComparison.OrdinalIgnoreCase)) return true;
            return _rxSyntheticId.IsMatch(item.ID ?? "");
        }

        private static CatalogSensorItem RefineIdMatchWithLocal(
            CompiledTargetMeta meta,
            CatalogSensorItem cand,
            Dictionary<string, CatalogSensorItem> nameMap,
            Dictionary<string, List<CatalogSensorItem>> cleanNameMap,
            Dictionary<string, List<CatalogSensorItem>> compactNameMap)
        {
            if (cand == null || string.Equals(cand.Source, "local", StringComparison.OrdinalIgnoreCase)) return cand;
            CatalogSensorItem best = cand;
            CatalogSensorItem alt;

            if (!string.IsNullOrEmpty(cand.Name) && nameMap.TryGetValue(cand.Name, out alt) &&
                IsLocalOrSyntheticCandidate(alt) && IsMatchCompatible(meta, alt))
            {
                best = SelectPreferredSensorPair(best, alt);
            }
            if (!string.IsNullOrEmpty(meta.Name) && !string.Equals(meta.Name, cand.Name, StringComparison.OrdinalIgnoreCase) &&
                nameMap.TryGetValue(meta.Name, out alt) &&
                IsLocalOrSyntheticCandidate(alt) && IsMatchCompatible(meta, alt))
            {
                best = SelectPreferredSensorPair(best, alt);
            }
            for (int a = 0; a < meta.CleanAliases.Count; a++)
            {
                string rawAl = meta.CleanAliases[a].Raw;
                if (!string.IsNullOrEmpty(rawAl) && nameMap.TryGetValue(rawAl, out alt) &&
                    IsLocalOrSyntheticCandidate(alt) && IsMatchCompatible(meta, alt))
                {
                    best = SelectPreferredSensorPair(best, alt);
                }
            }

            var seenClean = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var cleanKeys = new List<string>(2 + meta.CleanAliases.Count);
            if (!string.IsNullOrWhiteSpace(cand.CleanName) && cand.CleanName.Length >= 2 && seenClean.Add(cand.CleanName)) cleanKeys.Add(cand.CleanName);
            if (!string.IsNullOrWhiteSpace(meta.CleanTarget) && meta.CleanTarget.Length >= 2 && seenClean.Add(meta.CleanTarget)) cleanKeys.Add(meta.CleanTarget);
            for (int a = 0; a < meta.CleanAliases.Count; a++)
            {
                string ac = meta.CleanAliases[a].Clean;
                if (!string.IsNullOrWhiteSpace(ac) && ac.Length >= 2 && seenClean.Add(ac)) cleanKeys.Add(ac);
            }
            for (int k = 0; k < cleanKeys.Count; k++)
            {
                List<CatalogSensorItem> bucket;
                if (cleanNameMap.TryGetValue(cleanKeys[k], out bucket))
                {
                    for (int i = 0; i < bucket.Count; i++)
                    {
                        CatalogSensorItem loc = bucket[i];
                        if (IsLocalOrSyntheticCandidate(loc) && IsMatchCompatible(meta, loc))
                        {
                            best = SelectPreferredSensorPair(best, loc);
                        }
                    }
                }
            }

            if (compactNameMap != null)
            {
                var seenComp = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                var compKeys = new List<string>(2 + meta.CleanAliases.Count);
                string candComp = CompactAlnumKey(cand.CleanName ?? "");
                if (candComp.Length >= 4 && seenComp.Add(candComp)) compKeys.Add(candComp);
                if (meta.CompactTarget.Length >= 4 && seenComp.Add(meta.CompactTarget)) compKeys.Add(meta.CompactTarget);
                for (int a = 0; a < meta.CleanAliases.Count; a++)
                {
                    string acmp = meta.CleanAliases[a].Compact;
                    if (!string.IsNullOrWhiteSpace(acmp) && acmp.Length >= 4 && seenComp.Add(acmp)) compKeys.Add(acmp);
                }
                for (int k = 0; k < compKeys.Count; k++)
                {
                    List<CatalogSensorItem> bucket;
                    if (compactNameMap.TryGetValue(compKeys[k], out bucket))
                    {
                        for (int i = 0; i < bucket.Count; i++)
                        {
                            CatalogSensorItem loc = bucket[i];
                            if (IsLocalOrSyntheticCandidate(loc) && IsMatchCompatible(meta, loc))
                            {
                                best = SelectPreferredSensorPair(best, loc);
                            }
                        }
                    }
                }
            }
            return best;
        }

        private static CatalogSensorItem MatchSingleCatalogTarget(
            CatalogMatchTarget target,
            Dictionary<string, CatalogSensorItem> idMap,
            Dictionary<string, CatalogSensorItem> nameMap,
            Dictionary<string, List<CatalogSensorItem>> cleanNameMap,
            Dictionary<string, List<CatalogSensorItem>> compactNameMap,
            Dictionary<string, List<CatalogSensorItem>> tokenIndex,
            Dictionary<CatalogSensorItem, string> itemCompactMap,
            Dictionary<CatalogSensorItem, HashSet<string>> itemNameTokenMap)
        {
            if (target == null) return null;
            string targetId = target.ID ?? "";
            CompiledTargetMeta meta = GetOrBuildTargetMeta(target);
            CatalogSensorItem cand;

            if (idMap.TryGetValue(targetId, out cand) && IsMatchCompatible(meta, cand))
            {
                return RefineIdMatchWithLocal(meta, cand, nameMap, cleanNameMap, compactNameMap);
            }
            for (int a = 0; a < meta.CleanAliases.Count; a++)
            {
                if (idMap.TryGetValue(meta.CleanAliases[a].Raw, out cand) && IsMatchCompatible(meta, cand))
                {
                    return RefineIdMatchWithLocal(meta, cand, nameMap, cleanNameMap, compactNameMap);
                }
            }
            if (!string.IsNullOrEmpty(meta.Name) && nameMap.TryGetValue(meta.Name, out cand) && IsMatchCompatible(meta, cand))
            {
                return RefineIdMatchWithLocal(meta, cand, nameMap, cleanNameMap, compactNameMap);
            }
            for (int a = 0; a < meta.CleanAliases.Count; a++)
            {
                AliasPatternPair ap = meta.CleanAliases[a];
                if (nameMap.TryGetValue(ap.Raw, out cand) && IsMatchCompatible(meta, cand))
                {
                    return RefineIdMatchWithLocal(meta, cand, nameMap, cleanNameMap, compactNameMap);
                }
                if (ap.Clean.Length >= 2)
                {
                    cand = FindBestCompatibleInBucket(meta, cleanNameMap, ap.Clean);
                    if (cand != null) return cand;
                }
                if (ap.Compact.Length >= 4)
                {
                    cand = FindBestCompatibleInBucket(meta, compactNameMap, ap.Compact);
                    if (cand != null) return cand;
                }
            }
            if (meta.CleanTarget.Length >= 2)
            {
                cand = FindBestCompatibleInBucket(meta, cleanNameMap, meta.CleanTarget);
                if (cand != null) return cand;
            }
            if (meta.CompactTarget.Length >= 4)
            {
                cand = FindBestCompatibleInBucket(meta, compactNameMap, meta.CompactTarget);
                if (cand != null) return cand;
            }

            if (meta.QueryTokens.Count == 0) return null;

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
                string iNameNoParens = _rxCleanParens.Replace(iName, "").Trim();
                string iClean = item.CleanName ?? "";
                int score = 0;

                for (int aeIdx = 0; aeIdx < meta.AliasEntries.Count; aeIdx++)
                {
                    AliasPatternPair ae = meta.AliasEntries[aeIdx];
                    bool isIdLikeAlias = ae.Raw.IndexOf('.') >= 0 || ae.Raw.IndexOf('\\') >= 0;
                    if (isIdLikeAlias && iId.IndexOf(ae.Raw, StringComparison.OrdinalIgnoreCase) >= 0 && ae.Pattern.IsMatch(iId))
                    {
                        score = 780;
                        break;
                    }
                    string nameForAlias = (ae.Raw.IndexOf('(') >= 0 || _rxItemX64.IsMatch(ae.Raw) || _rxItemX86.IsMatch(ae.Raw) || _rxItemArm.IsMatch(ae.Raw))
                        ? iName
                        : iNameNoParens;
                    if (nameForAlias.IndexOf(ae.Raw, StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        Match mAl = ae.Pattern.Match(nameForAlias);
                        if (mAl.Success && !(mAl.Index >= 4 && nameForAlias.Substring(0, mAl.Index).TrimEnd().EndsWith(" for", StringComparison.OrdinalIgnoreCase)))
                        {
                            int lenRatio = Math.Min(40, (meta.CleanTarget.Length * 40) / Math.Max(1, nameForAlias.Length));
                            int cScore = 700 + lenRatio;
                            if (cScore > score) score = cScore;
                        }
                    }
                }

                if (score == 0 && meta.PatternClean != null && iClean.IndexOf(meta.CleanTarget, StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    Match mPc = meta.PatternClean.Match(iClean);
                    if (mPc.Success &&
                        !(mPc.Index >= 4 && iClean.Substring(0, mPc.Index).TrimEnd().EndsWith(" for", StringComparison.OrdinalIgnoreCase)) &&
                        (meta.CleanTarget.Length >= 5 || iClean.StartsWith(meta.CleanTarget, StringComparison.OrdinalIgnoreCase) || (meta.CleanTarget.Length * 2 >= iClean.Length)))
                    {
                        int lenRatio = Math.Min(40, (meta.CleanTarget.Length * 40) / Math.Max(1, iClean.Length));
                        score = 650 + lenRatio;
                    }
                }

                if (score == 0 && meta.TargetTokenSet.Count >= 2)
                {
                    HashSet<string> itSet;
                    if (itemNameTokenMap.TryGetValue(item, out itSet) && itSet.Count >= meta.TargetTokenSet.Count)
                    {
                        int hitToks = 0;
                        foreach (string tt in meta.TargetTokenSet)
                        {
                            if (itSet.Contains(tt)) hitToks++;
                        }
                        int minCovPct = meta.TargetTokenSet.Count == 2 ? 66 : 60;
                        if (hitToks == meta.TargetTokenSet.Count && (hitToks * 100 >= itSet.Count * minCovPct))
                        {
                            int jacc = (hitToks * 30) / Math.Max(1, itSet.Count);
                            score = 670 + jacc;
                        }
                    }
                }

                if (score == 0 && meta.CompactTarget.Length >= 4)
                {
                    string itemCmp;
                    itemCompactMap.TryGetValue(item, out itemCmp);
                    int dotIdx = iId.LastIndexOf('.');
                    string lastSegCmp = (!_rxSyntheticId.IsMatch(iId) && dotIdx >= 0 && dotIdx + 1 < iId.Length)
                        ? CompactAlnumKey(iId.Substring(dotIdx + 1))
                        : "";
                    if ((!string.IsNullOrEmpty(itemCmp) && string.Equals(itemCmp, meta.CompactTarget, StringComparison.Ordinal)) ||
                        (meta.CompactTarget.Length >= 5 && !string.IsNullOrEmpty(lastSegCmp) && string.Equals(lastSegCmp, meta.CompactTarget, StringComparison.Ordinal)))
                    {
                        score = 690;
                    }
                    else if (!string.IsNullOrEmpty(itemCmp) && meta.CompactTarget.Length >= 6 && itemCmp.Length >= 6 &&
                             meta.CompactTarget[0] == itemCmp[0] && meta.CompactTarget[1] == itemCmp[1])
                    {
                        int maxL = Math.Max(meta.CompactTarget.Length, itemCmp.Length);
                        int minL = Math.Min(meta.CompactTarget.Length, itemCmp.Length);
                        if (minL * 100 >= maxL * 78)
                        {
                            double jw = ComputeJaroWinkler(meta.CompactTarget, itemCmp);
                            if (jw >= 0.94)
                            {
                                score = 610 + (int)Math.Round(jw * 70.0);
                            }
                        }
                    }
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

            return bestCand;
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
            var cleanNameMap = new Dictionary<string, List<CatalogSensorItem>>(StringComparer.OrdinalIgnoreCase);
            var compactNameMap = new Dictionary<string, List<CatalogSensorItem>>(StringComparer.OrdinalIgnoreCase);
            var tokenIndex = new Dictionary<string, List<CatalogSensorItem>>(StringComparer.OrdinalIgnoreCase);
            var itemCompactMap = new Dictionary<CatalogSensorItem, string>();
            var itemNameTokenMap = new Dictionary<CatalogSensorItem, HashSet<string>>();

            for (int i = 0; i < installedItems.Length; i++)
            {
                CatalogSensorItem it = installedItems[i];
                if (it == null) continue;
                string itId = it.ID ?? "";
                string itName = it.Name ?? "";
                string itClean = it.CleanName ?? "";

                if (!string.IsNullOrWhiteSpace(itId)) SetPreferredEntry(idMap, itId, it);
                if (!string.IsNullOrWhiteSpace(itName)) SetPreferredEntry(nameMap, itName, it);
                if (itClean.Length >= 2) AddBucketEntry(cleanNameMap, itClean, it);

                string itCompact = CompactAlnumKey(itClean.Length > 0 ? itClean : itName);
                itemCompactMap[it] = itCompact;
                if (itCompact.Length >= 4) AddBucketEntry(compactNameMap, itCompact, it);

                string rawText = itId + " " + itName + " " + itClean;
                string[] toks = _rxTokSplit.Split(rawText);
                var seenIdxTok = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                for (int ti = 0; ti < toks.Length; ti++)
                {
                    string tk = toks[ti];
                    if ((tk.Length >= 3 || string.Equals(tk, "7z", StringComparison.OrdinalIgnoreCase)) && seenIdxTok.Add(tk))
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

                string nameOnlyText = (itClean.Length > 0 ? itClean : _rxCleanParens.Replace(itName, ""));
                string[] nameToks = _rxTokSplit.Split(nameOnlyText);
                var seenNameTok = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                for (int ti = 0; ti < nameToks.Length; ti++)
                {
                    string tk = nameToks[ti];
                    if (tk.Length >= 2 && !_matchStopWords.Contains(tk))
                    {
                        seenNameTok.Add(tk);
                    }
                }
                itemNameTokenMap[it] = seenNameTok;
            }

            if (targets.Length >= 24)
            {
                Parallel.For(0, targets.Length, delegate(int tIdx)
                {
                    results[tIdx] = MatchSingleCatalogTarget(targets[tIdx], idMap, nameMap, cleanNameMap, compactNameMap, tokenIndex, itemCompactMap, itemNameTokenMap);
                });
            }
            else
            {
                for (int tIdx = 0; tIdx < targets.Length; tIdx++)
                {
                    results[tIdx] = MatchSingleCatalogTarget(targets[tIdx], idMap, nameMap, cleanNameMap, compactNameMap, tokenIndex, itemCompactMap, itemNameTokenMap);
                }
            }

            return results;
        }

        public static Task<CatalogSensorItem[]> MatchCatalogAppsAsync(CatalogMatchTarget[] targets, CatalogSensorItem[] installedItems)
        {
            return Task.Run(delegate() { return MatchCatalogApps(targets, installedItems); });
        }
    }
}
