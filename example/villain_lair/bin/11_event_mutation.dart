/// # 11: Event Mutation (`on<T>` Semantics)
///
/// An `on<T>((envelope) async {...})` handler has three patterns:
///
/// 1. Continue the cascade: do not call `envelope.stop(...)`. Optionally
///    mutate `envelope.event` so later handlers see the new payload.
/// 2. Short-circuit with replacement: call `envelope.stop(value)` and
///    return from the handler. The cascade ends with `value`.
/// 3. Abort via `envelope.stop(value)`: mark the cascade as stopped but keep
///    running code in the handler afterwards (emit a side event, log, etc.),
///    then return. `result.stopped` is true.
library;

import 'package:plugin_kit/plugin_kit.dart';

// SECTION 1: Mutation. Handlers mutate envelope.event without stopping, so
// every handler contributes to the final payload.

/// Mutable payload so every handler can append to the same trail.
class EvilPlan {
  final String name;
  final List<String> trail;

  EvilPlan(this.name) : trail = [];

  @override
  String toString() => 'EvilPlan($name, trail: $trail)';
}

// SECTION 2: Short-circuit with envelope.stop(). The priority-0 handler
// either concedes or stops with a sanitized replacement.

/// A press-release payload. The sanitizer handler replaces it when it sees
/// brand-protected terms.
class PressRelease {
  final String headline;
  const PressRelease(this.headline);

  @override
  String toString() => 'PressRelease("$headline")';
}

// SECTION 3: Abort via envelope.stop(). The quota handler needs to emit a
// rejection event BEFORE halting, so it uses .stop() instead of a bare
// non-null return.

/// A coffee order. Gary has a quota.
class CoffeeOrder {
  final String who;
  final String drink;
  const CoffeeOrder({required this.who, required this.drink});

  @override
  String toString() => 'CoffeeOrder($who, $drink)';
}

/// Observer-facing event emitted when an order is rejected.
class OrderRejected {
  final String who;
  final String reason;
  const OrderRejected({required this.who, required this.reason});
}

/// Wires the three cascades. Every handler demonstrates exactly one pattern.
class HookSemanticsPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('hook_semantics');

  @override
  void attach(SessionPluginContext context) {
    _wireMutationCascade(context);
    _wireShortCircuitCascade(context);
    _wireAbortCascade(context);
  }

  /// Section 1: three handlers mutate `envelope.event` without stopping.
  /// Every handler runs; the trail ends with three entries.
  void _wireMutationCascade(SessionPluginContext context) {
    context.bus.on<EvilPlan>((envelope) async {
      envelope.event.trail.add('Mr. Whiskers reviewed');
      print('[EvilPlan, priority 0] Mr. Whiskers appends to trail.');
    }, priority: 0);

    context.bus.on<EvilPlan>((envelope) async {
      envelope.event.trail.add('Janet budgeted');
      print('[EvilPlan, priority 5] Janet appends to trail.');
    }, priority: 5);

    context.bus.on<EvilPlan>((envelope) async {
      envelope.event.trail.add('Doug executed');
      print('[EvilPlan, priority 10] Doug appends to trail.');
    }, priority: 10);
  }

  /// Section 2: the priority-0 handler either concedes or stops with a
  /// sanitized replacement. The priority-10 handler only sees the payload
  /// when priority-0 conceded.
  void _wireShortCircuitCascade(SessionPluginContext context) {
    context.bus.on<PressRelease>((envelope) async {
      if (envelope.event.headline.contains('Doom')) {
        print(
          '[PressRelease, priority 0] Sanitizer stops with a replacement. '
          'Handler body exits on this return.',
        );
        envelope.stop(const PressRelease('[REDACTED by Legal]'));
        return;
      }
      print('[PressRelease, priority 0] Sanitizer concedes (no stop).');
    }, priority: 0);

    context.bus.on<PressRelease>((envelope) async {
      print(
        '[PressRelease, priority 10] Publisher sees "${envelope.event.headline}".',
      );
    }, priority: 10);
  }

  /// Section 3: the priority-0 handler detects Gary's quota, emits a rejection
  /// event for observers, THEN calls envelope.stop() and returns null. The
  /// downstream brewer never sees the order.
  void _wireAbortCascade(SessionPluginContext context) {
    // Closure-local counter. No plugin fields.
    var garyOrderCount = 0;

    context.bus.on<CoffeeOrder>((envelope) async {
      final order = envelope.event;

      if (order.who == 'Gary') {
        garyOrderCount++;
        if (garyOrderCount > 2) {
          print(
            '[CoffeeOrder, priority 0] Gary quota exceeded. '
            'Emitting OrderRejected BEFORE stopping the cascade.',
          );
          // Side effect must happen before the stop decision is final.
          await context.bus.emit<OrderRejected>(
            event: OrderRejected(
              who: order.who,
              reason: 'Daily bean budget exceeded.',
            ),
          );
          // Mark the cascade as stopped, then fall through to the return
          // below. With `.stop`, code after this line still executes.
          envelope.stop(order);
          print(
            '[CoffeeOrder, priority 0] Post-stop cleanup runs; handler '
            'returns. Cascade will halt after this handler.',
          );
          return;
        }
      }

      print('[CoffeeOrder, priority 0] Quota check passed for ${order.who}.');
    }, priority: 0);

    context.bus.on<CoffeeOrder>((envelope) async {
      print(
        '[CoffeeOrder, priority 10] Brewer prepares '
        '"${envelope.event.drink}" for ${envelope.event.who}.',
      );
    }, priority: 10);

    // Observer that proves the rejection event actually fires as a side
    // effect from inside the aborting handler.
    context.bus.on<OrderRejected>((e) {
      print(
        '[OrderRejected observer] ${e.event.who} notified: ${e.event.reason}',
      );
    });
  }
}

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [HookSemanticsPlugin()])..init();
  final session = await runtime.createSession();

  print('=== Section 1: Mutation (mutate envelope.event, no stop) ===\n');
  final planResult = await session.emit(EvilPlan('Operation Sandwich'));
  print('\nStopped? ${planResult.stopped}');
  print('Final trail: ${planResult.event.trail}');
  print('All three handlers contributed. Cascade ran to completion.');

  print('\n=== Section 2a: Short-circuit by stop (conceding branch) ===\n');
  final clean = await session.emit(const PressRelease('Tuesday Luncheon'));
  print('\nStopped? ${clean.stopped}');
  print('Final headline: ${clean.event.headline}');
  print('Priority-0 did not stop; priority-10 saw the payload.');

  print('\n=== Section 2b: Short-circuit by stop (firing branch) ===\n');
  final redacted = await session.emit(const PressRelease('Doom Ray Unveiled'));
  print('\nStopped? ${redacted.stopped}');
  print('Final headline: ${redacted.event.headline}');
  print('Priority-0 called envelope.stop(...); priority-10 never saw it.');

  print('\n=== Section 3: Abort via envelope.stop() with side effects ===\n');
  print('First two Gary orders pass the quota:\n');
  await session.emit(const CoffeeOrder(who: 'Gary', drink: 'Latte'));
  print('');
  await session.emit(const CoffeeOrder(who: 'Gary', drink: 'Mocha'));

  print('\nThird Gary order trips the quota:\n');
  final blocked = await session.emit(
    const CoffeeOrder(who: 'Gary', drink: 'Cortado'),
  );
  print('\nStopped? ${blocked.stopped}');
  print(
    'Brewer at priority 10 never ran. Rejection observer fired from inside '
    'the aborting handler, before envelope.stop() took effect.',
  );

  await runtime.dispose();
}
