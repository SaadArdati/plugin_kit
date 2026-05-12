import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _Tick {
  const _Tick(this.count);
  final int count;
}

class _ListenerTestPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('plugin_kit.test.session_listener');

  @override
  void register(ScopedServiceRegistry registry) {}
}

class _Recorder with PluginSessionListener {
  _Recorder(this.session);

  @override
  final PluginSession session;

  final List<int> ticks = [];

  @override
  List<EventBinding> get subscriptions => [
    EventBinding.on<_Tick>((envelope) => ticks.add(envelope.event.count)),
  ];
}

class _SwappableRecorder with PluginSessionListener {
  _SwappableRecorder(this._session);

  PluginSession _session;

  @override
  PluginSession get session => _session;

  final List<int> ticks = [];

  @override
  List<EventBinding> get subscriptions => [
    EventBinding.on<_Tick>((envelope) => ticks.add(envelope.event.count)),
  ];

  void switchTo(PluginSession next) {
    detachSubscriptions();
    _session = next;
    attachSubscriptions();
  }
}

Future<PluginSession> _newSession() async {
  final runtime = PluginRuntime(plugins: [_ListenerTestPlugin()])
    ..init(settings: RuntimeSettings.empty());
  addTearDown(runtime.dispose);
  final session = await runtime.createSession();
  addTearDown(session.dispose);
  return session;
}

void main() {
  group('PluginSessionListener', () {
    test('attach receives events; detach stops them', () async {
      final session = await _newSession();
      final recorder = _Recorder(session);

      recorder.attachSubscriptions();
      await session.emit(const _Tick(1));
      await session.emit(const _Tick(2));
      expect(recorder.ticks, equals([1, 2]));

      recorder.detachSubscriptions();
      await session.emit(const _Tick(3));
      expect(recorder.ticks, equals([1, 2]));
    });

    test('double attach is a no-op (no duplicate subscriptions)', () async {
      final session = await _newSession();
      final recorder = _Recorder(session);

      recorder.attachSubscriptions();
      recorder.attachSubscriptions(); // second call must not duplicate

      await session.emit(const _Tick(7));
      expect(recorder.ticks, equals([7])); // exactly once, not [7, 7]
    });

    test('double detach is a no-op', () async {
      final session = await _newSession();
      final recorder = _Recorder(session);

      recorder.attachSubscriptions();
      recorder.detachSubscriptions();
      recorder.detachSubscriptions(); // second call must not throw

      await session.emit(const _Tick(1));
      expect(recorder.ticks, isEmpty);
    });

    test(
      're-attach after detach restores subscriptions from current bindings',
      () async {
        final session = await _newSession();
        final recorder = _Recorder(session);

        recorder.attachSubscriptions();
        await session.emit(const _Tick(1));
        recorder.detachSubscriptions();
        await session.emit(const _Tick(2)); // dropped while detached
        recorder.attachSubscriptions();
        await session.emit(const _Tick(3));

        expect(recorder.ticks, equals([1, 3]));
      },
    );

    test('manual session swap rebinds to the new session', () async {
      final sessionA = await _newSession();
      final sessionB = await _newSession();
      final recorder = _SwappableRecorder(sessionA);

      recorder.attachSubscriptions();
      await sessionA.emit(const _Tick(1));
      expect(recorder.ticks, equals([1]));

      recorder.switchTo(sessionB);
      await sessionA.emit(const _Tick(2)); // old session — dropped
      await sessionB.emit(const _Tick(3));
      expect(recorder.ticks, equals([1, 3]));
    });
  });
}
