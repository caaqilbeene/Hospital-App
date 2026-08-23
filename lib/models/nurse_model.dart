class NurseModel {
  final String id;
  final String name;
  final String specialty;
  final String imageUrl;
  final double fee;
  final double? discountFee;

  NurseModel({
    required this.id,
    required this.name,
    required this.specialty,
    required this.imageUrl,
    this.fee = 0.0,
    this.discountFee,
  });

  // Backward compatibility getters
  String get role => specialty;
  double get visitFee => fee;
  double get activePrice => (discountFee != null && discountFee! > 0) ? discountFee! : fee;

  factory NurseModel.fromJson(Map<String, dynamic> json) {
    return NurseModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      specialty: json['specialty']?.toString() ?? json['role']?.toString() ?? 'Kalkaaliso',
      imageUrl: (json['image_url'] != null && json['image_url'].toString().trim().isNotEmpty)
          ? json['image_url'].toString()
          : (json['imageUrl']?.toString() ?? ''),
      fee: ((json['fee'] ?? json['visit_fee'] ?? json['price'] ?? json['consultation_fee'] ?? 0.0) as num).toDouble(),
      discountFee: json['discount_fee'] != null ? (json['discount_fee'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'specialty': specialty,
      'role': specialty,
      'fee': fee,
      'visit_fee': fee,
      'discount_fee': discountFee,
      'image_url': imageUrl,
    };
  }

  NurseModel copyWith({
    String? id,
    String? name,
    String? specialty,
    String? imageUrl,
    double? fee,
    double? discountFee,
  }) {
    return NurseModel(
      id: id ?? this.id,
      name: name ?? this.name,
      specialty: specialty ?? this.specialty,
      imageUrl: imageUrl ?? this.imageUrl,
      fee: fee ?? this.fee,
      discountFee: discountFee ?? this.discountFee,
    );
  }
}
