class AppointmentModel {
  final String id;
  final String referenceId;
  final String doctorId;
  final String doctorName;
  final String doctorSpecialty;
  final String doctorImageUrl;
  final String hospitalName;
  final String date;
  final String time;
  final String appointmentType; // 'New Patient' or 'Follow-up'
  final String patientName;
  final String patientPhone;
  final int patientAge;
  final String patientGender;
  final String reasonForVisit;
  final String paymentMethod; // 'EVC Plus', 'Zaad', 'Sahal', 'Card', 'Cash'
  final double amount;
  final int queueNumber;
  final String status; // 'Upcoming', 'Confirmed', 'Completed', 'Cancelled'
  final String createdAt;
  final String? prescription; // Added for doctor admin portal prescription writing!
  final String? patientImageUrl; // Added for dynamic patient avatar photo saving!

  AppointmentModel({
    required this.id,
    required this.referenceId,
    required this.doctorId,
    required this.doctorName,
    required this.doctorSpecialty,
    required this.doctorImageUrl,
    this.hospitalName = 'Nasiib Hospital',
    required this.date,
    required this.time,
    required this.appointmentType,
    required this.patientName,
    required this.patientPhone,
    required this.patientAge,
    required this.patientGender,
    required this.reasonForVisit,
    required this.paymentMethod,
    required this.amount,
    required this.queueNumber,
    this.status = 'Confirmed',
    required this.createdAt,
    this.prescription,
    this.patientImageUrl,
  });

  factory AppointmentModel.fromJson(Map<String, dynamic> json) {
    return AppointmentModel(
      id: json['id']?.toString() ?? '',
      referenceId: json['reference_id'] ?? json['referenceId'] ?? '#APT78542',
      doctorId: json['doctor_id'] ?? json['doctorId'] ?? '',
      doctorName: json['doctor_name'] ?? json['doctorName'] ?? '',
      doctorSpecialty: json['doctor_specialty'] ?? json['doctorSpecialty'] ?? '',
      doctorImageUrl: json['doctor_image_url'] ?? json['doctorImageUrl'] ?? '',
      hospitalName: json['hospital_name'] ?? json['hospitalName'] ?? 'Nasiib Hospital',
      date: json['date'] ?? '',
      time: json['time'] ?? '',
      appointmentType: json['appointment_type'] ?? json['appointmentType'] ?? 'New Patient',
      patientName: json['patient_name'] ?? json['patientName'] ?? '',
      patientPhone: json['patient_phone'] ?? json['patientPhone'] ?? '',
      patientAge: json['patient_age'] ?? json['patientAge'] ?? 24,
      patientGender: json['patient_gender'] ?? json['patientGender'] ?? 'Male',
      reasonForVisit: json['reason_for_visit'] ?? json['reasonForVisit'] ?? json['reason'] ?? '',
      paymentMethod: json['payment_method'] ?? json['paymentMethod'] ?? 'EVC Plus',
      amount: (json['amount'] ?? json['consultation_fee'] ?? json['fee'] as num?)?.toDouble() ?? 15.0,
      queueNumber: json['queue_number'] ?? json['queueNumber'] ?? 1,
      status: json['status'] ?? 'Confirmed',
      createdAt: json['created_at'] ?? json['createdAt'] ?? DateTime.now().toIso8601String(),
      prescription: json['prescription']?.toString(),
      patientImageUrl: json['patient_image'] ?? json['patient_avatar_url'] ?? json['patient_image_url'] ?? json['patientImageUrl'] ?? json['avatar_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reference_id': referenceId,
      'doctor_id': doctorId,
      'doctor_name': doctorName,
      'doctor_specialty': doctorSpecialty,
      'doctor_image_url': doctorImageUrl,
      'hospital_name': hospitalName,
      'date': date,
      'time': time,
      'appointment_type': appointmentType,
      'patient_name': patientName,
      'patient_phone': patientPhone,
      'patient_age': patientAge,
      'patient_gender': patientGender,
      'reason_for_visit': reasonForVisit,
      'payment_method': paymentMethod,
      'amount': amount,
      'queue_number': queueNumber,
      'status': status,
      'created_at': createdAt,
      'prescription': prescription,
      'patient_image': patientImageUrl,
      'patient_avatar_url': patientImageUrl,
    };
  }

  AppointmentModel copyWith({
    String? id,
    String? referenceId,
    String? doctorId,
    String? doctorName,
    String? doctorSpecialty,
    String? doctorImageUrl,
    String? hospitalName,
    String? date,
    String? time,
    String? appointmentType,
    String? patientName,
    String? patientPhone,
    int? patientAge,
    String? patientGender,
    String? reasonForVisit,
    String? paymentMethod,
    double? amount,
    int? queueNumber,
    String? status,
    String? createdAt,
    String? prescription,
    String? patientImageUrl,
  }) {
    return AppointmentModel(
      id: id ?? this.id,
      referenceId: referenceId ?? this.referenceId,
      doctorId: doctorId ?? this.doctorId,
      doctorName: doctorName ?? this.doctorName,
      doctorSpecialty: doctorSpecialty ?? this.doctorSpecialty,
      doctorImageUrl: doctorImageUrl ?? this.doctorImageUrl,
      hospitalName: hospitalName ?? this.hospitalName,
      date: date ?? this.date,
      time: time ?? this.time,
      appointmentType: appointmentType ?? this.appointmentType,
      patientName: patientName ?? this.patientName,
      patientPhone: patientPhone ?? this.patientPhone,
      patientAge: patientAge ?? this.patientAge,
      patientGender: patientGender ?? this.patientGender,
      reasonForVisit: reasonForVisit ?? this.reasonForVisit,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      amount: amount ?? this.amount,
      queueNumber: queueNumber ?? this.queueNumber,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      prescription: prescription ?? this.prescription,
      patientImageUrl: patientImageUrl ?? this.patientImageUrl,
    );
  }
}
