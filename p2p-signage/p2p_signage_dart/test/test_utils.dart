import 'dart:async';

Future<void> waitUntil(bool Function() condition, {Duration timeout = const Duration(seconds: 10)}) async {
  final completer = Completer<void>();
  final stopwatch = Stopwatch()..start();

  Timer.periodic(const Duration(milliseconds: 100), (timer) {
    if (condition()) {
      timer.cancel();
      completer.complete();
    } else if (stopwatch.elapsed > timeout) {
      timer.cancel();
      completer.completeError(TimeoutException('Condition not met within timeout'));
    }
  });

  return completer.future;
}
