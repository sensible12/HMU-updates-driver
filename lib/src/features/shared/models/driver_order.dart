class OrderItem {
  const OrderItem({
    required this.name,
    this.qty,
    this.notes,
    this.price,
    this.orderType,
  });

  final String name;
  final int? qty;
  final String? notes;
  final double? price;
  final String? orderType;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'qty': qty,
      'notes': notes,
      'price': price,
      'orderType': orderType,
    };
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      name: json['name'] as String? ?? 'Item',
      qty: (json['qty'] as num?)?.toInt(),
      notes: json['notes'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      orderType: json['orderType'] as String?,
    );
  }
}

class DriverOrder {
  const DriverOrder({
    required this.id,
    required this.status,
    required this.items,
    this.alert = false,
    this.orderNumber,
    this.allergyNote,
    this.deliveryAddress,
    this.driverId,
    this.deliveryLat,
    this.deliveryLng,
    this.customerId,
    this.restaurantId,
    this.subtotalCents,
    this.deliveryFeeCents,
    this.totalCents,
    this.paymentIntentId,
    this.createdAt,
    this.mpesaTransactionId,
    this.payout,
    this.etaMinutes,
    this.restaurantName,
    this.restaurantOrderDelayMinutes = 10,
    this.customerName,
    this.customerPhone,
  });

  final String id;
  final String status;
  final bool alert;
  final String? orderNumber;
  final String? allergyNote;
  final String? deliveryAddress;
  final String? driverId;
  final double? deliveryLat;
  final double? deliveryLng;
  final String? customerId;
  final String? restaurantId;
  final List<OrderItem> items;
  final int? subtotalCents;
  final int? deliveryFeeCents;
  final int? totalCents;
  final String? paymentIntentId;
  final String? createdAt;
  final String? mpesaTransactionId;
  final String? payout;
  final int? etaMinutes;
  final String? restaurantName;
  final int restaurantOrderDelayMinutes;
  final String? customerName;
  final String? customerPhone;

  bool get hasMpesaTransaction =>
      mpesaTransactionId != null && mpesaTransactionId!.trim().isNotEmpty;

  DateTime? get createdAtDateTime {
    if (createdAt == null || createdAt!.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(createdAt!)?.toUtc();
  }

  bool isReadyForDriverScreen({DateTime? now, Duration? delay}) {
    if (!hasMpesaTransaction) {
      return true;
    }
    final created = createdAtDateTime;
    if (created == null) {
      return true;
    }
    final currentTime = (now ?? DateTime.now()).toUtc();
    return currentTime.difference(created) >= _effectiveDelay(delay);
  }

  Duration remainingMpesaDelay({DateTime? now, Duration? delay}) {
    if (!hasMpesaTransaction) {
      return Duration.zero;
    }
    final created = createdAtDateTime;
    if (created == null) {
      return Duration.zero;
    }
    final currentTime = (now ?? DateTime.now()).toUtc();
    final elapsed = currentTime.difference(created);
    final effectiveDelay = _effectiveDelay(delay);
    if (elapsed >= effectiveDelay) {
      return Duration.zero;
    }
    return effectiveDelay - elapsed;
  }

  Duration _effectiveDelay(Duration? delay) {
    return delay ?? Duration(minutes: restaurantOrderDelayMinutes);
  }

  DriverOrder copyWith({
    String? status,
    String? restaurantName,
    String? customerName,
    String? customerPhone,
    String? driverId,
    bool? alert,
    String? orderNumber,
    int? restaurantOrderDelayMinutes,
  }) {
    return DriverOrder(
      id: id,
      status: status ?? this.status,
      items: items,
      alert: alert ?? this.alert,
      orderNumber: orderNumber ?? this.orderNumber,
      allergyNote: allergyNote,
      deliveryAddress: deliveryAddress,
      driverId: driverId ?? this.driverId,
      deliveryLat: deliveryLat,
      deliveryLng: deliveryLng,
      customerId: customerId,
      restaurantId: restaurantId,
      subtotalCents: subtotalCents,
      deliveryFeeCents: deliveryFeeCents,
      totalCents: totalCents,
      paymentIntentId: paymentIntentId,
      createdAt: createdAt,
      mpesaTransactionId: mpesaTransactionId,
      payout: payout,
      etaMinutes: etaMinutes,
      restaurantName: restaurantName ?? this.restaurantName,
      restaurantOrderDelayMinutes:
          restaurantOrderDelayMinutes ?? this.restaurantOrderDelayMinutes,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status,
      'alert': alert,
      'orderNumber': orderNumber,
      'allergyNote': allergyNote,
      'deliveryAddress': deliveryAddress,
      'driverId': driverId,
      'deliveryLat': deliveryLat,
      'deliveryLng': deliveryLng,
      'customerId': customerId,
      'restaurantId': restaurantId,
      'items': items.map((item) => item.toJson()).toList(),
      'subtotalCents': subtotalCents,
      'deliveryFeeCents': deliveryFeeCents,
      'totalCents': totalCents,
      'paymentIntentId': paymentIntentId,
      'createdAt': createdAt,
      'mpesaTransactionId': mpesaTransactionId,
      'payout': payout,
      'etaMinutes': etaMinutes,
      'restaurantName': restaurantName,
      'restaurantOrderDelayMinutes': restaurantOrderDelayMinutes,
      'customerName': customerName,
      'customerPhone': customerPhone,
    };
  }

  factory DriverOrder.fromJson(Map<String, dynamic> json) {
    return DriverOrder(
      id: json['id'].toString(),
      status: json['status'] as String? ?? 'pending',
      alert: _parseBool(json['alert']),
      orderNumber: json['orderNumber']?.toString(),
      allergyNote: json['allergyNote'] as String?,
      deliveryAddress: json['deliveryAddress'] as String?,
      driverId: json['driverId'] as String?,
      deliveryLat: (json['deliveryLat'] as num?)?.toDouble(),
      deliveryLng: (json['deliveryLng'] as num?)?.toDouble(),
      customerId: json['customerId'] as String?,
      restaurantId: json['restaurantId'] as String?,
      items: (json['items'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                OrderItem.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      subtotalCents: (json['subtotalCents'] as num?)?.toInt(),
      deliveryFeeCents: (json['deliveryFeeCents'] as num?)?.toInt(),
      totalCents: (json['totalCents'] as num?)?.toInt(),
      paymentIntentId: json['paymentIntentId'] as String?,
      createdAt: json['createdAt'] as String?,
      mpesaTransactionId: json['mpesaTransactionId'] as String?,
      payout: json['payout'] as String?,
      etaMinutes: (json['etaMinutes'] as num?)?.toInt(),
      restaurantName: json['restaurantName'] as String?,
      restaurantOrderDelayMinutes:
          (json['restaurantOrderDelayMinutes'] as num?)?.toInt() ?? 10,
      customerName: json['customerName'] as String?,
      customerPhone: json['customerPhone'] as String?,
    );
  }

  static bool _parseBool(dynamic value) {
    return switch (value) {
      final bool boolValue => boolValue,
      final num number => number != 0,
      final String text =>
        text.trim().toLowerCase() == 'true' || text.trim() == '1',
      _ => false,
    };
  }
}
