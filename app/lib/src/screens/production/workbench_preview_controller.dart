import 'package:flutter/foundation.dart';

/// 工作台首帧预览的纯时间状态。
///
/// 计时器由页面持有；这样镜头跳转、定位和结束行为无需依赖 widget 测试。
class PreviewTimelineController extends ChangeNotifier {
  PreviewTimelineController(List<Duration> durations)
      : _durations = List.unmodifiable([
          for (final duration in durations)
            duration > Duration.zero
                ? duration
                : const Duration(seconds: 3),
        ]);

  final List<Duration> _durations;
  int _currentIndex = 0;
  Duration _elapsed = Duration.zero;
  bool _isPlaying = false;

  int get currentIndex => _currentIndex;
  Duration get elapsed => _elapsed;
  bool get isPlaying => _isPlaying;
  bool get isEmpty => _durations.isEmpty;
  Duration get currentDuration =>
      isEmpty ? Duration.zero : _durations[_currentIndex];
  Duration get totalDuration =>
      _durations.fold(Duration.zero, (total, duration) => total + duration);
  Duration get totalElapsed => _elapsedFor(_currentIndex) + _elapsed;
  double get progress {
    final total = totalDuration.inMicroseconds;
    if (total == 0) return 0;
    return totalElapsed.inMicroseconds / total;
  }

  void togglePlay() {
    if (isEmpty) return;
    if (_isPlaying) {
      pause();
      return;
    }
    if (totalElapsed >= totalDuration) {
      _currentIndex = 0;
      _elapsed = Duration.zero;
    }
    _isPlaying = true;
    notifyListeners();
  }

  void pause() {
    if (!_isPlaying) return;
    _isPlaying = false;
    notifyListeners();
  }

  void previous() {
    if (isEmpty || _currentIndex == 0) return;
    _isPlaying = false;
    _currentIndex--;
    _elapsed = Duration.zero;
    notifyListeners();
  }

  void next() {
    if (isEmpty || _currentIndex >= _durations.length - 1) return;
    _isPlaying = false;
    _currentIndex++;
    _elapsed = Duration.zero;
    notifyListeners();
  }

  void jumpTo(int index) {
    if (isEmpty || index < 0 || index >= _durations.length) return;
    _isPlaying = false;
    _currentIndex = index;
    _elapsed = Duration.zero;
    notifyListeners();
  }

  void seek(Duration target) {
    if (isEmpty) return;
    _setElapsed(_clamp(target));
    notifyListeners();
  }

  void tick(Duration delta) {
    if (!_isPlaying || isEmpty || delta <= Duration.zero) return;
    final next = _clamp(totalElapsed + delta);
    _setElapsed(next);
    if (next >= totalDuration) _isPlaying = false;
    notifyListeners();
  }

  Duration _clamp(Duration value) {
    if (value < Duration.zero) return Duration.zero;
    final total = totalDuration;
    return value > total ? total : value;
  }

  void _setElapsed(Duration target) {
    var passed = Duration.zero;
    for (var index = 0; index < _durations.length; index++) {
      final duration = _durations[index];
      final end = passed + duration;
      if (target < end || index == _durations.length - 1) {
        _currentIndex = index;
        _elapsed = target - passed;
        return;
      }
      passed = end;
    }
  }

  Duration _elapsedFor(int index) => _durations
      .take(index)
      .fold(Duration.zero, (total, duration) => total + duration);
}
