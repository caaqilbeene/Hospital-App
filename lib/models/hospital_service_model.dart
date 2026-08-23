class HospitalServiceModel {
  final String id;
  final String title;
  final String description;
  final String iconName;
  final String category;
  final double fee;
  final bool isActive;
  final String createdAt;

  HospitalServiceModel({
    required this.id,
    required this.title,
    this.description = '',
    this.iconName = '',
    this.category = 'General',
    this.fee = 0.0,
    this.isActive = true,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  factory HospitalServiceModel.fromJson(Map<String, dynamic> json) {
    return HospitalServiceModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      iconName: json['icon_name']?.toString() ?? '',
      category: json['category']?.toString() ?? 'General',
      fee: (json['fee'] is num) ? (json['fee'] as num).toDouble() : (double.tryParse(json['fee']?.toString() ?? '0') ?? 0.0),
      isActive: json['is_active'] == true || json['is_active'] == 1 || json['is_active'] == null,
      createdAt: json['created_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'icon_name': iconName,
      'category': category,
      'fee': fee,
      'is_active': isActive,
      'created_at': createdAt,
    };
  }

  HospitalServiceModel copyWith({
    String? id,
    String? title,
    String? description,
    String? iconName,
    String? category,
    double? fee,
    bool? isActive,
    String? createdAt,
  }) {
    return HospitalServiceModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      iconName: iconName ?? this.iconName,
      category: category ?? this.category,
      fee: fee ?? this.fee,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
