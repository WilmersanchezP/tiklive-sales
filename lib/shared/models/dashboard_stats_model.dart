import 'package:freezed_annotation/freezed_annotation.dart';

part 'dashboard_stats_model.freezed.dart';
part 'dashboard_stats_model.g.dart';

@freezed
class DashboardStats with _$DashboardStats {
  const factory DashboardStats({
    @Default(0) int totalOrdersToday,
    @Default(0.0) double totalRevenueToday,
    @Default(0) int pendingOrders,
    @Default(0) int lowStockAlerts,
    @Default([]) List<TopProduct> topProducts,
    @Default([]) List<SalesDataPoint> salesChart,
    @Default(0) int activeSession,
  }) = _DashboardStats;

  factory DashboardStats.fromJson(Map<String, dynamic> json) =>
      _$DashboardStatsFromJson(json);

  factory DashboardStats.empty() => const DashboardStats();
}

@freezed
class TopProduct with _$TopProduct {
  const factory TopProduct({
    required String productName,
    required int unitsSold,
    required double revenue,
    String? imageUrl,
  }) = _TopProduct;

  factory TopProduct.fromJson(Map<String, dynamic> json) =>
      _$TopProductFromJson(json);
}

@freezed
class SalesDataPoint with _$SalesDataPoint {
  const factory SalesDataPoint({
    required DateTime date,
    required double revenue,
    required int orderCount,
  }) = _SalesDataPoint;

  factory SalesDataPoint.fromJson(Map<String, dynamic> json) =>
      _$SalesDataPointFromJson(json);
}
