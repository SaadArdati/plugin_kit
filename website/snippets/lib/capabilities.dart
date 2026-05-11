/// Snippets for Capability subclasses, capability lookup, and registration.
library;

import 'package:plugin_kit/plugin_kit.dart';

// #docregion capability-define
class SupportsFileFormats extends Capability {
  /// The set of file extensions this service supports.
  final Set<String> extensions;

  /// Creates a capability declaring support for [extensions].
  const SupportsFileFormats(this.extensions);
}
// #enddocregion capability-define

/// Marks a service as part of a named tool suite.
class PartOfASuiteOfTools extends Capability {
  /// The name of the tool suite this service belongs to.
  final String suiteName;

  /// Creates a capability for [suiteName].
  const PartOfASuiteOfTools(this.suiteName);
}

/// Marks a service as potentially slow, with a human-readable reason.
class CanBeSlow extends Capability {
  /// Whether the service can be slow.
  final bool value;

  /// The reason the service may be slow.
  final String reason;

  /// Creates a [CanBeSlow] capability with [value] and [reason].
  const CanBeSlow(this.value, {required this.reason});
}

/// Marks a service as supporting a set of programming languages.
class SupportsLanguages extends Capability {
  /// The supported language identifiers.
  final List<String> languages;

  /// Creates a capability for [languages].
  const SupportsLanguages(this.languages);
}

/// A configurable capability marker.
class ConfigurableCapability extends Capability {
  /// Creates a [ConfigurableCapability] marker.
  const ConfigurableCapability();
}

/// A placeholder service used in capability examples.
class MyService {
  /// Creates a [MyService].
  const MyService();
}

/// A placeholder code linter service.
class CodeLinter {
  /// Creates a [CodeLinter].
  CodeLinter();
}

// #docregion capability-register-and-resolve
void registerWithCapabilities(ScopedServiceRegistry registry) {
  registry.registerFactory<MyService>(
    const ServiceId('importer'),
    () => const MyService(),
    capabilities: const {SupportsFileFormats({'jsx', 'dart'})},
  );
}

SupportsFileFormats? resolveCapability(ServiceRegistry registry) {
  final wrapper = registry.resolveRaw<MyService>(const ServiceId('importer'));
  return wrapper.capabilities.getOfType<SupportsFileFormats>();
}
// #enddocregion capability-register-and-resolve

// #docregion capability-register-multiple
void registerLinterWithCapabilities(ServiceRegistry registry) {
  registry.registerSingleton<CodeLinter>(
    pluginId: const PluginId('linter_suite'),
    serviceId: const ServiceId('linter'),
    create: () => CodeLinter(),
    capabilities: {
      const SupportsLanguages(['dart', 'js']),
      const PartOfASuiteOfTools('super_suite'),
      const CanBeSlow(true, reason: 'network round-trip per call'),
    },
  );
}
// #enddocregion capability-register-multiple

// #docregion capability-lookup
void lookupCapability(ServiceRegistry registry) {
  final wrapper = registry.resolveRaw<MyService>(const ServiceId('importer'));
  final formats = wrapper.capabilities.getOfType<SupportsFileFormats>();
  if (formats != null) {
    print('Supported: ${formats.extensions}');
  }
  final hasSlow = wrapper.capabilities.hasType<CanBeSlow>();
  print('Can be slow: $hasSlow');
}
// #enddocregion capability-lookup

// #docregion capability-in-plugin-register
void registerCapabilityInPlugin(ScopedServiceRegistry registry) {
  registry.registerSingleton<MyService>(
    const ServiceId('my_service'),
    () => const MyService(),
    capabilities: const {ConfigurableCapability()},
  );
}

bool checkConfigurable(ServiceRegistry registry) {
  return registry
      .resolveRaw<MyService>(const ServiceId('my_service'))
      .capabilities
      .hasType<ConfigurableCapability>();
}
// #enddocregion capability-in-plugin-register

// #docregion capability-ui-configurable
class UiCapabilityExample extends Capability {
  /// The label for the UI section.
  final String label;

  /// Creates a [UiCapabilityExample] with [label].
  const UiCapabilityExample(this.label);
}
// #enddocregion capability-ui-configurable

// #docregion capability-resolve-raw-wrapper
void inspectWrapper(ServiceRegistry registry) {
  final wrapper = registry.resolveRaw<CodeLinter>(const ServiceId('linter'));
  final caps = wrapper.capabilities;
  final slow = caps.getOfType<CanBeSlow>();
  print('slow reason: ${slow?.reason}');
  print('has languages: ${caps.hasType<SupportsLanguages>()}');
}
// #enddocregion capability-resolve-raw-wrapper

// #docregion capability-resolve-raw-tooling
/// Resolves a raw wrapper for a tooling namespace slot and reads capabilities.
void resolveToolingWrapper(PluginContext context) {
  const tooling = Namespace('tooling');
  final wrapper = context.registry.resolveRaw<CodeLinter>(tooling('formatter'));
  final caps = wrapper.capabilities;
  print('has slow: ${caps.hasType<CanBeSlow>()}');
  print('has languages: ${caps.hasType<SupportsLanguages>()}');
}
// #enddocregion capability-resolve-raw-tooling

// #docregion capability-resolve-raw-get-of-type
/// Resolves the winning formatter wrapper and reads a typed capability.
CanBeSlow? getFormatterCapability(PluginContext context) {
  final wrapper = context.registry.resolveRaw<CodeLinter>(
    const ServiceId('formatter'),
  );
  return wrapper.capabilities.getOfType<CanBeSlow>();
}
// #enddocregion capability-resolve-raw-get-of-type

/// Marks a service as potentially slow, with an isSlow flag.
class IsSlowCapability extends Capability {
  /// Whether this service is expected to be slow.
  final bool isSlow;

  /// A human-readable reason.
  final String reason;

  /// Creates an [IsSlowCapability].
  const IsSlowCapability({required this.isSlow, required this.reason});
}

// #docregion capability-has-type-is-slow
/// Inspects a wrapper for [IsSlowCapability] and warns if slow.
void warnIfSlow(PluginContext context) {
  final wrapper = context.registry.resolveRaw<CodeLinter>(
    const ServiceId('formatter'),
  );
  final caps = wrapper.capabilities;

  if (caps.hasType<IsSlowCapability>()) {
    final slow = caps.getOfType<IsSlowCapability>()!;
    if (slow.isSlow) {
      // Warn the user before invoking this slot in a latency-sensitive path.
      print('Warning: ${slow.reason}');
    }
  }
}
// #enddocregion capability-has-type-is-slow
