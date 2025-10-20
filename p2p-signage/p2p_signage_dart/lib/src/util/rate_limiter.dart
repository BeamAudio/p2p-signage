
import 'dart:collection';
import 'dart:io';

class RateLimiter {
  final int maxRequests;
  final Duration period;
  final _requests = <String, Queue<DateTime>>{};

  RateLimiter(this.maxRequests, this.period);

  bool isAllowed(String key) {
    final now = DateTime.now();
    final queue = _requests.putIfAbsent(key, () => Queue());

    while (queue.isNotEmpty && now.difference(queue.first) > period) {
      queue.removeFirst();
    }

    if (queue.length < maxRequests) {
      queue.add(now);
      return true;
    }

    return false;
  }
}
