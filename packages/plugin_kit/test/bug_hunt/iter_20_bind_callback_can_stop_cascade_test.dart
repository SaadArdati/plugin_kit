// Regression test for ISSUE-20260518-1240-bind-callback-can-stop-cascade.
// bind() callbacks are documented as side-effect observers that cannot
// truncate the typed-handler cascade. Before the fix, calling
// EventEnvelope.stop() from a bind callback set _stopped=true on the
// shared envelope, so the dispatch loop broke before any typed handler
// ran.

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _Ping {
  _Ping(this.payload);
  final String payload;
}

void main() {
  group('bug-hunt iter 20: bind-callback-can-stop-cascade', () {
    test(
      'emit: typed handlers run even when a bind callback calls stop()',
      () async {
        final bus = EventBus();
        addTearDown(bus.dispose);

        final seen = <String>[];
        bus.bind((envelope) {
          // Bind observer tries to truncate. Per docs this must NOT
          // affect typed handlers.
          if (envelope.event is _Ping) {
            (envelope as EventEnvelope<_Ping>).stop(_Ping('hijacked-by-bind'));
          }
        });
        bus.on<_Ping>((envelope) {
          seen.add(envelope.event.payload);
        });

        final result = await bus.emit<_Ping>(event: _Ping('original'));

        expect(seen, [
          'original',
        ], reason: 'typed handler must run despite bind calling stop()');
        expect(
          result.stopped,
          isFalse,
          reason: 'bind-induced stop must not propagate to the result',
        );
      },
    );

    test('emitSync: same invariant on the sync path', () {
      final bus = EventBus();
      addTearDown(bus.dispose);

      final seen = <String>[];
      bus.bind((envelope) {
        if (envelope.event is _Ping) {
          (envelope as EventEnvelope<_Ping>).stop(_Ping('hijacked-by-bind'));
        }
      });
      bus.onSync<_Ping>((envelope) {
        seen.add(envelope.event.payload);
      });

      final result = bus.emitSync<_Ping>(event: _Ping('original'));

      expect(seen, ['original']);
      expect(result.stopped, isFalse);
    });

    test(
      'emitSync: bind mutation WITHOUT stop() still reaches typed handlers',
      () {
        // Sync-path companion to the test below. Pins the same
        // mutation-without-stop boundary.
        final bus = EventBus();
        addTearDown(bus.dispose);

        final seen = <String>[];
        bus.bind((envelope) {
          if (envelope.event is _Ping) {
            (envelope as EventEnvelope<_Ping>).event = _Ping(
              'mutated-by-bind-sync',
            );
          }
        });
        bus.onSync<_Ping>((envelope) {
          seen.add(envelope.event.payload);
        });

        final result = bus.emitSync<_Ping>(event: _Ping('original'));

        expect(seen, ['mutated-by-bind-sync']);
        expect(result.stopped, isFalse);
      },
    );

    test('mixed: one bind .stop()s, another mutates; typed handler sees the '
        'pre-bind original (stop revert wins over the .stop()-induced '
        'mutation), and the cascade is NOT truncated', () async {
      // Codex round-3 optional hardening. Pins precedence when one
      // callback calls .stop(value) and another mutates `event`
      // without stop. The revert keys on `wrapped.stopped`, so any
      // bind-time mutations are wiped together with the truncation.
      final bus = EventBus();
      addTearDown(bus.dispose);

      final seen = <String>[];
      // First callback calls .stop with a hijacked payload.
      bus.bind((envelope) {
        if (envelope.event is _Ping) {
          (envelope as EventEnvelope<_Ping>).stop(_Ping('stop-hijack'));
        }
      });
      // Second callback mutates the (already .stop-mutated) event.
      // Since the revert keys on the .stopped flag, BOTH mutations
      // are erased together.
      bus.bind((envelope) {
        if (envelope.event is _Ping) {
          (envelope as EventEnvelope<_Ping>).event = _Ping(
            'second-bind-mutation',
          );
        }
      });
      bus.on<_Ping>((envelope) {
        seen.add(envelope.event.payload);
      });

      final result = await bus.emit<_Ping>(event: _Ping('original'));

      expect(
        seen,
        ['original'],
        reason:
            'when any bind called .stop(), the revert restores '
            'the pre-bind event for every typed handler',
      );
      expect(result.stopped, isFalse);
    });

    test(
      'emit: bind callback mutation WITHOUT stop() still reaches typed handlers',
      () async {
        // The fix only reverts the envelope when a bind callback called
        // stop(). Other mutations (event field reassignment, ad-hoc
        // observability hooks) must NOT be reverted; typed handlers see
        // them. This pins that boundary so a future "always revert"
        // refactor would fail loud.
        final bus = EventBus();
        addTearDown(bus.dispose);

        final seen = <String>[];
        bus.bind((envelope) {
          if (envelope.event is _Ping) {
            // Mutate without calling stop. Per contract this propagates
            // to typed handlers.
            (envelope as EventEnvelope<_Ping>).event = _Ping('mutated-by-bind');
          }
        });
        bus.on<_Ping>((envelope) {
          seen.add(envelope.event.payload);
        });

        final result = await bus.emit<_Ping>(event: _Ping('original'));

        expect(seen, [
          'mutated-by-bind',
        ], reason: 'bind mutation without stop() must reach handlers');
        expect(result.stopped, isFalse);
      },
    );
  });
}
