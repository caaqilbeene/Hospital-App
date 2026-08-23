class MedicineModel {
  final String id;
  final String title;
  final String category;
  final double price;
  final double? originalPrice;
  final int soldCount;
  final String imageUrl;
  final String description;
  final double rating;
  final String sku;
  final bool isFavorite;

  MedicineModel({
    required this.id,
    required this.title,
    this.category = 'Medicine',
    required this.price,
    this.originalPrice,
    required this.soldCount,
    required this.imageUrl,
    required this.description,
    this.rating = 4.7,
    this.sku = 'HP0964',
    this.isFavorite = false,
  });

  factory MedicineModel.fromJson(Map<String, dynamic> json) {
    double parsedPrice = 0.0;
    final rawPrice = json['price'];
    if (rawPrice != null) {
      if (rawPrice is num) {
        parsedPrice = rawPrice.toDouble();
      } else {
        parsedPrice = double.tryParse(rawPrice.toString()) ?? 0.0;
      }
    }

    double? parsedOriginalPrice;
    final rawOrig = json['original_price'] ?? json['originalPrice'];
    if (rawOrig != null) {
      if (rawOrig is num) {
        parsedOriginalPrice = rawOrig.toDouble();
      } else {
        parsedOriginalPrice = double.tryParse(rawOrig.toString());
      }
      if (parsedOriginalPrice != null && (parsedOriginalPrice <= 0 || parsedOriginalPrice <= parsedPrice)) {
        parsedOriginalPrice = null;
      }
    }

    // Auto-heal: If user typed price in original_price field only, promote it to main price!
    if (parsedPrice == 0.0 && parsedOriginalPrice != null && parsedOriginalPrice > 0) {
      parsedPrice = parsedOriginalPrice;
      parsedOriginalPrice = null;
    }

    return MedicineModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      category: json['category'] ?? 'Medicine',
      price: parsedPrice,
      originalPrice: parsedOriginalPrice,
      soldCount: json['sold_count'] ?? json['soldCount'] ?? 40,
      imageUrl: json['image_url'] ?? json['imageUrl'] ?? '',
      description: json['description'] ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 4.7,
      sku: json['sku'] ?? 'HP0964',
      isFavorite: json['is_favorite'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'price': price,
      'original_price': originalPrice,
      'sold_count': soldCount,
      'image_url': imageUrl,
      'description': description,
      'rating': rating,
      'sku': sku,
      'is_favorite': isFavorite,
    };
  }

  MedicineModel copyWith({
    String? id,
    String? title,
    String? category,
    double? price,
    double? originalPrice,
    bool clearOriginalPrice = false, // Flag to clear discount/original price
    int? soldCount,
    String? imageUrl,
    String? description,
    double? rating,
    String? sku,
    bool? isFavorite,
  }) {
    return MedicineModel(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      price: price ?? this.price,
      originalPrice: clearOriginalPrice ? null : (originalPrice ?? this.originalPrice),
      soldCount: soldCount ?? this.soldCount,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
      rating: rating ?? this.rating,
      sku: sku ?? this.sku,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
