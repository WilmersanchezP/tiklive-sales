import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiklive_sales/core/constants/app_constants.dart';
import 'package:tiklive_sales/core/theme/app_theme.dart';
import 'package:tiklive_sales/features/voice_sales/providers/voice_sales_provider.dart';
import 'package:tiklive_sales/shared/models/product_model.dart';

final productsProvider = FutureProvider<List<ProductModel>>((ref) {
  return ref.watch(supabaseServiceProvider).getProducts();
});

final inventorySearchProvider = StateProvider<String>((_) => '');

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    final searchQuery = ref.watch(inventorySearchProvider);

    return Scaffold(
      backgroundColor: AppColors.surface900,
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAddProductDialog(context, ref),
            tooltip: 'Agregar producto',
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => ref.read(inventorySearchProvider.notifier).state = v,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: 18),
                hintText: 'Buscar producto...',
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: AppColors.accentRed)),
        ),
        data: (products) {
          final filtered = searchQuery.isEmpty
              ? products
              : products.where((p) =>
                  p.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();

          if (filtered.isEmpty) {
            return const Center(
              child: Text(
                'Sin productos.\nAgrega tu catálogo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.of(context).size.width > 900
                  ? 4
                  : MediaQuery.of(context).size.width > 600
                      ? 3
                      : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) => _ProductCard(
              product: filtered[i],
              index: i,
            ),
          );
        },
      ),
    );
  }

  void _showAddProductDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface800,
        title: const Text('Nuevo Producto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nombre del producto'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(
                labelText: 'Precio base',
                prefixText: '\$ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              await ref.read(supabaseServiceProvider)._client
                  .from(AppConstants.tableProducts)
                  .insert({
                'name': nameController.text.trim(),
                'base_price': double.tryParse(priceController.text),
              });
              ref.invalidate(productsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final int index;

  const _ProductCard({required this.product, required this.index});

  @override
  Widget build(BuildContext context) {
    final totalStock = product.variants.fold<int>(
      0,
      (sum, v) => sum + v.stockQuantity,
    );
    final isLowStock = totalStock <= AppConstants.lowStockThreshold && totalStock > 0;
    final isOutOfStock = totalStock == 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface800,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOutOfStock
              ? AppColors.accentRed.withOpacity(0.4)
              : isLowStock
                  ? AppColors.accentAmber.withOpacity(0.4)
                  : AppColors.surface600,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: AspectRatio(
              aspectRatio: 1,
              child: product.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: product.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          const ColoredBox(color: AppColors.surface700),
                      errorWidget: (_, __, ___) => _PlaceholderImage(),
                    )
                  : _PlaceholderImage(),
            ),
          ),

          // Product info
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (product.basePrice != null)
                  Text(
                    '\$${product.basePrice!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppColors.accentGreen,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 6),
                // Stock badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isOutOfStock
                        ? AppColors.accentRed.withOpacity(0.15)
                        : isLowStock
                            ? AppColors.accentAmber.withOpacity(0.15)
                            : AppColors.accentGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isOutOfStock
                        ? 'Sin stock'
                        : isLowStock
                            ? 'Stock bajo: $totalStock'
                            : '$totalStock en stock',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isOutOfStock
                          ? AppColors.accentRed
                          : isLowStock
                              ? AppColors.accentAmber
                              : AppColors.accentGreen,
                    ),
                  ),
                ),

                // Variants
                if (product.variants.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: product.variants.take(4).map((v) {
                      return Tooltip(
                        message: '${v.size ?? ''} ${v.color ?? ''} — ${v.stockQuantity} uds',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surface600,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            v.size ?? v.color ?? '?',
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(
          delay: Duration(milliseconds: index * 40),
          duration: 350.ms,
        )
        .slideY(begin: 0.1, end: 0);
  }
}

class _PlaceholderImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surface700,
        child: const Center(
          child: Icon(
            Icons.inventory_2_outlined,
            color: AppColors.textMuted,
            size: 40,
          ),
        ),
      );
}
