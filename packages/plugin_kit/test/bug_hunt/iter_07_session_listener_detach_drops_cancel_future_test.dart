import 'dart:async';

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _DelaySub implements EventSubscription {
  _DelaySub(this.inner, this.ready);
  final EventSubscription inner;
  final Future<void> ready;
  @override
  Future<void> cancel() async {
    await ready;
    await inner.cancel();
  }
}

class _DelayBinding implements EventBinding {
  _DelayBinding(this.ready, this.onEvent);
  final Completer<void> ready;
  final EventHandler<int> onEvent;
  @override
  EventSubscription attachTo(PluginSession session) =>
      _DelaySub(session.on<int>(onEvent), ready.future);
}

class _Listener with PluginSessionListener {
  _Listener(this.session, this.binding);
  @override
  final PluginSession session;
  final EventBinding binding;
  @override
  List<EventBinding> get subscriptions => <EventBinding>[binding];
}

void main() {
  group('bug-hunt iter 7: session-listener-detach-drops-cancel-future', () {
    test(
      'stops delivering session events before detachSubscriptions returns',
      () async {
        final runtime = PluginRuntime()..init(settings: RuntimeSettings());
        addTearDown(runtime.dispose);
        final session = await runtime.createSession();
        addTearDown(session.dispose);
        final gate = Completer<void>();
        final seen = <int>[];
        final listener = _Listener(
          session,
          _DelayBinding(gate, (e) => seen.add(e.event)),
        );

        listener.attachSubscriptions();
        // Open the cancel gate FIRST so the awaited cancellation can complete.
        gate.complete();
        // detachSubscriptions now returns Future<void> that resolves once every
        // underlying sub.cancel() resolves. Awaiting it guarantees no further
        // events will be dispatched to the handler.
        await listener.detachSubscriptions();
        await session.emit(1);

        expect(seen, isEmpty);
      },
    );
  });
}
