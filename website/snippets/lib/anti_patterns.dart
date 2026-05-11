/// Wrong-way examples for events, registry, settings, naming.
/// Each region shows an anti-pattern and the correct fix.
library;

import 'package:plugin_kit/plugin_kit.dart';

/// Abstract redactor interface for anti-pattern examples.
abstract class Redactor {
  /// Redacts [input] and returns the result.
  String redact(String input);
}

/// A simple user message event.
class UserMessageReceived {
  /// The text content of the message.
  String text;

  /// Creates a [UserMessageReceived] with [text].
  UserMessageReceived(this.text);
}

/// A simple logger service.
class Logger {
  /// Logs [message].
  void log(String message) {}
}

/// A simple event type for anti-pattern examples.
class MyEvent {
  /// Creates a [MyEvent].
  const MyEvent();
}

// #docregion anti-pattern-direct-subscribe-wrong
// WRONG: Multiple plugins subscribing directly to the same event for
// winner-takes-all semantics. All handlers fire; both mutate; result depends
// on registration order.
class MyRedactionPluginWrong extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('my_redaction_wrong');

  @override
  void attach(SessionPluginContext context) {
    on<UserMessageReceived>(context, (e) {
      // This runs alongside every other subscriber -- not winner-only.
      e.event.text = e.event.text.replaceAll('secret', '[REDACTED]');
    });
  }
}
// #enddocregion anti-pattern-direct-subscribe-wrong

// #docregion anti-pattern-direct-subscribe-fix
// CORRECT: Register the redactor as a service; let the registry pick the winner.
class MyRedactionPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('my_redaction');

  static const serviceId = ServiceId('redactor');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Redactor>(serviceId, () => _ComplianceRedactor());
  }

  @override
  void attach(SessionPluginContext context) {
    on<UserMessageReceived>(context, (e) {
      final redactor = context.maybeResolve<Redactor>(serviceId);
      if (redactor == null) return;
      e.event.text = redactor.redact(e.event.text);
    });
  }
}

class _ComplianceRedactor implements Redactor {
  @override
  String redact(String input) => input.replaceAll(
    RegExp(r'\bsecret\b', caseSensitive: false),
    '[REDACTED]',
  );
}
// #enddocregion anti-pattern-direct-subscribe-fix

// #docregion anti-pattern-string-settings-key-wrong
// WRONG: Using raw strings as map keys.
// RuntimeSettings.services is Map<Pin, ServiceSettings> -- String keys won't compile.
RuntimeSettings buildWrongSettings() {
  return const RuntimeSettings(
    services: {
      // Use Pin(...) or the typed chain, never raw strings here.
    },
  );
}
// #enddocregion anti-pattern-string-settings-key-wrong

// #docregion anti-pattern-string-settings-key-fix
// CORRECT: Use the typed chain or Pin constructors.
final correctSettings = RuntimeSettings(
  services: {
    const PluginId('chat').namespace('agent').service('model'):
        const ServiceSettings(config: {'temperature': 0.7}),
    PluginId.wildcard.namespace('agent').service('tools'):
        const ServiceSettings(priority: 200),
  },
);
// #enddocregion anti-pattern-string-settings-key-fix

// #docregion anti-pattern-resolve-in-register-wrong
// WRONG: Resolving services during register(). At that point, other plugins
// may not have registered yet. The behavior is undefined.
class BadPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('bad_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    // DO NOT do this: resolution order is undefined during register-all.
    final _ = registry.raw.maybeResolve<Logger>(const ServiceId('logger'));
    registry.registerSingleton<Logger>(const ServiceId('my_logger'), () => Logger());
  }
}
// #enddocregion anti-pattern-resolve-in-register-wrong

// #docregion anti-pattern-resolve-in-register-fix
// CORRECT: Defer resolution via lazy singleton, or resolve in attach.
class GoodPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('good_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    // (a) Lazy + closure capture; resolve when the lazy factory fires.
    registry.registerLazySingleton<Logger>(
      const ServiceId('my_logger'),
      () => registry.raw.resolve<Logger>(const ServiceId('logger')),
    );
  }

  @override
  void attach(SessionPluginContext context) {
    // (b) Resolve in attach or in event handlers.
    final logger = context.resolve<Logger>(const ServiceId('logger'));
    logger.log('good plugin attached');
  }
}
// #enddocregion anti-pattern-resolve-in-register-fix

// #docregion anti-pattern-plugin-helper-missing-context-wrong
// WRONG: Plugin helpers require context as first arg because plugin instances
// are shared across sessions. Omitting it has no compile-time binding.
class BadPluginHelper extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('bad_helper');

  @override
  void attach(SessionPluginContext context) {
    // context.bus.on<MyEvent>((e) => null);  // <-- raw bus bypasses tracking
    // Use the plugin helper below instead.
    on<MyEvent>(context, (e) {
      /* correctly tracked */
    });
  }
}
// #enddocregion anti-pattern-plugin-helper-missing-context-wrong

// #docregion anti-pattern-cache-resolution-wrong
// WRONG: Caching a resolved service in a field. The cache holds the winner
// at attach time; a higher-priority plugin enabled later is invisible.
class CachingService extends StatefulPluginService {
  Logger? _cachedLogger;

  @override
  void attach() {
    _cachedLogger = context.resolve<Logger>(const ServiceId('logger'));
    on<MyEvent>((e) => _cachedLogger!.log('event'));
  }
}
// #enddocregion anti-pattern-cache-resolution-wrong

// #docregion anti-pattern-cache-resolution-fix
// CORRECT: Resolve at the point of use. O(1) Map lookup.
class NonCachingService extends StatefulPluginService {
  @override
  void attach() {
    on<MyEvent>((e) {
      final logger = context.resolve<Logger>(const ServiceId('logger'));
      logger.log('event');
    });
  }
}
// #enddocregion anti-pattern-cache-resolution-fix

// #docregion anti-pattern-shared-instance-wrong
// WRONG: Captured field across sessions. Session A and B share the same Logger.
class SessionPlugin1 extends SessionPlugin {
  final Logger _logger = Logger(); // shared across all sessions

  @override
  PluginId get pluginId => const PluginId('shared_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Logger>(
      const ServiceId('logger'),
      () => _logger, // every session resolves the same instance
    );
  }
}
// #enddocregion anti-pattern-shared-instance-wrong

// #docregion anti-pattern-shared-instance-fix
// CORRECT: Construct inline. Each session's register() creates a fresh instance.
class SessionPlugin2 extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('isolated_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Logger>(
      const ServiceId('logger'),
      () => Logger(), // fresh per session
    );
  }
}
// #enddocregion anti-pattern-shared-instance-fix

// #docregion anti-pattern-reserved-plugin-id
// WRONG: PluginId values starting with '__pk_' are reserved.
// runtime.addPlugin(ReservedPlugin()); // throws ArgumentError
class ReservedPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('my_normal_plugin'); // fine

  // Avoid: const PluginId('__pk_internal') -- reserved prefix
}
// #enddocregion anti-pattern-reserved-plugin-id

// #docregion anti-pattern-mutable-fact-event-wrong
// WRONG: Mutating a fact event. Facts are observations of things that already
// happened; mutating them contradicts their semantics.
class ImmutableUserMessage {
  /// The message text.
  final String text;

  /// Creates an [ImmutableUserMessage].
  const ImmutableUserMessage(this.text);
}

void showMutableMistake(PluginContext context) {
  context.bus.on<ImmutableUserMessage>((e) {
    // Trying to mutate a fact event is wrong -- the field is final.
    // e.event.text = e.event.text.toUpperCase(); // compile error
    print(e.event.text);
  });
}

// #enddocregion anti-pattern-mutable-fact-event-wrong
