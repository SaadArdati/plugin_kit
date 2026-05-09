import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

import 'plugins/auto_retry_plugin.dart';
import 'plugins/base_mcp_plugin.dart';
import 'plugins/brave_search_plugin.dart';
import 'plugins/chat_plugin.dart';
import 'plugins/circuit_breaker_plugin.dart';
import 'plugins/context_injector_plugin.dart';
import 'plugins/core_plugin.dart';
import 'plugins/dart_sdk_mcp_plugin.dart';
import 'plugins/debug_overrides_plugin.dart';
import 'plugins/enterprise_chat_plugin.dart';
import 'plugins/exponential_backoff_plugin.dart';
import 'plugins/firebase_mcp_plugin.dart';
import 'plugins/kagi_search_plugin.dart';
import 'plugins/legacy_anthropic_plugin.dart';
import 'plugins/local_llm_runner_plugin.dart';
import 'plugins/memory_keeper_plugin.dart';
import 'plugins/model_router_plugin.dart';
import 'plugins/research_agent_plugin.dart';
import 'plugins/thread_summarizer_plugin.dart';
import 'plugins/web_search_explorer_plugin.dart';

/// Builds the visuals plugin that maps the three visual axes (plugin,
/// namespace, service) to icons, colors, and labels for the dialog UI.
Plugin visualsPlugin() => PluginKitVisualsPlugin(
  pluginVisuals: {
    CorePlugin.id: const PluginKitVisual(
      label: 'Core',
      description:
          'Provides locked baseline system and agent services for demos.',
      icon: Icon(Icons.settings_outlined),
      color: Color(0xFF9E9E9E),
    ),
    BaseMcpPlugin.id: const PluginKitVisual(
      label: 'Base MCP',
      description:
          'Locked MCP foundation that owns the shared `mcp` namespace and '
          'transport. Firebase and Dart SDK MCP plugins depend on it.',
      icon: Icon(Icons.hub_outlined),
      color: Color(0xFF455A64),
    ),
    ChatPlugin.id: const PluginKitVisual(
      label: 'Chat',
      description:
          'Provides main agent model, temperature, and system message demo controls.',
      icon: Icon(Icons.psychology),
      color: Color(0xFF2196F3),
    ),
    EnterpriseChatPlugin.id: const PluginKitVisual(
      label: 'Enterprise Chat',
      description:
          'Overrides agent stack with enterprise-tier defaults and audit fields.',
      icon: Icon(Icons.business),
      color: Color(0xFF4CAF50),
    ),
    LegacyAnthropicPlugin.id: const PluginKitVisual(
      label: 'Legacy Anthropic',
      description:
          'Deprecated direct Anthropic transport kept for migration tests.',
      icon: Icon(Icons.history),
      color: Color(0xFFFFB300),
    ),
    AutoRetryPlugin.id: const PluginKitVisual(
      label: 'Auto Retry',
      description: 'Adds a retry policy service for demo settings.',
      icon: Icon(Icons.replay),
      color: Color(0xFF607D8B),
    ),
    ContextInjectorPlugin.id: const PluginKitVisual(
      label: 'Context Injector',
      description: 'Adds configurable context injection rules for demos.',
      icon: Icon(Icons.alt_route),
      color: Color(0xFF7B1FA2),
    ),
    FirebaseMcpPlugin.id: const PluginKitVisual(
      label: 'Firebase MCP',
      description:
          'Registers a demo MCP client service for Firebase connectivity.',
      icon: Icon(Icons.cloud),
      color: Color(0xFFFF9800),
    ),
    WebSearchExplorerPlugin.id: const PluginKitVisual(
      label: 'Web Search Explorer',
      description: 'Provides a demo search provider selector.',
      icon: Icon(Icons.travel_explore),
      color: Color(0xFFFF9500),
    ),
    BraveSearchPlugin.id: const PluginKitVisual(
      label: 'Brave Search',
      description: 'Demo Brave Search provider with API-key configuration.',
      icon: Icon(Icons.shield_outlined),
      color: Color(0xFFFF6B35),
    ),
    ExponentialBackoffPlugin.id: const PluginKitVisual(
      label: 'Exponential Backoff',
      description:
          'Replaces the linear retry policy with an exponential schedule.',
      icon: Icon(Icons.show_chart),
      color: Color(0xFFC0CA33),
    ),
    MemoryKeeperPlugin.id: const PluginKitVisual(
      label: 'Memory Keeper',
      description: 'Prepends a memory recall block to the system message.',
      icon: Icon(Icons.psychology_alt),
      color: Color(0xFF5C6BC0),
    ),
    ThreadSummarizerPlugin.id: const PluginKitVisual(
      label: 'Thread Summarizer',
      description: 'Replaces the system message with a rolling thread summary.',
      icon: Icon(Icons.summarize),
      color: Color(0xFFEC407A),
    ),
    ModelRouterPlugin.id: const PluginKitVisual(
      label: 'Model Router',
      description:
          'Experimental multi-provider routing with weighted failover.',
      icon: Icon(Icons.device_hub),
      color: Color(0xFF26C6DA),
    ),
    DartSdkMcpPlugin.id: const PluginKitVisual(
      label: 'Dart SDK MCP',
      description: 'Experimental MCP client for Dart SDK tooling integration.',
      icon: Icon(Icons.developer_mode),
      color: Color(0xFF42A5F5),
    ),
    ResearchAgentPlugin.id: const PluginKitVisual(
      label: 'Research Agent',
      description: 'Experimental research-policy configuration for agent runs.',
      icon: Icon(Icons.science),
      color: Color(0xFF66BB6A),
    ),
    LocalLlmRunnerPlugin.id: const PluginKitVisual(
      label: 'Local LLM Runner',
      description:
          'Experimental on-device model runner with hardware settings.',
      icon: Icon(Icons.computer),
      color: Color(0xFFAB47BC),
    ),
    KagiSearchPlugin.id: const PluginKitVisual(
      label: 'Kagi Search',
      description: 'Experimental Kagi search provider with subscription key.',
      icon: Icon(Icons.search),
      color: Color(0xFF26A69A),
    ),
    CircuitBreakerPlugin.id: const PluginKitVisual(
      label: 'Circuit Breaker',
      description: 'Experimental circuit-breaker retry policy competitor.',
      icon: Icon(Icons.electric_bolt),
      color: Color(0xFFEF5350),
    ),
    DebugOverridesPlugin.id: const PluginKitVisual(
      label: 'Debug Overrides',
      description: 'Experimental debug-mode overrides for development builds.',
      icon: Icon(Icons.bug_report),
      color: Color(0xFF8D6E63),
    ),
  },
  namespaceVisuals: {
    CorePlugin.agentNamespace: const PluginKitVisual(
      label: 'Main Agent',
      description: 'Agent model, sampling, system message',
      icon: Icon(Icons.smart_toy),
      color: Color(0xFF7C5CFF),
    ),
    WebSearchExplorerPlugin.namespace: const PluginKitVisual(
      label: 'Search',
      icon: Icon(Icons.travel_explore),
      color: Color(0xFFFF9500),
    ),
    BaseMcpPlugin.namespace: const PluginKitVisual(
      label: 'MCP',
      icon: Icon(Icons.cloud),
      color: Color(0xFF26A69A),
    ),
    AutoRetryPlugin.namespace: const PluginKitVisual(
      label: 'Retry',
      icon: Icon(Icons.replay),
    ),
    CorePlugin.systemNamespace: const PluginKitVisual(
      label: 'System',
      icon: Icon(Icons.settings_outlined),
    ),
  },
  serviceVisuals: {
    CorePlugin.model: const PluginKitVisual(
      label: 'Model & Provider',
      icon: Icon(Icons.tune),
    ),
    ChatPlugin.temperature: const PluginKitVisual(
      label: 'Temperature',
      icon: Icon(Icons.thermostat),
    ),
    CorePlugin.systemMessage: const PluginKitVisual(
      label: 'System Message',
      icon: Icon(Icons.description),
    ),
    WebSearchExplorerPlugin.provider: const PluginKitVisual(
      label: 'Provider',
      icon: Icon(Icons.public),
    ),
    AutoRetryPlugin.linear: const PluginKitVisual(
      label: 'Linear',
      icon: Icon(Icons.replay),
    ),
    ExponentialBackoffPlugin.exponential: const PluginKitVisual(
      label: 'Exponential',
      icon: Icon(Icons.show_chart),
    ),
    CircuitBreakerPlugin.circuitBreaker: const PluginKitVisual(
      label: 'Circuit Breaker',
      icon: Icon(Icons.electric_bolt),
    ),
    DebugOverridesPlugin.debug: const PluginKitVisual(
      label: 'Debug',
      icon: Icon(Icons.bug_report),
    ),
    BaseMcpPlugin.transport: const PluginKitVisual(
      label: 'Transport',
      icon: Icon(Icons.swap_horiz),
    ),
    FirebaseMcpPlugin.firebase: const PluginKitVisual(
      label: 'Firebase',
      icon: Icon(Icons.cloud),
    ),
    DartSdkMcpPlugin.dartSdk: const PluginKitVisual(
      label: 'Dart SDK',
      icon: Icon(Icons.developer_mode),
    ),
    ContextInjectorPlugin.contextInjector: const PluginKitVisual(
      label: 'Context Injector',
      icon: Icon(Icons.alt_route),
    ),
    ResearchAgentPlugin.researchPolicy: const PluginKitVisual(
      label: 'Research Policy',
      icon: Icon(Icons.science),
    ),
    ModelRouterPlugin.strategy: const PluginKitVisual(
      label: 'Routing Strategy',
      icon: Icon(Icons.alt_route),
    ),
  },
);
