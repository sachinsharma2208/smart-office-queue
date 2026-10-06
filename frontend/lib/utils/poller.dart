import 'dart:async';

/// Reference-counted periodic task used for "live" data.
///
/// Several screens can call [start]; the timer runs while at least one of them
/// is still open and stops when the last one calls [stop]. A tick is skipped
/// if the previous one is still running, so slow networks never pile up.
class Poller {
  Poller(this.interval, this.task);

  final Duration interval;
  final Future<void> Function() task;

  Timer? _timer;
  int _users = 0;
  bool _running = false;

  void start() {
    _users++;
    _timer ??= Timer.periodic(interval, (_) async {
      if (_running) return;
      _running = true;
      try {
        await task();
      } catch (_) {
        // Polling is best-effort; the next tick will retry.
      } finally {
        _running = false;
      }
    });
  }

  void stop() {
    if (_users > 0) _users--;
    if (_users == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _users = 0;
  }
}
