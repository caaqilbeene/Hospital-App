String toTitleCase(String input) {
  if (input.trim().isEmpty) return input;
  return input.trim().split(RegExp(r'\s+')).map((word) {
    if (word.isEmpty) return '';
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }).join(' ');
}

class UserModel {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String email;
  final String avatarUrl;
  final bool isAdmin;
  final DateTime? createdAt;

  UserModel({
    required this.id,
    required String fullName,
    required this.phoneNumber,
    required this.email,
    this.avatarUrl = '',
    this.isAdmin = false,
    this.createdAt,
  }) : fullName = toTitleCase(fullName);

  factory UserModel.fromJson(Map<String, dynamic> json) {
    DateTime? parsedDate;
    final rawDate = json['createdAt'] ?? json['created_at'];
    if (rawDate != null) {
      if (rawDate is String) {
        parsedDate = DateTime.tryParse(rawDate);
      } else if (rawDate.runtimeType.toString().contains('Timestamp')) {
        try {
          parsedDate = (rawDate as dynamic).toDate();
        } catch (_) {}
      }
    }

    final rawName = json['full_name'] ?? json['fullName'] ?? 'Patient';

    return UserModel(
      id: json['id']?.toString() ?? '',
      fullName: toTitleCase(rawName.toString()),
      phoneNumber:
          json['phone_number'] ?? json['phoneNumber'] ?? '+252 61 1234567',
      email: json['email'] ?? '',
      avatarUrl: json['avatar_url'] ?? json['avatarUrl'] ?? '',
      isAdmin: json['is_admin'] ?? false,
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'email': email,
      'avatar_url': avatarUrl,
      'is_admin': isAdmin,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  String get formattedJoinedDate {
    final date = createdAt ?? DateTime(2026, 8, 5);
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${date.day} ${months[date.month - 1]}, ${date.year}';
  }

  UserModel copyWith({
    String? id,
    String? fullName,
    String? phoneNumber,
    String? email,
    String? avatarUrl,
    bool? isAdmin,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isAdmin: isAdmin ?? this.isAdmin,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

