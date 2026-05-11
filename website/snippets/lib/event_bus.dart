/// Snippets for EventBus, on, emit, request, requestSync, bind, draft events.
library;

import 'package:plugin_kit/plugin_kit.dart';

/// Simple event payload for a user log-in.
class UserLoggedInEvent {
  /// The user identifier.
  final String userId;

  /// Creates a [UserLoggedInEvent] for [userId].
  UserLoggedInEvent(this.userId);
}

/// Simple event to represent a user message.
class UserMessage {
  /// Raw text of the message.
  final String text;

  /// Creates a [UserMessage] with [text].
  const UserMessage({required this.text});
}

/// Represents a search query payload.
class SearchQuery {
  /// The query string to search for.
  final String query;

  /// Creates a [SearchQuery] with [query].
  const SearchQuery({required this.query});
}

/// Represents search results payload.
class SearchResults {
  /// The list of result strings.
  final List<String> results;

  /// Creates [SearchResults] with [results].
  const SearchResults({required this.results});
}

/// Represents a tool execution event.
class ToolExecutionEvent {
  /// The name of the tool that was executed.
  final String toolName;

  /// Creates a [ToolExecutionEvent] for [toolName].
  const ToolExecutionEvent({this.toolName = 'unknown'});
}

/// Event emitted before a save operation, allowing plugins to intercept.
class BeforeSaveEvent {
  /// The id of the document being saved.
  final String documentId;

  /// Creates a [BeforeSaveEvent] for [documentId].
  const BeforeSaveEvent({required this.documentId});
}

// #docregion event-bus-on-emit
Future<void> demonstrateOnAndEmit(PluginContext context) async {
  context.bus.on<UserLoggedInEvent>((env) {
    print('User logged in: ${env.event.userId}');
  });

  await context.bus.emit<UserLoggedInEvent>(event: UserLoggedInEvent('u_123'));
}
// #enddocregion event-bus-on-emit

// #docregion event-bus-priority
void demonstratePriority(PluginContext context) {
  context.bus.on<UserMessage>((env) {
    if (env.event.text.contains('spam')) {
      env.stop(const UserMessage(text: '[blocked]'));
    }
  }, priority: 0);

  context.bus.on<UserMessage>((env) {
    print('Processing: ${env.event.text}');
  }, priority: 10);
}
// #enddocregion event-bus-priority

// #docregion event-bus-bind
void Function() demonstrateBind(PluginContext context) {
  final unbind = context.bus.bind((envelope) {
    print('event ${envelope.event.runtimeType}');
  });
  return unbind;
}
// #enddocregion event-bus-bind

// #docregion event-bus-request-response
Future<SearchResults?> demonstrateRequest(PluginContext context) async {
  context.bus.onRequest<SearchQuery, SearchResults?>((req) async {
    if (req.event.query.isEmpty) return null;

    return SearchResults(results: ['result_${req.event.query}']);
  }, priority: 0);

  return context.bus.request<SearchQuery, SearchResults?>(
    const SearchQuery(query: 'dart patterns'),
  );
}
// #enddocregion event-bus-request-response

// #docregion event-bus-identifier-scoping
Future<void> demonstrateIdentifierScoping(PluginContext context) async {
  context.bus.on<ToolExecutionEvent>((env) {
    print('saw tool execution: ${env.event.toolName}');
  });

  context.bus.on<ToolExecutionEvent>((env) {
    print('calculator specifically: ${env.event.toolName}');
  }, identifier: 'calculator');

  await context.bus.emit<ToolExecutionEvent>(
    event: const ToolExecutionEvent(toolName: 'calculator'),
    identifier: 'calculator',
  );
}
// #enddocregion event-bus-identifier-scoping

// #docregion event-bus-emit-envelope
Future<void> demonstrateEmitEnvelope(PluginContext context) async {
  final result = await context.bus.emit<BeforeSaveEvent>(
    event: const BeforeSaveEvent(documentId: 'doc_1'),
  );

  if (result.stopped) {
    print('Save was blocked or replaced: ${result.event}');
  }

  final BeforeSaveEvent payload = result.event;
  print('Final document ID to save: ${payload.documentId}');
}
// #enddocregion event-bus-emit-envelope

/// An event used in the mutate-stop example.
class MyEvent {
  /// Whether this event should be cancelled.
  final bool shouldCancel;

  /// Creates a [MyEvent].
  const MyEvent({this.shouldCancel = false});

  /// Returns a copy of this event.
  MyEvent copyWith({bool? modified}) => MyEvent(shouldCancel: shouldCancel);

  /// Sentinel cancelled value.
  static const cancelled = MyEvent(shouldCancel: true);
}

// #docregion event-bus-mutate-stop
Future<void> demonstrateMutateAndStop(EventBus bus) async {
  bus.on<MyEvent>((env) async {
    env.event = env.event.copyWith(modified: true);
  }, priority: 10);

  bus.on<MyEvent>((env) async {
    if (env.event.shouldCancel) env.stop(MyEvent.cancelled);
  });

  final result = await bus.emit<MyEvent>(event: const MyEvent());

  bus.bind((obs) => print('saw ${obs.event}'));

  bus.onRequest<SearchQuery, SearchResults>(
    (req) async => const SearchResults(results: ['r']),
  );

  final results = await bus.request<SearchQuery, SearchResults>(
    const SearchQuery(query: 'dart patterns'),
  );

  print(results.results);
  print(result.event.shouldCancel);
}
// #enddocregion event-bus-mutate-stop

// #docregion event-bus-standalone
void demonstrateStandaloneEventBus() {
  final bus = EventBus();

  bus.on<UserMessage>((env) {
    print('received: ${env.event.text}');
  });

  bus.bind((obs) => print('binding saw: ${obs.event.runtimeType}'));
}
// #enddocregion event-bus-standalone

// #docregion event-bus-envelope-class
void demonstrateEventEnvelope(EventEnvelope<UserMessage> envelope) {
  // Read the payload.
  print(envelope.event.text);

  // Mutate it for downstream handlers.
  envelope.event = UserMessage(text: envelope.event.text.toUpperCase());

  // Stop the cascade with a final value.
  envelope.stop(const UserMessage(text: '[stopped]'));

  print('Stopped: ${envelope.stopped}');
}
// #enddocregion event-bus-envelope-class

// #docregion event-bus-unawaited-vs-awaited
/// Wrong: handler throws but the error is on the unobserved Future.
// context.bus.emit<UserMessage>(event: const UserMessage(text: '...'));

/// Right: caller sees the exception.
Future<void> correctEmitUsage(PluginContext context) async {
  await context.bus.emit<UserMessage>(event: const UserMessage(text: 'hello'));
}
// #enddocregion event-bus-unawaited-vs-awaited

// #docregion event-bus-maybe-request
/// Demonstrates maybeRequest returning null when no handler answers.
Future<void> demonstrateMaybeRequest(PluginContext context) async {
  context.bus.onRequest<SearchQuery, SearchResults?>((env) async {
    if (env.event.query.isEmpty) return null;
    return SearchResults(results: ['result_${env.event.query}']);
  });

  final result = await context.bus.maybeRequest<SearchQuery, SearchResults?>(
    const SearchQuery(query: 'dart'),
  );
  // result is SearchResults?

  final result2 = await context.bus.request<SearchQuery, SearchResults?>(
    const SearchQuery(query: 'dart'),
  );
  // result2 is SearchResults?, no throw on null cascade.
  print('$result $result2');
}
// #enddocregion event-bus-maybe-request

/// A user message received event used in the stateful-service emit example.
class UserMessageReceived {
  /// The session identifier.
  final String sessionId;

  /// The message text.
  final String text;

  /// Creates a [UserMessageReceived] event.
  const UserMessageReceived({required this.sessionId, required this.text});
}

// #docregion events-stateful-emit
/// Demonstrates emitting a [UserMessageReceived] event from a stateful service.
class MessageDispatchService extends StatefulPluginService {
  /// The current session id, set on attach.
  String currentSession = 'default';

  @override
  void attach() {
    on<UserMessage>((e) async {
      await emit(
        UserMessageReceived(sessionId: currentSession, text: e.event.text),
      );
    });
  }
}
// #enddocregion events-stateful-emit

/// A request type asking for an open port number.
class FindOpenPort {
  /// Creates a [FindOpenPort] request.
  const FindOpenPort();
}

// #docregion events-request-find-port
/// Demonstrates request/response for finding an open port.
Future<int?> requestOpenPort(PluginContext context) async {
  final port = await context.bus.request<FindOpenPort, int?>(
    const FindOpenPort(),
  );
  return port;
}

// #enddocregion events-request-find-port
