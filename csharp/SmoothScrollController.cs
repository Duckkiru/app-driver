using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace DuckUtil {
    public sealed class SmoothScrollController {
        private readonly ScrollViewer _sv;
        private double _currentOffset;
        private double _targetOffset;
        private double _lastAppliedOffset;
        private bool _isAnimating;
        private readonly Stopwatch _sw = new Stopwatch();
        private double _lastTimeSec;

        private SmoothScrollController(ScrollViewer sv) {
            _sv = sv;
            _currentOffset = sv.VerticalOffset;
            _targetOffset = sv.VerticalOffset;
            _lastAppliedOffset = sv.VerticalOffset;
            _sv.PreviewMouseWheel += OnPreviewMouseWheel;
        }

        public static SmoothScrollController Attach(ScrollViewer sv) {
            if (sv == null) return null;
            return new SmoothScrollController(sv);
        }

        private void OnPreviewMouseWheel(object sender, MouseWheelEventArgs e) {
            if (e == null || e.Handled) return;
            if (Keyboard.Modifiers != ModifierKeys.None) return;

            double maxScroll = _sv.ScrollableHeight;
            if (maxScroll <= 0) return;

            if (!_isAnimating || Math.Abs(_sv.VerticalOffset - _lastAppliedOffset) > 2.5) {
                _currentOffset = _sv.VerticalOffset;
                _targetOffset = _sv.VerticalOffset;
            }

            double step = -e.Delta * 0.85;
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
            if (!_sv.IsLoaded) {
                StopAnimation();
                return;
            }

            if (Math.Abs(_sv.VerticalOffset - _lastAppliedOffset) > 2.5) {
                _currentOffset = _sv.VerticalOffset;
                _targetOffset = _sv.VerticalOffset;
                StopAnimation();
                return;
            }

            double nowSec = _sw.Elapsed.TotalSeconds;
            double dt = nowSec - _lastTimeSec;
            _lastTimeSec = nowSec;
            if (dt <= 0.0 || dt > 0.1) dt = 0.016;

            double maxScroll = _sv.ScrollableHeight;
            if (_targetOffset > maxScroll) _targetOffset = maxScroll;
            if (_targetOffset < 0.0) _targetOffset = 0.0;

            double diff = _targetOffset - _currentOffset;
            if (Math.Abs(diff) < 0.25) {
                _currentOffset = _targetOffset;
                _lastAppliedOffset = _currentOffset;
                _sv.ScrollToVerticalOffset(_currentOffset);
                StopAnimation();
                return;
            }

            double factor = 1.0 - Math.Exp(-17.0 * dt);
            _currentOffset += diff * factor;
            _lastAppliedOffset = _currentOffset;
            _sv.ScrollToVerticalOffset(_currentOffset);
        }

        private void StopAnimation() {
            if (_isAnimating) {
                _isAnimating = false;
                CompositionTarget.Rendering -= OnRendering;
                _sw.Stop();
            }
        }
    }
}
