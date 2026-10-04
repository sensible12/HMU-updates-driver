import 'package:flutter_test/flutter_test.dart';
import 'package:hmu_driver/src/features/shared/models/driver_order.dart';

void main() {
  group('DriverOrder restaurant-configured delay tests', () {
    final now = DateTime.utc(2026, 9, 4, 12, 0, 0);

    test('order without mpesaTransactionId is ready immediately', () {
      final order = DriverOrder(
        id: 'ord-1',
        status: 'accepted',
        items: const [],
        createdAt: now.toIso8601String(),
      );

      expect(order.hasMpesaTransaction, isFalse);
      expect(order.isReadyForDriverScreen(now: now), isTrue);
      expect(order.remainingMpesaDelay(now: now), Duration.zero);
    });

    test('order with empty mpesaTransactionId is ready immediately', () {
      final order = DriverOrder(
        id: 'ord-2',
        status: 'accepted',
        items: const [],
        mpesaTransactionId: '   ',
        createdAt: now.toIso8601String(),
      );

      expect(order.hasMpesaTransaction, isFalse);
      expect(order.isReadyForDriverScreen(now: now), isTrue);
      expect(order.remainingMpesaDelay(now: now), Duration.zero);
    });

    test('order with mpesaTransactionId created 30s ago is NOT ready', () {
      final createdAt = now.subtract(const Duration(seconds: 30));
      final order = DriverOrder(
        id: 'ord-3',
        status: 'accepted',
        items: const [],
        mpesaTransactionId: 'MP123456',
        createdAt: createdAt.toIso8601String(),
      );

      expect(order.hasMpesaTransaction, isTrue);
      expect(order.isReadyForDriverScreen(now: now), isFalse);
      expect(
        order.remainingMpesaDelay(now: now),
        const Duration(minutes: 9, seconds: 30),
      );
    });

    test('order with mpesaTransactionId created 1m 59s ago is NOT ready', () {
      final createdAt = now.subtract(const Duration(minutes: 1, seconds: 59));
      final order = DriverOrder(
        id: 'ord-4',
        status: 'accepted',
        items: const [],
        mpesaTransactionId: 'MP123456',
        createdAt: createdAt.toIso8601String(),
      );

      expect(order.isReadyForDriverScreen(now: now), isFalse);
      expect(
        order.remainingMpesaDelay(now: now),
        const Duration(minutes: 8, seconds: 1),
      );
    });

    test(
      'order with mpesaTransactionId created exactly 2 mins ago is NOT ready',
      () {
        final createdAt = now.subtract(const Duration(minutes: 2));
        final order = DriverOrder(
          id: 'ord-5',
          status: 'accepted',
          items: const [],
          mpesaTransactionId: 'MP123456',
          createdAt: createdAt.toIso8601String(),
        );

        expect(order.isReadyForDriverScreen(now: now), isFalse);
        expect(order.remainingMpesaDelay(now: now), const Duration(minutes: 8));
      },
    );

    test('order with mpesaTransactionId created 10 mins ago IS ready', () {
      final createdAt = now.subtract(const Duration(minutes: 10));
      final order = DriverOrder(
        id: 'ord-6',
        status: 'accepted',
        items: const [],
        mpesaTransactionId: 'MP123456',
        createdAt: createdAt.toIso8601String(),
      );

      expect(order.isReadyForDriverScreen(now: now), isTrue);
      expect(order.remainingMpesaDelay(now: now), Duration.zero);
    });

    test('restaurant can configure a five-minute delay', () {
      final createdAt = now.subtract(const Duration(minutes: 4));
      final order = DriverOrder(
        id: 'ord-7',
        status: 'accepted',
        items: const [],
        mpesaTransactionId: 'MP123456',
        createdAt: createdAt.toIso8601String(),
        restaurantOrderDelayMinutes: 5,
      );

      expect(order.isReadyForDriverScreen(now: now), isFalse);
      expect(order.remainingMpesaDelay(now: now), const Duration(minutes: 1));
    });
  });
}
