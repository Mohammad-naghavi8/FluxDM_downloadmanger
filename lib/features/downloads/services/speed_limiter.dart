import 'dart:async';

import 'package:dio/dio.dart';

class SpeedLimiter {
  final int Function() getMaxBytesPerSecond;
  final Stopwatch _stopwatch = Stopwatch()..start();

  int _windowStartMs = 0;
  int _bytesInWindow = 0;

  SpeedLimiter(this.getMaxBytesPerSecond);

  void reset() {
    _windowStartMs = _stopwatch.elapsedMilliseconds;
    _bytesInWindow = 0;
  }

  Future<void> throttle(int bytes, {CancelToken? cancelToken}) async {
    final maxBps = getMaxBytesPerSecond();
    if (maxBps <= 0 || bytes <= 0) return;

    final nowMs = _stopwatch.elapsedMilliseconds;
    if (nowMs - _windowStartMs >= 1000) {
      _windowStartMs = nowMs;
      _bytesInWindow = 0;
    }

    _bytesInWindow += bytes;

    final expectedElapsedMs = (_bytesInWindow * 1000) ~/ maxBps;
    final actualElapsedMs = _stopwatch.elapsedMilliseconds - _windowStartMs;
    final waitMs = expectedElapsedMs - actualElapsedMs;

    if (waitMs > 10) {
      await cancellableDelay(
        Duration(milliseconds: waitMs.clamp(10, 1000)),
        cancelToken: cancelToken,
      );

      final afterMs = _stopwatch.elapsedMilliseconds;
      if (afterMs - _windowStartMs >= 1000) {
        _windowStartMs = afterMs;
        _bytesInWindow = 0;
      }
    }
  }

  static Future<void> cancellableDelay(
    Duration duration, {
    CancelToken? cancelToken,
  }) {
    if (cancelToken?.isCancelled ?? false) {
      return Future<void>.value();
    }

    final completer = Completer<void>();
    final timer = Timer(duration, () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    cancelToken?.whenCancel.then((_) {
      timer.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    return completer.future;
  }
}
