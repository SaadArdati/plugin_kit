# plugin_kit: Testing

Test plugins, services, and event handlers without a full runtime.

## Stubs and fakes

Three context factories in `types.dart`. All params optional; defaults are `ServiceRegistry.empty()`, fresh `EventBus()`, `{}`.

```dart
PluginContext.stub({registry, bus, extras});
GlobalPluginContext.stub({registry, bus, extras, sessions});
SessionPluginContext.stub({registry, bus, globalBus, extras});
```

`ctx.registry` on a stub is the raw `ServiceRegistry`. Inject a fake using the named-arg registration form:

```dart
final ctx = SessionPluginContext.stub();
ctx.registry.registerSingleton<Logger>(
  pluginId: const PluginId('test'),
  serviceId: const ServiceId('logger'),
  instance: FakeLogger(),
  priority: 1000, // beats anything the SUT registers
);
```

## Asserting cascade

`emit` returns the post-cascade envelope. Inspect `event` for mutations, `stopped` for halts.

```dart
ctx.bus.on<DraftMessage>((e) => e.event.text = e.event.text.toUpperCase());
final env = await ctx.bus.emit<DraftMessage>(event: DraftMessage('hi'));
expect(env.event.text, 'HI');
expect(env.stopped, false);
```

For request/response: `bus.maybeRequest` returns null on no-handler-or-all-conceded; `bus.request` throws `RequestUnavailableException`. Use `maybeRequest` to assert the absence path.

## Pitfalls

- Stubs do NOT run `register-all -> attach-all`. Multi-plugin lifecycle tests (deps, settings reconciliation, `onPluginSettingsChanged`) need a real `PluginRuntime` or `PluginRuntime`.
- `StatefulPluginService.this.context` is bound by framework `_bindContext` during attach. A stub bypasses this; `this.context` throws. Drive through a real runtime, or test only pure methods.
- `PluginService.injectSettings` runs during attach. In a stub, call it manually if your service reads `config`.
- `ctx.bus.on(...)` subscriptions do not auto-cancel. Within a single test the bus is discarded, so this is fine. In production code, use the helpers (anti-patterns.md #7).
- Fresh state per test. Don't share registries or buses across tests.

For an integration-style example driving a real `PluginRuntime` through settings reconciliation and session swap, see `example/state_garden/test/lifecycle_proofs_test.dart`.
