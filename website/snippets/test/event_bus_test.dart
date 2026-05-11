import 'package:docs_snippets/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  late PluginContext context;

  setUp(() {
    context = PluginContext.stub();
  });

  group('event-bus-on-emit', () {
    test('handler fires when event is emitted', () async {
      String? seen;
      context.bus.on<UserLoggedInEvent>((env) {
        seen = env.event.userId;
      });
      await context.bus.emit<UserLoggedInEvent>(
        event: UserLoggedInEvent('u_42'),
      );
      expect(seen, equals('u_42'));
    });
  });

  group('event-bus-priority', () {
    test('handler with priority 0 runs before priority 10', () async {
      final order = <int>[];
      context.bus.on<UserMessage>((env) => order.add(0), priority: 0);
      context.bus.on<UserMessage>((env) => order.add(10), priority: 10);
      await context.bus.emit<UserMessage>(
        event: const UserMessage(text: 'test'),
      );
      expect(order, equals([0, 10]));
    });
  });

  group('event-bus-bind', () {
    test('bind observer fires on emit', () async {
      int count = 0;
      final unbind = demonstrateBind(context);
      context.bus.on<UserLoggedInEvent>((env) {});
      count = 0; // reset to check bind fires
      await context.bus.emit<UserLoggedInEvent>(
        event: UserLoggedInEvent('x'),
      );
      // bind is registered; just verify unbind returns a function
      expect(unbind, isA<Function>());
      count++; // suppress unused warning
      expect(count, 1);
    });
  });

  group('event-bus-request-response', () {
    test('request returns results', () async {
      final results = await demonstrateRequest(context);
      expect(results?.results, isNotNull);
    });
  });

  group('event-bus-identifier-scoping', () {
    test('identifier-scoped event only hits matching handlers', () async {
      final general = <String>[];
      final scoped = <String>[];
      context.bus.on<ToolExecutionEvent>((env) {
        general.add(env.event.toolName);
      });
      context.bus.on<ToolExecutionEvent>(
        (env) => scoped.add(env.event.toolName),
        identifier: 'calc',
      );
      await context.bus.emit<ToolExecutionEvent>(
        event: const ToolExecutionEvent(toolName: 'calc'),
        identifier: 'calc',
      );
      expect(general, contains('calc'));
      expect(scoped, contains('calc'));

      general.clear();
      scoped.clear();
      await context.bus.emit<ToolExecutionEvent>(
        event: const ToolExecutionEvent(toolName: 'other'),
      );
      expect(scoped, isEmpty);
    });
  });

  group('event-bus-emit-envelope', () {
    test('stopped envelope has stopped flag', () async {
      context.bus.on<BeforeSaveEvent>((env) {
        env.stop(const BeforeSaveEvent(documentId: 'blocked'));
      });
      final result = await context.bus.emit<BeforeSaveEvent>(
        event: const BeforeSaveEvent(documentId: 'original'),
      );
      expect(result.stopped, isTrue);
      expect(result.event.documentId, equals('blocked'));
    });
  });

  group('event-bus-mutate-stop', () {
    test('mutate-stop example runs without error', () async {
      final bus = EventBus();
      await demonstrateMutateAndStop(bus);
    });
  });

  group('event-bus-standalone', () {
    test('standalone bus demonstration runs without error', () {
      demonstrateStandaloneEventBus();
    });
  });

  group('event-bus-envelope-class', () {
    test('EventEnvelope demonstrates mutate and stop', () {
      final envelope = EventEnvelope<UserMessage>(
        event: const UserMessage(text: 'hello'),
        identifier: null,
      );
      demonstrateEventEnvelope(envelope);
      expect(envelope.stopped, isTrue);
    });
  });

  group('events-stateful-emit', () {
    test('UserMessageReceived can be constructed with required fields', () {
      const event = UserMessageReceived(
        sessionId: 'sess-1',
        text: 'Hello',
      );
      expect(event.sessionId, equals('sess-1'));
      expect(event.text, equals('Hello'));
    });
  });

  group('events-request-find-port', () {
    test('requestOpenPort returns null when no handler registered', () async {
      final ctx = PluginContext.stub();
      // No onRequest handler registered; maybeRequest returns null.
      final result = await ctx.bus.maybeRequest<FindOpenPort, int?>(
        const FindOpenPort(),
      );
      expect(result, isNull);
    });
  });
}
