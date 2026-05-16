import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _TestGlobalPlugin extends GlobalPlugin {
  @override
  final PluginId pluginId;

  _TestGlobalPlugin(String id) : pluginId = PluginId(id);
}

void main() {
  group('bug-hunt iter 3: settings-normalizer-shallow-copies-config-maps', () {
    test(
      'keeps runtime plugin config isolated from caller map mutations after init',
      () async {
        final runtime = PluginRuntime();
        addTearDown(runtime.dispose);

        final pid = PluginId('p1');
        final mutableConfig = <String, dynamic>{'k': 'before'};
        runtime.addPlugin(_TestGlobalPlugin('p1'));

        runtime.init(
          settings: RuntimeSettings(
            plugins: {pid: PluginConfig(config: mutableConfig)},
          ),
        );

        mutableConfig['k'] = 'after';

        expect(runtime.settings.plugins[pid]!.config['k'], 'before');
      },
    );
  });
}
