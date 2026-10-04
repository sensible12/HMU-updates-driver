import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';

import '../../../app/app_scope.dart';
import '../../shared/models/driver_order.dart';
import '../widgets/order_card.dart';

class OrdersHomeScreen extends StatefulWidget {
  const OrdersHomeScreen({super.key});

  @override
  State<OrdersHomeScreen> createState() => _OrdersHomeScreenState();
}

class _OrdersHomeScreenState extends State<OrdersHomeScreen> {
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<DriverOrder> _orders = const [];
  StreamSubscription<void>? _ordersSubscription;
  Timer? _delayedOrdersTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _primeOrders();
      }
    });
  }

  @override
  void dispose() {
    _delayedOrdersTimer?.cancel();
    _ordersSubscription?.cancel();
    super.dispose();
  }

  void _scheduleDelayedOrdersTimer() {
    _delayedOrdersTimer?.cancel();
    _delayedOrdersTimer = null;

    final unreadyOrders =
        _orders.where((order) => !order.isReadyForDriverScreen());
    if (unreadyOrders.isEmpty) {
      return;
    }

    Duration? minRemaining;
    for (final order in unreadyOrders) {
      final remaining = order.remainingMpesaDelay();
      if (minRemaining == null || remaining < minRemaining) {
        minRemaining = remaining;
      }
    }

    if (minRemaining != null) {
      final delay = minRemaining + const Duration(milliseconds: 200);
      _delayedOrdersTimer = Timer(delay, () {
        if (mounted) {
          setState(() {});
          _scheduleDelayedOrdersTimer();
        }
      });
    }
  }

  Future<void> _primeOrders() async {
    final repository = AppScope.of(context).repository;
    final cachedOrders = await repository.getCachedAcceptedOrders();
    if (mounted && cachedOrders.isNotEmpty) {
      setState(() {
        _orders = cachedOrders;
        _loading = false;
      });
      _scheduleDelayedOrdersTimer();
    }

    _ordersSubscription ??=
        repository.watchAcceptedOrderChanges().listen((_) {
          if (mounted) {
            _loadOrders();
          }
        });

    await _loadOrders();
  }

  Future<void> _loadOrders({bool pullToRefresh = false}) async {
    final repository = AppScope.of(context).repository;

    if (pullToRefresh) {
      setState(() => _refreshing = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final orders = await repository.fetchAcceptedOrders();
      if (mounted) {
        setState(() {
          _orders = orders;
          _error = null;
        });
        _scheduleDelayedOrdersTimer();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _orders = const [];
        });
        _scheduleDelayedOrdersTimer();
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _openOrder(DriverOrder order) async {
    await context.push('/order/${order.id}');
    if (mounted) {
      await _loadOrders();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    final visibleOrders =
        _orders.where((order) => order.isReadyForDriverScreen()).toList();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF1FFF9), Color(0xFFF7F7F7)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => _loadOrders(pullToRefresh: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your delivery orders',
                            style: theme.textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Track available orders, claim pickups, and complete active deliveries.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => context.push('/profile'),
                      icon: const Icon(Icons.person_outline_rounded),
                    ),
                  ],
                ),
                if (scope.repository.isDemoMode) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Text(
                      'This app is running with sample driver data. Real Supabase sync turns on when you provide a public anon key.',
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _StateMessage(
                    title: 'Unable to load orders',
                    message: _error!,
                    actionLabel: 'Retry',
                    onPressed: _loadOrders,
                  )
                else if (visibleOrders.isEmpty)
                  _StateMessage(
                    title: 'No accepted orders',
                    message:
                        'No available or active delivery orders right now.',
                    actionLabel: 'Refresh',
                    onPressed: _loadOrders,
                  )
                else
                  ...visibleOrders.map(
                    (order) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: OrderCard(
                        order: order,
                        onTap: () => _openOrder(order),
                      ),
                    ),
                  ),
                if (_refreshing)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: onPressed,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
