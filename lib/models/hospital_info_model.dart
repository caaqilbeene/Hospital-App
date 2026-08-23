class HospitalInfoModel {
  final String id;
  final String hospitalName;
  final String description;
  final String about;
  final String phone;
  final String email;
  final String address;
  final String openingHours;
  final String emergencyNumber;
  final String logoUrl;
  final String bannerUrl;

  HospitalInfoModel({
    this.id = 'default',
    this.hospitalName = 'Nasiib Hospital',
    this.description = 'Leading digital healthcare & hospital services',
    this.about = 'Nasiib Hospital is committed to providing world-class compassionate healthcare.',
    this.phone = '+252 61 000 0000',
    this.email = 'info@nasiibhospital.com',
    this.address = 'Mogadishu, Somalia',
    this.openingHours = '24/7 Open',
    this.emergencyNumber = '999',
    this.logoUrl = '',
    this.bannerUrl = '',
  });

  factory HospitalInfoModel.fromJson(Map<String, dynamic> json) {
    return HospitalInfoModel(
      id: json['id']?.toString() ?? 'default',
      hospitalName: json['hospital_name']?.toString() ?? json['name']?.toString() ?? 'Nasiib Hospital',
      description: json['description']?.toString() ?? '',
      about: json['about']?.toString() ?? '',
      phone: json['phone']?.toString() ?? json['phone_number']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      openingHours: json['opening_hours']?.toString() ?? '24/7 Open',
      emergencyNumber: json['emergency_number']?.toString() ?? '',
      logoUrl: json['logo_url']?.toString() ?? '',
      bannerUrl: json['banner_url']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'hospital_name': hospitalName,
      'description': description,
      'about': about,
      'phone': phone,
      'email': email,
      'address': address,
      'opening_hours': openingHours,
      'emergency_number': emergencyNumber,
      'logo_url': logoUrl,
      'banner_url': bannerUrl,
    };
  }

  HospitalInfoModel copyWith({
    String? id,
    String? hospitalName,
    String? description,
    String? about,
    String? phone,
    String? email,
    String? address,
    String? openingHours,
    String? emergencyNumber,
    String? logoUrl,
    String? bannerUrl,
  }) {
    return HospitalInfoModel(
      id: id ?? this.id,
      hospitalName: hospitalName ?? this.hospitalName,
      description: description ?? this.description,
      about: about ?? this.about,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      openingHours: openingHours ?? this.openingHours,
      emergencyNumber: emergencyNumber ?? this.emergencyNumber,
      logoUrl: logoUrl ?? this.logoUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
    );
  }
}
