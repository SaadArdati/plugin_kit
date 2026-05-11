/// Snippets for test patterns: PluginContext.stub, level 1/2/3 testing.
library;

import 'package:plugin_kit/plugin_kit.dart';

/// A notification request used in testing snippets.
class NotificationRequest {
  /// The notification message.
  final String message;

  /// Creates a [NotificationRequest] with [message].
  const NotificationRequest(this.message);
}

/// A new message event used in ChatBuffer tests.
class NewMessageEvent {
  /// The message text.
  final String text;

  /// Creates a [NewMessageEvent] with [text].
  const NewMessageEvent(this.text);
}

/// A mutable draft message for cascade-assertion examples.
class DraftMessage {
  /// The current text, mutable by handlers.
  String text;

  /// Creates a [DraftMessage] with [text].
  DraftMessage(this.text);
}

/// A notification service that reads its channel from settings.
class NotificationService extends PluginService {
  /// The channel from injected settings.
  String get channel => config.getString('channel') ?? 'default';
}

/// A simple logger interface for testing-injection examples.
abstract class Logger {
  /// Logs [message].
  void log(String message);
}

/// A fake [Logger] used in testing-stub-inject examples.
class FakeLogger implements Logger {
  /// Captured log calls.
  final List<String> logs = [];

  @override
  void log(String message) => logs.add(message);
}

// #docregion testing-stub-inject-fake
/// Demonstrates injecting a fake into [SessionPluginContext.stub]'s registry
/// using the named-arg form of [ServiceRegistry.registerSingleton].
void demonstrateStubInjectFake() {
  final ctx = SessionPluginContext.stub();
  ctx.registry.registerSingleton<Logger>(
    pluginId: const PluginId('test'),
    serviceId: const ServiceId('logger'),
    instance: FakeLogger(),
    priority: 1000, // beats anything the SUT registers
  );

  final logger = ctx.registry.resolve<Logger>(const ServiceId('logger'));
  assert(logger is FakeLogger, 'expected FakeLogger');
}
// #enddocregion testing-stub-inject-fake

// #docregion testing-level-1-service
/// Level 1: test a PluginService in total isolation.
void testNotificationServiceChannel() {
  final service = NotificationService();
  service.injectSettings({'channel': 'slack'}, hash: 'test-1');

  assert(service.channel == 'slack', 'channel should be slack');
}
// #enddocregion testing-level-1-service

// #docregion testing-assert-cascade
/// Asserts cascade mutation and halt via [EventEnvelope].
Future<void> testAssertCascade() async {
  final ctx = PluginContext.stub();
  ctx.bus.on<DraftMessage>((e) => e.event.text = e.event.text.toUpperCase());
  final env = await ctx.bus.emit<DraftMessage>(event: DraftMessage('hi'));
  assert(env.event.text == 'HI', 'handler should uppercase the draft text');
  assert(!env.stopped, 'no handler called stop; should not be stopped');
}
// #enddocregion testing-assert-cascade

/// A notification plugin that answers notification requests.
class NotificationPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('notifier');

  @override
  void attach(SessionPluginContext context) {
    onRequest<NotificationRequest, bool>(context, (req) async {
      return req.event.message.isNotEmpty;
    });
  }
}

// #docregion testing-level-2-plugin
/// Level 2: test a plugin against a real context.
Future<bool> testPluginAnswersRequest() async {
  final registry = ServiceRegistry();
  final bus = EventBus();
  final context = SessionPluginContext(
    registry: registry,
    bus: bus,
    globalBus: EventBus(),
  );

  final plugin = NotificationPlugin();
  plugin.register(registry.scopedFor(plugin.pluginId));
  plugin.attach(context);

  final result = await bus.request<NotificationRequest, bool>(
    const NotificationRequest('hello'),
  );

  return result; // true
}
// #enddocregion testing-level-2-plugin

// #docregion testing-tracking-plugin
class TrackingPlugin extends SessionPlugin {
  @override
  final PluginId pluginId;

  /// Ordered log of lifecycle calls for assertion.
  final List<String> calls = [];

  /// Creates a [TrackingPlugin] with [pluginId].
  TrackingPlugin(this.pluginId);

  @override
  void register(ScopedServiceRegistry registry) {
    calls.add('register');
  }

  @override
  void attach(SessionPluginContext context) {
    calls.add('attach');
  }

  @override
  Future<void> detach(SessionPluginContext context) async {
    calls.add('detach');
  }
}
// #enddocregion testing-tracking-plugin

// #docregion testing-level-3-lifecycle
Future<void> testLifecycleOrder() async {
  final runtime = PluginRuntime();
  final plugin = TrackingPlugin(const PluginId('trackee'));
  runtime.addPlugin(plugin);
  runtime.init();

  final session = await runtime.createSession();
  await session.dispose();

  assert(
    plugin.calls.join(',') == 'register,attach,detach',
    'lifecycle order must be register->attach->detach',
  );

  await runtime.dispose();
}
// #enddocregion testing-level-3-lifecycle

// #docregion testing-update-settings-disable
Future<void> testPluginDisabledByUpdateSettings() async {
  final runtime = PluginRuntime();
  final plugin = TrackingPlugin(const PluginId('toggle_me'));
  runtime.addPlugin(plugin);
  runtime.init();
  final session = await runtime.createSession();

  await runtime.updateSettings(
    const RuntimeSettings(
      plugins: {PluginId('toggle_me'): PluginConfig(enabled: false)},
    ),
  );

  assert(
    !session.isPluginEnabled(const PluginId('toggle_me')),
    'plugin should be disabled',
  );
  assert(
    plugin.calls.join(',') == 'register,attach,detach',
    'detach must run on disable',
  );

  await runtime.dispose();
}
// #enddocregion testing-update-settings-disable

/// A chat buffer service that stores messages while attached.
class ChatBuffer extends StatefulPluginService {
  /// The messages recorded while attached.
  final List<String> messages = [];

  @override
  void attach() {
    on<NewMessageEvent>((e) => messages.add(e.event.text));
  }
}

/// A plugin that registers [ChatBuffer] for testing purposes.
class ChatBufferPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('chat');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<ChatBuffer>(
      const ServiceId('buffer'),
      ChatBuffer(),
    );
  }
}

// #docregion testing-stateful-service
Future<void> testChatBufferRecordsMessages() async {
  final runtime = PluginRuntime(plugins: [ChatBufferPlugin()])..init();
  final session = await runtime.createSession();

  final buffer = session.resolve<ChatBuffer>(const ServiceId('buffer'));

  await session.bus.emit<NewMessageEvent>(event: const NewMessageEvent('hi'));
  assert(buffer.messages.length == 1, 'should have 1 message after attach');

  await runtime.updateSessionSettings(
    session,
    newSettings: const RuntimeSettings(
      plugins: {PluginId('chat'): PluginConfig(enabled: false)},
    ),
  );

  await session.bus.emit<NewMessageEvent>(event: const NewMessageEvent('bye'));
  assert(buffer.messages.length == 1, 'detached; subscription cancelled');

  await runtime.dispose();
}
// #enddocregion testing-stateful-service

/// A plugin that throws during attach, used in exception-surface tests.
class CrashingPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('crashing_plugin');

  @override
  void attach(GlobalPluginContext context) {
    throw StateError('intentional crash for testing');
  }
}

// #docregion testing-lifecycle-exception
Future<void> testBadPluginSurfacesException() async {
  final runtime = PluginRuntime();
  runtime.addPlugin(CrashingPlugin());

  try {
    runtime.init();
    assert(false, 'expected PluginLifecycleException');
  } on PluginLifecycleException catch (e) {
    assert(e.phase == 'attachGlobal', 'phase should be attachGlobal');
    assert(
      e.failures.first.$1 == const PluginId('crashing_plugin'),
      'failure plugin id should match',
    );
  } finally {
    if (runtime.globalBus.isDisposed == false) {
      await runtime.dispose();
    }
  }
}

// #enddocregion testing-lifecycle-exception

// #docregion testing-throws-lifecycle-exception
/// Demonstrates asserting that runtime.init throws PluginLifecycleException.
void assertThrowsLifecycleException() {
  final runtime = PluginRuntime(plugins: [CrashingPlugin()]);

  Object? caught;
  try {
    runtime.init();
  } on PluginLifecycleException catch (e) {
    caught = e;
  }
  assert(caught is PluginLifecycleException, 'expected PluginLifecycleException');
}
// #enddocregion testing-throws-lifecycle-exception
