import 'package:freezed_annotation/freezed_annotation.dart';

part 'order_model.freezed.dart';
part 'order_model.g.dart';

enum PaymentMethod {
  @JsonValue('CASH') cash,
  @JsonValue('COD') cod,
  @JsonValue('TRANSFER') transfer,
  @JsonValue('PENDING') pending,
}

enum OrderStatus {
  @JsonValue('PENDING') pending,
  @JsonValue('CONFIRMED') confirmed,
  @JsonValue('RESERVED') reserved,
  @JsonValue('SHIPPED') shipped,
  @JsonValue('DELIVERED') delivered,
  @JsonValue('CANCELLED') cancelled,
}

extension PaymentMethodLabel on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.cash => 'Efectivo',
        PaymentMethod.cod => 'Contra Entrega',
        PaymentMethod.transfer => 'Transferencia',
        PaymentMethod.pending => 'Por definir',
      };
}

extension OrderStatusLabel on OrderStatus {
  String get label => switch (this) {
        OrderStatus.pending => 'Pendiente',
        OrderStatus.confirmed => 'Confirmado',
        OrderStatus.reserved => 'Reservado',
        OrderStatus.shipped => 'Enviado',
        OrderStatus.delivered => 'Entregado',
        OrderStatus.cancelled => 'Cancelado',
      };
}

@freezed
class OrderModel with _$OrderModel {
  const factory OrderModel({
    required String id,
    required String productName,
    String? color,
    String? size,
    @Default(1) int quantity,
    required String customerName,
    String? customerPhone,
    @Default(PaymentMethod.pending) PaymentMethod paymentMethod,
    @Default(OrderStatus.pending) OrderStatus status,
    required DateTime createdAt,
    String? liveSessionId,
    String? notes,
    double? unitPrice,
    double? totalPrice,
    String? sellerId,
    String? productVariantId,
  }) = _OrderModel;

  factory OrderModel.fromJson(Map<String, dynamic> json) =>
      _$OrderModelFromJson(json);

  factory OrderModel.fromSupabase(Map<String, dynamic> row) => OrderModel(
        id: row['id'] as String,
        productName: row['product_name'] as String,
        color: row['color'] as String?,
        size: row['size'] as String?,
        quantity: (row['quantity'] as num?)?.toInt() ?? 1,
        customerName: row['customer_name'] as String? ?? 'Sin nombre',
        customerPhone: row['customer_phone'] as String?,
        paymentMethod: PaymentMethod.values.firstWhere(
          (e) => e.name.toUpperCase() == (row['payment_method'] as String? ?? 'PENDING'),
          orElse: () => PaymentMethod.pending,
        ),
        status: OrderStatus.values.firstWhere(
          (e) => e.name.toUpperCase() == (row['status'] as String? ?? 'PENDING'),
          orElse: () => OrderStatus.pending,
        ),
        createdAt: DateTime.parse(row['created_at'] as String),
        liveSessionId: row['live_session_id'] as String?,
        notes: row['notes'] as String?,
        unitPrice: (row['unit_price'] as num?)?.toDouble(),
        totalPrice: (row['total_price'] as num?)?.toDouble(),
        sellerId: row['seller_id'] as String?,
        productVariantId: row['product_variant_id'] as String?,
      );
}

// Extension keeps toSupabase() outside Freezed to avoid codegen conflicts
extension OrderModelX on OrderModel {
  Map<String, dynamic> toSupabase() => {
        'product_name': productName,
        'color': color,
        'size': size,
        'quantity': quantity,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'payment_method': paymentMethod.name.toUpperCase(),
        'status': status.name.toUpperCase(),
        'live_session_id': liveSessionId,
        'notes': notes,
        'unit_price': unitPrice,
        'total_price': totalPrice,
        'seller_id': sellerId,
        'product_variant_id': productVariantId,
      };
}

@freezed
class ExtractedOrder with _$ExtractedOrder {
  const factory ExtractedOrder({
    required String productName,
    String? color,
    String? size,
    @Default(1) int quantity,
    String? customerName,
    @Default(PaymentMethod.pending) PaymentMethod paymentMethod,
    @Default(OrderStatus.pending) OrderStatus status,
    String? notes,
    required String rawTranscript,
    @Default(1.0) double confidence,
  }) = _ExtractedOrder;

  factory ExtractedOrder.fromJson(Map<String, dynamic> json) =>
      _$ExtractedOrderFromJson(json);
}
