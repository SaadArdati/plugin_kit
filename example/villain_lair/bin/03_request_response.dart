/// # 03: Evil Supply Requisitions (Request/Response)
///
/// Request/response sends a typed query and waits for a typed answer.
///
/// Covers:
/// - `onRequest<Req, Res>()` / `request<Req, Res>()`: async pair
/// - `onRequestSync` / `requestSync`: sync pair
/// - `maybeRequest`: nullable fallback when no handler is registered
/// - Priority cascading in request handlers
library;

import 'package:plugin_kit/plugin_kit.dart';

class SupplyRequest {
  final String item;
  final int quantity;
  final String requestedBy;

  const SupplyRequest(this.item, this.quantity, {required this.requestedBy});
}

class SupplyResponse {
  final bool approved;
  final String message;

  const SupplyResponse({required this.approved, required this.message});
}

/// Quick inventory check. Synchronous since lookups are instant.
class InventoryCheck {
  final String item;

  const InventoryCheck(this.item);
}

class StockLevel {
  final String item;
  final int count;

  const StockLevel(this.item, this.count);
}

/// A request with no handler. Used to show `maybeRequest` returning null.
class UnicornRequest {
  const UnicornRequest();
}

/// Registers three request handlers: Janet's async review, the sync stock
/// room, and a VIP lane keyed on a nullable response type.
class ProcurementPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('procurement');

  @override
  void attach(SessionPluginContext context) {
    // Janet's handler: async, non-nullable SupplyResponse.
    context.bus.onRequest<SupplyRequest, SupplyResponse>((req) async {
      final request = req.event;

      if (request.item.toLowerCase().contains('death ray')) {
        return const SupplyResponse(
          approved: false,
          message:
              'Denied. We already have three death rays. '
              'And Gary keeps using them to reheat lunch.',
        );
      }

      if (request.quantity > 1000) {
        return const SupplyResponse(
          approved: false,
          message:
              'Denied. Nobody needs 1000 of anything. '
              "Except maybe Gary's staplers.",
        );
      }

      return SupplyResponse(
        approved: true,
        message:
            'Approved: ${request.quantity}x ${request.item} '
            'for ${request.requestedBy}. Receipt filed.',
      );
    });

    // Stock room: synchronous inventory lookup.
    context.bus.onRequestSync<InventoryCheck, StockLevel>((req) {
      const inventory = <String, int>{
        'capes': 12,
        'death rays': 3,
        'staplers': 0, // Gary took them all
        'cat food': 500, // Mr. Whiskers gets priority
      };

      final item = req.event.item.toLowerCase();
      final count = inventory[item] ?? 0;
      return StockLevel(req.event.item, count);
    });

    // Dr. Nefarious's VIP lane. Keyed on (SupplyRequest, SupplyResponse?),
    // a different bucket from Janet's (SupplyRequest, SupplyResponse).
    // Requests issued against the nullable type land here; non-VIP requests
    // fall through to null.
    context.bus.onRequest<SupplyRequest, SupplyResponse?>((req) async {
      if (req.event.requestedBy == 'Dr. Nefarious') {
        return SupplyResponse(
          approved: true,
          message:
              'Auto-approved. Dr. Nefarious gets what Dr. Nefarious wants. '
              '(${req.event.quantity}x ${req.event.item})',
        );
      }
      return null; // No downstream handler; caller gets null.
    }, priority: 0);
  }
}

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [ProcurementPlugin()])..init();
  final session = await runtime.createSession();

  print('=== Supply Requisitions ===\n');

  final capeRequest = await session.request<SupplyRequest, SupplyResponse>(
    const SupplyRequest(
      'Villain Capes (Medium)',
      5,
      requestedBy: 'Dr. Nefarious',
    ),
  );
  print('Cape request: ${capeRequest.message}');

  final rayRequest = await session.request<SupplyRequest, SupplyResponse>(
    const SupplyRequest('Death Ray Mk IV', 1, requestedBy: 'Doug'),
  );
  print('Death ray request: ${rayRequest.message}');

  final staplerRequest = await session.request<SupplyRequest, SupplyResponse>(
    const SupplyRequest('Staplers', 1001, requestedBy: 'Gary'),
  );
  print('Stapler request: ${staplerRequest.message}');

  print('\n=== Inventory Checks ===\n');

  final capeStock = session.requestSync<InventoryCheck, StockLevel>(
    const InventoryCheck('Capes'),
  );
  print('Capes in stock: ${capeStock.count}');

  final staplerStock = session.requestSync<InventoryCheck, StockLevel>(
    const InventoryCheck('Staplers'),
  );
  print('Staplers in stock: ${staplerStock.count} (Gary...)');

  final catFood = session.requestSync<InventoryCheck, StockLevel>(
    const InventoryCheck('Cat Food'),
  );
  print('Cat food in stock: ${catFood.count} (Mr. Whiskers approves)');

  print('\n=== Unhandled Requests ===\n');

  final unicornResponse = await session.maybeRequest<UnicornRequest, String>(
    const UnicornRequest(),
  );
  if (unicornResponse == null) {
    print(
      'Unicorn request: No handler found. '
      "Gary's suggestion to start a unicorn division was denied.",
    );
  }

  print('\n=== Priority Cascade ===\n');

  final vipRequest = await session.request<SupplyRequest, SupplyResponse?>(
    const SupplyRequest('Death Ray Mk V', 1, requestedBy: 'Dr. Nefarious'),
  );
  print('VIP request: ${vipRequest?.message}');

  final garyRequest = await session.request<SupplyRequest, SupplyResponse?>(
    const SupplyRequest('Stapler (gold-plated)', 1, requestedBy: 'Gary'),
  );
  print("Gary's request: ${garyRequest?.message}");

  await runtime.dispose();
  print('\nProcurement office closed. Janet is archiving receipts.');
}
