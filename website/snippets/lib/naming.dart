/// Snippets for plugin/service/event/capability naming conventions.
library;

import 'package:plugin_kit/plugin_kit.dart';

// #docregion naming-core-plugin-static-id
/// A global plugin that exposes its id as a static constant.
class CorePlugin extends GlobalPlugin {
  /// The canonical id for this plugin.
  static const id = PluginId('core');

  @override
  PluginId get pluginId => id;

  @override
  void attach(GlobalPluginContext context) {}
}
// #enddocregion naming-core-plugin-static-id

// #docregion naming-event-past-tense
/// An event emitted after the user logs in.
class UserLoggedIn {
  /// The user identifier.
  final String userId;

  /// Creates a [UserLoggedIn] event.
  const UserLoggedIn({required this.userId});
}
// #enddocregion naming-event-past-tense

// #docregion naming-event-imperative
/// A command event requesting a notification be sent.
class SendNotification {
  /// The notification message.
  final String message;

  /// The target channel.
  final String channel;

  /// Creates a [SendNotification] command.
  const SendNotification({required this.message, required this.channel});
}
// #enddocregion naming-event-imperative

// #docregion naming-event-draft
/// A mutable draft event for outgoing messages, allowing handlers to mutate
/// or veto the payload before it is sent.
class DraftOutgoingMessage {
  /// The current text of the draft, mutable by handlers.
  String text;

  /// Metadata attached by handlers.
  final Map<String, String> metadata;

  /// Creates a [DraftOutgoingMessage] with [text].
  DraftOutgoingMessage(this.text) : metadata = {};
}
// #enddocregion naming-event-draft

// #docregion naming-capability
/// Capability advertising language support.
class SupportsLanguages extends Capability {
  /// The supported language identifiers.
  final List<String> languages;

  /// Creates a [SupportsLanguages] capability.
  const SupportsLanguages(this.languages);
}
// #enddocregion naming-capability

// #docregion naming-settings-keys
const exampleSettings = RuntimeSettings(
  plugins: {
    PluginId('linter_suite'): PluginConfig(enabled: true),
  },
  services: {
    // Key is pluginId:serviceId in wire form, built via typed chain.
  },
);
// #enddocregion naming-settings-keys

// #docregion naming-plugin-id
/// Plugin convention: lowercase_snake_case, describes the feature, not the impl.
const linter = PluginId('linter_suite');
// #enddocregion naming-plugin-id

// #docregion naming-service-settings
const serviceSettingsExample = ServiceSettings(
  config: {'channel': 'slack', 'max_retries': 3},
  priority: 100,
);
// #enddocregion naming-service-settings

// #docregion naming-namespace-composition
/// Composing namespaced service ids.
void demonstrateNamespaceComposition() {
  const agent = Namespace('agent');
  final modelId = agent('model');
  final scopeId = agent.child('system_prompt')('scope');

  final settings = RuntimeSettings(
    services: {
      const PluginId('chat').namespace('agent').service('model'):
          const ServiceSettings(config: {'temperature': 0.7}),
    },
  );

  print('$modelId $scopeId ${settings.services.length}');
}
// #enddocregion naming-namespace-composition
