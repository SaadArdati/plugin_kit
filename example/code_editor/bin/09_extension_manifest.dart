/// # 09: Extension Manifest
///
/// Capabilities with discovery via `resolveRaw` and `listCapabilitiesOfNamespace`,
/// without instantiating the underlying services.
///
/// Three custom capability types are defined for formatters, linters, and
/// debug adapters. A plugin registers services under the `tooling`
/// namespace, each tagged with the appropriate capability. Main then:
///
/// 1. Inspects each slot via `resolveRaw` without instantiating.
/// 2. Aggregates capabilities across the namespace.
/// 3. Uses `CapabilityLookup` (`hasType`, `getOfType`) to extract typed data.
library;

import 'package:code_editor/code_editor.dart';
import 'package:plugin_kit/plugin_kit.dart';

const _namespace = Namespace('tooling');

/// Declares the languages a formatter service supports.
// #docregion 09-extension-manifest-formatter-capability
class FormatterCapability extends Capability {
  final List<String> supportedLanguages;
  const FormatterCapability(this.supportedLanguages);
}
// #enddocregion 09-extension-manifest-formatter-capability

/// Declares the lint rules a linter service enforces.
class LinterCapability extends Capability {
  final List<String> ruleNames;
  const LinterCapability(this.ruleNames);
}

/// Declares the runtimes a debug adapter supports.
class DebugCapability extends Capability {
  final List<String> supportedRuntimes;
  const DebugCapability(this.supportedRuntimes);
}

// Stubs. Capability metadata is the point; the methods are no-ops.

class FormatterStub extends PluginService implements FormatterService {
  @override
  String get name => 'multi_lang_formatter';

  @override
  String format(TextDocument document) => document.content;
}

class LinterStub extends PluginService implements LinterService {
  @override
  String get name => 'strict_linter';

  @override
  List<Diagnostic> lint(TextDocument document) => const [];
}

class DebugAdapterStub extends PluginService {
  String get name => 'dart_debug_adapter';
}

/// Registers three services in the `tooling` namespace, each carrying one
/// domain-specific capability. Uses the namespace API rather than literal
/// dotted service ids.
class ManifestPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('manifest_demo');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<FormatterStub>(
      _namespace('formatter'),
      () => FormatterStub(),
      priority: 100,
      capabilities: {
        const FormatterCapability(['sql', 'dart', 'markdown']),
      },
    );

    registry.registerSingleton<LinterStub>(
      _namespace('linter'),
      () => LinterStub(),
      priority: 100,
      capabilities: {
        const LinterCapability(['no_todos', 'max_line_length']),
      },
    );

    registry.registerSingleton<DebugAdapterStub>(
      _namespace('debug_adapter'),
      () => DebugAdapterStub(),
      priority: 100,
      capabilities: {
        const DebugCapability(['dart_vm', 'flutter']),
      },
    );
  }
}

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [ManifestPlugin()])..init();
  final session = await runtime.createSession();
  final registry = session.registry;

  // Inspect each slot via resolveRaw. No service is instantiated.
  print('--- resolveRaw capability inspection ---');
  print('');

  for (final slot in ['formatter', 'linter', 'debug_adapter']) {
    final wrapper = registry.resolveRaw(_namespace(slot));
    final caps = wrapper.capabilities;

    print('Slot: tooling.$slot');
    print('  plugin:  ${wrapper.pluginId}');
    print('  priority: ${wrapper.priority}');

    if (caps.hasType<FormatterCapability>()) {
      final cap = caps.getOfType<FormatterCapability>()!;
      print('  FormatterCapability: languages ${cap.supportedLanguages}');
    }
    if (caps.hasType<LinterCapability>()) {
      final cap = caps.getOfType<LinterCapability>()!;
      print('  LinterCapability: rules ${cap.ruleNames}');
    }
    if (caps.hasType<DebugCapability>()) {
      final cap = caps.getOfType<DebugCapability>()!;
      print('  DebugCapability: runtimes ${cap.supportedRuntimes}');
    }
    print('');
  }

  print('--- listCapabilitiesOfNamespace("tooling") ---');
  print('');

  final caps = registry.listCapabilitiesOfNamespace(_namespace);
  print('Total capabilities: ${caps.length}');
  print('  Formatters: ${caps.whereType<FormatterCapability>().length}');
  print('  Linters:   ${caps.whereType<LinterCapability>().length}');
  print('  Debug adapters: ${caps.whereType<DebugCapability>().length}');

  await runtime.dispose();
}
