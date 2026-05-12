// Regression tests for re-registration of a singleton or lazy-singleton.
//
// A `StatefulPluginService` whose `attach()` has already run owns
// subscriptions on the bus and has a bound `_context`. Silently replacing
// its wrapper would strand the old instance (its subscriptions still fire)
// and leave the new instance unattached (`_runAttach` has already completed
// for the plugin). The registry refuses this case so the misuse is loud
// instead of silently broken.
//
// Replacement remains allowed for:
//   - non-stateful PluginService instances (no lifecycle to unwind), and
//   - StatefulPluginService instances that were never attached
//     (no context bound, no subscriptions in flight).
import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _LifecycleSpyService
    extends StatefulPluginService<SessionPluginContext> {
  bool attachCalled = false;
  bool detachCalled = false;

  @override
  void attach() {
    attachCalled = true;
  }

  @override
  Future<void> detach() async {
    detachCalled = true;
  }
}

class _SwappingPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('swap_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_LifecycleSpyService>(
      const ServiceId('svc'),
      () => _LifecycleSpyService(),
    );
  }

  /// Re-registers the same singleton slot mid-session via `registry.raw`,
  /// simulating user code that tries to swap a stateful service
  /// implementation without going through plugin lifecycle.
  void swap(PluginSession session) {
    session.registry.registerSingleton<_LifecycleSpyService>(
      pluginId: pluginId,
      serviceId: const ServiceId('svc'),
      create: () => _LifecycleSpyService(),
    );
  }
}

class _LazySwappingPlugin extends SessionPlugin {
  _LazySwappingPlugin({required this.captureFirstInstance});

  final void Function(_LifecycleSpyService) captureFirstInstance;

  @override
  PluginId get pluginId => const PluginId('lazy_swap_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerLazySingleton<_LifecycleSpyService>(
      const ServiceId('svc'),
      () {
        final instance = _LifecycleSpyService();
        captureFirstInstance(instance);
        return instance;
      },
    );
  }

  void swap(PluginSession session) {
    session.registry.registerLazySingleton<_LifecycleSpyService>(
      pluginId: pluginId,
      serviceId: const ServiceId('svc'),
      factory: () => _LifecycleSpyService(),
    );
  }
}

class _NonStatefulService extends PluginService {}

class _NonStatefulSwappingPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('non_stateful_swap');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_NonStatefulService>(
      const ServiceId('svc'),
      () => _NonStatefulService(),
    );
  }

  void swap(PluginSession session) {
    session.registry.registerSingleton<_NonStatefulService>(
      pluginId: pluginId,
      serviceId: const ServiceId('svc'),
      create: () => _NonStatefulService(),
    );
  }
}

void main() {
  group('registerSingleton replacement guard', () {
    test(
      'rejects replacement when the existing singleton is an attached StatefulPluginService',
      () async {
        final plugin = _SwappingPlugin();
        final runtime = PluginRuntime(plugins: [plugin])..init();
        final session = await runtime.createSession();

        // Sanity: the first instance was attached during session init.
        final firstInstance =
            session.resolve<_LifecycleSpyService>(const ServiceId('svc'));
        expect(firstInstance.attachCalled, isTrue);
        expect(firstInstance.hasContext, isTrue);

        // Replacement of a LIVE stateful service must throw. Without the
        // guard, the old instance is stranded (subscriptions still live,
        // context still bound) AND the new instance is never attached.
        expect(
          () => plugin.swap(session),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('StatefulPluginService is attached'),
                contains('plugin "${plugin.pluginId.value}"'),
                contains('"svc"'),
              ),
            ),
          ),
        );

        // The original instance is untouched after a rejected replacement.
        expect(firstInstance.detachCalled, isFalse);
        expect(firstInstance.hasContext, isTrue);

        await runtime.dispose();
      },
    );

    test(
      'allows replacement when the existing singleton is a non-stateful PluginService',
      () async {
        final plugin = _NonStatefulSwappingPlugin();
        final runtime = PluginRuntime(plugins: [plugin])..init();
        final session = await runtime.createSession();

        // Non-stateful service has no lifecycle to unwind; replacement is
        // the documented "model swap" path and stays silent.
        expect(() => plugin.swap(session), returnsNormally);

        await runtime.dispose();
      },
    );

    test(
      'allows replacement when the existing StatefulPluginService was never attached',
      () {
        // Direct registry use without going through a runtime. The
        // StatefulPluginService is constructed (registerSingleton runs the
        // factory) but never bound to a context because no plugin
        // lifecycle ran. Replacement is safe in this state.
        final registry = ServiceRegistry();
        registry.registerSingleton<_LifecycleSpyService>(
          pluginId: const PluginId('p'),
          serviceId: const ServiceId('svc'),
          create: () => _LifecycleSpyService(),
        );

        final first =
            registry.resolve<_LifecycleSpyService>(const ServiceId('svc'));
        expect(first.hasContext, isFalse);

        expect(
          () => registry.registerSingleton<_LifecycleSpyService>(
            pluginId: const PluginId('p'),
            serviceId: const ServiceId('svc'),
            create: () => _LifecycleSpyService(),
          ),
          returnsNormally,
        );
      },
    );

    test(
      'rejected replacement leaves the registry list unchanged',
      () async {
        final plugin = _SwappingPlugin();
        final runtime = PluginRuntime(plugins: [plugin])..init();
        final session = await runtime.createSession();

        final firstInstance =
            session.resolve<_LifecycleSpyService>(const ServiceId('svc'));
        final beforeIds = session.registry.listAllServiceIds();
        final beforeRegistrations =
            session.registry.getRegistrations(const ServiceId('svc'))!;

        expect(() => plugin.swap(session), throwsArgumentError);

        // The wrapper list for this service is byte-equivalent to its
        // pre-reject state: same length, same wrapper identities, and the
        // resolver still hands back the original instance.
        expect(session.registry.listAllServiceIds(), beforeIds);
        final afterRegistrations =
            session.registry.getRegistrations(const ServiceId('svc'))!;
        expect(afterRegistrations.length, beforeRegistrations.length);
        expect(
          identical(afterRegistrations.first, beforeRegistrations.first),
          isTrue,
          reason: 'wrapper identity must survive a rejected replacement',
        );
        expect(
          identical(
            session.resolve<_LifecycleSpyService>(const ServiceId('svc')),
            firstInstance,
          ),
          isTrue,
          reason: 'resolved instance identity must survive a rejected replacement',
        );

        await runtime.dispose();
      },
    );

    test(
      'does not run the replacement factory when the call is rejected',
      () async {
        // Side effects from the replacement factory must not leak when the
        // guard rejects the call.
        final plugin = _SwappingPlugin();
        final runtime = PluginRuntime(plugins: [plugin])..init();
        final session = await runtime.createSession();

        // Force the first instance to attach.
        session.resolve<_LifecycleSpyService>(const ServiceId('svc'));

        var factoryRan = false;
        expect(
          () => session.registry.registerSingleton<_LifecycleSpyService>(
            pluginId: plugin.pluginId,
            serviceId: const ServiceId('svc'),
            create: () {
              factoryRan = true;
              return _LifecycleSpyService();
            },
          ),
          throwsArgumentError,
        );
        expect(
          factoryRan,
          isFalse,
          reason:
              'replacement factory must not run when the guard rejects the call',
        );

        await runtime.dispose();
      },
    );
  });

  group('register* leaves no empty bucket on failure', () {
    test(
      'registerSingleton: a throwing factory does not leave an empty bucket in _registry',
      () {
        // Pre-fix: `_registry[serviceId] ??= []` ran before `create()`, so
        // a throwing factory polluted the registry with an empty list.
        // Symptoms: listAllServiceIds returned the id with no registrations,
        // resolve threw "all disabled by overrides" instead of "no service
        // registered".
        final registry = ServiceRegistry();
        expect(
          () => registry.registerSingleton<_NonStatefulService>(
            pluginId: const PluginId('p'),
            serviceId: const ServiceId('svc'),
            create: () => throw StateError('factory boom'),
          ),
          throwsStateError,
        );

        expect(
          registry.listAllServiceIds().contains(const ServiceId('svc')),
          isFalse,
          reason: 'a failed factory must not leave an empty bucket behind',
        );
        expect(
          () => registry.resolve<_NonStatefulService>(const ServiceId('svc')),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('No service registered'),
            ),
          ),
          reason:
              'resolve must report "not registered", not "all disabled by overrides"',
        );
      },
    );

    test(
      'registerSingleton: a rejected replacement does not leave an empty bucket',
      () async {
        // Even on the reject path, the bucket already existed (the first
        // registration created it), so this is really asserting that the
        // original registration list is intact. Paired with the regression
        // above to cover both empty-bucket avenues.
        final plugin = _SwappingPlugin();
        final runtime = PluginRuntime(plugins: [plugin])..init();
        final session = await runtime.createSession();

        session.resolve<_LifecycleSpyService>(const ServiceId('svc'));
        expect(() => plugin.swap(session), throwsArgumentError);

        final registrations =
            session.registry.getRegistrations(const ServiceId('svc'));
        expect(registrations, isNotNull);
        expect(registrations!.isNotEmpty, isTrue);

        await runtime.dispose();
      },
    );
  });

  group('registerLazySingleton replacement guard', () {
    test(
      'rejects replacement when the existing lazy-singleton is an attached StatefulPluginService',
      () async {
        late _LifecycleSpyService firstInstance;
        final plugin = _LazySwappingPlugin(
          captureFirstInstance: (i) => firstInstance = i,
        );
        final runtime = PluginRuntime(plugins: [plugin])..init();
        final session = await runtime.createSession();

        // Force lazy resolution + attach.
        session.resolve<_LifecycleSpyService>(const ServiceId('svc'));
        expect(firstInstance.attachCalled, isTrue);
        expect(firstInstance.hasContext, isTrue);

        expect(
          () => plugin.swap(session),
          throwsA(isA<ArgumentError>()),
        );

        expect(firstInstance.detachCalled, isFalse);
        expect(firstInstance.hasContext, isTrue);

        await runtime.dispose();
      },
    );

    test(
      'allows replacement when the lazy factory has never fired',
      () {
        // The lazy-singleton wrapper exists but the factory has not run, so
        // there is no instance to strand. Replacement is safe.
        final registry = ServiceRegistry();
        registry.registerLazySingleton<_LifecycleSpyService>(
          pluginId: const PluginId('p'),
          serviceId: const ServiceId('svc'),
          factory: () => _LifecycleSpyService(),
        );

        // Note: no `resolve` call here, so the factory has not run.
        expect(
          () => registry.registerLazySingleton<_LifecycleSpyService>(
            pluginId: const PluginId('p'),
            serviceId: const ServiceId('svc'),
            factory: () => _LifecycleSpyService(),
          ),
          returnsNormally,
        );
      },
    );
  });
}
