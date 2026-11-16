using System;
using System.Diagnostics;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
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
}
