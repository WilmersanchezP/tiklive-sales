import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tiklive_sales/core/theme/app_theme.dart';
import 'package:tiklive_sales/features/voice_sales/providers/voice_sales_provider.dart';
import 'package:tiklive_sales/shared/models/dashboard_stats_model.dart';

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) {
  return ref.watch(supabaseServiceProvider).getDashboardStats();
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface900,
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(dashboardStatsProvider),
            tooltip: 'Actualizar',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: statsAsync.when(
        loading: () => const _DashboardSkeleton(),
        error: (e, _) => Center(
          child: Text('Error al cargar: $e', style: const TextStyle(color: AppColors.accentRed)),
        ),
        data: (stats) => _DashboardContent(stats: stats),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final DashboardStats stats;

  const _DashboardContent({required this.stats});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'es_PA', symbol: '\$');

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface800,
      onRefresh: () async {},
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen de Hoy',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              DateFormat('EEEE, d MMMM yyyy', 'es').format(DateTime.now()),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),

            // ── KPI Cards grid ──────────────────────────────────────────────
            GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _KpiCard(
                  label: 'Pedidos Hoy',
                  value: stats.totalOrdersToday.toString(),
                  icon: Icons.receipt_long_rounded,
                  accentColor: AppColors.primary,
                  index: 0,
                ),
                _KpiCard(
                  label: 'Ingresos Hoy',
                  value: currency.format(stats.totalRevenueToday),
                  icon: Icons.monetization_on_rounded,
                  accentColor: AppColors.accentGreen,
                  index: 1,
                ),
                _KpiCard(
                  label: 'Pendientes',
                  value: stats.pendingOrders.toString(),
                  icon: Icons.pending_actions_rounded,
                  accentColor: AppColors.accentAmber,
                  index: 2,
                ),
                _KpiCard(
                  label: 'Stock Bajo',
                  value: stats.lowStockAlerts.toString(),
                  icon: Icons.warning_amber_rounded,
                  accentColor: AppColors.accentRed,
                  index: 3,
                ),
              ],
            ),

            const SizedBox(height: 28),

            // ── Sales chart ─────────────────────────────────────────────────
            if (stats.salesChart.isNotEmpty) ...[
              Text(
                'Ventas Últimos 7 Días',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              _SalesChart(dataPoints: stats.salesChart),
              const SizedBox(height: 28),
            ],

            // ── Top products ─────────────────────────────────────────────────
            if (stats.topProducts.isNotEmpty) ...[
              Text(
                'Productos Más Vendidos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _TopProductsList(products: stats.topProducts),
            ],
          ],
        ),
      ),
    );
  }
}

// ── KPI card ──────────────────────────────────────────────────────────────────
class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final int index;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.index,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: statCardDecoration(accentColor: accentColor),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: accentColor, size: 22),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      )
          .animate()
          .fadeIn(delay: Duration(milliseconds: index * 80), duration: 400.ms)
          .slideY(begin: 0.15, end: 0);
}

// ── Sales chart ───────────────────────────────────────────────────────────────
class _SalesChart extends StatelessWidget {
  final List<SalesDataPoint> dataPoints;

  const _SalesChart({required this.dataPoints});

  @override
  Widget build(BuildContext context) => Container(
        height: 200,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface800,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surface600),
        ),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(
                color: AppColors.surface600,
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= dataPoints.length) return const SizedBox();
                    return Text(
                      DateFormat('E', 'es').format(dataPoints[idx].date),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: List.generate(
                  dataPoints.length,
                  (i) => FlSpot(i.toDouble(), dataPoints[i].revenue),
                ),
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppColors.primary,
                barWidth: 3,
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primary.withOpacity(0.3),
                      AppColors.primary.withOpacity(0.0),
                    ],
                  ),
                ),
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 500.ms);
}

// ── Top products list ─────────────────────────────────────────────────────────
class _TopProductsList extends StatelessWidget {
  final List<TopProduct> products;

  const _TopProductsList({required this.products});

  @override
  Widget build(BuildContext context) {
    final maxUnits = products.isEmpty ? 1 : products.first.unitsSold;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface800,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface600),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: products.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (ctx, i) {
          final p = products[i];
          final fraction = p.unitsSold / maxUnits;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.productName,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: fraction,
                          backgroundColor: AppColors.surface600,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(AppColors.primary),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${p.unitsSold} uds',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(
                delay: Duration(milliseconds: i * 60),
                duration: 350.ms,
              );
        },
      ),
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: List.generate(
                4,
                (_) => Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface800,
                    borderRadius: BorderRadius.circular(16),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .shimmer(duration: 1200.ms, color: AppColors.surface600),
              ),
            ),
          ],
        ),
      );
}
