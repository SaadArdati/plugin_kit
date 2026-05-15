import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_plugin_kit/flutter_plugin_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

class _Ping {
  const _Ping(this.value);
  final int value;
}

class _NoopPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('flutter_plugin_kit.test.noop');

  @override
  void register(ScopedServiceRegistry registry) {}
}

PluginRuntime _newRuntime() => PluginRuntime(plugins: [_NoopPlugin()])..init();

void main() {
  group('bug-hunt iter 5: session-listener-stale-old-session-event-after-swap', () {
    testWidgets('ignores late events from session A after swapping to session B', (
      tester,
    ) async {
      final runtime = _newRuntime();
      addTearDown(runtime.dispose);
      final sessionA = await runtime.createSession();
      final sessionB = await runtime.createSession();
      addTearDown(sessionA.dispose);
      addTearDown(sessionB.dispose);

      final gate = Completer<void>();
      final blocker = sessionA.on<_Ping>((_) async => gate.future, priority: 100);
      addTearDown(blocker.cancel);

      Widget tree(PluginSession session) => Directionality(
        textDirection: TextDirection.ltr,
        child: PluginSessionScope(session: session, child: const _Probe()),
      );

      await tester.pumpWidget(tree(sessionA));
      final inFlight = sessionA.emit(const _Ping(7));
      await tester.pump();

      await tester.pumpWidget(tree(sessionB));
      await tester.pump();

      gate.complete();
      await inFlight;
      await tester.pump();

      expect(find.text('idle'), findsOneWidget);
    });
  });
}

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with PluginSessionStateListener<_Probe> {
  int? _seen;

  @override
  void initState() {
    super.initState();
    listen<_Ping>((envelope) => setState(() => _seen = envelope.event.value));
  }

  @override
  Widget build(BuildContext context) => Text(_seen == null ? 'idle' : 'seen: $_seen');
}
