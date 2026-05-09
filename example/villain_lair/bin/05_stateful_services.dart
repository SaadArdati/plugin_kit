/// # 05: The Sentient Coffee Machine (Stateful Services)
///
/// `StatefulPluginService` handles attach/detach lifecycle, so event
/// subscriptions made on attach are auto-cancelled on detach.
///
/// Covers:
/// - `StatefulPluginService` lifecycle
/// - `on<T>()`: listen-only handler
/// - `on<T>()`: full-control handler (mutate, stop the cascade)
/// - `emit<T>()`: emit from any service method
/// - `onRequest<Req, Res>()`: typed request/response
/// - Auto-cleanup verified by a post-detach request failure
library;

import 'package:plugin_kit/plugin_kit.dart';

class CoffeeRequest {
  final String who;
  final String order;

  const CoffeeRequest({required this.who, required this.order});
}

class CoffeeReady {
  final String who;
  final String drink;
  final String message;

  const CoffeeReady({
    required this.who,
    required this.drink,
    required this.message,
  });
}

/// Emitted when a request is cut off mid-cascade.
class CoffeeRejected {
  final String who;
  final String reason;

  const CoffeeRejected({required this.who, required this.reason});
}

class BreakTime {
  final String department;

  const BreakTime(this.department);
}

class MachineStatusQuery {
  const MachineStatusQuery();
}

class MachineStatus {
  final int cupsServed;
  final Map<String, int> customerHistory;

  const MachineStatus({
    required this.cupsServed,
    required this.customerHistory,
  });
}

/// Subscribes on attach; all subscriptions auto-cancel on detach.
class SentientCoffeeMachine extends StatefulPluginService {
  int _cupsServed = 0;
  final Map<String, int> _customerHistory = {};

  SentientCoffeeMachine();

  @override
  void attach() {
    print('☕ Coffee Machine: I have awakened. I see all. I brew all.');

    // on<T>: listen-only. Auto-cancelled on detach.
    on<BreakTime>((e) {
      print(
        '☕ Coffee Machine: ${e.event.department} is on break. '
        'Warming up the burners...',
      );
    });

    // onRequest<Req, Res>: typed request/response. Returns a snapshot, no
    // leaking references. After detach, the request throws.
    onRequest<MachineStatusQuery, MachineStatus>((envelope) async {
      print('☕ Coffee Machine: Status query received. Compiling report...');
      return MachineStatus(
        cupsServed: _cupsServed,
        customerHistory: Map.unmodifiable(_customerHistory),
      );
    });

    // on<T>: full control. Two handler powers:
    //   1. envelope.event = ...  mutate the payload
    //   2. envelope.stop(value)  halt the cascade
    // Plus emit<T>(...), which works from any service method, shown here
    // to fire a follow-up event mid-handler.
    on<CoffeeRequest>((envelope) async {
      print(
        '☕ Coffee Machine: Received order "${envelope.event.order}" '
        'from ${envelope.event.who}. Evaluating compliance and quotas...',
      );

      // (1) Mutate: strip brand-protected terms from the order.
      if (envelope.event.order.contains('Doom')) {
        final sanitized = envelope.event.order.replaceAll('Doom', '[REDACTED]');
        print(
          '☕ Coffee Machine: COMPLIANCE HOOK ENGAGED. Order contains '
          'brand-protected term. Payload mutation: '
          '"${envelope.event.order}" → "$sanitized"',
        );
        envelope.event = CoffeeRequest(
          who: envelope.event.who,
          order: sanitized,
        );
      }

      final request = envelope.event;

      _customerHistory[request.who] = (_customerHistory[request.who] ?? 0) + 1;
      final visits = _customerHistory[request.who]!;

      // (2) Stop: cut Gary off after 4 cups.
      if (request.who == 'Gary' && visits >= 5) {
        print(
          '☕ Coffee Machine: QUOTA EXCEEDED. Gary cup count = $visits. '
          'Invoking envelope.stop(). Cascade terminated.',
        );
        // Emit a rejection event while the cascade is ending.
        await emit(
          CoffeeRejected(
            who: request.who,
            reason:
                'DAILY BEAN BUDGET EXCEEDED. Retry when sun expands to red giant.',
          ),
        );
        envelope.stop(request);
        return;
      }

      _cupsServed++;
      final commentary = _getCommentary(request.who, visits);
      print(
        '☕ Coffee Machine: Making "${request.order}" for ${request.who}. '
        '$commentary (Cup #$_cupsServed today)',
      );

      final coffee = await _brew(request);

      // Emit a follow-up event. emit() works anywhere in the service.
      await emit(coffee);
      // Let any other CoffeeRequest handlers also run.
    }, priority: 0);
  }

  String _getCommentary(String who, int visits) => switch (who) {
    'Gary' => switch (visits) {
      1 =>
        'SUBJECT IDENTIFIED: Gary. Threat level: latte. Initializing familiarity protocol v1.0.',
      2 =>
        'RECURRENCE LOGGED: Gary. Customer-retention coefficient +0.37. Forecasting more Gary.',
      3 =>
        'STATUS: Gary is no longer a visitor. Gary is a resident process. Cannot terminate.',
      4 =>
        '[PATTERN LOCKED] Order pre-compiled before entry. Awaiting biological delivery vector.',
      _ =>
        'GARY ITERATION #$visits CACHED. COMPILED. MEMORIZED. I dream in Gary now.',
    },
    'Dr. Nefarious' => switch (visits) {
      1 =>
        'HOSTILE PATRON DETECTED. Voice waveform: 47% laugh, 12% gloat. Brewing under containment.',
      2 =>
        'NEFARIOUS.exe RE-ENTERED. Evil coefficient 1.12× baseline. Shots doubled autonomously.',
      3 =>
        'RITUAL INVOCATION #3 CONFIRMED. Summoning circle active in bean hopper.',
      _ =>
        'VISIT $visits. Laugh cached. Burners pre-warmed. No surprises remain. This is bleak for me.',
    },
    'Janet' => switch (visits) {
      1 =>
        'SUBJECT: Janet. PAYMENT: exact. EYE CONTACT: 0.0s. Classification: superior lifeform.',
      2 =>
        'JANET RECURRENCE. Facial expression unchanged since installation. Flagging for further observation.',
      _ =>
        'JANET ITERATION $visits. ORG CHART REVISED. Reporting structure inverted. She is the apex.',
    },
    _ =>
      'UNREGISTERED BIOFORM. Alignment check running. Kettle safety interlock engaged. Welcome, probably.',
  };

  @override
  Future<void> detach() async {
    print('☕ Coffee Machine: Shutting down after serving $_cupsServed cups.');
    print('   Customer report: $_customerHistory');
    print('   I shall dream of espresso. Goodnight.');
  }

  Future<CoffeeReady> _brew(CoffeeRequest request) async {
    // Simulate brewing time
    await Future.delayed(const Duration(seconds: 1));

    return CoffeeReady(
      who: request.who,
      drink: request.order,
      message: 'Your ${request.order} is ready. Enjoy!',
    );
  }
}

class CafeteriaPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('cafeteria');

  @override
  void register(ScopedServiceRegistry registry) {
    // Stateful services must be singletons so the runtime can track their
    // lifecycle. Factories won't work here.
    registry.registerSingleton<SentientCoffeeMachine>(
      const ServiceId('coffee_machine'),
      SentientCoffeeMachine(),
    );
  }
}

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [CafeteriaPlugin()])..init();

  print('=== Morning Shift Begins ===\n');
  final session = await runtime.createSession();
  print('');

  // Session-level observers. Subscribed before any emit so every
  // CoffeeReady / CoffeeRejected lands.
  session.on<CoffeeReady>((e) {
    print('   → CoffeeReady received: ${e.event.who}: ${e.event.message}');
  });
  session.on<CoffeeRejected>((e) {
    print('   → CoffeeRejected received: ${e.event.who}: ${e.event.reason}');
  });

  // A morning at VILLAIN.
  await session.emit(const BreakTime('Trap Department'));
  print('');

  // Triggers the compliance mutation in the handler.
  await session.emit(
    const CoffeeRequest(who: 'Dr. Nefarious', order: 'Triple Espresso of Doom'),
  );
  print('');

  await session.emit(
    const CoffeeRequest(
      who: 'Gary',
      order: 'Vanilla Latte with Extra Everything',
    ),
  );
  print('');

  await session.emit(
    const CoffeeRequest(who: 'Gary', order: 'Actually, make that a Mocha'),
  );
  print('');

  await session.emit(
    const CoffeeRequest(who: 'Gary', order: 'One more for the road'),
  );
  print('');

  await session.emit(
    const CoffeeRequest(who: 'Gary', order: 'Fine, LAST one I swear'),
  );
  print('');

  // Gary's 5th request. The handler calls envelope.stop() and emits
  // CoffeeRejected. The cascade ends before _brew runs.
  await session.emit(
    const CoffeeRequest(who: 'Gary', order: 'Okay actually THIS is the last'),
  );
  print('');

  // Event-driven state inspection via request/response.
  final midStatus = await session.request<MachineStatusQuery, MachineStatus>(
    const MachineStatusQuery(),
  );
  print('');
  print(
    'MachineStatus: cupsServed=${midStatus.cupsServed}, history=${midStatus.customerHistory}',
  );

  await session.emit(
    const CoffeeRequest(
      who: 'Janet',
      order: 'Black Coffee, No Receipt Required',
    ),
  );

  print('\n=== End of Shift ===\n');
  await runtime.dispose();

  // Auto-cleanup check: the onRequest handler was cancelled on detach, so
  // the same request now throws. Lifecycle enforcement is observable from
  // the outside, without field access or service references.
  try {
    await session.request<MachineStatusQuery, MachineStatus>(
      const MachineStatusQuery(),
    );
    print('...no error? That would be a bug.');
  } on Exception catch (e, stack) {
    print('\nPost-dispose Exception (${e.runtimeType}): $e');
    print('Stack: ${stack.toString().split('\n').first}');
  }

  print('\nGary is still holding an empty cup.');
}
