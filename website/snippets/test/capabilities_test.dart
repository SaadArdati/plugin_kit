import 'package:docs_snippets/capabilities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('capability-define', () {
    test('SupportsFileFormats holds extensions set', () {
      const cap = SupportsFileFormats({'jsx', 'dart'});
      expect(cap.extensions, contains('dart'));
    });
  });

  group('capability-register-and-resolve', () {
    test('resolveCapability returns the registered capability', () {
      final registry = ServiceRegistry();
      final scoped = registry.scopedFor(const PluginId('importer_plugin'));
      registerWithCapabilities(scoped);
      final cap = resolveCapability(registry);
      expect(cap, isNotNull);
      expect(cap!.extensions, containsAll(['jsx', 'dart']));
    });
  });

  group('capability-register-multiple', () {
    test('registers linter with multiple capabilities', () {
      final registry = ServiceRegistry();
      registerLinterWithCapabilities(registry);
      final wrapper = registry.resolveRaw<CodeLinter>(
        const ServiceId('linter'),
      );
      expect(wrapper.capabilities.hasType<SupportsLanguages>(), isTrue);
      expect(wrapper.capabilities.hasType<PartOfASuiteOfTools>(), isTrue);
      expect(wrapper.capabilities.hasType<CanBeSlow>(), isTrue);
    });
  });

  group('capability-in-plugin-register', () {
    test('checkConfigurable returns true', () {
      final registry = ServiceRegistry();
      final scoped = registry.scopedFor(const PluginId('my_plugin'));
      registerCapabilityInPlugin(scoped);
      expect(checkConfigurable(registry), isTrue);
    });
  });

  group('capability-lookup', () {
    test('getOfType returns the capability', () {
      const cap = SupportsFileFormats({'dart'});
      expect(cap, isNotNull);
      final set = <Capability>{cap};
      expect(set.getOfType<SupportsFileFormats>(), isNotNull);
      expect(set.hasType<CanBeSlow>(), isFalse);
    });
  });

  group('capability-ui-configurable', () {
    test('UiCapabilityExample is not null', () {
      const cap = UiCapabilityExample('Settings');
      expect(cap, isNotNull);
      expect(cap.label, equals('Settings'));
    });
  });

  group('capability-resolve-raw-tooling', () {
    test('resolveToolingWrapper reads hasType without error', () {
      final registry = ServiceRegistry();
      registry.registerSingleton<CodeLinter>(
        pluginId: const PluginId('linter_suite'),
        serviceId: const ServiceId('tooling.formatter'),
        create: () => CodeLinter(),
      );
      final ctx = PluginContext.stub(registry: registry);
      expect(() => resolveToolingWrapper(ctx), returnsNormally);
    });
  });

  group('capability-resolve-raw-get-of-type', () {
    test(
      'getFormatterCapability returns null when no CanBeSlow registered',
      () {
        final registry = ServiceRegistry();
        registry.registerSingleton<CodeLinter>(
          pluginId: const PluginId('linter_suite'),
          serviceId: const ServiceId('formatter'),
          create: () => CodeLinter(),
        );
        final ctx = PluginContext.stub(registry: registry);
        final result = getFormatterCapability(ctx);
        expect(result, isNull);
      },
    );
  });

  group('capability-has-type-is-slow', () {
    test('warnIfSlow runs without error when capability is absent', () {
      final registry = ServiceRegistry();
      registry.registerSingleton<CodeLinter>(
        pluginId: const PluginId('linter_suite'),
        serviceId: const ServiceId('formatter'),
        create: () => CodeLinter(),
      );
      final ctx = PluginContext.stub(registry: registry);
      expect(() => warnIfSlow(ctx), returnsNormally);
    });
  });
}
