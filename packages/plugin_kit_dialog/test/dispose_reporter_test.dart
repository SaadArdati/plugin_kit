import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit_dialog/src/utils.dart';

void main() {
  group('plugin_kit_dialog disposeAndReport', () {
    testWidgets(
      'routes a synchronous throw before the future returns through reportError',
      (tester) async {
        disposeAndReport(
          () => throw StateError('intentional sync throw'),
          contextDescription: 'sync-path test',
        );
        await tester.pumpAndSettle();

        final error = tester.takeException();
        expect(error, isA<StateError>());
        expect(
          (error as StateError).message,
          contains('intentional sync throw'),
        );
      },
    );

    testWidgets('routes a throw on the returned future through reportError', (
      tester,
    ) async {
      disposeAndReport(
        () async => throw StateError('intentional async throw'),
        contextDescription: 'async-path test',
      );
      await tester.pumpAndSettle();

      final error = tester.takeException();
      expect(error, isA<StateError>());
      expect(
        (error as StateError).message,
        contains('intentional async throw'),
      );
    });

    testWidgets(
      'reported FlutterErrorDetails carry the helper library and context for sync throws',
      (tester) async {
        final captured = <FlutterErrorDetails>[];
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          captured.add(details);
          original?.call(details);
        };

        try {
          disposeAndReport(
            () => throw StateError('sync metadata test'),
            contextDescription: 'sync metadata marker',
          );
          await tester.pumpAndSettle();

          expect(captured, hasLength(1));
          expect(captured.single.library, equals('plugin_kit_dialog'));
          expect(
            captured.single.context.toString(),
            contains('sync metadata marker'),
          );
        } finally {
          FlutterError.onError = original;
        }

        tester.takeException();
      },
    );

    testWidgets(
      'reported FlutterErrorDetails carry the helper library and context for async throws',
      (tester) async {
        final captured = <FlutterErrorDetails>[];
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          captured.add(details);
          original?.call(details);
        };

        try {
          disposeAndReport(
            () async => throw StateError('async metadata test'),
            contextDescription: 'async metadata marker',
          );
          await tester.pumpAndSettle();

          expect(captured, hasLength(1));
          expect(captured.single.library, equals('plugin_kit_dialog'));
          expect(
            captured.single.context.toString(),
            contains('async metadata marker'),
          );
        } finally {
          FlutterError.onError = original;
        }

        tester.takeException();
      },
    );

    testWidgets('a successful dispose closure does not surface any error', (
      tester,
    ) async {
      var ran = false;
      disposeAndReport(() async {
        ran = true;
      }, contextDescription: 'happy path');
      await tester.pumpAndSettle();

      expect(ran, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
