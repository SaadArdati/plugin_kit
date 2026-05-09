/// Reference implementations and integration proofs for using plugin_kit
/// alongside Flutter state management libraries.
///
/// Each integration is exposed as a public bridge class plus a public screen
/// widget. Tests in this package exercise the same classes the example app
/// imports, so the integrations are kept honest by `flutter test` and
/// `flutter analyze`.
library;

// Chat protocol.
export 'src/chat/chat_events.dart';
export 'src/chat/chat_message.dart';
export 'src/chat/chat_plugin.dart';
export 'src/chat/chat_service.dart';

// Runtime fixture used by tests and the example app.
export 'src/runtime_holder.dart';

// Reusable presentation widgets.
export 'src/widgets/chat_view.dart';
export 'src/widgets/message_input.dart';
export 'src/widgets/message_list.dart';

// Integrations.
export 'src/integrations/bloc_chat.dart';
export 'src/integrations/change_notifier_chat.dart';
export 'src/integrations/flutter_plugin_kit_chat_screen.dart';
export 'src/integrations/flutter_plugin_kit_notifier_chat.dart';
export 'src/integrations/get_it_chat_screen.dart';
export 'src/integrations/integration_launcher.dart';
export 'src/integrations/mobx_chat.dart';
export 'src/integrations/plugin_kit_session_listener_chat.dart';
export 'src/integrations/riverpod_chat.dart';
export 'src/integrations/set_state_chat_screen.dart';
export 'src/integrations/signals_chat.dart';
