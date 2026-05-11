import 'package:docs_snippets/state_bridges.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('state-bridge-chat-message-types', () {
    test('ChatMessage, ChatMessagesChanged and SendMessageRequested are constructable', () {
      const msg = ChatMessage(author: 'alice', text: 'hi');
      const changed = ChatMessagesChanged(messages: [msg]);
      const requested = SendMessageRequested(text: 'hello');

      expect(msg.author, equals('alice'));
      expect(changed.messages, hasLength(1));
      expect(requested.text, equals('hello'));
    });
  });

  group('state-bridge-event-notifier', () {
    test('makeNotifier returns a PluginEventNotifier for a session', () async {
      final runtime = PluginRuntime.empty()..init();
      final session = await runtime.createSession();

      final notifier = makeNotifier(session);
      expect(notifier, isNotNull);
      notifier.dispose();
      await runtime.dispose();
    });
  });
}
