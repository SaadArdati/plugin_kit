// Sealed `NoRequestAnswerException` hierarchy: `request` / `requestSync`
// throw a typed subtype for the no-answer outcome so consumers can
// distinguish wiring bugs from genuinely conceded chains at the catch
// site without inspecting an enum.
//
// Two concrete subtypes (mirrors the throw sites in event_bus.dart):
//
//   - RequestNotWiredException (wasIdentifierMismatch: false): no
//     handlers registered for the (Request, Response) type pair at all.
//   - RequestNotWiredException (wasIdentifierMismatch: true): the type
//     pair has registered handlers, but the priority-merged set for the
//     requested identifier is empty.
//   - AllConcededException: every matched handler returned null but
//     the Response type is non-nullable.
//
// `maybeRequest` / `maybeRequestSync` still catch all three (via the
// sealed `NoRequestAnswerException` base) and convert to null. Callers
// that need to distinguish catch the subtypes individually.
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
  group('NoRequestAnswerException sealed hierarchy', () {
    test(
      'no handler for type pair throws RequestNotWiredException (wasIdentifierMismatch: false)',
      () async {
        final bus = EventBus();

        // Async path.
        await expectLater(
          () => bus.request<_Q, _R>(const _Q('q')),
          throwsA(
            isA<RequestNotWiredException>().having(
              (e) => e.wasIdentifierMismatch,
              'wasIdentifierMismatch',
              isFalse,
            ),
          ),
        );

        // Sync path.
        expect(
          () => bus.requestSync<_Q, _R>(const _Q('q')),
          throwsA(
            isA<RequestNotWiredException>().having(
              (e) => e.wasIdentifierMismatch,
              'wasIdentifierMismatch',
              isFalse,
            ),
          ),
        );
      },
    );

    test(
      'identifier mismatch throws RequestNotWiredException (wasIdentifierMismatch: true)',
      () async {
        final bus = EventBus();
        // Register only an identifier-scoped handler. A request with a
        // different identifier finds the bucket but no matching handler.
        bus.onRequest<_Q, _R>((env) => const _R('foo'), identifier: 'foo');

        await expectLater(
          () => bus.request<_Q, _R>(const _Q('q'), identifier: 'bar'),
          throwsA(
            isA<RequestNotWiredException>().having(
              (e) => e.wasIdentifierMismatch,
              'wasIdentifierMismatch',
              isTrue,
            ),
          ),
        );

        expect(
          () => bus.requestSync<_Q, _R>(const _Q('q'), identifier: 'bar'),
          throwsA(
            isA<RequestNotWiredException>().having(
              (e) => e.wasIdentifierMismatch,
              'wasIdentifierMismatch',
              isTrue,
            ),
          ),
        );
      },
    );

    test(
      'bucket lookups by (Request, Response) do not collapse across nullable / non-nullable Response generics',
      () async {
        // Pins bucket isolation: handlers registered under
        // `(Request, Response?)` live in a different bucket from
        // `(Request, Response)`. A request issued under the non-nullable
        // form does not see handlers registered under the nullable form,
        // so the no-wired-handler path fires regardless of how many
        // nullable-typed handlers exist.
        //
        // The AllConcededException-with-non-nullable-Response path
        // (the headline case for this plan) is exercised by the
        // 'callers can catch the two subtypes separately' test below.
        final bus = EventBus();
        bus.onRequest<_Q, _R?>((env) async => null);
        bus.onRequest<_Q, _R?>((env) async => null);

        await expectLater(
          () => bus.request<_Q, _R>(const _Q('q')),
          throwsA(isA<RequestNotWiredException>()),
        );
      },
    );

    test('callers can catch the two subtypes separately', () async {
      final bus = EventBus();
      // First, exercise the not-wired path.
      try {
        await bus.request<_Q, _R>(const _Q('q'));
        fail('expected RequestNotWiredException');
      } on RequestNotWiredException catch (e) {
        expect(e.requestType, _Q);
        expect(e.responseType, _R);
      } on AllConcededException {
        fail('expected RequestNotWiredException, got AllConcededException');
      }

      // Then, exercise the all-conceded path on a handler that returns null.
      bus.onRequest<_Q, _R>((env) async => null);
      try {
        await bus.request<_Q, _R>(const _Q('q'));
        fail('expected AllConcededException');
      } on RequestNotWiredException {
        fail('expected AllConcededException, got RequestNotWiredException');
      } on AllConcededException catch (e) {
        expect(e.requestType, _Q);
        expect(e.responseType, _R);
        expect(e.suggestion, contains('maybeRequest'));
      }
    });

    test(
      'maybeRequest / maybeRequestSync catch both subtypes via the shared base',
      () async {
        final bus = EventBus();

        // Not wired.
        expect(await bus.maybeRequest<_Q, _R>(const _Q('q')), isNull);
        expect(bus.maybeRequestSync<_Q, _R>(const _Q('q')), isNull);

        // Identifier mismatch.
        bus.onRequestSync<_Q, _R>((env) => const _R('foo'), identifier: 'foo');
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

    test('toString includes a human-readable description per subtype', () {
      final notWired = RequestNotWiredException(
        requestType: _Q,
        responseType: _R,
      );
      final identifierMismatch = RequestNotWiredException(
        requestType: _Q,
        responseType: _R,
        identifier: 'bar',
        wasIdentifierMismatch: true,
      );
      final allConceded = AllConcededException(
        requestType: _Q,
        responseType: _R,
      );

      expect(notWired.toString(), contains('no handler registered'));
      expect(
        notWired.toString(),
        contains('Register a handler with EventBus.onRequest'),
      );
      expect(identifierMismatch.toString(), contains('identifier: bar'));
      expect(
        identifierMismatch.toString(),
        contains('none matched the identifier'),
      );
      expect(allConceded.toString(), contains('conceded'));
      expect(allConceded.toString(), contains('maybeRequest'));
    });
  });
}
