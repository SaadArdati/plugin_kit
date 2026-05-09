/// # 02: The Lair Intercom (Event Bus Basics)
///
/// Emit events on a session bus; subscribe from a plugin via the
/// auto-tracking helpers; cancel a subscription in response to another
/// event.
///
/// Covers:
/// - `session.emit<T>()`: fire an event on the session bus
/// - `on<T>()`: register an observer (auto-cancelled on detach)
/// - `bind()`: type-agnostic debug tap (also auto-cancelled on detach)
/// - Cancelling a subscription through an event (no plugin fields)
///
/// Pedagogical caveat: this file puts every handler directly on the plugin
/// to keep the bus mechanics visible without a service detour. In a real
/// plugin, behavior of this size belongs in a `StatefulPluginService` so it
/// can be overridden, prioritized, or settings-tuned through the registry.
/// Plugin-level subscriptions are an escape hatch for trivial wiring; they
/// trade away the composition mechanics that services get for free.
library;

import 'package:plugin_kit/plugin_kit.dart';

class LairAnnouncement {
  final String message;
  final String from;

  const LairAnnouncement(this.message, {this.from = 'Dr. Nefarious'});

  @override
  String toString() => '[$from]: $message';
}

class LunchMenuEvent {
  final String todaysSpecial;

  const LunchMenuEvent(this.todaysSpecial);
}

class SecurityAlert {
  final String description;
  final int severity; // 1 = Gary left the door open, 10 = hero infiltration
  const SecurityAlert(this.description, {this.severity = 1});
}

/// Fired when Gary puts his headphones on. The plugin responds by cancelling
/// his announcement subscription. State flows through events, not fields.
class PutOnHeadphones {
  const PutOnHeadphones();
}

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [LairIntercomPlugin()])..init();
  final session = await runtime.createSession();

  print('=== Morning Announcements ===');
  await session.emit(
    const LairAnnouncement(
      'Remember: the death ray is NOT a microwave. '
      'Stop reheating your burritos in it.',
    ),
  );

  print('\n=== Lunch Time ===');
  await session.emit(const LunchMenuEvent('Mystery Meat Surprise (again)'));

  print('\n=== Security ===');
  await session.emit(
    const SecurityAlert('Gary left the front door open. Again.', severity: 1),
  );

  // No handler subscribed to SecurityAlert. The bind() debug observer
  // still sees it.

  print('\n=== Gary Gets Noise-Cancelling Headphones ===');
  // Emit an event. The plugin cancels Gary's subscription in response.
  await session.emit(const PutOnHeadphones());
  await session.emit(const LairAnnouncement('Has anyone seen Gary?'));

  await runtime.dispose();
  print('\nIntercom shut down. The silence is deafening.');
}

/// Subscribes at attach. The session cancels all handlers at dispose.
/// No plugin fields; any runtime state lives in closures captured by the
/// subscriptions themselves.
class LairIntercomPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('lair_intercom');

  @override
  void attach(SessionPluginContext context) {
    // The on/bind helpers from PluginHelper auto-track every subscription
    // they create. detach() cancels them all; nothing has to live in a
    // field unless you want to cancel one early (see Gary's case below).

    // Observer: departmental reaction to announcements.
    on<LairAnnouncement>(context, (e) {
      print('📢 Heard announcement: ${e.event}');
    });

    // Multiple observers can subscribe to the same event type.
    on<LunchMenuEvent>(context, (e) {
      print(
        '🍽️  Gary: "${e.event.todaysSpecial}"? I hope it\'s not the '
        'mystery meat again.',
      );
    });
    on<LunchMenuEvent>(context, (_) {
      print('🍽️  Janet: I need the receipt for the mystery meat. For taxes.');
    });
    on<LunchMenuEvent>(context, (_) {
      print('🍽️  Dr. Nefarious: I shall have my lunch... OF EVIL.');
    });

    // Gary's announcement listener. on() returns the StreamSubscription so
    // a peer handler can cancel it before detach. The subscription is also
    // tracked, so detach() would cancel it anyway if no one canceled early.
    final garyListener = on<LairAnnouncement>(context, (_) {
      print('🎧 Gary heard that one.');
    });

    // Cancel Gary's listener when an event says he put his headphones on.
    // All state flows through events; nothing is exposed as a field.
    on<PutOnHeadphones>(context, (_) async {
      print(
        '🎧 Gary slides on his headphones. Announcements stop reaching him.',
      );
      await garyListener.cancel();
    });

    // bind(): type-agnostic passive observer. Fires before any on handlers
    // and is auto-removed on detach just like the on() subscriptions.
    bind(context, (e) {
      print('  [debug] Event observed: ${e.event.runtimeType}');
    });
  }
}
