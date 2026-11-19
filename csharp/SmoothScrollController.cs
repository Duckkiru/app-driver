using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace DuckUtil {
    public sealed class SmoothScrollController {
        private readonly ScrollViewer _sv;
        private double _currentOffset;
        private double _targetOffset;
        private double _lastAppliedOffset;
        private double _preApplySvOffset;
        private int _pendingLayoutSyncFrames;
        private bool _isAnimating;
        private readonly Stopwatch _sw = new Stopwatch();
        private double _lastTimeSec;

        private SmoothScrollController(ScrollViewer sv) {
            _sv = sv;
            _currentOffset = sv.VerticalOffset;
            _targetOffset = sv.VerticalOffset;
            _lastAppliedOffset = sv.VerticalOffset;
            _preApplySvOffset = sv.VerticalOffset;
            _sv.PreviewMouseWheel += OnPreviewMouseWheel;
            _sv.IsVisibleChanged += OnIsVisibleChanged;
            _sv.Unloaded += OnUnloaded;
        }

        public static SmoothScrollController Attach(ScrollViewer sv) {
            if (sv == null) return null;
            return new SmoothScrollController(sv);
        }

        public static void AttachFrameWake(Task task, Dispatcher dispatcher, DispatcherFrame frame) {
            if (task == null || frame == null) return;
            task.ContinueWith(_ => {
                try {
                    if (dispatcher != null && !dispatcher.HasShutdownStarted && !dispatcher.HasShutdownFinished) {
                        dispatcher.BeginInvoke(DispatcherPriority.Send, new Action(() => { frame.Continue = false; }));
                    } else {
                        frame.Continue = false;
                    }
                } catch {}
            }, TaskScheduler.Default);
        }

        private bool IsActiveAndVisible() {
            return _sv.IsLoaded && _sv.IsVisible && PresentationSource.FromVisual(_sv) != null;
        }

        private void OnIsVisibleChanged(object sender, DependencyPropertyChangedEventArgs e) {
            if (!IsActiveAndVisible()) {
                StopAnimationAndSync();
            }
        }

        private void OnUnloaded(object sender, RoutedEventArgs e) {
            StopAnimationAndSync();
        }

        private void OnPreviewMouseWheel(object sender, MouseWheelEventArgs e) {
            if (e == null || e.Handled) return;
            if (Keyboard.Modifiers != ModifierKeys.None) return;
            if (!IsActiveAndVisible()) return;

            double maxScroll = _sv.ScrollableHeight;
            if (double.IsNaN(maxScroll) || double.IsInfinity(maxScroll) || maxScroll <= 0) return;

            double svOffset = _sv.VerticalOffset;
            if (double.IsNaN(svOffset) || double.IsInfinity(svOffset)) svOffset = 0.0;

            bool externalJump = _isAnimating
                && Math.Abs(svOffset - _lastAppliedOffset) > 2.5
                && (_pendingLayoutSyncFrames == 0 || Math.Abs(svOffset - _preApplySvOffset) > 0.5);

            if (!_isAnimating || externalJump) {
                _currentOffset = svOffset;
                _targetOffset = svOffset;
                _lastAppliedOffset = svOffset;
                _preApplySvOffset = svOffset;
                _pendingLayoutSyncFrames = 0;
            }

            double step = -e.Delta * 0.85;
            if (double.IsNaN(step) || double.IsInfinity(step)) return;

            _targetOffset = Math.Max(0.0, Math.Min(maxScroll, _targetOffset + step));
            e.Handled = true;

            if (!_isAnimating) {
                _isAnimating = true;
                _sw.Restart();
                _lastTimeSec = 0.0;
                CompositionTarget.Rendering += OnRendering;
            }
        }

        private void OnRendering(object sender, EventArgs e) {
            if (!IsActiveAndVisible()) {
                StopAnimationAndSync();
                return;
            }

            double svOffset = _sv.VerticalOffset;
            if (double.IsNaN(svOffset) || double.IsInfinity(svOffset)) {
                StopAnimationAndSync();
                return;
            }

            if (Math.Abs(svOffset - _lastAppliedOffset) <= 2.5) {
                _pendingLayoutSyncFrames = 0;
            } else if (_pendingLayoutSyncFrames > 0 && Math.Abs(svOffset - _preApplySvOffset) <= 0.5 && _pendingLayoutSyncFrames <= 3) {
                _pendingLayoutSyncFrames++;
            } else {
                _currentOffset = svOffset;
                _targetOffset = svOffset;
                _lastAppliedOffset = svOffset;
                _preApplySvOffset = svOffset;
                StopAnimation();
                return;
            }

            double nowSec = _sw.Elapsed.TotalSeconds;
            double dt = nowSec - _lastTimeSec;
            _lastTimeSec = nowSec;
            if (double.IsNaN(dt) || double.IsInfinity(dt) || dt <= 0.0) dt = 0.016;
            else if (dt > 0.05) dt = 0.05;

            double maxScroll = _sv.ScrollableHeight;
            if (double.IsNaN(maxScroll) || double.IsInfinity(maxScroll) || maxScroll < 0.0) maxScroll = 0.0;
            if (_targetOffset > maxScroll) _targetOffset = maxScroll;
            if (_targetOffset < 0.0) _targetOffset = 0.0;

            double diff = _targetOffset - _currentOffset;
            if (double.IsNaN(diff) || double.IsInfinity(diff)) {
                StopAnimationAndSync();
                return;
            }

            if (Math.Abs(diff) < 0.35) {
                _currentOffset = _targetOffset;
                _lastAppliedOffset = _currentOffset;
                _pendingLayoutSyncFrames = 0;
                _sv.ScrollToVerticalOffset(_currentOffset);
                StopAnimation();
                return;
            }

            double factor = 1.0 - Math.Exp(-20.0 * dt);
            _currentOffset += diff * factor;
            if (_pendingLayoutSyncFrames == 0) {
                _preApplySvOffset = svOffset;
            }
            _lastAppliedOffset = _currentOffset;
            if (Math.Abs(svOffset - _currentOffset) > 0.1 && _pendingLayoutSyncFrames == 0) {
                _pendingLayoutSyncFrames = 1;
            }
            _sv.ScrollToVerticalOffset(_currentOffset);
        }

        private void StopAnimation() {
            if (_isAnimating) {
                _isAnimating = false;
                CompositionTarget.Rendering -= OnRendering;
                _sw.Stop();
            }
            _pendingLayoutSyncFrames = 0;
        }

        private void StopAnimationAndSync() {
            StopAnimation();
            double svOffset = _sv.VerticalOffset;
            if (double.IsNaN(svOffset) || double.IsInfinity(svOffset)) svOffset = 0.0;
            _currentOffset = svOffset;
            _targetOffset = svOffset;
            _lastAppliedOffset = svOffset;
            _preApplySvOffset = svOffset;
        }
    }

    public sealed class ReadyIconItem {
        public int Index { get; set; }
        public int Generation { get; set; }
        public string CacheKey { get; set; }
        public BitmapSource Bitmap { get; set; }
    }

    public sealed class UninstRowVisual {
        public Border RowBorder { get; set; }
        public CheckBox CheckBox { get; set; }
        public System.Windows.Controls.Image IconImg { get; set; }
        public Border FallbackBadge { get; set; }
        public Border FolderBtn { get; set; }
    }

    public sealed class CatalogRowVisual {
        public Border RowBorder { get; set; }
        public CheckBox CheckBox { get; set; }
        public Border IconBadge { get; set; }
        public System.Windows.Controls.Image IconImg { get; set; }
        public TextBlock FallbackGlyph { get; set; }
        public TextBlock NameText { get; set; }
        public Border UpdateBadge { get; set; }
        public TextBlock UpdateText { get; set; }
        public Border LinkBtn { get; set; }
        public TextBlock LinkIcon { get; set; }
    }

    public static class UiAssetPipeline {
        private sealed class RemoteIconJob {
            public int Index;
            public int Generation;
            public string Url;
            public string FallbackUrl;
            public string DestPath;
            public string CacheKey;
        }

        private sealed class UninstIconJob {
            public int Index;
            public int Generation;
            public string TargetPath;
        }

        private static readonly ConcurrentDictionary<string, BitmapSource> _remoteBmpCache =
            new ConcurrentDictionary<string, BitmapSource>(StringComparer.OrdinalIgnoreCase);
        private static readonly ConcurrentDictionary<string, BitmapSource> _uninstBmpCache =
            new ConcurrentDictionary<string, BitmapSource>(StringComparer.OrdinalIgnoreCase);

        private static readonly ConcurrentQueue<ReadyIconItem> _remoteQueue = new ConcurrentQueue<ReadyIconItem>();
        private static readonly ConcurrentQueue<ReadyIconItem> _uninstQueue = new ConcurrentQueue<ReadyIconItem>();
        private static readonly ConcurrentQueue<RemoteIconJob> _remoteJobs = new ConcurrentQueue<RemoteIconJob>();
        private static readonly ConcurrentQueue<UninstIconJob> _uninstJobs = new ConcurrentQueue<UninstIconJob>();

        private static int _remoteGen = 0;
        private static int _remoteRemaining = 0;
        private static int _remoteActiveWorkers = 0;
        private static int _uninstGen = 0;
        private static int _uninstRemaining = 0;
        private static int _uninstActiveWorkers = 0;
        private static readonly HttpClient _httpClient = CreateHttpClient();

        private static HttpClient CreateHttpClient() {
            var handler = new HttpClientHandler();
            try { handler.UseProxy = false; } catch {}
            try { handler.AllowAutoRedirect = true; } catch {}
            var client = new HttpClient(handler);
            client.Timeout = TimeSpan.FromMilliseconds(3500);
            try { client.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) DuckUtil/3.5"); } catch {}
            return client;
        }

        public static bool IsRemoteIdle {
            get { return Volatile.Read(ref _remoteRemaining) <= 0 && _remoteQueue.IsEmpty; }
        }

        public static bool IsUninstIdle {
            get { return Volatile.Read(ref _uninstRemaining) <= 0 && _uninstQueue.IsEmpty; }
        }

        public static BitmapSource TryGetCachedRemoteIcon(string cacheKey) {
            if (string.IsNullOrEmpty(cacheKey)) return null;
            BitmapSource bmp;
            return _remoteBmpCache.TryGetValue(cacheKey, out bmp) ? bmp : null;
        }

        public static BitmapSource TryGetCachedUninstIcon(string key) {
            if (string.IsNullOrEmpty(key)) return null;
            BitmapSource bmp;
            return _uninstBmpCache.TryGetValue(key, out bmp) ? bmp : null;
        }

        public static void ResetRemoteIconPipeline() {
            Interlocked.Increment(ref _remoteGen);
            Interlocked.Exchange(ref _remoteRemaining, 0);
            RemoteIconJob j;
            while (_remoteJobs.TryDequeue(out j)) {}
            ReadyIconItem d;
            while (_remoteQueue.TryDequeue(out d)) {}
        }

        public static void StopRemoteIconPipeline() {
            ResetRemoteIconPipeline();
        }

        public static void ResetUninstallerIconPipeline() {
            Interlocked.Increment(ref _uninstGen);
            Interlocked.Exchange(ref _uninstRemaining, 0);
            UninstIconJob j;
            while (_uninstJobs.TryDequeue(out j)) {}
            ReadyIconItem d;
            while (_uninstQueue.TryDequeue(out d)) {}
        }

        public static void StopUninstallerIconPipeline() {
            ResetUninstallerIconPipeline();
        }

        private static BitmapImage DecodeFrozenPngOrIcoBitmap(byte[] data) {
            if (data == null || data.Length <= 64) return null;
            try {
                using (var ms = new MemoryStream(data)) {
                    var bmp = new BitmapImage();
                    bmp.BeginInit();
                    bmp.StreamSource = ms;
                    bmp.CacheOption = BitmapCacheOption.OnLoad;
                    bmp.CreateOptions = BitmapCreateOptions.IgnoreColorProfile;
                    bmp.DecodePixelWidth = 36;
                    bmp.EndInit();
                    bmp.Freeze();
                    if (bmp.PixelWidth <= 0) return null;
                    return bmp;
                }
            } catch {
                return null;
            }
        }

        private static byte[] DownloadBytesWithTimeout(string url, int timeoutMs) {
            if (string.IsNullOrWhiteSpace(url)) return null;
            try {
                using (var cts = new CancellationTokenSource(timeoutMs))
                using (HttpResponseMessage resp = _httpClient.GetAsync(url, HttpCompletionOption.ResponseContentRead, cts.Token).GetAwaiter().GetResult()) {
                    if (resp == null || !resp.IsSuccessStatusCode || resp.Content == null) return null;
                    long? cl = resp.Content.Headers.ContentLength;
                    if (cl.HasValue && cl.Value > 2 * 1024 * 1024) return null;
                    byte[] bytes = resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
                    if (bytes != null && bytes.Length <= 2 * 1024 * 1024) {
                        return bytes;
                    }
                }
            } catch {}
            return null;
        }

        private static void EnsureRemoteWorkers(int maxWorkers) {
            while (true) {
                if (_remoteJobs.IsEmpty) return;
                int cur = Volatile.Read(ref _remoteActiveWorkers);
                if (cur >= maxWorkers) return;
                if (Interlocked.CompareExchange(ref _remoteActiveWorkers, cur + 1, cur) == cur) {
                    Task.Run(delegate() { RemoteWorkerLoop(); });
                }
            }
        }

        private static void RemoteWorkerLoop() {
            try {
                while (true) {
                    RemoteIconJob job;
                    if (!_remoteJobs.TryDequeue(out job)) break;
                    if (job == null) continue;
                    int gen = job.Generation;
                    try {
                        if (Volatile.Read(ref _remoteGen) != gen) continue;
                        BitmapSource ready = null;
                        if (!string.IsNullOrEmpty(job.CacheKey)) {
                            _remoteBmpCache.TryGetValue(job.CacheKey, out ready);
                        }
                        if (ready == null && !string.IsNullOrEmpty(job.DestPath) && File.Exists(job.DestPath)) {
                            try {
                                byte[] fBytes = File.ReadAllBytes(job.DestPath);
                                ready = DecodeFrozenPngOrIcoBitmap(fBytes);
                                if (ready == null) {
                                    try { File.Delete(job.DestPath); } catch {}
                                }
                            } catch {}
                        }
                        if (ready == null && Volatile.Read(ref _remoteGen) == gen) {
                            byte[] dl = DownloadBytesWithTimeout(job.Url, 2500);
                            if (dl != null && dl.Length > 230 && dl.Length != 588) {
                                ready = DecodeFrozenPngOrIcoBitmap(dl);
                                if (ready != null && !string.IsNullOrEmpty(job.DestPath) && !File.Exists(job.DestPath)) {
                                    try { File.WriteAllBytes(job.DestPath, dl); } catch {}
                                }
                            }
                            if (ready == null && !string.IsNullOrWhiteSpace(job.FallbackUrl) && Volatile.Read(ref _remoteGen) == gen) {
                                byte[] dl2 = DownloadBytesWithTimeout(job.FallbackUrl, 2500);
                                if (dl2 != null && dl2.Length > 230 && dl2.Length != 588) {
                                    ready = DecodeFrozenPngOrIcoBitmap(dl2);
                                    if (ready != null && !string.IsNullOrEmpty(job.DestPath) && !File.Exists(job.DestPath)) {
                                        try { File.WriteAllBytes(job.DestPath, dl2); } catch {}
                                    }
                                }
                            }
                        }
                        if (ready != null && Volatile.Read(ref _remoteGen) == gen) {
                            if (!string.IsNullOrEmpty(job.CacheKey)) {
                                _remoteBmpCache[job.CacheKey] = ready;
                            }
                            _remoteQueue.Enqueue(new ReadyIconItem {
                                Index = job.Index,
                                Generation = gen,
                                CacheKey = job.CacheKey,
                                Bitmap = ready
                            });
                        }
                    } catch {
                    } finally {
                        if (Volatile.Read(ref _remoteGen) == gen) {
                            Interlocked.Decrement(ref _remoteRemaining);
                        }
                    }
                }
            } finally {
                Interlocked.Decrement(ref _remoteActiveWorkers);
                if (!_remoteJobs.IsEmpty) EnsureRemoteWorkers(12);
            }
        }

        public static void EnqueueRemoteIcons(int[] indices, string[] urls, string[] fallbackUrls, string[] destPaths, string[] cacheKeys) {
            if (indices == null || indices.Length == 0) return;
            int gen = Volatile.Read(ref _remoteGen);
            int queued = 0;
            for (int k = 0; k < indices.Length; k++) {
                int idx = indices[k];
                string url = (urls != null && k < urls.Length) ? urls[k] : null;
                string fbUrl = (fallbackUrls != null && k < fallbackUrls.Length) ? fallbackUrls[k] : null;
                string dest = (destPaths != null && k < destPaths.Length) ? destPaths[k] : null;
                string cKey = (cacheKeys != null && k < cacheKeys.Length) ? cacheKeys[k] : null;

                BitmapSource cached = null;
                if (!string.IsNullOrEmpty(cKey) && _remoteBmpCache.TryGetValue(cKey, out cached) && cached != null) {
                    _remoteQueue.Enqueue(new ReadyIconItem {
                        Index = idx,
                        Generation = gen,
                        CacheKey = cKey,
                        Bitmap = cached
                    });
                    continue;
                }

                Interlocked.Increment(ref _remoteRemaining);
                _remoteJobs.Enqueue(new RemoteIconJob {
                    Index = idx,
                    Generation = gen,
                    Url = url,
                    FallbackUrl = fbUrl,
                    DestPath = dest,
                    CacheKey = cKey
                });
                queued++;
            }
            if (queued > 0) {
                EnsureRemoteWorkers(Math.Min(12, Math.Max(4, queued)));
            }
        }

        public static void StartRemoteIconPipeline(string[] urls, string[] fallbackUrls, string[] destPaths, string[] cacheKeys) {
            ResetRemoteIconPipeline();
            int total = urls != null ? urls.Length : 0;
            if (total == 0) return;
            int[] indices = new int[total];
            for (int i = 0; i < total; i++) indices[i] = i;
            EnqueueRemoteIcons(indices, urls, fallbackUrls, destPaths, cacheKeys);
        }

        public static ReadyIconItem[] DequeueReadyRemoteIcons(int maxCount) {
            if (_remoteQueue.IsEmpty) return new ReadyIconItem[0];
            var list = new List<ReadyIconItem>(maxCount);
            int curGen = Volatile.Read(ref _remoteGen);
            ReadyIconItem item;
            while (list.Count < maxCount && _remoteQueue.TryDequeue(out item)) {
                if (item != null && item.Generation == curGen && item.Bitmap != null) {
                    list.Add(item);
                }
            }
            return list.ToArray();
        }

        private static BitmapSource ExtractIconBitmapFromPath(string path) {
            if (string.IsNullOrWhiteSpace(path)) return null;
            BitmapSource cached;
            if (_uninstBmpCache.TryGetValue(path, out cached)) return cached;
            if (!File.Exists(path)) return null;

            BitmapSource res = null;
            try {
                string ext = Path.GetExtension(path) ?? "";
                if (ext.Equals(".png", StringComparison.OrdinalIgnoreCase)) {
                    byte[] bytes = File.ReadAllBytes(path);
                    res = DecodeFrozenPngOrIcoBitmap(bytes);
                } else if (ext.Equals(".ico", StringComparison.OrdinalIgnoreCase) || string.IsNullOrEmpty(ext)) {
                    byte[] bytes = File.ReadAllBytes(path);
                    if (bytes != null && bytes.Length > 6 && bytes[0] == 0 && bytes[1] == 0 && (bytes[2] == 1 || bytes[2] == 2) && bytes[3] == 0) {
                        using (var ms = new MemoryStream(bytes))
                        using (var ico = new Icon(ms, 32, 32)) {
                            BitmapSource bs = Imaging.CreateBitmapSourceFromHIcon(ico.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                            bs.Freeze();
                            res = bs;
                        }
                    }
                }
                if (res == null) {
                    using (Icon assoc = Icon.ExtractAssociatedIcon(path)) {
                        if (assoc != null) {
                            BitmapSource bs2 = Imaging.CreateBitmapSourceFromHIcon(assoc.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                            bs2.Freeze();
                            res = bs2;
                        }
                    }
                }
            } catch {}

            if (res != null) {
                _uninstBmpCache[path] = res;
            }
            return res;
        }

        private static void EnsureUninstWorkers(int maxWorkers) {
            while (true) {
                if (_uninstJobs.IsEmpty) return;
                int cur = Volatile.Read(ref _uninstActiveWorkers);
                if (cur >= maxWorkers) return;
                if (Interlocked.CompareExchange(ref _uninstActiveWorkers, cur + 1, cur) == cur) {
                    Thread t = new Thread(delegate() { UninstWorkerLoop(); });
                    t.IsBackground = true;
                    t.Priority = ThreadPriority.BelowNormal;
                    t.SetApartmentState(ApartmentState.STA);
                    t.Start();
                }
            }
        }

        private static void UninstWorkerLoop() {
            try {
                while (true) {
                    UninstIconJob job;
                    if (!_uninstJobs.TryDequeue(out job)) break;
                    if (job == null) continue;
                    int gen = job.Generation;
                    try {
                        if (Volatile.Read(ref _uninstGen) != gen) continue;
                        BitmapSource bmp = ExtractIconBitmapFromPath(job.TargetPath);
                        if (bmp != null && Volatile.Read(ref _uninstGen) == gen) {
                            _uninstQueue.Enqueue(new ReadyIconItem {
                                Index = job.Index,
                                Generation = gen,
                                CacheKey = job.TargetPath,
                                Bitmap = bmp
                            });
                        }
                    } catch {
                    } finally {
                        if (Volatile.Read(ref _uninstGen) == gen) {
                            Interlocked.Decrement(ref _uninstRemaining);
                        }
                    }
                }
            } finally {
                Interlocked.Decrement(ref _uninstActiveWorkers);
                if (!_uninstJobs.IsEmpty) EnsureUninstWorkers(2);
            }
        }

        public static void EnqueueUninstallerIcons(int[] indices, string[] targetPaths) {
            if (indices == null || targetPaths == null || indices.Length == 0) return;
            int gen = Volatile.Read(ref _uninstGen);
            int queued = 0;
            for (int k = 0; k < indices.Length && k < targetPaths.Length; k++) {
                string p = targetPaths[k];
                if (string.IsNullOrWhiteSpace(p)) continue;
                BitmapSource cached;
                if (_uninstBmpCache.TryGetValue(p, out cached) && cached != null) {
                    _uninstQueue.Enqueue(new ReadyIconItem {
                        Index = indices[k],
                        Generation = gen,
                        CacheKey = p,
                        Bitmap = cached
                    });
                    continue;
                }
                Interlocked.Increment(ref _uninstRemaining);
                _uninstJobs.Enqueue(new UninstIconJob {
                    Index = indices[k],
                    Generation = gen,
                    TargetPath = p
                });
                queued++;
            }
            if (queued > 0) {
                EnsureUninstWorkers(Math.Min(2, queued));
            }
        }

        public static void StartUninstallerIconPipeline(string[] targetPaths) {
            ResetUninstallerIconPipeline();
            if (targetPaths == null || targetPaths.Length == 0) return;
            int[] indices = new int[targetPaths.Length];
            for (int i = 0; i < targetPaths.Length; i++) indices[i] = i;
            EnqueueUninstallerIcons(indices, targetPaths);
        }

        public static ReadyIconItem[] DequeueReadyUninstallerIcons(int maxCount) {
            if (_uninstQueue.IsEmpty) return new ReadyIconItem[0];
            var list = new List<ReadyIconItem>(maxCount);
            int curGen = Volatile.Read(ref _uninstGen);
            ReadyIconItem item;
            while (list.Count < maxCount && _uninstQueue.TryDequeue(out item)) {
                if (item != null && item.Generation == curGen && item.Bitmap != null) {
                    list.Add(item);
                }
            }
            return list.ToArray();
        }

        private static readonly GridLength _uCol0 = new GridLength(38, GridUnitType.Pixel);
        private static readonly GridLength _uCol1 = new GridLength(1, GridUnitType.Star);
        private static readonly GridLength _uCol2 = new GridLength(130, GridUnitType.Pixel);
        private static readonly GridLength _uCol3 = new GridLength(220, GridUnitType.Pixel);
        private static readonly GridLength _uCol4 = new GridLength(105, GridUnitType.Pixel);
        private static readonly GridLength _uCol5 = new GridLength(115, GridUnitType.Pixel);
        private static readonly GridLength _uCol6 = new GridLength(54, GridUnitType.Pixel);
        private static readonly GridLength _uIconW = new GridLength(20, GridUnitType.Pixel);
        private static readonly Thickness _tZero = new Thickness(0);
        private static readonly Thickness _tRowBdr = new Thickness(1, 0, 1, 1);
        private static readonly Thickness _tOne = new Thickness(1);
        private static readonly Thickness _tName = new Thickness(8, 0, 8, 0);
        private static readonly Thickness _tCol = new Thickness(10, 0, 10, 0);
        private static readonly Thickness _tSize = new Thickness(8, 0, 12, 0);
        private static readonly Thickness _tBadgePad = new Thickness(8, 2, 8, 2);
        private static readonly CornerRadius _cRow = new CornerRadius(0);
        private static readonly CornerRadius _cFour = new CornerRadius(1);

        public static UninstRowVisual CreateUninstallerRow(
            string displayName,
            string displayVersion,
            string publisher,
            string sizeText,
            bool isBrokenOrphan,
            string targetFolder,
            string rowToolTip,
            string folderGlyph,
            Style rowStyle,
            System.Windows.Media.Brush rowBorderBrush,
            System.Windows.Media.Brush titleBrush,
            System.Windows.Media.Brush titleBrokenBrush,
            System.Windows.Media.Brush mutedBrush,
            System.Windows.Media.Brush lightBrush,
            System.Windows.Media.Brush badgeBg,
            System.Windows.Media.Brush badgeFg,
            System.Windows.Media.Brush badgeBrokenBg,
            System.Windows.Media.Brush badgeBrokenFg,
            System.Windows.Media.Brush statusOkBg,
            System.Windows.Media.Brush statusOkBorder,
            System.Windows.Media.Brush statusOkFg,
            System.Windows.Media.Brush statusBrokenBg,
            System.Windows.Media.Brush statusBrokenBorder,
            System.Windows.Media.Brush folderBg,
            System.Windows.Media.Brush folderBorder,
            BitmapSource preCachedIcon)
        {
            var rowBorder = new Border();
            rowBorder.Height = 38;
            rowBorder.CornerRadius = _cRow;
            rowBorder.Padding = _tZero;
            rowBorder.Margin = _tZero;
            if (rowStyle != null) rowBorder.Style = rowStyle;
            rowBorder.BorderBrush = rowBorderBrush;
            rowBorder.BorderThickness = _tRowBdr;
            rowBorder.Cursor = Cursors.Hand;
            if (!string.IsNullOrEmpty(rowToolTip)) {
                rowBorder.ToolTip = rowToolTip;
                ToolTipService.SetInitialShowDelay(rowBorder, 5000);
            }

            var rowGrid = new Grid();
            rowGrid.VerticalAlignment = VerticalAlignment.Stretch;
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _uCol0 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _uCol1 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _uCol2 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _uCol3 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _uCol4 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _uCol5 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _uCol6 });

            var cb = new CheckBox();
            cb.VerticalAlignment = VerticalAlignment.Center;
            cb.HorizontalAlignment = HorizontalAlignment.Center;
            cb.Margin = _tZero;
            cb.Tag = rowBorder;
            Grid.SetColumn(cb, 0);
            rowGrid.Children.Add(cb);

            var nameGrid = new Grid();
            nameGrid.VerticalAlignment = VerticalAlignment.Center;
            nameGrid.Margin = _tName;
            nameGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _uIconW });
            nameGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _uCol1 });

            var iconSlot = new Grid();
            iconSlot.Width = 20;
            iconSlot.Height = 20;
            iconSlot.VerticalAlignment = VerticalAlignment.Center;
            iconSlot.HorizontalAlignment = HorizontalAlignment.Left;

            var fallbackBadge = new Border();
            fallbackBadge.Width = 20;
            fallbackBadge.Height = 20;
            fallbackBadge.CornerRadius = _cFour;
            fallbackBadge.Background = isBrokenOrphan ? badgeBrokenBg : badgeBg;
            fallbackBadge.VerticalAlignment = VerticalAlignment.Center;
            fallbackBadge.HorizontalAlignment = HorizontalAlignment.Center;

            string dispTrim = string.IsNullOrEmpty(displayName) ? "A" : displayName.Trim();
            string badgeLetter = isBrokenOrphan ? "!" : (dispTrim.Length > 0 ? dispTrim.Substring(0, 1).ToUpperInvariant() : "\u2022");
            var badgeTb = new TextBlock();
            badgeTb.Text = badgeLetter;
            badgeTb.FontSize = 10.5;
            badgeTb.FontWeight = FontWeights.Bold;
            badgeTb.Foreground = isBrokenOrphan ? badgeBrokenFg : badgeFg;
            badgeTb.HorizontalAlignment = HorizontalAlignment.Center;
            badgeTb.VerticalAlignment = VerticalAlignment.Center;
            fallbackBadge.Child = badgeTb;

            var img = new System.Windows.Controls.Image();
            img.Width = 20;
            img.Height = 20;
            img.Stretch = Stretch.Uniform;
            RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.LowQuality);
            img.VerticalAlignment = VerticalAlignment.Center;
            img.HorizontalAlignment = HorizontalAlignment.Center;

            if (preCachedIcon != null) {
                img.Source = preCachedIcon;
                fallbackBadge.Visibility = Visibility.Collapsed;
            }

            iconSlot.Children.Add(fallbackBadge);
            iconSlot.Children.Add(img);
            Grid.SetColumn(iconSlot, 0);
            nameGrid.Children.Add(iconSlot);

            var nameTb = new TextBlock();
            nameTb.Text = displayName ?? "";
            nameTb.FontSize = 12;
            nameTb.FontWeight = FontWeights.SemiBold;
            nameTb.Foreground = isBrokenOrphan ? titleBrokenBrush : titleBrush;
            nameTb.VerticalAlignment = VerticalAlignment.Center;
            nameTb.TextTrimming = TextTrimming.CharacterEllipsis;
            nameTb.Margin = new Thickness(8, 0, 4, 0);
            Grid.SetColumn(nameTb, 1);
            nameGrid.Children.Add(nameTb);

            Grid.SetColumn(nameGrid, 1);
            rowGrid.Children.Add(nameGrid);

            var verTb = new TextBlock();
            verTb.Text = string.IsNullOrEmpty(displayVersion) ? "--" : displayVersion;
            verTb.FontSize = 11.5;
            verTb.Foreground = mutedBrush;
            verTb.VerticalAlignment = VerticalAlignment.Center;
            verTb.TextTrimming = TextTrimming.CharacterEllipsis;
            verTb.Margin = _tCol;
            Grid.SetColumn(verTb, 2);
            rowGrid.Children.Add(verTb);

            var pubTb = new TextBlock();
            pubTb.Text = string.IsNullOrEmpty(publisher) ? "--" : publisher;
            pubTb.FontSize = 11.5;
            pubTb.Foreground = mutedBrush;
            pubTb.VerticalAlignment = VerticalAlignment.Center;
            pubTb.TextTrimming = TextTrimming.CharacterEllipsis;
            pubTb.Margin = _tCol;
            Grid.SetColumn(pubTb, 3);
            rowGrid.Children.Add(pubTb);

            var sizeTb = new TextBlock();
            sizeTb.Text = string.IsNullOrEmpty(sizeText) ? "--" : sizeText;
            sizeTb.FontSize = 11.5;
            sizeTb.Foreground = lightBrush;
            sizeTb.VerticalAlignment = VerticalAlignment.Center;
            sizeTb.TextAlignment = TextAlignment.Right;
            sizeTb.Margin = _tSize;
            Grid.SetColumn(sizeTb, 4);
            rowGrid.Children.Add(sizeTb);

            var statusBorder = new Border();
            statusBorder.CornerRadius = _cFour;
            statusBorder.Padding = _tBadgePad;
            statusBorder.HorizontalAlignment = HorizontalAlignment.Center;
            statusBorder.VerticalAlignment = VerticalAlignment.Center;
            statusBorder.BorderThickness = _tOne;
            statusBorder.Background = isBrokenOrphan ? statusBrokenBg : statusOkBg;
            statusBorder.BorderBrush = isBrokenOrphan ? statusBrokenBorder : statusOkBorder;

            var statusTb = new TextBlock();
            statusTb.FontSize = 10.5;
            statusTb.FontWeight = FontWeights.SemiBold;
            statusTb.Text = isBrokenOrphan ? "X\u00F3a sai c\u00E1ch" : "B\u00ECnh th\u01B0\u1EDDng";
            statusTb.Foreground = isBrokenOrphan ? badgeBrokenFg : statusOkFg;
            statusBorder.Child = statusTb;
            Grid.SetColumn(statusBorder, 5);
            rowGrid.Children.Add(statusBorder);

            var folderBtn = new Border();
            folderBtn.Width = 26;
            folderBtn.Height = 24;
            folderBtn.CornerRadius = _cFour;
            folderBtn.Background = folderBg;
            folderBtn.BorderBrush = folderBorder;
            folderBtn.BorderThickness = _tOne;
            folderBtn.HorizontalAlignment = HorizontalAlignment.Center;
            folderBtn.VerticalAlignment = VerticalAlignment.Center;

            var folderIcon = new TextBlock();
            folderIcon.Text = folderGlyph ?? "";
            folderIcon.FontSize = 10.5;
            folderIcon.HorizontalAlignment = HorizontalAlignment.Center;
            folderIcon.VerticalAlignment = VerticalAlignment.Center;
            folderBtn.Child = folderIcon;

            if (!string.IsNullOrWhiteSpace(targetFolder)) {
                folderBtn.Cursor = Cursors.Hand;
                folderBtn.Tag = targetFolder;
                folderBtn.ToolTip = "M\u1EDF th\u01B0 m\u1EE5c: " + targetFolder;
            } else {
                folderBtn.Opacity = 0.25;
                folderBtn.Cursor = Cursors.Arrow;
                folderBtn.ToolTip = "Kh\u00F4ng t\u00ECm th\u1EA5y th\u01B0 m\u1EE5c c\u00E0i \u0111\u1EB7t";
            }
            ToolTipService.SetInitialShowDelay(folderBtn, 5000);
            Grid.SetColumn(folderBtn, 6);
            rowGrid.Children.Add(folderBtn);

            rowBorder.Child = rowGrid;

            return new UninstRowVisual {
                RowBorder = rowBorder,
                CheckBox = cb,
                IconImg = img,
                FallbackBadge = fallbackBadge,
                FolderBtn = folderBtn
            };
        }

        private static readonly GridLength _cCol0 = new GridLength(20, GridUnitType.Pixel);
        private static readonly GridLength _cCol1 = new GridLength(23, GridUnitType.Pixel);
        private static readonly GridLength _cCol2 = new GridLength(1, GridUnitType.Star);
        private static readonly GridLength _cCol3 = new GridLength(22, GridUnitType.Pixel);
        private static readonly GridLength _cAuto = GridLength.Auto;
        private static readonly Thickness _ctRowPad = new Thickness(5, 0, 4, 0);
        private static readonly Thickness _ctRowMgn = new Thickness(0, 1, 0, 1);
        private static readonly Thickness _ctNameMgn = new Thickness(5, 0, 4, 0);
        private static readonly Thickness _ctUpdPad = new Thickness(5, 1, 5, 1);
        private static readonly Thickness _ctUpdMgn = new Thickness(2, 0, 4, 0);
        private static readonly Thickness _ctLinkMgn = new Thickness(0, -1, 0, 0);
        private static readonly CornerRadius _ccRow = new CornerRadius(1);

        public static CatalogRowVisual CreateCatalogRow(
            string appName,
            string rowToolTip,
            string targetPageUrl,
            string fallbackGlyphText,
            bool useLightBadge,
            Style rowStyle,
            Style linkBtnStyle,
            System.Windows.Media.FontFamily fontSegoeUI,
            System.Windows.Media.FontFamily fontSegoeEmoji,
            System.Windows.Media.Brush textWhiteBrush,
            System.Windows.Media.Brush iconBadgeBg,
            System.Windows.Media.Brush iconBadgeLightBg,
            System.Windows.Media.Brush iconBadgeBorder,
            System.Windows.Media.Brush updBadgeBg,
            System.Windows.Media.Brush updBadgeBorder,
            System.Windows.Media.Brush updBadgeFg,
            System.Windows.Media.Brush linkIconFg,
            BitmapSource preCachedIcon)
        {
            var rowBorder = new Border();
            rowBorder.Height = 27;
            rowBorder.CornerRadius = _ccRow;
            rowBorder.Padding = _ctRowPad;
            rowBorder.Margin = _ctRowMgn;
            if (rowStyle != null) rowBorder.Style = rowStyle;
            rowBorder.Cursor = Cursors.Hand;
            if (!string.IsNullOrEmpty(rowToolTip)) {
                rowBorder.ToolTip = rowToolTip;
                ToolTipService.SetInitialShowDelay(rowBorder, 5000);
            }

            var rowGrid = new Grid();
            rowGrid.VerticalAlignment = VerticalAlignment.Center;
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _cCol0 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _cCol1 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _cCol2 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _cCol3 });

            var cb = new CheckBox();
            cb.VerticalAlignment = VerticalAlignment.Center;
            cb.HorizontalAlignment = HorizontalAlignment.Left;
            cb.Margin = _tZero;
            Grid.SetColumn(cb, 0);
            rowGrid.Children.Add(cb);

            var iconBadge = new Border();
            iconBadge.Width = 20;
            iconBadge.Height = 20;
            iconBadge.CornerRadius = _ccRow;
            iconBadge.Background = (preCachedIcon != null && useLightBadge) ? iconBadgeLightBg : iconBadgeBg;
            iconBadge.BorderBrush = iconBadgeBorder;
            iconBadge.BorderThickness = _tZero;
            iconBadge.HorizontalAlignment = HorizontalAlignment.Center;
            iconBadge.VerticalAlignment = VerticalAlignment.Center;

            var iconInnerGrid = new Grid();
            iconInnerGrid.Width = 20;
            iconInnerGrid.Height = 20;
            iconInnerGrid.HorizontalAlignment = HorizontalAlignment.Center;
            iconInnerGrid.VerticalAlignment = VerticalAlignment.Center;

            var fallbackGlyph = new TextBlock();
            fallbackGlyph.Text = fallbackGlyphText ?? "";
            if (fontSegoeEmoji != null) fallbackGlyph.FontFamily = fontSegoeEmoji;
            fallbackGlyph.FontSize = 10;
            fallbackGlyph.HorizontalAlignment = HorizontalAlignment.Center;
            fallbackGlyph.VerticalAlignment = VerticalAlignment.Center;

            var img = new System.Windows.Controls.Image();
            double imgDim = useLightBadge ? 15.0 : 17.0;
            img.Width = imgDim;
            img.Height = imgDim;
            img.Stretch = Stretch.Uniform;
            RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.LowQuality);
            img.HorizontalAlignment = HorizontalAlignment.Center;
            img.VerticalAlignment = VerticalAlignment.Center;

            if (preCachedIcon != null) {
                img.Source = preCachedIcon;
                img.Visibility = Visibility.Visible;
                fallbackGlyph.Visibility = Visibility.Collapsed;
            } else {
                img.Visibility = Visibility.Collapsed;
            }

            iconInnerGrid.Children.Add(fallbackGlyph);
            iconInnerGrid.Children.Add(img);
            iconBadge.Child = iconInnerGrid;
            Grid.SetColumn(iconBadge, 1);
            rowGrid.Children.Add(iconBadge);

            var nameAreaGrid = new Grid();
            nameAreaGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _cCol2 });
            nameAreaGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _cAuto });

            var nameText = new TextBlock();
            nameText.Text = appName ?? "";
            nameText.Foreground = textWhiteBrush;
            nameText.FontSize = 12;
            nameText.FontWeight = FontWeights.SemiBold;
            nameText.VerticalAlignment = VerticalAlignment.Center;
            nameText.Margin = _ctNameMgn;
            nameText.TextTrimming = TextTrimming.CharacterEllipsis;
            Grid.SetColumn(nameText, 0);
            nameAreaGrid.Children.Add(nameText);

            var updateBadge = new Border();
            updateBadge.Background = updBadgeBg;
            updateBadge.BorderBrush = updBadgeBorder;
            updateBadge.BorderThickness = _tOne;
            updateBadge.CornerRadius = _ccRow;
            updateBadge.Padding = _ctUpdPad;
            updateBadge.Margin = _ctUpdMgn;
            updateBadge.VerticalAlignment = VerticalAlignment.Center;
            updateBadge.Visibility = Visibility.Collapsed;
            updateBadge.MaxWidth = 86;

            var updateText = new TextBlock();
            updateText.FontSize = 9.5;
            updateText.FontWeight = FontWeights.Bold;
            updateText.Foreground = updBadgeFg;
            updateText.TextTrimming = TextTrimming.CharacterEllipsis;
            updateBadge.Child = updateText;
            Grid.SetColumn(updateBadge, 1);
            nameAreaGrid.Children.Add(updateBadge);

            Grid.SetColumn(nameAreaGrid, 2);
            rowGrid.Children.Add(nameAreaGrid);

            var linkBtn = new Border();
            linkBtn.Width = 20;
            linkBtn.Height = 19;
            linkBtn.CornerRadius = _cFour;
            if (linkBtnStyle != null) linkBtn.Style = linkBtnStyle;
            linkBtn.BorderThickness = _tOne;
            linkBtn.Cursor = Cursors.Hand;
            linkBtn.HorizontalAlignment = HorizontalAlignment.Right;
            linkBtn.VerticalAlignment = VerticalAlignment.Center;
            linkBtn.Margin = _tZero;
            linkBtn.ToolTip = "M\u1EDF trang ch\u00EDnh th\u1EE9c: " + (targetPageUrl ?? "");
            ToolTipService.SetInitialShowDelay(linkBtn, 5000);
            linkBtn.Tag = targetPageUrl ?? "";

            var linkIcon = new TextBlock();
            linkIcon.Text = "\u2197";
            if (fontSegoeUI != null) linkIcon.FontFamily = fontSegoeUI;
            linkIcon.FontSize = 11.5;
            linkIcon.FontWeight = FontWeights.Bold;
            linkIcon.Foreground = linkIconFg;
            linkIcon.HorizontalAlignment = HorizontalAlignment.Center;
            linkIcon.VerticalAlignment = VerticalAlignment.Center;
            linkIcon.Margin = _ctLinkMgn;
            linkBtn.Child = linkIcon;

            Grid.SetColumn(linkBtn, 3);
            rowGrid.Children.Add(linkBtn);

            rowBorder.Child = rowGrid;

            return new CatalogRowVisual {
                RowBorder = rowBorder,
                CheckBox = cb,
                IconBadge = iconBadge,
                IconImg = img,
                FallbackGlyph = fallbackGlyph,
                NameText = nameText,
                UpdateBadge = updateBadge,
                UpdateText = updateText,
                LinkBtn = linkBtn,
                LinkIcon = linkIcon
            };
        }
    }
}
