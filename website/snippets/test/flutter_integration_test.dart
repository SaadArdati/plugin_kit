import 'package:docs_snippets/flutter_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('flutter-terminal-plugin', () {
    test('TerminalPlugin registers PanelWidgetFactory', () async {
      final runtime = PluginRuntime(plugins: [TerminalPlugin()])..init();
      final session = await runtime.createSession();

      const panel = Namespace('panel');
      final factory = session.resolve<PanelWidgetFactory>(panel('terminal'));
      expect(factory, isNotNull);
      await runtime.dispose();
    });
  });

  group('flutter-fake-search-plugin', () {
    test('FakeSearchPlugin registers SearchService', () async {
      final runtime = PluginRuntime(plugins: [FakeSearchPlugin()])..init();
      final session = await runtime.createSession();

      final search = session.resolve<SearchService>(const ServiceId('search'));
      expect(search.search('dart'), equals(['fake_dart']));
      await runtime.dispose();
    });
  });

  group('flutter-plugin-event-notifier', () {
    test('PluginEventCubit can be created and closed', () async {
      final runtime = PluginRuntime()..init();
      final session = await runtime.createSession();

      final cubit = PluginEventCubit<ChatMessageReceived>(session);
      expect(cubit.value, isNull);
      cubit.close();
      await runtime.dispose();
    });
  });

  group('flutter-chat-controller', () {
    test('ChatController attaches and disposes without error', () async {
      final runtime = PluginRuntime()..init();
      final session = await runtime.createSession();

      final controller = ChatController(session);
      expect(controller, isNotNull);
      controller.dispose();
      await runtime.dispose();
    });
  });

  group('flutter-toggle-pending-serialize', () {
    test('TogglePendingExample serializes setEnabled calls', () async {
      final example = TogglePendingExample();
      // setEnabled chains onto togglePending; calling twice should not throw.
      await example.setEnabled(const PluginId('chat'), true);
      await example.setEnabled(const PluginId('chat'), false);
    });
  });
}
