import 'package:logging/logging.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

const _globalPluginId = PluginId('contract_global');
const _sessionPluginId = PluginId('contract_session');
const _addedGlobalPluginId = PluginId('contract_added_global');
const _addedSessionPluginId = PluginId('contract_added_session');

const _enabledSettings = RuntimeSettings(
  plugins: {
    _globalPluginId: PluginConfig(enabled: true),
    _sessionPluginId: PluginConfig(enabled: true),
  },
);

const _disabledSettings = RuntimeSettings(
  plugins: {
    _globalPluginId: PluginConfig(enabled: false),
    _sessionPluginId: PluginConfig(enabled: false),
  },
);

class _NoopGlobalPlugin extends GlobalPlugin {
  _NoopGlobalPlugin(this.id);

  final PluginId id;

  @override
  PluginId get pluginId => id;
}

class _NoopSessionPlugin extends SessionPlugin {
  _NoopSessionPlugin(this.id);

  final PluginId id;

  @override
  PluginId get pluginId => id;
}

class _ExperimentalPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('contract_experimental');

  @override
  List<FeatureFlag> get featureFlags => const [FeatureFlag.experimental];
}

class _LockedPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('contract_locked');

  @override
  List<FeatureFlag> get featureFlags => const [FeatureFlag.locked];
}

typedef _InitMethod =
    PluginRuntime<GlobalPluginContext, SessionPluginContext> Function({
      RuntimeSettings? settings,
      GlobalContextFactory<GlobalPluginContext, SessionPluginContext>?
      globalContextFactory,
      UnknownReferencePolicy unknownReferencePolicy,
    });

typedef _DisposeMethod = Future<void> Function();

typedef _UpdateSettingsMethod =
    Future<void> Function(RuntimeSettings newSettings);

typedef _UpdateGlobalSettingsMethod =
    Future<void> Function({
      required RuntimeSettings oldSettings,
      required RuntimeSettings newSettings,
    });

typedef _UpdateSettingsSnapshotMethod = void Function(RuntimeSettings value);

typedef _ResetSettingsMethod = void Function();

typedef _CreateSessionMethod =
    Future<PluginSession<SessionPluginContext>> Function({
      RuntimeSettings? settings,
      SessionContextFactory<GlobalPluginContext, SessionPluginContext>?
      contextFactory,
    });

typedef _UpdateSessionSettingsMethod =
    Future<void> Function(
      PluginSession<SessionPluginContext> session, {
      required RuntimeSettings newSettings,
    });

typedef _AddPluginMethod = void Function(Plugin plugin);

typedef _AddPluginsMethod = void Function(List<Plugin> plugins);

typedef _IsPluginEnabledMethod =
    bool Function(PluginId pluginId, [RuntimeSettings? settings]);

typedef _IsPluginAttachedMethod = bool Function(PluginId pluginId);

typedef _IsPluginEnabledByDefaultMethod = bool Function(Plugin plugin);

class _OverrideSubclass<
  G extends GlobalPluginContext,
  S extends SessionPluginContext
>
    extends PluginRuntime<G, S> {
  _OverrideSubclass({super.plugins});

  final List<String> calls = [];

  @override
  PluginRuntime init({
    RuntimeSettings? settings,
    GlobalContextFactory<G, S>? globalContextFactory,
    UnknownReferencePolicy unknownReferencePolicy =
        UnknownReferencePolicy.throwError,
  }) {
    calls.add('init');
    return super.init(
      settings: settings,
      globalContextFactory: globalContextFactory,
      unknownReferencePolicy: unknownReferencePolicy,
    );
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await super.dispose();
  }

  @override
  Future<void> updateSettings(RuntimeSettings newSettings) async {
    calls.add('updateSettings');
    await super.updateSettings(newSettings);
  }

  @override
  Future<void> updateGlobalSettings({
    required RuntimeSettings oldSettings,
    required RuntimeSettings newSettings,
  }) async {
    calls.add('updateGlobalSettings');
    await super.updateGlobalSettings(
      oldSettings: oldSettings,
      newSettings: newSettings,
    );
  }

  @override
  void updateSettingsSnapshot(RuntimeSettings value) {
    calls.add('updateSettingsSnapshot');
    super.updateSettingsSnapshot(value);
  }

  @override
  void resetSettings() {
    calls.add('resetSettings');
    super.resetSettings();
  }

  @override
  Future<PluginSession<S>> createSession({
    RuntimeSettings? settings,
    SessionContextFactory<G, S>? contextFactory,
  }) async {
    calls.add('createSession');
    return super.createSession(
      settings: settings,
      contextFactory: contextFactory,
    );
  }

  @override
  Future<void> updateSessionSettings(
    PluginSession<S> session, {
    required RuntimeSettings newSettings,
  }) async {
    calls.add('updateSessionSettings');
    await super.updateSessionSettings(session, newSettings: newSettings);
  }

  @override
  void addPlugin(Plugin plugin) {
    calls.add('addPlugin');
    super.addPlugin(plugin);
  }

  @override
  void addPlugins(List<Plugin> plugins) {
    calls.add('addPlugins');
    super.addPlugins(plugins);
  }

  @override
  bool isPluginEnabled(PluginId pluginId, [RuntimeSettings? settings]) {
    calls.add('isPluginEnabled');
    return super.isPluginEnabled(pluginId, settings);
  }

  @override
  bool isPluginAttached(PluginId pluginId) {
    calls.add('isPluginAttached');
    return super.isPluginAttached(pluginId);
  }
}

PluginRuntime<GlobalPluginContext, SessionPluginContext> _newRuntime() {
  return PluginRuntime<GlobalPluginContext, SessionPluginContext>(
    plugins: [
      _NoopGlobalPlugin(_globalPluginId),
      _NoopSessionPlugin(_sessionPluginId),
    ],
  );
}

Future<void> _runContractSequence(
  PluginRuntime<GlobalPluginContext, SessionPluginContext> runtime,
) async {
  runtime.addPlugin(_NoopGlobalPlugin(_addedGlobalPluginId));
  runtime.addPlugins([_NoopSessionPlugin(_addedSessionPluginId)]);
  final inited = runtime.init(settings: _enabledSettings);
  expect(inited, same(runtime));

  final session = await runtime.createSession(settings: _enabledSettings);

  await runtime.updateSessionSettings(session, newSettings: _disabledSettings);
  await runtime.updateGlobalSettings(
    oldSettings: runtime.settings,
    newSettings: _enabledSettings,
  );
  await runtime.updateSettings(_enabledSettings);
  runtime.updateSettingsSnapshot(_disabledSettings);
  runtime.resetSettings();

  runtime.isPluginEnabled(_globalPluginId);
  runtime.isPluginAttached(_globalPluginId);

  await runtime.dispose();
}

void main() {
  group('public API contract', () {
    test(
      'static dispatch baseline covers all public runtime methods',
      () async {
        final runtime = _newRuntime();
        await _runContractSequence(runtime);

        final experimental = _ExperimentalPlugin();
        final locked = _LockedPlugin();
        expect(PluginRuntime.isPluginEnabledByDefault(experimental), isFalse);
        expect(PluginRuntime.isPluginEnabledByDefault(locked), isTrue);
      },
    );

    test('dynamic dispatch fails if methods move off the class', () async {
      final runtime = _newRuntime();
      final dynamic dyn = runtime;

      dyn.addPlugin(_NoopGlobalPlugin(_addedGlobalPluginId));
      dyn.addPlugins([_NoopSessionPlugin(_addedSessionPluginId)]);
      final inited = dyn.init(settings: _enabledSettings);
      expect(inited, same(runtime));

      final session =
          await dyn.createSession(settings: _enabledSettings)
              as PluginSession<SessionPluginContext>;

      await dyn.updateSessionSettings(session, newSettings: _disabledSettings);
      await dyn.updateGlobalSettings(
        oldSettings: runtime.settings,
        newSettings: _enabledSettings,
      );
      await dyn.updateSettings(_enabledSettings);
      dyn.updateSettingsSnapshot(_disabledSettings);
      dyn.resetSettings();

      dyn.isPluginEnabled(_globalPluginId);
      dyn.isPluginAttached(_globalPluginId);

      await dyn.dispose();

      expect(
        PluginRuntime.isPluginEnabledByDefault(_ExperimentalPlugin()),
        isFalse,
      );
    });

    test('subclass override remains valid for every public method', () async {
      final runtime =
          _OverrideSubclass<GlobalPluginContext, SessionPluginContext>(
            plugins: [
              _NoopGlobalPlugin(_globalPluginId),
              _NoopSessionPlugin(_sessionPluginId),
            ],
          );

      runtime.addPlugin(_NoopGlobalPlugin(_addedGlobalPluginId));
      runtime.addPlugins([_NoopSessionPlugin(_addedSessionPluginId)]);
      runtime.init(settings: _enabledSettings);
      final session = await runtime.createSession(settings: _enabledSettings);

      await runtime.updateSessionSettings(
        session,
        newSettings: _disabledSettings,
      );
      await runtime.updateGlobalSettings(
        oldSettings: runtime.settings,
        newSettings: _enabledSettings,
      );
      await runtime.updateSettings(_enabledSettings);
      runtime.updateSettingsSnapshot(_disabledSettings);
      runtime.resetSettings();
      runtime.isPluginEnabled(_globalPluginId);
      runtime.isPluginAttached(_globalPluginId);
      await runtime.dispose();

      expect(
        runtime.calls,
        containsAll(<String>[
          'addPlugin',
          'addPlugins',
          'init',
          'createSession',
          'updateSessionSettings',
          'updateGlobalSettings',
          'updateSettings',
          'updateSettingsSnapshot',
          'resetSettings',
          'isPluginEnabled',
          'isPluginAttached',
          'dispose',
        ]),
      );
    });

    test(
      'tear-off type contract remains stable for every public method',
      () async {
        final runtime = _newRuntime();

        final _InitMethod initRef = runtime.init;
        final _DisposeMethod disposeRef = runtime.dispose;
        final _UpdateSettingsMethod updateSettingsRef = runtime.updateSettings;
        final _UpdateGlobalSettingsMethod updateGlobalSettingsRef =
            runtime.updateGlobalSettings;
        final _UpdateSettingsSnapshotMethod updateSettingsSnapshotRef =
            runtime.updateSettingsSnapshot;
        final _ResetSettingsMethod resetSettingsRef = runtime.resetSettings;
        final _CreateSessionMethod createSessionRef = runtime.createSession;
        final _UpdateSessionSettingsMethod updateSessionSettingsRef =
            runtime.updateSessionSettings;
        final _AddPluginMethod addPluginRef = runtime.addPlugin;
        final _AddPluginsMethod addPluginsRef = runtime.addPlugins;
        final _IsPluginEnabledMethod isPluginEnabledRef =
            runtime.isPluginEnabled;
        final _IsPluginAttachedMethod isPluginAttachedRef =
            runtime.isPluginAttached;
        final _IsPluginEnabledByDefaultMethod isPluginEnabledByDefaultRef =
            PluginRuntime.isPluginEnabledByDefault;

        addPluginRef(_NoopGlobalPlugin(_addedGlobalPluginId));
        addPluginsRef([_NoopSessionPlugin(_addedSessionPluginId)]);
        final inited = initRef(settings: _enabledSettings);
        expect(inited, same(runtime));

        final session = await createSessionRef(settings: _enabledSettings);
        await updateSessionSettingsRef(session, newSettings: _disabledSettings);
        await updateGlobalSettingsRef(
          oldSettings: runtime.settings,
          newSettings: _enabledSettings,
        );
        await updateSettingsRef(_enabledSettings);
        updateSettingsSnapshotRef(_disabledSettings);
        resetSettingsRef();

        isPluginEnabledRef(_globalPluginId);
        isPluginAttachedRef(_globalPluginId);

        expect(isPluginEnabledByDefaultRef(_ExperimentalPlugin()), isFalse);
        expect(isPluginEnabledByDefaultRef(_LockedPlugin()), isTrue);

        await disposeRef();
      },
    );

    test('updateSettings emits a PluginRuntime logger record', () async {
      final records = <LogRecord>[];
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord.listen(records.add);
      addTearDown(() async {
        await sub.cancel();
        Logger.root.level = previousLevel;
      });

      final runtime = _newRuntime()..init(settings: _enabledSettings);
      addTearDown(runtime.dispose);

      await runtime.updateSettings(_disabledSettings);

      expect(
        records.any((r) => r.loggerName == 'plugin_kit.PluginRuntime'),
        isTrue,
      );
    });
  });
}
