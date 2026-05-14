# plugin_kit: Testing

Three questions, three tools.

## Stance

- Fake at boundaries (repo, IO, external API). Do not fake the framework (bus, registry, context, runtime).
- Use the `.stub()` factories. Do not hand-construct a `SessionPluginContext` from `ServiceRegistry()` + `EventBus()`.
- Each test owns its harness. No shared registry, bus, or context across tests.
- `StatefulPluginService.attach` runs only inside `PluginRuntime._runAttach`. Outside it, `this.context` throws.

## Does this service compute correctly?

Plain Dart. Construct, `injectSettings` if needed, call, assert. No framework primitives.

```dart
/// Level 1: test a PluginService in total isolation.
void testNotificationServiceChannel() {
  final service = NotificationService();
  service.injectSettings({'channel': 'slack'}, hash: 'test-1');

  assert(service.channel == 'slack', 'channel should be slack');
}
```

Most plugin tests should land here.

## Does it interact with bus and registry?

`SessionPluginContext.stub()` (or `PluginContext.stub()`). Real registry + real bus, no runtime.

Inject a fake peer service. Named-arg `registerSingleton` carries a priority; `Priority.system` beats anything the SUT registers.

```dart
/// Demonstrates injecting a fake into [SessionPluginContext.stub]'s registry
/// using the named-arg form of [ServiceRegistry.registerSingleton].
void demonstrateStubInjectFake() {
  final ctx = SessionPluginContext.stub();
  ctx.registry.registerSingleton<Logger>(
    pluginId: const PluginId('test'),
    serviceId: const ServiceId('logger'),
    create: () => FakeLogger(),
    priority: Priority.system, // beats anything the SUT registers
  );

  final logger = ctx.registry.resolve<Logger>(const ServiceId('logger'));
  assert(logger is FakeLogger, 'expected FakeLogger');
}
```

Drive a plugin's `attach` handlers. Only works when reactive logic lives in `Plugin.attach` via the inherited `on` / `onRequest` helpers; plugins that delegate to a `StatefulPluginService` need a runtime.

```dart
/// Drive a plugin's [Plugin.attach] handlers against a
/// [SessionPluginContext.stub] and emit on the stub's bus. No runtime
/// orchestration: cheaper than `PluginRuntime` when the question is "does
/// this plugin react to this event correctly?" rather than "does the
/// runtime sequence things correctly?".
Future<void> testPluginRecordsOnEvent() async {
  final ctx = SessionPluginContext.stub();
  final plugin = UsernameRecorderPlugin();

  plugin.register(ctx.registry.scopedFor(plugin.pluginId));
  plugin.attach(ctx);

  await ctx.bus.emit<UserJoined>(event: const UserJoined('alice'));

  assert(
    plugin.recorded.single == 'alice',
    'attach should have wired the handler against the stub bus',
  );
}
```

Assert on cascade. `emit` returns the post-cascade envelope; inspect `event` for mutations, `stopped` for halts.

```dart
/// Asserts cascade mutation and halt via [EventEnvelope].
Future<void> testAssertCascade() async {
  final ctx = PluginContext.stub();
  ctx.bus.on<DraftMessage>((e) => e.event.text = e.event.text.toUpperCase());
  final env = await ctx.bus.emit<DraftMessage>(event: DraftMessage('hi'));
  assert(env.event.text == 'HI', 'handler should uppercase the draft text');
  assert(!env.stopped, 'no handler called stop; should not be stopped');
}
```

Request/response: `bus.maybeRequest` returns null on no-handler-or-all-conceded; `bus.request` throws a `NoRequestAnswerException` subtype (`RequestNotWiredException` or `AllConcededException`).

## Does the plugin work end-to-end?

Real `PluginRuntime`. Default tier for plugin behavior (because of the `StatefulPluginService` constraint), settings reconciliation, lifecycle order, exception aggregation. Not an escape hatch.

```dart
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
```

`runtime.updateSettings(...)` runs reconciliation: toggling off runs `detach`, toggling back on runs `register` and `attach`. Lifecycle exceptions aggregate into `PluginLifecycleException` with a `phase` string and a list of `(pluginId, error, stackTrace)` tuples.

For an integration-style example through settings reconciliation and session swap, see `example/state_garden/test/lifecycle_proofs_test.dart`.

## Avoid

- Faking the bus, registry, or context. Use `.stub()` for a real one.
- Hand-constructing `SessionPluginContext(registry: ..., bus: ..., globalBus: ...)`. `.stub()` does this with defaults.
- Calling `StatefulPluginService.attach()` directly. `_runAttach` is what binds its context; outside the runtime, `this.context` throws.
- Sharing buses, registries, or contexts across tests.
- Asserting on private state when an emitted event covers the same behavior.
