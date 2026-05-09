import 'package:flutter/material.dart';
import 'package:flutter_plugin_kit/flutter_plugin_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:provider/provider.dart';
import 'package:state_garden/state_garden.dart';

/// Pumps the supplied screen against a real [PluginRuntime], types
/// "hello" into the message input, taps send, and asserts the user line and
/// bot reply both render.
///
/// This catches bridge wiring failures such as missing/incorrect
/// subscriptions, reading payload from the wrong event shape (direct payload
/// instead of envelope event), or basic state-to-UI propagation breaks.
Future<void> _proveBridge(
  WidgetTester tester,
  Widget Function(RuntimeHolder holder) screenBuilder,
) async {
  final RuntimeHolder holder = await RuntimeHolder.create();
  addTearDown(holder.dispose);

  await tester.pumpWidget(
    MaterialApp(home: Material(child: screenBuilder(holder))),
  );
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(MessageInput.fieldKey), 'hello');
  await tester.tap(find.byKey(MessageInput.sendButtonKey));
  await tester.pumpAndSettle();

  expect(find.text('hello'), findsOneWidget);
  expect(find.text('echo: hello'), findsOneWidget);
}

void main() {
  testWidgets('setState bridge', (WidgetTester tester) async {
    await _proveBridge(
      tester,
      (RuntimeHolder h) => SetStateChatScreen(session: h.session),
    );
  });

  testWidgets('flutter_plugin_kit State mixin bridge', (
    WidgetTester tester,
  ) async {
    final RuntimeHolder holder = await RuntimeHolder.create();
    addTearDown(holder.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: FlutterPluginKitChatScreen(session: holder.session),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Bridge-mechanism proof: the screen's State must actually mix in
    // PluginSessionStateListener. Replacing the screen with a raw
    // session.on + setState recipe would fail this isA check, even though
    // chat-flow assertions would still pass.
    final State<dynamic> state = tester.state(
      find.byType(FlutterPluginKitChatScreen),
    );
    expect(
      state,
      isA<PluginSessionStateListener>(),
      reason:
          'screen must use PluginSessionStateListener mixin; replacing it '
          'with raw session.on + StreamSubscription should fail this test',
    );

    await tester.enterText(find.byKey(MessageInput.fieldKey), 'hello');
    await tester.tap(find.byKey(MessageInput.sendButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('echo: hello'), findsOneWidget);
  });

  testWidgets('ChangeNotifier + provider bridge', (WidgetTester tester) async {
    await _proveBridge(
      tester,
      (RuntimeHolder h) => ChangeNotifierChatScreen(session: h.session),
    );
  });

  testWidgets('plugin_kit PluginSessionListener mixin bridge', (
    WidgetTester tester,
  ) async {
    final RuntimeHolder holder = await RuntimeHolder.create();
    addTearDown(holder.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: PluginSessionListenerChatScreen(session: holder.session),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Bridge-mechanism proof: the chat notifier must actually mix in
    // PluginSessionListener (pure-Dart mixin from package:plugin_kit).
    // Replacing the bridge with manual session.on + StreamSubscription
    // plumbing would still pass the UI round-trip below, so we look at
    // the type of the notifier reachable through provider.
    final BuildContext bodyContext = tester.element(find.byType(ChatView));
    final ChatSessionListenerNotifier bridge =
        Provider.of<ChatSessionListenerNotifier>(bodyContext, listen: false);
    expect(
      bridge,
      isA<PluginSessionListener>(),
      reason:
          'bridge must mix in PluginSessionListener; replacing it with manual '
          'session.on + StreamSubscription should fail this test',
    );

    await tester.enterText(find.byKey(MessageInput.fieldKey), 'hello');
    await tester.tap(find.byKey(MessageInput.sendButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('echo: hello'), findsOneWidget);
  });

  testWidgets('flutter_plugin_kit PluginEventNotifier bridge', (
    WidgetTester tester,
  ) async {
    final RuntimeHolder holder = await RuntimeHolder.create();
    addTearDown(holder.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: FlutterPluginKitNotifierChatScreen(session: holder.session),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Bridge-mechanism proof: a PluginEventNotifier<ChatMessagesChanged>
    // must be reachable through the provider tree under ChatView. The
    // typed `Provider.of<...>` lookup itself enforces the type at the
    // call site (a different ChangeNotifier subclass under the same
    // provider type would not compile). The .value assertion below is
    // the actual mechanism check: a regression that broke the
    // notifier's session subscription would leave .value null after a
    // successful chat round trip.
    final BuildContext bodyContext = tester.element(find.byType(ChatView));
    final PluginEventNotifier<ChatMessagesChanged> notifier =
        Provider.of<PluginEventNotifier<ChatMessagesChanged>>(
          bodyContext,
          listen: false,
        );

    await tester.enterText(find.byKey(MessageInput.fieldKey), 'hello');
    await tester.tap(find.byKey(MessageInput.sendButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('echo: hello'), findsOneWidget);

    // The notifier's value must reflect the latest snapshot. A regression
    // that broke its subscription wiring would leave .value null even
    // though chat-flow assertions above still pass via the underlying
    // ChatService instance.
    expect(
      notifier.value,
      isNotNull,
      reason:
          'PluginEventNotifier must have observed ChatMessagesChanged '
          'after the round-trip; null indicates subscription wiring is broken',
    );
    expect(notifier.value!.messages.last.text, 'echo: hello');
  });

  testWidgets('flutter_bloc Cubit bridge', (WidgetTester tester) async {
    await _proveBridge(
      tester,
      (RuntimeHolder h) => BlocChatScreen(session: h.session),
    );
  });

  testWidgets('Riverpod AsyncNotifier bridge', (WidgetTester tester) async {
    final RuntimeHolder holder = await RuntimeHolder.create();
    addTearDown(holder.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sessionProvider.overrideWithValue(holder.session),
        ],
        child: const MaterialApp(home: Material(child: RiverpodChatScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(MessageInput.fieldKey), 'hello');
    await tester.tap(find.byKey(MessageInput.sendButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('echo: hello'), findsOneWidget);
  });

  testWidgets('Riverpod bridge: provider swap tears down old subscription', (
    WidgetTester tester,
  ) async {
    final PluginRuntime m1 = PluginRuntime(plugins: <Plugin>[ChatPlugin()])
      ..init();
    final PluginRuntime m2 = PluginRuntime(plugins: <Plugin>[ChatPlugin()])
      ..init();
    addTearDown(m1.dispose);
    addTearDown(m2.dispose);

    final PluginSession s1 = await m1.createSession();
    final PluginSession s2 = await m2.createSession();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[sessionProvider.overrideWithValue(s1)],
        child: const MaterialApp(home: Material(child: RiverpodChatScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await s1.bus.emit<SendMessageRequested>(
      event: const SendMessageRequested('first message'),
    );
    await tester.pumpAndSettle();
    expect(find.text('first message'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[sessionProvider.overrideWithValue(s2)],
        child: const MaterialApp(home: Material(child: RiverpodChatScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await s1.bus.emit<SendMessageRequested>(
      event: const SendMessageRequested('post-swap message to s1'),
    );
    await tester.pumpAndSettle();
    expect(find.text('post-swap message to s1'), findsNothing);
    expect(find.text('echo: post-swap message to s1'), findsNothing);

    await s2.bus.emit<SendMessageRequested>(
      event: const SendMessageRequested('message to s2'),
    );
    await tester.pumpAndSettle();
    expect(find.text('message to s2'), findsOneWidget);
    expect(find.text('echo: message to s2'), findsOneWidget);

    await s1.dispose();
    await s2.dispose();
  });

  testWidgets('signals_flutter bridge', (WidgetTester tester) async {
    await _proveBridge(
      tester,
      (RuntimeHolder h) => SignalsChatScreen(session: h.session),
    );
  });

  testWidgets('MobX bridge', (WidgetTester tester) async {
    await _proveBridge(
      tester,
      (RuntimeHolder h) => MobxChatScreen(session: h.session),
    );
  });

  testWidgets('GetIt bridge', (WidgetTester tester) async {
    final GetIt locator = GetIt.asNewInstance();
    final RuntimeHolder holder = await RuntimeHolder.create();
    addTearDown(() async {
      await holder.dispose();
      await locator.reset();
    });
    locator.registerSingleton<PluginSession>(holder.session);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(child: GetItChatScreen(locator: locator)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(MessageInput.fieldKey), 'hello');
    await tester.tap(find.byKey(MessageInput.sendButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('echo: hello'), findsOneWidget);
  });
}
