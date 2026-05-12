import 'package:freezed_annotation/freezed_annotation.dart';

part 'product_model.freezed.dart';
part 'product_model.g.dart';

@freezed
class ProductModel with _$ProductModel {
  const factory ProductModel({
    required String id,
    required String name,
    String? description,
    String? imageUrl,
    double? basePrice,
    String? category,
    @Default(true) bool isActive,
    required DateTime createdAt,
    @Default([]) List<ProductVariantModel> variants,
  }) = _ProductModel;

  factory ProductModel.fromJson(Map<String, dynamic> json) =>
      _$ProductModelFromJson(json);

  factory ProductModel.fromSupabase(Map<String, dynamic> row) => ProductModel(
        id: row['id'] as String,
        name: row['name'] as String,
        description: row['description'] as String?,
        imageUrl: row['image_url'] as String?,
        basePrice: (row['base_price'] as num?)?.toDouble(),
        category: row['category'] as String?,
        isActive: row['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(row['created_at'] as String),
        variants: (row['product_variants'] as List<dynamic>? ?? [])
            .map((v) => ProductVariantModel.fromSupabase(v as Map<String, dynamic>))
            .toList(),
      );
}

@freezed
class ProductVariantModel with _$ProductVariantModel {
  const factory ProductVariantModel({
    required String id,
    required String productId,
    String? color,
    String? size,
    double? price,
    String? sku,
    required int stockQuantity,
  }) = _ProductVariantModel;

  factory ProductVariantModel.fromJson(Map<String, dynamic> json) =>
      _$ProductVariantModelFromJson(json);

  factory ProductVariantModel.fromSupabase(Map<String, dynamic> row) =>
      ProductVariantModel(
        id: row['id'] as String,
        productId: row['product_id'] as String,
        color: row['color'] as String?,
        size: row['size'] as String?,
        price: (row['price'] as num?)?.toDouble(),
        sku: row['sku'] as String?,
        stockQuantity: (row['stock_quantity'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toSupabase() => {
        'product_id': productId,
        'color': color,
        'size': size,
        'price': price,
        'sku': sku,
        'stock_quantity': stockQuantity,
      };
}
