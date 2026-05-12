// Pinning the asymptotic cost of bucket insertion. The current
// `_insertPrioritized` uses `indexWhere` (linear scan) to find the
// insertion point, making N inserts O(N^2) in the worst case. With
// ascending-priority inserts the predicate fails until the end of the
// list, so every insert scans the full current list.
//
// `package:collection` is already a direct dependency, so swapping in
// `binarySearch` (or `lowerBound`) gives O(log N) per insert and
// O(N log N) total.
//
// This test exercises the worst case at a size where the naive
// algorithm exceeds a generous wall-clock budget, while the binary-search
// implementation completes in milliseconds. The budget is conservative
// (5s) so the test stays stable on slow CI runners.

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  test('inserting many handlers with ascending priorities stays under '
      'the wall-clock budget (O(N log N), not O(N^2))', () {
    const n = 100000;
    final bus = EventBus();
    final stopwatch = Stopwatch()..start();

    for (var i = 0; i < n; i++) {
      // Ascending priorities mean each insert lands at the END of the
      // current bucket. `indexWhere` walks the full list every time:
      // total work is N*(N+1)/2 comparisons, which on a modern
      // workstation is roughly 5-10 seconds for N=20000. Binary
      // search closes that to ~N*log2(N) ~= 285k compares, which is
      // milliseconds.
      bus.on<String>((env) {}, priority: i);
    }

    stopwatch.stop();

    expect(
      stopwatch.elapsed.inMilliseconds,
      lessThan(5000),
      reason:
          'inserting $n handlers should complete in well under 5s; '
          'O(N^2) implementations blow past this even on fast hardware. '
          'Elapsed: ${stopwatch.elapsed}.',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('priority-sorted dispatch order is preserved after binary-search '
      'insertion', () async {
    // Performance refactor must not change the dispatch contract:
    // higher priorities still run first. This test pins the
    // invariant so a binary-search bug that inserts on the wrong
    // side of equal priorities (or sorts ascending instead of
    // descending) is caught.
    final bus = EventBus();
    final order = <int>[];

    // Register out of priority order to exercise insertion paths.
    bus.on<String>((env) => order.add(50), priority: 50);
    bus.on<String>((env) => order.add(10), priority: 10);
    bus.on<String>((env) => order.add(100), priority: 100);
    bus.on<String>((env) => order.add(75), priority: 75);
    bus.on<String>((env) => order.add(25), priority: 25);

    await bus.emit<String>(event: 'x');

    expect(order, [
      100,
      75,
      50,
      25,
      10,
    ], reason: 'handlers must dispatch in strictly descending priority');
  });

  test(
    'equal-priority handlers preserve registration order (stable sort)',
    () async {
      // Insertion at equal priority must place new entries AFTER
      // existing ones at the same priority, mirroring the original
      // `indexWhere` semantics (`entry.priority > e.priority` returns
      // false on equals, so the search continues past them and the
      // new entry lands after).
      final bus = EventBus();
      final order = <String>[];

      bus.on<String>((env) => order.add('a'), priority: 50);
      bus.on<String>((env) => order.add('b'), priority: 50);
      bus.on<String>((env) => order.add('c'), priority: 50);

      await bus.emit<String>(event: 'x');

      expect(order, [
        'a',
        'b',
        'c',
      ], reason: 'equal-priority handlers must fire in registration order');
    },
  );
}
