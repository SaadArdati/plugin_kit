/// # 14: Identifier Scoping
///
/// Handlers can be registered against an optional identifier. When an event
/// is emitted with that identifier, the bus merges general handlers and
/// identifier-scoped handlers in priority order. Handlers scoped to a
/// different identifier don't run.
///
/// Covers:
/// - `on<T>()` / `onRequest<Req, Res>()` with an `identifier`
/// - `emit(event, identifier: ...)` / `request(req, identifier: ...)`
/// - Merged dispatch: general handlers fire for every identifier; scoped
///   handlers only for their matching one
library;

import 'package:plugin_kit/plugin_kit.dart';

class DepartmentMemo {
  final String subject;
  final String body;
  final String from;
  const DepartmentMemo({
    required this.subject,
    required this.body,
    required this.from,
  });
}

class StatusRequest {
  final String question;
  const StatusRequest(this.question);
}

class StatusResponse {
  final String department;
  final String status;
  const StatusResponse({required this.department, required this.status});
}

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [LairMemoPlugin()])..init();
  final session = await runtime.createSession();

  print('=== Memo to Trap Department Only ===\n');

  // With an identifier, general handlers merge with scoped handlers in
  // priority order: Janet (general, 0), Doug (trap_dept, 5), Gary
  // (general, 99). Cafeteria and research handlers don't fire.
  await session.emit(
    const DepartmentMemo(
      subject: 'Hero spotted in Sector 7',
      body: 'Deploy all traps. Yes, even the paper clip one.',
      from: 'Dr. Nefarious',
    ),
    identifier: 'trap_dept',
  );

  print('\n=== Memo to Cafeteria Only ===\n');

  await session.emit(
    const DepartmentMemo(
      subject: 'Mr. Whiskers demands tuna',
      body: 'This is not negotiable.',
      from: 'Mr. Whiskers (via Dr. Nefarious)',
    ),
    identifier: 'cafeteria',
  );

  print('\n=== Memo to Everyone (no identifier) ===\n');

  // No identifier: only general handlers fire.
  await session.emit(
    const DepartmentMemo(
      subject: 'Annual Evil Picnic is Saturday',
      body: 'Bring your own diabolical dish to share.',
      from: 'HR (Janet)',
    ),
  );

  print('\n=== Department Status Checks ===\n');

  final trapStatus = await session.request<StatusRequest, StatusResponse>(
    const StatusRequest('Status report?'),
    identifier: 'trap_dept',
  );
  print('${trapStatus.department}: ${trapStatus.status}');

  final cafeStatus = await session.request<StatusRequest, StatusResponse>(
    const StatusRequest('Status report?'),
    identifier: 'cafeteria',
  );
  print('${cafeStatus.department}: ${cafeStatus.status}');

  final researchStatus = await session.request<StatusRequest, StatusResponse>(
    const StatusRequest('Status report?'),
    identifier: 'research',
  );
  print('${researchStatus.department}: ${researchStatus.status}');

  await runtime.dispose();

  print(
    '\nAll departments reported in. '
    'Gary is still reading his memo upside down.',
  );
}

/// Registers general memo observers plus per-department scoped observers
/// and scoped request handlers.
class LairMemoPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('lair_memo');

  @override
  void attach(SessionPluginContext context) {
    // General memo observers. Fire for every emit, regardless of identifier.
    context.bus.on<DepartmentMemo>((e) {
      print(
        '[General, Janet] Memo logged for tax purposes: '
        '"${e.event.subject}" from ${e.event.from}',
      );
    }, priority: 0);

    context.bus.on<DepartmentMemo>((_) {
      print('[General, Gary] Ooh, a memo! *reads upside down*');
    }, priority: 99);

    // Department-scoped memo observers. Only fire when the emit's identifier
    // matches.
    context.bus.on<DepartmentMemo>(
      (e) {
        print(
          '[trap_dept, Doug] Got it. Setting up traps in '
          'response to: "${e.event.subject}"',
        );
      },
      priority: 5,
      identifier: 'trap_dept',
    );

    context.bus.on<DepartmentMemo>(
      (e) {
        print(
          '[cafeteria, Chef] Acknowledged: "${e.event.subject}". '
          'Adjusting mystery meat accordingly.',
        );
      },
      priority: 5,
      identifier: 'cafeteria',
    );

    context.bus.on<DepartmentMemo>(
      (e) {
        print(
          '[research, Scientist] Fascinating: "${e.event.subject}". '
          'Will investigate between naps.',
        );
      },
      priority: 5,
      identifier: 'research',
    );

    // Scoped request handlers.
    context.bus.onRequest<StatusRequest, StatusResponse>((req) async {
      return const StatusResponse(
        department: 'Trap Department',
        status: 'Doug is untangling the laser grid. Gary walked through it.',
      );
    }, identifier: 'trap_dept');

    context.bus.onRequest<StatusRequest, StatusResponse>((req) async {
      return const StatusResponse(
        department: 'Cafeteria',
        status: 'Mystery meat is at temperature. Do not ask which temperature.',
      );
    }, identifier: 'cafeteria');

    context.bus.onRequest<StatusRequest, StatusResponse>((req) async {
      return const StatusResponse(
        department: 'Research',
        status:
            "Gary's teleporter prototype exploded. Again. Nap time resumed.",
      );
    }, identifier: 'research');
  }
}
