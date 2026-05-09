import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:state_garden/state_garden.dart';

/// Pure plugin_kit lifecycle proofs. No widgets, no state-management
/// libraries: these tests cite plugin_kit behavior directly.
void main() {
  test(
    'settings reconcile: disabling the plugin tears down its handlers',
    () async {
      final PluginRuntimeManager manager = PluginRuntimeManager(
        plugins: <Plugin>[ChatPlugin()],
      )..init();
      addTearDown(manager.dispose);

      final PluginSession session = await manager.createSession();

      ChatMessagesChanged? received;
      final sub = session.on<ChatMessagesChanged>((env) {
        received = env.event;
      });
      addTearDown(sub.cancel);

      await session.emit(const SendMessageRequested('first'));
      expect(
        received,
        isNotNull,
        reason: 'plugin should respond while enabled',
      );
      expect(received!.messages.last.text, equals('echo: first'));

      received = null;
      await manager.runtime.updateSessionSettings(
        session,
        newSettings: const RuntimeSettings(
          plugins: <PluginId, PluginConfig>{
            ChatPlugin.id: PluginConfig(enabled: false),
          },
        ),
      );

      await session.emit(const SendMessageRequested('after-disable'));
      expect(received, isNull, reason: 'detached plugin must not respond');
    },
  );

  test('session swap: a new session has fresh state', () async {
    final PluginRuntimeManager manager = PluginRuntimeManager(
      plugins: <Plugin>[ChatPlugin()],
    )..init();
    addTearDown(manager.dispose);

    final PluginSession s1 = await manager.createSession();
    await s1.emit(const SendMessageRequested('on-s1'));
    final ChatService svc1 = s1.resolve<ChatService>(ChatPlugin.serviceId);
    expect(svc1.messages, hasLength(2));

    await s1.dispose();

    final PluginSession s2 = await manager.createSession();
    final ChatService svc2 = s2.resolve<ChatService>(ChatPlugin.serviceId);
    expect(
      svc2.messages,
      isEmpty,
      reason: 'session 2 must not see session 1 state',
    );
    expect(
      identical(svc1, svc2),
      isFalse,
      reason: 'each session constructs its own service instance',
    );

    await s2.emit(const SendMessageRequested('on-s2'));
    expect(svc2.messages, hasLength(2));
    expect(
      svc1.messages,
      hasLength(2),
      reason: 's1 service is detached and cannot grow further',
    );
  });

  test('two live sessions stay isolated', () async {
    final PluginRuntimeManager manager = PluginRuntimeManager(
      plugins: <Plugin>[ChatPlugin()],
    )..init();
    addTearDown(manager.dispose);

    final PluginSession s1 = await manager.createSession();
    final PluginSession s2 = await manager.createSession();

    await s1.bus.emit<SendMessageRequested>(
      event: const SendMessageRequested('to s1'),
    );
    await s2.bus.emit<SendMessageRequested>(
      event: const SendMessageRequested('to s2'),
    );

    final ChatService s1Chat = s1.resolve<ChatService>(ChatPlugin.serviceId);
    final ChatService s2Chat = s2.resolve<ChatService>(ChatPlugin.serviceId);

    expect(s1Chat.messages.map((m) => m.text), contains('to s1'));
    expect(s1Chat.messages.map((m) => m.text), isNot(contains('to s2')));
    expect(s2Chat.messages.map((m) => m.text), contains('to s2'));
    expect(s2Chat.messages.map((m) => m.text), isNot(contains('to s1')));

    await s1.dispose();
    await s2.dispose();
  });

  test('canonical dispose: manager.dispose tears down sessions', () async {
    final PluginRuntimeManager manager = PluginRuntimeManager(
      plugins: <Plugin>[ChatPlugin()],
    )..init();

    final PluginSession session = await manager.createSession();
    final EventBus bus = session.bus;
    expect(bus.isDisposed, isFalse);
    expect(manager.runtime.sessions, hasLength(1));

    await manager.dispose();

    expect(
      bus.isDisposed,
      isTrue,
      reason: 'manager.dispose must dispose live session buses',
    );
    expect(
      manager.runtime.sessions,
      isEmpty,
      reason: 'sessions list must be drained after dispose',
    );
  });

  test(
    'hot-swap: priority winner shifts when higher one is disabled',
    () async {
      final PluginRuntimeManager manager = PluginRuntimeManager(
        plugins: <Plugin>[ChatPlugin(), AltChatPlugin()],
      )..init();
      addTearDown(manager.dispose);

      final PluginSession session = await manager.createSession();

      final ChatService winner1 = session.resolve<ChatService>(
        ChatPlugin.serviceId,
      );
      expect(
        winner1,
        isA<AltChatService>(),
        reason: 'priority 100 should beat default 50',
      );
      expect(winner1.replyPrefix, equals('alt: '));

      await manager.runtime.updateSessionSettings(
        session,
        newSettings: const RuntimeSettings(
          plugins: <PluginId, PluginConfig>{
            AltChatPlugin.id: PluginConfig(enabled: false),
          },
        ),
      );

      final ChatService winner2 = session.resolve<ChatService>(
        ChatPlugin.serviceId,
      );
      expect(
        winner2,
        isNot(isA<AltChatService>()),
        reason: 'AltChatService unregistered, base ChatService should win',
      );
      expect(winner2.replyPrefix, equals('echo: '));
      expect(
        identical(winner1, winner2),
        isFalse,
        reason: 'different concrete service instance after hot-swap',
      );
    },
  );

  test('toggle race: latest intent converges deterministically', () async {
    final PluginRuntimeManager manager = PluginRuntimeManager(
      plugins: <Plugin>[ChatPlugin(), AltChatPlugin()],
    )..init();
    addTearDown(manager.dispose);
    final PluginSession session = await manager.createSession();

    expect(session.isPluginEnabled(ChatPlugin.id), isTrue);
    expect(session.isPluginEnabled(AltChatPlugin.id), isTrue);

    const settings1 = RuntimeSettings(
      plugins: <PluginId, PluginConfig>{
        AltChatPlugin.id: PluginConfig(enabled: true),
      },
    );
    const settings2 = RuntimeSettings(
      plugins: <PluginId, PluginConfig>{
        AltChatPlugin.id: PluginConfig(enabled: false),
      },
    );

    final Future<void> f1 = manager.updateSettings(settings1);
    final Future<void> f2 = manager.updateSettings(settings2);
    await Future.wait<void>(<Future<void>>[f1, f2]);

    expect(
      manager.attachedPluginIds.contains(AltChatPlugin.id),
      isFalse,
      reason: 'latest intent should disable AltChatPlugin at runtime',
    );
    expect(
      manager.enabledPluginIds.contains(AltChatPlugin.id),
      isFalse,
      reason: 'latest intent should disable AltChatPlugin in settings',
    );
  });
}
