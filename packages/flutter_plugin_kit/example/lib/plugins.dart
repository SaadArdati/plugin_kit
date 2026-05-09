import 'dart:async';

import 'package:plugin_kit/plugin_kit.dart';

/// Fired by [TickerService] every second while the session is alive.
class TickEvent {
  const TickEvent({required this.count, required this.at});
  final int count;
  final DateTime at;
}

/// Fired by the UI to ask the counter plugin to step its value.
class IncrementRequested {
  const IncrementRequested();
}

/// Fired by [CounterService] after every successful increment.
class CounterChanged {
  const CounterChanged(this.value);
  final int value;
}

/// Heartbeat service: emits a [TickEvent] every second while attached.
class TickerService extends SessionStatefulPluginService {
  Timer? _timer;
  int _count = 0;

  @override
  void attach() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _count++;
      emit(TickEvent(count: _count, at: DateTime.now()));
    });
  }

  @override
  Future<void> detach() async {
    _timer?.cancel();
  }
}

/// Owns the [TickerService] slot.
class TickerPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('flutter_plugin_kit.example.ticker');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerLazySingleton<TickerService>(
      const ServiceId('ticker_service'),
      () => TickerService(),
    );
  }
}

/// Holds the counter value, advances on every [IncrementRequested].
class CounterService extends SessionStatefulPluginService {
  int _value = 0;

  @override
  void attach() {
    on<IncrementRequested>((_) {
      _value++;
      emit(CounterChanged(_value));
    });
  }
}

/// Owns the [CounterService] slot.
class CounterPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('flutter_plugin_kit.example.counter');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerLazySingleton<CounterService>(
      const ServiceId('counter_service'),
      () => CounterService(),
    );
  }
}
