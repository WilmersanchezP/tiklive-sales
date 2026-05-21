import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tiklive_sales/core/constants/app_constants.dart';
import 'package:tiklive_sales/shared/models/dashboard_stats_model.dart';
import 'package:tiklive_sales/shared/models/order_model.dart';
import 'package:tiklive_sales/shared/models/product_model.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // ── Auth ────────────────────────────────────────────────────────────────────
  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _client.auth.signOut();

  Future<Map<String, dynamic>?> getCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;
    return _client
        .from(AppConstants.tableProfiles)
        .select()
        .eq('id', user.id)
        .single();
  }

  // ── Orders ──────────────────────────────────────────────────────────────────
  Future<List<OrderModel>> getOrders({
    int limit = 50,
    DateTime? from,
    String? status,
  }) async {
    // Filters must be applied before order/limit in Supabase Flutter 2.x
    var q = _client.from(AppConstants.tableOrders).select();
    if (from != null) q = q.gte('created_at', from.toIso8601String());
    if (status != null) q = q.eq('status', status);
    final data = await q
        .order('created_at', ascending: false)
        .limit(limit)
        .timeout(const Duration(seconds: 10), onTimeout: () => []);
    return (data as List)
        .map((row) => OrderModel.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  Future<OrderModel> createOrder(OrderModel order) async {
    final data = order.toSupabase()
      ..['seller_id'] = currentUser?.id; // RLS requires seller_id = auth.uid()
    final row = await _client
        .from(AppConstants.tableOrders)
        .insert(data)
        .select()
        .single();

    // Decrement inventory if variant known
    if (order.productVariantId != null) {
      await _decrementStock(order.productVariantId!, order.quantity);
    }

    return OrderModel.fromSupabase(row);
  }

  Future<OrderModel> updateOrderStatus(String orderId, OrderStatus status) async {
    final row = await _client
        .from(AppConstants.tableOrders)
        .update({'status': status.name.toUpperCase()})
        .eq('id', orderId)
        .select()
        .single();
    return OrderModel.fromSupabase(row);
  }

  // ── Products & Inventory ────────────────────────────────────────────────────
  Future<void> createProduct({required String name, double? basePrice}) async {
    await _client.from(AppConstants.tableProducts).insert({
      'name': name,
      if (basePrice != null) 'base_price': basePrice,
      'created_by': currentUser?.id,
    });
  }

  Future<List<ProductModel>> getProducts({bool activeOnly = true}) async {
    var query = _client
        .from(AppConstants.tableProducts)
        .select('*, product_variants(*)');

    if (activeOnly) {
      query = query.eq('is_active', true);
    }

    final data = await query.order('name');
    return (data as List)
        .map((row) => ProductModel.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<ProductVariantModel>> getLowStockVariants() async {
    try {
      final data = await _client
          .from(AppConstants.tableProductVariants)
          .select('*, products(name)')
          .lte('stock_quantity', AppConstants.lowStockThreshold)
          .order('stock_quantity');

      return (data as List)
          .map((row) => ProductVariantModel.fromSupabase(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[SupabaseService] getLowStockVariants error: $e');
      return [];
    }
  }

  Future<void> adjustStock(String variantId, int delta) async {
    await _client.rpc('adjust_stock', params: {
      'variant_id': variantId,
      'delta': delta,
    });
  }

  // ── Dashboard ───────────────────────────────────────────────────────────────
  Future<DashboardStats> getDashboardStats() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    const t = Duration(seconds: 8);

    // Each query runs independently so one failure never blocks the others.
    List<OrderModel> todayOrders = [];
    int pendingCount = 0;
    List<ProductVariantModel> lowStock = [];
    List<TopProduct> topProducts = [];
    List<SalesDataPoint> chart = [];

    try {
      todayOrders = await _getTodayOrders(todayStart).timeout(t, onTimeout: () => []);
    } catch (e) {
      debugPrint('[Dashboard] todayOrders: $e');
    }
    try {
      pendingCount = await _getPendingCount().timeout(t, onTimeout: () => 0);
    } catch (e) {
      debugPrint('[Dashboard] pendingCount: $e');
    }
    try {
      lowStock = await getLowStockVariants().timeout(t, onTimeout: () => []);
    } catch (e) {
      debugPrint('[Dashboard] lowStock: $e');
    }
    try {
      topProducts = await _getTopProducts(todayStart).timeout(t, onTimeout: () => []);
    } catch (e) {
      debugPrint('[Dashboard] topProducts: $e');
    }
    try {
      chart = await _getSalesChart().timeout(t, onTimeout: () => []);
    } catch (e) {
      debugPrint('[Dashboard] chart: $e');
    }

    final revenue = todayOrders.fold<double>(
      0,
      (sum, o) => sum + (o.totalPrice ?? 0),
    );

    return DashboardStats(
      totalOrdersToday: todayOrders.length,
      totalRevenueToday: revenue,
      pendingOrders: pendingCount,
      lowStockAlerts: lowStock.length,
      topProducts: topProducts,
      salesChart: chart,
    );
  }

  Future<List<OrderModel>> _getTodayOrders(DateTime todayStart) => getOrders(
        from: todayStart,
        limit: 500,
      );

  // Uses select+length instead of .count() to avoid API version inconsistencies.
  Future<int> _getPendingCount() async {
    final data = await _client
        .from(AppConstants.tableOrders)
        .select('id')
        .eq('status', 'PENDING');
    return (data as List).length;
  }

  Future<List<TopProduct>> _getTopProducts(DateTime from) async {
    try {
      final data = await _client.rpc('get_top_products', params: {
        'from_date': from.toIso8601String(),
        'limit_count': 5,
      });
      if (data == null) return [];
      return (data as List).map((row) {
        final m = row as Map<String, dynamic>;
        return TopProduct(
          productName: m['product_name'] as String,
          unitsSold: (m['units_sold'] as num).toInt(),
          revenue: (m['revenue'] as num).toDouble(),
        );
      }).toList();
    } catch (e) {
      debugPrint('[SupabaseService] _getTopProducts error: $e');
      return [];
    }
  }

  Future<List<SalesDataPoint>> _getSalesChart() async {
    try {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final data = await _client.rpc('get_daily_sales', params: {
        'from_date': sevenDaysAgo.toIso8601String(),
      });
      if (data == null) return [];
      return (data as List).map((row) {
        final m = row as Map<String, dynamic>;
        return SalesDataPoint(
          date: DateTime.parse(m['sale_date'] as String),
          revenue: (m['revenue'] as num).toDouble(),
          orderCount: (m['order_count'] as num).toInt(),
        );
      }).toList();
    } catch (e) {
      debugPrint('[SupabaseService] _getSalesChart error: $e');
      return [];
    }
  }

  // ── Live Sessions ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> startLiveSession(String title) async {
    return _client
        .from(AppConstants.tableLiveSessions)
        .insert({
          'title': title,
          'seller_id': currentUser?.id,
          'started_at': DateTime.now().toIso8601String(),
          'status': 'ACTIVE',
        })
        .select()
        .single();
  }

  Future<void> endLiveSession(String sessionId) async {
    await _client
        .from(AppConstants.tableLiveSessions)
        .update({
          'ended_at': DateTime.now().toIso8601String(),
          'status': 'ENDED',
        })
        .eq('id', sessionId);
  }

  // ── Voice transcripts (audit log) ──────────────────────────────────────────
  Future<void> saveTranscript({
    required String transcript,
    required String? orderId,
    required String? sessionId,
  }) async {
    await _client.from(AppConstants.tableVoiceTranscripts).insert({
      'transcript': transcript,
      'order_id': orderId,
      'session_id': sessionId,
      'seller_id': currentUser?.id,
    });
  }

  // ── Realtime subscription ───────────────────────────────────────────────────
  RealtimeChannel subscribeToOrders(
    void Function(Map<String, dynamic>) onInsert,
  ) {
    return _client
        .channel('orders-realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: AppConstants.tableOrders,
          callback: (payload) => onInsert(payload.newRecord),
        )
        .subscribe();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  Future<void> _decrementStock(String variantId, int quantity) async {
    try {
      await _client.rpc('adjust_stock', params: {
        'variant_id': variantId,
        'delta': -quantity,
      });
    } catch (e) {
      debugPrint('[SupabaseService] Stock decrement error: $e');
    }
  }
}
