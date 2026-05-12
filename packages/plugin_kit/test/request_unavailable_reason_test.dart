// Promote RequestUnavailableException.reason from a free-form String to a
// typed enum so callers can switch on the unavailability case without
// parsing message text.
//
// Three cases (mirrors the throw sites in event_bus.dart):
//
//   - noRegistration: no handlers registered for the (Request, Response)
//     type pair at all (the request bucket is missing).
//   - noMatchingHandler: the bucket exists but no handler matches the
//     priority-merged set (identifier scopes handlers exist for a
//     different identifier, or only general handlers exist for an
//     identifier-scoped request, etc.).
//   - allConceded: every matched handler returned null but the Response
//     type is non-nullable.
//
// `maybeRequest` / `maybeRequestSync` still catch all three and convert
// to null. Callers that need to distinguish catch
// `RequestUnavailableException` and switch on `reason`.
import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _Q {
  const _Q(this.text);
  final String text;
}

class _R {
  const _R(this.text);
  final String text;
}

void main() {
  group('RequestUnavailableException.reason as enum', () {
    test('noRegistration: thrown when no handler exists for the type pair',
        () async {
      final bus = EventBus();

      // Async path.
      await expectLater(
        () => bus.request<_Q, _R>(const _Q('q')),
        throwsA(
          isA<RequestUnavailableException>().having(
            (e) => e.reason,
            'reason',
            RequestUnavailableReason.noRegistration,
          ),
        ),
      );

      // Sync path.
      expect(
        () => bus.requestSync<_Q, _R>(const _Q('q')),
        throwsA(
          isA<RequestUnavailableException>().having(
            (e) => e.reason,
            'reason',
            RequestUnavailableReason.noRegistration,
          ),
        ),
      );
    });

    test(
      'noMatchingHandler: thrown when the type pair has handlers but the '
      'priority-merged list is empty for this identifier',
      () async {
        final bus = EventBus();
        // Register only an identifier-scoped handler. A request with a
        // different identifier finds the bucket but no matching handler.
        bus.onRequest<_Q, _R>(
          (env) => const _R('foo'),
          identifier: 'foo',
        );

        await expectLater(
          () => bus.request<_Q, _R>(const _Q('q'), identifier: 'bar'),
          throwsA(
            isA<RequestUnavailableException>().having(
              (e) => e.reason,
              'reason',
              RequestUnavailableReason.noMatchingHandler,
            ),
          ),
        );

        expect(
          () => bus.requestSync<_Q, _R>(const _Q('q'), identifier: 'bar'),
          throwsA(
            isA<RequestUnavailableException>().having(
              (e) => e.reason,
              'reason',
              RequestUnavailableReason.noMatchingHandler,
            ),
          ),
        );
      },
    );

    test(
      'allConceded: bucket lookups by (Request, Response) do not collapse '
      'across nullable / non-nullable Response generics',
      () async {
        // The allConceded throw site fires when every matched handler
        // returns null and Response is non-nullable. With Dart sound null
        // safety, a handler typed for a non-nullable Response cannot
        // legitimately return null (the await at the bus would throw a
        // TypeError before reaching the throw), so allConceded is
        // defensive code unreachable in well-typed runs. The enum value
        // and the toString are exercised by other tests in this group.
        //
        // This test pins a related shape: handlers registered under a
        // nullable Response are stored under a different bucket key than
        // a non-nullable request, so the request hits noRegistration
        // (not allConceded) when the type generic mismatches.
        final bus = EventBus();
        bus.onRequest<_Q, _R?>((env) async => null);
        bus.onRequest<_Q, _R?>((env) async => null);

        await expectLater(
          () => bus.request<_Q, _R>(const _Q('q')),
          throwsA(
            isA<RequestUnavailableException>().having(
              (e) => e.reason,
              'reason',
              RequestUnavailableReason.noRegistration,
            ),
          ),
        );
      },
    );

    test('callers can switch on reason exhaustively', () async {
      final bus = EventBus();
      try {
        await bus.request<_Q, _R>(const _Q('q'));
        fail('expected RequestUnavailableException');
      } on RequestUnavailableException catch (e) {
        // Exhaustive switch: no `default`, compiler enforces all cases.
        final label = switch (e.reason) {
          RequestUnavailableReason.noRegistration => 'register a handler',
          RequestUnavailableReason.noMatchingHandler =>
            'check identifier scope',
          RequestUnavailableReason.allConceded => 'add a fallback handler',
        };
        expect(label, 'register a handler');
      }
    });

    test(
      'maybeRequest / maybeRequestSync still convert every unavailability '
      'reason to null',
      () async {
        final bus = EventBus();

        // noRegistration
        expect(await bus.maybeRequest<_Q, _R>(const _Q('q')), isNull);
        expect(bus.maybeRequestSync<_Q, _R>(const _Q('q')), isNull);

        // noMatchingHandler
        bus.onRequestSync<_Q, _R>(
          (env) => const _R('foo'),
          identifier: 'foo',
        );
        expect(
          await bus.maybeRequest<_Q, _R>(const _Q('q'), identifier: 'bar'),
          isNull,
        );
        expect(
          bus.maybeRequestSync<_Q, _R>(const _Q('q'), identifier: 'bar'),
          isNull,
        );
      },
    );

    test('toString includes a human-readable description per reason', () {
      const noReg = RequestUnavailableException(
        requestType: _Q,
        responseType: _R,
        reason: RequestUnavailableReason.noRegistration,
      );
      const noMatch = RequestUnavailableException(
        requestType: _Q,
        responseType: _R,
        identifier: 'bar',
        reason: RequestUnavailableReason.noMatchingHandler,
      );
      const allConc = RequestUnavailableException(
        requestType: _Q,
        responseType: _R,
        reason: RequestUnavailableReason.allConceded,
      );

      expect(noReg.toString(), contains('no handler'));
      expect(noMatch.toString(), contains('identifier: bar'));
      expect(allConc.toString(), contains('conceded'));
    });
  });
}
