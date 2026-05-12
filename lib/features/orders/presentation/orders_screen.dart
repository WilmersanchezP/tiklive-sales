import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tiklive_sales/core/theme/app_theme.dart';
import 'package:tiklive_sales/features/voice_sales/providers/voice_sales_provider.dart';
import 'package:tiklive_sales/services/export_service.dart';
import 'package:tiklive_sales/shared/models/order_model.dart';

final ordersFilterProvider = StateProvider<OrderStatus?>((_) => null);

final filteredOrdersProvider = FutureProvider<List<OrderModel>>((ref) async {
  final filter = ref.watch(ordersFilterProvider);
  final db = ref.watch(supabaseServiceProvider);
  return db.getOrders(
    limit: 100,
    status: filter?.name.toUpperCase(),
  );
});

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(filteredOrdersProvider);
    final filter = ref.watch(ordersFilterProvider);

    return Scaffold(
      backgroundColor: AppColors.surface900,
      appBar: AppBar(
        title: const Text('Pedidos'),
        actions: [
          // Export button
          ordersAsync.when(
            data: (orders) => IconButton(
              icon: const Icon(Icons.download_rounded),
              onPressed: () => _showExportMenu(context, orders),
              tooltip: 'Exportar',
            ),
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _FilterChip(
                  label: 'Todos',
                  isSelected: filter == null,
                  onTap: () => ref.read(ordersFilterProvider.notifier).state = null,
                ),
                ...OrderStatus.values.map(
                  (s) => _FilterChip(
                    label: s.label,
                    isSelected: filter == s,
                    onTap: () => ref.read(ordersFilterProvider.notifier).state = s,
                    color: _statusColor(s),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: AppColors.accentRed)),
        ),
        data: (orders) => orders.isEmpty
            ? const _EmptyOrders()
            : _OrdersList(orders: orders),
      ),
    );
  }

  void _showExportMenu(BuildContext context, List<OrderModel> orders) {
    final export = ExportService();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface800,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface500,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_rounded, color: AppColors.accentGreen),
              title: const Text('Exportar a Excel (.xlsx)'),
              onTap: () {
                Navigator.pop(ctx);
                export.exportOrdersToExcel(orders);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.accentRed),
              title: const Text('Exportar a PDF'),
              onTap: () {
                Navigator.pop(ctx);
                export.exportOrdersToPdf(orders);
              },
            ),
            ListTile(
              leading: const Icon(Icons.data_object_rounded, color: AppColors.accent),
              title: const Text('Exportar a CSV'),
              onTap: () {
                Navigator.pop(ctx);
                export.exportOrdersToCsv(orders);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  final List<OrderModel> orders;

  const _OrdersList({required this.orders});

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) => _OrderCard(order: orders[i], index: i),
      );
}

class _OrderCard extends ConsumerWidget {
  final OrderModel order;
  final int index;

  const _OrderCard({required this.order, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface800,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surface600),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (order.color != null) order.color!,
                          if (order.size != null) 'Talla ${order.size}',
                          'x${order.quantity}',
                        ].join(' • '),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusDropdown(order: order, onChanged: (s) => _updateStatus(ref, s)),
              ],
            ),

            const SizedBox(height: 12),

            // Customer & payment row
            Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(order.customerName,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(width: 12),
                const Icon(Icons.payment_rounded, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(order.paymentMethod.label,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const Spacer(),
                if (order.totalPrice != null)
                  Text(
                    '\$${order.totalPrice!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppColors.accentGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 6),

            // Timestamp
            Text(
              DateFormat('dd/MM/yyyy HH:mm', 'es').format(order.createdAt),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),

            if (order.notes != null && order.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                order.notes!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      )
          .animate()
          .fadeIn(
            delay: Duration(milliseconds: index * 30),
            duration: 350.ms,
          )
          .slideY(begin: 0.05, end: 0);

  Future<void> _updateStatus(WidgetRef ref, OrderStatus status) async {
    await ref.read(supabaseServiceProvider).updateOrderStatus(order.id, status);
    ref.invalidate(filteredOrdersProvider);
  }
}

class _StatusDropdown extends StatelessWidget {
  final OrderModel order;
  final void Function(OrderStatus) onChanged;

  const _StatusDropdown({required this.order, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButton<OrderStatus>(
        value: order.status,
        underline: const SizedBox(),
        style: TextStyle(
          fontSize: 12,
          color: _statusColor(order.status),
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
        dropdownColor: AppColors.surface700,
        borderRadius: BorderRadius.circular(10),
        items: OrderStatus.values
            .map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(s.label,
                      style: TextStyle(color: _statusColor(s), fontSize: 12)),
                ))
            .toList(),
        onChanged: (s) => s != null ? onChanged(s) : null,
      );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.15) : AppColors.surface700,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.surface500,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isSelected ? activeColor : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_rounded, size: 48, color: AppColors.textMuted),
            SizedBox(height: 16),
            Text(
              'Sin pedidos en este filtro',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      );
}

Color _statusColor(OrderStatus status) => switch (status) {
      OrderStatus.confirmed => AppColors.accentGreen,
      OrderStatus.reserved => AppColors.accentAmber,
      OrderStatus.pending => AppColors.textMuted,
      OrderStatus.shipped => AppColors.accent,
      OrderStatus.delivered => AppColors.accentGreen,
      OrderStatus.cancelled => AppColors.accentRed,
    };
