import 'package:plugin_kit/plugin_kit.dart';

import 'auto_retry_plugin.dart';
import 'base_mcp_plugin.dart';
import 'brave_search_plugin.dart';
import 'chat_plugin.dart';
import 'circuit_breaker_plugin.dart';
import 'context_injector_plugin.dart';
import 'core_plugin.dart';
import 'dart_sdk_mcp_plugin.dart';
import 'debug_overrides_plugin.dart';
import 'enterprise_chat_plugin.dart';
import 'exponential_backoff_plugin.dart';
import 'firebase_mcp_plugin.dart';
import 'kagi_search_plugin.dart';
import 'legacy_anthropic_plugin.dart';
import 'local_llm_runner_plugin.dart';
import 'memory_keeper_plugin.dart';
import 'model_router_plugin.dart';
import 'research_agent_plugin.dart';
import 'thread_summarizer_plugin.dart';
import 'web_search_explorer_plugin.dart';

export 'auto_retry_plugin.dart';
export 'base_mcp_plugin.dart';
export 'brave_search_plugin.dart';
export 'chat_plugin.dart';
export 'circuit_breaker_plugin.dart';
export 'context_injector_plugin.dart';
export 'core_plugin.dart';
export 'dart_sdk_mcp_plugin.dart';
export 'debug_overrides_plugin.dart';
export 'enterprise_chat_plugin.dart';
export 'exponential_backoff_plugin.dart';
export 'firebase_mcp_plugin.dart';
export 'kagi_search_plugin.dart';
export 'legacy_anthropic_plugin.dart';
export 'local_llm_runner_plugin.dart';
export 'memory_keeper_plugin.dart';
export 'model_router_plugin.dart';
export 'research_agent_plugin.dart';
export 'thread_summarizer_plugin.dart';
export 'web_search_explorer_plugin.dart';

/// Returns the full demo plugin set for plugin_kit_dialog.
///
/// The set showcases:
/// - Namespace coordination via parallel redeclaration: `agent` is
///   co-defined by [CorePlugin] (`model`, `system_message`),
///   [ChatPlugin] (`temperature`), and [ResearchAgentPlugin]
///   (`research_policy`) - each redeclares `Namespace('agent')` independently.
/// - Namespace coordination via dependency: `mcp` is owned by
///   [BaseMcpPlugin]; [FirebaseMcpPlugin] and [DartSdkMcpPlugin] depend on it
///   and define their own slots inside `BaseMcpPlugin.namespace`.
/// - Unnamespaced services: [ContextInjectorPlugin] and [ModelRouterPlugin]
///   register flat services without a namespace.
/// - Multi-namespace plugin ownership: [CorePlugin] owns slots in both
///   `agent` and `system`.
/// - Service-level priority competition: `agent:model` has 7 contenders,
///   `agent:system_message` has 5, `search:provider` has 4.
List<Plugin> demoPlugins() {
  return [
    // Baseline / locked tier.
    CorePlugin(),
    BaseMcpPlugin(),
    LegacyAnthropicPlugin(),

    // Default stable stack.
    AutoRetryPlugin(),
    ChatPlugin(),
    ContextInjectorPlugin(),
    FirebaseMcpPlugin(),
    WebSearchExplorerPlugin(),

    // Competing stable contenders.
    BraveSearchPlugin(),
    ExponentialBackoffPlugin(),
    MemoryKeeperPlugin(),
    ThreadSummarizerPlugin(),
    EnterpriseChatPlugin(),

    // Experimental contenders.
    ModelRouterPlugin(),
    DartSdkMcpPlugin(),
    ResearchAgentPlugin(),
    LocalLlmRunnerPlugin(),
    KagiSearchPlugin(),
    CircuitBreakerPlugin(),
    DebugOverridesPlugin(),
  ];
}
