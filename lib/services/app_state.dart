import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/doctor_model.dart';
import '../models/appointment_model.dart';
import '../models/medicine_model.dart';
import '../models/user_model.dart';
import '../models/cart_item_model.dart';
import '../models/nurse_model.dart';
import '../models/specialty_model.dart';
import '../models/hospital_service_model.dart';
import '../models/hospital_info_model.dart';
import '../models/banner_model.dart';
import 'supabase_service.dart';
import 'encryption_service.dart';
import 'fcm_sender.dart';
import 'push_notification_service.dart';

class AppState extends ChangeNotifier {
  AppState() {
    _loadDoctorSettingsFromPrefs();
    _loadProfileFromPrefs();
    _loadCartFromPrefs();
    _loadDataFromSupabase();
    loadNotificationsFromSupabase();
  }

  final Set<String> _verifiedDoctorIds = {};
  final Map<String, bool> _doctorAvailabilityMap = {};

  final List<DoctorModel> _customDoctors = [];
  final List<DoctorModel> _doctors = [];
  final List<NurseModel> _nurses = [];

  Future<void> _saveCustomDoctorsToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listMap = _customDoctors.map((d) => d.toJson()).toList();
      await prefs.setString('saved_custom_doctors_v1', jsonEncode(listMap));
    } catch (e) {
      debugPrint("Error saving custom doctors: $e");
    }
  }

  Future<void> _loadCustomDoctorsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey('saved_custom_doctors_v1')) {
        final jsonStr = prefs.getString('saved_custom_doctors_v1');
        if (jsonStr != null) {
          final List<dynamic> list = jsonDecode(jsonStr);
          _customDoctors.clear();
          for (var map in list) {
            final doc = DoctorModel.fromJson(Map<String, dynamic>.from(map));
            _customDoctors.add(doc);
            if (!_doctors.any((d) => d.id == doc.id)) {
              _doctors.insert(0, doc);
            }
          }
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("Error loading custom doctors: $e");
    }
  }

  Future<void> _loadDoctorSettingsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey('saved_global_online_status_v1')) {
        _globalDoctorOnlineStatus =
            prefs.getBool('saved_global_online_status_v1') ?? true;
      }
      final savedVerified = prefs.getStringList('saved_verified_doctor_ids_v2');
      if (savedVerified != null) {
        _verifiedDoctorIds.addAll(savedVerified);
      }
      final savedAvailJson = prefs.getString(
        'saved_doctor_availability_map_v2',
      );
      if (savedAvailJson != null) {
        final Map<String, dynamic> map = jsonDecode(savedAvailJson);
        map.forEach((k, v) {
          _doctorAvailabilityMap[k] = v == true;
        });
      }
      _applyDoctorSettingsToMemory();
      await _loadCustomDoctorsFromPrefs();
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading doctor settings from SharedPreferences: $e");
    }
  }

  Future<void> _saveDoctorSettingsToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        'saved_global_online_status_v1',
        _globalDoctorOnlineStatus,
      );
      await prefs.setStringList(
        'saved_verified_doctor_ids_v2',
        _verifiedDoctorIds.toList(),
      );
      await prefs.setString(
        'saved_doctor_availability_map_v2',
        jsonEncode(_doctorAvailabilityMap),
      );
    } catch (e) {
      debugPrint("Error saving doctor settings to SharedPreferences: $e");
    }
  }

  void _applyDoctorSettingsToMemory() {
    for (int i = 0; i < _doctors.length; i++) {
      final doc = _doctors[i];
      final bool isV = _verifiedDoctorIds.contains(doc.id) || doc.isVerified;
      final bool isA =
          _doctorAvailabilityMap[doc.id] ?? _globalDoctorOnlineStatus;
      if (isV) {
        _verifiedDoctorIds.add(doc.id);
      }
      _doctorAvailabilityMap[doc.id] = isA;
      _doctors[i] = doc.copyWith(isVerified: isV, isAvailable: isA);
    }
  }

  Future<void> _loadProfileFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isLoggedIn = prefs.getBool('is_logged_in_v1') ?? (FirebaseAuth.instance.currentUser != null);
      if (_isLoggedIn && prefs.containsKey('user_profile_v1')) {
        final jsonStr = prefs.getString('user_profile_v1');
        if (jsonStr != null) {
          final map = jsonDecode(jsonStr);
          _currentUser = UserModel.fromJson(Map<String, dynamic>.from(map));
        }
      } else if (!_isLoggedIn) {
        _currentUser = null;
      }
      final savedAvatar = prefs.getString('saved_user_avatar_v1');
      if (savedAvatar != null &&
          savedAvatar.isNotEmpty &&
          _currentUser != null) {
        _currentUser = _currentUser!.copyWith(avatarUrl: savedAvatar);
      }

      // Auto-subscribe this device to user's private notification topics
      if (_currentUser != null) {
        PushNotificationService.instance.subscribeToUserTopic(_currentUser!.id);
        if (_currentUser!.phoneNumber.isNotEmpty) {
          PushNotificationService.instance.subscribeToUserTopic(_currentUser!.phoneNumber);
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint("Error loading profile from SharedPreferences: $e");
    }
  }

  Future<void> _saveProfileToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in_v1', _isLoggedIn);
      if (_currentUser != null) {
        await prefs.setString(
          'user_profile_v1',
          jsonEncode(_currentUser!.toJson()),
        );
        if (_currentUser!.avatarUrl.isNotEmpty) {
          await prefs.setString(
            'saved_user_avatar_v1',
            _currentUser!.avatarUrl,
          );
        }
      } else {
        await prefs.remove('user_profile_v1');
        await prefs.remove('saved_user_avatar_v1');
      }
    } catch (e) {
      debugPrint("Error saving profile to SharedPreferences: $e");
    }
  }

  Future<void> _loadCartFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey('permanent_cart_items_v1')) {
        final String? jsonStr = prefs.getString('permanent_cart_items_v1');
        if (jsonStr != null && jsonStr.trim() != '[]' && jsonStr.trim().isNotEmpty) {
          final List<dynamic> list = jsonDecode(jsonStr);
          if (list.isNotEmpty) {
            _cartItems.clear();
            for (var itemMap in list) {
              _cartItems.add(
                CartItemModel.fromJson(Map<String, dynamic>.from(itemMap)),
              );
            }
            notifyListeners();
          }
        }
      } else {
        _saveCartToPrefs();
      }
    } catch (e) {
      debugPrint("Error loading cart from SharedPreferences: $e");
    }
  }

  Future<void> _saveCartToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listMap = _cartItems.map((item) => item.toJson()).toList();
      await prefs.setString('permanent_cart_items_v1', jsonEncode(listMap));
    } catch (e) {
      debugPrint("Error saving cart to SharedPreferences: $e");
    }
  }

  Future<void> fetchDoctors() async {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) {
      debugPrint("[DOCTORS] Supabase client unavailable or not initialized.");
      return;
    }

    try {
      debugPrint(
        "[DOCTORS] Fetch started from Supabase target: ${SupabaseService.instance.supabaseUrl}",
      );
      final doctorsData = await client.from('doctors').select();
      debugPrint(
        "[DOCTORS] Supabase returned ${doctorsData.length} records from doctors table.",
      );

      if (doctorsData.isNotEmpty) {
        final List<DoctorModel> parsed = [];
        for (var d in doctorsData) {
          final doc = DoctorModel.fromJson(d);
          debugPrint(
            "[DOCTORS] Loaded Doctor from DB: ID=${doc.id}, Name=${doc.name}, Specialty=${doc.specialty}, isAvailable=${doc.isAvailable}",
          );

          final String rawImg = doc.imageUrl.trim();
          String validImg = (rawImg.isNotEmpty && rawImg != 'null')
              ? rawImg
              : '';
          if (validImg.startsWith('data:image')) {
            debugPrint(
              "[DOCTORS] Found legacy Base64 string in DB row ID=${doc.id}. Sanitizing for egress safety.",
            );
            validImg = '';
          }

          final bool statusBool =
              (d['is_online'] == true || d['is_online']?.toString() == 'true');
          final updatedDoc = doc.copyWith(
            imageUrl: validImg,
            isOnline: statusBool,
            isAvailable: statusBool,
          );

          // Exclude any legacy nurse rows from doctors list
          if (!updatedDoc.specialty.toLowerCase().contains('kalkaaliso') &&
              !updatedDoc.specialty.toLowerCase().contains('nurse')) {
            parsed.add(updatedDoc);
          }
        }
        if (parsed.isNotEmpty) {
          _doctors.clear();
          _doctors.addAll(parsed);
        }
      } else {
        debugPrint(
          "[DOCTORS] Notice: doctors table returned 0 rows (check database entries or RLS SELECT policies). Preserving fallback list.",
        );
      }

      // Fetch dedicated 'nurses' table in Supabase DB
      try {
        final nursesData = await client.from('nurses').select();
        _nurses.clear();
        if (nursesData.isNotEmpty) {
          for (var n in nursesData) {
            final String nurseId = n['id']?.toString() ?? '';
            final String nurseName = n['name']?.toString() ?? '';
            if (nurseId.isNotEmpty && nurseName.isNotEmpty) {
              _nurses.add(
                NurseModel(
                  id: nurseId,
                  name: nurseName,
                  specialty: n['specialty'] ?? 'Kalkaaliso',
                  imageUrl: n['image_url'] ?? n['imageUrl'] ?? '',
                ),
              );
            }
          }
        }
      } catch (nurseErr) {
        debugPrint("[NURSES] Dedicated nurses table fetch notice: $nurseErr");
      }

      // Merge any nurse records from doctors table into _nurses list
      if (doctorsData.isNotEmpty) {
        for (var d in doctorsData) {
          final String spec = (d['specialty'] ?? '').toString().toLowerCase();
          if (spec.contains('kalkaaliso') || spec.contains('nurse')) {
            final String nId = d['id']?.toString() ?? '';
            final String nName = d['name']?.toString() ?? '';
            if (nId.isNotEmpty &&
                nName.isNotEmpty &&
                !_nurses.any((n) => n.id == nId || n.name == nName)) {
              _nurses.add(
                NurseModel(
                  id: nId,
                  name: nName,
                  specialty: d['specialty']?.toString() ?? 'Kalkaaliso',
                  imageUrl: d['image_url']?.toString() ?? '',
                ),
              );
            }
          }
        }
      }

      debugPrint(
        "[DOCTORS] Final _doctors count: ${_doctors.length}. Calling notifyListeners()",
      );
      notifyListeners();
    } catch (e) {
      debugPrint("[DOCTORS] Fetch error from Supabase: $e");
    }
  }

  Future<void> fetchMedicines() async {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) return;

    try {
      final medicinesData = await client.from('medicines').select();
      if (medicinesData.isNotEmpty) {
        final List<MedicineModel> parsedMeds = [];
        for (var m in medicinesData) {
          parsedMeds.add(
            MedicineModel.fromJson(Map<String, dynamic>.from(m)),
          );
        }
        _medicines.clear();
        _medicines.addAll(parsedMeds);
        notifyListeners();
        debugPrint('[MEDICINES] fetchMedicines → ${_medicines.length} items loaded');
      }
    } catch (medErr) {
      debugPrint('[MEDICINES] Supabase fetch error: $medErr');
    }
  }

  Future<void> fetchNurses() async {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) return;

    try {
      final response = await client.from('nurses').select().order('created_at', ascending: false);
      _nurses.clear();
      if (response.isNotEmpty) {
        for (var n in response) {
          final String nurseId = n['id']?.toString() ?? '';
          final String nurseName = n['name']?.toString() ?? '';
          if (nurseId.isNotEmpty && nurseName.isNotEmpty) {
            _nurses.add(NurseModel.fromJson(Map<String, dynamic>.from(n)));
          }
        }
      }
      notifyListeners();
      debugPrint('⚡ [NURSES] fetchNurses → ${_nurses.length} nurses loaded');
    } catch (e) {
      debugPrint('Error fetching nurses: $e');
      try {
        final response = await client.from('nurses').select();
        _nurses.clear();
        if (response.isNotEmpty) {
          for (var n in response) {
            final String nurseId = n['id']?.toString() ?? '';
            final String nurseName = n['name']?.toString() ?? '';
            if (nurseId.isNotEmpty && nurseName.isNotEmpty) {
              _nurses.add(NurseModel.fromJson(Map<String, dynamic>.from(n)));
            }
          }
        }
        notifyListeners();
        debugPrint('⚡ [NURSES] fetchNurses fallback → ${_nurses.length} nurses loaded');
      } catch (fallbackErr) {
        debugPrint('Error fetching nurses fallback: $fallbackErr');
      }
    }
  }

  void listenToRealtimeAdminChanges() {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) return;

    // A. Live sync for Medicines (Dawooyinka)
    client
        .channel('public:medicines_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'medicines',
          callback: (payload) async {
            debugPrint('Medicines table changed: ${payload.eventType}');
            await fetchMedicines();
            notifyListeners();
          },
        )
        .subscribe();

    // B. Live sync for Doctors (Dhaqaatiirta)
    client
        .channel('public:doctors_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'doctors',
          callback: (payload) async {
            debugPrint('Doctors table changed: ${payload.eventType}');
            await fetchDoctors();
            notifyListeners();
          },
        )
        .subscribe();

    // C. Live sync for Nurses (Kalkaaliyaasha)
    client
        .channel('nurses-realtime-channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'nurses',
          callback: (payload) async {
            debugPrint('⚡ [REALTIME] Nurses table changed (${payload.eventType}). Refetching...');
            await fetchNurses();
          },
        )
        .subscribe((status, [error]) {
          debugPrint('⚡ [REALTIME STATUS] Nurses subscription: $status, error: $error');
        });
  }

  Future<void> _loadDataFromSupabase() async {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) {
      debugPrint(
        "AppState: Supabase client not initialized or offline. Using local store.",
      );
      return;
    }

    try {
      // 1. Fetch Doctors & Nurses
      await fetchDoctors();

      // Subscribe to Realtime Doctor Changes (INSERT, UPDATE, DELETE)
      try {
        client
            .channel('public:doctors_realtime_all')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'doctors',
              callback: (payload) {
                debugPrint(
                  "[DOCTORS_REALTIME] Postgres event received on doctors table: ${payload.eventType}",
                );
                fetchDoctors();
              },
            )
            .subscribe();
      } catch (e) {
        debugPrint("Notice subscribing to doctors realtime: $e");
      }

      // 2. Fetch Medicines
      try {
        final medicinesData = await client.from('medicines').select();
        if (medicinesData.isNotEmpty) {
          final List<MedicineModel> parsedMeds = [];
          for (var m in medicinesData) {
            parsedMeds.add(
              MedicineModel.fromJson(Map<String, dynamic>.from(m)),
            );
          }
          if (parsedMeds.isNotEmpty) {
            _medicines.clear();
            _medicines.addAll(parsedMeds);
          }
        }
      } catch (medErr) {
        debugPrint("[MEDICINES] Supabase fetch notice: $medErr");
      }

      // 3. Fetch Appointments
      final appointmentsData = await client.from('appointments').select();
      if (appointmentsData.isNotEmpty) {
        _appointments.clear();
        for (var a in appointmentsData) {
          _appointments.add(
            AppointmentModel(
              id: a['id'].toString(),
              referenceId: a['reference_id'] ?? '',
              doctorId: a['doctor_id']?.toString() ?? '',
              doctorName: a['doctor_name'] ?? '',
              doctorSpecialty: a['doctor_specialty'] ?? '',
              doctorImageUrl: '',
              hospitalName: 'Nasiib Hospital',
              date: a['date'] ?? '',
              time: a['time'] ?? '',
              appointmentType: a['appointment_type'] ?? 'New Patient',
              patientName: a['patient_name'] ?? '',
              patientPhone: a['patient_phone'] ?? '',
              patientAge: a['patient_age'] ?? 20,
              patientGender: a['patient_gender'] ?? 'Male',
              reasonForVisit: a['reason'] ?? '',
              paymentMethod: a['payment_method'] ?? 'EVC Plus',
              amount: (a['amount'] as num?)?.toDouble() ?? 10.0,
              queueNumber: a['queue_number'] ?? 1,
              status: a['status'] ?? 'Upcoming',
              createdAt: a['created_at'] ?? '',
              patientImageUrl: a['patient_image'] ?? a['patient_avatar_url'] ?? a['patient_image_url'],
            ),
          );
        }
      }

      // 4. Fetch Announcements / Notifications
      final notificationsData = await client
          .from('notifications')
          .select()
          .order('created_at', ascending: false);

      final prefs = await SharedPreferences.getInstance();
      final savedReadIds = prefs.getStringList('read_notification_ids_v1') ?? [];
      _readNotificationIds.addAll(savedReadIds);

      _notifications.clear();
      for (var n in notificationsData) {
        String displayTime = 'Just now';
        if (n['created_at'] != null) {
          try {
            final dt = DateTime.parse(n['created_at'].toString()).toLocal();
            final day = dt.day.toString().padLeft(2, '0');
            final months = [
              'Jan',
              'Feb',
              'Mar',
              'Apr',
              'May',
              'Jun',
              'Jul',
              'Aug',
              'Sep',
              'Oct',
              'Nov',
              'Dec',
            ];
            final month = months[dt.month - 1];
            final hourNum = dt.hour > 12
                ? (dt.hour - 12)
                : (dt.hour == 0 ? 12 : dt.hour);
            final minute = dt.minute.toString().padLeft(2, '0');
            final ampm = dt.hour >= 12 ? 'PM' : 'AM';
            displayTime = '$day $month, $hourNum:$minute $ampm';
          } catch (e) {
            displayTime = n['created_at'].toString();
          }
        }

        final String nId = n['id'].toString();
        final bool isRead = _readNotificationIds.contains(nId);

        _notifications.add({
          'id': nId,
          'title': n['title'] ?? '',
          'body': n['body'] ?? '',
          'time': displayTime,
          'sender': n['sender_label'] ?? n['sender'] ?? 'Nasiib Hospital',
          'isRead': isRead,
        });
      }

      // Fetch Patients (Select only standard existing columns to avoid PGRST204 schema cache errors)
      try {
        final patientsData = await client
            .from('patients')
            .select('id, full_name, phone_number, email, avatar_url');
        _dbPatients = List<Map<String, dynamic>>.from(patientsData);
      } catch (e) {
        debugPrint("Failed to fetch patients initially: $e");
        // Fallback fetch all
        try {
          final patientsData = await client.from('patients').select();
          _dbPatients = List<Map<String, dynamic>>.from(patientsData);
        } catch (err) {
          debugPrint("Failed fallback patients fetch: $err");
        }
      }

      // 5. Fetch Messages
      try {
        final messagesData = await client
            .from('messages')
            .select()
            .order('created_at', ascending: true);
        _chatMessages.clear();
        for (var msg in messagesData) {
          final rawText = (msg['message'] ?? msg['text'] ?? msg['content'] ?? '').toString();
          final decryptedText = EncryptionService.decrypt(rawText);

          _chatMessages.add({
            'id': msg['id'].toString(),
            'sender_id': msg['sender_id'] ?? '',
            'sender_name': msg['sender_name'] ?? '',
            'text': decryptedText,
            'image_url': msg['image_url'] ?? '',
            'patient_id': msg['patient_id'] ?? '',
            'doctor_id': msg['doctor_id'] ?? '',
            'doctor_name': msg['doctor_name'] ?? '',
            'time': msg['created_at'] != null
                ? msg['created_at'].toString()
                : '',
            'is_read': msg['is_read'] ?? false,
          });
        }
      } catch (err) {
        debugPrint("Failed to fetch messages from Supabase: $err");
      }

      // 6. Fetch Specialties
      try {
        final specialtiesData = await client.from('specialties').select();
        _specialties.clear();
        for (var s in specialtiesData) {
          _specialties.add(SpecialtyModel.fromJson(s));
        }
      } catch (err) {
        debugPrint("Notice fetching specialties: $err");
      }

      // 7. Initial Fetch of Orders & Order Items
      try {
        final ordersData = await client
            .from('orders')
            .select()
            .order('created_at', ascending: false);
        final itemsData = await client.from('order_items').select();

        _orders = List<Map<String, dynamic>>.from(ordersData);
        _orderItems = List<Map<String, dynamic>>.from(itemsData);
      } catch (err) {
        debugPrint("Notice fetching initial orders: $err");
      }

      // 8. Subscribe to True Supabase Realtime Event Channels
      initRealtimeSubscriptions();
      listenToRealtimeAdminChanges();

      notifyListeners();
      debugPrint("AppState: Synced successfully with Supabase Realtime!");
    } catch (e) {
      debugPrint("AppState: Supabase sync error: $e");
    }
  }

  // Navigation & User State
  bool _isLoggedIn = false;
  bool _isAdminMode = false;
  int _currentPatientNavIndex =
      0; // 0: Home, 1: Pharmacy, 2: Message, 3: Profile
  String _selectedSpecialty = 'All';

  String get selectedSpecialty => _selectedSpecialty;

  UserModel? _currentUser;

  // Nurses List getter
  List<NurseModel> get nurses => _nurses;

  // Dynamic Specialties
  final List<SpecialtyModel> _specialties = [];
  List<SpecialtyModel> get specialties =>
      _specialties.where((s) => s.isActive).toList();
  List<SpecialtyModel> get allSpecialties => List.unmodifiable(_specialties);

  void addSpecialty(SpecialtyModel s) {
    _specialties.insert(0, s);
    notifyListeners();
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      client
          .from('specialties')
          .insert(s.toJson())
          .catchError((e) => debugPrint("Add specialty error: $e"));
    }
  }

  void updateSpecialty(SpecialtyModel s) {
    final idx = _specialties.indexWhere((item) => item.id == s.id);
    if (idx != -1) {
      _specialties[idx] = s;
      notifyListeners();
      final client = SupabaseService.instance.client;
      if (client != null && SupabaseService.instance.isInitialized) {
        client
            .from('specialties')
            .update(s.toJson())
            .eq('id', s.id)
            .catchError((e) => debugPrint("Update specialty error: $e"));
      }
    }
  }

  void deleteSpecialty(String id) {
    _specialties.removeWhere((s) => s.id == id);
    notifyListeners();
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      client
          .from('specialties')
          .delete()
          .eq('id', id)
          .catchError((e) => debugPrint("Delete specialty error: $e"));
    }
  }

  // Dynamic Hospital Services
  final List<HospitalServiceModel> _hospitalServices = [];
  List<HospitalServiceModel> get hospitalServices =>
      _hospitalServices.where((s) => s.isActive).toList();
  List<HospitalServiceModel> get allHospitalServices =>
      List.unmodifiable(_hospitalServices);

  void addService(HospitalServiceModel s) {
    _hospitalServices.insert(0, s);
    notifyListeners();
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      client
          .from('services')
          .insert(s.toJson())
          .catchError((e) => debugPrint("Add service error: $e"));
    }
  }

  void updateService(HospitalServiceModel s) {
    final idx = _hospitalServices.indexWhere((item) => item.id == s.id);
    if (idx != -1) {
      _hospitalServices[idx] = s;
      notifyListeners();
      final client = SupabaseService.instance.client;
      if (client != null && SupabaseService.instance.isInitialized) {
        client
            .from('services')
            .update(s.toJson())
            .eq('id', s.id)
            .catchError((e) => debugPrint("Update service error: $e"));
      }
    }
  }

  void deleteService(String id) {
    _hospitalServices.removeWhere((s) => s.id == id);
    notifyListeners();
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      client
          .from('services')
          .delete()
          .eq('id', id)
          .catchError((e) => debugPrint("Delete service error: $e"));
    }
  }

  // Dynamic Hospital Profile Info Settings
  HospitalInfoModel _hospitalInfo = HospitalInfoModel();
  HospitalInfoModel get hospitalInfo => _hospitalInfo;

  void updateHospitalInfo(HospitalInfoModel info) {
    _hospitalInfo = info;
    notifyListeners();
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      client
          .from('hospital_info')
          .upsert(info.toJson())
          .catchError((e) => debugPrint("Update hospital_info error: $e"));
    }
  }

  // Dynamic Banners
  final List<BannerModel> _banners = [];
  List<BannerModel> get banners => _banners.where((b) => b.isActive).toList();
  List<BannerModel> get allBanners => List.unmodifiable(_banners);

  void addBanner(BannerModel b) {
    _banners.insert(0, b);
    notifyListeners();
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      client
          .from('banners')
          .insert(b.toJson())
          .catchError((e) => debugPrint("Add banner error: $e"));
    }
  }

  void updateBanner(BannerModel b) {
    final idx = _banners.indexWhere((item) => item.id == b.id);
    if (idx != -1) {
      _banners[idx] = b;
      notifyListeners();
      final client = SupabaseService.instance.client;
      if (client != null && SupabaseService.instance.isInitialized) {
        client
            .from('banners')
            .update(b.toJson())
            .eq('id', b.id)
            .catchError((e) => debugPrint("Update banner error: $e"));
      }
    }
  }

  void deleteBanner(String id) {
    _banners.removeWhere((b) => b.id == id);
    notifyListeners();
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      client
          .from('banners')
          .delete()
          .eq('id', id)
          .catchError((e) => debugPrint("Delete banner error: $e"));
    }
  }

  String? lastNurseError;

  Future<bool> addNurse(NurseModel nurse, {Uint8List? imageBytes}) async {
    lastNurseError = null;
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) {
      lastNurseError = "Supabase client offline or uninitialized.";
      debugPrint("[NURSES_ADD] Error: $lastNurseError");
      return false;
    }

    try {
      // 1. Upload binary nurse image bytes to Supabase Storage 'nurses' bucket
      String finalImageUrl = nurse.imageUrl;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        debugPrint(
          "[NURSES_ADD] Uploading nurse profile image to Supabase Storage 'nurses' bucket...",
        );
        try {
          final uploadedUrl = await SupabaseService.instance.uploadNurseImage(
            imageBytes,
            nurseId: nurse.id,
          );
          if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
            finalImageUrl = uploadedUrl;
            debugPrint(
              "[NURSES_ADD] Storage upload SUCCESS: URL=$finalImageUrl",
            );
          }
        } catch (imgErr) {
          debugPrint("[NURSES_ADD] Storage upload error: $imgErr");
        }
      }

      final String cleanNum = nurse.id.replaceAll(RegExp(r'[^0-9]'), '');
      final String dbId = cleanNum.isNotEmpty
          ? cleanNum
          : (DateTime.now().millisecondsSinceEpoch % 2147483647).toString();

      // 2. Prepare exact clean payload matching public.nurses schema: id, name, specialty, hospital, image_url
      final Map<String, dynamic> nursePayload = {
        'id': dbId,
        'name': nurse.name.trim(),
        'specialty': nurse.specialty.isNotEmpty
            ? nurse.specialty.trim()
            : 'Kalkaaliso',
        'role': nurse.specialty.isNotEmpty ? nurse.specialty.trim() : 'Kalkaaliso',
        'fee': nurse.fee,
        'visit_fee': nurse.fee,
        'discount_fee': nurse.discountFee,
        'hospital': 'Nasiib Hospital',
        'image_url': finalImageUrl,
      };

      debugPrint(
        "[NURSES_ADD] Executing DB INSERT into public.nurses table with payload: $nursePayload",
      );

      bool insertSuccess = false;

      // Attempt 1: Standard insert into public.nurses table
      try {
        await client.from('nurses').insert(nursePayload);
        insertSuccess = true;
        lastNurseError = null;
        debugPrint(
          "[NURSES_ADD] DB INSERT into public.nurses SUCCEEDED for nurse ID=$dbId!",
        );
      } catch (e1) {
        debugPrint("[NURSES_ADD] Primary insert error: $e1");
        if (e1 is PostgrestException) {
          lastNurseError =
              "[Code: ${e1.code}] ${e1.message} ${e1.details ?? ''} ${e1.hint ?? ''}";
        } else {
          lastNurseError = e1.toString();
        }

        // Attempt 2: Try without hospital column if column missing in Supabase schema
        try {
          final Map<String, dynamic> altPayload = Map<String, dynamic>.from(nursePayload);
          altPayload.remove('hospital');
          await client.from('nurses').insert(altPayload);
          insertSuccess = true;
          lastNurseError = null;
          debugPrint(
            "[NURSES_ADD] Alt DB INSERT into public.nurses SUCCEEDED!",
          );
        } catch (e2) {
          debugPrint("[NURSES_ADD] Alt insert error: $e2");
          if (e2 is PostgrestException) {
            lastNurseError =
                "[Code: ${e2.code}] ${e2.message} ${e2.details ?? ''} ${e2.hint ?? ''}";
          }
        }
      }

      if (insertSuccess) {
        await fetchNurses();
        return true;
      } else {
        return false;
      }
    } catch (e) {
      lastNurseError = e.toString();
      debugPrint("[NURSES_ADD] Exception creating nurse in Supabase DB: $e");
      return false;
    }
  }

  Future<void> deleteNurse(String id) async {
    final NurseModel? targetNurse = _nurses.cast<NurseModel?>().firstWhere(
      (n) => n?.id == id,
      orElse: () => null,
    );
    final String targetName = targetNurse?.name.trim() ?? '';
    final String cleanNum = id.replaceAll(RegExp(r'[^0-9]'), '');
    final int? intId = int.tryParse(cleanNum);

    // Remove from memory state immediately
    _nurses.removeWhere(
      (n) =>
          n.id == id ||
          (targetName.isNotEmpty &&
              n.name.trim().toLowerCase() == targetName.toLowerCase()),
    );
    notifyListeners();

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        await client.from('nurses').delete().eq('id', id);
        if (intId != null) {
          await client.from('nurses').delete().eq('id', intId);
        }
        if (targetName.isNotEmpty) {
          await client.from('nurses').delete().eq('name', targetName);
        }
        debugPrint(
          "[NURSE_DELETE] Nurse '$targetName' (ID=$id) deleted from nurses DB.",
        );
      } catch (e) {
        debugPrint("[NURSE_DELETE] Delete nurse error from Supabase: $e");
      }
    }

    // Re-sync from Supabase DB to confirm state
    await fetchNurses();
    notifyListeners();
  }

  Future<bool> updateNurse(NurseModel nurse, {Uint8List? newImageBytes}) async {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) {
      final index = _nurses.indexWhere((n) => n.id == nurse.id);
      if (index != -1) {
        _nurses[index] = nurse;
        notifyListeners();
      }
      return true;
    }

    try {
      String finalImageUrl = nurse.imageUrl;
      if (newImageBytes != null && newImageBytes.isNotEmpty) {
        final uploadedUrl = await SupabaseService.instance.uploadNurseImage(
          newImageBytes,
          nurseId: nurse.id,
        );
        if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
          finalImageUrl = uploadedUrl;
        }
      }

      final updatedNurse = nurse.copyWith(imageUrl: finalImageUrl);

      final Map<String, dynamic> nursePayload = {
        'name': updatedNurse.name,
        'specialty': updatedNurse.specialty,
        'role': updatedNurse.specialty,
        'fee': updatedNurse.fee,
        'visit_fee': updatedNurse.fee,
        'discount_fee': updatedNurse.discountFee,
        'image_url': finalImageUrl,
      };

      try {
        await client.from('nurses').update(nursePayload).eq('id', updatedNurse.id);
      } catch (e1) {
        debugPrint("[NURSES_UPDATE] Primary update notice: $e1");
        final Map<String, dynamic> altPayload = Map<String, dynamic>.from(nursePayload);
        altPayload.remove('visit_fee');
        altPayload.remove('role');
        try {
          await client.from('nurses').update(altPayload).eq('id', updatedNurse.id);
        } catch (e2) {
          debugPrint("[NURSES_UPDATE] Alt update notice: $e2");
        }
      }

      final index = _nurses.indexWhere((n) => n.id == updatedNurse.id);
      if (index != -1) {
        _nurses[index] = updatedNurse;
      } else {
        _nurses.add(updatedNurse);
      }

      await fetchNurses();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("[NURSES_UPDATE] Update nurse error: $e");
      return false;
    }
  }

  // Appointments List (Populated dynamically from Supabase DB)
  final List<AppointmentModel> _appointments = [];

  // Medicines List (Populated dynamically from Supabase DB)
  final List<MedicineModel> _medicines = [];

  // Shopping Cart List
  final List<CartItemModel> _cartItems = [];

  // Temporary Draft Booking
  AppointmentModel? currentDraftBooking;

  // Notifications List (Populated dynamically from Supabase DB)
  final List<Map<String, dynamic>> _notifications = [];
  final Set<String> _readNotificationIds = {};

  List<Map<String, dynamic>> _dbPatients = [];
  List<Map<String, dynamic>> get dbPatients => _dbPatients;

  final Map<String, bool> _patientsTyping = {};
  bool isPatientTyping(String patientId) => _patientsTyping[patientId] ?? false;
  bool _hasUnreadNotification = false;
  bool _pushNotificationsEnabled = true;

  // Chat Messages List
  final List<Map<String, dynamic>> _chatMessages = [];
  List<Map<String, dynamic>> get chatMessages => _chatMessages;

  // Recycle Bin storage lists
  final List<DoctorModel> _deletedDoctors = [];
  final List<MedicineModel> _deletedMedicines = [];
  final List<AppointmentModel> _deletedAppointments = [];

  List<DoctorModel> get deletedDoctors => _deletedDoctors;
  List<MedicineModel> get deletedMedicines => _deletedMedicines;
  List<AppointmentModel> get deletedAppointments => _deletedAppointments;

  // Getters
  List<Map<String, dynamic>> get notifications => _notifications;
  bool get hasUnreadNotification =>
      unreadNotificationCount > 0 && _pushNotificationsEnabled;
  bool get pushNotificationsEnabled => _pushNotificationsEnabled;

  void setPushNotificationsEnabled(bool enabled) {
    _pushNotificationsEnabled = enabled;
    notifyListeners();
  }

  Future<void> markNotificationsAsRead() async {
    for (var n in _notifications) {
      n['isRead'] = true;
      _readNotificationIds.add(n['id'].toString());
    }
    _hasUnreadNotification = false;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'read_notification_ids_v1',
        _readNotificationIds.toList(),
      );
    } catch (e) {
      debugPrint("[NOTIFICATIONS] Error saving notification read state: $e");
    }
  }

  Future<void> markSingleNotificationAsRead(String id) async {
    _readNotificationIds.add(id);
    for (var n in _notifications) {
      if (n['id'].toString() == id) {
        n['isRead'] = true;
      }
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'read_notification_ids_v1',
        _readNotificationIds.toList(),
      );
    } catch (e) {
      debugPrint("[NOTIFICATIONS] Error saving single notification read state: $e");
    }
  }

  Future<void> loadNotificationsFromSupabase() async {
    try {
      final client = SupabaseService.instance.client;
      if (client != null && SupabaseService.instance.isInitialized) {
        final List<dynamic> response = await client
            .from('notifications')
            .select('*')
            .order('created_at', ascending: false);

        final prefs = await SharedPreferences.getInstance();
        final List<String> savedReadIds = prefs.getStringList('read_notification_ids_v1') ?? [];
        _readNotificationIds.addAll(savedReadIds);

        _notifications.clear();
        final Set<String> seenIds = {};

        for (var item in response) {
          final String id = item['id'].toString();
          if (seenIds.contains(id)) continue;
          seenIds.add(id);

          final String createdAtStr = item['created_at']?.toString() ?? '';
          final bool isRead = _readNotificationIds.contains(id);

          _notifications.add({
            'id': id,
            'title': item['title'] ?? '',
            'body': item['body'] ?? '',
            'time': createdAtStr.isNotEmpty ? createdAtStr.split('T').first : 'Just now',
            'created_at': createdAtStr,
            'sender': item['sender_label'] ?? item['sender'] ?? 'Nasiib Hospital',
            'isRead': isRead,
          });
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint("[NOTIFICATIONS] Error fetching notifications from Supabase: $e");
    }
  }

  int get unreadNotificationCount {
    final Set<String> unreadUniqueIds = {};
    for (var n in _notifications) {
      final String nId = n['id'].toString();
      final isRead = n['isRead'];
      final bool unread = isRead != true && !_readNotificationIds.contains(nId);
      if (unread) {
        unreadUniqueIds.add(nId);
      }
    }
    return unreadUniqueIds.length;
  }

  Future<void> sendAnnouncement(String title, String body) async {
    final id = 'not_${DateTime.now().millisecondsSinceEpoch}';
    if (!_notifications.any((n) => n['id'].toString() == id)) {
      _notifications.insert(0, {
        'id': id,
        'title': title,
        'body': body,
        'time': 'Just now',
        'sender': 'Nasiib Hospital',
        'isRead': false,
      });
    }
    if (_pushNotificationsEnabled) {
      _hasUnreadNotification = true;
    }
    notifyListeners();

    // 1. Await Insert to Supabase public.notifications
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      final String nowIso = DateTime.now().toIso8601String();
      try {
        await client.from('notifications').insert({
          'id': id,
          'title': title,
          'body': body,
          'sender': 'Nasiib Hospital',
          'sender_label': 'Nasiib Hospital',
          'target_user_id': 'all',
          'created_at': nowIso,
        });
        debugPrint("[SUPABASE_NOTIFICATIONS] Announcement successfully saved to Supabase notifications table.");
      } catch (e) {
        debugPrint("[SUPABASE_NOTIFICATIONS] Failed to save announcement to Supabase: $e");
      }
    }
  }

  bool get isLoggedIn => _isLoggedIn;
  bool get isAdminMode => _isAdminMode;
  int get currentPatientNavIndex => _currentPatientNavIndex;

  UserModel? get currentUser => _currentUser;
  List<DoctorModel> get doctors => _doctors;
  List<AppointmentModel> get appointments => _appointments;
  List<MedicineModel> get medicines => _medicines;
  List<CartItemModel> get cartItems => _cartItems;

  int get cartCount => _cartItems.fold(0, (sum, item) => sum + item.quantity);
  double get cartSubtotal =>
      _cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);

  // Cart Actions
  void addToCart(MedicineModel medicine, int quantity) {
    final index = _cartItems.indexWhere(
      (item) => item.medicine.id == medicine.id,
    );
    if (index != -1) {
      _cartItems[index].quantity += quantity;
    } else {
      _cartItems.add(CartItemModel(medicine: medicine, quantity: quantity));
    }
    _saveCartToPrefs();
    notifyListeners();
  }

  void removeFromCart(String medicineId) {
    _cartItems.removeWhere((item) => item.medicine.id == medicineId);
    _saveCartToPrefs();
    notifyListeners();
  }

  void updateCartQuantity(String medicineId, int quantity) {
    final index = _cartItems.indexWhere(
      (item) => item.medicine.id == medicineId,
    );
    if (index != -1) {
      if (quantity <= 0) {
        _cartItems.removeAt(index);
      } else {
        _cartItems[index].quantity = quantity;
      }
      _saveCartToPrefs();
      notifyListeners();
    }
  }

  Future<void> clearCart() async {
    // 1. Wipe in-memory immediately so UI updates right away.
    _cartItems.clear();
    notifyListeners();

    // 2. Wipe ALL possible persistent storage keys asynchronously.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('permanent_cart_items_v1');
      await prefs.remove('cart_items');
      await prefs.remove('cart');
      // Also write an empty list under the primary key to prevent stale
      // data from being re-read on next cold start.
      await prefs.setString('permanent_cart_items_v1', '[]');
      debugPrint('[CART] clearCart() — storage wiped');
    } catch (e) {
      debugPrint('[CART] clearCart() storage error: $e');
    }
  }

  // Navigation & General Actions
  void setPatientNavIndex(int index) {
    _currentPatientNavIndex = index;
    if (index == 0) {
      _selectedSpecialty =
          'All'; // Always show all doctors when returning to Home!
    }
    notifyListeners();
  }

  void setSelectedSpecialty(String specialty) {
    _selectedSpecialty = specialty;
    notifyListeners();
  }

  void resetHomeFilters() {
    _selectedSpecialty = 'All';
    notifyListeners();
  }

  void toggleAdminMode(bool enable) {
    _isAdminMode = enable;
    notifyListeners();
  }

  // Alias used by web admin portal
  void setAdminMode(bool enable) => toggleAdminMode(enable);

  Future<void> logout() async {
    _currentUser = null;
    _isLoggedIn = false;
    _appointments.clear();
    _cartItems.clear();
    _notifications.clear();
    _chatMessages.clear();
    _currentPatientNavIndex = 0;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint("Firebase signOut error: $e");
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await prefs.setBool('is_logged_in_v1', false);
    } catch (e) {
      debugPrint("Prefs clear error: $e");
    }
    notifyListeners();
  }

  Future<void> deleteUserAccount([String? phoneNumber]) async {
    final targetPhone = phoneNumber ?? _currentUser?.phoneNumber ?? '';
    final String cleanPhone = targetPhone.replaceAll(RegExp(r'[\s\-()]+'), '');
    final String fullE164 = cleanPhone.startsWith('+')
        ? cleanPhone
        : (cleanPhone.isNotEmpty ? '+252${cleanPhone.replaceAll(RegExp(r'^252|^0'), '')}' : '');
    final String digitsOnly = fullE164.replaceAll('+252', '');
    final possibleFormats = [
      fullE164,
      digitsOnly,
      '0$digitsOnly',
      _currentUser?.id ?? '',
      _currentUser?.email ?? '',
      _currentUser?.fullName ?? '',
    ].where((s) => s.isNotEmpty).toList();

    // 1. Permanently delete from Firebase Firestore & Auth
    try {
      for (final id in possibleFormats) {
        if (id.isNotEmpty) {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(id)
                .delete()
                .timeout(const Duration(seconds: 2));
          } catch (_) {}
        }
      }
      if (possibleFormats.isNotEmpty) {
        try {
          final q1 = await FirebaseFirestore.instance
              .collection('users')
              .where('phoneNumber', whereIn: possibleFormats)
              .get()
              .timeout(const Duration(seconds: 2));
          for (final doc in q1.docs) {
            await doc.reference.delete().timeout(const Duration(seconds: 2));
          }
        } catch (_) {}
        try {
          final q2 = await FirebaseFirestore.instance
              .collection('users')
              .where('phone_number', whereIn: possibleFormats)
              .get()
              .timeout(const Duration(seconds: 2));
          for (final doc in q2.docs) {
            await doc.reference.delete().timeout(const Duration(seconds: 2));
          }
        } catch (_) {}
      }

      final currentFbUser = FirebaseAuth.instance.currentUser;
      if (currentFbUser != null) {
        try {
          await currentFbUser.delete().timeout(const Duration(seconds: 2));
        } catch (e) {
          debugPrint("[FIRESTORE_AUTH] User delete auth notice: $e");
        }
      }
      debugPrint("[FIRESTORE_AUTH] Permanently deleted user from Firebase Auth & Firestore.");
    } catch (e) {
      debugPrint("[FIRESTORE_AUTH] Delete user error: $e");
    }

    // 2. Permanently delete from Supabase patients table & Storage
    try {
      await SupabaseService.instance
          .deleteUserData(
            fullE164.isNotEmpty ? fullE164 : targetPhone,
            userId: _currentUser?.id,
          )
          .timeout(const Duration(seconds: 2));
      debugPrint("[SUPABASE] Permanently deleted user from Supabase patients.");
    } catch (e) {
      debugPrint("[SUPABASE] Delete user error: $e");
    }

    // 3. Clear local state and preferences completely
    await logout();
  }

  void setLoggedIn(bool loggedIn) {
    _isLoggedIn = loggedIn;
    if (loggedIn) {
      _currentPatientNavIndex = 0;
      loadPatientProfileFromSupabase();
    } else {
      logout();
    }
    notifyListeners();
  }

  Future<void> loadPatientProfileFromSupabase([String? phone]) async {
    try {
      final client = SupabaseService.instance.client;
      final fbUser = FirebaseAuth.instance.currentUser;
      final uid = fbUser?.uid ?? _currentUser?.id;

      if (client != null && SupabaseService.instance.isInitialized) {
        Map<String, dynamic>? data;
        if (uid != null && uid.isNotEmpty) {
          try {
            data = await client
                .from('patients')
                .select('*')
                .or('id.eq."$uid",user_id.eq."$uid"')
                .maybeSingle();
          } catch (e) {
            debugPrint("[SUPABASE_PROFILE] ID filter notice: $e");
          }
        }

        if (data == null) {
          final targetPhone = phone ?? _currentUser?.phoneNumber ?? fbUser?.phoneNumber;
          if (targetPhone != null && targetPhone.isNotEmpty) {
            final digits = targetPhone.replaceAll(RegExp(r'\D'), '');
            final possible = [targetPhone, digits, '0$digits', '252$digits', '+252$digits'];
            try {
              data = await client
                  .from('patients')
                  .select('*')
                  .inFilter('phone_number', possible)
                  .maybeSingle();
            } catch (e) {
              debugPrint("[SUPABASE_PROFILE] phone_number inFilter notice: $e");
            }
          }
        }

        if (data != null) {
          final fetchedName = (data['full_name'] as String?) ?? (data['name'] as String?) ?? _currentUser?.fullName ?? 'Patient';
          final fetchedPhone = (data['phone_number'] as String?) ?? (data['phone'] as String?) ?? phone ?? _currentUser?.phoneNumber ?? '';
          final fetchedEmail = (data['email'] as String?) ?? _currentUser?.email ?? '';
          final fetchedAvatar = (data['avatar_url'] as String?) ?? _currentUser?.avatarUrl ?? '';

          _currentUser = UserModel(
            id: uid ?? (data['id'] as String? ?? 'usr_${DateTime.now().millisecondsSinceEpoch}'),
            fullName: fetchedName,
            phoneNumber: fetchedPhone,
            email: fetchedEmail,
            avatarUrl: fetchedAvatar,
            createdAt: _currentUser?.createdAt ?? DateTime.now(),
          );
          _isLoggedIn = true;
          _saveProfileToPrefs();
          await loadNotificationsFromSupabase();
          notifyListeners();
          debugPrint("[SUPABASE_PROFILE] Successfully loaded patient full_name: $fetchedName");
        }
      }
    } catch (e) {
      debugPrint("[SUPABASE_PROFILE] Error loading patient profile: $e");
    }
  }

  void registerUser({
    required String name,
    required String phone,
    required String email,
    String? id,
  }) async {
    final now = DateTime.now();
    final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
    final userId = id ?? firebaseUid ?? 'usr_${now.millisecondsSinceEpoch}';

    // Clear previous user's cached state, appointments, cart, and avatar
    _appointments.clear();
    _cartItems.clear();
    _notifications.clear();
    _chatMessages.clear();

    _currentUser = UserModel(
      id: userId,
      fullName: name,
      phoneNumber: phone,
      email: email,
      avatarUrl: '', // Default empty avatar for new user
      createdAt: now,
    );
    _isLoggedIn = true;
    _saveProfileToPrefs();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_read_notification_time_v1', now.toUtc().toIso8601String());
    } catch (e) {
      debugPrint("Error setting initial notification timestamp: $e");
    }

    notifyListeners();

    // Pure Supabase Profile Creation in public.patients table
    try {
      final client = SupabaseService.instance.client;
      if (client != null && SupabaseService.instance.isInitialized) {
        await client.from('patients').upsert({
          'id': userId,
          'user_id': userId,
          'full_name': name,
          'phone_number': phone,
          'email': email,
          'created_at': now.toIso8601String(),
        });
        debugPrint("[SUPABASE_PATIENTS] Registered patient profile exclusively in Supabase patients table.");
      }
    } catch (e) {
      debugPrint("Supabase registerUser notice: $e");
    }
  }

  Future<bool> updateProfile({
    String? fullName,
    String? phoneNumber,
    String? email,
    String? avatarUrl,
    Uint8List? avatarBytes,
  }) async {
    if (_currentUser == null) return false;

    String finalAvatarUrl = avatarUrl ?? _currentUser!.avatarUrl;
    if (avatarBytes != null && avatarBytes.isNotEmpty) {
      debugPrint(
        "[AVATAR_UPLOAD] Uploading user profile avatar to Supabase Storage...",
      );
      final uploadedUrl = await SupabaseService.instance.uploadUserAvatar(
        avatarBytes,
        userId: _currentUser?.id,
      );
      if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
        finalAvatarUrl = uploadedUrl;
      } else {
        // Fallback: Convert to data URL if remote upload fails completely
        finalAvatarUrl = 'data:image/png;base64,${base64Encode(avatarBytes)}';
      }
    }

    final newFullName = fullName?.trim() ?? _currentUser!.fullName;
    final newPhone = phoneNumber?.trim() ?? _currentUser!.phoneNumber;
    final newEmail = email?.trim() ?? _currentUser!.email;

    _currentUser = _currentUser!.copyWith(
      fullName: newFullName,
      phoneNumber: newPhone,
      email: newEmail,
      avatarUrl: finalAvatarUrl,
    );
    _saveProfileToPrefs();
    notifyListeners();

    // 1. Execute Supabase update on public.patients
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        await client.from('patients').upsert({
          'id': _currentUser!.id,
          'user_id': _currentUser!.id,
          'full_name': newFullName,
          'phone_number': newPhone,
          'email': newEmail,
          'avatar_url': finalAvatarUrl,
        }).select().timeout(const Duration(seconds: 5));
        debugPrint("[SUPABASE_PROFILE] Updated patient in Supabase public.patients.");
      } catch (e) {
        debugPrint("[SUPABASE_PROFILE] Supabase profile sync notice: $e");
      }
    }

    return true;
  }

  int getNextQueueNumberForDoctor({required String doctorId, required String date}) {
    // Normalize date and doctorId for accurate daily matching
    final cleanDate = date.trim().toLowerCase();
    final cleanDoc = doctorId.trim().toLowerCase();

    final matches = _appointments.where((a) {
      final matchDoc = a.doctorId.trim().toLowerCase() == cleanDoc ||
          a.doctorName.trim().toLowerCase() == cleanDoc;
      final matchDate = a.date.trim().toLowerCase() == cleanDate;
      return matchDoc && matchDate;
    }).toList();

    if (matches.isEmpty) {
      return 1;
    }

    int maxQueue = 0;
    for (final a in matches) {
      if (a.queueNumber > maxQueue) {
        maxQueue = a.queueNumber;
      }
    }
    return maxQueue + 1;
  }

  void startDraftBooking(DoctorModel doctor) {
    final todayStr = DateFormat('EEEE, MMM d, yyyy').format(DateTime.now());
    final initialQueue = getNextQueueNumberForDoctor(doctorId: doctor.id, date: todayStr);

    currentDraftBooking = AppointmentModel(
      id: 'apt_${DateTime.now().millisecondsSinceEpoch}',
      referenceId: '#APT${(10000 + DateTime.now().millisecond * 7).toString()}',
      doctorId: doctor.id,
      doctorName: doctor.name,
      doctorSpecialty: doctor.specialty,
      doctorImageUrl: doctor.imageUrl,
      hospitalName: doctor.hospital,
      date: todayStr,
      time: '09:00 AM',
      appointmentType: 'New Patient',
      patientName: _currentUser?.fullName ?? '',
      patientPhone: _currentUser?.phoneNumber ?? '',
      patientAge: 24,
      patientGender: 'Male',
      patientImageUrl: (_currentUser?.avatarUrl != null && _currentUser!.avatarUrl.trim().isNotEmpty)
          ? _currentUser!.avatarUrl.trim()
          : null,
      reasonForVisit: '',
      paymentMethod: 'EVC Plus',
      amount: doctor.activePrice,
      queueNumber: initialQueue,
      status: 'Upcoming',
      createdAt: DateTime.now().toIso8601String(),
    );
    notifyListeners();
  }

  void updateDraftBooking({
    String? date,
    String? time,
    String? appointmentType,
    String? reasonForVisit,
    String? paymentMethod,
    String? patientName,
    String? patientPhone,
    int? patientAge,
    String? patientGender,
    String? patientImageUrl,
    int? queueNumber,
  }) {
    if (currentDraftBooking == null) return;
    final String effectiveImg = (patientImageUrl != null && patientImageUrl.trim().isNotEmpty)
        ? patientImageUrl.trim()
        : ((currentDraftBooking!.patientImageUrl != null && currentDraftBooking!.patientImageUrl!.trim().isNotEmpty)
            ? currentDraftBooking!.patientImageUrl!.trim()
            : ((_currentUser?.avatarUrl != null && _currentUser!.avatarUrl.trim().isNotEmpty)
                ? _currentUser!.avatarUrl.trim()
                : ''));

    final effectiveDate = date ?? currentDraftBooking!.date;
    final effectiveQueue = queueNumber ??
        getNextQueueNumberForDoctor(
          doctorId: currentDraftBooking!.doctorId,
          date: effectiveDate,
        );

    currentDraftBooking = AppointmentModel(
      id: currentDraftBooking!.id,
      referenceId: currentDraftBooking!.referenceId,
      doctorId: currentDraftBooking!.doctorId,
      doctorName: currentDraftBooking!.doctorName,
      doctorSpecialty: currentDraftBooking!.doctorSpecialty,
      doctorImageUrl: currentDraftBooking!.doctorImageUrl,
      hospitalName: currentDraftBooking!.hospitalName,
      date: effectiveDate,
      time: time ?? currentDraftBooking!.time,
      appointmentType: appointmentType ?? currentDraftBooking!.appointmentType,
      patientName: (patientName != null && patientName.trim().isNotEmpty)
          ? patientName.trim()
          : currentDraftBooking!.patientName,
      patientPhone: (patientPhone != null && patientPhone.trim().isNotEmpty)
          ? patientPhone.trim()
          : currentDraftBooking!.patientPhone,
      patientAge: patientAge ?? currentDraftBooking!.patientAge,
      patientGender: patientGender ?? currentDraftBooking!.patientGender,
      patientImageUrl: effectiveImg.isNotEmpty ? effectiveImg : null,
      reasonForVisit: reasonForVisit ?? currentDraftBooking!.reasonForVisit,
      paymentMethod: paymentMethod ?? currentDraftBooking!.paymentMethod,
      amount: currentDraftBooking!.amount,
      queueNumber: effectiveQueue,
      status: currentDraftBooking!.status,
      createdAt: currentDraftBooking!.createdAt,
    );
    notifyListeners();
  }

  void confirmCurrentBooking() {
    if (currentDraftBooking != null) {
      final latestQueue = getNextQueueNumberForDoctor(
        doctorId: currentDraftBooking!.doctorId,
        date: currentDraftBooking!.date,
      );

      final finalBooking = currentDraftBooking!.copyWith(queueNumber: latestQueue);
      _appointments.insert(0, finalBooking);
      notifyListeners();

      // Insert to Supabase
      final client = SupabaseService.instance.client;
      if (client != null && SupabaseService.instance.isInitialized) {
        client
            .from('appointments')
            .insert({
              'id': finalBooking.id,
              'reference_id': finalBooking.referenceId,
              'doctor_id': finalBooking.doctorId,
              'doctor_name': finalBooking.doctorName,
              'doctor_specialty': finalBooking.doctorSpecialty,
              'patient_name': finalBooking.patientName,
              'patient_phone': finalBooking.patientPhone,
              'patient_age': finalBooking.patientAge,
              'patient_gender': finalBooking.patientGender,
              'date': finalBooking.date,
              'time': finalBooking.time,
              'status': 'Confirmed',
              'reason': finalBooking.reasonForVisit,
              'payment_method': finalBooking.paymentMethod,
              'amount': finalBooking.amount,
              'queue_number': finalBooking.queueNumber,
            })
            .then((_) => debugPrint("Booking saved to Supabase"))
            .catchError(
              (e) => debugPrint("Failed to save booking to Supabase: $e"),
            );
      }
    }
  }

  // Admin CRUD
  Future<bool> addDoctor(DoctorModel doctor, {Uint8List? imageBytes}) async {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) {
      debugPrint(
        "[DOCTORS_ADD] Error: Supabase client offline or uninitialized.",
      );
      throw Exception("Supabase client is not initialized.");
    }

    try {
      // 1. Upload binary image to Storage bucket 'avatars'
      String finalImageUrl = doctor.imageUrl;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        debugPrint(
          "[DOCTORS_ADD] Uploading binary image bytes to Supabase Storage bucket 'avatars'...",
        );
        final uploadedUrl = await SupabaseService.instance.uploadDoctorImage(
          imageBytes,
          doctorId: doctor.id.isNotEmpty
              ? doctor.id
              : '${DateTime.now().millisecondsSinceEpoch}',
        );
        if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
          finalImageUrl = uploadedUrl;
          debugPrint("[DOCTORS_ADD] Upload success! Public URL: $finalImageUrl");
        } else {
          debugPrint(
            "[DOCTORS_ADD] Storage upload returned null/empty URL.",
          );
          if (finalImageUrl.startsWith('data:image')) {
            finalImageUrl = ''; // Never store Base64 in PostgreSQL!
          }
        }
      } else if (finalImageUrl.startsWith('data:image')) {
        finalImageUrl = '';
      }

      // 2. Prepare database payload matching public.doctors schema
      final String cleanNum = doctor.id.replaceAll(RegExp(r'[^0-9]'), '');
      final int? intId = cleanNum.isNotEmpty ? int.tryParse(cleanNum) : null;

      final Map<String, dynamic> cleanPayload = {
        'name': doctor.name,
        'specialty': doctor.specialty,
        'experience': doctor.experience,
        'patients_count': doctor.patientsCount.isNotEmpty ? doctor.patientsCount : '0+',
        'working_hours': doctor.workingHours,
        'about': doctor.about,
        'image_url': finalImageUrl,
        'is_available': doctor.isAvailable,
        'is_online': doctor.isOnline,
        'consultation_fee': doctor.consultationFee,
        'discount_fee': doctor.discountFee,
      };

      if (doctor.id.isNotEmpty) {
        cleanPayload['id'] = doctor.id;
      }

      debugPrint(
        "[DOCTORS_ADD] Sending database payload to Supabase doctors table: $cleanPayload",
      );

      dynamic insertedRow;
      try {
        final res = await client.from('doctors').insert(cleanPayload).select();
        if (res.isNotEmpty) {
          insertedRow = res.first;
        }
        debugPrint("[DOCTORS_ADD] DB insert succeeded! Returned row: $insertedRow");
      } catch (insertErr) {
        debugPrint(
          "[DOCTORS_ADD] Primary insert notice: $insertErr. Trying auto-ID payload...",
        );
        final Map<String, dynamic> autoIdPayload = Map<String, dynamic>.from(cleanPayload);
        autoIdPayload.remove('id');

        try {
          final res = await client.from('doctors').insert(autoIdPayload).select();
          if (res.isNotEmpty) {
            insertedRow = res.first;
          }
          debugPrint("[DOCTORS_ADD] Auto-ID DB insert succeeded! Returned row: $insertedRow");
        } catch (retryErr) {
          debugPrint("[DOCTORS_ADD] CRITICAL INSERT ERROR: $retryErr");
          rethrow;
        }
      }

      // 3. ONLY AFTER Successful DB Insert: Update local state & notify listeners
      DoctorModel confirmedDoc;
      if (insertedRow != null) {
        confirmedDoc = DoctorModel.fromJson(Map<String, dynamic>.from(insertedRow));
      } else {
        confirmedDoc = doctor.copyWith(imageUrl: finalImageUrl);
      }

      _doctors.removeWhere((d) => d.id == confirmedDoc.id);
      _doctors.insert(0, confirmedDoc);

      await fetchDoctors();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("[DOCTORS_ADD] Add doctor failed: $e");
      rethrow;
    }
  }

  Future<bool> updateDoctor(
    DoctorModel doctor, {
    Uint8List? newImageBytes,
  }) async {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) return false;

    try {
      String finalImageUrl = doctor.imageUrl;
      if (newImageBytes != null && newImageBytes.isNotEmpty) {
        final uploadedUrl = await SupabaseService.instance.uploadDoctorImage(
          newImageBytes,
          doctorId: doctor.id,
        );
        if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
          finalImageUrl = uploadedUrl;
        }
      } else if (finalImageUrl.startsWith('data:image')) {
        finalImageUrl = '';
      }

      final Map<String, dynamic> updatePayload = {
        'name': doctor.name,
        'specialty': doctor.specialty,
        'experience': doctor.experience,
        'patients_count': doctor.patientsCount.isNotEmpty ? doctor.patientsCount : '0+',
        'working_hours': doctor.workingHours,
        'about': doctor.about,
        'image_url': finalImageUrl,
        'is_available': doctor.isAvailable,
        'is_online': doctor.isOnline,
        'consultation_fee': doctor.consultationFee,
        'discount_fee': doctor.discountFee,
      };

      try {
        await client.from('doctors').update(updatePayload).eq('id', doctor.id);
        debugPrint(
          "[DOCTORS_UPDATE] Update succeeded for doctor ID=${doctor.id}",
        );
      } catch (e1) {
        debugPrint("[DOCTORS_UPDATE] Update error: $e1");
      }

      await fetchDoctors();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Error updating order status: $e");
      return false;
    }
  }

  RealtimeChannel? subscribeToOrderTracking(String orderId) {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) return null;

    final String channelName = 'order_tracking_$orderId';
    debugPrint("[SUPABASE_REALTIME] Subscribing to order tracking channel: $channelName");

    final channel = client.channel(channelName);
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'orders',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: orderId,
      ),
      callback: (payload) {
        print("🟢 REALTIME ORDER UPDATE RECEIVED: ${payload.newRecord}");
        debugPrint("🟢 [SUPABASE_REALTIME] REALTIME ORDER UPDATE RECEIVED: ${payload.newRecord}");
        final newRecord = payload.newRecord;
        if (newRecord.isNotEmpty) {
          final String id = newRecord['id'].toString();
          final idx = _orders.indexWhere((o) => o['id'].toString() == id);
          if (idx != -1) {
            _orders[idx] = Map<String, dynamic>.from(newRecord);
          } else {
            _orders.insert(0, Map<String, dynamic>.from(newRecord));
          }
          notifyListeners();
        }
      },
    ).subscribe();

    return channel;
  }

  Future<void> deleteDoctor(String id, {bool permanently = true}) async {
    _doctors.removeWhere((d) => d.id == id);
    _nurses.removeWhere((n) => n.id == id);
    _deletedDoctors.removeWhere((d) => d.id == id);
    _customDoctors.removeWhere((d) => d.id == id);
    await _saveCustomDoctorsToPrefs();
    notifyListeners();

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        final cleanId = id.replaceAll('doc_', '');
        final parsedId = int.tryParse(cleanId);
        if (parsedId != null) {
          await client.from('doctors').delete().eq('id', parsedId);
          debugPrint(
            "Permanently deleted doctor int ID $parsedId from Supabase",
          );
        }
        await client.from('doctors').delete().eq('id', id);
        debugPrint("Permanently deleted doctor string ID $id from Supabase");
      } catch (e) {
        debugPrint("Delete doctor error: $e");
      }
    }
    notifyListeners();
  }

  void restoreDoctor(DoctorModel doctor) {
    _deletedDoctors.removeWhere((d) => d.id == doctor.id);
    addDoctor(doctor);
  }

  void deleteDoctorPermanentlyFromBin(String id) {
    _deletedDoctors.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  void updateAppointmentStatus(String id, String newStatus) {
    final idx = _appointments.indexWhere((a) => a.id == id);
    if (idx != -1) {
      final old = _appointments[idx];
      _appointments[idx] = AppointmentModel(
        id: old.id,
        referenceId: old.referenceId,
        doctorId: old.doctorId,
        doctorName: old.doctorName,
        doctorSpecialty: old.doctorSpecialty,
        doctorImageUrl: old.doctorImageUrl,
        hospitalName: old.hospitalName,
        date: old.date,
        time: old.time,
        appointmentType: old.appointmentType,
        patientName: old.patientName,
        patientPhone: old.patientPhone,
        patientAge: old.patientAge,
        patientGender: old.patientGender,
        reasonForVisit: old.reasonForVisit,
        paymentMethod: old.paymentMethod,
        amount: old.amount,
        queueNumber: old.queueNumber,
        status: newStatus,
        createdAt: old.createdAt,
      );
      notifyListeners();
    }
  }

  /// Calculate accurate dynamic sequential queue number from Supabase across all patients for this doctor on this date
  Future<int> getRealNextQueueNumber({
    required String doctorId,
    required String doctorName,
    required String date,
  }) async {
    final client = SupabaseService.instance.client;
    int maxQueue = 0;

    final cleanDoc = doctorId.trim().toLowerCase();
    final cleanName = doctorName.trim().toLowerCase();
    final cleanDate = date.trim().toLowerCase();

    // 1. Check in-memory appointments
    for (final a in _appointments) {
      final matchDoc = a.doctorId.trim().toLowerCase() == cleanDoc ||
          a.doctorName.trim().toLowerCase() == cleanName ||
          (cleanName.isNotEmpty && (cleanName.contains(a.doctorName.trim().toLowerCase()) || a.doctorName.trim().toLowerCase().contains(cleanName)));
      final matchDate = a.date.trim().toLowerCase() == cleanDate;
      if (matchDoc && matchDate && a.queueNumber > maxQueue) {
        maxQueue = a.queueNumber;
      }
    }

    // 2. Query Supabase appointments table across all patients for this doctor and date
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        final res = await client
            .from('appointments')
            .select('queue_number, doctor_id, doctor_name, date');

        if (res is List) {
          for (final row in res) {
            final rowDocId = (row['doctor_id'] ?? '').toString().trim().toLowerCase();
            final rowDocName = (row['doctor_name'] ?? '').toString().trim().toLowerCase();
            final rowDate = (row['date'] ?? '').toString().trim().toLowerCase();

            final bool matchDoc = rowDocId == cleanDoc ||
                rowDocName == cleanName ||
                (cleanName.isNotEmpty && (cleanName.contains(rowDocName) || rowDocName.contains(cleanName)));
            final bool matchDate = rowDate == cleanDate;

            if (matchDoc && matchDate) {
              final rawQ = row['queue_number'];
              final qNum = (rawQ is num) ? rawQ.toInt() : (int.tryParse(rawQ?.toString() ?? '') ?? 0);
              if (qNum > maxQueue) {
                maxQueue = qNum;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[QUEUE] Error fetching max queue from Supabase: $e');
      }
    }

    return maxQueue + 1;
  }

  Future<bool> addAppointment(AppointmentModel appointment) async {
    final String activeUserImg = (currentUser?.avatarUrl != null && currentUser!.avatarUrl.trim().isNotEmpty)
        ? currentUser!.avatarUrl.trim()
        : '';

    final String finalPatientImg = (appointment.patientImageUrl != null && appointment.patientImageUrl!.trim().isNotEmpty)
        ? appointment.patientImageUrl!.trim()
        : activeUserImg;

    // Dynamically calculate next queue number if not already assigned
    final int dynamicQueue = (appointment.queueNumber > 1)
        ? appointment.queueNumber
        : await getRealNextQueueNumber(
            doctorId: appointment.doctorId,
            doctorName: appointment.doctorName,
            date: appointment.date,
          );

    final String finalCreatedAt = (appointment.createdAt.isNotEmpty && DateTime.tryParse(appointment.createdAt) != null)
        ? appointment.createdAt
        : DateTime.now().toIso8601String();

    final String safeRef = (appointment.referenceId.isNotEmpty && appointment.referenceId != '#APT0')
        ? appointment.referenceId
        : '#APT${(10000 + Random().nextInt(89999))}';

    appointment = appointment.copyWith(
      referenceId: safeRef,
      patientImageUrl: finalPatientImg,
      queueNumber: dynamicQueue,
      createdAt: finalCreatedAt,
    );

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      // 1. Try standard comprehensive payload
      final Map<String, dynamic> payload = {
        'reference_id': safeRef,
        'doctor_id': appointment.doctorId,
        'doctor_name': appointment.doctorName,
        'doctor_specialty': appointment.doctorSpecialty,
        'patient_name': appointment.patientName,
        'patient_phone': appointment.patientPhone,
        'patient_age': appointment.patientAge,
        'patient_gender': appointment.patientGender,
        'date': appointment.date,
        'time': appointment.time,
        'appointment_type': appointment.appointmentType,
        'status': appointment.status,
        'reason': appointment.reasonForVisit,
        'payment_method': appointment.paymentMethod,
        'amount': appointment.amount > 0 ? appointment.amount : 15.0,
        'queue_number': appointment.queueNumber,
        'created_at': appointment.createdAt,
      };

      if (finalPatientImg.isNotEmpty) {
        payload['patient_image'] = finalPatientImg;
      }

      try {
        final res = await client.from('appointments').insert(payload).select().maybeSingle();
        if (res != null && res['id'] != null) {
          appointment = appointment.copyWith(id: res['id'].toString());
        }
        debugPrint("[SUPABASE_SUCCESS] Appointment inserted into public.appointments successfully!");
      } catch (err) {
        debugPrint("[SUPABASE_ERROR] Full insert error: $err, trying standard payload...");
        try {
          final standardPayload = {
            'reference_id': safeRef,
            'doctor_id': appointment.doctorId,
            'doctor_name': appointment.doctorName,
            'doctor_specialty': appointment.doctorSpecialty,
            'patient_name': appointment.patientName,
            'patient_phone': appointment.patientPhone,
            'patient_age': appointment.patientAge,
            'patient_gender': appointment.patientGender,
            'date': appointment.date,
            'time': appointment.time,
            'appointment_type': appointment.appointmentType,
            'status': appointment.status,
            'payment_method': appointment.paymentMethod,
            'amount': appointment.amount > 0 ? appointment.amount : 15.0,
            'queue_number': appointment.queueNumber,
            'created_at': appointment.createdAt,
          };
          final res2 = await client.from('appointments').insert(standardPayload).select().maybeSingle();
          if (res2 != null && res2['id'] != null) {
            appointment = appointment.copyWith(id: res2['id'].toString());
          }
          debugPrint("[SUPABASE_SUCCESS] Standard appointment inserted successfully!");
        } catch (err2) {
          debugPrint("[SUPABASE_ERROR] Standard insert error: $err2, trying minimal payload...");
          try {
            final minimalPayload = {
              'reference_id': safeRef,
              'doctor_name': appointment.doctorName,
              'doctor_specialty': appointment.doctorSpecialty,
              'patient_name': appointment.patientName,
              'patient_phone': appointment.patientPhone,
              'date': appointment.date,
              'time': appointment.time,
              'status': appointment.status,
              'payment_method': appointment.paymentMethod,
              'amount': appointment.amount > 0 ? appointment.amount : 15.0,
              'queue_number': appointment.queueNumber,
              'created_at': appointment.createdAt,
            };
            final res3 = await client.from('appointments').insert(minimalPayload).select().maybeSingle();
            if (res3 != null && res3['id'] != null) {
              appointment = appointment.copyWith(id: res3['id'].toString());
            }
            debugPrint("[SUPABASE_SUCCESS] Minimal fallback appointment inserted successfully!");
          } catch (err3) {
            debugPrint("[SUPABASE_ERROR] All Supabase appointment insert attempts failed: $err3");
          }
        }
      }
    }

    // Persist this booking to the user's booked IDs so it is never dropped on refresh
    if (appointment.id.isNotEmpty) _userBookedAppointmentIds.add(appointment.id);
    if (appointment.referenceId.isNotEmpty) _userBookedAppointmentIds.add(appointment.referenceId);
    if (appointment.patientPhone.isNotEmpty) _userBookedAppointmentIds.add(appointment.patientPhone);
    _saveUserBookedAppointmentIdsToPrefs();

    // Deduplicate in-memory list so duplicate twin records are never added locally
    _appointments.removeWhere((a) =>
        a.id == appointment.id ||
        (a.referenceId.isNotEmpty && a.referenceId == appointment.referenceId));
    // Always insert at the very top (index 0)
    _appointments.insert(0, appointment);
    _saveLocalAppointmentsToPrefs();
    notifyListeners();
    return true;
  }

  void addMedicine(MedicineModel medicine) {
    _medicines.insert(0, medicine);
    notifyListeners();

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      client
          .from('medicines')
          .insert({
            'id': medicine.id,
            'title': medicine.title,
            'category': medicine.category,
            'sku': medicine.sku,
            'price': medicine.price,
            'original_price': medicine.originalPrice,
            'image_url': medicine.imageUrl,
            'description': medicine.description,
          })
          .then((_) => debugPrint("Medicine saved to Supabase"))
          .catchError((e) => debugPrint("Failed to save medicine: $e"));
    }
  }

  void toggleFavoriteMedicine(String id) {
    final idx = _medicines.indexWhere((m) => m.id == id);
    if (idx != -1) {
      _medicines[idx] = _medicines[idx].copyWith(
        isFavorite: !_medicines[idx].isFavorite,
      );
      notifyListeners();
    }
  }

  void addOrUpdatePrescription(String appointmentId, String prescriptionText) {
    final index = _appointments.indexWhere((apt) => apt.id == appointmentId);
    if (index != -1) {
      _appointments[index] = _appointments[index].copyWith(
        prescription: prescriptionText,
      );
      notifyListeners();
    }
  }

  void deleteMedicine(String id, {bool permanently = true}) {
    _medicines.removeWhere((m) => m.id == id);
    _deletedMedicines.removeWhere((m) => m.id == id);
    notifyListeners();

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      final cleanId = id.replaceAll('med_', '');
      final parsedId = int.tryParse(cleanId);
      if (parsedId != null) {
        client
            .from('medicines')
            .delete()
            .eq('id', parsedId)
            .then(
              (_) => debugPrint(
                "Permanently deleted medicine int ID $parsedId from Supabase",
              ),
            )
            .catchError((e) => debugPrint("Delete medicine error: $e"));
      }
      client
          .from('medicines')
          .delete()
          .eq('id', id)
          .then(
            (_) => debugPrint(
              "Permanently deleted medicine string ID $id from Supabase",
            ),
          )
          .catchError((e) => debugPrint("Delete medicine error: $e"));
    }
  }

  void restoreMedicine(MedicineModel medicine) {
    _deletedMedicines.removeWhere((m) => m.id == medicine.id);
    addMedicine(medicine);
  }

  void deleteMedicinePermanentlyFromBin(String id) {
    _deletedMedicines.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  void updateMedicinePrice(String id, double price, double? originalPrice) {
    final idx = _medicines.indexWhere((m) => m.id == id);
    if (idx != -1) {
      _medicines[idx] = _medicines[idx].copyWith(
        price: price,
        originalPrice: originalPrice,
        clearOriginalPrice: originalPrice == null,
      );
      notifyListeners();
    }
  }

  Future<bool> updateMedicine(MedicineModel updated) async {
    final idx = _medicines.indexWhere((m) => m.id == updated.id);
    if (idx != -1) {
      _medicines[idx] = updated;
      notifyListeners();
    }

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        final payload = <String, dynamic>{
          'title': updated.title,
          'name': updated.title,
          'category': updated.category,
          'sku': updated.sku,
          'price': updated.price,
          'original_price': updated.originalPrice,
          'image_url': updated.imageUrl,
          'description': updated.description,
        };

        final parsedIntId = int.tryParse(updated.id);
        if (parsedIntId != null) {
          await client.from('medicines').update(payload).eq('id', parsedIntId);
        } else {
          await client.from('medicines').update(payload).eq('id', updated.id);
        }
        debugPrint('[SUPABASE] Successfully updated medicine ${updated.id}');
        return true;
      } catch (e) {
        debugPrint('[SUPABASE_ERROR] Error updating medicine ${updated.id}: $e');
      }
    }
    return true;
  }

  final Set<String> _deletedAppointmentIds = {};
  final Set<String> _userBookedAppointmentIds = {};

  Future<void> _loadUserBookedAppointmentIdsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('saved_user_booked_appointment_ids_v1');
      if (list != null) {
        _userBookedAppointmentIds.addAll(list);
      }
    } catch (_) {}
  }

  Future<void> _saveUserBookedAppointmentIdsToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('saved_user_booked_appointment_ids_v1', _userBookedAppointmentIds.toList());
    } catch (_) {}
  }

  Future<void> _loadDeletedAppointmentIdsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('saved_deleted_appointment_ids_v1');
      if (list != null) {
        _deletedAppointmentIds.addAll(list);
      }
    } catch (_) {}
  }

  Future<void> _saveDeletedAppointmentIdsToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('saved_deleted_appointment_ids_v1', _deletedAppointmentIds.toList());
    } catch (_) {}
  }

  Future<void> _saveLocalAppointmentsToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> encoded = _appointments.map((a) => jsonEncode(a.toJson())).toList();
      await prefs.setStringList('saved_local_appointments_cache_v2', encoded);
    } catch (_) {}
  }

  Future<List<AppointmentModel>> _loadLocalAppointmentsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('saved_local_appointments_cache_v2');
      if (list != null && list.isNotEmpty) {
        return list.map((str) => AppointmentModel.fromJson(jsonDecode(str))).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> deleteAppointment(String id) async {
    _appointments.removeWhere((a) => a.id == id || a.referenceId == id);
    _deletedAppointments.removeWhere((a) => a.id == id || a.referenceId == id);
    _deletedAppointmentIds.add(id);
    _saveDeletedAppointmentIdsToPrefs();
    notifyListeners();

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        await client.from('appointments').delete().or('id.eq."$id",reference_id.eq."$id"');
        await client.from('nurse_orders').delete().or('id.eq."$id",booking_id.eq."$id",service_notes.eq."$id"');
        final cleanId = id.replaceAll('apt_', '').replaceAll('nurse_', '');
        final parsedInt = int.tryParse(cleanId);
        if (parsedInt != null) {
          await client.from('appointments').delete().eq('id', parsedInt);
        }
        debugPrint("[SUPABASE_SUCCESS] Permanently deleted appointment $id from Supabase");
      } catch (e) {
        debugPrint("[SUPABASE_ERROR] Error deleting appointment from Supabase: $e");
      }
    }
  }

  void restoreAppointment(AppointmentModel appointment) {
    _deletedAppointments.removeWhere((a) => a.id == appointment.id);
    _appointments.insert(0, appointment);
    notifyListeners();

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      client.from('appointments').insert({
        'id': appointment.id,
        'reference_id': appointment.referenceId,
        'doctor_id': appointment.doctorId,
        'doctor_name': appointment.doctorName,
        'doctor_specialty': appointment.doctorSpecialty,
        'patient_name': appointment.patientName,
        'patient_phone': appointment.patientPhone,
        'patient_age': appointment.patientAge,
        'patient_gender': appointment.patientGender,
        'date': appointment.date,
        'time': appointment.time,
        'status': appointment.status,
        'reason': appointment.reasonForVisit,
        'payment_method': appointment.paymentMethod,
        'amount': appointment.amount,
        'queue_number': appointment.queueNumber,
      });
    }
  }

  void deleteAppointmentPermanentlyFromBin(String id) {
    final index = _deletedAppointments.indexWhere((a) => a.id == id);
    if (index != -1) {
      final target = _deletedAppointments[index];
      if (target.patientPhone.isNotEmpty) {
        deleteUserAccount(target.patientPhone);
      }
      _deletedAppointments.removeAt(index);
      notifyListeners();
    }
  }

  String? _activeConversationId;
  String? get activeConversationId => _activeConversationId;
  RealtimeChannel? _realtimeSubscription;
  final List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> get conversations => _conversations;

  Future<String> getOrCreateConversation({
    required String patientId,
    required String doctorId,
  }) async {
    final String pId = patientId.trim();
    final String dId = doctorId.trim().isEmpty ? 'admin_support' : doctorId.trim();
    final String cleanPId = pId.replaceAll(RegExp(r'[\s\-()]+'), '_');
    final String cleanDId = dId.replaceAll(RegExp(r'[\s\-()]+'), '_');
    final String deterministicConvId = 'conv_${cleanPId}_$cleanDId';

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        final convPayload = {
          'id': deterministicConvId,
          'patient_id': pId,
          'doctor_id': dId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        final res = await client
            .from('conversations')
            .upsert(convPayload)
            .select()
            .maybeSingle();

        if (res != null && res['id'] != null) {
          final convId = res['id'].toString();
          if (!_conversations.any((c) => c['id'] == convId)) {
            _conversations.add(Map<String, dynamic>.from(res));
          }
          return convId;
        }
      } catch (e) {
        debugPrint("[CONVERSATION_UPSERT_NOTICE] $e");
      }
    }

    if (!_conversations.any((c) => c['id'] == deterministicConvId)) {
      _conversations.add({
        'id': deterministicConvId,
        'patient_id': pId,
        'doctor_id': dId,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    return deterministicConvId;
  }

  Future<void> openDoctorConversation({
    required String patientId,
    required String doctorId,
  }) async {
    final convId = await getOrCreateConversation(
      patientId: patientId,
      doctorId: doctorId,
    );
    await setActiveConversation(convId);
  }

  Future<void> setActiveConversation(String? conversationId) async {
    _activeConversationId = conversationId;
    await fetchMessagesSilently();
  }

  Future<void> fetchMessagesForActiveConversation() async {
    if (_activeConversationId == null || _activeConversationId!.isEmpty) return;
    final conversationId = _activeConversationId!;

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        final messagesData = await client
            .from('messages')
            .select()
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: true);

        final list = <Map<String, dynamic>>[];
        for (var msg in messagesData) {
          final rawText = msg['text'] ?? msg['message'] ?? '';
          final decryptedText = EncryptionService.decrypt(rawText);

          list.add({
            'id': msg['id'].toString(),
            'conversation_id':
                msg['conversation_id']?.toString() ?? conversationId,
            'sender_id': msg['sender_id'] ?? '',
            'sender_name': msg['sender_name'] ?? '',
            'sender_role': msg['sender_role'] ?? '',
            'text': decryptedText,
            'message': decryptedText,
            'image_url': msg['image_url'] ?? '',
            'patient_id': msg['patient_id'] ?? '',
            'doctor_id': msg['doctor_id'] ?? '',
            'doctor_name': msg['doctor_name'] ?? '',
            'time': msg['created_at'] != null
                ? msg['created_at'].toString()
                : '',
            'is_read': msg['is_read'] ?? false,
          });
        }

        _chatMessages.clear();
        _chatMessages.addAll(list);
        notifyListeners();
      } catch (e) {
        debugPrint(
          "Failed to fetch messages for conversation $conversationId: $e",
        );
      }
    }
  }

  Future<void> sendChatMessage(
    String senderId,
    String senderName,
    String text,
    String patientId, {
    String? imageUrl,
    String? doctorId,
    String? doctorName,
    String? conversationId,
    String? senderRole,
  }) async {
    final client = SupabaseService.instance.client;
    final String docIdVal = doctorId ?? 'admin_support';
    final String docNameVal = doctorName ?? 'Nasiib Hospital Support';
    final String roleVal = senderRole ?? (senderId == 'admin' || senderId == 'doctor' ? 'admin' : 'patient');

    String activeConvId = conversationId ?? _activeConversationId ?? '';
    if (activeConvId.isEmpty) {
      activeConvId = await getOrCreateConversation(
        patientId: patientId,
        doctorId: docIdVal,
      );
      _activeConversationId = activeConvId;
    }

    final tempMsg = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'conversation_id': activeConvId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_role': roleVal,
      'text': text,
      'message': text,
      'image_url': imageUrl ?? '',
      'patient_id': patientId,
      'doctor_id': docIdVal,
      'doctor_name': docNameVal,
      'time': DateTime.now().toIso8601String(),
      'is_read': false,
    };
    _chatMessages.add(tempMsg);
    notifyListeners();

    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        final encryptedText = EncryptionService.encrypt(text);

        // Pre-upsert parent conversation record to avoid Foreign Key constraint error
        try {
          await client.from('conversations').upsert({
            'id': activeConvId,
            'patient_id': patientId,
            'doctor_id': docIdVal,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (convErr) {
          debugPrint("[CONV_PRE_UPSERT] $convErr");
        }

        final textPayload = (imageUrl != null && imageUrl.isNotEmpty) ? imageUrl : text;

        final Map<String, dynamic> minimalPayload = {
          'sender_id': senderId,
          'patient_id': patientId,
          'patient_name': senderName,
          'sender_name': senderName,
          'message': textPayload,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        };

        try {
          final richPayload = Map<String, dynamic>.from(minimalPayload);
          richPayload['conversation_id'] = activeConvId;
          richPayload['sender_role'] = roleVal;
          richPayload['text'] = textPayload;
          richPayload['content'] = textPayload;
          if (imageUrl != null && imageUrl.isNotEmpty) {
            richPayload['image_url'] = imageUrl;
            richPayload['media_url'] = imageUrl;
          }
          richPayload['doctor_id'] = docIdVal;
          richPayload['doctor_name'] = docNameVal;
          richPayload['is_read'] = false;

          final inserted = await client.from('messages').insert(richPayload).select().maybeSingle();
          if (inserted != null && inserted['id'] != null) {
            tempMsg['id'] = inserted['id'].toString();
          }
        } catch (richErr) {
          debugPrint("[SUPABASE RICH INSERT NOTICE] $richErr. Retrying minimal insert...");
          try {
            final inserted = await client.from('messages').insert(minimalPayload).select().maybeSingle();
            if (inserted != null && inserted['id'] != null) {
              tempMsg['id'] = inserted['id'].toString();
            }
          } catch (minErr) {
            debugPrint("[SUPABASE MINIMAL INSERT ERROR] $minErr");
          }
        }
      } catch (e) {
        debugPrint("Failed to send message to Supabase: $e");
      }
    }
  }

  void markChatAsRead(String patientIdOrName) {
    bool updated = false;
    for (var msg in _chatMessages) {
      final pId = msg['patient_id']?.toString() ?? '';
      final sName = msg['sender_name']?.toString() ?? '';
      final sId = msg['sender_id']?.toString() ?? '';

      if (pId == patientIdOrName ||
          sName == patientIdOrName ||
          sId == patientIdOrName ||
          pId.toLowerCase() == patientIdOrName.toLowerCase() ||
          sName.toLowerCase() == patientIdOrName.toLowerCase()) {
        if (msg['is_read'] != true) {
          msg['is_read'] = true;
          updated = true;
        }
      }
    }
    if (updated) {
      notifyListeners();
      final client = SupabaseService.instance.client;
      if (client != null && SupabaseService.instance.isInitialized) {
        client
            .from('messages')
            .update({'is_read': true})
            .eq('patient_id', patientIdOrName)
            .catchError(
              (e) => debugPrint(
                "Failed to update read status patient_id in Supabase: $e",
              ),
            );
        client
            .from('messages')
            .update({'is_read': true})
            .eq('sender_name', patientIdOrName)
            .catchError(
              (e) => debugPrint(
                "Failed to update read status sender_name in Supabase: $e",
              ),
            );
      }
    }
  }

  Future<void> deleteChatMessage(String msgId) async {
    // Remove locally
    _chatMessages.removeWhere((m) => m['id'] == msgId);
    notifyListeners();

    // Remove from Supabase
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        final parsedId = int.tryParse(msgId);
        if (parsedId != null) {
          await client.from('messages').delete().eq('id', parsedId);
        } else {
          await client.from('messages').delete().eq('id', msgId);
        }
        debugPrint("Deleted message $msgId from Supabase");
      } catch (e) {
        debugPrint("Failed to delete message from Supabase: $e");
      }
    }
  }

  Future<void> deleteConversationPermanently({
    required String patientId,
    required String doctorId,
    required String doctorName,
  }) async {
    final cleanDocId = doctorId.replaceAll('doc_', '');

    // 1. Remove all matching messages from local state immediately
    _chatMessages.removeWhere((m) {
      final mPatient = m['patient_id']?.toString() ?? '';
      final mDocId = m['doctor_id']?.toString() ?? '';
      final mDocName = m['doctor_name']?.toString() ?? '';

      final matchDoc =
          mDocId == doctorId ||
          mDocId == cleanDocId ||
          (mDocName.isNotEmpty &&
              mDocName.toLowerCase() == doctorName.toLowerCase());
      final matchPatient =
          mPatient.isEmpty ||
          mPatient == patientId ||
          (currentUser != null &&
              (mPatient == currentUser!.fullName ||
                  mPatient == currentUser!.id));

      return matchDoc && matchPatient;
    });

    notifyListeners();

    // 2. Delete permanently from Supabase DB 'messages' table
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        final parsedDocId = int.tryParse(cleanDocId);
        if (parsedDocId != null) {
          await client
              .from('messages')
              .delete()
              .eq('doctor_id', parsedDocId.toString());
        }
        await client.from('messages').delete().eq('doctor_id', doctorId);
        if (doctorName.isNotEmpty) {
          await client.from('messages').delete().eq('doctor_name', doctorName);
          await client
              .from('messages')
              .delete()
              .ilike('doctor_name', '%$doctorName%');
        }
        debugPrint(
          "[CHAT_DELETE] Permanently deleted conversation for doctor '$doctorName' (ID=$doctorId).",
        );
      } catch (e) {
        debugPrint("[CHAT_DELETE] Delete chat error: $e");
      }
    }
  }

  Future<void> clearPatientChatHistory(String patientId, String patientName) async {
    final cleanName = patientName.trim();
    final cleanId = patientId.trim();

    _chatMessages.removeWhere((m) {
      final pId = (m['patient_id'] ?? m['sender_id'] ?? '').toString().trim();
      final pName = (m['patient_name'] ?? m['sender_name'] ?? '').toString().trim();
      return pId == cleanId || pName == cleanName || pName.toLowerCase() == cleanName.toLowerCase();
    });
    notifyListeners();

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        await client.from('messages').delete().or(
          'patient_id.eq.$cleanId,patient_id.eq.$cleanName,patient_name.eq.$cleanName,sender_id.eq.$cleanId,sender_name.eq.$cleanName'
        );
      } catch (e) {
        debugPrint("Error clearing patient chat history: $e");
      }
    }
  }

  String? _lastMessageTimestamp;

  Future<void> fetchMessagesSilently() async {
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        var query = client.from('messages').select();
        if (_chatMessages.isNotEmpty &&
            _lastMessageTimestamp != null &&
            _lastMessageTimestamp!.isNotEmpty) {
          query = query.gt('created_at', _lastMessageTimestamp!);
        }

        final messagesData = await query.order('created_at', ascending: true);

        if (messagesData.isNotEmpty) {
          bool addedNew = false;
          for (var msg in messagesData) {
            final String msgId = msg['id'].toString();
            final rawTime = msg['created_at'] != null
                ? msg['created_at'].toString()
                : '';
            if (rawTime.isNotEmpty) {
              _lastMessageTimestamp = rawTime;
            }

            if (!_chatMessages.any((m) => m['id'] == msgId)) {
              final rawText = (msg['message'] ?? msg['text'] ?? msg['content'] ?? '').toString();
              final decryptedText = EncryptionService.decrypt(rawText);
              String imgUrl = (msg['image_url'] ?? msg['media_url'] ?? msg['attachment_url'] ?? '').toString().trim();
              if (imgUrl.isEmpty && (rawText.startsWith('http://') || rawText.startsWith('https://') || rawText.startsWith('data:image/'))) {
                imgUrl = rawText.trim();
              }

              _chatMessages.add({
                'id': msgId,
                'sender_id': msg['sender_id'] ?? '',
                'sender_name': msg['sender_name'] ?? '',
                'text': decryptedText,
                'message': decryptedText,
                'image_url': imgUrl,
                'media_url': imgUrl,
                'patient_id': msg['patient_id'] ?? '',
                'doctor_id': msg['doctor_id'] ?? '',
                'doctor_name': msg['doctor_name'] ?? '',
                'time': rawTime,
                'is_read': msg['is_read'] ?? false,
              });
              addedNew = true;
            }
          }
          if (addedNew) {
            notifyListeners();
          }
        }
      } catch (err) {
        debugPrint("Failed to fetch messages silently from Supabase: $err");
      }
    }
  }

  // --- REAL-TIME ORDERS & PHARMACY DELIVERY PORTAL ---
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> get orders {
    if (isAdminMode) return _orders;
    final String currentPhone = (_currentUser?.phoneNumber ?? '').replaceAll(RegExp(r'[\s\-()]+'), '');
    if (currentPhone.isEmpty) return [];
    
    final String cleanDigits = currentPhone.replaceAll('+252', '').replaceAll(RegExp(r'^252|^0'), '');

    return _orders.where((o) {
      final pPhone = (o['patient_phone'] ?? o['patientPhone'] ?? o['phone'] ?? '').toString().replaceAll(RegExp(r'[\s\-()]+'), '');
      if (pPhone.isEmpty) return false;
      final pDigits = pPhone.replaceAll('+252', '').replaceAll(RegExp(r'^252|^0'), '');
      return pDigits == cleanDigits || pPhone == currentPhone;
    }).toList();
  }

  List<Map<String, dynamic>> _orderItems = [];
  List<Map<String, dynamic>> get orderItems => _orderItems;

  final List<Map<String, dynamic>> _nurseOrders = [];
  List<Map<String, dynamic>> get nurseOrders => _nurseOrders;

  /// Check if a nurse is currently busy (On Duty / In Progress / Pending)
  bool isNurseBusy(NurseModel nurse) {
    // 1. Check if nurse record explicitly has isAvailable false
    if (!nurse.isAvailable) return true;

    // 2. Check if nurse currently has an active order (pending or in progress)
    final cleanName = nurse.name.trim().toLowerCase();
    final cleanId = nurse.id.trim().toLowerCase();

    return _nurseOrders.any((order) {
      final status = (order['status'] ?? order['order_status'] ?? 'pending')
          .toString()
          .toLowerCase()
          .trim();
      final isActive = status == 'pending' ||
          status == 'in progress' ||
          status == 'in_progress' ||
          status == 'accepted' ||
          status == 'assigned' ||
          status == 'on the way';

      if (!isActive) return false;

      final nId = (order['nurse_id'] ?? '').toString().toLowerCase().trim();
      final nName = (order['nurse_name'] ?? order['doctor_name'] ?? '').toString().toLowerCase().trim();

      return (cleanId.isNotEmpty && nId == cleanId) ||
          (cleanName.isNotEmpty && nName.contains(cleanName)) ||
          (cleanName.isNotEmpty && cleanName.contains(nName));
    });
  }

  final List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> get payments => _payments;

  RealtimeChannel? _systemSyncChannel;

  void initRealtimeSubscriptions() {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) return;

    _systemSyncChannel?.unsubscribe();

    final String channelName = 'admin_appointments_realtime_${DateTime.now().millisecondsSinceEpoch}';
    debugPrint("[SUPABASE_REALTIME] Connecting WebSocket channel: $channelName");

    _systemSyncChannel = client
        .channel(channelName)
        // 1. Appointments (Bookings, status updates, cancellations, deletions)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'appointments',
          callback: (payload) {
            final eventType = payload.eventType;
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;

            if (eventType == PostgresChangeEvent.insert && newRecord.isNotEmpty) {
              print('🟢 REALTIME INSERT RECEIVED: $newRecord');
              debugPrint('🟢 [SUPABASE_REALTIME] REALTIME INSERT RECEIVED: $newRecord');

              final newModel = AppointmentModel.fromJson(newRecord);
              _appointments.removeWhere((a) =>
                  a.id == newModel.id ||
                  (a.referenceId.isNotEmpty && a.referenceId == newModel.referenceId));
              _appointments.insert(0, newModel);
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.update && newRecord.isNotEmpty) {
              print('🟢 REALTIME UPDATE RECEIVED: $newRecord');
              debugPrint('🟢 [SUPABASE_REALTIME] REALTIME UPDATE RECEIVED: $newRecord');

              final updatedModel = AppointmentModel.fromJson(newRecord);
              final idx = _appointments.indexWhere((a) =>
                  a.id == updatedModel.id ||
                  (a.referenceId.isNotEmpty && a.referenceId == updatedModel.referenceId));
              if (idx != -1) {
                _appointments[idx] = updatedModel;
              } else {
                _appointments.insert(0, updatedModel);
              }
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.delete && oldRecord.isNotEmpty) {
              print('🟢 REALTIME DELETE RECEIVED: $oldRecord');
              debugPrint('🟢 [SUPABASE_REALTIME] REALTIME DELETE RECEIVED: $oldRecord');

              final String deletedId = oldRecord['id']?.toString() ?? '';
              final String deletedRef = oldRecord['reference_id']?.toString() ?? '';
              _appointments.removeWhere((a) =>
                  (deletedId.isNotEmpty && a.id == deletedId) ||
                  (deletedRef.isNotEmpty && a.referenceId == deletedRef));
              notifyListeners();
            }
          },
        )
        // 2. Doctors (Additions, edits, status/roster changes)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'doctors',
          callback: (payload) {
            debugPrint("[SUPABASE_REALTIME] Doctors event: ${payload.eventType}");
            final eventType = payload.eventType;
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;

            if (eventType == PostgresChangeEvent.insert && newRecord.isNotEmpty) {
              final newModel = DoctorModel.fromJson(newRecord);
              _doctors.removeWhere((d) => d.id == newModel.id);
              _doctors.insert(0, newModel);
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.update && newRecord.isNotEmpty) {
              final updatedModel = DoctorModel.fromJson(newRecord);
              final idx = _doctors.indexWhere((d) => d.id == updatedModel.id);
              if (idx != -1) {
                _doctors[idx] = updatedModel;
              } else {
                _doctors.insert(0, updatedModel);
              }
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.delete && oldRecord.isNotEmpty) {
              final String deletedId = oldRecord['id']?.toString() ?? '';
              _doctors.removeWhere((d) => d.id == deletedId);
              notifyListeners();
            }
          },
        )
        // 3. Medicines (Catalog, prices, stock changes)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'medicines',
          callback: (payload) {
            debugPrint("[SUPABASE_REALTIME] Medicines event: ${payload.eventType}");
            final eventType = payload.eventType;
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;

            if (eventType == PostgresChangeEvent.insert && newRecord.isNotEmpty) {
              final newModel = MedicineModel.fromJson(newRecord);
              _medicines.removeWhere((m) => m.id == newModel.id);
              _medicines.insert(0, newModel);
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.update && newRecord.isNotEmpty) {
              final updatedModel = MedicineModel.fromJson(newRecord);
              final idx = _medicines.indexWhere((m) => m.id == updatedModel.id);
              if (idx != -1) {
                _medicines[idx] = updatedModel;
              } else {
                _medicines.insert(0, updatedModel);
              }
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.delete && oldRecord.isNotEmpty) {
              final String deletedId = oldRecord['id']?.toString() ?? '';
              _medicines.removeWhere((m) => m.id == deletedId);
              notifyListeners();
            }
          },
        )
        // 4. Pharmacy Orders
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) async {
            debugPrint("[SUPABASE_REALTIME] Orders event: ${payload.eventType}");
            final eventType = payload.eventType;
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;

            if (eventType == PostgresChangeEvent.insert && newRecord.isNotEmpty) {
              final String orderId = newRecord['id'].toString();
              List<Map<String, dynamic>> itemsList = [];
              try {
                final itemsData = await client.from('order_items').select().eq('order_id', orderId);
                itemsList = List<Map<String, dynamic>>.from(itemsData);
              } catch (e) {
                debugPrint("[SUPABASE_REALTIME] Order items load notice: $e");
              }
              _orders.removeWhere((o) => o['id'].toString() == orderId);
              _orders.insert(0, Map<String, dynamic>.from(newRecord));
              _orderItems.removeWhere((item) => item['order_id'].toString() == orderId);
              _orderItems.addAll(itemsList);
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.update && newRecord.isNotEmpty) {
              final String orderId = newRecord['id'].toString();
              final idx = _orders.indexWhere((o) => o['id'].toString() == orderId);
              if (idx != -1) {
                _orders[idx] = Map<String, dynamic>.from(newRecord);
              } else {
                _orders.insert(0, Map<String, dynamic>.from(newRecord));
              }
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.delete && oldRecord.isNotEmpty) {
              final String orderId = oldRecord['id']?.toString() ?? '';
              _orders.removeWhere((o) => o['id'].toString() == orderId);
              _orderItems.removeWhere((item) => item['order_id'].toString() == orderId);
              notifyListeners();
            }
          },
        )
        // 5. Nurses
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'nurses',
          callback: (payload) {
            debugPrint("[SUPABASE_REALTIME] Nurses event: ${payload.eventType}");
            final eventType = payload.eventType;
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;

            if (eventType == PostgresChangeEvent.insert && newRecord.isNotEmpty) {
              final newModel = NurseModel.fromJson(newRecord);
              _nurses.removeWhere((n) => n.id == newModel.id);
              _nurses.insert(0, newModel);
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.update && newRecord.isNotEmpty) {
              final updatedModel = NurseModel.fromJson(newRecord);
              final idx = _nurses.indexWhere((n) => n.id == updatedModel.id);
              if (idx != -1) {
                _nurses[idx] = updatedModel;
              } else {
                _nurses.insert(0, updatedModel);
              }
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.delete && oldRecord.isNotEmpty) {
              final String deletedId = oldRecord['id']?.toString() ?? '';
              _nurses.removeWhere((n) => n.id == deletedId);
              notifyListeners();
            }
          },
        )
        // 6. Nurse Dispatch Requests / Orders
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'nurse_orders',
          callback: (payload) {
            debugPrint("[SUPABASE_REALTIME] Nurse Orders event: ${payload.eventType}");
            final eventType = payload.eventType;
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;

            if (eventType == PostgresChangeEvent.insert && newRecord.isNotEmpty) {
              final String orderId = newRecord['id'].toString();
              _nurseOrders.removeWhere((b) => b['id'].toString() == orderId);
              _nurseOrders.insert(0, Map<String, dynamic>.from(newRecord));
              fetchAppointmentsAndNurseOrders();
            } else if (eventType == PostgresChangeEvent.update && newRecord.isNotEmpty) {
              final String orderId = newRecord['id'].toString();
              final idx = _nurseOrders.indexWhere((b) => b['id'].toString() == orderId);
              if (idx != -1) {
                _nurseOrders[idx] = Map<String, dynamic>.from(newRecord);
              } else {
                _nurseOrders.insert(0, Map<String, dynamic>.from(newRecord));
              }
              final nStatus = (newRecord['status'] ?? newRecord['order_status'] ?? '').toString();
              final refId = (newRecord['service_notes'] ?? newRecord['reference_id'] ?? newRecord['booking_id'] ?? '').toString();
              final nurseName = (newRecord['nurse_name'] ?? newRecord['service_type'] ?? '').toString();
              if (nStatus.isNotEmpty) {
                final aptIdx = _appointments.indexWhere((a) =>
                    (refId.isNotEmpty && a.referenceId.contains(refId)) ||
                    (a.referenceId.isNotEmpty && refId.contains(a.referenceId)) ||
                    (nurseName.isNotEmpty && a.doctorName.toLowerCase() == nurseName.toLowerCase()));
                if (aptIdx != -1) {
                  _appointments[aptIdx] = _appointments[aptIdx].copyWith(status: nStatus);
                }
              }
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.delete && oldRecord.isNotEmpty) {
              final String orderId = oldRecord['id']?.toString() ?? '';
              _nurseOrders.removeWhere((b) => b['id'].toString() == orderId);
              notifyListeners();
            }
          },
        )
        // 7. Instant Revenue / Payments
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payments',
          callback: (payload) {
            debugPrint("[SUPABASE_REALTIME] Payments event: ${payload.eventType}");
            final eventType = payload.eventType;
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;

            if (eventType == PostgresChangeEvent.insert && newRecord.isNotEmpty) {
              final String payId = newRecord['id'].toString();
              _payments.removeWhere((p) => p['id'].toString() == payId);
              _payments.insert(0, Map<String, dynamic>.from(newRecord));
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.update && newRecord.isNotEmpty) {
              final String payId = newRecord['id'].toString();
              final idx = _payments.indexWhere((p) => p['id'].toString() == payId);
              if (idx != -1) {
                _payments[idx] = Map<String, dynamic>.from(newRecord);
              } else {
                _payments.insert(0, Map<String, dynamic>.from(newRecord));
              }
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.delete && oldRecord.isNotEmpty) {
              final String payId = oldRecord['id']?.toString() ?? '';
              _payments.removeWhere((p) => p['id'].toString() == payId);
              notifyListeners();
            }
          },
        )
        // 8. Specialties
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'specialties',
          callback: (payload) {
            debugPrint("[SUPABASE_REALTIME] Specialties event: ${payload.eventType}");
            final eventType = payload.eventType;
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;

            if (eventType == PostgresChangeEvent.insert && newRecord.isNotEmpty) {
              final newModel = SpecialtyModel.fromJson(newRecord);
              _specialties.removeWhere((s) => s.id == newModel.id);
              _specialties.insert(0, newModel);
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.update && newRecord.isNotEmpty) {
              final updatedModel = SpecialtyModel.fromJson(newRecord);
              final idx = _specialties.indexWhere((s) => s.id == updatedModel.id);
              if (idx != -1) {
                _specialties[idx] = updatedModel;
              } else {
                _specialties.insert(0, updatedModel);
              }
              notifyListeners();
            } else if (eventType == PostgresChangeEvent.delete && oldRecord.isNotEmpty) {
              final String deletedId = oldRecord['id']?.toString() ?? '';
              _specialties.removeWhere((s) => s.id == deletedId);
              notifyListeners();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'nurse_orders',
          callback: (payload) {
            debugPrint("[SUPABASE_REALTIME] nurse_orders event: ${payload.eventType}");
            fetchAppointmentsAndNurseOrders();
          },
        )
        // 9. Real-time Admin Notifications & Broadcast Messages (Supabase Stream)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (payload) {
            debugPrint("[SUPABASE_REALTIME] Notifications event: ${payload.eventType}");
            final eventType = payload.eventType;
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;

            if (eventType == PostgresChangeEvent.insert && newRecord.isNotEmpty) {
              final String targetUser = (newRecord['target_user_id'] ?? newRecord['target_phone'] ?? newRecord['user_id'] ?? 'all').toString();
              final String currentPhone = (_currentUser?.phoneNumber ?? '').replaceAll(RegExp(r'[\s\-()]+'), '');
              final String currentUserId = _currentUser?.id ?? '';
              
              final bool isForMe = targetUser == 'all' ||
                  targetUser == 'broadcast' ||
                  targetUser.isEmpty ||
                  targetUser == 'null' ||
                  targetUser == currentUserId ||
                  (currentPhone.isNotEmpty && targetUser.contains(currentPhone));

              if (isForMe) {
                final String itemId = newRecord['id'].toString();
                _notifications.removeWhere((n) => n['id'].toString() == itemId);
                _notifications.insert(0, {
                  'id': itemId,
                  'title': newRecord['title'] ?? 'Announcement',
                  'body': newRecord['body'] ?? '',
                  'time': 'Just now',
                  'sender': newRecord['sender_label'] ?? newRecord['sender'] ?? 'Nasiib Hospital Admin',
                  'isRead': false,
                });
                _hasUnreadNotification = true;
                notifyListeners();
              }
            } else if (eventType == PostgresChangeEvent.delete && oldRecord.isNotEmpty) {
              final String itemId = oldRecord['id']?.toString() ?? '';
              _notifications.removeWhere((n) => n['id'].toString() == itemId);
              notifyListeners();
            }
          },
        )
        // 10. Instant Chat Messages
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            debugPrint("[SUPABASE_REALTIME] Messages event: ${payload.eventType}");
            final eventType = payload.eventType;
            final newRecord = payload.newRecord;

            if (eventType == PostgresChangeEvent.insert && newRecord.isNotEmpty) {
              final String msgId = newRecord['id'].toString();
              if (!_chatMessages.any((m) => m['id'].toString() == msgId)) {
                final rawText = newRecord['text'] ?? '';
                final decryptedText = EncryptionService.decrypt(rawText);
                _chatMessages.add({
                  'id': msgId,
                  'sender_id': newRecord['sender_id'] ?? '',
                  'sender_name': newRecord['sender_name'] ?? '',
                  'text': decryptedText,
                  'image_url': newRecord['image_url'] ?? '',
                  'patient_id': newRecord['patient_id'] ?? '',
                  'doctor_id': newRecord['doctor_id'] ?? '',
                  'doctor_name': newRecord['doctor_name'] ?? '',
                  'time': newRecord['created_at'] != null ? newRecord['created_at'].toString() : '',
                  'is_read': newRecord['is_read'] ?? false,
                });
              }
            }
          },
        )
        .subscribe();
  }

  Future<String?> placeOrder({
    required String patientName,
    required String patientPhone,
    required String city,
    required String district,
    required String deliveryAddress,
    required double subtotal,
    required double deliveryFee,
    required double totalAmount,
    required String paymentMethod,
    required String paymentStatus,
    required List<Map<String, dynamic>> items,
  }) async {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) return null;

    try {
      final String hexSuffix = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
      final String orderNum = '#ORD-$hexSuffix';
      final String orderId = DateTime.now().millisecondsSinceEpoch.toString();

      final orderPayload = {
        'id': orderId,
        'order_number': orderNum,
        'customer_name': patientName,
        'patient_name': patientName,
        'phone': patientPhone,
        'patient_phone': patientPhone,
        'city': city,
        'district': district,
        'neighborhood': deliveryAddress,
        'customer_address': '$deliveryAddress, $district, $city',
        'delivery_address': deliveryAddress,
        'subtotal': subtotal,
        'delivery_fee': deliveryFee,
        'total_amount': totalAmount,
        'payment_method': paymentMethod,
        'payment_status': paymentStatus,
        'status': 'Pending',
        'tracking_number': 'TRK-$hexSuffix',
        'current_location': 'Warehouse',
        'estimated_delivery': '30-45 mins',
        'created_at': DateTime.now().toIso8601String(),
      };

      Map<String, dynamic>? insertedOrder;
      try {
        final res = await client.from('orders').insert(orderPayload).select().maybeSingle();
        if (res != null) {
          insertedOrder = Map<String, dynamic>.from(res);
        }
      } on PostgrestException catch (pgErr) {
        debugPrint("[SUPABASE_ORDER_ERROR] PostgrestException: ${pgErr.message} | Details: ${pgErr.details}");
      } catch (err) {
        debugPrint("[SUPABASE_ORDER_ERROR] Error inserting order: $err");
      }

      final String finalOrderId = insertedOrder != null && insertedOrder['id'] != null
          ? insertedOrder['id'].toString()
          : orderId;

      _orders.removeWhere((o) => o['id'].toString() == finalOrderId);
      _orders.insert(0, insertedOrder ?? Map<String, dynamic>.from(orderPayload));

      for (var item in items) {
        final itemPayload = {
          'order_id': finalOrderId,
          'medicine_name': item['name'] ?? item['title'] ?? 'Medicine Item',
          'quantity': item['quantity'] ?? 1,
          'unit_price': item['price'] ?? 0.0,
          'total_price':
              ((item['price'] ?? 0.0) as num).toDouble() *
              ((item['quantity'] ?? 1) as num).toInt(),
          'created_at': DateTime.now().toIso8601String(),
        };
        try {
          await client.from('order_items').insert(itemPayload);
        } catch (e) {
          debugPrint("[SUPABASE_ORDER_ITEMS_ERROR] Failed inserting order item: $e");
        }
        _orderItems.add(itemPayload);
      }

      await client.from('payments').insert({
        'order_id': orderId,
        'patient_name': patientName,
        'patient_phone': patientPhone,
        'payment_method': paymentMethod,
        'amount': totalAmount,
        'status': paymentStatus == 'Paid' ? 'Completed' : 'Pending',
        'transaction_id': 'TXN-${DateTime.now().millisecondsSinceEpoch}',
        'created_at': DateTime.now().toIso8601String(),
      });

      notifyListeners();
      return finalOrderId;
    } catch (e) {
      debugPrint('[ORDERS] Error in placeOrder: $e');
      return null;
    }
  }

  /// Place Nurse Booking Order directly in nurse_orders table
  Future<String?> placeNurseOrder({
    required String nurseId,
    required String nurseName,
    required String patientName,
    required String phone,
    required String district,
    required String address,
    required String notes,
    required double fee,
    required String paymentMethod,
    String status = 'Pending',
  }) async {
    final String hexSuffix = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    final String bookingId = 'NURSE-$hexSuffix';

    String? cleanNurseId;
    if (RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(nurseId)) {
      cleanNurseId = nurseId;
    }
    String? cleanPatientId;
    if (_currentUser != null && RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(_currentUser!.id)) {
      cleanPatientId = _currentUser!.id;
    }
    NurseModel? matchingNurse;
    for (final n in _nurses) {
      if ((cleanNurseId != null && n.id == cleanNurseId) ||
          n.name.toLowerCase().trim() == nurseName.toLowerCase().trim() ||
          nurseName.toLowerCase().contains(n.name.toLowerCase())) {
        matchingNurse = n;
        break;
      }
    }

    final String nurseImg = matchingNurse?.imageUrl ?? 'https://images.unsplash.com/photo-1559839734-2b71ea197ec2?w=500';

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        final cleanNursePayload = <String, dynamic>{
          'nurse_name': nurseName,
          'customer_name': patientName,
          'phone': phone,
          'district': district,
          'neighborhood': address,
          'amount_paid': fee,
          'payment_method': paymentMethod,
          'payment_status': 'paid',
          'status': 'pending',
          'service_notes': '#NURSE-$hexSuffix',
        };
        if (nurseImg.isNotEmpty) {
          cleanNursePayload['nurse_image'] = nurseImg;
        }
        if (cleanPatientId != null) cleanNursePayload['patient_id'] = cleanPatientId;
        if (cleanNurseId != null) cleanNursePayload['nurse_id'] = cleanNurseId;

        try {
          await client.from('nurse_orders').insert(cleanNursePayload);
          debugPrint('[NURSE_ORDERS] Inserted into nurse_orders successfully (Tier 1)');
        } catch (tier1Err) {
          debugPrint('[NURSE_ORDERS] Tier 1 error: $tier1Err, trying Tier 2 standard...');
          try {
            final standardPayload = <String, dynamic>{
              'nurse_name': nurseName,
              'customer_name': patientName,
              'phone': phone,
              'district': district,
              'amount_paid': fee,
              'payment_method': paymentMethod,
              'status': 'pending',
              'service_notes': '#NURSE-$hexSuffix',
            };
            await client.from('nurse_orders').insert(standardPayload);
            debugPrint('[NURSE_ORDERS] Inserted into nurse_orders successfully (Tier 2)');
          } catch (tier2Err) {
            debugPrint('[NURSE_ORDERS] Tier 2 error: $tier2Err, trying Tier 3 minimal...');
            try {
              final minimalPayload = <String, dynamic>{
                'nurse_name': nurseName,
                'customer_name': patientName,
                'phone': phone,
                'amount_paid': fee,
                'service_notes': '#NURSE-$hexSuffix',
              };
              await client.from('nurse_orders').insert(minimalPayload);
              debugPrint('[NURSE_ORDERS] Inserted into nurse_orders successfully (Tier 3)');
            } catch (tier3Err) {
              debugPrint('[NURSE_ORDERS] Tier 3 error: $tier3Err');
            }
          }
        }

        try {
          final ordersPayload = <String, dynamic>{
            'customer_name': patientName,
            'phone': phone,
            'total_amount': fee,
            'payment_method': paymentMethod,
            'order_type': 'nurse',
            'type': 'nurse',
            'service_notes': '#NURSE-$hexSuffix',
            'status': 'pending',
          };
          await client.from('orders').insert(ordersPayload);
        } catch (_) {}

        // Automatically set the booked Nurse to Busy (Auto-Lock)
        try {
          if (cleanNurseId != null) {
            await client.from('nurses').update({
              'is_available': false,
              'status': 'busy',
            }).eq('id', cleanNurseId);
          } else {
            await client.from('nurses').update({
              'is_available': false,
              'status': 'busy',
            }).eq('name', nurseName);
          }
        } catch (_) {}
      } catch (e) {
        debugPrint('[NURSE_ORDERS] placeNurseOrder supabase handling error: $e');
      }
    }

    // Persist this nurse booking to user's booked IDs & local cache
    _userBookedAppointmentIds.add(bookingId);
    _userBookedAppointmentIds.add('#NURSE-$hexSuffix');
    if (phone.isNotEmpty) _userBookedAppointmentIds.add(phone);
    _saveUserBookedAppointmentIdsToPrefs();

    final localNurseAppointment = AppointmentModel(
      id: 'nurse_$hexSuffix',
      referenceId: '#NURSE-$hexSuffix',
      doctorId: nurseId.isNotEmpty ? nurseId : 'nurse_dispatch',
      doctorName: 'Nurse ($nurseName)',
      doctorSpecialty: 'Home Care Service',
      doctorImageUrl: nurseImg,
      hospitalName: 'Nasiib Home Care',
      date: 'Today',
      time: 'Flexible Dispatch',
      appointmentType: 'Home Care',
      patientName: patientName,
      patientPhone: phone,
      patientAge: 30,
      patientGender: 'Flexible',
      reasonForVisit: notes.isNotEmpty ? notes : 'Home Care Request',
      paymentMethod: paymentMethod,
      amount: fee,
      queueNumber: 1,
      status: 'Pending',
      createdAt: DateTime.now().toIso8601String(),
    );

    final existingIdx = _appointments.indexWhere((a) => a.id == localNurseAppointment.id || a.referenceId == localNurseAppointment.referenceId);
    if (existingIdx != -1) {
      _appointments[existingIdx] = localNurseAppointment;
    } else {
      _appointments.insert(0, localNurseAppointment);
    }
    _saveLocalAppointmentsToPrefs();
    notifyListeners();

    // Send instant push notification ONLY to this patient's own device
    try {
      PushNotificationService.instance.showLocalNotification(
        title: 'Nasiib Home Care',
        body: 'Waan helnay codsigaaga kalkaaliso, dhakhso ayaan kuugu soo jawaabi doonaa.',
      );
    } catch (_) {}

    return bookingId;
  }

  /// Toggle or update Nurse availability (Available vs Busy)
  Future<bool> setNurseAvailability(String nurseIdOrName, bool isAvailable) async {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) return false;

    try {
      final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(nurseIdOrName);
      if (isUuid) {
        await client.from('nurses').update({
          'is_available': isAvailable,
          'status': isAvailable ? 'available' : 'busy',
        }).eq('id', nurseIdOrName);
      } else {
        await client.from('nurses').update({
          'is_available': isAvailable,
          'status': isAvailable ? 'available' : 'busy',
        }).eq('name', nurseIdOrName);
      }

      await fetchAppointmentsAndNurseOrders();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[NURSE_AVAILABILITY] Error: $e');
      return false;
    }
  }

  Future<bool> updateOrderStatus(String orderId, String newStatus) async {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) return false;

    try {
      String location = 'Warehouse';
      if (newStatus == 'Accepted' || newStatus == 'Preparing') {
        location = 'Pharmacy Prep Room';
      } else if (newStatus == 'Ready' || newStatus == 'Ready for Delivery') {
        location = 'Dispatch Counter';
      } else if (newStatus == 'Out for Delivery') {
        location = 'On the way to customer';
      } else if (newStatus == 'Delivered') {
        location = 'Delivered to Patient';
      } else if (newStatus == 'Cancelled') {
        location = 'Order Cancelled';
      }

      await client
          .from('orders')
          .update({'status': newStatus, 'current_location': location})
          .eq('id', orderId);

      final idx = _orders.indexWhere((o) => o['id'].toString() == orderId);
      if (idx != -1) {
        _orders[idx]['status'] = newStatus;
        _orders[idx]['current_location'] = location;
      }
      notifyListeners();

      // Trigger FCM Push Notification for ALL order status updates
      String notificationTitle = 'Nasiib Pharmacy Update';
      String notificationBody = 'Status-ka dalabkaaga wuxuu noqday: $newStatus';

      if (newStatus == 'Accepted') {
        notificationBody = 'Dalabkaaga dawooyinka waa la aqbalay!';
      } else if (newStatus == 'Preparing') {
        notificationBody = 'Dawooyinkaaga waa la diyaarinayaa...';
      } else if (newStatus == 'Ready' || newStatus == 'Ready for Delivery') {
        notificationBody = 'Dalabkaaga dawooyinka waa la diyaariyay!';
      } else if (newStatus == 'Out for Delivery') {
        notificationBody = 'Dalabkaaga dawooyinka wuxuu ku jiraa jidka!';
      } else if (newStatus == 'Delivered') {
        notificationBody = 'Dalabkaaga dawooyinka waa la gaarsiiyay. Waad mahadsan tahay!';
      } else if (newStatus == 'Cancelled') {
        notificationBody = 'Dalabkaaga dawooyinka waa la kansalay.';
      }

      // Trigger FCM Push Notification strictly to THIS specific customer's private channel
      try {
        final orderData = _orders.firstWhere((o) => o['id'].toString() == orderId, orElse: () => {});
        final pPhone = (orderData['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
        final pId = (orderData['patient_id'] ?? orderData['user_id'] ?? '').toString();
        final targetTopic = pId.isNotEmpty ? 'user_$pId' : (pPhone.isNotEmpty ? 'user_$pPhone' : null);

        if (targetTopic != null) {
          FcmSender().sendTopicNotification(
            topic: targetTopic,
            title: notificationTitle,
            body: notificationBody,
          );
        }
      } catch (fcmErr) {
        debugPrint('[ORDER_NOTIFICATION] Error routing notification: $fcmErr');
      }

      return true;
    } catch (e) {
      debugPrint("Failed to update order status in Supabase: $e");
      return false;
    }
  }

  /// Fetch orders belonging to the current user by user_id, patient_id, OR phone.
  /// Called from MyOrdersScreen.initState() to ensure the list is always fresh.
  Future<void> fetchUserOrders() async {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) return;

    try {
      final supabaseUser = client.auth.currentUser;
      final phone = (_currentUser?.phoneNumber ?? '').trim();
      final name = (_currentUser?.fullName ?? '').trim();

      List<dynamic> response = [];

      // ── Step 1: Try user-scoped query ──────────────────────────────────
      if (supabaseUser != null) {
        // Authenticated Supabase user — filter by user_id
        try {
          response = await client
              .from('orders')
              .select()
              .eq('user_id', supabaseUser.id)
              .order('created_at', ascending: false);
        } catch (_) {}

        // If no orders found by user_id, try phone
        if (response.isEmpty && phone.isNotEmpty) {
          try {
            response = await client
                .from('orders')
                .select()
                .eq('patient_phone', phone)
                .order('created_at', ascending: false);
          } catch (_) {}
        }
      } else if (phone.isNotEmpty) {
        // No Supabase auth user but we have a phone number
        try {
          response = await client
              .from('orders')
              .select()
              .eq('patient_phone', phone)
              .order('created_at', ascending: false);
        } catch (_) {}
      }
      // ── Step 3: Replace _orders cleanly ───────────────────────────────
      final List<Map<String, dynamic>> freshList = response
          .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
          .toList();

      // Merge: preserve any Realtime-only records not in the fresh fetch,
      // update existing ones with the freshly fetched copy.
      for (final record in freshList) {
        final String id = record['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final idx = _orders.indexWhere((o) => o['id']?.toString() == id);
        if (idx != -1) {
          _orders[idx] = record;
        } else {
          _orders.insert(0, record);
        }
      }

      notifyListeners();
      debugPrint('[ORDERS] fetchUserOrders → ${response.length} orders loaded');
    } catch (e) {
      debugPrint('[ORDERS] fetchUserOrders error: $e');
    }
  }

  /// Fetch ALL orders from Supabase for the Web Admin / Pharmacy panel.
  /// Called on page reload so the list never disappears on browser refresh.
  Future<void> fetchPharmacyOrders() async {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) return;

    try {
      final data = await client
          .from('orders')
          .select()
          .order('created_at', ascending: false);

      // Merge fetched records into _orders without wiping Realtime data.
      for (final row in data) {
        final Map<String, dynamic> record = Map<String, dynamic>.from(row);
        final String id = record['id']?.toString() ?? '';
        final idx = _orders.indexWhere((o) => o['id']?.toString() == id);
        if (idx != -1) {
          _orders[idx] = record;
        } else {
          _orders.add(record);
        }
      }

      // Also fetch order items
      try {
        final itemsData = await client.from('order_items').select();
        for (final row in itemsData) {
          final Map<String, dynamic> item = Map<String, dynamic>.from(row);
          final String orderId = item['order_id']?.toString() ?? '';
          _orderItems.removeWhere((i) =>
              i['id']?.toString() == item['id']?.toString());
          if (orderId.isNotEmpty) _orderItems.add(item);
        }
      } catch (_) {}

      notifyListeners();
      debugPrint('[ORDERS] fetchPharmacyOrders → ${data.length} orders loaded');
    } catch (e) {
      debugPrint('[ORDERS] fetchPharmacyOrders error: $e');
    }
  }

  Future<bool> deleteOrder(String orderId) async {
    // 1. Remove from local patient view immediately
    _orders.removeWhere((o) => o['id']?.toString() == orderId || o['order_number']?.toString() == orderId);
    notifyListeners();

    // 2. Soft-delete / status update in Supabase without deleting the database row
    // This preserves all sales, revenue cards, and accounting logs for hospital admins.
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        await client.from('orders').update({
          'status': 'Cancelled',
          'is_deleted_by_patient': true,
        }).eq('id', orderId);
      } catch (e) {
        try {
          await client.from('orders').update({'status': 'Cancelled'}).eq('id', orderId);
        } catch (err) {
          debugPrint("[ORDERS] Soft delete update error: $err");
        }
      }
    }
    return true;
  }

  bool _globalDoctorOnlineStatus = true;
  bool get globalDoctorOnlineStatus => _globalDoctorOnlineStatus;

  String getLoggedInDoctorId(String userRole, String? userEmail) {
    if (_doctors.isEmpty) return '1';
    final email = (userEmail ?? '').toLowerCase();
    if (email.contains('mukhtar')) {
      for (var d in _doctors) {
        if (d.name.toLowerCase().contains('mukhtar')) return d.id;
      }
    }
    final cleanEmailPrefix = email
        .split('@')[0]
        .replaceAll('dr', '')
        .replaceAll('.', '')
        .replaceAll('_', '');
    for (var doc in _doctors) {
      final cleanDocName = doc.name
          .toLowerCase()
          .replaceAll('dr', '')
          .replaceAll('.', '')
          .replaceAll(' ', '')
          .replaceAll('_', '');
      if (cleanEmailPrefix.isNotEmpty &&
          (cleanDocName.contains(cleanEmailPrefix) ||
              cleanEmailPrefix.contains(cleanDocName))) {
        return doc.id;
      }
    }
    return _doctors.first.id;
  }

  Future<bool> setDoctorOnlineStatus(String doctorId, bool isOnline) async {
    final client = SupabaseService.instance.client;
    final nowIso = DateTime.now().toIso8601String();

    final cleanId = doctorId.replaceAll('doc_', '');
    _doctorAvailabilityMap[doctorId] = isOnline;
    _doctorAvailabilityMap[cleanId] = isOnline;
    _doctorAvailabilityMap['doc_$cleanId'] = isOnline;

    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        final dynamic idValue = int.tryParse(cleanId) ?? doctorId;
        final updatePayload = {'is_online': isOnline, 'last_seen': nowIso};

        var res = await client
            .from('doctors')
            .update(updatePayload)
            .eq('id', doctorId)
            .select();

        if (res.isEmpty) {
          res = await client
              .from('doctors')
              .update(updatePayload)
              .eq('id', idValue)
              .select();
        }

        if (res.isNotEmpty) {
          final confirmedDoc = DoctorModel.fromJson(
            Map<String, dynamic>.from(res.first),
          );
          for (int i = 0; i < _doctors.length; i++) {
            if (_doctors[i].id == doctorId ||
                _doctors[i].id == confirmedDoc.id ||
                _doctors[i].id == 'doc_${confirmedDoc.id}') {
              _doctors[i] = _doctors[i].copyWith(
                isOnline: confirmedDoc.isOnline,
                isAvailable: confirmedDoc.isOnline,
                lastSeen: nowIso,
              );
            }
          }
          notifyListeners();
          return true;
        }
      } catch (e) {
        debugPrint("[DOCTOR_STATUS] Supabase UPDATE failed: $e");
      }
    }

    // Local update fallback if offline
    for (int i = 0; i < _doctors.length; i++) {
      if (_doctors[i].id == doctorId ||
          _doctors[i].id == 'doc_$doctorId' ||
          doctorId == 'doc_${_doctors[i].id}') {
        _doctors[i] = _doctors[i].copyWith(
          isOnline: isOnline,
          isAvailable: isOnline,
          lastSeen: nowIso,
        );
      }
    }
    notifyListeners();
    return false;
  }

  Future<void> toggleDoctorAvailability(
    String doctorId,
    bool isAvailable,
  ) async {
    await setDoctorOnlineStatus(doctorId, isAvailable);
  }

  Future<bool> toggleDoctorChatVisibility(
    String doctorId,
    bool showInChat,
  ) async {
    final client = SupabaseService.instance.client;
    final cleanId = doctorId.replaceAll('doc_', '');
    final dynamic idValue = int.tryParse(cleanId) ?? doctorId;

    for (int i = 0; i < _doctors.length; i++) {
      if (_doctors[i].id == doctorId ||
          _doctors[i].id == cleanId ||
          _doctors[i].id == 'doc_$cleanId') {
        _doctors[i] = _doctors[i].copyWith(showInChat: showInChat);
      }
    }
    notifyListeners();

    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        final payload = {'show_in_chat': showInChat};
        var res = await client
            .from('doctors')
            .update(payload)
            .eq('id', doctorId)
            .select();

        if (res.isEmpty) {
          res = await client
              .from('doctors')
              .update(payload)
              .eq('id', idValue)
              .select();
        }

        if (res.isNotEmpty) {
          final confirmedDoc = DoctorModel.fromJson(
            Map<String, dynamic>.from(res.first),
          );
          for (int i = 0; i < _doctors.length; i++) {
            if (_doctors[i].id == doctorId ||
                _doctors[i].id == confirmedDoc.id ||
                _doctors[i].id == 'doc_${confirmedDoc.id}') {
              _doctors[i] = _doctors[i].copyWith(
                showInChat: confirmedDoc.showInChat,
              );
            }
          }
          notifyListeners();
          return true;
        }
      } catch (e) {
        debugPrint(
          "[CHAT_VISIBILITY] Supabase UPDATE notice (column may be missing in legacy table): $e",
        );
      }
    }
    return false;
  }

  Future<void> setPatientTyping(bool isTyping) async {
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        await client
            .from('patients')
            .update({'is_typing': isTyping})
            .eq('id', _currentUser?.id ?? 'usr_1');
      } catch (e) {
        debugPrint("Failed to update patient typing status in Supabase: $e");
      }
    }
  }

  Future<void> setDoctorTyping(String doctorId, bool isTyping) async {
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        final cleanId = doctorId.replaceAll('doc_', '');
        await client
            .from('doctors')
            .update({'is_typing': isTyping})
            .eq('id', cleanId);
      } catch (e) {
        debugPrint("Failed to update doctor typing status in Supabase: $e");
      }
    }
  }

  Future<void> markDoctorMessagesAsRead(String doctorName) async {
    bool updated = false;
    for (var msg in _chatMessages) {
      if (msg['sender_name'] == doctorName &&
          msg['sender_id'] == 'doctor' &&
          msg['is_read'] != true) {
        msg['is_read'] = true;
        updated = true;
      }
    }
    if (updated) {
      notifyListeners();
    }

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        await client
            .from('messages')
            .update({'is_read': true})
            .eq('sender_name', doctorName)
            .eq('sender_id', 'doctor');
      } catch (e) {
        debugPrint("Failed to mark doctor messages as read: $e");
      }
    }
  }

  Future<void> markMessagesAsRead(String patientId) async {
    bool updated = false;
    for (var msg in _chatMessages) {
      if (msg['patient_id'] == patientId &&
          msg['sender_id'] != 'doctor' &&
          msg['is_read'] != true) {
        msg['is_read'] = true;
        updated = true;
      }
    }
    if (updated) {
      notifyListeners();
    }

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        await client
            .from('messages')
            .update({'is_read': true})
            .eq('patient_id', patientId)
            .neq('sender_id', 'doctor');
      } catch (e) {
        debugPrint("Failed to mark messages as read: $e");
      }
    }
  }

  Future<void> deleteMessage(String msgId) async {
    _chatMessages.removeWhere((m) => m['id'] == msgId);
    notifyListeners();

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        final parsedId = int.tryParse(msgId);
        if (parsedId != null) {
          await client.from('messages').delete().eq('id', parsedId);
        } else {
          await client.from('messages').delete().eq('id', msgId);
        }
        debugPrint("Deleted message $msgId from Supabase");
      } catch (e) {
        debugPrint("Failed to delete message: $e");
      }
    }
  }

  Future<void> deleteNotification(String id) async {
    _notifications.removeWhere((n) => n['id'] == id);
    notifyListeners();

    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      try {
        final parsedId = int.tryParse(id);
        if (parsedId != null) {
          await client.from('notifications').delete().eq('id', parsedId);
        } else {
          await client.from('notifications').delete().eq('id', id);
        }
        debugPrint("Deleted notification $id from Supabase");
      } catch (e) {
        debugPrint("Failed to delete notification from Supabase: $e");
      }
    }
  }

  List<Map<String, dynamic>> _dbNurseOrders = [];
  List<Map<String, dynamic>> get dbNurseOrders => _dbNurseOrders;

  /// Fetch persistent Doctor Appointments & Nurse Visits from Supabase
  Future<void> fetchAppointmentsAndNurseOrders() async {
    final client = SupabaseService.instance.client;
    if (client == null || !SupabaseService.instance.isInitialized) return;

    final targetPhone = _currentUser?.phoneNumber ?? FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
    final String cleanPhone = targetPhone.replaceAll(RegExp(r'\D'), '');
    String baseDigits = cleanPhone;
    if (baseDigits.startsWith('252') && baseDigits.length >= 12) {
      baseDigits = baseDigits.substring(3);
    }
    if (baseDigits.startsWith('0') && baseDigits.length >= 10) {
      baseDigits = baseDigits.substring(1);
    }
    
    final possibleFormats = [
      targetPhone,
      cleanPhone,
      baseDigits,
      '0$baseDigits',
      '252$baseDigits',
      '+252$baseDigits',
      _currentUser?.id ?? '',
    ].where((s) => s.isNotEmpty).toSet().toList();

    try {
      await _loadUserBookedAppointmentIdsFromPrefs();
      await _loadDeletedAppointmentIdsFromPrefs();
      final localCached = await _loadLocalAppointmentsFromPrefs();

      final List<AppointmentModel> updatedList = [];

      // Include all valid non-deleted locally cached appointments
      for (final lApt in localCached) {
        if (_deletedAppointmentIds.contains(lApt.id) ||
            (lApt.referenceId.isNotEmpty && _deletedAppointmentIds.contains(lApt.referenceId))) {
          continue;
        }
        if (lApt.id.isNotEmpty) _userBookedAppointmentIds.add(lApt.id);
        if (lApt.referenceId.isNotEmpty) _userBookedAppointmentIds.add(lApt.referenceId);
        if (lApt.patientPhone.isNotEmpty) _userBookedAppointmentIds.add(lApt.patientPhone);
        updatedList.add(lApt);
      }

      // 1. Fetch Doctor Appointments exclusively for this patient
      final aptData = await client
          .from('appointments')
          .select()
          .order('created_at', ascending: false);

      if (aptData is List) {
        for (final row in aptData) {
          try {
            final apt = AppointmentModel.fromJson(Map<String, dynamic>.from(row));
            // Skip appointments deleted by this user
            if (_deletedAppointmentIds.contains(apt.id) ||
                (apt.referenceId.isNotEmpty && _deletedAppointmentIds.contains(apt.referenceId))) {
              continue;
            }

            // Match if booked on this device/account OR matches phone/name/user_id
            final bool isBookedByMe = _userBookedAppointmentIds.contains(apt.id) ||
                (apt.referenceId.isNotEmpty && _userBookedAppointmentIds.contains(apt.referenceId)) ||
                (apt.patientPhone.isNotEmpty && _userBookedAppointmentIds.contains(apt.patientPhone));

            final String aptPhone = apt.patientPhone.replaceAll(RegExp(r'\D'), '');
            final bool matchesPhone = possibleFormats.isNotEmpty && possibleFormats.any((f) {
              final cleanF = f.replaceAll(RegExp(r'\D'), '');
              return (cleanF.isNotEmpty && (aptPhone.contains(cleanF) || cleanF.contains(aptPhone))) || apt.patientPhone.contains(f);
            });

            final bool matchesName = _currentUser != null &&
                apt.patientName.trim().isNotEmpty &&
                (apt.patientName.trim().toLowerCase() == _currentUser!.fullName.trim().toLowerCase());

            final String rowUserId = (row['user_id'] ?? row['patient_id'] ?? '').toString();
            final bool matchesUserId = _currentUser != null && rowUserId.isNotEmpty && rowUserId == _currentUser!.id;

            if (!isBookedByMe && !matchesPhone && !matchesName && !matchesUserId) {
              continue; // Skip appointments belonging to other users
            }

            // Ensure tracked in user booked IDs
            if (apt.id.isNotEmpty) _userBookedAppointmentIds.add(apt.id);
            if (apt.referenceId.isNotEmpty) _userBookedAppointmentIds.add(apt.referenceId);
            if (apt.patientPhone.isNotEmpty) _userBookedAppointmentIds.add(apt.patientPhone);

            final idx = updatedList.indexWhere((a) =>
                a.id == apt.id ||
                (a.referenceId.isNotEmpty && a.referenceId == apt.referenceId));
            if (idx != -1) {
              updatedList[idx] = apt;
            } else {
              updatedList.add(apt);
            }
          } catch (_) {}
        }
      }

      // 2. Fetch Nurse Orders for this patient
      try {
        final nurseData = await client
            .from('nurse_orders')
            .select()
            .order('created_at', ascending: false);

        if (nurseData is List) {
          _dbNurseOrders = List<Map<String, dynamic>>.from(nurseData);
          for (final nRow in _dbNurseOrders) {
            final nId = (nRow['id'] ?? nRow['booking_id'] ?? '').toString();
            final refId = (nRow['service_notes'] ?? nRow['reference_id'] ?? nRow['booking_id'] ?? '').toString();
            if (_deletedAppointmentIds.contains(nId) || (refId.isNotEmpty && _deletedAppointmentIds.contains(refId))) {
              continue; // Skip deleted nurse orders
            }

            final bool isNurseBookedByMe = (nId.isNotEmpty && _userBookedAppointmentIds.contains(nId)) ||
                (refId.isNotEmpty && _userBookedAppointmentIds.contains(refId));

            final phone = (nRow['phone'] ?? nRow['patient_phone'] ?? '').toString();
            final String cleanNPhone = phone.replaceAll(RegExp(r'\D'), '');
            final bool matchesNPhone = possibleFormats.isNotEmpty && possibleFormats.any((f) {
              final cleanF = f.replaceAll(RegExp(r'\D'), '');
              return (cleanF.isNotEmpty && (cleanNPhone.contains(cleanF) || cleanF.contains(cleanNPhone))) || phone.contains(f);
            });

            final String custName = (nRow['customer_name'] ?? nRow['patient_name'] ?? '').toString().trim().toLowerCase();
            final bool matchesNName = _currentUser != null && custName.isNotEmpty && custName == _currentUser!.fullName.trim().toLowerCase();

            final String nUserId = (nRow['patient_id'] ?? nRow['user_id'] ?? '').toString();
            final bool matchesNUserId = _currentUser != null && nUserId.isNotEmpty && nUserId == _currentUser!.id;

            if (!isNurseBookedByMe && !matchesNPhone && !matchesNName && !matchesNUserId) {
              continue;
            }

            if (nId.isNotEmpty) _userBookedAppointmentIds.add(nId);
            if (refId.isNotEmpty) _userBookedAppointmentIds.add(refId);

            final nStatus = (nRow['status'] ?? nRow['order_status'] ?? 'pending').toString();
            final nurseName = (nRow['nurse_name'] ?? nRow['service_type'] ?? 'Home Care Nurse').toString();
            final patientName = (nRow['customer_name'] ?? nRow['patient_name'] ?? (_currentUser?.fullName ?? 'Patient')).toString();
            final fee = (nRow['amount_paid'] ?? nRow['fee'] ?? nRow['total_amount'] ?? 0.0);
            final double amount = (fee is num) ? fee.toDouble() : (double.tryParse(fee.toString()) ?? 3.0);
            final paymentMethod = (nRow['payment_method'] ?? 'EVC Plus').toString();

            final String uniqueNurseId = 'nurse_${nId.isNotEmpty ? nId : refId.replaceAll(RegExp(r'\D'), '')}';

            NurseModel? matchingNurse;
            for (final n in _nurses) {
              if (n.id == (nRow['nurse_id']?.toString() ?? '') ||
                  n.name.toLowerCase().trim() == nurseName.toLowerCase().trim() ||
                  nurseName.toLowerCase().contains(n.name.toLowerCase())) {
                matchingNurse = n;
                break;
              }
            }

            final String resolvedNurseImage = (nRow['nurse_image'] ?? nRow['nurse_avatar_url'] ?? nRow['image_url'] ?? matchingNurse?.imageUrl ?? '').toString().trim();

            final String finalNurseImg = resolvedNurseImage.isNotEmpty
                ? resolvedNurseImage
                : (matchingNurse?.imageUrl ?? 'https://images.unsplash.com/photo-1559839734-2b71ea197ec2?w=500');

            final idx = updatedList.indexWhere((a) =>
                a.id == uniqueNurseId ||
                (refId.isNotEmpty && a.referenceId == refId) ||
                (nId.isNotEmpty && a.id == nId));

            if (idx != -1) {
              updatedList[idx] = updatedList[idx].copyWith(
                status: nStatus,
                doctorImageUrl: finalNurseImg,
              );
            } else {
              updatedList.add(
                AppointmentModel(
                  id: uniqueNurseId,
                  referenceId: refId.isNotEmpty ? refId : '#NURSE-${Random().nextInt(99999)}',
                  doctorId: 'nurse_dispatch',
                  doctorName: 'Nurse ($nurseName)',
                  doctorSpecialty: 'Home Care Service',
                  doctorImageUrl: finalNurseImg,
                  hospitalName: 'Nasiib Home Care',
                  date: 'Today',
                  time: 'Flexible Dispatch',
                  appointmentType: 'Home Care',
                  patientName: patientName,
                  patientPhone: phone.isNotEmpty ? phone : (_currentUser?.phoneNumber ?? ''),
                  patientAge: 30,
                  patientGender: 'Flexible',
                  reasonForVisit: (nRow['service_notes'] ?? 'Home Care Request').toString(),
                  paymentMethod: paymentMethod,
                  amount: amount,
                  queueNumber: 1,
                  status: nStatus,
                  createdAt: (nRow['created_at'] ?? DateTime.now().toIso8601String()).toString(),
                ),
              );
            }
          }
        }
      } catch (err) {
        debugPrint('[NURSE_ORDERS] Fetch error: $err');
      }

      _saveUserBookedAppointmentIdsToPrefs();

      // Robust DateTime parsing to guarantee the newest booking is ALWAYS on top
      DateTime parseDateSafe(String raw) {
        if (raw.trim().isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
        final dt = DateTime.tryParse(raw.trim());
        if (dt != null) return dt;
        final intVal = int.tryParse(raw.trim());
        if (intVal != null) return DateTime.fromMillisecondsSinceEpoch(intVal);
        return DateTime.fromMillisecondsSinceEpoch(0);
      }

      // Sort by creation date descending (newest on top)
      updatedList.sort((a, b) => parseDateSafe(b.createdAt).compareTo(parseDateSafe(a.createdAt)));
      _appointments.clear();
      _appointments.addAll(updatedList);
      _saveLocalAppointmentsToPrefs();

      notifyListeners();
      debugPrint('[APPOINTMENTS] Loaded ${_appointments.length} appointments & nurse orders.');
    } catch (e) {
      debugPrint('[APPOINTMENTS] fetchAppointmentsAndNurseOrders error: $e');
    }
  }
}
