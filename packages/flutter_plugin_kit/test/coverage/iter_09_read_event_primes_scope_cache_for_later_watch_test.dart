import 'package:flutter/material.dart';
import 'package:flutter_plugin_kit/flutter_plugin_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

class _Ping {
  const _Ping(this.value);
  final int value;
}

void main() {
  testWidgets(
    'readEvent primes scope cache so later watchEvent sees the emitted value without a second emit',
    (tester) async {
      final runtime = PluginRuntime()..init();
      addTearDown(runtime.dispose);
      final session = await runtime.createSession();
      addTearDown(session.dispose);

      var useWatch = false;
      var readBuilds = 0;
      StateSetter? toggle;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (_, setState) {
              toggle = setState;
              return PluginSessionScope(
                session: session,
                child: Builder(
                  builder: (context) {
                    final ping = useWatch
                        ? context.watchEvent<_Ping>()
                        : context.readEvent<_Ping>();
                    if (!useWatch) readBuilds++;
                    return Text('val: ${ping?.value ?? 'none'}');
                  },
                ),
              );
            },
          ),
        ),
      );

      await session.emit(const _Ping(7));
      await tester.pump();
      expect(readBuilds, 1);

      toggle!(() => useWatch = true);
      await tester.pump();
      expect(find.text('val: 7'), findsOneWidget);
    },
  );
}
