class DoctorModel {
  final String id;
  final String userId;
  final String name;
  final String specialty;
  final String hospital;
  final double rating;
  final int reviewsCount;
  final String experience;
  final String patientsCount;
  final String workingHours;
  final String about;
  final double consultationFee;
  final double? discountFee;
  final String imageUrl;
  final bool isAvailable;
  final bool isOnline;
  final String lastSeen;
  final bool isVerified;
  final bool isTyping;
  final bool showInChat;

  double get activePrice => (discountFee != null && discountFee! > 0 && discountFee! < consultationFee)
      ? discountFee!
      : consultationFee;

  DoctorModel({
    required this.id,
    this.userId = '',
    required this.name,
    required this.specialty,
    required this.hospital,
    required this.rating,
    required this.reviewsCount,
    required this.experience,
    required this.patientsCount,
    required this.workingHours,
    required this.about,
    required this.consultationFee,
    this.discountFee,
    required this.imageUrl,
    this.isAvailable = true,
    this.isOnline = false,
    this.lastSeen = '',
    this.isVerified = false,
    this.isTyping = false,
    this.showInChat = true,
  });

  static bool _parseBool(dynamic val, {bool defaultValue = false}) {
    if (val == null) return defaultValue;
    if (val is bool) return val;
    final str = val.toString().trim().toLowerCase();
    if (str == 'true' || str == '1' || str == 't') return true;
    if (str == 'false' || str == '0' || str == 'f') return false;
    return defaultValue;
  }

  static String sanitizeDoctorName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return 'Dr.';
    String clean = trimmed;
    while (RegExp(r'^dr\.?\s*', caseSensitive: false).hasMatch(clean)) {
      clean = clean.replaceFirst(RegExp(r'^dr\.?\s*', caseSensitive: false), '').trim();
    }
    return 'Dr. $clean';
  }

  factory DoctorModel.fromJson(Map<String, dynamic> json) {
    final rawConsultation = json['consultation_fee'] ?? json['price'] ?? 0.0;

    return DoctorModel(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      name: sanitizeDoctorName(json['name'] ?? ''),
      specialty: json['specialty'] ?? '',
      hospital: json['hospital'] ?? 'Nasiib Hospital',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviewsCount: json['reviews_count'] ?? json['reviewsCount'] ?? 0,
      experience: json['experience']?.toString() ?? '',
      patientsCount: (json['patients_count'] != null && json['patients_count'].toString().trim().isNotEmpty)
          ? json['patients_count'].toString().trim()
          : ((json['patientsCount'] != null && json['patientsCount'].toString().trim().isNotEmpty)
              ? json['patientsCount'].toString().trim()
              : '0+'),
      workingHours: json['working_hours']?.toString() ?? json['workingHours']?.toString() ?? '',
      about: json['about']?.toString() ?? '',
      consultationFee: (rawConsultation as num?)?.toDouble() ?? 0.0,
      discountFee: json['discount_fee'] != null
          ? (json['discount_fee'] as num).toDouble()
          : ((json['discountFee'] as num?)?.toDouble()),
      imageUrl: json['image_url'] ?? json['imageUrl'] ?? '',
      isAvailable: _parseBool(json['is_available'] ?? json['isAvailable'], defaultValue: true),
      isOnline: _parseBool(json['is_online'] ?? json['isOnline'], defaultValue: false),
      lastSeen: json['last_seen']?.toString() ?? json['lastSeen']?.toString() ?? '',
      isVerified: _parseBool(json['is_verified'] ?? json['isVerified'], defaultValue: false),
      isTyping: _parseBool(json['is_typing'], defaultValue: false),
      showInChat: _parseBool(json['show_in_chat'] ?? json['showInChat'], defaultValue: true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'specialty': specialty,
      'hospital': hospital,
      'rating': rating,
      'reviews_count': reviewsCount,
      'experience': experience,
      'patients_count': patientsCount,
      'working_hours': workingHours,
      'about': about,
      'consultation_fee': consultationFee,
      'discount_fee': discountFee,
      'image_url': imageUrl,
      'is_available': isAvailable,
      'is_online': isOnline,
      'last_seen': lastSeen,
      'is_verified': isVerified,
      'is_typing': isTyping,
      'show_in_chat': showInChat,
    };
  }

  DoctorModel copyWith({
    String? id,
    String? userId,
    String? name,
    String? specialty,
    String? hospital,
    double? rating,
    int? reviewsCount,
    String? experience,
    String? patientsCount,
    String? workingHours,
    String? about,
    double? consultationFee,
    double? discountFee,
    String? imageUrl,
    bool? isAvailable,
    bool? isOnline,
    String? lastSeen,
    bool? isVerified,
    bool? isTyping,
    bool? showInChat,
  }) {
    return DoctorModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      specialty: specialty ?? this.specialty,
      hospital: hospital ?? this.hospital,
      rating: rating ?? this.rating,
      reviewsCount: reviewsCount ?? this.reviewsCount,
      experience: experience ?? this.experience,
      patientsCount: patientsCount ?? this.patientsCount,
      workingHours: workingHours ?? this.workingHours,
      about: about ?? this.about,
      consultationFee: consultationFee ?? this.consultationFee,
      discountFee: discountFee ?? this.discountFee,
      imageUrl: imageUrl ?? this.imageUrl,
      isAvailable: isAvailable ?? this.isAvailable,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      isVerified: isVerified ?? this.isVerified,
      isTyping: isTyping ?? this.isTyping,
      showInChat: showInChat ?? this.showInChat,
    );
  }
}


