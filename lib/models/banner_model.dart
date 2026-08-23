class BannerModel {
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String linkTarget;
  final bool isActive;
  final String createdAt;

  BannerModel({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.imageUrl = '',
    this.linkTarget = '',
    this.isActive = true,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  factory BannerModel.fromJson(Map<String, dynamic> json) {
    return BannerModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      linkTarget: json['link_target']?.toString() ?? '',
      isActive: json['is_active'] == true || json['is_active'] == 1 || json['is_active'] == null,
      createdAt: json['created_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'image_url': imageUrl,
      'link_target': linkTarget,
      'is_active': isActive,
      'created_at': createdAt,
    };
  }

  BannerModel copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? imageUrl,
    String? linkTarget,
    bool? isActive,
    String? createdAt,
  }) {
    return BannerModel(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      imageUrl: imageUrl ?? this.imageUrl,
      linkTarget: linkTarget ?? this.linkTarget,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
