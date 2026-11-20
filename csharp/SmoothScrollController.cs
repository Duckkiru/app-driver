using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace DuckUtil {
    public static class ConsoleHelper {
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
        public static void DisableQuickEdit() {
            IntPtr h = GetStdHandle(-10);
            if (h == IntPtr.Zero || h == new IntPtr(-1)) return;
            uint mode;
            if (GetConsoleMode(h, out mode)) {
                uint next = (mode & ~0x0040u) | 0x0080u;
                if (next != mode) SetConsoleMode(h, next);
            }
        }
    }

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

            double step = -e.Delta * 0.90;
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

            if (Math.Abs(diff) < 0.25) {
                _currentOffset = _targetOffset;
                _lastAppliedOffset = _currentOffset;
                _pendingLayoutSyncFrames = 0;
                _sv.ScrollToVerticalOffset(_currentOffset);
                StopAnimation();
                return;
            }

            double factor = 1.0 - Math.Exp(-16.0 * dt);
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

    public sealed class SmoothAccordionItem {
        private readonly FrameworkElement _host;
        private readonly RotateTransform _chevronRotate;
        private readonly TranslateTransform _slideTransform;
        private readonly double _expandedHeight;
        private readonly Stopwatch _sw = new Stopwatch();
        private double _currentHeight;
        private double _targetHeight;
        private double _currentAngle;
        private double _targetAngle;
        private double _lastTimeSec;
        private bool _isExpanded;
        private bool _isAnimating;
        private bool _firstFramePending;

        private SmoothAccordionItem(FrameworkElement host, RotateTransform chevronRotate, TranslateTransform slideTransform, double expandedHeight) {
            _host = host;
            _chevronRotate = chevronRotate;
            _slideTransform = slideTransform;
            _expandedHeight = Math.Max(1.0, expandedHeight);
            _host.Unloaded += OnUnloaded;
        }

        public static SmoothAccordionItem Attach(FrameworkElement host, RotateTransform chevronRotate, TranslateTransform slideTransform, double expandedHeight) {
            if (host == null) return null;
            return new SmoothAccordionItem(host, chevronRotate, slideTransform, expandedHeight);
        }

        private void OnUnloaded(object sender, RoutedEventArgs e) {
            Stop();
        }

        public void SetExpanded(bool expanded, bool animate) {
            _isExpanded = expanded;
            _targetHeight = expanded ? _expandedHeight : 0.0;
            _targetAngle = expanded ? 90.0 : 0.0;

            if (!animate) {
                Stop();
                ApplyValues(_targetHeight, _targetAngle);
                _host.Visibility = expanded ? Visibility.Visible : Visibility.Collapsed;
                return;
            }

            if (expanded && _host.Visibility != Visibility.Visible) {
                _host.Visibility = Visibility.Visible;
            }

            if (Math.Abs(_targetHeight - _currentHeight) < 0.25 && Math.Abs(_targetAngle - _currentAngle) < 0.25) {
                Stop();
                ApplyValues(_targetHeight, _targetAngle);
                if (!_isExpanded) _host.Visibility = Visibility.Collapsed;
                return;
            }

            if (!_isAnimating) {
                _isAnimating = true;
                _firstFramePending = true;
                _sw.Restart();
                _lastTimeSec = 0.0;
                CompositionTarget.Rendering += OnRendering;
            }
        }

        private void OnRendering(object sender, EventArgs e) {
            if (!_host.IsLoaded) {
                Stop();
                return;
            }

            double nowSec = _sw.Elapsed.TotalSeconds;
            double dt;
            if (_firstFramePending) {
                _firstFramePending = false;
                _lastTimeSec = nowSec;
                dt = 0.010;
            } else {
                dt = nowSec - _lastTimeSec;
                _lastTimeSec = nowSec;
                if (double.IsNaN(dt) || double.IsInfinity(dt) || dt <= 0.0) dt = 0.016;
                else if (dt > 0.018) dt = 0.018;
            }

            double dh = _targetHeight - _currentHeight;
            double da = _targetAngle - _currentAngle;
            if (Math.Abs(dh) < 0.35 && Math.Abs(da) < 0.35) {
                ApplyValues(_targetHeight, _targetAngle);
                if (!_isExpanded) {
                    _host.Visibility = Visibility.Collapsed;
                }
                Stop();
                return;
            }

            double factor = 1.0 - Math.Exp(-12.5 * dt);
            _currentHeight += dh * factor;
            _currentAngle += da * factor;
            ApplyValues(_currentHeight, _currentAngle);
        }

        private void ApplyValues(double h, double angle) {
            _currentHeight = Math.Max(0.0, Math.Min(_expandedHeight, h));
            _currentAngle = angle;
            double ratio = _expandedHeight > 0.0 ? Math.Max(0.0, Math.Min(1.0, _currentHeight / _expandedHeight)) : 1.0;
            _host.Height = _currentHeight;
            _host.Opacity = Math.Pow(ratio, 0.72);
            if (_slideTransform != null) {
                _slideTransform.Y = -6.0 * (1.0 - ratio);
            }
            if (_chevronRotate != null) {
                _chevronRotate.Angle = _currentAngle;
            }
        }

        private void Stop() {
            if (_isAnimating) {
                _isAnimating = false;
                CompositionTarget.Rendering -= OnRendering;
                _sw.Stop();
            }
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
        private static readonly ConcurrentStack<UninstIconJob> _uninstJobs = new ConcurrentStack<UninstIconJob>();

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
            _uninstJobs.Clear();
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

        private static void WriteBytesAtomic(string destPath, byte[] data) {
            if (string.IsNullOrEmpty(destPath) || data == null || data.Length == 0 || File.Exists(destPath)) return;
            string tmpPath = destPath + ".tmp." + Guid.NewGuid().ToString("N");
            try {
                string dir = Path.GetDirectoryName(destPath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir)) Directory.CreateDirectory(dir);
                File.WriteAllBytes(tmpPath, data);
                if (!File.Exists(destPath)) {
                    File.Move(tmpPath, destPath);
                }
            } catch {
            } finally {
                try { if (File.Exists(tmpPath)) File.Delete(tmpPath); } catch {}
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
                                if (ready != null) {
                                    WriteBytesAtomic(job.DestPath, dl);
                                }
                            }
                            if (ready == null && !string.IsNullOrWhiteSpace(job.FallbackUrl) && Volatile.Read(ref _remoteGen) == gen) {
                                byte[] dl2 = DownloadBytesWithTimeout(job.FallbackUrl, 2500);
                                if (dl2 != null && dl2.Length > 230 && dl2.Length != 588) {
                                    ready = DecodeFrozenPngOrIcoBitmap(dl2);
                                    if (ready != null) {
                                        WriteBytesAtomic(job.DestPath, dl2);
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
                    if (!_uninstJobs.TryPop(out job)) break;
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
                if (!_uninstJobs.IsEmpty) EnsureUninstWorkers(3);
            }
        }

        public static void EnqueueUninstallerIcons(int[] indices, string[] targetPaths) {
            if (indices == null || targetPaths == null || indices.Length == 0) return;
            int gen = Volatile.Read(ref _uninstGen);
            int queued = 0;
            for (int k = indices.Length - 1; k >= 0; k--) {
                if (k >= targetPaths.Length) continue;
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
                _uninstJobs.Push(new UninstIconJob {
                    Index = indices[k],
                    Generation = gen,
                    TargetPath = p
                });
                queued++;
            }
            if (queued > 0) {
                EnsureUninstWorkers(Math.Min(3, queued));
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
        private static readonly Thickness _tBadgePad = new Thickness(8, 0, 8, 2);
        private static readonly CornerRadius _cRow = new CornerRadius(0);
        private static readonly CornerRadius _cFour = new CornerRadius(1);
        private static readonly CornerRadius _cPill = new CornerRadius(3);

        internal static TextBlock CreateCenteredBadgeLabel(string text, double fontSize, FontWeight weight, System.Windows.Media.Brush fg) {
            var tb = new TextBlock();
            tb.Text = text ?? "";
            tb.FontSize = fontSize;
            tb.FontWeight = weight;
            tb.Foreground = fg;
            tb.HorizontalAlignment = HorizontalAlignment.Center;
            tb.VerticalAlignment = VerticalAlignment.Center;
            tb.TextAlignment = TextAlignment.Center;
            TextOptions.SetTextFormattingMode(tb, TextFormattingMode.Display);
            return tb;
        }

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
            statusBorder.CornerRadius = _cPill;
            statusBorder.Height = 22;
            statusBorder.Padding = _tBadgePad;
            statusBorder.HorizontalAlignment = HorizontalAlignment.Center;
            statusBorder.VerticalAlignment = VerticalAlignment.Center;
            statusBorder.BorderThickness = _tOne;
            statusBorder.Background = isBrokenOrphan ? statusBrokenBg : statusOkBg;
            statusBorder.BorderBrush = isBrokenOrphan ? statusBrokenBorder : statusOkBorder;

            var statusTb = CreateCenteredBadgeLabel(
                isBrokenOrphan ? "L\u1ED7i / C\u00F2n s\u00F3t" : "B\u00ECnh th\u01B0\u1EDDng",
                10.5,
                FontWeights.SemiBold,
                isBrokenOrphan ? badgeBrokenFg : statusOkFg);
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
        private static readonly Thickness _ctUpdPad = new Thickness(5, 0, 5, 0);
        private static readonly Thickness _ctUpdMgn = new Thickness(2, 0, 4, 0);
        private static readonly Thickness _ctLinkMgn = new Thickness(0, -1, 0, 0);
        private static readonly CornerRadius _ccRow = new CornerRadius(2);

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
            rowBorder.SnapsToDevicePixels = true;
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
            updateBadge.Height = 18;
            updateBadge.Padding = _ctUpdPad;
            updateBadge.Margin = _ctUpdMgn;
            updateBadge.VerticalAlignment = VerticalAlignment.Center;
            updateBadge.Visibility = Visibility.Collapsed;
            updateBadge.MaxWidth = 86;

            var updateText = CreateCenteredBadgeLabel("", 9.5, FontWeights.Bold, updBadgeFg);
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

        private static readonly Thickness _loItemMgn = new Thickness(0, 0, 0, 6);
        private static readonly Thickness _loItemPad = new Thickness(10, 8, 10, 8);
        private static readonly Thickness _loCbMgn = new Thickness(0, 0, 10, 0);
        private static readonly Thickness _loBadgePad = new Thickness(8, 0, 8, 3);
        private static readonly Thickness _loConfPad = new Thickness(7, 0, 7, 2);
        private static readonly Thickness _loConfMgn = new Thickness(6, 0, 0, 0);
        private static readonly Thickness _loSizeMgn = new Thickness(10, 0, 8, 0);
        private static readonly Thickness _loBtnPad = new Thickness(10, 0, 10, 1);
        private static readonly CornerRadius _loItemCr = new CornerRadius(2);
        private static readonly CornerRadius _loPillCr = new CornerRadius(3);

        public static Border CreateLeftoverItemRow(
            object tagItem,
            string typeText,
            string confText,
            string appName,
            string displayPath,
            string sizeText,
            bool isRegistry,
            System.Windows.Media.Brush itemBg,
            System.Windows.Media.Brush itemBorder,
            System.Windows.Media.Brush badgeBg,
            System.Windows.Media.Brush whiteBrush,
            System.Windows.Media.Brush confBg,
            System.Windows.Media.Brush confBorder,
            System.Windows.Media.Brush confFg,
            System.Windows.Media.Brush titleFg,
            System.Windows.Media.Brush pathFg,
            System.Windows.Media.Brush sizeRegFg,
            System.Windows.Media.Brush sizeFileFg,
            System.Windows.Media.Brush btnBg,
            System.Windows.Media.Brush btnFg,
            out CheckBox outCheckBox,
            out Button outOpenBtn)
        {
            var itemBorderEl = new Border();
            itemBorderEl.Background = itemBg;
            itemBorderEl.BorderBrush = itemBorder;
            itemBorderEl.BorderThickness = _tOne;
            itemBorderEl.CornerRadius = _loItemCr;
            itemBorderEl.Margin = _loItemMgn;
            itemBorderEl.Padding = _loItemPad;

            var itemGrid = new Grid();
            itemGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _cAuto });
            itemGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _cAuto });
            itemGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _uCol1 });
            itemGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _cAuto });
            itemGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _cAuto });

            var cb = new CheckBox();
            cb.IsChecked = true;
            cb.Tag = tagItem;
            cb.VerticalAlignment = VerticalAlignment.Center;
            cb.Margin = _loCbMgn;
            Grid.SetColumn(cb, 0);
            itemGrid.Children.Add(cb);

            var badgeGrid = new Grid();
            badgeGrid.VerticalAlignment = VerticalAlignment.Center;
            badgeGrid.Margin = _loCbMgn;
            badgeGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _cAuto, SharedSizeGroup = "LoTypeCol" });
            badgeGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _cAuto, SharedSizeGroup = "LoConfCol" });

            var badgeBorder = new Border();
            badgeBorder.Background = badgeBg;
            badgeBorder.CornerRadius = _loPillCr;
            badgeBorder.Height = 22;
            badgeBorder.Padding = _loBadgePad;
            badgeBorder.HorizontalAlignment = HorizontalAlignment.Left;
            badgeBorder.VerticalAlignment = VerticalAlignment.Center;
            var badgeTb = CreateCenteredBadgeLabel(typeText ?? "", 10.5, FontWeights.SemiBold, whiteBrush);
            badgeBorder.Child = badgeTb;
            Grid.SetColumn(badgeBorder, 0);
            badgeGrid.Children.Add(badgeBorder);

            var confBorderEl = new Border();
            confBorderEl.Background = confBg;
            confBorderEl.BorderBrush = confBorder;
            confBorderEl.BorderThickness = _tOne;
            confBorderEl.CornerRadius = _loPillCr;
            confBorderEl.Height = 22;
            confBorderEl.Padding = _loConfPad;
            confBorderEl.Margin = _loConfMgn;
            confBorderEl.HorizontalAlignment = HorizontalAlignment.Left;
            confBorderEl.VerticalAlignment = VerticalAlignment.Center;
            var confTb = CreateCenteredBadgeLabel(string.IsNullOrEmpty(confText) ? "An to\u00E0n 100%" : confText, 10.0, FontWeights.SemiBold, confFg);
            confBorderEl.Child = confTb;
            Grid.SetColumn(confBorderEl, 1);
            badgeGrid.Children.Add(confBorderEl);

            Grid.SetColumn(badgeGrid, 1);
            itemGrid.Children.Add(badgeGrid);

            var infoPanel = new StackPanel();
            infoPanel.VerticalAlignment = VerticalAlignment.Center;
            var appTb = new TextBlock();
            appTb.Text = appName ?? "";
            appTb.FontWeight = FontWeights.SemiBold;
            appTb.Foreground = titleFg;
            infoPanel.Children.Add(appTb);

            var pathTb = new TextBlock();
            pathTb.Text = displayPath ?? "";
            pathTb.FontSize = 11;
            pathTb.Foreground = pathFg;
            pathTb.TextTrimming = TextTrimming.CharacterEllipsis;
            pathTb.ToolTip = displayPath ?? "";
            infoPanel.Children.Add(pathTb);

            Grid.SetColumn(infoPanel, 2);
            itemGrid.Children.Add(infoPanel);

            var sizeTb = new TextBlock();
            sizeTb.VerticalAlignment = VerticalAlignment.Center;
            sizeTb.FontSize = 11.5;
            sizeTb.FontWeight = FontWeights.SemiBold;
            sizeTb.Margin = _loSizeMgn;
            sizeTb.Text = isRegistry ? "Registry" : (sizeText ?? "0.00 MB");
            sizeTb.Foreground = isRegistry ? sizeRegFg : sizeFileFg;
            Grid.SetColumn(sizeTb, 3);
            itemGrid.Children.Add(sizeTb);

            var openBtn = new Button();
            openBtn.Content = "M\u1EDF v\u1ECB tr\u00ED";
            openBtn.FontSize = 10.5;
            openBtn.Height = 24;
            openBtn.Padding = _loBtnPad;
            openBtn.VerticalAlignment = VerticalAlignment.Center;
            openBtn.VerticalContentAlignment = VerticalAlignment.Center;
            openBtn.HorizontalContentAlignment = HorizontalAlignment.Center;
            openBtn.Background = btnBg;
            openBtn.Foreground = btnFg;
            openBtn.Tag = tagItem;
            Grid.SetColumn(openBtn, 4);
            itemGrid.Children.Add(openBtn);

            itemBorderEl.Child = itemGrid;
            outCheckBox = cb;
            outOpenBtn = openBtn;
            return itemBorderEl;
        }

        public static void DistributeRowsToColumns(Panel rowsStack, Panel[] cols, System.Collections.IList rows) {
            if (cols == null || cols.Length == 0 || rows == null) return;
            for (int c = 0; c < cols.Length; c++) {
                if (cols[c] != null) cols[c].Children.Clear();
            }
            if (rowsStack != null) {
                rowsStack.Children.Clear();
            }
            int n = rows.Count;
            int colCnt = cols.Length;
            int baseCnt = n / colCnt;
            int rem = n % colCnt;
            int offset = 0;
            for (int ci = 0; ci < colCnt; ci++) {
                int take = baseCnt + (ci < rem ? 1 : 0);
                Panel cp = cols[ci];
                for (int k = 0; k < take && (offset + k) < n; k++) {
                    UIElement el = rows[offset + k] as UIElement;
                    if (el != null && cp != null) cp.Children.Add(el);
                }
                offset += take;
            }
        }

        public static void RestoreRowsFromColumns(Panel rowsStack, Panel[] cols, System.Collections.IList rows) {
            if (cols != null) {
                for (int c = 0; c < cols.Length; c++) {
                    if (cols[c] != null) cols[c].Children.Clear();
                }
            }
            if (rowsStack != null && rows != null) {
                rowsStack.Children.Clear();
                for (int i = 0; i < rows.Count; i++) {
                    UIElement el = rows[i] as UIElement;
                    if (el != null) rowsStack.Children.Add(el);
                }
            }
        }

        private static readonly HttpClient _downloadClient = CreateDownloadClient();

        private static HttpClient CreateDownloadClient() {
            if (Environment.Version.Major == 4) {
                try {
                    Type spm = Type.GetType("System.Net.ServicePointManager, System");
                    if (spm != null) {
                        PropertyInfo prop = spm.GetProperty("SecurityProtocol", BindingFlags.Public | BindingFlags.Static);
                        if (prop != null) {
                            int cur = Convert.ToInt32(prop.GetValue(null, null));
                            object val = Enum.ToObject(prop.PropertyType, cur | 3072);
                            prop.SetValue(null, val, null);
                        }
                    }
                } catch {}
            }
            var handler = new HttpClientHandler();
            try { handler.AllowAutoRedirect = true; } catch {}
            var client = new HttpClient(handler);
            client.Timeout = TimeSpan.FromMinutes(3);
            try { client.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "DuckUtil"); } catch {}
            return client;
        }

        public static string NormalizeSearchFold(string input) {
            if (string.IsNullOrWhiteSpace(input)) return "";
            string norm = input.Normalize(NormalizationForm.FormD);
            var sb = new StringBuilder(norm.Length);
            bool prevSpace = true;
            for (int i = 0; i < norm.Length; i++) {
                char ch = norm[i];
                if (ch == '\u0111' || ch == '\u0110') {
                    sb.Append('d');
                    prevSpace = false;
                    continue;
                }
                UnicodeCategory uc = CharUnicodeInfo.GetUnicodeCategory(ch);
                if (uc == UnicodeCategory.NonSpacingMark) continue;
                if (ch >= 'A' && ch <= 'Z') {
                    sb.Append((char)(ch + 32));
                    prevSpace = false;
                } else if ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9')) {
                    sb.Append(ch);
                    prevSpace = false;
                } else if (!prevSpace) {
                    sb.Append(' ');
                    prevSpace = true;
                }
            }
            if (sb.Length > 0 && sb[sb.Length - 1] == ' ') sb.Length--;
            return sb.ToString();
        }

        public static string CompactSearchAlnum(string folded) {
            if (string.IsNullOrEmpty(folded)) return "";
            var sb = new StringBuilder(folded.Length);
            for (int i = 0; i < folded.Length; i++) {
                char c = folded[i];
                if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) sb.Append(c);
            }
            return sb.ToString();
        }

        public static string[] SplitFoldedTokens(string folded) {
            if (string.IsNullOrEmpty(folded)) return new string[0];
            return folded.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
        }

        private static int BoundedDamerauDistance(string a, string b, int maxDist) {
            int n = a.Length;
            int m = b.Length;
            if (Math.Abs(n - m) > maxDist) return maxDist + 1;
            int[] prevPrev = new int[m + 1];
            int[] prev = new int[m + 1];
            int[] curr = new int[m + 1];
            for (int j = 0; j <= m; j++) prev[j] = j;
            for (int i = 1; i <= n; i++) {
                curr[0] = i;
                int rowMin = curr[0];
                char ai = a[i - 1];
                for (int j = 1; j <= m; j++) {
                    char bj = b[j - 1];
                    int cost = (ai == bj) ? 0 : 1;
                    int val = Math.Min(Math.Min(curr[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
                    if (i > 1 && j > 1 && ai == b[j - 2] && a[i - 2] == bj) {
                        int trans = prevPrev[j - 2] + 1;
                        if (trans < val) val = trans;
                    }
                    curr[j] = val;
                    if (val < rowMin) rowMin = val;
                }
                if (rowMin > maxDist) return maxDist + 1;
                int[] tmp = prevPrev;
                prevPrev = prev;
                prev = curr;
                curr = tmp;
            }
            return prev[m];
        }

        public static int ScoreSearchQuery(
            string foldedQuery,
            string compactQuery,
            string[] qTokens,
            string foldedName,
            string compactName,
            string foldedHaystack,
            string compactHaystack,
            string[] nameWords)
        {
            if (string.IsNullOrEmpty(foldedQuery)) return 1;
            if (foldedName == foldedQuery || (!string.IsNullOrEmpty(compactQuery) && compactName == compactQuery)) {
                return 1000;
            }
            if (!string.IsNullOrEmpty(foldedName)) {
                if (foldedName.StartsWith(foldedQuery, StringComparison.Ordinal)) return 880;
                if (!string.IsNullOrEmpty(compactQuery) && compactQuery.Length >= 2 && compactName.StartsWith(compactQuery, StringComparison.Ordinal)) return 840;
                if (foldedName.IndexOf(" " + foldedQuery, StringComparison.Ordinal) >= 0) return 760;
                if (foldedName.IndexOf(foldedQuery, StringComparison.Ordinal) >= 0) return 700;
                if (!string.IsNullOrEmpty(compactQuery) && compactQuery.Length >= 3 && compactName.IndexOf(compactQuery, StringComparison.Ordinal) >= 0) return 680;
            }
            if (!string.IsNullOrEmpty(foldedHaystack)) {
                if (foldedHaystack.IndexOf(foldedQuery, StringComparison.Ordinal) >= 0) return 610;
                if (!string.IsNullOrEmpty(compactQuery) && compactQuery.Length >= 3 && compactHaystack.IndexOf(compactQuery, StringComparison.Ordinal) >= 0) return 580;
            }
            if (qTokens != null && qTokens.Length >= 2 && !string.IsNullOrEmpty(foldedHaystack)) {
                int hits = 0;
                int nameHits = 0;
                for (int qi = 0; qi < qTokens.Length; qi++) {
                    string qt = qTokens[qi];
                    if (foldedHaystack.IndexOf(qt, StringComparison.Ordinal) >= 0) {
                        hits++;
                        if (!string.IsNullOrEmpty(foldedName) && foldedName.IndexOf(qt, StringComparison.Ordinal) >= 0) nameHits++;
                    }
                }
                if (hits == qTokens.Length) return 500 + Math.Min(80, nameHits * 25);
            }
            if (qTokens != null && qTokens.Length == 1 && nameWords != null && nameWords.Length > 0) {
                string qt = qTokens[0];
                int maxDist = qt.Length >= 7 ? 2 : (qt.Length >= 4 ? 1 : 0);
                if (maxDist > 0) {
                    int bestDist = maxDist + 1;
                    for (int wi = 0; wi < nameWords.Length; wi++) {
                        string w = nameWords[wi];
                        if (w.Length < 3) continue;
                        int d = BoundedDamerauDistance(qt, w, maxDist);
                        if (d < bestDist) bestDist = d;
                    }
                    if (bestDist <= maxDist) return 420 - (bestDist * 60);
                }
            }
            return 0;
        }

        private static void SkipJsonWhitespace(string json, ref int pos) {
            while (pos < json.Length) {
                char c = json[pos];
                if (c == ' ' || c == '\t' || c == '\r' || c == '\n') pos++;
                else break;
            }
        }

        private static string ReadJsonString(string json, ref int pos) {
            if (pos >= json.Length || json[pos] != '"') return "";
            pos++;
            var sb = new StringBuilder();
            while (pos < json.Length) {
                char c = json[pos++];
                if (c == '"') break;
                if (c == '\\' && pos < json.Length) {
                    char n = json[pos++];
                    if (n == '"' || n == '\\' || n == '/') sb.Append(n);
                    else if (n == 'n') sb.Append('\n');
                    else if (n == 'r') sb.Append('\r');
                    else if (n == 't') sb.Append('\t');
                    else if (n == 'b') sb.Append('\b');
                    else if (n == 'f') sb.Append('\f');
                    else if (n == 'u' && pos + 3 < json.Length) {
                        int code;
                        if (int.TryParse(json.Substring(pos, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out code)) {
                            sb.Append((char)code);
                            pos += 4;
                        }
                    } else {
                        sb.Append(n);
                    }
                } else {
                    sb.Append(c);
                }
            }
            return sb.ToString();
        }

        private static void SkipJsonValue(string json, ref int pos) {
            SkipJsonWhitespace(json, ref pos);
            if (pos >= json.Length) return;
            char c = json[pos];
            if (c == '"') {
                ReadJsonString(json, ref pos);
                return;
            }
            if (c == '{' || c == '[') {
                int depth = 0;
                while (pos < json.Length) {
                    char ch = json[pos];
                    if (ch == '"') {
                        ReadJsonString(json, ref pos);
                        continue;
                    }
                    if (ch == '{' || ch == '[') depth++;
                    else if (ch == '}' || ch == ']') {
                        depth--;
                        pos++;
                        if (depth <= 0) break;
                        continue;
                    }
                    pos++;
                }
                return;
            }
            while (pos < json.Length) {
                char ch = json[pos];
                if (ch == ',' || ch == '}' || ch == ']' || ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') break;
                pos++;
            }
        }

        public static string FindGitHubReleaseAssetUrl(string json, string assetRegex, out string matchedName) {
            matchedName = "";
            if (string.IsNullOrWhiteSpace(json) || string.IsNullOrWhiteSpace(assetRegex)) return "";
            Regex rxAsset = new Regex(assetRegex, RegexOptions.IgnoreCase);
            int pos = 0;
            SkipJsonWhitespace(json, ref pos);
            if (pos >= json.Length || json[pos] != '{') return "";
            pos++;
            while (pos < json.Length) {
                SkipJsonWhitespace(json, ref pos);
                if (pos >= json.Length || json[pos] == '}') break;
                if (json[pos] == ',') { pos++; continue; }
                if (json[pos] != '"') break;
                string rootKey = ReadJsonString(json, ref pos);
                SkipJsonWhitespace(json, ref pos);
                if (pos >= json.Length || json[pos] != ':') break;
                pos++;
                if (string.Equals(rootKey, "assets", StringComparison.Ordinal)) {
                    SkipJsonWhitespace(json, ref pos);
                    if (pos < json.Length && json[pos] == '[') {
                        pos++;
                        while (pos < json.Length) {
                            SkipJsonWhitespace(json, ref pos);
                            if (pos >= json.Length || json[pos] == ']') break;
                            if (json[pos] == ',') { pos++; continue; }
                            if (json[pos] != '{') {
                                SkipJsonValue(json, ref pos);
                                continue;
                            }
                            pos++;
                            string candName = "";
                            string candUrl = "";
                            while (pos < json.Length) {
                                SkipJsonWhitespace(json, ref pos);
                                if (pos >= json.Length) break;
                                if (json[pos] == '}') { pos++; break; }
                                if (json[pos] == ',') { pos++; continue; }
                                if (json[pos] != '"') {
                                    SkipJsonValue(json, ref pos);
                                    continue;
                                }
                                string aKey = ReadJsonString(json, ref pos);
                                SkipJsonWhitespace(json, ref pos);
                                if (pos >= json.Length || json[pos] != ':') break;
                                pos++;
                                SkipJsonWhitespace(json, ref pos);
                                if ((string.Equals(aKey, "name", StringComparison.Ordinal) || string.Equals(aKey, "browser_download_url", StringComparison.Ordinal)) && pos < json.Length && json[pos] == '"') {
                                    string aVal = ReadJsonString(json, ref pos);
                                    if (string.Equals(aKey, "name", StringComparison.Ordinal)) candName = aVal;
                                    else candUrl = aVal;
                                } else {
                                    SkipJsonValue(json, ref pos);
                                }
                            }
                            if (!string.IsNullOrWhiteSpace(candName) && !string.IsNullOrWhiteSpace(candUrl) && rxAsset.IsMatch(candName)) {
                                matchedName = candName;
                                return candUrl;
                            }
                        }
                    }
                    return "";
                } else {
                    SkipJsonValue(json, ref pos);
                }
            }
            return "";
        }

        public static async Task<string> PrefetchGitHubReleaseAssetDetailedAsync(string repo, string assetRegex, string destDir, CancellationToken ct) {
            if (string.IsNullOrWhiteSpace(repo) || string.IsNullOrWhiteSpace(assetRegex) || string.IsNullOrWhiteSpace(destDir)) return "SKIP|invalid-args";
            string outFile = "";
            try {
                ct.ThrowIfCancellationRequested();
                string apiUrl = "https://api.github.com/repos/" + repo.Trim('/') + "/releases/latest";
                string json = "";
                using (HttpResponseMessage apiResp = await _downloadClient.GetAsync(apiUrl, HttpCompletionOption.ResponseContentRead, ct).ConfigureAwait(false)) {
                    if (!apiResp.IsSuccessStatusCode || apiResp.Content == null) {
                        return "ERR|http-" + ((int)apiResp.StatusCode).ToString(CultureInfo.InvariantCulture);
                    }
                    json = await apiResp.Content.ReadAsStringAsync().ConfigureAwait(false);
                }
                if (string.IsNullOrEmpty(json)) return "ERR|empty-response";

                string matchedName;
                string matchedUrl = FindGitHubReleaseAssetUrl(json, assetRegex, out matchedName);
                if (string.IsNullOrWhiteSpace(matchedName) || string.IsNullOrWhiteSpace(matchedUrl)) return "SKIP|no-matching-asset";
                string safeName = Path.GetFileName(matchedName);
                if (string.IsNullOrWhiteSpace(safeName)) return "SKIP|invalid-asset-name";
                bool isInstaller = safeName.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) || safeName.EndsWith(".msi", StringComparison.OrdinalIgnoreCase);
                if (!isInstaller || !matchedUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) return "SKIP|non-installer:" + safeName;

                ct.ThrowIfCancellationRequested();
                Directory.CreateDirectory(destDir);
                outFile = Path.Combine(destDir, safeName);
                using (HttpResponseMessage dlResp = await _downloadClient.GetAsync(matchedUrl, HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false)) {
                    if (!dlResp.IsSuccessStatusCode || dlResp.Content == null) {
                        return "ERR|download-http-" + ((int)dlResp.StatusCode).ToString(CultureInfo.InvariantCulture);
                    }
                    using (Stream src = await dlResp.Content.ReadAsStreamAsync().ConfigureAwait(false))
                    using (var dst = new FileStream(outFile, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true)) {
                        byte[] buf = new byte[81920];
                        int r;
                        while ((r = await src.ReadAsync(buf, 0, buf.Length, ct).ConfigureAwait(false)) > 0) {
                            await dst.WriteAsync(buf, 0, r, ct).ConfigureAwait(false);
                        }
                    }
                }
                if (File.Exists(outFile)) {
                    FileInfo fi = new FileInfo(outFile);
                    if (fi.Length > 0) return "OK|" + outFile;
                }
                return "ERR|empty-file";
            } catch (OperationCanceledException) {
                try { if (!string.IsNullOrEmpty(outFile) && File.Exists(outFile)) File.Delete(outFile); } catch {}
                try { if (Directory.Exists(destDir)) Directory.Delete(destDir, true); } catch {}
                return "ERR|canceled";
            } catch (Exception ex) {
                try { if (!string.IsNullOrEmpty(outFile) && File.Exists(outFile)) File.Delete(outFile); } catch {}
                try { if (Directory.Exists(destDir)) Directory.Delete(destDir, true); } catch {}
                return "ERR|" + (ex.Message ?? "unknown");
            }
        }

        public static async Task<string> PrefetchGitHubReleaseAssetAsync(string repo, string assetRegex, string destDir, CancellationToken ct) {
            string res = await PrefetchGitHubReleaseAssetDetailedAsync(repo, assetRegex, destDir, ct).ConfigureAwait(false);
            if (!string.IsNullOrEmpty(res) && res.StartsWith("OK|", StringComparison.Ordinal)) {
                return res.Substring(3);
            }
            return "";
        }
    }

    public sealed class MasonryPanel : Panel {
        private int _columns = 3;
        private double _columnSpacing = 8.0;

        public int Columns {
            get { return _columns; }
            set {
                int clamped = value < 1 ? 1 : value;
                if (_columns != clamped) {
                    _columns = clamped;
                    InvalidateMeasure();
                }
            }
        }

        public double ColumnSpacing {
            get { return _columnSpacing; }
            set {
                double clamped = value < 0.0 ? 0.0 : value;
                if (Math.Abs(_columnSpacing - clamped) > 0.01) {
                    _columnSpacing = clamped;
                    InvalidateMeasure();
                }
            }
        }

        protected override System.Windows.Size MeasureOverride(System.Windows.Size availableSize) {
            int cols = _columns < 1 ? 1 : _columns;
            double totalW = (double.IsInfinity(availableSize.Width) || double.IsNaN(availableSize.Width) || availableSize.Width <= 0.0)
                ? 900.0
                : availableSize.Width;
            double spacing = _columnSpacing;
            double availCols = Math.Max(1.0, totalW - (cols - 1) * spacing);
            double colW = Math.Floor(availCols / cols);
            if (colW < 1.0) colW = availCols / cols;

            System.Windows.Size childConstraint = new System.Windows.Size(colW, double.PositiveInfinity);
            double[] colHeights = new double[cols];
            UIElementCollection children = InternalChildren;
            int count = children.Count;

            for (int i = 0; i < count; i++) {
                UIElement child = children[i];
                if (child == null || child.Visibility == Visibility.Collapsed) continue;
                child.Measure(childConstraint);
                int bestCol = 0;
                double minH = colHeights[0];
                for (int c = 1; c < cols; c++) {
                    if (colHeights[c] < minH) {
                        minH = colHeights[c];
                        bestCol = c;
                    }
                }
                colHeights[bestCol] += child.DesiredSize.Height;
            }

            double maxH = 0.0;
            for (int c = 0; c < cols; c++) {
                if (colHeights[c] > maxH) maxH = colHeights[c];
            }
            return new System.Windows.Size(totalW, maxH);
        }

        protected override System.Windows.Size ArrangeOverride(System.Windows.Size finalSize) {
            int cols = _columns < 1 ? 1 : _columns;
            double totalW = finalSize.Width > 0.0 ? finalSize.Width : 900.0;
            double spacing = _columnSpacing;
            double availCols = Math.Max(1.0, totalW - (cols - 1) * spacing);
            double colW = Math.Floor(availCols / cols);
            if (colW < 1.0) colW = availCols / cols;
            double colStep = colW + spacing;

            double[] colHeights = new double[cols];
            UIElementCollection children = InternalChildren;
            int count = children.Count;

            for (int i = 0; i < count; i++) {
                UIElement child = children[i];
                if (child == null || child.Visibility == Visibility.Collapsed) continue;
                int bestCol = 0;
                double minH = colHeights[0];
                for (int c = 1; c < cols; c++) {
                    if (colHeights[c] < minH) {
                        minH = colHeights[c];
                        bestCol = c;
                    }
                }
                double h = child.DesiredSize.Height;
                child.Arrange(new System.Windows.Rect(bestCol * colStep, minH, colW, h));
                colHeights[bestCol] = minH + h;
            }

            double maxH = 0.0;
            for (int c = 0; c < cols; c++) {
                if (colHeights[c] > maxH) maxH = colHeights[c];
            }
            return new System.Windows.Size(totalW, maxH);
        }
    }

    public sealed class UninstVirtualItem {
        public object App { get; set; }
        public string Id { get; set; }
        public string DisplayName { get; set; }
        public string DisplayVersion { get; set; }
        public string Publisher { get; set; }
        public string SizeText { get; set; }
        public long SizeBytes { get; set; }
        public bool IsBrokenOrphan { get; set; }
        public string TargetFolder { get; set; }
        public string InstallLocation { get; set; }
        public string DataLocation { get; set; }
        public string UninstallString { get; set; }
        public string SearchText { get; set; }
        public string FoldedName { get; set; }
        public string CompactName { get; set; }
        public string FoldedSearch { get; set; }
        public string CompactSearch { get; set; }
        public string[] SearchWords { get; set; }
        public int LastSearchScore { get; set; }
        public string IconTarget { get; set; }
        public string QueueKey { get; set; }
        public string BadgeLetter { get; set; }
        public int RegIndex { get; set; }
        public bool IsSelected { get; set; }
        public bool IsQueued { get; set; }
        public bool IsRemoved { get; set; }
        public bool IconEnqueued { get; set; }
        public bool IconLoaded { get; set; }
        internal UninstRowSlot BoundSlot;
        public Border Row { get { return BoundSlot != null ? BoundSlot.RowBorder : null; } }
        public CheckBox CheckBox { get { return BoundSlot != null ? BoundSlot.CheckBox : null; } }
    }

    public sealed class UninstFilterStats {
        public int VisibleCount { get; set; }
        public int TotalCount { get; set; }
        public int BrokenCount { get; set; }
        public long VisibleBytes { get; set; }
        public int SelectedCount { get; set; }
    }

    internal sealed class UninstRowSlot {
        public Border RowBorder;
        public CheckBox CheckBox;
        public System.Windows.Controls.Image IconImg;
        public Border FallbackBadge;
        public TextBlock BadgeTb;
        public TextBlock NameTb;
        public TextBlock VerTb;
        public TextBlock PubTb;
        public TextBlock SizeTb;
        public Border StatusBorder;
        public TextBlock StatusTb;
        public Border FolderBtn;
        public UninstVirtualItem BoundItem;
        public int BoundIndex = -1;
        public bool HasBoundOnce = false;
        public bool LastBroken = false;
        public bool LastSelected = false;
        public bool LastQueued = false;
        public bool LastHasFolder = false;
        public double LastTop = -1.0;
    }

    public sealed class UninstallerVirtualView {
        private sealed class FallbackRule {
            public Regex Pattern;
            public string Id;
            public FallbackRule(string pat, string id) {
                Pattern = new Regex(pat, RegexOptions.IgnoreCase | RegexOptions.Compiled);
                Id = id;
            }
        }

        private static readonly Regex _rxParen = new Regex(@"\(.*?\)", RegexOptions.Compiled);
        private static readonly Regex _rxVersion = new Regex(@"\b(version|v)?\s*\d+(\.\d+)+[^\s]*", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex _rxUninstExe = new Regex(@"unins|vc_redist|vcredist", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly FallbackRule[] _fallbackRules = new FallbackRule[] {
            new FallbackRule(@"Visual Studio Code|VS Code", "Microsoft.VisualStudioCode"),
            new FallbackRule(@"Visual C\+\+|VCRedist", "Microsoft.VCRedist.2015+.x64"),
            new FallbackRule(@"ASP\.NET|\.NET SDK|Desktop Runtime|\.NET", "Microsoft.DotNet.DesktopRuntime.8"),
            new FallbackRule(@"Corretto", "Amazon.Corretto.25.JDK"),
            new FallbackRule(@"Temurin|Adoptium", "EclipseAdoptium.Temurin.21.JDK"),
            new FallbackRule(@"Java \d+|Java\(TM\)|OpenJDK", "Oracle.JavaRuntimeEnvironment"),
            new FallbackRule(@"Node\.js", "OpenJS.NodeJS.LTS"),
            new FallbackRule(@"GitHub CLI", "GitHub.cli"),
            new FallbackRule(@"^Git\b", "Git.Git"),
            new FallbackRule(@"Python", "Python.Python.3.13"),
            new FallbackRule(@"Rustup", "Rustlang.Rustup"),
            new FallbackRule(@"PowerToys", "Microsoft.PowerToys"),
            new FallbackRule(@"Legacy Launcher", "LegacyLauncher.LegacyLauncher"),
            new FallbackRule(@"Google Chrome", "Google.Chrome"),
            new FallbackRule(@"Chrome Remote Desktop", "Google.ChromeRemoteDesktopHost"),
            new FallbackRule(@"Brave", "Brave.Brave"),
            new FallbackRule(@"Firefox", "Mozilla.Firefox"),
            new FallbackRule(@"Microsoft Edge", "Microsoft.Edge"),
            new FallbackRule(@"Discord", "Discord.Discord"),
            new FallbackRule(@"Zalo", "VNGCorp.Zalo"),
            new FallbackRule(@"Docker Desktop", "Docker.DockerDesktop"),
            new FallbackRule(@"Ollama", "Ollama.Ollama"),
            new FallbackRule(@"Antigravity IDE", "Google.AntigravityIDE"),
            new FallbackRule(@"^Antigravity", "Google.Antigravity"),
            new FallbackRule(@"WebStorm", "JetBrains.WebStorm"),
            new FallbackRule(@"Android Studio", "Google.AndroidStudio"),
            new FallbackRule(@"Visual Studio|vs_", "Microsoft.VisualStudio.2022.Community"),
            new FallbackRule(@"Windows Software Development Kit|Windows SDK", "Microsoft.WindowsTerminal")
        };

        private static readonly GridLength _col0 = new GridLength(38, GridUnitType.Pixel);
        private static readonly GridLength _col1 = new GridLength(1, GridUnitType.Star);
        private static readonly GridLength _col2 = new GridLength(130, GridUnitType.Pixel);
        private static readonly GridLength _col3 = new GridLength(220, GridUnitType.Pixel);
        private static readonly GridLength _col4 = new GridLength(105, GridUnitType.Pixel);
        private static readonly GridLength _col5 = new GridLength(115, GridUnitType.Pixel);
        private static readonly GridLength _col6 = new GridLength(54, GridUnitType.Pixel);
        private static readonly GridLength _iconCol = new GridLength(20, GridUnitType.Pixel);
        private static readonly Thickness _tZero = new Thickness(0);
        private static readonly Thickness _tRowBdr = new Thickness(1, 0, 1, 1);
        private static readonly Thickness _tOne = new Thickness(1);
        private static readonly Thickness _tName = new Thickness(8, 0, 8, 0);
        private static readonly Thickness _tNameText = new Thickness(8, 0, 4, 0);
        private static readonly Thickness _tCol = new Thickness(10, 0, 10, 0);
        private static readonly Thickness _tSize = new Thickness(8, 0, 12, 0);
        private static readonly Thickness _tBadgePad = new Thickness(8, 0, 8, 2);
        private static readonly CornerRadius _cRow = new CornerRadius(0);
        private static readonly CornerRadius _cFour = new CornerRadius(1);
        private static readonly CornerRadius _cPill = new CornerRadius(3);
        private const double RowHeight = 38.0;

        private readonly ScrollViewer _sv;
        private readonly Canvas _canvas;
        private readonly UIElement _tabPage;
        private readonly string _folderGlyph;
        private readonly Style _rowStyle;
        private readonly System.Windows.Media.Brush _rowBorderBrush;
        private readonly System.Windows.Media.Brush _colDividerBrush;
        private readonly System.Windows.Media.Brush _checkedBg;
        private readonly System.Windows.Media.Brush _titleBrush;
        private readonly System.Windows.Media.Brush _titleBrokenBrush;
        private readonly System.Windows.Media.Brush _mutedBrush;
        private readonly System.Windows.Media.Brush _lightBrush;
        private readonly System.Windows.Media.Brush _badgeBg;
        private readonly System.Windows.Media.Brush _badgeFg;
        private readonly System.Windows.Media.Brush _badgeBrokenBg;
        private readonly System.Windows.Media.Brush _badgeBrokenFg;
        private readonly System.Windows.Media.Brush _statusOkBg;
        private readonly System.Windows.Media.Brush _statusOkBorder;
        private readonly System.Windows.Media.Brush _statusOkFg;
        private readonly System.Windows.Media.Brush _statusBrokenBg;
        private readonly System.Windows.Media.Brush _statusBrokenBorder;
        private readonly System.Windows.Media.Brush _folderBg;
        private readonly System.Windows.Media.Brush _folderBorder;

        private readonly List<UninstVirtualItem> _allItems = new List<UninstVirtualItem>();
        private UninstVirtualItem[] _byRegIndex = new UninstVirtualItem[0];
        private readonly List<UninstVirtualItem> _visibleItems = new List<UninstVirtualItem>();
        private readonly List<UninstRowSlot> _allSlots = new List<UninstRowSlot>();
        private readonly Dictionary<int, UninstRowSlot> _activeSlots = new Dictionary<int, UninstRowSlot>();
        private readonly Stack<UninstRowSlot> _freeSlots = new Stack<UninstRowSlot>();
        private readonly DispatcherTimer _iconTimer;
        private readonly RoutedEventHandler _checkedHandler;
        private readonly RoutedEventHandler _uncheckedHandler;
        private readonly MouseButtonEventHandler _mouseUpHandler;

        private int _lastStart = -1;
        private int _lastEnd = -1;
        private int _selectedCount = 0;
        private double _panelWidth = 0.0;
        private bool _suppressCheckEvents = false;
        private bool _isStopped = false;
        private bool _eventsAttached = false;
        private int _lastTotalSourceCount = 0;

        public Func<bool> CanInteract;
        public Action<int> OnSelectionChanged;

        public List<UninstVirtualItem> AllItems { get { return _allItems; } }
        public List<UninstVirtualItem> VisibleItems { get { return _visibleItems; } }
        public int SelectedCount { get { return _selectedCount; } }
        public int PoolSize { get { return _allSlots.Count; } }

        public UninstallerVirtualView(
            ScrollViewer sv,
            Canvas canvas,
            UIElement tabPage,
            string folderGlyph,
            Style rowStyle,
            System.Windows.Media.Brush rowBorderBrush,
            System.Windows.Media.Brush colDividerBrush,
            System.Windows.Media.Brush checkedBg,
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
            System.Windows.Media.Brush folderBorder)
        {
            _sv = sv;
            _canvas = canvas;
            _tabPage = tabPage;
            _folderGlyph = folderGlyph ?? "";
            _rowStyle = rowStyle;
            _rowBorderBrush = rowBorderBrush;
            _colDividerBrush = colDividerBrush;
            _checkedBg = checkedBg;
            _titleBrush = titleBrush;
            _titleBrokenBrush = titleBrokenBrush;
            _mutedBrush = mutedBrush;
            _lightBrush = lightBrush;
            _badgeBg = badgeBg;
            _badgeFg = badgeFg;
            _badgeBrokenBg = badgeBrokenBg;
            _badgeBrokenFg = badgeBrokenFg;
            _statusOkBg = statusOkBg;
            _statusOkBorder = statusOkBorder;
            _statusOkFg = statusOkFg;
            _statusBrokenBg = statusBrokenBg;
            _statusBrokenBorder = statusBrokenBorder;
            _folderBg = folderBg;
            _folderBorder = folderBorder;

            _checkedHandler = new RoutedEventHandler(OnRowCheckBoxChecked);
            _uncheckedHandler = new RoutedEventHandler(OnRowCheckBoxUnchecked);
            _mouseUpHandler = new MouseButtonEventHandler(OnCanvasMouseLeftButtonUp);

            _iconTimer = new DispatcherTimer(DispatcherPriority.Background);
            _iconTimer.Interval = TimeSpan.FromMilliseconds(33);
            AttachEvents();
        }

        private void AttachEvents() {
            if (_eventsAttached) return;
            _eventsAttached = true;
            if (_sv != null) {
                _sv.ScrollChanged += OnScrollChanged;
            }
            if (_canvas != null) {
                _canvas.SizeChanged += OnCanvasSizeChanged;
                _canvas.AddHandler(ToggleButton.CheckedEvent, _checkedHandler);
                _canvas.AddHandler(ToggleButton.UncheckedEvent, _uncheckedHandler);
                _canvas.AddHandler(UIElement.MouseLeftButtonUpEvent, _mouseUpHandler);
            }
            if (_iconTimer != null) {
                _iconTimer.Tick += OnIconTimerTick;
            }
        }

        private void DetachEvents() {
            if (!_eventsAttached) return;
            _eventsAttached = false;
            if (_sv != null) {
                _sv.ScrollChanged -= OnScrollChanged;
            }
            if (_canvas != null) {
                _canvas.SizeChanged -= OnCanvasSizeChanged;
                _canvas.RemoveHandler(ToggleButton.CheckedEvent, _checkedHandler);
                _canvas.RemoveHandler(ToggleButton.UncheckedEvent, _uncheckedHandler);
                _canvas.RemoveHandler(UIElement.MouseLeftButtonUpEvent, _mouseUpHandler);
            }
            if (_iconTimer != null) {
                _iconTimer.Tick -= OnIconTimerTick;
            }
        }

        public static Task<List<UninstVirtualItem>> BuildVirtualItemsAsync(
            System.Collections.IList rawApps,
            Dictionary<string, string> catalogIconLookup,
            string iconsCacheDir)
        {
            return Task.Run(delegate() {
                var result = new List<UninstVirtualItem>();
                if (rawApps == null || rawApps.Count == 0) return result;

                string windir = Environment.GetEnvironmentVariable("WINDIR") ?? @"C:\Windows";
                string msiExe = Path.Combine(windir, @"System32\msiexec.exe");
                if (!File.Exists(msiExe)) msiExe = "";

                PropertyInfo pId = null, pName = null, pVer = null, pPub = null, pSize = null;
                PropertyInfo pBroken = null, pInstLoc = null, pDataLoc = null, pUninst = null;
                PropertyInfo pRawReg = null, pIconSrc = null, pTargetFolder = null, pSearchIdx = null;
                Type cachedType = null;

                int regIdx = 0;
                for (int i = 0; i < rawApps.Count; i++) {
                    object app = rawApps[i];
                    if (app == null) continue;
                    Type t = app.GetType();
                    if (t != cachedType) {
                        cachedType = t;
                        pId = t.GetProperty("Id");
                        pName = t.GetProperty("DisplayName");
                        pVer = t.GetProperty("DisplayVersion");
                        pPub = t.GetProperty("Publisher");
                        pSize = t.GetProperty("SizeBytes");
                        pBroken = t.GetProperty("IsBrokenOrphan");
                        pInstLoc = t.GetProperty("InstallLocation");
                        pDataLoc = t.GetProperty("DataLocation");
                        pUninst = t.GetProperty("UninstallString");
                        pRawReg = t.GetProperty("RawRegPath");
                        pIconSrc = t.GetProperty("IconSourcePath");
                        pTargetFolder = t.GetProperty("TargetFolder");
                        pSearchIdx = t.GetProperty("SearchIndex");
                    }

                    string id = pId != null ? (pId.GetValue(app, null) as string ?? "") : "";
                    string dispName = pName != null ? (pName.GetValue(app, null) as string ?? "") : "";
                    string dispVer = pVer != null ? (pVer.GetValue(app, null) as string ?? "") : "";
                    string pub = pPub != null ? (pPub.GetValue(app, null) as string ?? "") : "";
                    long sizeBytes = 0;
                    if (pSize != null) {
                        object svObj = pSize.GetValue(app, null);
                        if (svObj != null) { try { sizeBytes = Convert.ToInt64(svObj); } catch {} }
                    }
                    bool isBroken = false;
                    if (pBroken != null) {
                        object brObj = pBroken.GetValue(app, null);
                        if (brObj != null) { try { isBroken = Convert.ToBoolean(brObj); } catch {} }
                    }
                    string instLoc = pInstLoc != null ? (pInstLoc.GetValue(app, null) as string ?? "") : "";
                    string dataLoc = pDataLoc != null ? (pDataLoc.GetValue(app, null) as string ?? "") : "";
                    string uninstStr = pUninst != null ? (pUninst.GetValue(app, null) as string ?? "") : "";
                    string rawReg = pRawReg != null ? (pRawReg.GetValue(app, null) as string ?? "") : "";
                    string iconSrc = pIconSrc != null ? (pIconSrc.GetValue(app, null) as string ?? "") : "";
                    string targetFolder = pTargetFolder != null ? (pTargetFolder.GetValue(app, null) as string ?? "") : "";
                    string searchIdx = pSearchIdx != null ? (pSearchIdx.GetValue(app, null) as string ?? "") : "";

                    if (string.IsNullOrEmpty(targetFolder)) {
                        if (!string.IsNullOrWhiteSpace(instLoc) && Directory.Exists(instLoc)) targetFolder = instLoc;
                        else if (!string.IsNullOrWhiteSpace(dataLoc) && Directory.Exists(dataLoc)) targetFolder = dataLoc;
                    }
                    if (string.IsNullOrEmpty(searchIdx)) {
                        searchIdx = (dispName + " " + pub + " " + dispVer).ToLowerInvariant();
                    }

                    string sizeText = "--";
                    if (sizeBytes > 0) {
                        double mb = (double)sizeBytes / 1048576.0;
                        sizeText = mb >= 1024.0
                            ? string.Format("{0:N2} GB", mb / 1024.0)
                            : string.Format("{0:N1} MB", mb);
                    }

                    string queueKey;
                    if (!string.IsNullOrWhiteSpace(rawReg)) queueKey = "REG:" + rawReg;
                    else if (!string.IsNullOrWhiteSpace(id)) queueKey = "ID:" + id + "|" + dispName;
                    else queueKey = "NAME:" + dispName + "|" + instLoc;

                    string dispTrim = string.IsNullOrEmpty(dispName) ? "A" : dispName.Trim();
                    string badgeLetter = isBroken ? "!" : (dispTrim.Length > 0 ? dispTrim.Substring(0, 1).ToUpperInvariant() : "\u2022");

                    string iconTarget = ResolveBestIconTarget(id, dispName, iconSrc, catalogIconLookup, iconsCacheDir, msiExe);

                    string foldedName = UiAssetPipeline.NormalizeSearchFold(dispName);
                    string foldedSearch = UiAssetPipeline.NormalizeSearchFold(searchIdx);
                    result.Add(new UninstVirtualItem {
                        App = app,
                        Id = id,
                        DisplayName = dispName,
                        DisplayVersion = string.IsNullOrEmpty(dispVer) ? "--" : dispVer,
                        Publisher = string.IsNullOrEmpty(pub) ? "--" : pub,
                        SizeText = sizeText,
                        SizeBytes = sizeBytes,
                        IsBrokenOrphan = isBroken,
                        TargetFolder = targetFolder,
                        InstallLocation = instLoc,
                        DataLocation = dataLoc,
                        UninstallString = uninstStr,
                        SearchText = searchIdx,
                        FoldedName = foldedName,
                        CompactName = UiAssetPipeline.CompactSearchAlnum(foldedName),
                        FoldedSearch = foldedSearch,
                        CompactSearch = UiAssetPipeline.CompactSearchAlnum(foldedSearch),
                        SearchWords = UiAssetPipeline.SplitFoldedTokens(foldedName),
                        IconTarget = iconTarget,
                        QueueKey = queueKey,
                        BadgeLetter = badgeLetter,
                        RegIndex = regIdx++
                    });
                }
                return result;
            });
        }

        private static string ResolveBestIconTarget(
            string id,
            string displayName,
            string srcPath,
            Dictionary<string, string> catalogLookup,
            string iconsCacheDir,
            string msiExe)
        {
            bool srcExists = !string.IsNullOrWhiteSpace(srcPath) && File.Exists(srcPath);
            if (srcExists) {
                string fn = Path.GetFileNameWithoutExtension(srcPath) ?? "";
                bool inPkgCache = srcPath.IndexOf(@"\Package Cache\", StringComparison.OrdinalIgnoreCase) >= 0;
                if (!inPkgCache && !_rxUninstExe.IsMatch(fn)) {
                    return srcPath;
                }
            }

            string catPng = ResolveCatalogPng(id, displayName, catalogLookup, iconsCacheDir);
            if (!string.IsNullOrEmpty(catPng)) return catPng;
            if (srcExists) return srcPath;
            return msiExe;
        }

        private static string ResolveCatalogPng(
            string id,
            string displayName,
            Dictionary<string, string> catalogLookup,
            string iconsCacheDir)
        {
            string cand;
            if (catalogLookup != null) {
                if (!string.IsNullOrEmpty(id) && catalogLookup.TryGetValue(id, out cand) && File.Exists(cand)) return cand;
                if (!string.IsNullOrEmpty(displayName) && catalogLookup.TryGetValue(displayName, out cand) && File.Exists(cand)) return cand;
                if (!string.IsNullOrEmpty(displayName)) {
                    string cleanDn = _rxVersion.Replace(_rxParen.Replace(displayName, ""), "").Trim();
                    if (!string.IsNullOrEmpty(cleanDn) && catalogLookup.TryGetValue(cleanDn, out cand) && File.Exists(cand)) return cand;
                }
            }
            if (!string.IsNullOrEmpty(displayName) && !string.IsNullOrEmpty(iconsCacheDir)) {
                for (int r = 0; r < _fallbackRules.Length; r++) {
                    if (_fallbackRules[r].Pattern.IsMatch(displayName)) {
                        string p = Path.Combine(iconsCacheDir, _fallbackRules[r].Id + ".png");
                        if (File.Exists(p)) return p;
                    }
                }
            }
            return "";
        }

        public void SetItems(List<UninstVirtualItem> items, int totalSourceCount) {
            _isStopped = false;
            AttachEvents();
            _iconTimer.Stop();
            UnbindAllSlots();
            _allItems.Clear();
            _visibleItems.Clear();
            _selectedCount = 0;
            _lastStart = -1;
            _lastEnd = -1;
            _lastTotalSourceCount = totalSourceCount;

            if (items != null) {
                for (int i = 0; i < items.Count; i++) {
                    UninstVirtualItem it = items[i];
                    if (it != null) {
                        it.RegIndex = _allItems.Count;
                        _allItems.Add(it);
                    }
                }
            }
            _byRegIndex = _allItems.ToArray();
            if (_canvas != null && _canvas.ActualWidth > 0) {
                _panelWidth = _canvas.ActualWidth;
            }
        }

        public UninstFilterStats ApplyFilterAndSort(string query, bool brokenOnly, bool sortBySize, bool resort) {
            if (resort && _allItems.Count > 1) {
                if (sortBySize) {
                    _allItems.Sort(delegate(UninstVirtualItem a, UninstVirtualItem b) {
                        int c = b.SizeBytes.CompareTo(a.SizeBytes);
                        if (c != 0) return c;
                        return string.Compare(a.DisplayName, b.DisplayName, StringComparison.OrdinalIgnoreCase);
                    });
                } else {
                    _allItems.Sort(delegate(UninstVirtualItem a, UninstVirtualItem b) {
                        int c = b.IsBrokenOrphan.CompareTo(a.IsBrokenOrphan);
                        if (c != 0) return c;
                        return string.Compare(a.DisplayName, b.DisplayName, StringComparison.OrdinalIgnoreCase);
                    });
                }
            }

            string foldedQ = UiAssetPipeline.NormalizeSearchFold(query);
            string compactQ = UiAssetPipeline.CompactSearchAlnum(foldedQ);
            string[] qTokens = UiAssetPipeline.SplitFoldedTokens(foldedQ);
            bool hasQ = foldedQ.Length > 0;

            _visibleItems.Clear();
            int brokenCount = 0;
            long visibleBytes = 0;
            int selCount = 0;

            for (int i = 0; i < _allItems.Count; i++) {
                UninstVirtualItem it = _allItems[i];
                if (it.IsRemoved) continue;
                if (it.IsBrokenOrphan) brokenCount++;
                if (it.IsSelected) selCount++;

                if (brokenOnly && !it.IsBrokenOrphan) continue;
                if (hasQ) {
                    int score = UiAssetPipeline.ScoreSearchQuery(
                        foldedQ,
                        compactQ,
                        qTokens,
                        it.FoldedName ?? "",
                        it.CompactName ?? "",
                        it.FoldedSearch ?? (it.SearchText ?? ""),
                        it.CompactSearch ?? "",
                        it.SearchWords
                    );
                    if (score <= 0) continue;
                    it.LastSearchScore = score;
                } else {
                    it.LastSearchScore = 0;
                }

                _visibleItems.Add(it);
                if (it.SizeBytes > 0) visibleBytes += it.SizeBytes;
            }
            if (hasQ && _visibleItems.Count > 1) {
                _visibleItems.Sort(delegate(UninstVirtualItem a, UninstVirtualItem b) {
                    int sc = b.LastSearchScore.CompareTo(a.LastSearchScore);
                    if (sc != 0) return sc;
                    if (sortBySize) {
                        int szc = b.SizeBytes.CompareTo(a.SizeBytes);
                        if (szc != 0) return szc;
                    }
                    return string.Compare(a.DisplayName, b.DisplayName, StringComparison.OrdinalIgnoreCase);
                });
            }
            _selectedCount = selCount;

            if (_canvas != null) {
                double newH = _visibleItems.Count * RowHeight;
                if (double.IsNaN(_canvas.Height) || Math.Abs(_canvas.Height - newH) > 0.5) {
                    _canvas.Height = newH;
                }
                if (_sv != null) {
                    double vh = _sv.ViewportHeight > 100.0 ? _sv.ViewportHeight : 620.0;
                    double maxOff = Math.Max(0.0, newH - vh);
                    if (_sv.VerticalOffset > maxOff) {
                        _sv.ScrollToVerticalOffset(maxOff);
                    }
                }
            }

            SyncViewport(true);

            return new UninstFilterStats {
                VisibleCount = _visibleItems.Count,
                TotalCount = _lastTotalSourceCount > 0 ? _lastTotalSourceCount : _allItems.Count,
                BrokenCount = brokenCount,
                VisibleBytes = visibleBytes,
                SelectedCount = _selectedCount
            };
        }

        public void SyncViewport(bool force) {
            if (_isStopped || _canvas == null) return;
            if (_tabPage != null && _tabPage.Visibility != Visibility.Visible) return;

            int visCount = _visibleItems.Count;
            if (visCount == 0) {
                UnbindAllSlots();
                CollapseFreeSlots();
                _lastStart = -1;
                _lastEnd = -1;
                return;
            }

            if (_canvas.ActualWidth > 0 && Math.Abs(_canvas.ActualWidth - _panelWidth) > 0.5) {
                _panelWidth = _canvas.ActualWidth;
            }

            double vOff = _sv != null ? _sv.VerticalOffset : 0.0;
            double vH = (_sv != null && _sv.ViewportHeight > 100.0) ? _sv.ViewportHeight : 620.0;

            int startIdx = Math.Max(0, (int)Math.Floor(vOff / RowHeight) - 3);
            int endIdx = Math.Min(visCount - 1, (int)Math.Ceiling((vOff + vH) / RowHeight) + 4);

            if (!force && startIdx == _lastStart && endIdx == _lastEnd) {
                return;
            }
            _lastStart = startIdx;
            _lastEnd = endIdx;

            if (force) {
                UnbindAllSlots();
            } else if (_activeSlots.Count > 0) {
                var toRemove = new List<int>();
                foreach (KeyValuePair<int, UninstRowSlot> kv in _activeSlots) {
                    if (kv.Key < startIdx || kv.Key > endIdx) {
                        toRemove.Add(kv.Key);
                    }
                }
                for (int r = 0; r < toRemove.Count; r++) {
                    int idx = toRemove[r];
                    UninstRowSlot slot = _activeSlots[idx];
                    _activeSlots.Remove(idx);
                    if (slot.BoundItem != null && slot.BoundItem.BoundSlot == slot) {
                        slot.BoundItem.BoundSlot = null;
                    }
                    slot.BoundItem = null;
                    slot.BoundIndex = -1;
                    _freeSlots.Push(slot);
                }
            }

            List<int> enqIdx = null;
            List<string> enqPaths = null;

            for (int idx = startIdx; idx <= endIdx; idx++) {
                if (_activeSlots.ContainsKey(idx)) continue;
                UninstVirtualItem item = _visibleItems[idx];
                UninstRowSlot slot = _freeSlots.Count > 0 ? _freeSlots.Pop() : CreateSlot();

                double topY = idx * RowHeight;
                if (Math.Abs(slot.LastTop - topY) > 0.1) {
                    Canvas.SetTop(slot.RowBorder, topY);
                    slot.LastTop = topY;
                }
                if (_panelWidth > 0 && (double.IsNaN(slot.RowBorder.Width) || Math.Abs(slot.RowBorder.Width - _panelWidth) > 0.5)) {
                    slot.RowBorder.Width = _panelWidth;
                }
                if (slot.RowBorder.Visibility != Visibility.Visible) {
                    slot.RowBorder.Visibility = Visibility.Visible;
                }

                BindSlot(slot, item, idx);
                _activeSlots[idx] = slot;

                if (!item.IconLoaded && !item.IconEnqueued && !string.IsNullOrEmpty(item.IconTarget)) {
                    item.IconEnqueued = true;
                    if (enqIdx == null) {
                        enqIdx = new List<int>();
                        enqPaths = new List<string>();
                    }
                    enqIdx.Add(item.RegIndex);
                    enqPaths.Add(item.IconTarget);
                }
            }

            CollapseFreeSlots();

            if (enqIdx != null && enqIdx.Count > 0) {
                UiAssetPipeline.EnqueueUninstallerIcons(enqIdx.ToArray(), enqPaths.ToArray());
                if (!_iconTimer.IsEnabled) {
                    _iconTimer.Start();
                }
            }
        }

        private void UnbindAllSlots() {
            if (_activeSlots.Count == 0) return;
            foreach (KeyValuePair<int, UninstRowSlot> kv in _activeSlots) {
                UninstRowSlot slot = kv.Value;
                if (slot.BoundItem != null && slot.BoundItem.BoundSlot == slot) {
                    slot.BoundItem.BoundSlot = null;
                }
                slot.BoundItem = null;
                slot.BoundIndex = -1;
                _freeSlots.Push(slot);
            }
            _activeSlots.Clear();
        }

        private void CollapseFreeSlots() {
            if (_freeSlots.Count == 0) return;
            foreach (UninstRowSlot slot in _freeSlots) {
                if (slot.RowBorder.Visibility != Visibility.Collapsed) {
                    slot.RowBorder.Visibility = Visibility.Collapsed;
                }
            }
        }

        private UninstRowSlot CreateSlot() {
            var rowBorder = new Border();
            rowBorder.Height = RowHeight;
            if (_panelWidth > 0) rowBorder.Width = _panelWidth;
            rowBorder.CornerRadius = _cRow;
            rowBorder.Padding = _tZero;
            rowBorder.Margin = _tZero;
            if (_rowStyle != null) rowBorder.Style = _rowStyle;
            rowBorder.BorderBrush = _rowBorderBrush;
            rowBorder.BorderThickness = _tRowBdr;
            rowBorder.SnapsToDevicePixels = true;
            rowBorder.Cursor = Cursors.Hand;
            rowBorder.ToolTip = "";
            ToolTipService.SetInitialShowDelay(rowBorder, 5000);
            Canvas.SetLeft(rowBorder, 0.0);

            var rowGrid = new Grid();
            rowGrid.VerticalAlignment = VerticalAlignment.Stretch;
            rowGrid.SnapsToDevicePixels = true;
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _col0 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _col1 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _col2 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _col3 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _col4 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _col5 });
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _col6 });

            var cb = new CheckBox();
            cb.VerticalAlignment = VerticalAlignment.Center;
            cb.HorizontalAlignment = HorizontalAlignment.Center;
            cb.Margin = _tZero;
            Grid.SetColumn(cb, 0);
            rowGrid.Children.Add(cb);

            var nameGrid = new Grid();
            nameGrid.VerticalAlignment = VerticalAlignment.Center;
            nameGrid.Margin = _tName;
            nameGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _iconCol });
            nameGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = _col1 });

            var iconSlot = new Grid();
            iconSlot.Width = 20;
            iconSlot.Height = 20;
            iconSlot.VerticalAlignment = VerticalAlignment.Center;
            iconSlot.HorizontalAlignment = HorizontalAlignment.Left;

            var fallbackBadge = new Border();
            fallbackBadge.Width = 20;
            fallbackBadge.Height = 20;
            fallbackBadge.CornerRadius = _cFour;
            fallbackBadge.Background = _badgeBg;
            fallbackBadge.VerticalAlignment = VerticalAlignment.Center;
            fallbackBadge.HorizontalAlignment = HorizontalAlignment.Center;

            var badgeTb = new TextBlock();
            badgeTb.FontSize = 10.5;
            badgeTb.FontWeight = FontWeights.Bold;
            badgeTb.Foreground = _badgeFg;
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
            img.Visibility = Visibility.Collapsed;

            iconSlot.Children.Add(fallbackBadge);
            iconSlot.Children.Add(img);
            Grid.SetColumn(iconSlot, 0);
            nameGrid.Children.Add(iconSlot);

            var nameTb = new TextBlock();
            nameTb.FontSize = 12;
            nameTb.FontWeight = FontWeights.SemiBold;
            nameTb.Foreground = _titleBrush;
            nameTb.VerticalAlignment = VerticalAlignment.Center;
            nameTb.TextTrimming = TextTrimming.CharacterEllipsis;
            nameTb.Margin = _tNameText;
            Grid.SetColumn(nameTb, 1);
            nameGrid.Children.Add(nameTb);

            Grid.SetColumn(nameGrid, 1);
            rowGrid.Children.Add(nameGrid);

            var verTb = new TextBlock();
            verTb.FontSize = 11.5;
            verTb.Foreground = _mutedBrush;
            verTb.VerticalAlignment = VerticalAlignment.Center;
            verTb.TextTrimming = TextTrimming.CharacterEllipsis;
            verTb.Margin = _tCol;
            Grid.SetColumn(verTb, 2);
            rowGrid.Children.Add(verTb);

            var pubTb = new TextBlock();
            pubTb.FontSize = 11.5;
            pubTb.Foreground = _mutedBrush;
            pubTb.VerticalAlignment = VerticalAlignment.Center;
            pubTb.TextTrimming = TextTrimming.CharacterEllipsis;
            pubTb.Margin = _tCol;
            Grid.SetColumn(pubTb, 3);
            rowGrid.Children.Add(pubTb);

            var sizeTb = new TextBlock();
            sizeTb.FontSize = 11.5;
            sizeTb.Foreground = _lightBrush;
            sizeTb.VerticalAlignment = VerticalAlignment.Center;
            sizeTb.TextAlignment = TextAlignment.Right;
            sizeTb.Margin = _tSize;
            Grid.SetColumn(sizeTb, 4);
            rowGrid.Children.Add(sizeTb);

            var statusBorder = new Border();
            statusBorder.CornerRadius = _cPill;
            statusBorder.Height = 22;
            statusBorder.Padding = _tBadgePad;
            statusBorder.HorizontalAlignment = HorizontalAlignment.Center;
            statusBorder.VerticalAlignment = VerticalAlignment.Center;
            statusBorder.BorderThickness = _tOne;
            statusBorder.Background = _statusOkBg;
            statusBorder.BorderBrush = _statusOkBorder;

            var statusTb = UiAssetPipeline.CreateCenteredBadgeLabel(
                "B\u00ECnh th\u01B0\u1EDDng",
                10.5,
                FontWeights.SemiBold,
                _statusOkFg);
            statusBorder.Child = statusTb;
            Grid.SetColumn(statusBorder, 5);
            rowGrid.Children.Add(statusBorder);

            var folderBtn = new Border();
            folderBtn.Width = 26;
            folderBtn.Height = 24;
            folderBtn.CornerRadius = _cFour;
            folderBtn.Background = _folderBg;
            folderBtn.BorderBrush = _folderBorder;
            folderBtn.BorderThickness = _tOne;
            folderBtn.HorizontalAlignment = HorizontalAlignment.Center;
            folderBtn.VerticalAlignment = VerticalAlignment.Center;
            folderBtn.ToolTip = "";
            ToolTipService.SetInitialShowDelay(folderBtn, 5000);

            var folderIcon = new TextBlock();
            folderIcon.Text = _folderGlyph;
            folderIcon.FontSize = 10.5;
            folderIcon.HorizontalAlignment = HorizontalAlignment.Center;
            folderIcon.VerticalAlignment = VerticalAlignment.Center;
            folderBtn.Child = folderIcon;
            Grid.SetColumn(folderBtn, 6);
            rowGrid.Children.Add(folderBtn);

            if (_colDividerBrush != null) {
                for (int divCol = 0; divCol < 6; divCol++) {
                    var colDiv = new Border();
                    colDiv.Width = 1;
                    colDiv.Background = _colDividerBrush;
                    colDiv.HorizontalAlignment = HorizontalAlignment.Right;
                    colDiv.VerticalAlignment = VerticalAlignment.Stretch;
                    colDiv.SnapsToDevicePixels = true;
                    colDiv.IsHitTestVisible = false;
                    Grid.SetColumn(colDiv, divCol);
                    rowGrid.Children.Add(colDiv);
                }
            }

            rowBorder.Child = rowGrid;

            var slot = new UninstRowSlot {
                RowBorder = rowBorder,
                CheckBox = cb,
                IconImg = img,
                FallbackBadge = fallbackBadge,
                BadgeTb = badgeTb,
                NameTb = nameTb,
                VerTb = verTb,
                PubTb = pubTb,
                SizeTb = sizeTb,
                StatusBorder = statusBorder,
                StatusTb = statusTb,
                FolderBtn = folderBtn
            };
            rowBorder.Tag = slot;
            cb.Tag = slot;
            folderBtn.Tag = slot;

            rowBorder.ToolTipOpening += OnRowToolTipOpening;
            folderBtn.ToolTipOpening += OnFolderToolTipOpening;

            _allSlots.Add(slot);
            _canvas.Children.Add(rowBorder);
            return slot;
        }

        private void BindSlot(UninstRowSlot slot, UninstVirtualItem item, int visIdx) {
            slot.BoundItem = item;
            slot.BoundIndex = visIdx;
            item.BoundSlot = slot;

            if (slot.NameTb.Text != item.DisplayName) slot.NameTb.Text = item.DisplayName;
            if (slot.VerTb.Text != item.DisplayVersion) slot.VerTb.Text = item.DisplayVersion;
            if (slot.PubTb.Text != item.Publisher) slot.PubTb.Text = item.Publisher;
            if (slot.SizeTb.Text != item.SizeText) slot.SizeTb.Text = item.SizeText;

            bool first = !slot.HasBoundOnce;
            if (first || slot.LastBroken != item.IsBrokenOrphan) {
                slot.LastBroken = item.IsBrokenOrphan;
                slot.NameTb.Foreground = item.IsBrokenOrphan ? _titleBrokenBrush : _titleBrush;
                slot.FallbackBadge.Background = item.IsBrokenOrphan ? _badgeBrokenBg : _badgeBg;
                slot.BadgeTb.Foreground = item.IsBrokenOrphan ? _badgeBrokenFg : _badgeFg;
                slot.StatusBorder.Background = item.IsBrokenOrphan ? _statusBrokenBg : _statusOkBg;
                slot.StatusBorder.BorderBrush = item.IsBrokenOrphan ? _statusBrokenBorder : _statusOkBorder;
                slot.StatusTb.Text = item.IsBrokenOrphan ? "L\u1ED7i / C\u00F2n s\u00F3t" : "B\u00ECnh th\u01B0\u1EDDng";
                slot.StatusTb.Foreground = item.IsBrokenOrphan ? _badgeBrokenFg : _statusOkFg;
            }

            bool hasFolder = !string.IsNullOrEmpty(item.TargetFolder);
            if (first || slot.LastHasFolder != hasFolder) {
                slot.LastHasFolder = hasFolder;
                slot.FolderBtn.Cursor = hasFolder ? Cursors.Hand : Cursors.Arrow;
                slot.FolderBtn.Opacity = hasFolder ? 1.0 : 0.25;
            }

            if (first || slot.LastQueued != item.IsQueued) {
                slot.LastQueued = item.IsQueued;
                slot.RowBorder.Opacity = item.IsQueued ? 0.52 : 1.0;
            }

            if (first || slot.LastSelected != item.IsSelected) {
                slot.LastSelected = item.IsSelected;
                _suppressCheckEvents = true;
                try {
                    slot.CheckBox.IsChecked = item.IsSelected;
                } finally {
                    _suppressCheckEvents = false;
                }
                if (item.IsSelected) {
                    slot.RowBorder.Background = _checkedBg;
                } else {
                    slot.RowBorder.ClearValue(Border.BackgroundProperty);
                }
            }

            BitmapSource cachedBmp = !string.IsNullOrEmpty(item.IconTarget)
                ? UiAssetPipeline.TryGetCachedUninstIcon(item.IconTarget)
                : null;
            if (cachedBmp != null) {
                item.IconLoaded = true;
                if (!ReferenceEquals(slot.IconImg.Source, cachedBmp)) slot.IconImg.Source = cachedBmp;
                if (slot.IconImg.Visibility != Visibility.Visible) slot.IconImg.Visibility = Visibility.Visible;
                if (slot.FallbackBadge.Visibility != Visibility.Collapsed) slot.FallbackBadge.Visibility = Visibility.Collapsed;
            } else {
                if (slot.IconImg.Source != null) slot.IconImg.Source = null;
                if (slot.IconImg.Visibility != Visibility.Collapsed) slot.IconImg.Visibility = Visibility.Collapsed;
                if (slot.BadgeTb.Text != item.BadgeLetter) slot.BadgeTb.Text = item.BadgeLetter;
                if (slot.FallbackBadge.Visibility != Visibility.Visible) slot.FallbackBadge.Visibility = Visibility.Visible;
            }

            slot.HasBoundOnce = true;
        }

        private void OnScrollChanged(object sender, ScrollChangedEventArgs e) {
            if (_isStopped) return;
            if (Math.Abs(e.VerticalChange) > 0.01 || Math.Abs(e.ViewportHeightChange) > 0.5) {
                SyncViewport(false);
            }
        }

        private void OnCanvasSizeChanged(object sender, SizeChangedEventArgs e) {
            if (_isStopped || _canvas == null) return;
            double w = _canvas.ActualWidth;
            if (w <= 0 || Math.Abs(w - _panelWidth) <= 0.5) return;
            _panelWidth = w;
            for (int i = 0; i < _allSlots.Count; i++) {
                _allSlots[i].RowBorder.Width = w;
            }
        }

        private void OnRowToolTipOpening(object sender, ToolTipEventArgs e) {
            var b = sender as Border;
            if (b == null) return;
            var slot = b.Tag as UninstRowSlot;
            if (slot == null || slot.BoundItem == null) { e.Handled = true; return; }
            UninstVirtualItem it = slot.BoundItem;
            string dataTip = !string.IsNullOrWhiteSpace(it.DataLocation) ? ("\nKhu d\u1EEF li\u1EC7u ri\u00EAng: " + it.DataLocation) : "";
            b.ToolTip = it.DisplayName + "\nPhi\u00EAn b\u1EA3n: " + it.DisplayVersion + "\nNh\u00E0 ph\u00E1t h\u00E0nh: " + it.Publisher + "\n\u0110\u01B0\u1EDDng d\u1EABn: " + it.InstallLocation + dataTip + "\nL\u1EC7nh g\u1EE1: " + it.UninstallString;
        }

        private void OnFolderToolTipOpening(object sender, ToolTipEventArgs e) {
            var b = sender as Border;
            if (b == null) return;
            var slot = b.Tag as UninstRowSlot;
            if (slot == null || slot.BoundItem == null) { e.Handled = true; return; }
            string tf = slot.BoundItem.TargetFolder;
            b.ToolTip = !string.IsNullOrEmpty(tf) ? ("M\u1EDF th\u01B0 m\u1EE5c: " + tf) : "Kh\u00F4ng t\u00ECm th\u1EA5y th\u01B0 m\u1EE5c c\u00E0i \u0111\u1EB7t";
        }

        private void OnRowCheckBoxChecked(object sender, RoutedEventArgs e) {
            if (_suppressCheckEvents) return;
            var cb = e.OriginalSource as CheckBox;
            if (cb == null) return;
            var slot = cb.Tag as UninstRowSlot;
            if (slot == null || slot.BoundItem == null) return;
            if (!slot.BoundItem.IsSelected) {
                slot.BoundItem.IsSelected = true;
                _selectedCount++;
            }
            slot.LastSelected = true;
            slot.RowBorder.Background = _checkedBg;
            if (OnSelectionChanged != null) OnSelectionChanged(_selectedCount);
        }

        private void OnRowCheckBoxUnchecked(object sender, RoutedEventArgs e) {
            if (_suppressCheckEvents) return;
            var cb = e.OriginalSource as CheckBox;
            if (cb == null) return;
            var slot = cb.Tag as UninstRowSlot;
            if (slot == null || slot.BoundItem == null) return;
            if (slot.BoundItem.IsSelected) {
                slot.BoundItem.IsSelected = false;
                if (_selectedCount > 0) _selectedCount--;
            }
            slot.LastSelected = false;
            slot.RowBorder.ClearValue(Border.BackgroundProperty);
            if (OnSelectionChanged != null) OnSelectionChanged(_selectedCount);
        }

        private void OnCanvasMouseLeftButtonUp(object sender, MouseButtonEventArgs e) {
            if (e.Handled || _isStopped) return;
            if (CanInteract != null && !CanInteract()) return;

            DependencyObject node = e.OriginalSource as DependencyObject;
            while (node != null && !ReferenceEquals(node, _canvas)) {
                if (node is ToggleButton) return;
                var b = node as Border;
                if (b != null) {
                    var slot = b.Tag as UninstRowSlot;
                    if (slot != null && slot.BoundItem != null) {
                        if (ReferenceEquals(b, slot.FolderBtn)) {
                            e.Handled = true;
                            string loc = slot.BoundItem.TargetFolder;
                            if (!string.IsNullOrEmpty(loc) && Directory.Exists(loc)) {
                                try { Process.Start("explorer.exe", "\"" + loc + "\""); } catch {}
                            }
                            return;
                        }
                        if (ReferenceEquals(b, slot.RowBorder)) {
                            bool cur = slot.CheckBox.IsChecked == true;
                            slot.CheckBox.IsChecked = !cur;
                            return;
                        }
                    }
                }
                if (node is Visual) node = VisualTreeHelper.GetParent(node);
                else break;
            }
        }

        private void OnIconTimerTick(object sender, EventArgs e) {
            if (_isStopped) {
                _iconTimer.Stop();
                return;
            }
            ReadyIconItem[] ready = UiAssetPipeline.DequeueReadyUninstallerIcons(16);
            if (ready != null && ready.Length > 0) {
                for (int i = 0; i < ready.Length; i++) {
                    ReadyIconItem ri = ready[i];
                    if (ri == null || ri.Bitmap == null) continue;
                    if (ri.Index >= 0 && ri.Index < _byRegIndex.Length) {
                        UninstVirtualItem it = _byRegIndex[ri.Index];
                        if (it != null && string.Equals(it.IconTarget, ri.CacheKey, StringComparison.OrdinalIgnoreCase)) {
                            it.IconLoaded = true;
                            UninstRowSlot slot = it.BoundSlot;
                            if (slot != null && ReferenceEquals(slot.BoundItem, it)) {
                                slot.IconImg.Source = ri.Bitmap;
                                slot.IconImg.Visibility = Visibility.Visible;
                                slot.FallbackBadge.Visibility = Visibility.Collapsed;
                            }
                        }
                    }
                }
            }
            if (UiAssetPipeline.IsUninstIdle) {
                _iconTimer.Stop();
            }
        }

        public int SelectAllVisible() {
            _suppressCheckEvents = true;
            try {
                for (int i = 0; i < _visibleItems.Count; i++) {
                    UninstVirtualItem it = _visibleItems[i];
                    if (it.IsRemoved) continue;
                    if (!it.IsSelected) {
                        it.IsSelected = true;
                        _selectedCount++;
                    }
                }
                foreach (KeyValuePair<int, UninstRowSlot> kv in _activeSlots) {
                    UninstRowSlot slot = kv.Value;
                    if (slot.BoundItem != null && slot.BoundItem.IsSelected && !slot.LastSelected) {
                        slot.LastSelected = true;
                        slot.CheckBox.IsChecked = true;
                        slot.RowBorder.Background = _checkedBg;
                    }
                }
            } finally {
                _suppressCheckEvents = false;
            }
            if (OnSelectionChanged != null) OnSelectionChanged(_selectedCount);
            return _selectedCount;
        }

        public int DeselectAll() {
            _suppressCheckEvents = true;
            try {
                for (int i = 0; i < _allItems.Count; i++) {
                    _allItems[i].IsSelected = false;
                }
                _selectedCount = 0;
                foreach (KeyValuePair<int, UninstRowSlot> kv in _activeSlots) {
                    UninstRowSlot slot = kv.Value;
                    if (slot.LastSelected) {
                        slot.LastSelected = false;
                        slot.CheckBox.IsChecked = false;
                        slot.RowBorder.ClearValue(Border.BackgroundProperty);
                    }
                }
            } finally {
                _suppressCheckEvents = false;
            }
            if (OnSelectionChanged != null) OnSelectionChanged(0);
            return 0;
        }

        public void MarkQueuedByKeys(HashSet<string> keys) {
            if (keys == null || keys.Count == 0) return;
            _suppressCheckEvents = true;
            try {
                for (int i = 0; i < _allItems.Count; i++) {
                    UninstVirtualItem it = _allItems[i];
                    if (keys.Contains(it.QueueKey)) {
                        if (it.IsSelected) {
                            it.IsSelected = false;
                            if (_selectedCount > 0) _selectedCount--;
                        }
                        it.IsQueued = true;
                        UninstRowSlot slot = it.BoundSlot;
                        if (slot != null && ReferenceEquals(slot.BoundItem, it)) {
                            slot.LastSelected = false;
                            slot.LastQueued = true;
                            slot.CheckBox.IsChecked = false;
                            slot.RowBorder.ClearValue(Border.BackgroundProperty);
                            slot.RowBorder.Opacity = 0.52;
                        }
                    }
                }
            } finally {
                _suppressCheckEvents = false;
            }
            if (OnSelectionChanged != null) OnSelectionChanged(_selectedCount);
        }

        public void ClearAllQueued() {
            for (int i = 0; i < _allItems.Count; i++) {
                UninstVirtualItem it = _allItems[i];
                if (it.IsQueued) {
                    it.IsQueued = false;
                    UninstRowSlot slot = it.BoundSlot;
                    if (slot != null && ReferenceEquals(slot.BoundItem, it)) {
                        slot.LastQueued = false;
                        slot.RowBorder.Opacity = 1.0;
                    }
                }
            }
        }

        public bool MarkRemovedByKey(string key) {
            if (string.IsNullOrEmpty(key)) return false;
            bool removedAny = false;
            for (int i = 0; i < _allItems.Count; i++) {
                UninstVirtualItem it = _allItems[i];
                if (!it.IsRemoved && string.Equals(it.QueueKey, key, StringComparison.OrdinalIgnoreCase)) {
                    it.IsRemoved = true;
                    if (it.IsSelected) {
                        it.IsSelected = false;
                        if (_selectedCount > 0) _selectedCount--;
                    }
                    it.IsQueued = false;
                    removedAny = true;
                }
            }
            return removedAny;
        }

        public object[] GetSelectedApps() {
            var list = new List<object>();
            for (int i = 0; i < _allItems.Count; i++) {
                UninstVirtualItem it = _allItems[i];
                if (!it.IsRemoved && it.IsSelected && it.App != null) {
                    list.Add(it.App);
                }
            }
            return list.ToArray();
        }

        public void Stop() {
            _isStopped = true;
            try { _iconTimer.Stop(); } catch {}
            DetachEvents();
        }
    }
}
