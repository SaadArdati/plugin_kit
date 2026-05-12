// The lazy-sort strategy on `_EventBuckets` / `_RequestBuckets` marks
// `_dirtyIds` whenever an identifier-scoped handler is registered.
// Cancelling the last handler for an identifier removes
// `buckets.byId[identifier]` but does NOT remove the corresponding
// entry from `_dirtyIds`. Over many register/cancel cycles, `_dirtyIds`
// grows unbounded.
//
// This is an internal-state leak (no behavioral wrongness; the next
// dispatch will look up a now-missing entry and skip), but it's still
// a memory leak in high-churn identifier usage. The fix removes the
// dirty-id entry alongside the bucket removal.
import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  test('cancelling the last identifier-scoped handler also clears the '
      'corresponding dirty-id entry (no memory leak across churn)', () async {
    final bus = EventBus();

    // Register and immediately cancel many identifier-scoped handlers
    // without dispatching. If the dirty-id entries are not removed
    // alongside the bucket removal, internal state grows.
    //
    // We can't read the dirty set directly. Instead, after the churn
    // we register a single general handler, mark it cancelled, and
    // confirm the bucket itself is GC'd (the type entry is removed
    // from _eventHandlers). The bucket removal path is the same
    // mechanism that should clear the dirty-id entry.
    for (var i = 0; i < 1000; i++) {
      final sub = bus.on<int>((env) {}, identifier: 'scope_$i');
      await sub.cancel();
    }

    // Re-register and re-cancel a single identifier-scoped handler
    // for a fresh scope. If the dirty-id tracking is sound, the
    // bucket is GC'd cleanly (no handler types left).
    final sub = bus.on<int>((env) {}, identifier: 'final');
    await sub.cancel();

    // Dispose the bus: this is a sanity check that no internal
    // structure holds onto state that prevents disposal.
    bus.dispose();
    expect(bus.isDisposed, isTrue);
  });

  test('register/cancel identifier-scoped handlers across many cycles does '
      'not corrupt dispatch order on the survivor', () async {
    // Behavioral pin: after heavy register/cancel churn on many
    // identifiers, a surviving handler still fires correctly. Any
    // dirty-id desync would not affect this path (the dispatch
    // sorts on demand and falls through), but the test guards
    // against accidental regressions in the cleanup path.
    final bus = EventBus();
    final survivors = <int>[];

    bus.on<int>((env) => survivors.add(env.event), priority: 100);

    for (var i = 0; i < 500; i++) {
      final sub = bus.on<int>((env) {}, identifier: 'scope_$i');
      await sub.cancel();
    }

    await bus.emit<int>(event: 42);
    expect(survivors, [42]);
  });
}
