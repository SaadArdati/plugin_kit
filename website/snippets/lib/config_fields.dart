/// Snippets for UiConfigurableCapability and ConfigField subclasses.
library;

import 'package:plugin_kit/plugin_kit.dart';

/// Stub service used in config field examples.
class MyService {
  /// Creates a [MyService].
  const MyService();
}

/// A stub temperature service that reads its config from injected settings.
class TemperatureService extends PluginService {
  /// The temperature value from injected settings.
  double get temperature => config.getDouble('temperature') ?? 1.0;
}

// #docregion ui-configurable-capability-number
void registerWithNumberField(ScopedServiceRegistry registry) {
  const agent = Namespace('agent');

  registry.registerSingleton<TemperatureService>(
    agent('temperature'), // ServiceId('agent.temperature')
    () => TemperatureService(),
    capabilities: const {
      UiConfigurableCapability(
        label: 'Temperature',
        description: 'Controls randomness in responses.',
        fields: [
          NumberConfigField(
            key: 'temperature',
            label: 'Temperature',
            min: 0,
            max: 2,
            step: 0.1,
            defaultValue: 1.0,
          ),
        ],
      ),
    },
  );
}
// #enddocregion ui-configurable-capability-number

// #docregion config-field-text
const textField = TextConfigField(
  key: 'api_key',
  label: 'API Key',
  placeholder: 'sk-...',
  helperText: 'Your provider API key.',
);
// #enddocregion config-field-text

// #docregion config-field-multiline
const multilineField = MultilineConfigField(
  key: 'system_prompt',
  label: 'System Prompt',
  moustacheTags: ['{{user_name}}', '{{date}}'],
  minLines: 4,
  maxLines: 12,
);
// #enddocregion config-field-multiline

// #docregion config-field-password
const passwordField = PasswordConfigField(
  key: 'secret_key',
  label: 'Secret Key',
  helperText: 'Stored encrypted.',
);
// #enddocregion config-field-password

// #docregion config-field-number
const numberField = NumberConfigField(
  key: 'max_tokens',
  label: 'Max Tokens',
  min: 100,
  max: 8192,
  step: 100,
  isInteger: true,
  defaultValue: 2048,
);
// #enddocregion config-field-number

// #docregion config-field-dropdown
const dropdownField = DropdownConfigField<String>(
  key: 'model',
  label: 'Model',
  options: [
    DropdownOption('gpt-4.1', 'GPT-4.1'),
    DropdownOption('gpt-4.1-mini', 'GPT-4.1 Mini'),
    DropdownOption('claude-3-7-sonnet', 'Claude Sonnet'),
  ],
  defaultValue: 'gpt-4.1',
);
// #enddocregion config-field-dropdown

// #docregion config-field-bool
const boolField = BoolConfigField(
  key: 'streaming',
  label: 'Streaming',
  helperText: 'Emit partial tokens as they arrive.',
  defaultValue: true,
);
// #enddocregion config-field-bool

// #docregion config-field-group
const groupField = GroupConfigField(
  key: 'limits',
  label: 'Limits',
  children: [
    NumberConfigField(
      key: 'limits.max_tokens',
      label: 'Max Tokens',
      min: 100,
      max: 8192,
      isInteger: true,
    ),
    BoolConfigField(
      key: 'limits.strict',
      label: 'Strict',
    ),
  ],
);
// #enddocregion config-field-group

// #docregion config-field-extension
const extensionField = ExtensionConfigField(
  key: 'theme.accent',
  label: 'Accent color',
  rendererKey: 'color_picker',
  args: {'allow_alpha': false},
);
// #enddocregion config-field-extension

// #docregion ui-configurable-capability-full
void registerFullCapability(ScopedServiceRegistry registry) {
  registry.registerSingleton<MyService>(
    const ServiceId('llm_service'),
    () => const MyService(),
    capabilities: const {
      UiConfigurableCapability(
        label: 'LLM Settings',
        description: 'Language model and token budget.',
        fields: [
          DropdownConfigField<String>(
            key: 'model',
            label: 'Model',
            options: [
              DropdownOption('gpt-4.1', 'GPT-4.1'),
              DropdownOption('gpt-4.1-mini', 'GPT-4.1 Mini'),
            ],
          ),
          NumberConfigField(
            key: 'temperature',
            label: 'Temperature',
            min: 0,
            max: 2,
            step: 0.1,
          ),
          BoolConfigField(
            key: 'streaming',
            label: 'Streaming',
          ),
        ],
      ),
    },
  );
}
// #enddocregion ui-configurable-capability-full
