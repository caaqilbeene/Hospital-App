class SpecialtyModel {
  final String id;
  final String name;
  final String iconName;
  final String description;
  final bool isActive;
  final String createdAt;

  SpecialtyModel({
    required this.id,
    required this.name,
    this.iconName = '',
    this.description = '',
    this.isActive = true,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  factory SpecialtyModel.fromJson(Map<String, dynamic> json) {
    return SpecialtyModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? json['specialty']?.toString() ?? '',
      iconName: json['icon_name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      isActive: json['is_active'] == true || json['is_active'] == 1 || json['is_active'] == null,
      createdAt: json['created_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon_name': iconName,
      'description': description,
      'is_active': isActive,
      'created_at': createdAt,
    };
  }

  SpecialtyModel copyWith({
    String? id,
    String? name,
    String? iconName,
    String? description,
    bool? isActive,
    String? createdAt,
  }) {
    return SpecialtyModel(
      id: id ?? this.id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
