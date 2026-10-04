import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

import '../../../app/app_scope.dart';
import '../../shared/models/driver_order.dart';

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  DriverOrder? _order;
  StreamSubscription<bool>? _alertSubscription;
  bool _isListeningToAlert = false;
  bool _loading = true;
  bool _processing = false;
  bool _alertProcessing = false;
  bool? _lastKnownAlert;
  String? _error;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadOrder();
      }
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _alertSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isListeningToAlert) {
      return;
    }

    _isListeningToAlert = true;
    _listenToAlertChanges();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final order = await AppScope.of(context).repository.fetchOrderById(
        widget.orderId,
      );
      if (mounted) {
        setState(() {
          _order = order;
          _lastKnownAlert ??= order.alert;
        });

        if (!order.isReadyForDriverScreen()) {
          final remaining = order.remainingMpesaDelay();
          _delayTimer?.cancel();
          _delayTimer = Timer(remaining + const Duration(milliseconds: 200), () {
            if (mounted) {
              setState(() {});
            }
          });
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _order = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _listenToAlertChanges() {
    _alertSubscription = AppScope.of(context)
        .repository
        .watchOrderAlert(widget.orderId)
        .listen((alert) {
          if (!mounted) {
            return;
          }

          final previousAlert = _lastKnownAlert;
          _lastKnownAlert = alert;

          setState(() {
            final order = _order;
            if (order != null) {
              _order = order.copyWith(alert: alert);
            }
          });

          if (previousAlert == true && alert == false) {
            _showMessage('The customer is on their way.');
          }
        });
  }

  Future<void> _updateStatus(String status) async {
    final order = _order;
    if (order == null || _processing) {
      return;
    }

    setState(() => _processing = true);

    try {
      await AppScope.of(context).repository.updateOrderStatus(
        orderId: order.id,
        status: status,
      );
      if (mounted) {
        setState(() => _order = order.copyWith(status: status));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order marked ${status.replaceAll('_', ' ')}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _setCustomerAlert() async {
    final order = _order;
    if (order == null || _alertProcessing || order.alert) {
      return;
    }

    setState(() => _alertProcessing = true);

    try {
      await AppScope.of(context).repository.updateOrderAlert(
        orderId: order.id,
        alert: true,
      );
      if (mounted) {
        setState(() {
          _order = order.copyWith(alert: true);
          _lastKnownAlert = true;
        });
        _showMessage('Customer alert sent.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _alertProcessing = false);
      }
    }
  }

  Future<void> _openMaps() async {
    final order = _order;
    if (order == null) {
      return;
    }

    final Uri uri;
    if (order.deliveryLat != null && order.deliveryLng != null) {
      uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${order.deliveryLat},${order.deliveryLng}',
      );
    } else if (order.deliveryAddress != null &&
        order.deliveryAddress!.trim().isNotEmpty) {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(order.deliveryAddress!)}',
      );
    } else {
      _showMessage('No delivery location is available for this order.');
      return;
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showMessage('Unable to open maps on this device.');
    }
  }

  Future<void> _callCustomer() async {
    final phone = _order?.customerPhone;
    if (phone == null || phone.trim().isEmpty) {
      _showMessage('No customer phone number is available.');
      return;
    }

    final uri = Uri.parse('tel:$phone');
    if (!await launchUrl(uri)) {
      _showMessage('Unable to start a phone call on this device.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = _order;
    final orderReference =
        order?.orderNumber?.trim().isNotEmpty == true
        ? order!.orderNumber!
        : order?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          orderReference == null
              ? 'Order details'
              : 'Order #$orderReference',
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null || order == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error ?? 'Order not found.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 18),
                          ElevatedButton(
                            onPressed: _loadOrder,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Builder(
                    builder: (context) {
                      final isReady = order.isReadyForDriverScreen();
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
                        children: [
                          if (!isReady) ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.hourglass_top_rounded,
                                      color: Color(0xFFD97706)),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'This M-Pesa order is waiting for its 2-minute confirmation buffer before driver actions become available.',
                                      style: TextStyle(
                                        color: Color(0xFF92400E),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                order.restaurantName ?? 'Restaurant',
                                style: theme.textTheme.headlineMedium,
                              ),
                              _StatusPill(status: order.status),
                            ],
                          ),
                      const SizedBox(height: 8),
                      if (orderReference != null)
                        Text(
                          'Pickup reference: Order #$orderReference',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: const Color(0xFF4B5563),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (orderReference != null) const SizedBox(height: 8),
                      Text(
                        order.customerName ?? 'Customer',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 18),
                      _InfoCard(
                        title: 'Delivery',
                        children: [
                          _InfoRow(
                            label: 'Address',
                            value: order.deliveryAddress ?? '-',
                          ),
                          _InfoRow(
                            label: 'Customer',
                            value: order.customerName ?? '-',
                          ),
                          if ((order.allergyNote ?? '').isNotEmpty)
                            _InfoRow(
                              label: 'Allergy note',
                              value: order.allergyNote!,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _InfoCard(
                        title: 'Items',
                        children: [
                          ...order.items.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: const Color(0xFFD8F3EE),
                                    child: Text(
                                      '${item.qty ?? 1}x',
                                      style: const TextStyle(
                                        color: Color(0xFF0F766E),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        if ((item.orderType ?? '').isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(item.orderType!),
                                          ),
                                        if ((item.notes ?? '').isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              item.notes!,
                                              style: theme.textTheme.bodyMedium,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _openMaps,
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('Open maps'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (order.customerPhone ?? '').trim().isEmpty
                                  ? null
                                  : _callCustomer,
                              icon: const Icon(Icons.call_outlined),
                              label: const Text('Call customer'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed:
                              _alertProcessing ||
                                  order.status == 'delivered' ||
                                  order.alert
                              ? null
                              : _setCustomerAlert,
                          icon: _alertProcessing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.notifications_active_outlined),
                          label: Text(
                            order.alert
                                ? 'Customer alert sent'
                                : 'Alert customer',
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed:
                            _processing || order.status == 'picked_up' || !isReady
                                ? null
                                : () => _updateStatus('picked_up'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1D4ED8),
                        ),
                        child: _processing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Mark picked up'),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed:
                            _processing || order.status == 'delivered' || !isReady
                                ? null
                                : () => _updateStatus('delivered'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF047857),
                        ),
                        child: const Text('Mark delivered'),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'accepted' => const Color(0xFF7C3AED),
      'picked_up' => const Color(0xFF2563EB),
      'delivered' => const Color(0xFF047857),
      _ => const Color(0xFF6B7280),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
