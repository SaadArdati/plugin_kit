import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group('ServiceRegistry disabled-override enforcement', () {
    test('resolve throws when the sole registration is disabled', () {
      final registry = ServiceRegistry(
        overrides: [
          const LocalPluginOverride.disable(
            plugin: PluginId('alpha'),
            serviceId: ServiceId('svc'),
          ),
        ],
      );
      registry.registerSingleton<String>(
        pluginId: const PluginId('alpha'),
        serviceId: const ServiceId('svc'),
        create: () => 'alpha impl',
        priority: 100,
      );

      expect(
        () => registry.resolve<String>(const ServiceId('svc')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disabled by overrides'),
          ),
        ),
      );
    });

    test('resolve falls through to the next-priority enabled wrapper', () {
      final registry = ServiceRegistry(
        overrides: [
          const LocalPluginOverride.disable(
            plugin: PluginId('alpha'),
            serviceId: ServiceId('svc'),
          ),
        ],
      );
      registry.registerSingleton<String>(
        pluginId: const PluginId('alpha'),
        serviceId: const ServiceId('svc'),
        create: () => 'alpha impl',
        priority: 100,
      );
      registry.registerSingleton<String>(
        pluginId: const PluginId('beta'),
        serviceId: const ServiceId('svc'),
        create: () => 'beta impl',
        priority: 50,
      );

      expect(registry.resolve<String>(const ServiceId('svc')), 'beta impl');
    });

    test('resolveAfter skips disabled wrappers past the target', () {
      final registry = ServiceRegistry(
        overrides: [
          const LocalPluginOverride.disable(
            plugin: PluginId('beta'),
            serviceId: ServiceId('svc'),
          ),
        ],
      );
      registry.registerSingleton<String>(
        pluginId: const PluginId('alpha'),
        serviceId: const ServiceId('svc'),
        create: () => 'alpha impl',
        priority: 100,
      );
      registry.registerSingleton<String>(
        pluginId: const PluginId('beta'),
        serviceId: const ServiceId('svc'),
        create: () => 'beta impl',
        priority: 80,
      );
      registry.registerSingleton<String>(
        pluginId: const PluginId('gamma'),
        serviceId: const ServiceId('svc'),
        create: () => 'gamma impl',
        priority: 60,
      );

      // After alpha: beta is disabled, so gamma wins.
      expect(
        registry.resolveAfter<String>(
          pluginId: const PluginId('alpha'),
          serviceId: const ServiceId('svc'),
        ),
        'gamma impl',
      );
    });

    test('resolveAfter throws when the target is the last in the chain', () {
      // The list ordering is descending priority. alpha (100) is first,
      // beta (50) second. resolveAfter past beta has no successor — the
      // method must throw StateError naming the plugin and service id.
      // The forbidden substring guards against a regression in which a
      // disabled-but-present successor was the failure path: the wrong
      // branch's message ("disabled by overrides") would still match
      // contains('after plugin') and pass a looser assertion.
      // #docregion service-registry-test-registry
      final registry = ServiceRegistry();
      // #enddocregion service-registry-test-registry
      registry.registerSingleton<String>(
        pluginId: const PluginId('alpha'),
        serviceId: const ServiceId('svc'),
        create: () => 'alpha impl',
        priority: 100,
      );
      registry.registerSingleton<String>(
        pluginId: const PluginId('beta'),
        serviceId: const ServiceId('svc'),
        create: () => 'beta impl',
        priority: 50,
      );

      expect(
        () => registry.resolveAfter<String>(
          pluginId: const PluginId('beta'),
          serviceId: const ServiceId('svc'),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('after plugin "beta"'),
              contains('"svc"'),
              isNot(contains('disabled by overrides')),
            ),
          ),
        ),
      );
    });

    test('resolveAfter throws when the target plugin is not registered', () {
      // The cursor plugin id "ghost" is not in the chain at all.
      // resolveAfter must walk to the end without finding it and throw
      // StateError naming the missing plugin. Forbidden substrings here
      // distinguish this branch from "all candidates disabled" and from
      // "no service registered for slot".
      final registry = ServiceRegistry();
      registry.registerSingleton<String>(
        pluginId: const PluginId('alpha'),
        serviceId: const ServiceId('svc'),
        create: () => 'alpha impl',
        priority: 100,
      );
      registry.registerSingleton<String>(
        pluginId: const PluginId('beta'),
        serviceId: const ServiceId('svc'),
        create: () => 'beta impl',
        priority: 50,
      );

      expect(
        () => registry.resolveAfter<String>(
          pluginId: const PluginId('ghost'),
          serviceId: const ServiceId('svc'),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('after plugin "ghost"'),
              contains('"svc"'),
              isNot(contains('disabled by overrides')),
            ),
          ),
        ),
      );
    });

    test('resolveAfter throws when no service is registered for the slot', () {
      // No registrations exist for this serviceId at all. The branch's
      // canonical message starts with "No service registered for" — distinct
      // from the "after plugin ..." message used by the chain-end and
      // unknown-target branches above.
      final registry = ServiceRegistry();

      expect(
        () => registry.resolveAfter<String>(
          pluginId: const PluginId('alpha'),
          serviceId: const ServiceId('missing'),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('No service registered for "missing"'),
              isNot(contains('after plugin')),
            ),
          ),
        ),
      );
    });

    test('resolveAfter finds the target even when the target is disabled', () {
      // resolveAfter uses pluginId as a cursor; the target's own enabled
      // state is not consulted when locating it. Only the walk past the
      // target skips disabled candidates.
      final registry = ServiceRegistry(
        overrides: [
          const LocalPluginOverride.disable(
            plugin: PluginId('alpha'),
            serviceId: ServiceId('svc'),
          ),
        ],
      );
      registry.registerSingleton<String>(
        pluginId: const PluginId('alpha'),
        serviceId: const ServiceId('svc'),
        create: () => 'alpha impl',
        priority: 100,
      );
      registry.registerSingleton<String>(
        pluginId: const PluginId('beta'),
        serviceId: const ServiceId('svc'),
        create: () => 'beta impl',
        priority: 50,
      );

      expect(
        registry.resolveAfter<String>(
          pluginId: const PluginId('alpha'),
          serviceId: const ServiceId('svc'),
        ),
        'beta impl',
      );
    });

    test('maybeResolve returns null when every registration is disabled', () {
      final registry = ServiceRegistry(
        overrides: [
          const LocalPluginOverride.disable(
            plugin: PluginId('alpha'),
            serviceId: ServiceId('svc'),
          ),
          const LocalPluginOverride.disable(
            plugin: PluginId('beta'),
            serviceId: ServiceId('svc'),
          ),
        ],
      );
      registry.registerSingleton<String>(
        pluginId: const PluginId('alpha'),
        serviceId: const ServiceId('svc'),
        create: () => 'alpha impl',
        priority: 100,
      );
      registry.registerSingleton<String>(
        pluginId: const PluginId('beta'),
        serviceId: const ServiceId('svc'),
        create: () => 'beta impl',
        priority: 50,
      );

      // Distinct from "not registered": the slot exists, every candidate
      // is disabled. maybeResolve collapses both to null.
      expect(registry.maybeResolve<String>(const ServiceId('svc')), isNull);
    });

    test(
      'plugin-specific override beats wildcard override in disable precedence',
      () {
        // Wildcard disables the slot generally; a plugin-specific override
        // with enabled: true revives the match. Matches the precedence
        // documented on _overrideForInjection. RuntimeSettings maps
        // `*:serviceId` keys to an override keyed under
        // [PluginId.winnerScoped].
        final registry = ServiceRegistry(
          overrides: [
            const LocalPluginOverride.disable(
              plugin: PluginId.winnerScoped,
              serviceId: ServiceId('svc'),
            ),
            const LocalPluginOverride(
              plugin: PluginId('alpha'),
              serviceId: ServiceId('svc'),
              // `enabled` defaults to true.
            ),
          ],
        );
        registry.registerSingleton<String>(
          pluginId: const PluginId('alpha'),
          serviceId: const ServiceId('svc'),
          create: () => 'alpha impl',
          priority: 100,
        );

        expect(registry.resolve<String>(const ServiceId('svc')), 'alpha impl');
      },
    );
  });

  group('ServiceRegistry detach-before-unregister ordering invariant', () {
    // The reconciliation disable path runs plugin.detach before unregistering
    // the plugin's services. That's load-bearing: Plugin.detach (the base
    // impl) iterates the plugin's registered StatefulPluginServices via
    // getPluginServices(pluginId). If the registry were mutated first, the
    // iteration would return nothing and stateful services would leak their
    // subscriptions.
    //
    // This test asserts the invariant directly against getPluginServices.
    test('getPluginServices returns the plugin services before unregister', () {
      final registry = ServiceRegistry();
      registry.registerSingleton<String>(
        pluginId: const PluginId('alpha'),
        serviceId: const ServiceId('svc'),
        create: () => 'alpha impl',
      );

      final before = registry.getPluginServices(const PluginId('alpha'));
      expect(before, hasLength(1));
      expect(before.first, 'alpha impl');

      registry.unregister(
        pluginId: const PluginId('alpha'),
        serviceId: const ServiceId('svc'),
      );

      final after = registry.getPluginServices(const PluginId('alpha'));
      expect(after, isEmpty);
    });
  });

  group('ServiceId.topNamespace', () {
    test('returns the prefix before the first dot', () {
      expect(ServiceId('main_agent.service').topNamespace, 'main_agent');
    });

    test('splits on the first dot only', () {
      expect(ServiceId('a.b.c').topNamespace, 'a');
    });

    test('returns null for serviceIds without a dot', () {
      expect(ServiceId('service').topNamespace, isNull);
    });

    test('returns null when the serviceId starts with a dot', () {
      // Treat a leading dot as "no namespace" rather than an empty namespace,
      // so callers can `?? 'root'` without producing an empty bucket.
      expect(ServiceId('.service').topNamespace, isNull);
    });

    test('returns null for an empty serviceId', () {
      expect(ServiceId('').topNamespace, isNull);
    });
  });

  group('registerFactory rejects StatefulPluginService', () {
    test('throws ArgumentError when T is a StatefulPluginService subtype', () {
      final registry = ServiceRegistry();
      expect(
        () => registry.registerFactory<_StatefulFixture>(
          pluginId: const PluginId('alpha'),
          serviceId: const ServiceId('stateful'),
          create: _StatefulFixture.new,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('singleton or lazy singleton'),
          ),
        ),
      );
    });

    test('allows non-stateful PluginService as a factory', () {
      final registry = ServiceRegistry();
      registry.registerFactory<_StatelessFixture>(
        pluginId: const PluginId('alpha'),
        serviceId: const ServiceId('stateless'),
        create: _StatelessFixture.new,
      );
      expect(
        registry.resolve<_StatelessFixture>(const ServiceId('stateless')),
        isNotNull,
      );
    });

    test('allows a StatefulPluginService as a singleton', () {
      final registry = ServiceRegistry();
      registry.registerSingleton<_StatefulFixture>(
        pluginId: const PluginId('alpha'),
        serviceId: const ServiceId('stateful'),
        create: () => _StatefulFixture(),
      );
      expect(
        registry.resolve<_StatefulFixture>(const ServiceId('stateful')),
        isNotNull,
      );
    });
  });

  group('ScopedServiceRegistry positional ServiceId overloads', () {
    test(
      'registerSingleton(Service, instance) registers under service.key',
      () {
        final raw = ServiceRegistry();
        final scope = ScopedServiceRegistry(raw, const PluginId('alpha'));

        const svc = ServiceId.namespaced(Namespace('agent'), 'model');
        scope.registerSingleton<String>(svc, () => 'impl', priority: 80);

        expect(raw.resolve<String>(const ServiceId('agent.model')), 'impl');
      },
    );

    test(
      'registerFactory(Service, create) registers a fresh-instance factory',
      () {
        final raw = ServiceRegistry();
        final scope = ScopedServiceRegistry(raw, const PluginId('alpha'));

        var counter = 0;
        const svc = ServiceId('counter');
        scope.registerFactory<List<int>>(svc, () => [counter++]);

        final a = raw.resolve<List<int>>(const ServiceId('counter'));
        final b = raw.resolve<List<int>>(const ServiceId('counter'));
        expect(a, isNot(same(b)));
      },
    );

    test('registerLazySingleton(Service, factory) caches across resolves', () {
      final raw = ServiceRegistry();
      final scope = ScopedServiceRegistry(raw, const PluginId('alpha'));

      var built = 0;
      const svc = ServiceId('lazy');
      scope.registerLazySingleton<String>(svc, () {
        built++;
        return 'instance';
      });

      raw.resolve<String>(const ServiceId('lazy'));
      raw.resolve<String>(const ServiceId('lazy'));
      expect(built, 1);
    });

    test('positional overload uses default priority when none given', () {
      final raw = ServiceRegistry();
      final scope = ScopedServiceRegistry(raw, const PluginId('alpha'));

      const svc = ServiceId('thing');
      scope.registerSingleton<String>(svc, () => 'impl');

      final wrapper = raw.resolveRaw<String>(const ServiceId('thing'));
      expect(wrapper.priority, ServiceRegistry.defaultPriority);
    });
  });

  group('ScopedServiceRegistry.withPriority', () {
    test('returns a copy that applies the priority by default', () {
      final raw = ServiceRegistry();
      final scope = ScopedServiceRegistry(raw, const PluginId('alpha'));

      const svc = ServiceId.namespaced(Namespace('agent'), 'model');
      scope.withPriority(120).registerSingleton<String>(svc, () => 'impl');

      final wrapper = raw.resolveRaw<String>(const ServiceId('agent.model'));
      expect(wrapper.priority, 120);
    });

    test('per-call priority overrides the default', () {
      final raw = ServiceRegistry();
      final scope = ScopedServiceRegistry(raw, const PluginId('alpha'));

      const a = ServiceId.namespaced(Namespace('agent'), 'model');
      const b = ServiceId.namespaced(Namespace('agent'), 'temperature');
      scope.withPriority(100)
        ..registerSingleton<String>(a, () => 'a')
        ..registerSingleton<String>(b, () => 'b', priority: 80);

      expect(
        raw.resolveRaw<String>(const ServiceId('agent.model')).priority,
        100,
      );
      expect(
        raw.resolveRaw<String>(const ServiceId('agent.temperature')).priority,
        80,
      );
    });

    test('stacking withPriority returns the latest default', () {
      final raw = ServiceRegistry();
      final scope = ScopedServiceRegistry(raw, const PluginId('alpha'));

      const svc = ServiceId('thing');
      scope
          .withPriority(100)
          .withPriority(50)
          .registerSingleton<String>(svc, () => 'impl');

      expect(raw.resolveRaw<String>(const ServiceId('thing')).priority, 50);
    });

    test('withPriority does not mutate the original scope', () {
      final raw = ServiceRegistry();
      final scope = ScopedServiceRegistry(raw, const PluginId('alpha'));
      scope.withPriority(100); // discard result
      expect(scope.defaultPriority, isNull);
    });
  });
}

class _StatelessFixture extends PluginService {}

class _StatefulFixture extends StatefulPluginService<PluginContext> {}
