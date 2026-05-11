import 'package:docs_snippets/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('testing-assert-cascade', () {
    test('cascade mutation uppercases draft text', () async {
      await testAssertCascade();
    });

    test('DraftMessage text is mutable', () {
      final msg = DraftMessage('hello');
      msg.text = 'world';
      expect(msg.text, equals('world'));
    });
  });

  group('testing-level-1-service', () {
    test('NotificationService applies configured channel', () {
      testNotificationServiceChannel();
    });
  });

  group('testing-level-2-plugin', () {
    test('plugin answers notification request', () async {
      final result = await testPluginAnswersRequest();
      expect(result, isTrue);
    });
  });

  group('testing-tracking-plugin', () {
    test('TrackingPlugin tracks lifecycle calls', () async {
      final runtime = PluginRuntime();
      final plugin = TrackingPlugin(const PluginId('trackee'));
      runtime.addPlugin(plugin);
      runtime.init();
      final session = await runtime.createSession();
      await session.dispose();
      expect(plugin.calls, equals(['register', 'attach', 'detach']));
      await runtime.dispose();
    });
  });

  group('testing-level-3-lifecycle', () {
    test('lifecycle order matches expected', () async {
      await testLifecycleOrder();
    });
  });

  group('testing-update-settings-disable', () {
    test('plugin disables after updateSettings', () async {
      await testPluginDisabledByUpdateSettings();
    });
  });

  group('testing-stateful-service', () {
    test('ChatBuffer records messages while attached', () async {
      await testChatBufferRecordsMessages();
    });
  });

  group('testing-lifecycle-exception', () {
    test('bad plugin surfaces PluginLifecycleException', () async {
      await testBadPluginSurfacesException();
    });
  });

  group('testing-stub-inject-fake', () {
    test('FakeLogger resolves through the stub registry', () {
      demonstrateStubInjectFake();
    });
  });
}
