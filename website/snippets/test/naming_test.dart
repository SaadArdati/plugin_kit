import 'package:docs_snippets/naming.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('naming-event-past-tense', () {
    test('UserLoggedIn holds userId', () {
      const e = UserLoggedIn(userId: 'u-1');
      expect(e.userId, equals('u-1'));
    });
  });

  group('naming-event-imperative', () {
    test('SendNotification holds message and channel', () {
      const cmd = SendNotification(message: 'hello', channel: 'slack');
      expect(cmd.message, equals('hello'));
      expect(cmd.channel, equals('slack'));
    });
  });

  group('naming-event-draft', () {
    test('DraftOutgoingMessage has mutable text', () {
      final draft = DraftOutgoingMessage('hi');
      draft.text = 'bye';
      expect(draft.text, equals('bye'));
    });
  });

  group('naming-capability', () {
    test('SupportsLanguages holds language list', () {
      const cap = SupportsLanguages(['dart', 'js']);
      expect(cap.languages, containsAll(['dart', 'js']));
    });
  });

  group('naming-settings-keys', () {
    test('settings example has linter_suite plugin', () {
      expect(
        exampleSettings.plugins.containsKey(const PluginId('linter_suite')),
        isTrue,
      );
    });
  });

  group('naming-plugin-id', () {
    test('linter plugin id has correct value', () {
      expect(linter, equals(const PluginId('linter_suite')));
    });
  });

  group('naming-namespace-composition', () {
    test('namespace composition runs without error', () {
      demonstrateNamespaceComposition();
    });
  });
}
