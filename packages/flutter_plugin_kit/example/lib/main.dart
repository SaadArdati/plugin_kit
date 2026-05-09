import 'package:flutter/material.dart';
import 'package:flutter_plugin_kit/flutter_plugin_kit.dart';
import 'package:plugin_kit/plugin_kit.dart';

import 'plugins.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_plugin_kit example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: PluginRuntimeScope(
        plugins: [TickerPlugin(), CounterPlugin()],
        child: const PluginSessionScope(child: ExampleHome()),
      ),
    );
  }
}

class ExampleHome extends StatelessWidget {
  const ExampleHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_plugin_kit example')),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClockCard(),
              SizedBox(height: 12),
              CounterCard(),
              SizedBox(height: 12),
              HistoryCard(),
              SizedBox(height: 12),
              NotifierCard(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Path 1: `BuildContext.watchEvent<E>()`. Smallest call site for a
/// "rebuild on every E" widget.
class ClockCard extends StatelessWidget {
  const ClockCard({super.key});

  @override
  Widget build(BuildContext context) {
    final tick = context.watchEvent<TickEvent>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'context.watchEvent<TickEvent>()',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              tick == null
                  ? 'waiting for first tick…'
                  : 'tick #${tick.count} at ${_formatTime(tick.at)}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

/// Path 2: `emit` for user intents, `watchEvent` for the resulting state.
/// The plugin owns the value; the UI owns the action and the rebuild.
class CounterCard extends StatelessWidget {
  const CounterCard({super.key});

  @override
  Widget build(BuildContext context) {
    final counter = context.watchEvent<CounterChanged>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'session.emit + context.watchEvent<CounterChanged>()',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'count: ${counter?.value ?? 0}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                PluginSessionScope.of(context).emit(const IncrementRequested());
              },
              child: const Text('+1'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Path 3: `PluginSessionStateListener` mixin. Useful when the widget
/// needs to keep derived state alongside event handling.
class HistoryCard extends StatefulWidget {
  const HistoryCard({super.key});

  @override
  State<HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<HistoryCard>
    with PluginSessionStateListener<HistoryCard> {
  final List<int> _ticks = [];

  @override
  void initState() {
    super.initState();
    listen<TickEvent>((event) {
      setState(() {
        _ticks.add(event.count);
        if (_ticks.length > 5) _ticks.removeAt(0);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PluginSessionStateListener<HistoryCard>.listen<TickEvent>',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _ticks.isEmpty
                  ? 'no ticks yet'
                  : 'last 5 ticks: ${_ticks.join(', ')}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

/// Path 4: `PluginEventNotifier<E>` through a `ValueListenableBuilder`.
/// Same shape that drops into `ChangeNotifierProvider`,
/// `ValueListenableProvider`, or any other Listenable consumer.
class NotifierCard extends StatefulWidget {
  const NotifierCard({super.key});

  @override
  State<NotifierCard> createState() => _NotifierCardState();
}

class _NotifierCardState extends State<NotifierCard> {
  PluginEventNotifier<TickEvent>? _notifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notifier ??= PluginEventNotifier<TickEvent>(
      PluginSessionScope.of(context),
    );
  }

  @override
  void dispose() {
    _notifier?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = _notifier;
    if (notifier == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PluginEventNotifier<TickEvent> via ValueListenableBuilder',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<TickEvent?>(
              valueListenable: notifier,
              builder: (context, tick, _) => Text(
                tick == null
                    ? 'no tick yet'
                    : 'count: ${tick.count} (Listenable-friendly)',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
