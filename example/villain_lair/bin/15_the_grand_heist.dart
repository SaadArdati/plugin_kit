/// # 15: End-to-End Example (Multi-Plugin System)
///
/// A full heist demonstrates most of the APIs in one file: a global plugin,
/// session plugins with dependencies, a stateful service, request/response
/// with identifiers, event mutation via `on`, settings injection, and
/// settings reconciliation through `PluginRuntime`.
library;

import 'dart:async';

import 'package:plugin_kit/plugin_kit.dart';

class HeistPhase {
  final String phase;
  final String description;
  const HeistPhase(this.phase, {required this.description});
}

/// Mutable payload so Janet's handler can append budget commentary.
class DepartmentComm {
  final String from;
  String message;
  DepartmentComm({required this.from, required this.message});
}

class ReadyCheck {
  const ReadyCheck();
}

class ReadyResponse {
  final String department;
  final bool ready;
  final String note;
  const ReadyResponse(
    this.department, {
    required this.ready,
    required this.note,
  });
}

class LootAcquired {
  final String item;
  final String acquiredBy;
  const LootAcquired(this.item, {required this.acquiredBy});
}

class AbortHeist {
  final String reason;
  const AbortHeist(this.reason);
}

class OperationLog extends SessionStatefulPluginService {
  final List<String> _entries = [];

  OperationLog();

  List<String> get entries => List.unmodifiable(_entries);

  void log(String entry) {
    _entries.add('[${DateTime.now().toString().substring(11, 19)}] $entry');
  }

  @override
  void attach() {
    log('Operation Log initialized. Recording everything.');

    on<HeistPhase>((e) {
      log('PHASE: ${e.event.phase}: ${e.event.description}');
    });

    on<DepartmentComm>((e) {
      log('COMM [${e.event.from}]: ${e.event.message}');
    });

    on<LootAcquired>((e) {
      log('LOOT: ${e.event.item} acquired by ${e.event.acquiredBy}!');
    });

    on<AbortHeist>((e) {
      log('ABORT: ${e.event.reason}');
    });
  }

  @override
  Future<void> detach() async {
    log('Operation Log closed. ${_entries.length} entries recorded.');
  }
}

class BudgetTracker extends PluginService {
  BudgetTracker();

  double get budget => config.getDouble('budget') ?? 1000.0;
  double get spent => config.getDouble('spent') ?? 0.0;
  double get remaining => budget - spent;

  String report() =>
      'Budget: \$${budget.toStringAsFixed(2)} | '
      'Spent: \$${spent.toStringAsFixed(2)} | '
      'Remaining: \$${remaining.toStringAsFixed(2)}';
}

/// Global plugin. Persists across sessions.
class WhiskersGlobalPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('whiskers_global');

  @override
  void attach(GlobalPluginContext context) {
    context.bus.on<LootAcquired>((e) {
      if (e.event.item.toLowerCase().contains('tuna')) {
        print('🐱 Mr. Whiskers: *purrs with satisfaction*');
      } else {
        print('🐱 Mr. Whiskers: That is not tuna. Disappointing.');
      }
    });
  }
}

class CommandCenterPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('command_center');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<OperationLog>(
      const ServiceId('operation_log'),
      OperationLog(),
      priority: 100,
    );
  }

  @override
  void attach(SessionPluginContext context) {
    context.bus.onRequest<ReadyCheck, ReadyResponse>(
      (req) async => const ReadyResponse(
        'Command Center',
        ready: true,
        note: 'Dr. Nefarious has finished his pre-heist monologue.',
      ),
      identifier: 'command_center',
    );
  }
}

class AccountingPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('accounting');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerLazySingleton<BudgetTracker>(
      const ServiceId('budget'),
      () => BudgetTracker(),
      priority: 100,
    );
  }

  @override
  void attach(SessionPluginContext context) {
    // Handler at priority 0 mutates every DepartmentComm to tack on a budget
    // note before later handlers see it.
    context.bus.on<DepartmentComm>((envelope) async {
      envelope.event.message =
          '${envelope.event.message} '
          '[Janet: This costs money. I am watching.]';
    }, priority: 0);

    context.bus.onRequest<ReadyCheck, ReadyResponse>(
      (req) async => const ReadyResponse(
        'Accounting',
        ready: true,
        note: 'Budget spreadsheet is open. Receipts are ready.',
      ),
      identifier: 'accounting',
    );
  }
}

class InfiltrationPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('infiltration');

  @override
  Set<PluginId> get dependencies => {const PluginId('command_center')};

  @override
  void attach(SessionPluginContext context) {
    context.bus.onRequest<ReadyCheck, ReadyResponse>(
      (req) async => const ReadyResponse(
        'Infiltration',
        ready: true,
        note: 'Stealth suits on. Nobody can see us. Except Mr. Whiskers.',
      ),
      identifier: 'infiltration',
    );
  }
}

class DistractionPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('distraction');

  @override
  Set<PluginId> get dependencies => {const PluginId('command_center')};

  @override
  void attach(SessionPluginContext context) {
    context.bus.onRequest<ReadyCheck, ReadyResponse>(
      (req) async => const ReadyResponse(
        'Distraction',
        ready: true,
        note:
            "Gary volunteered. He doesn't know it's a distraction. "
            "He thinks he's the main character.",
      ),
      identifier: 'distraction',
    );
  }
}

class GarysPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('garys_contribution');

  @override
  void attach(SessionPluginContext context) {
    context.bus.on<HeistPhase>((e) {
      print(
        "  [Gary] We're in the ${e.event.phase} phase? "
        'I LOVE that phase!',
      );
    }, priority: 50);

    context.bus.onRequest<ReadyCheck, ReadyResponse>(
      (req) async => const ReadyResponse(
        "Gary's Station",
        ready: true,
        note: 'Gary has his stapler. He is ready for anything.',
      ),
      identifier: 'gary',
    );
  }
}

Future<void> main() async {
  final runtime = PluginRuntime();

  runtime.addPlugins([
    WhiskersGlobalPlugin(),
    CommandCenterPlugin(),
    AccountingPlugin(),
    InfiltrationPlugin(),
    DistractionPlugin(),
    GarysPlugin(),
  ]);

  runtime.init();

  print('╔══════════════════════════════════════╗');
  print('║   OPERATION MIDNIGHT TUNA            ║');
  print('║   Classification: TOP SECRET         ║');
  print('║   Objective: World\'s Largest Tuna    ║');
  print('║   Client: Mr. Whiskers               ║');
  print('╚══════════════════════════════════════╝\n');

  // Service settings inject the budget config into BudgetTracker on resolve.
  final session = await runtime.createSession(
    settings: RuntimeSettings(
      services: {
        Pin('accounting', ['budget']): ServiceSettings(
          config: {'budget': 5000.0, 'spent': 0.0},
        ),
      },
    ),
  );
  final log = session.context.resolve<OperationLog>(
    const ServiceId('operation_log'),
  );
  final budget = session.context.resolve<BudgetTracker>(
    const ServiceId('budget'),
  );

  print('=== PHASE 1: READY CHECK ===\n');

  await session.emit(
    const HeistPhase(
      'ready_check',
      description: 'All departments report readiness.',
    ),
  );
  print('');

  final departments = [
    'command_center',
    'accounting',
    'infiltration',
    'distraction',
    'gary',
  ];
  for (final dept in departments) {
    final response = await session.request<ReadyCheck, ReadyResponse>(
      const ReadyCheck(),
      identifier: dept,
    );
    final status = response.ready ? 'READY' : 'NOT READY';
    print('  [$status] ${response.department}: ${response.note}');
  }

  print('\n=== PHASE 2: DEPLOYMENT ===\n');

  await session.emit(
    const HeistPhase('deployment', description: 'Teams move into position.'),
  );
  print('');

  // Identifier-scoped emits target only department-scoped handlers.
  await session.emit(
    DepartmentComm(
      from: 'Dr. Nefarious',
      message: 'Infiltration team: enter through the air vents.',
    ),
    identifier: 'infiltration',
  );

  await session.emit(
    DepartmentComm(
      from: 'Dr. Nefarious',
      message: 'Distraction team: Gary, go be yourself in the lobby.',
    ),
    identifier: 'distraction',
  );

  print('\n=== PHASE 3: EXECUTION ===\n');

  await session.emit(
    const HeistPhase(
      'execution',
      description: 'The vault is breached. The tuna is in sight.',
    ),
  );
  print('');

  // Emit on the session for the in-session log, then on the global bus so
  // Mr. Whiskers and any bind(...) observers see the same public event.
  await session.emit(
    const LootAcquired(
      "World's Largest Tuna (4.2 meters)",
      acquiredBy: 'Infiltration Team',
    ),
  );
  await runtime.globalBus.emit(
    event: const LootAcquired(
      "World's Largest Tuna (4.2 meters)",
      acquiredBy: 'Infiltration Team',
    ),
  );

  print('\n=== PHASE 4: EXTRACTION ===\n');

  await session.emit(
    const HeistPhase(
      'extraction',
      description: 'Get out with the tuna before anyone notices.',
    ),
  );
  print('');

  await session.emit(
    DepartmentComm(
      from: 'Infiltration',
      message: 'We have the tuna. Heading to extraction point.',
    ),
  );

  await session.emit(
    DepartmentComm(
      from: 'Gary',
      message: 'I also found a really nice stapler in the gift shop!',
    ),
  );

  print('\n=== PHASE 5: DEBRIEFING ===\n');

  await session.emit(
    const HeistPhase(
      'debriefing',
      description: 'Operation Midnight Tuna is complete.',
    ),
  );

  // Budget report
  print('\nBudget Report:');
  print('  ${budget.report()}');

  // Operation log
  print('\nFull Operation Log:');
  for (final entry in log.entries) {
    print('  $entry');
  }

  print('\n=== OPERATION COMPLETE ===\n');

  await runtime.dispose();

  print('Mr. Whiskers has his tuna.');
  print("Dr. Nefarious claims credit for the monologue.");
  print('Janet filed all 47 receipts.');
  print('Doug says the traps would have worked if anyone had asked.');
  print("Gary has a new stapler. He's already named it.");
  print('');
  print('THE END');
  print('(Until the sequel: Operation Midnight Tuna 2: The Tunaning)');
}
