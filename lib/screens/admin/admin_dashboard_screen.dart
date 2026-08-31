import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/doctor_model.dart';
import '../../models/medicine_model.dart';

import '../../models/appointment_model.dart';
import '../../models/nurse_model.dart';
import '../../services/app_state.dart';
import '../../services/image_picker_service.dart';
import '../../services/supabase_service.dart';
import '../../services/encryption_service.dart';
import '../driver/driver_portal_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/print_service.dart';
import '../../services/fcm_sender.dart';
import '../../services/email_otp_service.dart';
import '../../widgets/network_or_asset_image.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _getDoctorAvatar(AppState appState) {
    final String docId = _currentUserRole == 'Admin' ? '1' : '2';
    final doc = appState.doctors.firstWhere(
      (d) => d.id == docId,
      orElse: () => DoctorModel(
        id: '',
        name: '',
        specialty: '',
        hospital: '',
        rating: 0,
        reviewsCount: 0,
        experience: '',
        patientsCount: '',
        workingHours: '',
        about: '',
        consultationFee: 0,
        imageUrl: '',
      ),
    );
    if (doc.imageUrl.isNotEmpty) return doc.imageUrl;
    return '';
  }

  String _getPatientAvatar(AppState appState, String patientIdOrName) {
    final p = appState.dbPatients.firstWhere(
      (pat) =>
          pat['full_name'] == patientIdOrName || pat['id'] == patientIdOrName,
      orElse: () => {},
    );
    if (p.isNotEmpty &&
        p['avatar_url'] != null &&
        p['avatar_url'].toString().isNotEmpty) {
      return p['avatar_url'];
    }
    return '';
  }

  Widget _buildDocumentImage(String docUrl) {
    if (docUrl.startsWith('data:image')) {
      try {
        final base64Str = docUrl.split(',')[1];
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            base64Decode(base64Str),
            height: 120,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        );
      } catch (e) {
        return const Icon(Icons.broken_image_rounded);
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        docUrl,
        height: 120,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          height: 120,
          color: Colors.grey.shade100,
          child: const Center(
            child: Icon(Icons.file_present_rounded, color: Colors.blue),
          ),
        ),
      ),
    );
  }

  Widget _buildChatImage(String imageUrl) {
    return Image.network(
      imageUrl,
      key: ValueKey(imageUrl),
      width: 220,
      height: 140,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: 220,
          height: 140,
          color: const Color(0xFFF1F5F9),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey[300],
          width: 220,
          height: 140,
          child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
        );
      },
    );
  }

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _currentUserEmail = null;
    _currentUserRole = null;
    // Connect WebSocket Realtime channel for Web Admin Portal
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final appState = Provider.of<AppState>(context, listen: false);
        appState.initRealtimeSubscriptions();
        // Fetch all pharmacy orders fresh from Supabase so orders persist on
        // browser refresh / page reload without depending solely on in-memory state.
        await appState.fetchPharmacyOrders();
        await appState.fetchMessagesSilently();

        _chatReplyController.addListener(() {
          final text = _chatReplyController.text.trim();
          final String doctorId = appState.doctors.isNotEmpty
              ? appState.doctors.first.id
              : '1';
          if (text.isNotEmpty) {
            appState.setDoctorTyping(doctorId, true);
            _typingTimer?.cancel();
            _typingTimer = Timer(const Duration(seconds: 2), () {
              appState.setDoctorTyping(doctorId, false);
            });
          }
        });
      }
    });
  }

  // Login Role Credentials
  String? _currentUserEmail;
  String? _currentUserRole; // 'Admin', 'Doctor', 'Pharmacy'
  String? _loggedInDoctorId; // DB id of logged-in doctor (for toggle)
  String _selectedPortalTab = 'Doctor';

  int _selectedAdminTab =
      0; // 0: Overview, 1: Doctors, 2: Patients (Prescriptions), 3: Appointments, 4: Pharmacy Catalog, 5: Messages/Chat

  // Selected Patient for Details Sidebar in Patients tab
  AppointmentModel? _selectedPatientForDetail;
  final TextEditingController _prescriptionController = TextEditingController();

  // Selected Patient for Chat Tab
  AppointmentModel? _selectedChatPatient;
  String? _selectedChatPatientName;
  String? _selectedChatPatientId;
  Timer? _typingTimer;
  final Map<String, String> _lastSeenMessageIds = {};
  final TextEditingController _chatReplyController = TextEditingController();

  // Web Admin Login text controllers
  final TextEditingController _loginEmailController = TextEditingController();
  final TextEditingController _loginPasswordController =
      TextEditingController();
  final TextEditingController _driverPhoneLoginController =
      TextEditingController();

  // Announcement controllers for broadcast
  final TextEditingController _announcementTitleController =
      TextEditingController();
  final TextEditingController _announcementBodyController =
      TextEditingController();
  bool _sendBroadcastToEmail = true;
  bool _isSendingBroadcast = false;
  final TextEditingController _diagnosisController = TextEditingController();
  final TextEditingController _weightController = TextEditingController(
    text: '70 kg',
  );

  // Patient Search Query for Web Admin Dashboard
  String _patientSearchQuery = '';

  @override
  void dispose() {
    _pollTimer?.cancel();
    _prescriptionController.dispose();
    _chatReplyController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _driverPhoneLoginController.dispose();
    super.dispose();
  }

  void _loginAs(String email, String role) {
    final appState = Provider.of<AppState>(context, listen: false);
    setState(() {
      _currentUserEmail = email;
      _currentUserRole = role;
      // Default tab based on role permissions
      if (role == 'Pharmacy') {
        _selectedAdminTab = 10; // Pharmacy Orders & Deliveries
      } else {
        _selectedAdminTab = 0; // Overview Dashboard
      }
      // Find the doctor's DB id by matching email keywords to their name
      if (role == 'Doctor') {
        final emailLower = email.toLowerCase();
        final matchedDoc =
            appState.doctors.firstWhereOrNull((d) {
              final nameLower = d.name.toLowerCase();
              return emailLower.contains('muktar') ||
                  emailLower.contains('mukhtar') ||
                  nameLower.contains('muktar') ||
                  nameLower.contains('mukhtar');
            }) ??
            (appState.doctors.isNotEmpty ? appState.doctors.first : null);
        _loggedInDoctorId = matchedDoc?.id ?? '1';
      } else if (role == 'Admin') {
        // Admin always controls first doctor for toggle demo
        _loggedInDoctorId = appState.doctors.isNotEmpty
            ? appState.doctors.first.id
            : null;
      }
    });
    // Tell AppState we are in admin/staff portal so toggle is preserved
    appState.setAdminMode(true);
  }

  void _logout() {
    setState(() {
      _currentUserEmail = null;
      _currentUserRole = null;
      _loggedInDoctorId = null;
      _selectedPatientForDetail = null;
      _selectedChatPatient = null;
      _selectedPortalTab = 'Doctor';
    });
    // Reset admin mode on logout
    final appState = Provider.of<AppState>(context, listen: false);
    appState.setAdminMode(false);
  }

  @override
  Widget build(BuildContext context) {
    // If not authenticated, show role selection screen
    if (_currentUserEmail == null) {
      return _buildLoginView();
    }

    final isDesktop = MediaQuery.of(context).size.width > 950;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: !isDesktop ? Drawer(child: SafeArea(child: _buildWebSidebar())) : null,
      appBar: _buildWebHeader(),
      body: Row(
        children: [
          // Sidebar Nav for Web (Desktop layout)
          if (isDesktop) _buildWebSidebar(),

          // Main Content Area
          Expanded(
            child: Column(
              children: [
                if (!isDesktop) ...[
                  // Mobile tab selector
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: _getAvailableNavItems().map((tab) {
                          final isSel = _selectedAdminTab == tab['index'];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              label: Text(tab['title']),
                              selected: isSel,
                              selectedColor: AppTheme.primaryColor,
                              labelStyle: TextStyle(
                                color: isSel
                                    ? Colors.white
                                    : AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (_) => setState(
                                () => _selectedAdminTab = tab['index'],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildSelectedTabContent(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- LOGIN ROLE SWITCHER ---
  Widget _buildLoginView() {
    if (_selectedPortalTab == 'Admin') {
      _selectedPortalTab = 'Doctor';
    }

    String title = 'Nasiib $_selectedPortalTab Portal';
    String subtitle = 'Soo gal si aad ula xiriirto bukaanadaada iyo balamaha';
    IconData icon = Icons.local_hospital_rounded;
    Color iconColor = AppTheme.primaryColor;
    Color iconBg = AppTheme.primaryLight;

    if (_selectedPortalTab == 'Pharmacy') {
      subtitle = 'Soo gal si aad u maamusho alaabta dawooyinka';
      icon = Icons.local_pharmacy_rounded;
    } else if (_selectedPortalTab == 'Driver') {
      title = 'Nasiib Driver Portal';
      subtitle = 'Geli nambarkaaga taleefanka si aad u gasho portal-ka darawalka';
      icon = Icons.two_wheeler_rounded;
      iconColor = const Color(0xFF15803D);
      iconBg = const Color(0xFFDCFCE7);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF475569), // Modern slate grey
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 420,
            margin: const EdgeInsets.symmetric(vertical: 24),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: iconBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),

                if (_selectedPortalTab == 'Driver') ...[
                  // Driver Phone Field
                  TextField(
                    controller: _driverPhoneLoginController,
                    keyboardType: TextInputType.phone,
                    style: GoogleFonts.plusJakartaSans(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Lambarka Taleefanka',
                      hintText: 'e.g. 612949911 ama +252612949911',
                      prefixIcon: const Icon(Icons.phone_rounded, size: 20, color: Color(0xFF15803D)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final rawPhone = _driverPhoneLoginController.text.trim();
                        if (rawPhone.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Fadlan geli nambarkaaga taleefanka!'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        String digits = rawPhone.replaceAll(RegExp(r'\D'), '');
                        if (digits.startsWith('252') && digits.length >= 12) {
                          digits = digits.substring(3);
                        }
                        if (digits.startsWith('0') && digits.length >= 10) {
                          digits = digits.substring(1);
                        }
                        final vBase = digits;
                        final vZero = '0$digits';
                        final v252 = '252$digits';
                        final vPlus252 = '+252$digits';
                        final possibleFormats = [vBase, vZero, v252, vPlus252];

                        try {
                          final client = SupabaseService.instance.client;
                          if (client != null && SupabaseService.instance.isInitialized) {
                            final res = await client.from('drivers').select().eq('status', 'active');
                            if (res is List && res.isNotEmpty) {
                              final matched = res.firstWhereOrNull((d) {
                                final ph = (d['phone'] ?? '').toString();
                                return possibleFormats.any((fmt) => ph.contains(fmt));
                              });

                              if (matched != null) {
                                final dName = (matched['name'] ?? matched['full_name'] ?? 'Darawal').toString();
                                final dPhone = (matched['phone'] ?? matched['phone_number'] ?? rawPhone).toString();
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setString('logged_driver_phone', dPhone);
                                await prefs.setString('logged_driver_name', dName);

                                if (context.mounted) {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DriverPortalScreen(
                                        initialDriver: Map<String, dynamic>.from(matched),
                                      ),
                                    ),
                                  );
                                }
                                return;
                              }
                            }

                            final userRes = await client.from('users').select().eq('role', 'driver');
                            if (userRes is List && userRes.isNotEmpty) {
                              final matchedUser = userRes.firstWhereOrNull((u) {
                                final ph = (u['phone'] ?? u['phone_number'] ?? '').toString();
                                return possibleFormats.any((fmt) => ph.contains(fmt));
                              });
                              if (matchedUser != null) {
                                final dName = (matchedUser['full_name'] ?? matchedUser['name'] ?? 'Darawal').toString();
                                final dPhone = (matchedUser['phone'] ?? matchedUser['phone_number'] ?? vPlus252).toString();
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setString('logged_driver_phone', dPhone);
                                await prefs.setString('logged_driver_name', dName);

                                final driverData = {
                                  'id': matchedUser['id'],
                                  'name': dName,
                                  'phone': dPhone,
                                  'status': 'active',
                                };

                                if (context.mounted) {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DriverPortalScreen(
                                        initialDriver: driverData,
                                      ),
                                    ),
                                  );
                                }
                                return;
                              }
                            }
                          }
                        } catch (e) {
                          debugPrint('Driver login error: $e');
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Nambarkan "$rawPhone" kuma diiwaangashana darawallada active-ka ah.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.login_rounded, color: Colors.white, size: 20),
                      label: Text(
                        'Gal Qaybta Darawalka',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF15803D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // Email Field
                  TextField(
                    controller: _loginEmailController,
                    style: GoogleFonts.plusJakartaSans(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      hintText: 'Enter your email',
                      prefixIcon: const Icon(Icons.email_outlined, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password Field
                  TextField(
                    controller: _loginPasswordController,
                    obscureText: true,
                    style: GoogleFonts.plusJakartaSans(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter password',
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        size: 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        final email = _loginEmailController.text
                            .trim()
                            .toLowerCase();
                        final password = _loginPasswordController.text;

                        if (email.isEmpty || password.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter email and password!'),
                            ),
                          );
                          return;
                        }

                        // Attempt Strict Supabase Authentication (NEW Supabase Project)
                        final client = SupabaseService.instance.client;
                        if (client != null &&
                            SupabaseService.instance.isInitialized) {
                          try {
                            final res = await client.auth
                                .signInWithPassword(
                                  email: email.trim(),
                                  password: password.trim(),
                                )
                                .timeout(const Duration(seconds: 8));

                            if (res.user != null) {
                              final user = res.user!;
                              final appMeta = user.appMetadata;
                              final userMeta = user.userMetadata;

                              // 1. Active / Inactive check
                              final bool isActive =
                                  (appMeta['is_active'] ??
                                      userMeta?['is_active'] ??
                                      true) ==
                                  true;
                              if (!isActive) {
                                await client.auth.signOut();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Account-kani waa uu xiran yahay (Inactive Account)',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                                return;
                              }

                              // 2. Role Resolution via Supabase Auth Metadata & User Email
                              String rawRole =
                                  (appMeta['role'] ?? userMeta?['role'] ?? '')
                                      .toString()
                                      .toLowerCase()
                                      .trim();
                              final emailLower = email.toLowerCase().trim();

                              String role = 'Admin';
                              if (rawRole == 'admin' ||
                                  emailLower == 'admin@nasiibhospital.com') {
                                role = 'Admin';
                              } else if (rawRole == 'pharmacy' ||
                                  emailLower == 'pharmacy@nasiib.com') {
                                role = 'Pharmacy';
                              } else if (rawRole == 'doctor' ||
                                  emailLower.contains('doctor') ||
                                  emailLower.contains('doc')) {
                                role = 'Doctor';
                              } else {
                                if (emailLower.contains('admin')) {
                                  role = 'Admin';
                                } else if (emailLower.contains('pharmacy')) {
                                  role = 'Pharmacy';
                                } else {
                                  role = _selectedPortalTab;
                                }
                              }

                              _loginAs(email.trim(), role);
                              return;
                            }
                          } catch (e) {
                            debugPrint("[LOGIN_ERROR] Supabase Auth error: $e");
                          }
                        }

                        // If Supabase Auth fails or returns error -> DENY ACCESS IMMEDIATELY
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Email ama Password-ka waa khalad!'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Sign In',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                _buildRoleSwitchLinks(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSwitchLinks() {
    final List<Widget> links = [];

    if (_selectedPortalTab != 'Doctor') {
      links.add(
        TextButton.icon(
          onPressed: () {
            setState(() {
              _selectedPortalTab = 'Doctor';
              _loginEmailController.clear();
              _loginPasswordController.clear();
            });
          },
          icon: const Icon(Icons.medical_services_outlined, size: 16, color: Color(0xFF0284C7)),
          label: Text(
            'Waxaan ahay Dhaqtar (Doctor Portal)',
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF0284C7),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    if (_selectedPortalTab != 'Pharmacy') {
      links.add(
        TextButton.icon(
          onPressed: () {
            setState(() {
              _selectedPortalTab = 'Pharmacy';
              _loginEmailController.clear();
              _loginPasswordController.clear();
            });
          },
          icon: const Icon(Icons.local_pharmacy_outlined, size: 16, color: Color(0xFF0284C7)),
          label: Text(
            'Waxaan ahay Farmashiye (Pharmacy Portal)',
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF0284C7),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    if (_selectedPortalTab != 'Driver') {
      links.add(
        TextButton.icon(
          onPressed: () {
            setState(() {
              _selectedPortalTab = 'Driver';
              _driverPhoneLoginController.clear();
            });
          },
          icon: const Icon(Icons.two_wheeler_rounded, size: 18, color: Color(0xFF15803D)),
          label: Text(
            'Waxaan ahay Darawal (Driver Portal)',
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF15803D),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Column(
      children: links,
    );
  }

  List<Map<String, dynamic>> _getAvailableNavItems() {
    final list = <Map<String, dynamic>>[];
    final role = _currentUserRole ?? 'Admin';
    if (role == 'Admin' || role == 'Doctor') {
      list.add({
        'index': 0,
        'title': 'Dashboard Overview',
        'icon': Icons.dashboard_rounded,
      });
      list.add({
        'index': 1,
        'title': 'Doctor Management',
        'icon': Icons.people_alt_rounded,
      });
      list.add({
        'index': 3,
        'title': 'Patient Appointments',
        'icon': Icons.calendar_month_rounded,
      });
    }
    if (role == 'Admin' || role == 'Pharmacy') {
      list.add({
        'index': 4,
        'title': 'Pharmacy Catalog',
        'icon': Icons.local_pharmacy_rounded,
      });
      list.add({
        'index': 10,
        'title': 'Pharmacy Orders & Deliveries',
        'icon': Icons.shopping_bag_rounded,
      });
      list.add({
        'index': 11,
        'title': 'Driver Management',
        'icon': Icons.delivery_dining_outlined,
      });
    }
    if (role == 'Admin' || role == 'Doctor') {
      list.add({
        'index': 8,
        'title': 'Broadcast Announcement',
        'icon': Icons.campaign_rounded,
      });
      list.add({
        'index': 9,
        'title': 'Nurse Management (Kalkaalisada)',
        'icon': Icons.medical_services_rounded,
      });
      list.add({
        'index': 12,
        'title': 'Home Care',
        'icon': Icons.home_work_rounded,
      });
      list.add({
        'index': 5,
        'title': 'Messages & Chat',
        'icon': Icons.chat_bubble_outline_rounded,
      });
    }
    return list;
  }

  // --- HEADER AND NAVIGATION ---
  PreferredSizeWidget _buildWebHeader() {
    final isDesktop = MediaQuery.of(context).size.width > 950;
    return AppBar(
      backgroundColor: const Color(0xFFF0FDF4),
      elevation: 0,
      leadingWidth: !isDesktop ? 56 : 0,
      leading: !isDesktop
          ? IconButton(
              icon: const Icon(Icons.menu_rounded, color: Color(0xFF065F46)),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            )
          : const SizedBox.shrink(),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: Container(
          color: const Color(0xFFDCFCE7),
          height: 1.0,
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF15803D).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.local_hospital_rounded,
              color: Color(0xFF15803D),
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Nasiib Hospital — Staff Portal',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF065F46),
            ),
          ),
          const SizedBox(width: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _currentUserRole == 'Admin'
                  ? 'CHIEF ADMIN'
                  : _currentUserRole == 'Doctor'
                  ? 'MEDICAL DOCTOR'
                  : 'PHARMACIST',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF15803D),
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (_currentUserRole == 'Admin' || _currentUserRole == 'Doctor') ...[
          Center(
            child: Builder(
              builder: (context) {
                final appState = context.watch<AppState>();
                final String? resolvedId =
                    _loggedInDoctorId ??
                    (_currentUserRole == 'Doctor' && _currentUserEmail != null
                        ? appState.doctors.firstWhereOrNull((d) {
                            final emailUser = _currentUserEmail!
                                .split('@')[0]
                                .toLowerCase();
                            final n = d.name
                                .toLowerCase()
                                .replaceAll('dr. ', '')
                                .replaceAll(' ', '');
                            return emailUser.contains(
                                  n.length > 5 ? n.substring(0, 5) : n,
                                ) ||
                                n.contains(
                                  emailUser
                                      .replaceAll('dr', '')
                                      .replaceAll('.', ''),
                                );
                          })?.id
                        : null);
                final DoctorModel? doc = resolvedId != null
                    ? appState.doctors.firstWhereOrNull(
                        (d) => d.id == resolvedId,
                      )
                    : (appState.doctors.isNotEmpty
                          ? appState.doctors.first
                          : null);
                final String doctorId = doc?.id ?? '';
                final isOnline = doc != null ? doc.isOnline : false;

                return const SizedBox.shrink();
              },
            ),
          ),
        ],
        const SizedBox(width: 14),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _currentUserRole == 'Admin'
                    ? 'Hospital Admin'
                    : (_currentUserRole == 'Doctor'
                          ? 'Doctor'
                          : 'Staff Member'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.bold,
                ),
              ),

              Text(
                _currentUserEmail ?? '',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
      ],
    );
  }

  Widget _buildBroadcastWidget(AppState appState) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: AppTheme.primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Broadcast Hospital Announcement',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    'Send updates, discounts, or Eid & Ramadan greetings to all patient app users.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 1. Announcement Title on top (Full Width)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Announcement Title (Cinwaanka Fariinta)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _announcementTitleController,
                style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'e.g., Happy Eid Al-Fitr! 🌙 / Warbixin Muhiim ah',
                  fillColor: const Color(0xFFF8FAFC),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 2. Announcement Message enlarged below Title (Multiline Large Text Area)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Announcement Message (Qoraalka Fariinta)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _announcementBodyController,
                minLines: 4,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                style: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.5),
                decoration: InputDecoration(
                  hintText: 'Qor halkan faahfaahinta fariinta aad rabto inaad u dirto dhammaan bukaannada...',
                  fillColor: const Color(0xFFF8FAFC),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 3. Email Checkbox and Send Broadcast Button Row
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _sendBroadcastToEmail = !_sendBroadcastToEmail;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _sendBroadcastToEmail,
                        activeColor: AppTheme.primaryColor,
                        onChanged: (val) {
                          setState(() {
                            _sendBroadcastToEmail = val ?? true;
                          });
                        },
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.email_outlined, size: 18, color: AppTheme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Sidoo kale fariintan Email ahaan ugu dir dhammaan bukaannada is-diiwaangeliyay (Send to All Patient Emails)',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                width: 220,
                child: ElevatedButton(
                  onPressed: _isSendingBroadcast ? null : () async {
                    final title = _announcementTitleController.text.trim();
                    final body = _announcementBodyController.text.trim();
                    if (title.isEmpty || body.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please enter both title and message!',
                          ),
                        ),
                      );
                      return;
                    }

                    setState(() => _isSendingBroadcast = true);

                    final String notifId = DateTime.now()
                        .millisecondsSinceEpoch
                        .toString();
                    final String nowIso = DateTime.now()
                        .toUtc()
                        .toIso8601String();

                    int emailSentCount = 0;

                    try {
                      final client = Supabase.instance.client;
                      // 1. Insert in notifications for App Push
                      await client.from('notifications').insert({
                        'id': notifId,
                        'title': title,
                        'body': body,
                        'created_at': nowIso,
                        'sender': 'admin',
                        'sender_label': 'Nasiib Hospital',
                        'target_user_id': 'all',
                      });

                      await appState.loadNotificationsFromSupabase();

                      // 2. Dispatch Email Broadcast if enabled
                      if (_sendBroadcastToEmail) {
                        try {
                          final Set<String> collectedEmails = {};

                          try {
                            final patientsData = await client.from('patients').select();
                            if (patientsData is List) {
                              for (final p in patientsData) {
                                final em = (p['email'] ?? p['patient_email'] ?? p['contact_email'] as String?)?.toString().trim().toLowerCase();
                                if (em != null && em.isNotEmpty && em.contains('@') && em.contains('.')) {
                                  collectedEmails.add(em);
                                }
                              }
                            }
                          } catch (pErr) {
                            debugPrint("[ADMIN_BROADCAST] Patients table email read: $pErr");
                          }

                          try {
                            final ordersData = await client.from('orders').select('customer_email, email').limit(200);
                            if (ordersData is List) {
                              for (final o in ordersData) {
                                final em1 = (o['customer_email'] as String?)?.trim().toLowerCase();
                                final em2 = (o['email'] as String?)?.trim().toLowerCase();
                                if (em1 != null && em1.isNotEmpty && em1.contains('@') && em1.contains('.')) collectedEmails.add(em1);
                                if (em2 != null && em2.isNotEmpty && em2.contains('@') && em2.contains('.')) collectedEmails.add(em2);
                              }
                            }
                          } catch (_) {}

                          try {
                            final apptsData = await client.from('appointments').select().limit(200);
                            if (apptsData is List) {
                              for (final a in apptsData) {
                                final em = (a['email'] ?? a['patient_email'] as String?)?.toString().trim().toLowerCase();
                                if (em != null && em.isNotEmpty && em.contains('@') && em.contains('.')) collectedEmails.add(em);
                              }
                            }
                          } catch (_) {}

                          // If no emails found yet, add admin/system email as default test recipient
                          if (collectedEmails.isEmpty) {
                            collectedEmails.add('admin@nasiibhospital.com');
                          }

                          debugPrint("[ADMIN_BROADCAST] Collected ${collectedEmails.length} recipient emails: $collectedEmails");

                          // 1. Send via Email Service
                          emailSentCount = await EmailOtpService.instance.sendBroadcastEmail(
                            subject: title,
                            announcementBody: body,
                            recipientEmails: collectedEmails.toList(),
                          );

                          // 2. Insert into Supabase broadcast_emails table
                          for (final targetEmail in collectedEmails) {
                            try {
                              final row = {
                                'id': 'em_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}',
                                'recipient_email': targetEmail,
                                'subject': title,
                                'message': body,
                                'sender': 'Nasiib Hospital Admin',
                                'status': 'sent',
                                'created_at': nowIso,
                              };
                              await client.from('broadcast_emails').insert(row);
                              debugPrint("[ADMIN_BROADCAST] Successfully inserted row into broadcast_emails for $targetEmail");
                            } catch (insertErr) {
                              debugPrint("[ADMIN_BROADCAST] Error inserting into broadcast_emails: $insertErr");
                            }
                          }
                        } catch (mailErr) {
                          debugPrint("[ADMIN_BROADCAST] Email dispatch error: $mailErr");
                        }
                      }

                      _announcementTitleController.clear();
                      _announcementBodyController.clear();

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.green,
                            content: Text(
                              _sendBroadcastToEmail && emailSentCount > 0
                                  ? 'Fariinta App-ka iyo Email-ada ($emailSentCount bukaan) si guul leh ayaa loo diray!'
                                  : 'Fariinta App-ka si guul leh ayaa loo diray!',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint("[ADMIN_BROADCAST] Direct insert error: $e");
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.red,
                            content: Text('Cilad ayaa dhacday: $e'),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _isSendingBroadcast = false);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSendingBroadcast
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text(
                              'Send Broadcast',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFullBroadcastView(AppState appState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Broadcast Hospital Announcement',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Send updates, discounts, or Eid & Ramadan greetings to all patient app users.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          _buildBroadcastWidget(appState),
        ],
      ),
    );
  }

  Widget _buildWebSidebar() {
    final appState = context.watch<AppState>();
    final hasMessagesPermission =
        _currentUserRole == 'Admin' || _currentUserRole == 'Doctor';

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        border: Border(right: BorderSide(color: Colors.green.shade100, width: 1)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: _getAvailableNavItems()
                  .where(
                    (item) => item['index'] != 5,
                  ) // Exclude Messages from main list
                  .map((item) {
                    final isSelected = _selectedAdminTab == item['index'];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10.0,
                        vertical: 1.0,
                      ),
                      child: ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        leading: Icon(
                          item['icon'],
                          size: 20,
                          color: isSelected
                              ? const Color(0xFF15803D)
                              : const Color(0xFF334155),
                        ),
                        title: Text(
                          item['title'],
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected
                                ? const Color(0xFF15803D)
                                : const Color(0xFF1E293B),
                          ),
                        ),
                        selected: isSelected,
                        selectedTileColor: const Color(0xFFDCFCE7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        trailing: item['index'] == 12
                            ? StreamBuilder<List<Map<String, dynamic>>>(
                                stream: (SupabaseService.instance.client != null && SupabaseService.instance.isInitialized)
                                    ? SupabaseService.instance.client!.from('nurse_orders').stream(primaryKey: ['id'])
                                    : const Stream.empty(),
                                builder: (context, snapshot) {
                                  final pending = (snapshot.data ?? []).where((o) {
                                    final st = (o['status'] ?? o['order_status'] ?? 'pending').toString().toLowerCase();
                                    return st == 'pending';
                                  }).length;
                                  if (pending == 0) return const SizedBox.shrink();
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$pending',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                },
                              )
                            : null,
                        onTap: () {
                          setState(() => _selectedAdminTab = item['index']);
                          if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    );
                  })
                  .toList(),
            ),
          ),

          if (hasMessagesPermission) ...[
            // Inbox/Messages tab explicitly positioned above Logout
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseService.instance.client != null
                  ? SupabaseService.instance.client!
                      .from('messages')
                      .stream(primaryKey: ['id'])
                      .order('created_at', ascending: false)
                  : const Stream.empty(),
              builder: (context, snapshot) {
                final streamedList = snapshot.data ?? [];
                final unreadPatientIds = <String>{};
                for (var m in streamedList) {
                  final isRead = m['is_read'] ?? false;
                  final sRole = m['sender_role']?.toString() ?? '';
                  final sId = m['sender_id']?.toString() ?? '';
                  final pId = m['patient_id']?.toString() ?? sId;
                  if (!isRead && (sRole == 'patient' || (sId != 'admin' && sId != 'doctor' && sId != 'support'))) {
                    if (pId.isNotEmpty) unreadPatientIds.add(pId);
                  }
                }
                for (var m in appState.chatMessages) {
                  final isRead = m['is_read'] ?? false;
                  final sRole = m['sender_role']?.toString() ?? '';
                  final sId = m['sender_id']?.toString() ?? '';
                  final pId = m['patient_id']?.toString() ?? sId;
                  if (!isRead && (sRole == 'patient' || (sId != 'admin' && sId != 'doctor' && sId != 'support'))) {
                    if (pId.isNotEmpty) unreadPatientIds.add(pId);
                  }
                }
                final totalUnreadChatsCount = unreadPatientIds.length;

                final isSelected = _selectedAdminTab == 5;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10.0,
                    vertical: 1.0,
                  ),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    leading: Icon(
                      isSelected
                          ? Icons.chat_bubble_rounded
                          : Icons.chat_bubble_outline_rounded,
                      size: 20,
                      color: isSelected
                          ? const Color(0xFF15803D)
                          : const Color(0xFF334155),
                    ),
                    title: Row(
                      children: [
                        Text(
                          'Messages',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected
                                ? const Color(0xFF15803D)
                                : const Color(0xFF1E293B),
                          ),
                        ),
                        if (totalUnreadChatsCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF15803D)
                                  : const Color(0xFF16A34A),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$totalUnreadChatsCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    selected: isSelected,
                    selectedTileColor: const Color(0xFFDCFCE7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onTap: () {
                      setState(() => _selectedAdminTab = 5);
                      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                );
              },
            ),
          ],

          // Logout button explicitly positioned at the bottom of the sidebar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 10.0,
              vertical: 1.0,
            ),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              leading: const Icon(
                Icons.logout_rounded,
                size: 20,
                color: Color(0xFFEF4444),
              ),
              title: Text(
                'Logout',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFEF4444),
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              onTap: _logout,
            ),
          ),

          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connected to Supabase DB',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppTheme.textLight,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Host: ugoklaeslodvadykcmbg.supabase.co',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: AppTheme.textLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedTabContent(BuildContext context) {
    switch (_selectedAdminTab) {
      case 0:
        return _buildOverviewTab(context);
      case 1:
        return _buildDoctorsTab(context);
      case 2:
        return _buildPatientsTab(context);
      case 3:
        return _buildAppointmentsTab(context);
      case 4:
        return _buildPharmacyTab(context);
      case 5:
        return _buildChatTab(context);
      case 6:
        return _buildRecycleBinTab(context);
      case 7:
        return _buildDoctorVerificationTab(context);
      case 8:
        return _buildFullBroadcastView(context.read<AppState>());
      case 9:
        return _buildNursesTab(context);
      case 10:
        return _buildPharmacyOrderPanel(context);
      case 11:
        return _buildDriverManagementView(context);
      case 12:
        return _buildHomeCareTab(context);
      default:
        return const Center(child: Text('Page not found.'));
    }
  }

  // ==========================================
  // TAB 0: CAREPLUS HOSPITAL DASHBOARD DESIGN
  // ==========================================
  Widget _buildOverviewTab(BuildContext context) {
    final appState = context.watch<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. TOP HEADER (Welcome bar + Search + Live Dynamic Date + Notifications)
        _buildCarePlusDashboardHeader(appState),
        const SizedBox(height: 24),

        // 2. TOP SUMMARY STATISTICS CARDS (4 Dynamic Cards in Row, Pending Appointments Removed)
        _buildCarePlusKpiCardsRow(appState),
        // 3. MIDDLE SECTION (Overview Statistics Chart + Recent Activities)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overview Statistics Line Chart (Dynamic Patient Registrations from Supabase)
            Expanded(
              flex: 3,
              child: _buildAppointmentsOverviewChartCard(appState),
            ),
            const SizedBox(width: 20),

            // Recent Activities Timeline (Dynamic Recent Users from Supabase)
            Expanded(flex: 2, child: _buildRecentActivitiesCard(appState)),
          ],
        ),
        const SizedBox(height: 24),

        // 4. BOTTOM SECTION (Patients Overview Table + Doctors List - Dynamic from Supabase)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Patients Overview Table (Dynamic from Supabase)
            Expanded(flex: 3, child: _buildPatientsOverviewTableCard(appState)),
            const SizedBox(width: 20),

            // Doctors Section List (Dynamic from Supabase)
            Expanded(flex: 2, child: _buildDoctorsStatusListCard(appState)),
          ],
        ),
      ],
    );
  }

  // --- HEADER SECTION (Dynamic Admin Welcome + Live Device Date/Time) ---
  Widget _buildCarePlusDashboardHeader(AppState appState) {
    final now = DateTime.now();
    final dateStr = DateFormat('dd MMMM yyyy').format(now);
    final timeStr = DateFormat('EEEE, hh:mm a').format(now);
    final unreadCount = appState.chatMessages
        .where((m) => m['is_read'] != true)
        .length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left Welcome Message
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _currentUserRole == 'Doctor'
                      ? 'Welcome back, Doctor'
                      : 'Welcome back, Admin',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 6),
                const Text('👋', style: TextStyle(fontSize: 20)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Here's what's happening in your hospital today.",
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),

        // Right Actions (Search Bar + Notification Bell + Live Device Date)
        Row(
          children: [
            // Search Input Box
            Container(
              width: 240,
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF94A3B8),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Search anything...',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Notification Bell with Badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    color: Color(0xFF475569),
                    size: 20,
                  ),
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),

            // Dynamic Live Date Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    color: Color(0xFF64748B),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dateStr,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        timeStr,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- KPI CARDS ROW (Realtime Pharmacy, Doctors, Nurses & Total Hospital Revenue Metrics) ---
  Widget _buildCarePlusKpiCardsRow(AppState appState) {
    final client = SupabaseService.instance.client;
    final bool canStream = client != null && SupabaseService.instance.isInitialized;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: canStream
          ? client.from('orders').stream(primaryKey: ['id'])
          : const Stream.empty(),
      builder: (context, ordersSnap) {
        final List<Map<String, dynamic>> orders = (ordersSnap.hasData && ordersSnap.data != null && ordersSnap.data!.isNotEmpty)
            ? ordersSnap.data!
            : appState.orders;

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: canStream
              ? client.from('appointments').stream(primaryKey: ['id'])
              : const Stream.empty(),
          builder: (context, apptsSnap) {
            final List<Map<String, dynamic>> rawAppts = (apptsSnap.hasData && apptsSnap.data != null && apptsSnap.data!.isNotEmpty)
                ? apptsSnap.data!
                : appState.appointments.map((a) => <String, dynamic>{
                    'id': a.id,
                    'doctor_name': a.doctorName,
                    'doctor_specialty': a.doctorSpecialty,
                    'patient_name': a.patientName,
                    'patient_phone': a.patientPhone,
                    'amount': a.amount,
                    'consultation_fee': a.amount,
                    'status': a.status,
                    'created_at': a.createdAt,
                    'queue_number': a.queueNumber,
                    'payment_method': a.paymentMethod,
                  }).toList();

            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: canStream
                  ? client.from('nurse_orders').stream(primaryKey: ['id'])
                  : const Stream.empty(),
              builder: (context, nurseSnap) {
                final List<Map<String, dynamic>> nurseList = (nurseSnap.hasData && nurseSnap.data != null && nurseSnap.data!.isNotEmpty)
                    ? nurseSnap.data!
                    : [];

                final now = DateTime.now();
                final todayStr = DateFormat('yyyy-MM-dd').format(now);

                bool isToday(dynamic rawDate) {
                  if (rawDate == null) return false;
                  final str = rawDate.toString();
                  if (str.contains(todayStr)) return true;
                  try {
                    final dt = DateTime.parse(str).toLocal();
                    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
                  } catch (_) {
                    return false;
                  }
                }

                // 1. Pharmacy calculations
                int todaysOrdersCount = 0;
                double todaysPharmacyRev = 0.0;
                for (final o in orders) {
                  final status = (o['status'] ?? '').toString().toLowerCase();
                  if (isToday(o['created_at'] ?? o['date'])) {
                    todaysOrdersCount++;
                    if (!status.contains('cancel')) {
                      final rawAmt = o['total_amount'] ?? o['total'] ?? o['amount'] ?? o['price'];
                      final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                      todaysPharmacyRev += amt;
                    }
                  }
                }

                // 2. Doctor Bookings calculations
                int todaysDoctorCount = 0;
                double todaysDoctorRev = 0.0;
                for (final a in rawAppts) {
                  final status = (a['status'] ?? '').toString().toLowerCase();
                  if (isToday(a['created_at'] ?? a['date'])) {
                    todaysDoctorCount++;
                    if (!status.contains('cancel') && !status.contains('reject')) {
                      final rawAmt = a['amount'] ?? a['consultation_fee'] ?? a['price'] ?? a['fee'];
                      final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                      todaysDoctorRev += amt;
                    }
                  }
                }

                // 3. Nurse Home Care calculations
                int todaysNurseCount = 0;
                double todaysNurseRev = 0.0;
                for (final n in nurseList) {
                  final status = (n['status'] ?? n['order_status'] ?? '').toString().toLowerCase();
                  if (isToday(n['created_at'] ?? n['date'])) {
                    todaysNurseCount++;
                    if (!status.contains('cancel') && !status.contains('reject')) {
                      final rawAmt = n['amount'] ?? n['total_amount'] ?? n['price'] ?? n['fee'];
                      final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                      todaysNurseRev += amt;
                    }
                  }
                }

                final double grandTotalToday = todaysPharmacyRev + todaysDoctorRev + todaysNurseRev;

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 700;
                    final isTablet = constraints.maxWidth >= 700 && constraints.maxWidth < 1200;

                    final cardPharmacy = _buildCarePlusStatCard(
                      title: 'Dakhliga Dawooyinka (Maanta)',
                      value: '\$${todaysPharmacyRev.toStringAsFixed(2)} USD',
                      change: '$todaysOrdersCount Dalab',
                      subtext: 'Pharmacy Revenue (Riix Chart)',
                      icon: Icons.medication_rounded,
                      iconColor: const Color(0xFF10B981),
                      bgColor: const Color(0xFFECFDF5),
                      showSparkline: true,
                      onTap: () => _showPharmacyRevenueAnalyticsDialog(context, appState, orders),
                    );

                    final cardDoctors = _buildCarePlusStatCard(
                      title: 'Dakhliga Dhaqaatiirta (Maanta)',
                      value: '\$${todaysDoctorRev.toStringAsFixed(2)} USD',
                      change: '$todaysDoctorCount Ballan',
                      subtext: 'Doctor Booking Revenue (Riix Chart)',
                      icon: Icons.medical_services_rounded,
                      iconColor: const Color(0xFF2563EB),
                      bgColor: const Color(0xFFEFF6FF),
                      showSparkline: true,
                      onTap: () => _showDoctorRevenueAnalyticsDialog(context, appState, rawAppts),
                    );

                    final cardNurses = _buildCarePlusStatCard(
                      title: 'Dakhliga Kalkaalisada (Maanta)',
                      value: '\$${todaysNurseRev.toStringAsFixed(2)} USD',
                      change: '$todaysNurseCount Dalab',
                      subtext: 'Nurse Home Care (Riix Chart)',
                      icon: Icons.health_and_safety_rounded,
                      iconColor: const Color(0xFF059669),
                      bgColor: const Color(0xFFD1FAE5),
                      showSparkline: true,
                      onTap: () => _showNurseRevenueAnalyticsDialog(context, appState, nurseList),
                    );

                    final cardGrandTotal = _buildCarePlusStatCard(
                      title: 'Wadarta Dakhliga Isbitaalka (Maanta)',
                      value: '\$${grandTotalToday.toStringAsFixed(2)} USD',
                      change: '↗ All Live',
                      subtext: '3-da Adeeg ee Isbitaalka Nasiib',
                      icon: Icons.account_balance_wallet_rounded,
                      iconColor: const Color(0xFF7C3AED),
                      bgColor: const Color(0xFFF3E8FF),
                      showSparkline: true,
                      onTap: () => _showCombinedRevenueAnalyticsDialog(context, appState, orders, rawAppts, nurseList),
                    );

                    if (isMobile) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            SizedBox(width: 230, child: cardPharmacy),
                            const SizedBox(width: 10),
                            SizedBox(width: 230, child: cardDoctors),
                            const SizedBox(width: 10),
                            SizedBox(width: 230, child: cardNurses),
                            const SizedBox(width: 10),
                            SizedBox(width: 230, child: cardGrandTotal),
                          ],
                        ),
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: cardPharmacy),
                        const SizedBox(width: 10),
                        Expanded(child: cardDoctors),
                        const SizedBox(width: 10),
                        Expanded(child: cardNurses),
                        const SizedBox(width: 10),
                        Expanded(child: cardGrandTotal),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCarePlusStatCard({
    required String title,
    required String value,
    required String change,
    required String subtext,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    bool showSparkline = false,
    VoidCallback? onTap,
  }) {
    final cardContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              if (showSparkline)
                SizedBox(
                  width: 52,
                  height: 26,
                  child: CustomPaint(
                    painter: SparklineChartPainter(color: iconColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  change,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF16A34A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  subtext,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9.5,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 8,
                  color: Color(0xFF94A3B8),
                ),
            ],
          ),
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }

  // --- INTERACTIVE PHARMACY REVENUE & SALES ANALYTICS MODAL ---
  void _showPharmacyRevenueAnalyticsDialog(
    BuildContext context,
    AppState appState,
    List<Map<String, dynamic>> allOrders,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        String selectedFilter = 'This Week'; // 'Today', 'Yesterday', '2 Days Ago', 'This Week', 'This Month', 'This Year', 'All Time'
        return StatefulBuilder(
          builder: (context, setModalState) {
            final now = DateTime.now();

            DateTime parseDateSafe(dynamic raw) {
              if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0);
              final str = raw.toString().trim();
              if (str.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
              final dt = DateTime.tryParse(str);
              if (dt != null) return dt.toLocal();
              final intVal = int.tryParse(str);
              if (intVal != null) return DateTime.fromMillisecondsSinceEpoch(intVal).toLocal();
              return DateTime.fromMillisecondsSinceEpoch(0);
            }

            bool isSameDate(DateTime a, DateTime b) {
              return a.year == b.year && a.month == b.month && a.day == b.day;
            }

            final yesterday = now.subtract(const Duration(days: 1));
            final twoDaysAgo = now.subtract(const Duration(days: 2));

            // Filter matching orders
            final List<Map<String, dynamic>> filteredOrders = [];
            for (final o in allOrders) {
              final oDate = parseDateSafe(o['created_at'] ?? o['date']);
              bool matches = false;

              if (selectedFilter == 'Today') {
                matches = isSameDate(oDate, now);
              } else if (selectedFilter == 'Yesterday') {
                matches = isSameDate(oDate, yesterday);
              } else if (selectedFilter == '2 Days Ago') {
                matches = isSameDate(oDate, twoDaysAgo);
              } else if (selectedFilter == 'This Week') {
                matches = oDate.isAfter(now.subtract(const Duration(days: 7)));
              } else if (selectedFilter == 'This Month') {
                matches = oDate.isAfter(now.subtract(const Duration(days: 30)));
              } else if (selectedFilter == 'This Year') {
                matches = oDate.isAfter(now.subtract(const Duration(days: 365)));
              } else {
                matches = true; // All Time
              }

              if (matches) filteredOrders.add(o);
            }

            // Calculate total revenue, order count, avg value
            double totalRevenue = 0.0;
            int totalItemsCount = 0;
            for (final o in filteredOrders) {
              final status = (o['status'] ?? '').toString().toLowerCase();
              if (!status.contains('cancel')) {
                final rawAmt = o['total_amount'] ?? o['total'] ?? o['amount'] ?? o['price'];
                final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                totalRevenue += amt;
              }
              final items = o['items'];
              if (items is List) {
                totalItemsCount += items.length;
              } else {
                totalItemsCount += 1;
              }
            }

            final double avgOrderValue = filteredOrders.isNotEmpty ? (totalRevenue / filteredOrders.length) : 0.0;

            // Generate daily chart data for the last 7 days (or 30 days / 12 months)
            final List<Map<String, dynamic>> chartBars = [];
            if (selectedFilter == 'This Year') {
              // 12 months
              for (int m = 1; m <= 12; m++) {
                final monthName = DateFormat('MMM').format(DateTime(now.year, m, 1));
                double mRev = 0.0;
                for (final o in allOrders) {
                  final oDate = parseDateSafe(o['created_at'] ?? o['date']);
                  if (oDate.year == now.year && oDate.month == m) {
                    final rawAmt = o['total_amount'] ?? o['total'] ?? o['amount'] ?? o['price'];
                    final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                    mRev += amt;
                  }
                }
                chartBars.add({'label': monthName, 'amount': mRev});
              }
            } else if (selectedFilter == 'This Month') {
              // Last 4 weeks / 30 days in 6 buckets
              for (int i = 5; i >= 0; i--) {
                final startDay = now.subtract(Duration(days: (i + 1) * 5));
                final endDay = now.subtract(Duration(days: i * 5));
                final label = '${DateFormat('d').format(startDay)}-${DateFormat('d MMM').format(endDay)}';
                double bRev = 0.0;
                for (final o in allOrders) {
                  final oDate = parseDateSafe(o['created_at'] ?? o['date']);
                  if (oDate.isAfter(startDay) && oDate.isBefore(endDay.add(const Duration(days: 1)))) {
                    final rawAmt = o['total_amount'] ?? o['total'] ?? o['amount'] ?? o['price'];
                    final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                    bRev += amt;
                  }
                }
                chartBars.add({'label': label, 'amount': bRev});
              }
            } else {
              // Last 7 days including Daraad, Shalay, Maanta
              for (int i = 6; i >= 0; i--) {
                final targetDay = now.subtract(Duration(days: i));
                String dayName;
                if (i == 0) {
                  dayName = 'Maanta';
                } else if (i == 1) {
                  dayName = 'Shalay';
                } else if (i == 2) {
                  dayName = 'Daraad';
                } else {
                  dayName = DateFormat('EEE, d MMM').format(targetDay);
                }

                double dayRev = 0.0;
                for (final o in allOrders) {
                  final oDate = parseDateSafe(o['created_at'] ?? o['date']);
                  if (isSameDate(oDate, targetDay)) {
                    final rawAmt = o['total_amount'] ?? o['total'] ?? o['amount'] ?? o['price'];
                    final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                    dayRev += amt;
                  }
                }
                chartBars.add({'label': dayName, 'amount': dayRev, 'isSpecial': i <= 2});
              }
            }

            final maxChartAmt = chartBars.fold<double>(0.0, (max, b) => b['amount'] > max ? b['amount'] : max);
            final double safeMax = maxChartAmt > 0 ? maxChartAmt : 100.0;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                width: 950,
                constraints: const BoxConstraints(maxHeight: 820),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x20000000),
                      blurRadius: 30,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Modal Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(28, 20, 20, 18),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.analytics_rounded, color: Color(0xFF10B981), size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dakhliga & Iibka Dawooyinka (Pharmacy Revenue Analytics)',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  'Xisaabi dakhliga maanta, shalay, daraad, toddobaadkan, bishan, iyo sannadkan',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Time Filter Tabs
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildTimeFilterPill('Maanta (Today)', 'Today', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Shalay (Yesterday)', 'Yesterday', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Daraad (2 Days Ago)', '2 Days Ago', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Toddobaadkan (7 Days)', 'This Week', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Bishan (30 Days)', 'This Month', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Sannadkan (12 Months)', 'This Year', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Dhammaan (All Time)', 'All Time', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // 2. Summary KPI Cards (4 Cards)
                            Row(
                              children: [
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Wadarta Dakhliga ($selectedFilter)',
                                    value: '\$${totalRevenue.toStringAsFixed(2)} USD',
                                    icon: Icons.payments_rounded,
                                    iconColor: const Color(0xFF10B981),
                                    bgColor: const Color(0xFFECFDF5),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Tirada Dalabaadka',
                                    value: '${filteredOrders.length} Dalab',
                                    icon: Icons.shopping_cart_rounded,
                                    iconColor: const Color(0xFF2563EB),
                                    bgColor: const Color(0xFFEFF6FF),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Celceliska Dalabkiiba',
                                    value: '\$${avgOrderValue.toStringAsFixed(2)} USD',
                                    icon: Icons.trending_up_rounded,
                                    iconColor: const Color(0xFF8B5CF6),
                                    bgColor: const Color(0xFFF5F3FF),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Dawooyinka La Gaday',
                                    value: '$totalItemsCount Xabbo/Qasacad',
                                    icon: Icons.medication_rounded,
                                    iconColor: const Color(0xFFEA580C),
                                    bgColor: const Color(0xFFFFF7ED),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // 3. Visual Interactive Chart Container
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.bar_chart_rounded, color: Color(0xFF10B981), size: 20),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Muuqaalka Dakhliga Maalinlaha & Muddada (Daily Revenue Chart)',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF0F172A),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDCFCE7),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Max: \$${maxChartAmt.toStringAsFixed(2)} USD',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF15803D),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  // Bar Chart Visualization
                                  SizedBox(
                                    height: 180,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: chartBars.map((bar) {
                                        final double amt = bar['amount'] as double;
                                        final String label = bar['label'] as String;
                                        final bool isSpecial = (bar['isSpecial'] == true);
                                        final double heightFactor = (amt / safeMax).clamp(0.06, 1.0);

                                        return Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                // Dollar label on top of bar
                                                Text(
                                                  '\$${amt.toStringAsFixed(amt % 1 == 0 ? 0 : 2)}',
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: amt > 0
                                                        ? (isSpecial ? const Color(0xFF059669) : const Color(0xFF2563EB))
                                                        : const Color(0xFF94A3B8),
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                // Bar body
                                                Flexible(
                                                  child: FractionallySizedBox(
                                                    heightFactor: heightFactor,
                                                    child: Container(
                                                      width: double.infinity,
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          begin: Alignment.topCenter,
                                                          end: Alignment.bottomCenter,
                                                          colors: isSpecial
                                                              ? (amt > 0
                                                                  ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                                                  : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)])
                                                              : (amt > 0
                                                                  ? [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)]
                                                                  : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)]),
                                                        ),
                                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                                        boxShadow: [
                                                          if (amt > 0)
                                                            BoxShadow(
                                                              color: (isSpecial ? const Color(0xFF10B981) : const Color(0xFF3B82F6)).withOpacity(0.3),
                                                              blurRadius: 6,
                                                              offset: const Offset(0, 2),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                // X-Axis Label
                                                Text(
                                                  label,
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 11,
                                                    fontWeight: isSpecial ? FontWeight.bold : FontWeight.w500,
                                                    color: isSpecial ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // 4. Detailed Orders Table for this Period
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Dalabaadka La Qabtay Muddadan ($selectedFilter) — ${filteredOrders.length} Dalab',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            if (filteredOrders.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(32),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(Icons.inbox_outlined, size: 48, color: Color(0xFFCBD5E1)),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Wax dalab dawo ah lagama helin muddada ($selectedFilter).',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filteredOrders.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final o = filteredOrders[index];
                                  final orderId = (o['id'] ?? o['order_id'] ?? '').toString();
                                  final customerName = (o['patient_name'] ?? o['customer_name'] ?? o['user_name'] ?? o['full_name'] ?? 'Bukaan').toString();
                                  final phone = (o['patient_phone'] ?? o['phone'] ?? '').toString();
                                  final rawAmt = o['total_amount'] ?? o['total'] ?? o['amount'] ?? o['price'];
                                  final amount = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                                  final paymentMethod = (o['payment_method'] ?? 'EVC Plus').toString();
                                  final createdAtRaw = o['created_at']?.toString() ?? o['date']?.toString();
                                  String formattedTime = 'Recently';
                                  if (createdAtRaw != null && createdAtRaw.isNotEmpty) {
                                    try {
                                      final dt = DateTime.parse(createdAtRaw).toLocal();
                                      formattedTime = DateFormat('EEE, d MMM yyyy • hh:mm a').format(dt);
                                    } catch (_) {}
                                  }

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEFF6FF),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF2563EB), size: 18),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    customerName,
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                      color: const Color(0xFF0F172A),
                                                    ),
                                                  ),
                                                  if (phone.isNotEmpty) ...[
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      '($phone)',
                                                      style: GoogleFonts.plusJakartaSans(
                                                        fontSize: 12,
                                                        color: const Color(0xFF64748B),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Order #$orderId • $formattedTime',
                                                style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 11,
                                                  color: const Color(0xFF94A3B8),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '\$${amount.toStringAsFixed(2)} USD',
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: const Color(0xFF10B981),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              paymentMethod,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 11,
                                                color: const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- INTERACTIVE DOCTOR REVENUE & APPOINTMENTS ANALYTICS MODAL ---
  void _showDoctorRevenueAnalyticsDialog(
    BuildContext context,
    AppState appState,
    List<Map<String, dynamic>> allAppts,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        String selectedFilter = 'This Week';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final now = DateTime.now();

            DateTime parseDateSafe(dynamic raw) {
              if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0);
              final str = raw.toString().trim();
              if (str.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
              final dt = DateTime.tryParse(str);
              if (dt != null) return dt.toLocal();
              final intVal = int.tryParse(str);
              if (intVal != null) return DateTime.fromMillisecondsSinceEpoch(intVal).toLocal();
              return DateTime.fromMillisecondsSinceEpoch(0);
            }

            bool isSameDate(DateTime a, DateTime b) {
              return a.year == b.year && a.month == b.month && a.day == b.day;
            }

            final yesterday = now.subtract(const Duration(days: 1));
            final twoDaysAgo = now.subtract(const Duration(days: 2));

            final List<Map<String, dynamic>> filteredAppts = [];
            for (final a in allAppts) {
              final aDate = parseDateSafe(a['created_at'] ?? a['date']);
              bool matches = false;

              if (selectedFilter == 'Today') {
                matches = isSameDate(aDate, now);
              } else if (selectedFilter == 'Yesterday') {
                matches = isSameDate(aDate, yesterday);
              } else if (selectedFilter == '2 Days Ago') {
                matches = isSameDate(aDate, twoDaysAgo);
              } else if (selectedFilter == 'This Week') {
                matches = aDate.isAfter(now.subtract(const Duration(days: 7)));
              } else if (selectedFilter == 'This Month') {
                matches = aDate.isAfter(now.subtract(const Duration(days: 30)));
              } else if (selectedFilter == 'This Year') {
                matches = aDate.isAfter(now.subtract(const Duration(days: 365)));
              } else {
                matches = true;
              }

              if (matches) filteredAppts.add(a);
            }

            double totalRevenue = 0.0;
            final Set<String> distinctDoctors = {};
            for (final a in filteredAppts) {
              final status = (a['status'] ?? '').toString().toLowerCase();
              if (!status.contains('cancel') && !status.contains('reject')) {
                final rawAmt = a['amount'] ?? a['consultation_fee'] ?? a['price'] ?? a['fee'];
                final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                totalRevenue += amt;
              }
              final docName = (a['doctor_name'] ?? a['doctorName'] ?? '').toString();
              if (docName.isNotEmpty) distinctDoctors.add(docName);
            }

            final double avgFee = filteredAppts.isNotEmpty ? (totalRevenue / filteredAppts.length) : 0.0;

            final List<Map<String, dynamic>> chartBars = [];
            if (selectedFilter == 'This Year') {
              for (int m = 1; m <= 12; m++) {
                final monthName = DateFormat('MMM').format(DateTime(now.year, m, 1));
                double mRev = 0.0;
                for (final a in allAppts) {
                  final aDate = parseDateSafe(a['created_at'] ?? a['date']);
                  if (aDate.year == now.year && aDate.month == m) {
                    final rawAmt = a['amount'] ?? a['consultation_fee'] ?? a['price'] ?? a['fee'];
                    final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                    mRev += amt;
                  }
                }
                chartBars.add({'label': monthName, 'amount': mRev});
              }
            } else if (selectedFilter == 'This Month') {
              for (int i = 5; i >= 0; i--) {
                final startDay = now.subtract(Duration(days: (i + 1) * 5));
                final endDay = now.subtract(Duration(days: i * 5));
                final label = '${DateFormat('d').format(startDay)}-${DateFormat('d MMM').format(endDay)}';
                double bRev = 0.0;
                for (final a in allAppts) {
                  final aDate = parseDateSafe(a['created_at'] ?? a['date']);
                  if (aDate.isAfter(startDay) && aDate.isBefore(endDay.add(const Duration(days: 1)))) {
                    final rawAmt = a['amount'] ?? a['consultation_fee'] ?? a['price'] ?? a['fee'];
                    final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                    bRev += amt;
                  }
                }
                chartBars.add({'label': label, 'amount': bRev});
              }
            } else {
              for (int i = 6; i >= 0; i--) {
                final targetDay = now.subtract(Duration(days: i));
                String dayName;
                if (i == 0) {
                  dayName = 'Maanta';
                } else if (i == 1) {
                  dayName = 'Shalay';
                } else if (i == 2) {
                  dayName = 'Daraad';
                } else {
                  dayName = DateFormat('EEE, d MMM').format(targetDay);
                }

                double dayRev = 0.0;
                for (final a in allAppts) {
                  final aDate = parseDateSafe(a['created_at'] ?? a['date']);
                  if (isSameDate(aDate, targetDay)) {
                    final rawAmt = a['amount'] ?? a['consultation_fee'] ?? a['price'] ?? a['fee'];
                    final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                    dayRev += amt;
                  }
                }
                chartBars.add({'label': dayName, 'amount': dayRev, 'isSpecial': i <= 2});
              }
            }

            final maxChartAmt = chartBars.fold<double>(0.0, (max, b) => b['amount'] > max ? b['amount'] : max);
            final double safeMax = maxChartAmt > 0 ? maxChartAmt : 100.0;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                width: 950,
                constraints: const BoxConstraints(maxHeight: 820),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x20000000),
                      blurRadius: 30,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(28, 20, 20, 18),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.medical_services_rounded, color: Color(0xFF2563EB), size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dakhliga & Ballamaha Dhaqaatiirta (Doctor Appointments Revenue)',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  'Xisaabi dakhliga maanta, shalay, daraad, toddobaadkan, bishan, iyo sannadkan ee dhaqaatiirta',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildTimeFilterPill('Maanta (Today)', 'Today', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Shalay (Yesterday)', 'Yesterday', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Daraad (2 Days Ago)', '2 Days Ago', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Toddobaadkan (7 Days)', 'This Week', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Bishan (30 Days)', 'This Month', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Sannadkan (12 Months)', 'This Year', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Dhammaan (All Time)', 'All Time', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Dakhliga Dhaqaatiirta ($selectedFilter)',
                                    value: '\$${totalRevenue.toStringAsFixed(2)} USD',
                                    icon: Icons.payments_rounded,
                                    iconColor: const Color(0xFF2563EB),
                                    bgColor: const Color(0xFFEFF6FF),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Tirada Ballamaha',
                                    value: '${filteredAppts.length} Ballan',
                                    icon: Icons.calendar_month_rounded,
                                    iconColor: const Color(0xFF10B981),
                                    bgColor: const Color(0xFFECFDF5),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Dhaqaatiirta La Dalbaday',
                                    value: '${distinctDoctors.length} Dhaqtar',
                                    icon: Icons.badge_rounded,
                                    iconColor: const Color(0xFF8B5CF6),
                                    bgColor: const Color(0xFFF5F3FF),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Celceliska Ballankiiba',
                                    value: '\$${avgFee.toStringAsFixed(2)} USD',
                                    icon: Icons.trending_up_rounded,
                                    iconColor: const Color(0xFFEA580C),
                                    bgColor: const Color(0xFFFFF7ED),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.bar_chart_rounded, color: Color(0xFF2563EB), size: 20),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Muuqaalka Dakhliga Ballamaha (Doctor Booking Revenue Chart)',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF0F172A),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDBEAFE),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Max: \$${maxChartAmt.toStringAsFixed(2)} USD',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF1D4ED8),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    height: 180,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: chartBars.map((bar) {
                                        final double amt = bar['amount'] as double;
                                        final String label = bar['label'] as String;
                                        final bool isSpecial = (bar['isSpecial'] == true);
                                        final double heightFactor = (amt / safeMax).clamp(0.06, 1.0);

                                        return Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                Text(
                                                  '\$${amt.toStringAsFixed(amt % 1 == 0 ? 0 : 2)}',
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: amt > 0
                                                        ? (isSpecial ? const Color(0xFF1D4ED8) : const Color(0xFF2563EB))
                                                        : const Color(0xFF94A3B8),
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Flexible(
                                                  child: FractionallySizedBox(
                                                    heightFactor: heightFactor,
                                                    child: Container(
                                                      width: double.infinity,
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          begin: Alignment.topCenter,
                                                          end: Alignment.bottomCenter,
                                                          colors: isSpecial
                                                              ? (amt > 0
                                                                  ? [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)]
                                                                  : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)])
                                                              : (amt > 0
                                                                  ? [const Color(0xFF60A5FA), const Color(0xFF2563EB)]
                                                                  : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)]),
                                                        ),
                                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  label,
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 11,
                                                    fontWeight: isSpecial ? FontWeight.bold : FontWeight.w500,
                                                    color: isSpecial ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Ballamaha La Qabsaday Muddadan ($selectedFilter) — ${filteredAppts.length} Ballan',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (filteredAppts.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(32),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(Icons.event_busy_rounded, size: 48, color: Color(0xFFCBD5E1)),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Wax ballan dhaqtar ah lagama helin muddada ($selectedFilter).',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filteredAppts.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final a = filteredAppts[index];
                                  final docName = (a['doctor_name'] ?? a['doctorName'] ?? 'Dhaqtar').toString();
                                  final docSpec = (a['doctor_specialty'] ?? a['doctorSpecialty'] ?? 'General').toString();
                                  final patName = (a['patient_name'] ?? a['patientName'] ?? 'Bukaan').toString();
                                  final rawAmt = a['amount'] ?? a['consultation_fee'] ?? a['price'] ?? a['fee'];
                                  final amount = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                                  final queue = (a['queue_number'] ?? a['queueNumber'] ?? 1).toString();
                                  final paymentMethod = (a['payment_method'] ?? a['paymentMethod'] ?? 'EVC Plus').toString();
                                  final createdAtRaw = a['created_at']?.toString() ?? a['date']?.toString();
                                  String formattedTime = 'Recently';
                                  if (createdAtRaw != null && createdAtRaw.isNotEmpty) {
                                    try {
                                      final dt = DateTime.parse(createdAtRaw).toLocal();
                                      formattedTime = DateFormat('EEE, d MMM yyyy • hh:mm a').format(dt);
                                    } catch (_) {}
                                  }

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEFF6FF),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.person_pin_rounded, color: Color(0xFF2563EB), size: 20),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    docName,
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                      color: const Color(0xFF0F172A),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFEEF2FF),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      docSpec,
                                                      style: GoogleFonts.plusJakartaSans(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: const Color(0xFF4F46E5),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFDCFCE7),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      'Queue #$queue',
                                                      style: GoogleFonts.plusJakartaSans(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: const Color(0xFF16A34A),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                'Bukaan: $patName • $formattedTime',
                                                style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 11,
                                                  color: const Color(0xFF64748B),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '\$${amount.toStringAsFixed(2)} USD',
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: const Color(0xFF2563EB),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              paymentMethod,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 11,
                                                color: const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- INTERACTIVE NURSE HOME CARE REVENUE ANALYTICS MODAL ---
  void _showNurseRevenueAnalyticsDialog(
    BuildContext context,
    AppState appState,
    List<Map<String, dynamic>> allNurseOrders,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        String selectedFilter = 'This Week';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final now = DateTime.now();

            DateTime parseDateSafe(dynamic raw) {
              if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0);
              final str = raw.toString().trim();
              if (str.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
              final dt = DateTime.tryParse(str);
              if (dt != null) return dt.toLocal();
              final intVal = int.tryParse(str);
              if (intVal != null) return DateTime.fromMillisecondsSinceEpoch(intVal).toLocal();
              return DateTime.fromMillisecondsSinceEpoch(0);
            }

            bool isSameDate(DateTime a, DateTime b) {
              return a.year == b.year && a.month == b.month && a.day == b.day;
            }

            final yesterday = now.subtract(const Duration(days: 1));
            final twoDaysAgo = now.subtract(const Duration(days: 2));

            final List<Map<String, dynamic>> filteredOrders = [];
            for (final n in allNurseOrders) {
              final nDate = parseDateSafe(n['created_at'] ?? n['date']);
              bool matches = false;

              if (selectedFilter == 'Today') {
                matches = isSameDate(nDate, now);
              } else if (selectedFilter == 'Yesterday') {
                matches = isSameDate(nDate, yesterday);
              } else if (selectedFilter == '2 Days Ago') {
                matches = isSameDate(nDate, twoDaysAgo);
              } else if (selectedFilter == 'This Week') {
                matches = nDate.isAfter(now.subtract(const Duration(days: 7)));
              } else if (selectedFilter == 'This Month') {
                matches = nDate.isAfter(now.subtract(const Duration(days: 30)));
              } else if (selectedFilter == 'This Year') {
                matches = nDate.isAfter(now.subtract(const Duration(days: 365)));
              } else {
                matches = true;
              }

              if (matches) filteredOrders.add(n);
            }

            double totalRevenue = 0.0;
            final Set<String> distinctNurses = {};
            for (final n in filteredOrders) {
              final status = (n['status'] ?? n['order_status'] ?? '').toString().toLowerCase();
              if (!status.contains('cancel') && !status.contains('reject')) {
                final rawAmt = n['amount'] ?? n['total_amount'] ?? n['price'] ?? n['fee'];
                final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                totalRevenue += amt;
              }
              final nurseName = (n['nurse_name'] ?? n['nurseName'] ?? '').toString();
              if (nurseName.isNotEmpty) distinctNurses.add(nurseName);
            }

            final double avgFee = filteredOrders.isNotEmpty ? (totalRevenue / filteredOrders.length) : 0.0;

            final List<Map<String, dynamic>> chartBars = [];
            if (selectedFilter == 'This Year') {
              for (int m = 1; m <= 12; m++) {
                final monthName = DateFormat('MMM').format(DateTime(now.year, m, 1));
                double mRev = 0.0;
                for (final n in allNurseOrders) {
                  final nDate = parseDateSafe(n['created_at'] ?? n['date']);
                  if (nDate.year == now.year && nDate.month == m) {
                    final rawAmt = n['amount'] ?? n['total_amount'] ?? n['price'] ?? n['fee'];
                    final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                    mRev += amt;
                  }
                }
                chartBars.add({'label': monthName, 'amount': mRev});
              }
            } else if (selectedFilter == 'This Month') {
              for (int i = 5; i >= 0; i--) {
                final startDay = now.subtract(Duration(days: (i + 1) * 5));
                final endDay = now.subtract(Duration(days: i * 5));
                final label = '${DateFormat('d').format(startDay)}-${DateFormat('d MMM').format(endDay)}';
                double bRev = 0.0;
                for (final n in allNurseOrders) {
                  final nDate = parseDateSafe(n['created_at'] ?? n['date']);
                  if (nDate.isAfter(startDay) && nDate.isBefore(endDay.add(const Duration(days: 1)))) {
                    final rawAmt = n['amount'] ?? n['total_amount'] ?? n['price'] ?? n['fee'];
                    final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                    bRev += amt;
                  }
                }
                chartBars.add({'label': label, 'amount': bRev});
              }
            } else {
              for (int i = 6; i >= 0; i--) {
                final targetDay = now.subtract(Duration(days: i));
                String dayName;
                if (i == 0) {
                  dayName = 'Maanta';
                } else if (i == 1) {
                  dayName = 'Shalay';
                } else if (i == 2) {
                  dayName = 'Daraad';
                } else {
                  dayName = DateFormat('EEE, d MMM').format(targetDay);
                }

                double dayRev = 0.0;
                for (final n in allNurseOrders) {
                  final nDate = parseDateSafe(n['created_at'] ?? n['date']);
                  if (isSameDate(nDate, targetDay)) {
                    final rawAmt = n['amount'] ?? n['total_amount'] ?? n['price'] ?? n['fee'];
                    final amt = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                    dayRev += amt;
                  }
                }
                chartBars.add({'label': dayName, 'amount': dayRev, 'isSpecial': i <= 2});
              }
            }

            final maxChartAmt = chartBars.fold<double>(0.0, (max, b) => b['amount'] > max ? b['amount'] : max);
            final double safeMax = maxChartAmt > 0 ? maxChartAmt : 100.0;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                width: 950,
                constraints: const BoxConstraints(maxHeight: 820),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x20000000),
                      blurRadius: 30,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(28, 20, 20, 18),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD1FAE5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.health_and_safety_rounded, color: Color(0xFF059669), size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dakhliga Adeegga Kalkaalisada Guriga (Nurse Home Care Revenue)',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  'Xisaabi dakhliga maanta, shalay, daraad, toddobaadkan, bishan, iyo sannadkan ee kalkaalisada',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildTimeFilterPill('Maanta (Today)', 'Today', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Shalay (Yesterday)', 'Yesterday', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Daraad (2 Days Ago)', '2 Days Ago', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Toddobaadkan (7 Days)', 'This Week', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Bishan (30 Days)', 'This Month', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Sannadkan (12 Months)', 'This Year', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Dhammaan (All Time)', 'All Time', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Dakhliga Kalkaalisada ($selectedFilter)',
                                    value: '\$${totalRevenue.toStringAsFixed(2)} USD',
                                    icon: Icons.payments_rounded,
                                    iconColor: const Color(0xFF059669),
                                    bgColor: const Color(0xFFD1FAE5),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Tirada Dalabaadka',
                                    value: '${filteredOrders.length} Dalab',
                                    icon: Icons.home_work_rounded,
                                    iconColor: const Color(0xFF2563EB),
                                    bgColor: const Color(0xFFEFF6FF),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Kalkaaliyayaasha La Diray',
                                    value: '${distinctNurses.length} Kalkaaliso',
                                    icon: Icons.people_alt_rounded,
                                    iconColor: const Color(0xFF8B5CF6),
                                    bgColor: const Color(0xFFF5F3FF),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Celceliska Dalabkiiba',
                                    value: '\$${avgFee.toStringAsFixed(2)} USD',
                                    icon: Icons.trending_up_rounded,
                                    iconColor: const Color(0xFFEA580C),
                                    bgColor: const Color(0xFFFFF7ED),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.bar_chart_rounded, color: Color(0xFF059669), size: 20),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Muuqaalka Dakhliga Kalkaalisada (Nurse Dispatch Revenue Chart)',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF0F172A),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDCFCE7),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Max: \$${maxChartAmt.toStringAsFixed(2)} USD',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF15803D),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    height: 180,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: chartBars.map((bar) {
                                        final double amt = bar['amount'] as double;
                                        final String label = bar['label'] as String;
                                        final bool isSpecial = (bar['isSpecial'] == true);
                                        final double heightFactor = (amt / safeMax).clamp(0.06, 1.0);

                                        return Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                Text(
                                                  '\$${amt.toStringAsFixed(amt % 1 == 0 ? 0 : 2)}',
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: amt > 0
                                                        ? (isSpecial ? const Color(0xFF059669) : const Color(0xFF10B981))
                                                        : const Color(0xFF94A3B8),
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Flexible(
                                                  child: FractionallySizedBox(
                                                    heightFactor: heightFactor,
                                                    child: Container(
                                                      width: double.infinity,
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          begin: Alignment.topCenter,
                                                          end: Alignment.bottomCenter,
                                                          colors: isSpecial
                                                              ? (amt > 0
                                                                  ? [const Color(0xFF059669), const Color(0xFF047857)]
                                                                  : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)])
                                                              : (amt > 0
                                                                  ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                                                  : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)]),
                                                        ),
                                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  label,
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 11,
                                                    fontWeight: isSpecial ? FontWeight.bold : FontWeight.w500,
                                                    color: isSpecial ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Dalabaadka Kalkaalisada ee Muddadan ($selectedFilter) — ${filteredOrders.length} Dalab',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (filteredOrders.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(32),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(Icons.home_repair_service_rounded, size: 48, color: Color(0xFFCBD5E1)),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Wax dalab kalkaaliso ah lagama helin muddada ($selectedFilter).',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filteredOrders.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final n = filteredOrders[index];
                                  final nurseName = (n['nurse_name'] ?? n['nurseName'] ?? 'Kalkaaliso').toString();
                                  final patName = (n['patient_name'] ?? n['patientName'] ?? 'Bukaan').toString();
                                  final notes = (n['service_notes'] ?? n['notes'] ?? 'Home Care Service').toString();
                                  final rawAmt = n['amount'] ?? n['total_amount'] ?? n['price'] ?? n['fee'];
                                  final amount = (rawAmt as num?)?.toDouble() ?? (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                                  final paymentMethod = (n['payment_method'] ?? 'EVC Plus').toString();
                                  final createdAtRaw = n['created_at']?.toString() ?? n['date']?.toString();
                                  String formattedTime = 'Recently';
                                  if (createdAtRaw != null && createdAtRaw.isNotEmpty) {
                                    try {
                                      final dt = DateTime.parse(createdAtRaw).toLocal();
                                      formattedTime = DateFormat('EEE, d MMM yyyy • hh:mm a').format(dt);
                                    } catch (_) {}
                                  }

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFD1FAE5),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.health_and_safety_rounded, color: Color(0xFF059669), size: 20),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    'Kalkaaliso: $nurseName',
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                      color: const Color(0xFF0F172A),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFDCFCE7),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      'Home Care',
                                                      style: GoogleFonts.plusJakartaSans(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: const Color(0xFF16A34A),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                'Bukaan: $patName ($notes) • $formattedTime',
                                                style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 11,
                                                  color: const Color(0xFF64748B),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '\$${amount.toStringAsFixed(2)} USD',
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: const Color(0xFF059669),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              paymentMethod,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 11,
                                                color: const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- INTERACTIVE COMBINED TOTAL HOSPITAL REVENUE ANALYTICS MODAL ---
  void _showCombinedRevenueAnalyticsDialog(
    BuildContext context,
    AppState appState,
    List<Map<String, dynamic>> orders,
    List<Map<String, dynamic>> appts,
    List<Map<String, dynamic>> nurseOrders,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        String selectedFilter = 'This Week';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final now = DateTime.now();

            DateTime parseDateSafe(dynamic raw) {
              if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0);
              final str = raw.toString().trim();
              if (str.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
              final dt = DateTime.tryParse(str);
              if (dt != null) return dt.toLocal();
              final intVal = int.tryParse(str);
              if (intVal != null) return DateTime.fromMillisecondsSinceEpoch(intVal).toLocal();
              return DateTime.fromMillisecondsSinceEpoch(0);
            }

            bool isSameDate(DateTime a, DateTime b) {
              return a.year == b.year && a.month == b.month && a.day == b.day;
            }

            final yesterday = now.subtract(const Duration(days: 1));
            final twoDaysAgo = now.subtract(const Duration(days: 2));

            bool matchesFilter(DateTime itemDate) {
              if (selectedFilter == 'Today') return isSameDate(itemDate, now);
              if (selectedFilter == 'Yesterday') return isSameDate(itemDate, yesterday);
              if (selectedFilter == '2 Days Ago') return isSameDate(itemDate, twoDaysAgo);
              if (selectedFilter == 'This Week') return itemDate.isAfter(now.subtract(const Duration(days: 7)));
              if (selectedFilter == 'This Month') return itemDate.isAfter(now.subtract(const Duration(days: 30)));
              if (selectedFilter == 'This Year') return itemDate.isAfter(now.subtract(const Duration(days: 365)));
              return true;
            }

            // Pharmacy
            double pRev = 0.0;
            int pCount = 0;
            for (final o in orders) {
              final d = parseDateSafe(o['created_at'] ?? o['date']);
              if (matchesFilter(d)) {
                pCount++;
                final s = (o['status'] ?? '').toString().toLowerCase();
                if (!s.contains('cancel')) {
                  final raw = o['total_amount'] ?? o['total'] ?? o['amount'] ?? o['price'];
                  pRev += (raw as num?)?.toDouble() ?? (double.tryParse(raw?.toString() ?? '') ?? 0.0);
                }
              }
            }

            // Doctors
            double dRev = 0.0;
            int dCount = 0;
            for (final a in appts) {
              final d = parseDateSafe(a['created_at'] ?? a['date']);
              if (matchesFilter(d)) {
                dCount++;
                final s = (a['status'] ?? '').toString().toLowerCase();
                if (!s.contains('cancel') && !s.contains('reject')) {
                  final raw = a['amount'] ?? a['consultation_fee'] ?? a['price'] ?? a['fee'];
                  dRev += (raw as num?)?.toDouble() ?? (double.tryParse(raw?.toString() ?? '') ?? 0.0);
                }
              }
            }

            // Nurses
            double nRev = 0.0;
            int nCount = 0;
            for (final n in nurseOrders) {
              final d = parseDateSafe(n['created_at'] ?? n['date']);
              if (matchesFilter(d)) {
                nCount++;
                final s = (n['status'] ?? n['order_status'] ?? '').toString().toLowerCase();
                if (!s.contains('cancel') && !s.contains('reject')) {
                  final raw = n['amount'] ?? n['total_amount'] ?? n['price'] ?? n['fee'];
                  nRev += (raw as num?)?.toDouble() ?? (double.tryParse(raw?.toString() ?? '') ?? 0.0);
                }
              }
            }

            final double grandTotal = pRev + dRev + nRev;
            final int grandOrders = pCount + dCount + nCount;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                width: 950,
                constraints: const BoxConstraints(maxHeight: 820),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x20000000),
                      blurRadius: 30,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(28, 20, 20, 18),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3E8FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF7C3AED), size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Wadarta Dakhliga Guud ee Isbitaalka (Total Hospital Revenue)',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  'Isku darka dakhliga Dawooyinka, Dhaqaatiirta, iyo Kalkaalisada ee Isbitaalka Nasiib',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildTimeFilterPill('Maanta (Today)', 'Today', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Shalay (Yesterday)', 'Yesterday', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Daraad (2 Days Ago)', '2 Days Ago', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Toddobaadkan (7 Days)', 'This Week', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Bishan (30 Days)', 'This Month', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Sannadkan (12 Months)', 'This Year', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                  const SizedBox(width: 8),
                                  _buildTimeFilterPill('Dhammaan (All Time)', 'All Time', selectedFilter, (val) => setModalState(() => selectedFilter = val)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Dakhliga Dawooyinka',
                                    value: '\$${pRev.toStringAsFixed(2)} USD',
                                    icon: Icons.medication_rounded,
                                    iconColor: const Color(0xFF10B981),
                                    bgColor: const Color(0xFFECFDF5),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Dakhliga Dhaqaatiirta',
                                    value: '\$${dRev.toStringAsFixed(2)} USD',
                                    icon: Icons.medical_services_rounded,
                                    iconColor: const Color(0xFF2563EB),
                                    bgColor: const Color(0xFFEFF6FF),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Dakhliga Kalkaalisada',
                                    value: '\$${nRev.toStringAsFixed(2)} USD',
                                    icon: Icons.health_and_safety_rounded,
                                    iconColor: const Color(0xFF059669),
                                    bgColor: const Color(0xFFD1FAE5),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildRevenueMetricBox(
                                    title: 'Wadarta Guud ($selectedFilter)',
                                    value: '\$${grandTotal.toStringAsFixed(2)} USD',
                                    icon: Icons.account_balance_wallet_rounded,
                                    iconColor: const Color(0xFF7C3AED),
                                    bgColor: const Color(0xFFF3E8FF),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFF5F3FF), Color(0xFFEFF6FF)],
                                ),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFFDDD6FE)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7C3AED),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(Icons.pie_chart_rounded, color: Colors.white, size: 28),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Guud ahaan Isbitaalka Nasiib ($selectedFilter)',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Wadarta dhammaan adeegyada la qabtay waa $grandOrders (Dawooyin: $pCount, Ballamo Dhaqtar: $dCount, Kalkaalisada Guriga: $nCount)',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '\$${grandTotal.toStringAsFixed(2)} USD',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFF7C3AED),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTimeFilterPill(
    String label,
    String key,
    String selectedKey,
    Function(String) onSelect,
  ) {
    final bool isSelected = key == selectedKey;
    return InkWell(
      onTap: () => onSelect(key),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: const Color(0xFF10B981).withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildRevenueMetricBox({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- APPOINTMENTS & PHARMACY REVENUE OVERVIEW LINE CHART CARD (Dynamic from Supabase) ---
  Widget _buildAppointmentsOverviewChartCard(AppState appState) {
    final now = DateTime.now();
    final days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));
    final dayLabels = days.map((d) => DateFormat('d MMM').format(d)).toList();

    final client = SupabaseService.instance.client;
    final bool canStream = client != null && SupabaseService.instance.isInitialized;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: canStream
          ? client.from('orders').stream(primaryKey: ['id']).order('created_at', ascending: false)
          : const Stream.empty(),
      builder: (context, snapshot) {
        final List<Map<String, dynamic>> orders = (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty)
            ? snapshot.data!
            : appState.orders;

        return Container(
          padding: const EdgeInsets.all(24),
          height: 380,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Overview Statistics',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _showPharmacyRevenueAnalyticsDialog(context, appState, orders),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.analytics_rounded, size: 12, color: Color(0xFF059669)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Dakhliga & Chart',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF059669),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 3,
                            color: const Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Registered Patients',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            width: 10,
                            height: 3,
                            color: const Color(0xFF10B981),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Pharmacy Revenue (Live)',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () => _showPharmacyRevenueAnalyticsDialog(context, appState, orders),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            'This Week (Chart)',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.tune_rounded,
                            color: Color(0xFF64748B),
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: InkWell(
                  onTap: () => _showPharmacyRevenueAnalyticsDialog(context, appState, orders),
                  child: Stack(
                    children: [
                      // Horizontal Grid lines
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(
                          5,
                          (index) =>
                              const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        ),
                      ),
                      // Custom Painted Graph Curves
                      Positioned.fill(
                        child: CustomPaint(painter: CarePlusLineChartPainter()),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Dynamic X-Axis Day Labels
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: dayLabels.map((day) {
                  return Text(
                    day,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- DAWOOYINKA LA GADAY (SOLD MEDICINES CARD) ---
  Widget _buildRecentActivitiesCard(AppState appState) {
    final client = SupabaseService.instance.client;
    final bool canStream = client != null && SupabaseService.instance.isInitialized;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: canStream
          ? client.from('orders').stream(primaryKey: ['id']).order('created_at', ascending: false)
          : const Stream.empty(),
      builder: (context, snapshot) {
        final List<Map<String, dynamic>> orders = (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty)
            ? snapshot.data!
            : appState.orders;

        final allItems = appState.orderItems;
        final soldItems = <Map<String, dynamic>>[];

        for (var order in orders) {
          final orderId = order['id']?.toString() ?? '';
          final patientName = (order['patient_name'] ?? order['customer_name'] ?? order['user_name'] ?? order['full_name'] ?? 'Bukaan').toString();
          final createdAtRaw = order['created_at']?.toString() ?? order['date']?.toString();

          String formattedTime = 'Maanta';
          if (createdAtRaw != null && createdAtRaw.isNotEmpty) {
            try {
              final dt = DateTime.parse(createdAtRaw).toLocal();
              formattedTime = DateFormat('hh:mm a').format(dt);
            } catch (_) {
              formattedTime = 'Recently';
            }
          }

          final matchingItems = allItems.where((i) => i['order_id']?.toString() == orderId).toList();

          if (matchingItems.isNotEmpty) {
            for (var item in matchingItems) {
              final medName = (item['medicine_name'] ?? item['name'] ?? item['title'] ?? 'Dawo').toString();
              final qty = item['quantity'] ?? item['qty'] ?? 1;
              final priceVal = item['price'] ?? item['unit_price'] ?? item['total_price'] ?? order['total_amount'] ?? order['total'] ?? 0;
              final double parsedPrice = double.tryParse(priceVal.toString()) ?? 0.0;

              soldItems.add({
                'order_id': orderId,
                'name': medName,
                'patient': patientName,
                'qty': qty,
                'price': parsedPrice > 0 ? '\$${parsedPrice.toStringAsFixed(2)}' : '',
                'time': formattedTime,
              });
            }
          } else {
            // Fallback for orders without separate order_items rows
            final rawSummary = order['items_summary'] ?? order['items'] ?? order['medicines'] ?? order['description'] ?? 'Dalab Dawo';
            String itemsSummary = rawSummary.toString();
            if (itemsSummary.startsWith('[') && itemsSummary.endsWith(']')) {
              itemsSummary = 'Dalab Dawo';
            }

            final rawTotal = order['total_amount'] ?? order['total_price'] ?? order['total'] ?? order['amount'] ?? 0;
            final double parsedTotal = double.tryParse(rawTotal.toString()) ?? 0.0;

            soldItems.add({
              'order_id': orderId,
              'name': itemsSummary.isNotEmpty ? itemsSummary : 'Dalab Dawo',
              'patient': patientName,
              'qty': 1,
              'price': parsedTotal > 0 ? '\$${parsedTotal.toStringAsFixed(2)}' : '',
              'time': formattedTime,
            });
          }
        }

        return Container(
          padding: const EdgeInsets.all(24),
          height: 380,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Dawooyinka La Gaday',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${soldItems.length} Iib',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF15803D),
                          ),
                        ),
                      ),
                      if (soldItems.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Tirtir Dhamaan Dawooyinka La Gaday',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('Tirtir Dhamaan Dawooyinka', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                                  content: Text('Ma ziirtaa inaad tirtirto dhammaan iibka dawooyinkan ku muuqda kaardka?', style: GoogleFonts.plusJakartaSans()),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: Text('Kanoo maaha', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B))),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: Text('Haa, Tirtir Dhamaan', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                final client = SupabaseService.instance.client;
                                if (client != null) {
                                  try {
                                    await client.from('order_items').delete().neq('id', '00000000-0000-0000-0000-000000000000');
                                  } catch (_) {}
                                  try {
                                    await client.from('orders').delete().neq('id', '00000000-0000-0000-0000-000000000000');
                                  } catch (_) {}
                                }
                                appState.orders.clear();
                                appState.orderItems.clear();
                                appState.notifyListeners();
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.delete_sweep_rounded,
                                color: Colors.red.shade400,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: soldItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.medication_liquid_rounded,
                              size: 36,
                              color: Color(0xFFCBD5E1),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Weli ma jiro dawooyin la gaday',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: soldItems.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = soldItems[index];
                          final targetOrderId = item['order_id']?.toString() ?? '';

                          return Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.medication_rounded,
                                  color: Color(0xFF10B981),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name'] as String,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${item['patient']} • ${item['qty']} xabo',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if ((item['price'] as String).isNotEmpty)
                                    Text(
                                      item['price'] as String,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF15803D),
                                      ),
                                    ),
                                  Text(
                                    item['time'] as String,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'Tirtir iibkan',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text('Tirtir Daawada/Dalabka', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                                        content: Text('Ma ziirtaa inaad tirtirto iibkan daawada ah?', style: GoogleFonts.plusJakartaSans()),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: Text('Kanoo maaha', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B))),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: Text('Haa, Tirtir', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm == true && targetOrderId.isNotEmpty) {
                                      final client = SupabaseService.instance.client;
                                      if (client != null) {
                                        try {
                                          await client.from('order_items').delete().eq('order_id', targetOrderId);
                                        } catch (_) {}
                                        try {
                                          await client.from('orders').delete().eq('id', targetOrderId);
                                        } catch (_) {}
                                      }
                                      appState.orders.removeWhere((o) => o['id']?.toString() == targetOrderId);
                                      appState.notifyListeners();
                                    }
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(4.0),
                                    child: Icon(
                                      Icons.delete_outline_rounded,
                                      color: Color(0xFFEF4444),
                                      size: 17,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- TODAY'S APPOINTMENTS CARD (Dynamic from Supabase) ---
  Widget _buildTodaysAppointmentsCard(AppState appState) {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todaysAppointments = appState.appointments
        .where(
          (a) => a.date.contains(todayStr) || a.createdAt.contains(todayStr),
        )
        .toList();

    return Container(
      padding: const EdgeInsets.all(24),
      height: 380,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Today's Appointments",
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Text(
                'View all',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2563EB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: todaysAppointments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.calendar_today_rounded,
                          size: 36,
                          color: Color(0xFFCBD5E1),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No appointments today',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: todaysAppointments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final apt = todaysAppointments[index];
                      final bool isConfirmed = apt.status == 'Confirmed';

                      return Row(
                        children: [
                          NetworkOrAssetImage(
                            imageUrl: apt.doctorImageUrl,
                            width: 38,
                            height: 38,
                            borderRadius: BorderRadius.circular(19),
                            fit: BoxFit.cover,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  apt.patientName,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  '${apt.time} • ${apt.appointmentType}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                Text(
                                  apt.doctorName,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isConfirmed
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              apt.status,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isConfirmed
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _getPatientInitials(String name) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return 'P';
    final parts = cleanName.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final first = parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '';
    } else if (cleanName.length >= 2) {
      return cleanName.substring(0, 2).toUpperCase();
    }
    return cleanName[0].toUpperCase();
  }

  Widget _buildPatientsOverviewTableCard(AppState appState) {
    final List<Map<String, dynamic>> registeredUsers = [];
    final Set<String> seenIds = {};

    for (final p in appState.dbPatients) {
      final String id = (p['id'] ?? p['user_id'] ?? '').toString();
      final String pName = (p['full_name'] ?? p['name'] ?? p['patient_name'] ?? '').toString().trim();
      final String pPhone = (p['phone_number'] ?? p['phone'] ?? '').toString().trim();
      final String pEmail = (p['email'] ?? '').toString().trim();
      final String pAvatar = (p['avatar_url'] ?? p['patient_image'] ?? p['image_url'] ?? '').toString().trim();
      final String rawCreatedAt = (p['created_at'] ?? '').toString();

      final dedupeKey = id.isNotEmpty ? id : '${pName}_$pPhone';
      if (seenIds.contains(dedupeKey)) continue;
      seenIds.add(dedupeKey);

      String joinedDate = 'Recent';
      if (rawCreatedAt.isNotEmpty) {
        final dt = DateTime.tryParse(rawCreatedAt);
        if (dt != null) {
          joinedDate = DateFormat('dd MMM yyyy').format(dt.toLocal());
        }
      }

      registeredUsers.add({
        'id': id,
        'name': pName.isNotEmpty ? pName : 'Registered User',
        'email': pEmail.isNotEmpty ? pEmail : 'N/A',
        'phone': pPhone.isNotEmpty ? pPhone : 'N/A',
        'joined_date': joinedDate,
        'avatar': pAvatar,
        'status': 'Active',
      });
    }

    return Container(
      padding: const EdgeInsets.all(24),
      height: 380,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dadka Kusoo Biiray (Registered Users)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Text(
                'Total: ${registeredUsers.length}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2563EB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Table Headers
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'User / Bukaan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Email',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Phone',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Joined Date',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: registeredUsers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.people_outline_rounded,
                          size: 36,
                          color: Color(0xFFCBD5E1),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No registered users yet',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: registeredUsers.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, index) {
                      final u = registeredUsers[index];
                      final String uName = u['name'];
                      final String uEmail = u['email'];
                      final String uPhone = u['phone'];
                      final String uJoined = u['joined_date'];
                      final String uAvatar = u['avatar'];

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: uAvatar.isNotEmpty
                                        ? const Color(0xFFEFF6FF)
                                        : const Color(0xFF0D9488),
                                    backgroundImage: uAvatar.isNotEmpty
                                        ? NetworkImage(uAvatar)
                                        : null,
                                    child: uAvatar.isEmpty
                                        ? Text(
                                            _getPatientInitials(uName),
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      uName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                uEmail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                uPhone,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                uJoined,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Active',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF16A34A),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAppointmentDialog(
    BuildContext context,
    AppState appState,
    String id,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Tirtir Ballanta (Permanently Delete)',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: const Color(0xFF0F172A),
            ),
          ),
          content: Text(
            'Ma hubtaa inaad ballantan si joogto ah uga tirtirto nidaamka iyo Supabase?',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: const Color(0xFF475569),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Kanoqo',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await appState.deleteAppointment(id);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Tirtir',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // --- DOCTORS STATUS LIST CARD (Dynamic from Supabase DB) ---
  Widget _buildDoctorsStatusListCard(AppState appState) {
    final doctors = appState.doctors;

    return Container(
      padding: const EdgeInsets.all(24),
      height: 380,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Doctors',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Text(
                'View all',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2563EB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: doctors.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.badge_outlined,
                          size: 36,
                          color: Color(0xFFCBD5E1),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No doctors registered yet',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: doctors.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final d = doctors[index];
                      final bool isOnline = d.isOnline;
                      final String statusStr = isOnline ? 'Online' : 'Offline';
                      Color badgeBg = isOnline
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFF1F5F9);
                      Color badgeText = isOnline
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF64748B);

                      return Row(
                        children: [
                          NetworkOrAssetImage(
                            imageUrl: d.imageUrl,
                            width: 38,
                            height: 38,
                            borderRadius: BorderRadius.circular(19),
                            fit: BoxFit.cover,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.name,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  d.specialty,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartBar(String label, double val1, double val2) {
    final maxVal = 350.0;
    final h1 = (val1 / maxVal) * 160.0;
    final h2 = (val2 / maxVal) * 160.0;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 14,
              height: h1,
              decoration: const BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 14,
              height: h2,
              decoration: const BoxDecoration(
                color: Color(0xFF0288D1),
                borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard(String title, String count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                count,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: DOCTOR MANAGEMENT
  // ==========================================
  Widget _buildDoctorsTab(BuildContext context) {
    final appState = context.watch<AppState>();
    final doctors = appState.doctors
        .where(
          (d) =>
              !d.specialty.toLowerCase().contains('kalkaaliso') &&
              !d.specialty.toLowerCase().contains('nurse'),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Doctor Management',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _showAddDoctorDialog(context),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add New Doctor',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: doctors.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = doctors[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  NetworkOrAssetImage(
                    imageUrl: doc.imageUrl,
                    width: 60,
                    height: 60,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          '${doc.specialty} • ${doc.hospital}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          'Working: ${doc.workingHours}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.edit_rounded,
                      color: AppTheme.primaryColor,
                    ),
                    onPressed: () {
                      _showEditDoctorDialog(context, doc);
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppTheme.errorRed,
                    ),
                    onPressed: () {
                      appState.deleteDoctor(doc.id);
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ==========================================
  // TAB 9: NURSE MANAGEMENT
  // ==========================================
  Widget _buildNursesTab(BuildContext context) {
    final appState = context.watch<AppState>();
    final nurses = appState.nurses;
    final nurseBookings = appState.appointments
        .where(
          (a) =>
              a.doctorSpecialty.toLowerCase().contains('kalkaaliso') ||
              a.appointmentType.toLowerCase().contains('nursing') ||
              a.reasonForVisit.toLowerCase().contains('nurse'),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Nurse Management (Kalkaalisada)',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _showAddNurseDialog(context),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add New Nurse',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Incoming Nurse Dispatch Requests Section
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.medical_services_rounded,
                    color: AppTheme.primaryColor,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Incoming Nurse Dispatch Requests (${nurseBookings.length})',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (nurseBookings.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Text(
                    'Waqtigan ma jiraan dalabyo kalkaaliso oo cusub.',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Customer')),
                      DataColumn(label: Text('Phone')),
                      DataColumn(label: Text('Address / District')),
                      DataColumn(label: Text('Nurse')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: nurseBookings.map((nb) {
                      final status = nb.status;
                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              nb.patientName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataCell(Text(nb.patientPhone)),
                          DataCell(
                            Text(
                              nb.reasonForVisit.replaceAll(
                                'Nurse Request: ',
                                '',
                              ),
                            ),
                          ),
                          DataCell(Text(nb.doctorName)),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    status == 'Approved' ||
                                        status == 'Confirmed' ||
                                        status == 'In Transit'
                                    ? Colors.green.shade50
                                    : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      status == 'Approved' ||
                                          status == 'Confirmed' ||
                                          status == 'In Transit'
                                      ? Colors.green.shade300
                                      : Colors.orange.shade300,
                                ),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      status == 'Approved' ||
                                          status == 'Confirmed' ||
                                          status == 'In Transit'
                                      ? Colors.green.shade800
                                      : Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Row(
                              children: [
                                ElevatedButton(
                                  onPressed: () {
                                    final newStatus = status == 'Pending'
                                        ? 'Approved'
                                        : 'In Transit';
                                    appState.updateAppointmentStatus(
                                      nb.id,
                                      newStatus,
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                  ),
                                  child: Text(
                                    status == 'Pending'
                                        ? 'Approve & Dispatch'
                                        : 'Mark In Transit',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        Text(
          'Registered Hospital Nurses Directory',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: nurses.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final nurse = nurses[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  NetworkOrAssetImage(
                    imageUrl: nurse.imageUrl,
                    width: 60,
                    height: 60,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nurse.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          nurse.specialty,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      appState.setNurseAvailability(nurse.id, !nurse.isAvailable);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: nurse.isAvailable ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: nurse.isAvailable ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            nurse.isAvailable ? '🟢 Available' : '🔴 Busy',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: nurse.isAvailable ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            nurse.isAvailable ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                            color: nurse.isAvailable ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(
                      Icons.edit_rounded,
                      color: AppTheme.primaryColor,
                    ),
                    onPressed: () {
                      _showEditNurseDialog(context, nurse);
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppTheme.errorRed,
                    ),
                    onPressed: () {
                      appState.deleteNurse(nurse.id);
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHomeCareTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Home Care Services & Nurse Orders',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Real-time nurse dispatch orders & home health visits',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),

        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: (SupabaseService.instance.client != null && SupabaseService.instance.isInitialized)
                ? SupabaseService.instance.client!
                    .from('nurse_orders')
                    .stream(primaryKey: ['id'])
                    .order('created_at', ascending: false)
                : Stream.value([]),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final orders = snapshot.data ?? [];

              if (orders.isEmpty) {
                return Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.home_repair_service_rounded,
                          size: 48,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No Home Care Orders Found',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Home care nurse bookings will appear here automatically in real-time.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 24,
                    horizontalMargin: 20,
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                    columns: [
                      DataColumn(label: Text('Patient Name', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Phone', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Service Requested', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Location / Address', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Fee', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Payment', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Order Status', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold))),
                    ],
                    rows: orders.map((o) {
                      final orderId = (o['id'] ?? o['booking_id'] ?? '').toString();
                      final patientName = (o['patient_name'] ?? o['customer_name'] ?? o['full_name'] ?? o['name'] ?? 'Patient').toString();
                      final phone = (o['phone'] ?? o['patient_phone'] ?? o['phoneNumber'] ?? o['contact_phone'] ?? '').toString();
                      final nurseName = (o['nurse_name'] ?? o['service_type'] ?? o['doctor_name'] ?? 'Home Care Nurse').toString();
                      final district = (o['district'] ?? '').toString();
                      final address = (o['address'] ?? o['delivery_address'] ?? o['neighborhood'] ?? (district.isNotEmpty ? '$district, Mogadishu' : 'Mogadishu')).toString();
                      final fee = (o['fee'] ?? o['total_amount'] ?? o['amount'] ?? 0.0).toString();
                      final paymentStatus = (o['payment_status'] ?? o['paymentStatus'] ?? 'Paid').toString();
                      final status = (o['status'] ?? o['order_status'] ?? 'Pending').toString();

                      return DataRow(
                        cells: [
                          DataCell(Text(patientName, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600))),
                          DataCell(Text(phone.isNotEmpty ? phone : 'N/A', style: GoogleFonts.plusJakartaSans())),
                          DataCell(
                            Row(
                              children: [
                                const Icon(Icons.medical_services_outlined, size: 16, color: AppTheme.primaryColor),
                                const SizedBox(width: 6),
                                Text('Nurse ($nurseName)', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                          DataCell(Text(address, style: GoogleFonts.plusJakartaSans())),
                          DataCell(Text('\$$fee', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold))),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: paymentStatus == 'Paid' ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                paymentStatus,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: paymentStatus == 'Paid' ? const Color(0xFF15803D) : const Color(0xFFD97706),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            DropdownButton<String>(
                              value: ['Pending', 'In Progress', 'Completed', 'Cancelled'].contains(status) ? status : 'Pending',
                              underline: const SizedBox(),
                              items: ['Pending', 'In Progress', 'Completed', 'Cancelled']
                                  .map((st) => DropdownMenuItem(
                                        value: st,
                                        child: Text(st, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600)),
                                      ))
                                  .toList(),
                              onChanged: (newStatus) async {
                                if (newStatus != null && SupabaseService.instance.client != null) {
                                  try {
                                    await SupabaseService.instance.client!
                                        .from('nurse_orders')
                                        .update({'status': newStatus})
                                        .eq('id', orderId);

                                    // If completed or cancelled, automatically free up the nurse back to available
                                    if (newStatus == 'Completed' || newStatus == 'Cancelled') {
                                      final assignedNurseId = (o['nurse_id'] ?? '').toString();
                                      final assignedNurseName = (o['nurse_name'] ?? '').toString();
                                      if (assignedNurseId.isNotEmpty) {
                                        await SupabaseService.instance.client!
                                            .from('nurses')
                                            .update({'is_available': true, 'status': 'available'})
                                            .eq('id', assignedNurseId);
                                      } else if (assignedNurseName.isNotEmpty) {
                                        await SupabaseService.instance.client!
                                            .from('nurses')
                                            .update({'is_available': true, 'status': 'available'})
                                            .eq('name', assignedNurseName);
                                      }
                                    }

                                    // Trigger FCM push notification to specific customer device
                                     final custPhone = (o['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
                                     final custId = (o['patient_id'] ?? o['customer_id'] ?? '').toString();
                                     final custTopic = custId.isNotEmpty ? 'user_$custId' : (custPhone.isNotEmpty ? 'user_$custPhone' : null);

                                     if (custTopic != null) {
                                       FcmSender().sendTopicNotification(
                                         topic: custTopic,
                                         title: 'Nasiib Home Care Update',
                                         body: 'Status-ka dalabkaaga kalkaaliso wuxuu noqday: $newStatus',
                                       );
                                     }
                                  } catch (e) {
                                    debugPrint('Error updating nurse order status: $e');
                                  }
                                }
                              },
                            ),
                          ),
                          DataCell(
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              onPressed: () async {
                                if (SupabaseService.instance.client != null) {
                                  await SupabaseService.instance.client!
                                      .from('nurse_orders')
                                      .delete()
                                      .eq('id', orderId);
                                }
                              },
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddNurseDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final specCtrl = TextEditingController();
    final feeCtrl = TextEditingController(text: '20.0');
    final discountFeeCtrl = TextEditingController(text: '');

    Uint8List? rawPickedNurseBytes;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                'Add New Nurse',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      _buildStyledField(
                        controller: nameCtrl,
                        label: 'Nurse Name (e.g. Deqa Hassan)',
                      ),
                      _buildStyledField(
                        controller: specCtrl,
                        label: 'Specialty / Role (e.g. Kalkaaliso)',
                      ),
                      _buildStyledField(
                        controller: feeCtrl,
                        label: 'Regular Visit Fee (\$)',
                        hintText: 'e.g. 20.00',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      _buildStyledField(
                        controller: discountFeeCtrl,
                        label: 'Discount Fee (\$) (Optional)',
                        hintText: 'e.g. 15.00 (leave empty if no discount)',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Profile Photo (Upload to Storage)',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Column(
                        children: [
                          if (rawPickedNurseBytes != null)
                            Center(
                              child: Container(
                                width: 90,
                                height: 90,
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.primaryColor,
                                    width: 2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(45),
                                  child: Image.memory(
                                    rawPickedNurseBytes!,
                                    height: 90,
                                    width: 90,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.topCenter,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 6),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      final bytes =
                                          await ImagePickerService.pickImageBytes();
                                      if (bytes != null && bytes.isNotEmpty) {
                                        setState(() {
                                          rawPickedNurseBytes = bytes;
                                        });
                                      }
                                    },

                              icon: Icon(
                                rawPickedNurseBytes != null
                                    ? Icons.refresh_rounded
                                    : Icons.add_a_photo_rounded,
                                color: Colors.white,
                              ),
                              label: Text(
                                rawPickedNurseBytes != null
                                    ? 'Sawirka Badel'
                                    : 'Sawirka Profile Soo Dooro',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (nameCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter nurse name'),
                              ),
                            );
                            return;
                          }

                          setState(() {
                            isSaving = true;
                          });

                          final feeVal =
                              double.tryParse(feeCtrl.text.trim()) ?? 0.0;
                          final discountVal = double.tryParse(
                            discountFeeCtrl.text.trim(),
                          );

                          final nurseModel = NurseModel(
                            id: 'nurse_${DateTime.now().millisecondsSinceEpoch}',
                            name: nameCtrl.text.trim(),
                            specialty: specCtrl.text.trim().isNotEmpty
                                ? specCtrl.text.trim()
                                : 'Kalkaaliso',
                            imageUrl: '',
                            fee: feeVal,
                            discountFee: discountVal,
                          );

                          final appState = context.read<AppState>();
                          final success = await appState.addNurse(
                            nurseModel,
                            imageBytes: rawPickedNurseBytes,
                          );

                          if (context.mounted) {
                            if (success) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Nurse saved to Supabase DB successfully!',
                                  ),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            } else {
                              setState(() {
                                isSaving = false;
                              });
                              final String errDetail =
                                  (appState.lastNurseError != null &&
                                      appState.lastNurseError!.isNotEmpty)
                                  ? appState.lastNurseError!
                                  : 'Check database permissions / RLS.';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Failed to save nurse to Supabase DB: $errDetail',
                                  ),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 6),
                                ),
                              );
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Save Nurse',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditNurseDialog(BuildContext context, NurseModel nurse) {
    final appState = context.read<AppState>();
    final nameCtrl = TextEditingController(text: nurse.name);
    final specCtrl = TextEditingController(text: nurse.specialty);
    final feeCtrl = TextEditingController(
      text: nurse.fee > 0 ? nurse.fee.toString() : '20.0',
    );
    final discountFeeCtrl = TextEditingController(
      text: nurse.discountFee != null ? nurse.discountFee.toString() : '',
    );

    Uint8List? editNurseImageBytes;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                'Edit Nurse Information',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      _buildStyledField(
                        controller: nameCtrl,
                        label: 'Nurse Name',
                      ),
                      _buildStyledField(
                        controller: specCtrl,
                        label: 'Specialty / Role',
                      ),
                      _buildStyledField(
                        controller: feeCtrl,
                        label: 'Regular Visit Fee (\$)',
                        hintText: 'e.g. 20.00',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      _buildStyledField(
                        controller: discountFeeCtrl,
                        label: 'Discount Fee (\$) (Optional)',
                        hintText: 'e.g. 15.00 (leave empty if no discount)',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Column(
                        children: [
                          if (editNurseImageBytes != null)
                            Center(
                              child: Container(
                                width: 90,
                                height: 90,
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.primaryColor,
                                    width: 2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(45),
                                  child: Image.memory(
                                    editNurseImageBytes!,
                                    height: 90,
                                    width: 90,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.topCenter,
                                  ),
                                ),
                              ),
                            )
                          else if (nurse.imageUrl.isNotEmpty)
                            Center(
                              child: Container(
                                width: 90,
                                height: 90,
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.primaryColor,
                                    width: 2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(45),
                                  child: NetworkOrAssetImage(
                                    imageUrl: nurse.imageUrl,
                                    height: 90,
                                    width: 90,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.topCenter,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      final bytes =
                                          await ImagePickerService.pickImageBytes();
                                      if (bytes != null && bytes.isNotEmpty) {
                                        setState(() {
                                          editNurseImageBytes = bytes;
                                        });
                                      }
                                    },
                              icon: const Icon(
                                Icons.add_a_photo_rounded,
                                color: Colors.white,
                              ),
                              label: Text(
                                (editNurseImageBytes != null ||
                                        nurse.imageUrl.isNotEmpty)
                                    ? 'Sawirka Badel'
                                    : 'Sawirka Profile Soo Dooro',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setState(() {
                            isSaving = true;
                          });

                          final feeVal =
                              double.tryParse(feeCtrl.text.trim()) ?? nurse.fee;
                          final discountVal = double.tryParse(
                            discountFeeCtrl.text.trim(),
                          );

                          final updatedNurse = NurseModel(
                            id: nurse.id,
                            name: nameCtrl.text.trim().isNotEmpty
                                ? nameCtrl.text.trim()
                                : nurse.name,
                            specialty: specCtrl.text.trim().isNotEmpty
                                ? specCtrl.text.trim()
                                : nurse.specialty,
                            imageUrl: nurse.imageUrl,
                            fee: feeVal,
                            discountFee: discountVal,
                          );

                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Nurse information updated!'),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 2),
                            ),
                          );

                          appState.updateNurse(
                            updatedNurse,
                            newImageBytes: editNurseImageBytes,
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Save Changes',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditDoctorDialog(BuildContext context, DoctorModel doc) {
    final appState = context.read<AppState>();
    final nameCtrl = TextEditingController(text: doc.name);
    final specCtrl = TextEditingController(text: doc.specialty);
    final expCtrl = TextEditingController(text: doc.experience);
    final patCtrl = TextEditingController(text: doc.patientsCount);
    final feeCtrl = TextEditingController(
      text: doc.consultationFee > 0 ? doc.consultationFee.toString() : '15.0',
    );
    final discountFeeCtrl = TextEditingController(
      text: doc.discountFee != null ? doc.discountFee.toString() : '',
    );
    final aboutCtrl = TextEditingController(text: doc.about);

    String selectedStartHours = '08:00 AM';
    String selectedEndHours = '06:00 PM';
    if (doc.workingHours.contains('-')) {
      final parts = doc.workingHours.split('-');
      if (parts.length == 2) {
        selectedStartHours = parts[0].trim();
        selectedEndHours = parts[1].trim();
      }
    }

    Uint8List? editImageBytes;
    bool isVerified = doc.isVerified;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                'Edit Doctor Information',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      _buildStyledField(
                        controller: nameCtrl,
                        label: 'Doctor Name',
                      ),
                      _buildStyledField(
                        controller: specCtrl,
                        label: 'Specialty',
                      ),
                      _buildStyledField(
                        controller: expCtrl,
                        label: 'Experience',
                      ),
                      _buildStyledField(
                        controller: patCtrl,
                        label: 'Patients Count',
                      ),
                      _buildStyledField(
                        controller: feeCtrl,
                        label: 'Regular Consultation Fee (\$)',
                        hintText: 'e.g. 15.00',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      _buildStyledField(
                        controller: discountFeeCtrl,
                        label: 'Discount Fee (\$) (Optional)',
                        hintText: 'e.g. 10.00 (leave empty if no discount)',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      _buildWorkingHoursPicker(
                        selectedStart: selectedStartHours,
                        selectedEnd: selectedEndHours,
                        onStartChanged: (v) {
                          if (v != null) setState(() => selectedStartHours = v);
                        },
                        onEndChanged: (v) {
                          if (v != null) setState(() => selectedEndHours = v);
                        },
                      ),
                      _buildStyledField(
                        controller: aboutCtrl,
                        label: 'About Doctor / Bio',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 6),
                      Column(
                        children: [
                          Center(
                            child: Container(
                              width: 90,
                              height: 90,
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.primaryColor,
                                  width: 2,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(45),
                                child: editImageBytes != null
                                    ? Image.memory(
                                        editImageBytes!,
                                        height: 90,
                                        width: 90,
                                        fit: BoxFit.cover,
                                      )
                                    : NetworkOrAssetImage(
                                        imageUrl: doc.imageUrl,
                                        height: 90,
                                        width: 90,
                                        fit: BoxFit.cover,
                                        alignment: Alignment.topCenter,
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      final bytes =
                                          await ImagePickerService.pickImageBytes();
                                      if (bytes != null && bytes.isNotEmpty) {
                                        setState(() {
                                          editImageBytes = bytes;
                                        });
                                      }
                                    },

                              icon: const Icon(
                                Icons.add_a_photo_rounded,
                                color: Colors.white,
                              ),
                              label: Text(
                                (editImageBytes != null ||
                                        doc.imageUrl.isNotEmpty)
                                    ? 'Sawirka Badel'
                                    : 'Sawirka Profile Soo Dooro',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: isVerified,
                        title: Text(
                          'Verified Doctor Badge (Calaamadda Verified-ka)',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        activeColor: AppTheme.primaryColor,
                        onChanged: isSaving
                            ? null
                            : (val) {
                                if (val != null) {
                                  setState(() => isVerified = val);
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setState(() {
                            isSaving = true;
                          });
                          final feeVal =
                              double.tryParse(feeCtrl.text.trim()) ??
                              doc.consultationFee;
                          final discountVal = double.tryParse(
                            discountFeeCtrl.text.trim(),
                          );

                          final updatedDoc = doc.copyWith(
                            name: nameCtrl.text.trim().isNotEmpty
                                ? nameCtrl.text.trim()
                                : doc.name,
                            specialty: specCtrl.text.trim().isNotEmpty
                                ? specCtrl.text.trim()
                                : doc.specialty,
                            experience: expCtrl.text.trim().isNotEmpty
                                ? expCtrl.text.trim()
                                : doc.experience,
                            patientsCount: patCtrl.text.trim().isNotEmpty
                                ? patCtrl.text.trim()
                                : doc.patientsCount,
                            workingHours:
                                '$selectedStartHours - $selectedEndHours',
                            about: aboutCtrl.text.trim(),
                            consultationFee: feeVal,
                            discountFee: discountVal,
                            isVerified: isVerified,
                          );

                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Doctor details updated!'),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 2),
                            ),
                          );

                          appState.updateDoctor(
                            updatedDoc,
                            newImageBytes: editImageBytes,
                          );
                        },

                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Save Changes',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWorkingHoursPicker({
    required String selectedStart,
    required String selectedEnd,
    required ValueChanged<String?> onStartChanged,
    required ValueChanged<String?> onEndChanged,
  }) {
    final List<String> startOptions = [
      '06:00 AM',
      '06:30 AM',
      '07:00 AM',
      '07:30 AM',
      '08:00 AM',
      '08:30 AM',
      '09:00 AM',
      '09:30 AM',
      '10:00 AM',
      '10:30 AM',
      '11:00 AM',
      '11:30 AM',
      '12:00 PM',
      '01:00 PM',
      '02:00 PM',
      '03:00 PM',
      '04:00 PM',
      '05:00 PM',
      '06:00 PM',
      '07:00 PM',
      '08:00 PM',
      '24/7 Open',
    ];

    final List<String> endOptions = [
      '12:00 PM',
      '01:00 PM',
      '02:00 PM',
      '03:00 PM',
      '04:00 PM',
      '05:00 PM',
      '06:00 PM',
      '07:00 PM',
      '07:30 PM',
      '08:00 PM',
      '08:30 PM',
      '09:00 PM',
      '09:30 PM',
      '10:00 PM',
      '10:30 PM',
      '11:00 PM',
      '11:30 PM',
      '12:00 AM',
      '06:00 AM',
      '24/7 Open',
    ];

    final String validStart = startOptions.contains(selectedStart)
        ? selectedStart
        : '08:00 AM';
    final String validEnd = endOptions.contains(selectedEnd)
        ? selectedEnd
        : '10:00 PM';

    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: validStart,
              decoration: InputDecoration(
                hintText: 'Bilaabashada (Start)',
                labelText: 'Saacadda Bilaabashada',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
                labelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryColor,
                    width: 2,
                  ),
                ),
              ),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
              items: startOptions.map((opt) {
                return DropdownMenuItem<String>(value: opt, child: Text(opt));
              }).toList(),
              onChanged: onStartChanged,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: validEnd,
              decoration: InputDecoration(
                hintText: 'Dhameystirka (End)',
                labelText: 'Saacadda Dhameystirka',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
                labelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryColor,
                    width: 2,
                  ),
                ),
              ),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
              items: endOptions.map((opt) {
                return DropdownMenuItem<String>(value: opt, child: Text(opt));
              }).toList(),
              onChanged: onEndChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyledField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: TextField(
        controller: controller,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: AppTheme.textPrimary,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          hintStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: Colors.grey.shade400,
          ),
          isDense: false,
          labelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppTheme.primaryColor,
              width: 1.5,
            ),
          ),
          filled: true,
          fillColor: const Color(0xFFFAFBFC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
        ),
      ),
    );
  }

  void _showAddDoctorDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final specCtrl = TextEditingController();
    final expCtrl = TextEditingController();
    final patCtrl = TextEditingController();
    final feeCtrl = TextEditingController(text: '15.0');
    final discountFeeCtrl = TextEditingController(text: '');
    final aboutCtrl = TextEditingController();
    String selectedStartHours = '08:00 AM';
    String selectedEndHours = '10:00 PM';
    bool isVerified = false;

    Uint8List? rawPickedImageBytes;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                'Add New Doctor',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      _buildStyledField(
                        controller: nameCtrl,
                        label: 'Doctor Name',
                        hintText: 'e.g. Dr. Mohamed Ali',
                      ),
                      _buildStyledField(
                        controller: specCtrl,
                        label: 'Specialty',
                        hintText: 'e.g. Dermatologist',
                      ),
                      _buildStyledField(
                        controller: expCtrl,
                        label: 'Experience',
                        hintText: 'e.g. 5+ Years',
                      ),
                      _buildStyledField(
                        controller: patCtrl,
                        label: 'Patients Count',
                        hintText: 'e.g. 670',
                      ),
                      _buildStyledField(
                        controller: feeCtrl,
                        label: 'Regular Consultation Fee (\$)',
                        hintText: 'e.g. 15.00',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      _buildStyledField(
                        controller: discountFeeCtrl,
                        label: 'Discount Fee (\$) (Optional)',
                        hintText: 'e.g. 10.00 (leave empty if no discount)',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      _buildWorkingHoursPicker(
                        selectedStart: selectedStartHours,
                        selectedEnd: selectedEndHours,
                        onStartChanged: (v) {
                          if (v != null) setState(() => selectedStartHours = v);
                        },
                        onEndChanged: (v) {
                          if (v != null) setState(() => selectedEndHours = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildStyledField(
                        controller: aboutCtrl,
                        label: 'About Doctor / Bio',
                        hintText:
                            'e.g. Experienced dermatologist specializing in skin care.',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Profile Photo (Upload)',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: InkWell(
                          onTap: isSaving
                              ? null
                              : () async {
                                  final bytes =
                                      await ImagePickerService.pickImageBytes();
                                  if (bytes != null && bytes.isNotEmpty) {
                                    setState(() {
                                      rawPickedImageBytes = bytes;
                                    });
                                  }
                                },
                          child: CircleAvatar(
                            radius: 45,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: rawPickedImageBytes != null
                                ? MemoryImage(rawPickedImageBytes!)
                                : null,
                            child: rawPickedImageBytes == null
                                ? const Icon(
                                    Icons.camera_alt,
                                    size: 32,
                                    color: AppTheme.primaryColor,
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        value: isVerified,
                        title: Text(
                          'Verified Doctor Badge (Calaamadda Verified-ka)',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        activeColor: AppTheme.primaryColor,
                        onChanged: (val) {
                          setState(() {
                            isVerified = val ?? false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () async {
                    final appState = context.read<AppState>();
                    final nameVal = nameCtrl.text.trim();
                    final specVal = specCtrl.text.trim();
                    if (nameVal.isEmpty || specVal.isEmpty) return;

                    final docId =
                        (DateTime.now().millisecondsSinceEpoch % 2147483647)
                            .toString();
                    final expVal = expCtrl.text.trim();
                    final patVal = patCtrl.text.trim();
                    final aboutVal = aboutCtrl.text.trim();
                    final feeVal = double.tryParse(feeCtrl.text.trim()) ?? 0.0;
                    final discountVal = double.tryParse(
                      discountFeeCtrl.text.trim(),
                    );

                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) =>
                          const Center(child: CircularProgressIndicator()),
                    );

                    try {
                      final success = await appState.addDoctor(
                        DoctorModel(
                          id: docId,
                          name: DoctorModel.sanitizeDoctorName(nameVal),
                          specialty: specVal,
                          hospital: 'Nasiib Hospital',
                          rating: 0.0,
                          reviewsCount: 0,
                          experience: expVal.isNotEmpty ? expVal : '0 Years',
                          patientsCount: patVal.isNotEmpty ? patVal : '0+',
                          workingHours:
                              '$selectedStartHours - $selectedEndHours',
                          about: aboutVal.isNotEmpty
                              ? aboutVal
                              : 'Dedicated doctor providing expert medical care.',
                          consultationFee: feeVal,
                          discountFee: discountVal,
                          imageUrl: '',
                          isVerified: isVerified,
                        ),
                        imageBytes: rawPickedImageBytes,
                      );

                      if (context.mounted)
                        Navigator.pop(context); // Dismiss loading

                      if (success && context.mounted) {
                        Navigator.pop(context); // Dismiss Add Doctor Form
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Doctor added successfully to Supabase DB!',
                            ),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (err) {
                      if (context.mounted)
                        Navigator.pop(context); // Dismiss loading
                      debugPrint(
                        "[DOCTOR_SAVE_ERROR] Supabase DB Insert failed: $err",
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Failed to insert doctor into Supabase DB: $err',
                            ),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      }
                    }
                  },
                  child: Text(
                    'Save Doctor',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddPatientDialog(BuildContext context) {
    final appState = context.read<AppState>();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ageCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    String gender = 'Female';
    DoctorModel? selectedDoctor = appState.doctors.isNotEmpty
        ? appState.doctors.first
        : null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                'Add New Patient & Booking',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      _buildStyledField(
                        controller: nameCtrl,
                        label: 'Patient Name (e.g. Halima Farah)',
                      ),
                      _buildStyledField(
                        controller: phoneCtrl,
                        label: 'Phone Number (e.g. +252 615 123456)',
                      ),
                      _buildStyledField(
                        controller: ageCtrl,
                        label: 'Age (e.g. 30)',
                        keyboardType: TextInputType.number,
                      ),

                      // Gender Selection Row
                      Row(
                        children: [
                          Text(
                            'Gender:  ',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          Radio<String>(
                            value: 'Female',
                            groupValue: gender,
                            activeColor: AppTheme.primaryColor,
                            onChanged: (val) =>
                                setDialogState(() => gender = val!),
                          ),
                          Text(
                            'Female',
                            style: GoogleFonts.plusJakartaSans(fontSize: 14),
                          ),
                          const SizedBox(width: 12),
                          Radio<String>(
                            value: 'Male',
                            groupValue: gender,
                            activeColor: AppTheme.primaryColor,
                            onChanged: (val) =>
                                setDialogState(() => gender = val!),
                          ),
                          Text(
                            'Male',
                            style: GoogleFonts.plusJakartaSans(fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Assigned Doctor Dropdown
                      if (appState.doctors.isNotEmpty) ...[
                        Row(
                          children: [
                            Text(
                              'Assign Doctor:  ',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFCBD5E1),
                                  ),
                                  color: const Color(0xFFFAFBFC),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<DoctorModel>(
                                    value: selectedDoctor,
                                    isExpanded: true,
                                    onChanged: (doc) => setDialogState(
                                      () => selectedDoctor = doc,
                                    ),
                                    items: appState.doctors.map((doc) {
                                      return DropdownMenuItem<DoctorModel>(
                                        value: doc,
                                        child: Text(
                                          doc.name,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 14,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      _buildStyledField(
                        controller: reasonCtrl,
                        label: 'Reason for Visit / Diagnosis',
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () {
                    if (nameCtrl.text.isNotEmpty &&
                        phoneCtrl.text.isNotEmpty &&
                        selectedDoctor != null) {
                      final age = int.tryParse(ageCtrl.text) ?? 30;

                      appState.addAppointment(
                        AppointmentModel(
                          id: 'apt_${DateTime.now().millisecondsSinceEpoch}',
                          referenceId:
                              '#APT${(10000 + DateTime.now().millisecond * 10).toString()}',
                          doctorId: selectedDoctor!.id,
                          doctorName: selectedDoctor!.name,
                          doctorSpecialty: selectedDoctor!.specialty,
                          doctorImageUrl: selectedDoctor!.imageUrl,
                          date:
                              '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                          time:
                              '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')} ${DateTime.now().hour >= 12 ? 'PM' : 'AM'}',
                          appointmentType: 'New Patient',
                          patientName: nameCtrl.text,
                          patientPhone: phoneCtrl.text,
                          patientAge: age,
                          patientGender: gender,
                          reasonForVisit: reasonCtrl.text.isNotEmpty
                              ? reasonCtrl.text
                              : 'Routine Checkup',
                          paymentMethod: 'Cash',
                          amount: selectedDoctor!.consultationFee,
                          queueNumber: appState.appointments.length + 1,
                          status: 'Confirmed',
                          createdAt: DateTime.now().toIso8601String(),
                        ),
                      );

                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Patient & Booking added successfully!',
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(
                    'Save Patient',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // TAB 2: PATIENTS & PRESCRIPTIONS TABLE (Sidebar detail)
  // ==========================================
  Widget _buildPatientsTab(BuildContext context) {
    final appState = context.watch<AppState>();
    final bookings =
        appState.appointments; // Patient lists derived from bookings
    final filteredBookings = bookings.where((b) {
      if (_patientSearchQuery.isEmpty) return true;
      final cleanQuery = _patientSearchQuery.toLowerCase().trim();
      final cleanId = b.id.toLowerCase();
      final cleanName = b.patientName.toLowerCase();
      final formattedPatientId = 'nh-${cleanId.replaceAll('usr_', '')}';
      return cleanId.contains(cleanQuery) ||
          cleanName.contains(cleanQuery) ||
          formattedPatientId.contains(cleanQuery);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Patient List',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Manage patient medical histories, checkups, and doctor recommendations.',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: () => _showAddPatientDialog(context),
              icon: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 18,
              ),
              label: Text(
                'Add Patient',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // SEARCH PATIENT BY ID BAR
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.search_rounded,
                color: AppTheme.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  onChanged: (val) {
                    setState(() {
                      _patientSearchQuery = val;
                    });
                  },
                  decoration: const InputDecoration(
                    hintText:
                        'Ku raadi Magaca Bukaanka (Search by Patient Name)...',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              if (_patientSearchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(
                    Icons.clear_rounded,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () {
                    setState(() {
                      _patientSearchQuery = '';
                    });
                  },
                ),
            ],
          ),
        ),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Patients Table/Cards List
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  // Table Header Row
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: const BoxDecoration(color: Colors.transparent),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 40,
                          child: Icon(
                            Icons.check_box_outline_blank,
                            color: Colors.transparent,
                            size: 20,
                          ),
                        ), // Spacer for Checkbox
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Patient Name',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Appointment ID',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Date',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Time',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Treatment',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(
                            'Doctor',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Center(
                            child: Text(
                              'Status',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 40,
                          child: Icon(
                            Icons.delete_outline_rounded,
                            color: AppTheme.textSecondary,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Table Body Rows
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredBookings.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final apt = filteredBookings[index];
                      final isSelected =
                          _selectedPatientForDetail?.id == apt.id;

                      // Find doctor profile image from appState
                      final matchingDoc = appState.doctors.firstWhere(
                        (d) =>
                            d.name.toLowerCase().contains(
                              apt.doctorName.toLowerCase(),
                            ) ||
                            apt.doctorName.toLowerCase().contains(
                              d.name.toLowerCase(),
                            ),
                        orElse: () => DoctorModel(
                          id: '',
                          name: apt.doctorName,
                          specialty: apt.doctorSpecialty,
                          hospital: 'Nasiib Hospital',
                          rating: 4.8,
                          reviewsCount: 1,
                          experience: '',
                          patientsCount: '',
                          workingHours: '',
                          about: '',
                          imageUrl: '',

                          consultationFee: 10,
                        ),
                      );

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedPatientForDetail = apt;
                            _prescriptionController.text =
                                apt.prescription ?? '';
                            _diagnosisController.text =
                                apt.reasonForVisit.isNotEmpty
                                ? apt.reasonForVisit
                                : 'Toothache';
                            _weightController.text = '70 kg';
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFEDF2F7)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryColor
                                  : const Color(0xFFF1F5F9),
                              width: isSelected ? 1.5 : 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.01),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // Checkbox
                              SizedBox(
                                width: 40,
                                child: Icon(
                                  Icons.check_box_outline_blank,
                                  color: Colors.grey[300],
                                  size: 20,
                                ),
                              ),
                              // Patient Name
                              Expanded(
                                flex: 3,
                                child: Text(
                                  apt.patientName,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              // Appointment ID
                              Expanded(
                                flex: 3,
                                child: Text(
                                  apt.referenceId,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              // Date
                              Expanded(
                                flex: 2,
                                child: Text(
                                  apt.date,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              // Time
                              Expanded(
                                flex: 2,
                                child: Text(
                                  apt.time,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              // Treatment
                              Expanded(
                                flex: 3,
                                child: Text(
                                  apt.doctorSpecialty,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppTheme.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              // Doctor with mini image
                              Expanded(
                                flex: 4,
                                child: Row(
                                  children: [
                                    NetworkOrAssetImage(
                                      imageUrl: matchingDoc.imageUrl,
                                      width: 24,
                                      height: 24,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        apt.doctorName,
                                        style: GoogleFonts.plusJakartaSans(
                                          color: AppTheme.textPrimary,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Status pill
                              Expanded(
                                flex: 3,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: apt.status == 'Confirmed'
                                          ? const Color(0xFFE6FFFA)
                                          : apt.status == 'Cancelled'
                                          ? const Color(0xFFFFEEEE)
                                          : const Color(0xFFFFF3CD),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      apt.status,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: apt.status == 'Confirmed'
                                            ? const Color(0xFF00796B)
                                            : apt.status == 'Cancelled'
                                            ? const Color(0xFFD32F2F)
                                            : const Color(0xFF856404),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Action dots menu
                              SizedBox(
                                width: 40,
                                child: PopupMenuButton<String>(
                                  icon: Icon(
                                    Icons.more_horiz_rounded,
                                    color: Colors.grey[600],
                                    size: 20,
                                  ),
                                  onSelected: (val) {
                                    if (val == 'cancel') {
                                      appState.updateAppointmentStatus(
                                        apt.id,
                                        'Cancelled',
                                      );
                                    } else if (val == 'confirm') {
                                      appState.updateAppointmentStatus(
                                        apt.id,
                                        'Confirmed',
                                      );
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'confirm',
                                      child: Text('Confirm Booking'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'cancel',
                                      child: Text('Cancel Booking'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Patient detail drawer / sidebar (if selected)
            if (_selectedPatientForDetail != null) ...[
              const SizedBox(width: 20),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.medical_services_rounded,
                                  color: AppTheme.primaryColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Patient Portal',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(
                                () => _selectedPatientForDetail = null,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 16),
                        const SizedBox(height: 10),

                        // Patient Header Details Visual Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF0F9FF), Color(0xFFE0F2FE)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFBAE6FD)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: Colors.white,
                                child: Text(
                                  _selectedPatientForDetail!
                                          .patientName
                                          .isNotEmpty
                                      ? _selectedPatientForDetail!
                                            .patientName[0]
                                            .toUpperCase()
                                      : 'P',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedPatientForDetail!.patientName,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'ID: NH-${_selectedPatientForDetail!.id.replaceAll('usr_', '').toUpperCase()}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFFE65100),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Phone: ${_selectedPatientForDetail!.patientPhone}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Bio Stats Capsule Cards
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'Gender',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _selectedPatientForDetail!.patientGender,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'Age',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_selectedPatientForDetail!.patientAge} yrs',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Consultation timeline card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline_rounded,
                                    color: Color(0xFFD97706),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Consultation History',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFFD97706),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Last meeting scheduled with Dr. ${_selectedPatientForDetail!.doctorName} on ${_selectedPatientForDetail!.date} at ${_selectedPatientForDetail!.time}. Status: ${_selectedPatientForDetail!.status}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: const Color(0xFF92400E),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Input 1: Diagnosis
                        Text(
                          'Diagnosis / Cudurka la ogaaday',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _diagnosisController,
                          style: GoogleFonts.plusJakartaSans(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'e.g., Tooth inflammation / Gum Pain',
                            fillColor: const Color(0xFFF8FAFC),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Input 2: Patient Weight
                        Text(
                          'Patient Weight / Miisaanka',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _weightController,
                          style: GoogleFonts.plusJakartaSans(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'e.g., 72 kg',
                            fillColor: const Color(0xFFF8FAFC),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Input 3: Prescription
                        Text(
                          'Medicines & Dosage / Dawooyinka & Sida loo qaadanayo',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _prescriptionController,
                          maxLines: 5,
                          style: GoogleFonts.plusJakartaSans(fontSize: 13),
                          decoration: InputDecoration(
                            hintText:
                                'e.g.,\n1. Paracetamol 500mg - 3 times daily (3 maalmood)\n2. Amoxicillin Capsule - 2 times daily after meals',
                            fillColor: const Color(0xFFF8FAFC),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Save & Print Action Buttons Row
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 44,
                                child: ElevatedButton(
                                  onPressed: () {
                                    context
                                        .read<AppState>()
                                        .addOrUpdatePrescription(
                                          _selectedPatientForDetail!.id,
                                          _prescriptionController.text,
                                        );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Prescription saved successfully!',
                                        ),
                                      ),
                                    );
                                    setState(() {
                                      _selectedPatientForDetail = context
                                          .read<AppState>()
                                          .appointments
                                          .firstWhere(
                                            (a) =>
                                                a.id ==
                                                _selectedPatientForDetail!.id,
                                          );
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Save Data',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SizedBox(
                                height: 44,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    _showPrescriptionPreviewDialog(
                                      context,
                                      _selectedPatientForDetail!,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.print_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Print (Rx)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0369A1),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ==========================================
  // TAB 3: APPOINTMENTS MANAGEMENT
  // ==========================================
  Widget _buildAppointmentsTab(BuildContext context) {
    final appState = context.watch<AppState>();
    final appointments = appState.appointments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Patient Appointments',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Approve or update booking queues.',
          style: GoogleFonts.plusJakartaSans(
            color: AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 20),

        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: appointments.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final apt = appointments[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Patient: ${apt.patientName} (${apt.patientPhone})',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Doctor: ${apt.doctorName} • ${apt.date} ${apt.time}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          'Queue #: ${apt.queueNumber} • Ref: ${apt.referenceId}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (status) {
                      appState.updateAppointmentStatus(apt.id, status);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'Confirmed',
                        child: Text('Confirm / Approve'),
                      ),
                      const PopupMenuItem(
                        value: 'Completed',
                        child: Text('Mark Completed'),
                      ),
                      const PopupMenuItem(
                        value: 'Cancelled',
                        child: Text('Cancel Appointment'),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Text(
                            apt.status,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            color: AppTheme.primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFEF4444),
                      size: 20,
                    ),
                    tooltip: 'Tirtir Ballanta',
                    onPressed: () {
                      _confirmDeleteAppointmentDialog(
                        context,
                        appState,
                        apt.id,
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ==========================================
  // TAB 4: PHARMACY & DISCOUNTS STOCK CATALOG
  // ==========================================
  Widget _buildPharmacyTab(BuildContext context) {
    final appState = context.watch<AppState>();
    final medicines = appState.medicines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pharmacy Catalog Management',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Manage catalog items, active prices, and discount strike-through prices.',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: () => _showAddMedicineDialog(context),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Medicine',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: medicines.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final med = medicines[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  NetworkOrAssetImage(
                    imageUrl: med.imageUrl,
                    width: 54,
                    height: 54,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(12),
                  ),

                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          med.title,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              'Price: \$${med.price.toStringAsFixed(2)}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            if (med.originalPrice != null &&
                                med.originalPrice! > 0 &&
                                med.originalPrice! > med.price) ...[
                              const SizedBox(width: 8),
                              Text(
                                '\$${med.originalPrice!.toStringAsFixed(2)}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  decoration: TextDecoration.lineThrough,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '(Discount Active)',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          'SKU: ${med.sku} • Category: ${med.category}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.edit_note_rounded,
                      color: AppTheme.primaryColor,
                    ),
                    tooltip: 'Edit Medicine Details',
                    onPressed: () => _showEditMedicineDialog(context, med),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppTheme.errorRed,
                    ),
                    onPressed: () {
                      appState.deleteMedicine(med.id);
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  void _showEditMedicineDialog(BuildContext context, MedicineModel med) {
    final titleCtrl = TextEditingController(text: med.title);
    final categoryCtrl = TextEditingController(text: med.category);
    final skuCtrl = TextEditingController(text: med.sku);
    final priceCtrl = TextEditingController(text: med.price.toString());
    final originalPriceCtrl = TextEditingController(
      text: med.originalPrice?.toString() ?? '',
    );
    final imgCtrl = TextEditingController(text: med.imageUrl);
    final descCtrl = TextEditingController(text: med.description);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Edit Medicine Details',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  _buildStyledField(
                    controller: titleCtrl,
                    label: 'Medicine Title (e.g. Paracetamol 500mg)',
                  ),
                  _buildStyledField(
                    controller: categoryCtrl,
                    label: 'Category (e.g. Tablets, Syrup)',
                  ),
                  _buildStyledField(
                    controller: skuCtrl,
                    label: 'Item Code (SKU)',
                  ),
                  _buildStyledField(
                    controller: priceCtrl,
                    label: 'Qiimaha Dawada / Selling Price (\$) (e.g. 2.99)',
                    keyboardType: TextInputType.number,
                  ),
                  _buildStyledField(
                    controller: originalPriceCtrl,
                    label:
                        'Qiima Dhimis Hore / Original Price (Optional - for discount strike-through e.g. 3.50)',
                    keyboardType: TextInputType.number,
                  ),
                  _buildStyledField(
                    controller: imgCtrl,
                    label: 'Medicine Image URL',
                  ),
                  _buildStyledField(
                    controller: descCtrl,
                    label: 'Description',
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              onPressed: () async {
                final val1 = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                final val2 = double.tryParse(originalPriceCtrl.text.trim());

                double finalPrice = med.price;
                double? finalOriginalPrice;

                if (val1 > 0 && val2 != null && val2 > 0) {
                  // Two prices provided: lower price is selling price ($3.99), higher price is original price ($5.00)
                  if (val1 < val2) {
                    finalPrice = val1;
                    finalOriginalPrice = val2;
                  } else if (val2 < val1) {
                    finalPrice = val2;
                    finalOriginalPrice = val1;
                  } else {
                    finalPrice = val1;
                    finalOriginalPrice = null;
                  }
                } else if (val1 > 0) {
                  finalPrice = val1;
                  finalOriginalPrice = null;
                } else if (val1 == 0 && val2 != null && val2 > 0) {
                  finalPrice = val2;
                  finalOriginalPrice = null;
                }

                final updatedMed = med.copyWith(
                  title: titleCtrl.text,
                  category: categoryCtrl.text,
                  sku: skuCtrl.text,
                  price: finalPrice,
                  originalPrice: finalOriginalPrice,
                  clearOriginalPrice: finalOriginalPrice == null,
                  imageUrl: imgCtrl.text,
                  description: descCtrl.text,
                );

                await context.read<AppState>().updateMedicine(updatedMed);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Medicine details updated successfully!'),
                    ),
                  );
                }
              },
              child: Text(
                'Save Changes',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAddMedicineDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final skuCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final originalPriceCtrl = TextEditingController();
    final imgCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? medicineImageBase64;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                'Add New Medicine',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      _buildStyledField(
                        controller: titleCtrl,
                        label: 'Medicine Title (e.g. Paracetamol 500mg)',
                      ),
                      _buildStyledField(
                        controller: categoryCtrl,
                        label: 'Category (e.g. Tablets, Syrup)',
                      ),
                      _buildStyledField(
                        controller: skuCtrl,
                        label: 'Item Code (SKU) (e.g. HP1707)',
                      ),
                      _buildStyledField(
                        controller: priceCtrl,
                        label:
                            'Qiimaha Dawada / Selling Price (\$) (e.g. 2.99)',
                        keyboardType: TextInputType.number,
                      ),
                      _buildStyledField(
                        controller: originalPriceCtrl,
                        label:
                            'Qiima Dhimis Hore / Original Price (Optional - for discount strike-through e.g. 3.50)',
                        keyboardType: TextInputType.number,
                      ),
                      _buildStyledField(
                        controller: descCtrl,
                        label: 'Description',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Medicine Image File (Sawirka Dawada)',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Column(
                        children: [
                          if (medicineImageBase64 != null ||
                              imgCtrl.text.isNotEmpty)
                            Center(
                              child: Container(
                                width: 90,
                                height: 90,
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppTheme.primaryColor,
                                    width: 2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: NetworkOrAssetImage(
                                    imageUrl:
                                        medicineImageBase64 ?? imgCtrl.text,
                                    width: 90,
                                    height: 90,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final bytes =
                                    await ImagePickerService.pickImageBytes();
                                if (bytes != null && bytes.isNotEmpty) {
                                  final publicUrl =
                                      await ImagePickerService.uploadAndGetUrl(
                                        bytes,
                                        folder: 'avatars',
                                      );
                                  if (publicUrl.isNotEmpty) {
                                    setState(() {
                                      medicineImageBase64 = publicUrl;
                                      imgCtrl.text = publicUrl;
                                    });
                                  }
                                }
                              },
                              icon: const Icon(
                                Icons.photo_library_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              label: Text(
                                'Sawirka Dawada Soo Dooro / Choose Medicine Image File',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () {
                    if (titleCtrl.text.isNotEmpty) {
                      final catVal = categoryCtrl.text.isNotEmpty
                          ? categoryCtrl.text
                          : 'General';
                      final skuVal = skuCtrl.text.isNotEmpty
                          ? skuCtrl.text
                          : 'MED-${DateTime.now().millisecondsSinceEpoch}';

                      final val1 =
                          double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                      final val2 = double.tryParse(
                        originalPriceCtrl.text.trim(),
                      );

                      double finalPrice = 0.0;
                      double? finalOriginalPrice;

                      if (val1 > 0 && val2 != null && val2 > 0) {
                        // Two prices provided: lower price is selling price ($3.99), higher price is original price ($5.00)
                        if (val1 < val2) {
                          finalPrice = val1;
                          finalOriginalPrice = val2;
                        } else if (val2 < val1) {
                          finalPrice = val2;
                          finalOriginalPrice = val1;
                        } else {
                          finalPrice = val1;
                          finalOriginalPrice = null;
                        }
                      } else if (val1 > 0) {
                        finalPrice = val1;
                        finalOriginalPrice = null;
                      } else if (val1 == 0 && val2 != null && val2 > 0) {
                        finalPrice = val2;
                        finalOriginalPrice = null;
                      }

                      final imgVal =
                          (medicineImageBase64 != null &&
                              medicineImageBase64!.isNotEmpty)
                          ? medicineImageBase64!
                          : (imgCtrl.text.isNotEmpty ? imgCtrl.text : '');

                      context.read<AppState>().addMedicine(
                        MedicineModel(
                          id: 'med_${DateTime.now().millisecondsSinceEpoch}',
                          title: titleCtrl.text,
                          category: catVal,
                          sku: skuVal,
                          price: finalPrice,
                          originalPrice: finalOriginalPrice,
                          soldCount: 0,
                          imageUrl: imgVal,
                          description: descCtrl.text.isNotEmpty
                              ? descCtrl.text
                              : 'Quality pharmacy product.',
                          rating: 4.8,
                        ),
                      );

                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Medicine added successfully!'),
                        ),
                      );
                    }
                  },
                  child: Text(
                    'Save Product',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // TAB 5: MESSAGES & CHAT SCREEN (Image 3 layout)
  // ==========================================
  Widget _buildChatTab(BuildContext context) {
    final appState = context.watch<AppState>();
    final bookings = appState.appointments;
    final currentDocId = appState.getLoggedInDoctorId(
      _currentUserRole ?? 'Doctor',
      _currentUserEmail,
    );

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseService.instance.client != null
          ? SupabaseService.instance.client!
              .from('messages')
              .stream(primaryKey: ['id'])
              .order('created_at', ascending: true)
          : const Stream.empty(),
      builder: (context, snapshot) {
        final streamedMsgs = snapshot.data ?? [];
        final Map<String, Map<String, dynamic>> activeChatsMap = {};

        // Combine stream messages and local in-memory messages
        final allMsgs = [...streamedMsgs, ...appState.chatMessages];
        allMsgs.sort((a, b) {
          final tA = a['created_at'] ?? a['time'] ?? '';
          final tB = b['created_at'] ?? b['time'] ?? '';
          return tA.toString().compareTo(tB.toString());
        });

        for (var msg in allMsgs) {
          final isFromAdmin = msg['sender_role'] == 'admin' || msg['sender_id'] == 'admin' || msg['sender_name'] == 'Hospital Admin' || msg['sender_role'] == 'doctor' || msg['sender_id'] == 'doctor';
          
          final pId = isFromAdmin 
              ? (msg['patient_id'] ?? msg['patient_name'] ?? '').toString().trim()
              : (msg['sender_id'] ?? msg['patient_id'] ?? msg['sender_name'] ?? msg['patient_name'] ?? '').toString().trim();
          
          if (pId.isEmpty || pId.toLowerCase() == 'admin' || pId.toLowerCase() == 'doctor') continue;

          String pName = isFromAdmin 
              ? (msg['patient_name'] ?? msg['patient_id'] ?? '').toString().trim()
              : (msg['sender_name'] ?? msg['patient_name'] ?? msg['sender_id'] ?? msg['patient_id'] ?? '').toString().trim();

          if (pName.isEmpty || pName.length > 20 || RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(pName)) {
            final dbUser = appState.dbPatients.firstWhereOrNull((u) => 
              u['id']?.toString() == pId || 
              u['phone']?.toString() == pId || 
              u['full_name']?.toString() == pId
            );
            if (dbUser != null && (dbUser['full_name']?.toString().isNotEmpty ?? false)) {
              pName = dbUser['full_name'].toString().trim();
            } else if (msg['patient_name']?.toString().isNotEmpty ?? false) {
              pName = msg['patient_name'].toString().trim();
            } else {
              pName = 'Bukaan ($pId)';
            }
          }

          String rawText = (msg['text'] ?? msg['message'] ?? msg['content'] ?? '').toString().trim();
          String imgUrl = (msg['image_url'] ?? msg['media_url'] ?? msg['attachment_url'] ?? '').toString().trim();

          if (rawText.isNotEmpty) {
            try {
              final dec = EncryptionService.decrypt(rawText).trim();
              if (dec.isNotEmpty) {
                if (dec.startsWith('http://') || dec.startsWith('https://') || dec.startsWith('data:image/')) {
                  imgUrl = dec;
                  rawText = '';
                } else {
                  rawText = dec;
                }
              }
            } catch (_) {}
          }

          final isImg = imgUrl.isNotEmpty || rawText.startsWith('http://') || rawText.startsWith('https://') || rawText.startsWith('data:image/');
          final lastText = isImg ? '📷 Sawir' : (rawText.isNotEmpty ? rawText : 'Fariin cusub');

          String formattedTime = 'Recently';
          final rawTime = msg['created_at']?.toString() ?? msg['time']?.toString() ?? '';
          if (rawTime.isNotEmpty) {
            try {
              final dt = DateTime.parse(rawTime).toLocal();
              formattedTime = DateFormat('hh:mm a').format(dt);
            } catch (_) {}
          }

          final chatKey = pName.isNotEmpty ? pName.toLowerCase().trim() : pId.toLowerCase().trim();

          activeChatsMap[chatKey] = {
            'patientId': pId,
            'patientName': pName,
            'lastMsg': lastText,
            'time': formattedTime,
          };
        }

        // Include any appointments if not yet in chat map
        for (var apt in bookings) {
          final pName = apt.patientName.trim();
          final chatKey = pName.isNotEmpty ? pName.toLowerCase() : apt.id.toLowerCase();
          if (!activeChatsMap.containsKey(chatKey)) {
            activeChatsMap[chatKey] = {
              'patientId': apt.id.isNotEmpty ? apt.id : pName,
              'patientName': pName,
              'lastMsg': 'Tap to start conversation.',
              'time': '',
            };
          }
        }

        final activeChats = activeChatsMap.values.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Doctor-Patient Support Center',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Secure communication channel between hospital staff and patients.',
          style: GoogleFonts.plusJakartaSans(
            color: AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 20),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left pane: active chat list
            Expanded(
              flex: 2,
              child: Container(
                height: 520,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Chats',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: activeChats.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final chat = activeChats[idx];
                          final patientName = chat['patientName']?.toString() ?? '';
                          final patientId = chat['patientId']?.toString() ?? patientName;

                          final isSelected = _selectedChatPatientName == patientName ||
                              _selectedChatPatientId == patientId ||
                              _selectedChatPatient?.id == patientId;

                          final patientMsgs = allMsgs
                              .where(
                                (m) {
                                  final pN = (m['patient_name'] ?? m['sender_name'] ?? '').toString().trim();
                                  final pI = (m['patient_id'] ?? m['sender_id'] ?? '').toString().trim();
                                  final isFromPatient = m['sender_role'] != 'admin' && m['sender_role'] != 'doctor' && m['sender_id'] != 'admin' && m['sender_id'] != 'doctor';
                                  return (pN == patientName || pI == patientId) && isFromPatient;
                                },
                              )
                              .toList();

                          int unreadCount = 0;
                          final isDismissed = _lastSeenMessageIds[patientName] == 'READ' || 
                                              _lastSeenMessageIds[patientId] == 'READ' ||
                                              _lastSeenMessageIds[patientName.toLowerCase()] == 'READ';

                          if (!isSelected && !isDismissed) {
                            unreadCount = patientMsgs.where((m) => m['is_read'] != true).length;
                          }

                          return ListTile(
                            selected: isSelected,
                            selectedTileColor: AppTheme.primaryLight,
                            leading: const CircleAvatar(
                              radius: 20,
                              backgroundColor: AppTheme.primaryColor,
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            title: Text(
                              patientName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              chat['lastMsg'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: isSelected
                                    ? AppTheme.primaryDark
                                    : AppTheme.textSecondary,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      chat['time'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textLight,
                                      ),
                                    ),
                                    if (unreadCount > 0 && !isSelected) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '$unreadCount',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Color(0xFFEF4444),
                                    size: 18,
                                  ),
                                  tooltip: 'Tirtir Wada-sheekaysiga',
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        title: Row(
                                          children: [
                                            const Icon(Icons.warning_amber_rounded, color: Colors.red),
                                            const SizedBox(width: 8),
                                            const Text('Tirtir Wada-sheekaysiga'),
                                          ],
                                        ),
                                        content: Text(
                                          'Ma ziirtaa inaad si joogto ah u tirtirto wada-sheekaysiga bukaanka ($patientName)?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('Kansal'),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                            ),
                                            onPressed: () async {
                                              Navigator.pop(ctx);
                                              await appState.clearPatientChatHistory(patientId, patientName);
                                              if (_selectedChatPatientName == patientName || _selectedChatPatientId == patientId) {
                                                setState(() {
                                                  _selectedChatPatient = null;
                                                  _selectedChatPatientName = null;
                                                  _selectedChatPatientId = null;
                                                });
                                              }
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('Wada-sheekaysigii bukaanka waa la tirtiray!'),
                                                    backgroundColor: Colors.red,
                                                  ),
                                                );
                                              }
                                            },
                                            child: const Text(
                                              'Haa, Tirtir',
                                              style: TextStyle(color: Colors.white),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            onTap: () async {
                              final pName = chat['patientName']?.toString() ?? '';
                              final pId = chat['patientId']?.toString() ?? pName;

                              _lastSeenMessageIds[pName] = 'READ';
                              _lastSeenMessageIds[pId] = 'READ';
                              _lastSeenMessageIds[pName.toLowerCase()] = 'READ';

                              final client = SupabaseService.instance.client;
                              if (client != null && SupabaseService.instance.isInitialized) {
                                try {
                                  await client.from('messages').update({'is_read': true}).or('patient_id.eq.$pId,patient_id.eq.$pName,sender_id.eq.$pId').eq('is_read', false).timeout(const Duration(seconds: 5));
                                } catch (_) {}
                              }

                              appState.markChatAsRead(pName);
                              final docId = appState.getLoggedInDoctorId(
                                _currentUserRole ?? 'Doctor',
                                _currentUserEmail,
                              );

                              final convId = await appState
                                  .getOrCreateConversation(
                                    patientId: pId,
                                    doctorId: docId,
                                  );
                              await appState.setActiveConversation(convId);
                              setState(() {
                                _selectedChatPatientName = pName;
                                _selectedChatPatientId = pId;
                                _selectedChatPatient = AppointmentModel(
                                  id: pId,
                                  referenceId: 'REF',
                                  doctorId: docId,
                                  doctorName: 'Doctor',
                                  doctorSpecialty: 'General',
                                  doctorImageUrl: '',
                                  hospitalName: 'Nasiib Hospital',
                                  date: '',
                                  time: '',
                                  appointmentType: '',
                                  patientName: pName,
                                  patientPhone: '',
                                  patientAge: 20,
                                  patientGender: 'Male',
                                  reasonForVisit: '',
                                  paymentMethod: '',
                                  amount: 0,
                                  queueNumber: 1,
                                  createdAt: '',
                                );
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),

            // Right pane: chat dialogue
            Expanded(
              flex: 4,
              child: Container(
                height: 520,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: _selectedChatPatient == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 64,
                              color: AppTheme.textLight,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Select a patient to start conversation',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          // Chat Header
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                            ),
                            child: Row(
                              children: [
                                const CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppTheme.primaryColor,
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (_selectedChatPatient!.patientName.length > 20 || RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(_selectedChatPatient!.patientName))
                                            ? (appState.dbPatients.firstWhereOrNull((u) => u['id']?.toString() == _selectedChatPatient!.patientName || u['phone']?.toString() == _selectedChatPatient!.patientName)?['full_name']?.toString() ?? 'Ahmed Muktar')
                                            : _selectedChatPatient!.patientName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            'Active Patient • Ref: ${_selectedChatPatient!.referenceId}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(
                                            Icons.lock_rounded,
                                            color: Color(0xFF10B981),
                                            size: 11,
                                          ),
                                          const SizedBox(width: 3),
                                          const Text(
                                            'E2EE Secured',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF10B981),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.phone,
                                    color: AppTheme.primaryColor,
                                    size: 20,
                                  ),
                                  onPressed: () {},
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.videocam,
                                    color: AppTheme.primaryColor,
                                    size: 20,
                                  ),
                                  onPressed: () {},
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),

                          // Messages List
                          Expanded(
                            child: Container(
                              color: const Color(0xFFFAFBFC),
                              padding: const EdgeInsets.all(20),
                              child: StreamBuilder<List<Map<String, dynamic>>>(
                                stream: (SupabaseService.instance.client != null && SupabaseService.instance.isInitialized)
                                    ? SupabaseService.instance.client!
                                        .from('messages')
                                        .stream(primaryKey: ['id'])
                                        .order('created_at', ascending: true)
                                    : const Stream.empty(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                                  final msgs = snapshot.data!;
                                  if (msgs.isEmpty) return const Center(child: Text("Fariin ma jirto"));

                                  return ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: msgs.length,
                                    itemBuilder: (context, index) {
                                      final m = msgs[index];
                                      String text = (m['message'] ?? m['text'] ?? m['content'] ?? '').toString().trim();
                                      String imgUrl = (m['media_url'] ?? m['image_url'] ?? m['attachment_url'] ?? '').toString().trim();

                                      if (text.isNotEmpty) {
                                        try {
                                          final dec = EncryptionService.decrypt(text).trim();
                                          if (dec.isNotEmpty) {
                                            if (dec.startsWith('http://') || dec.startsWith('https://') || dec.startsWith('data:image/')) {
                                              imgUrl = dec;
                                              text = '';
                                            } else {
                                              text = dec;
                                            }
                                          }
                                        } catch (_) {}
                                      }

                                      if (imgUrl.isEmpty && (text.startsWith('http://') || text.startsWith('https://') || text.startsWith('data:image/'))) {
                                        imgUrl = text;
                                        text = '';
                                      }

                                      final rawUrl = imgUrl.isNotEmpty ? imgUrl : text;
                                      final isImage = rawUrl.startsWith('http') && (rawUrl.contains('/storage/') || rawUrl.contains('supabase.co') || rawUrl.endsWith('.jpg') || rawUrl.endsWith('.png') || rawUrl.endsWith('.jpeg') || rawUrl.startsWith('data:image/'));
                                      final isAdm = m['sender_role'] == 'admin' || m['sender_role'] == 'doctor' || m['sender_id'] == 'admin' || m['sender_id'] == 'doctor' || m['sender_name'] == 'Hospital Admin';

                                      return Align(
                                        alignment: isAdm ? Alignment.centerRight : Alignment.centerLeft,
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(vertical: 4),
                                          padding: isImage ? EdgeInsets.zero : const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: isImage
                                                ? Colors.transparent
                                                : (isAdm ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9)),
                                            borderRadius: BorderRadius.circular(12),
                                            border: isImage
                                                ? null
                                                : Border.all(
                                                    color: isAdm
                                                        ? const Color(0xFF86EFAC).withOpacity(0.5)
                                                        : const Color(0xFFE2E8F0),
                                                  ),
                                            boxShadow: isImage
                                                ? []
                                                : [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.04),
                                                      blurRadius: 4,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                          ),
                                          child: isImage
                                              ? ClipRRect(
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: NetworkOrAssetImage(
                                                    imageUrl: rawUrl,
                                                    width: 240,
                                                    height: 180,
                                                    fit: BoxFit.cover,
                                                  ),
                                                )
                                              : Text(
                                                  text,
                                                  style: GoogleFonts.plusJakartaSans(
                                                    color: isAdm ? const Color(0xFF14532D) : const Color(0xFF1E293B),
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                          ),
                        ),
                       const Divider(height: 1),

                          // Text input box
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.add_photo_alternate_rounded,
                                    color: Color(0xFF0284C7),
                                    size: 26,
                                  ),
                                  tooltip: 'Sawir ka soo qabso computer-ka',
                                  onPressed: () async {
                                    final Uint8List? bytes =
                                        await ImagePickerService.pickImageBytes();
                                    if (bytes != null &&
                                        bytes.isNotEmpty &&
                                        _selectedChatPatient != null) {
                                      final String publicStorageUrl =
                                          await ImagePickerService.uploadAndGetUrl(
                                            bytes,
                                            folder: 'chat_images',
                                          );
                                      if (publicStorageUrl.isEmpty) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Sawirka Supabase Storage lagu shubi waayay.',
                                              ),
                                            ),
                                          );
                                        }
                                        return;
                                      }

                                      final currentDocId = appState
                                          .getLoggedInDoctorId(
                                            _currentUserRole ?? 'Doctor',
                                            _currentUserEmail,
                                          );
                                      final activeDocName = appState.doctors
                                          .firstWhere(
                                            (d) => d.id == currentDocId,
                                            orElse: () => DoctorModel(
                                              id: '',
                                              name: 'Doctor',
                                              specialty: '',
                                              hospital: '',
                                              rating: 0,
                                              reviewsCount: 0,
                                              experience: '',
                                              patientsCount: '',
                                              workingHours: '',
                                              about: '',
                                              imageUrl: '',
                                              consultationFee: 0,
                                            ),
                                          )
                                          .name;

                                      await appState.sendChatMessage(
                                        'admin',
                                        'Nasiib Hospital Support',
                                        '', // Image only
                                        _selectedChatPatient!.patientName,
                                        imageUrl: publicStorageUrl,
                                        senderRole: 'admin',
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Sawirkii waa loo diray bukaanka!',
                                            ),
                                            backgroundColor: Colors.green,
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    controller: _chatReplyController,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    decoration: InputDecoration(
                                      hintText: 'Type your message...',
                                      hintStyle: const TextStyle(fontSize: 13),
                                      fillColor: const Color(0xFFF3F4F6),
                                      filled: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(24),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 10,
                                          ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FloatingActionButton.small(
                                  onPressed: () async {
                                    final text = _chatReplyController.text.trim();
                                    if (text.isNotEmpty && _selectedChatPatient != null) {
                                      final targetPatientId = _selectedChatPatient!.id.isNotEmpty ? _selectedChatPatient!.id : _selectedChatPatient!.patientName;
                                      final targetPatientName = _selectedChatPatient!.patientName;
                                      final convId = 'conv_${targetPatientId}_support';

                                      appState.sendChatMessage(
                                        'admin',
                                        'Nasiib Hospital Support',
                                        text,
                                        targetPatientId,
                                        senderRole: 'admin',
                                        conversationId: convId,
                                      );

                                      _chatReplyController.clear();
                                    }
                                  },
                                  backgroundColor: AppTheme.primaryColor,
                                  child: const Icon(
                                    Icons.send,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  },
);
}

  Widget _buildRecycleBinTab(BuildContext context) {
    final appState = context.watch<AppState>();
    final deletedDocs = appState.deletedDoctors;
    final deletedMeds = appState.deletedMedicines;
    final deletedApts = appState.deletedAppointments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recycle Bin & Restore Center',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        Text(
          'Restore accidentally deleted profiles, catalog items, and bookings, or clear them permanently.',
          style: GoogleFonts.plusJakartaSans(
            color: AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 32),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // COLUMN 1: DELETED DOCTORS
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.people_alt_rounded,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Deleted Doctors (${deletedDocs.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    if (deletedDocs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: Text(
                            'No deleted doctors.',
                            style: TextStyle(
                              color: AppTheme.textLight,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    else
                      ...deletedDocs.map(
                        (doc) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      doc.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      doc.specialty,
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.settings_backup_restore_rounded,
                                  color: Colors.green,
                                  size: 18,
                                ),
                                tooltip: 'Restore',
                                onPressed: () {
                                  appState.restoreDoctor(doc);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${doc.name} restored successfully!',
                                      ),
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_forever_rounded,
                                  color: Colors.red,
                                  size: 18,
                                ),
                                tooltip: 'Delete Permanently',
                                onPressed: () {
                                  appState.deleteDoctorPermanentlyFromBin(
                                    doc.id,
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${doc.name} deleted permanently!',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),

            // COLUMN 2: DELETED MEDICINES
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.local_pharmacy_rounded,
                          color: AppTheme.successGreen,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Deleted Medicines (${deletedMeds.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    if (deletedMeds.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: Text(
                            'No deleted medicines.',
                            style: TextStyle(
                              color: AppTheme.textLight,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    else
                      ...deletedMeds.map(
                        (med) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      med.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '\$${med.price.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.settings_backup_restore_rounded,
                                  color: Colors.green,
                                  size: 18,
                                ),
                                tooltip: 'Restore',
                                onPressed: () {
                                  appState.restoreMedicine(med);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${med.title} restored successfully!',
                                      ),
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_forever_rounded,
                                  color: Colors.red,
                                  size: 18,
                                ),
                                tooltip: 'Delete Permanently',
                                onPressed: () {
                                  appState.deleteMedicinePermanentlyFromBin(
                                    med.id,
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${med.title} deleted permanently!',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),

            // COLUMN 3: DELETED BOOKINGS / PATIENTS
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_month_rounded,
                          color: Colors.deepOrange,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Deleted Bookings (${deletedApts.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    if (deletedApts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: Text(
                            'No deleted bookings.',
                            style: TextStyle(
                              color: AppTheme.textLight,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    else
                      ...deletedApts.map(
                        (apt) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      apt.patientName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '${apt.doctorName} • ${apt.date}',
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.settings_backup_restore_rounded,
                                  color: Colors.green,
                                  size: 18,
                                ),
                                tooltip: 'Restore',
                                onPressed: () {
                                  appState.restoreAppointment(apt);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${apt.patientName}\'s booking restored successfully!',
                                      ),
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_forever_rounded,
                                  color: Colors.red,
                                  size: 18,
                                ),
                                tooltip: 'Delete Permanently',
                                onPressed: () {
                                  appState.deleteAppointmentPermanentlyFromBin(
                                    apt.id,
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${apt.patientName}\'s booking deleted permanently!',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showPrescriptionPreviewDialog(
    BuildContext context,
    AppointmentModel apt,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 30,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. PRESCRIPTION PAPER (MATCHING IMAGE DESIGN)
              Container(
                width: 600,
                height: 750,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A. Top Wavy Gradient Header
                    Container(
                      height: 110,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.local_hospital_rounded,
                              color: Color(0xFF0284C7),
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Nasiib Hospital',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                'Quality & Caring Healthcare',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: Colors.white.withOpacity(0.8),
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // B. Doctor Info Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 14,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFAFAFA),
                        border: Border(
                          bottom: BorderSide(
                            color: Color(0xFFE2E8F0),
                            width: 2,
                          ),
                        ),
                      ),
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DoctorModel.sanitizeDoctorName(apt.doctorName),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0284C7),
                            ),
                          ),
                          Text(
                            apt.doctorSpecialty.toUpperCase(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF64748B),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // C. Patient Metadata Grid Rows
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        border: Border(
                          bottom: BorderSide(
                            color: Color(0xFFE2E8F0),
                            width: 2,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildPreviewMetaRow(
                                  'Patient Name:',
                                  apt.patientName,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 2,
                                child: _buildPreviewMetaRow('Date:', apt.date),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildPreviewMetaRow(
                                  'Age / Gender:',
                                  '${apt.patientAge} yrs / ${apt.patientGender}',
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 2,
                                child: _buildPreviewMetaRow(
                                  'Weight:',
                                  _weightController.text,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildPreviewMetaRow(
                                  'Diagnosis:',
                                  _diagnosisController.text,
                                  isHighlight: true,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // D. Rx Body with Stethoscope Watermark & Authorized Sign block
                    Expanded(
                      child: Stack(
                        children: [
                          // Background stethoscope icon watermark
                          Center(
                            child: Icon(
                              Icons.favorite_rounded,
                              size: 200,
                              color: const Color(0xFF0284C7).withOpacity(0.03),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(30.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Text(
                                      _prescriptionController.text.isNotEmpty
                                          ? _prescriptionController.text
                                          : 'No medicines written yet.',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        height: 1.6,
                                        color: const Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                ),
                                // Signature line
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: Container(
                                    width: 180,
                                    margin: const EdgeInsets.only(top: 20),
                                    child: Column(
                                      children: [
                                        Container(
                                          decoration: const BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Color(0xFF64748B),
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                          height: 30,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Authorized Signature',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. DIALOG BUTTONS ROW
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Cancel / Ka bax'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  ElevatedButton.icon(
                    onPressed: () {
                      printPrescription(
                        doctorName: apt.doctorName,
                        specialty: apt.doctorSpecialty,
                        patientName: apt.patientName,
                        date: apt.date,
                        age: apt.patientAge.toString(),
                        gender: apt.patientGender,
                        diagnosis: _diagnosisController.text,
                        prescription: _prescriptionController.text,
                        patientId: apt.id,
                        weight: _weightController.text,
                      );
                      Navigator.pop(context);
                    },
                    icon: const Icon(
                      Icons.print_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Print Now / Daabac Warqadda',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPreviewMetaRow(
    String label,
    String val, {
    bool isHighlight = false,
  }) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFE2E8F0),
            style: BorderStyle.solid,
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              val,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isHighlight
                    ? const Color(0xFF0284C7)
                    : const Color(0xFF1E293B),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getMessagesForSelectedChat(AppState appState) {
    final sel = _selectedChatPatient;
    if (sel == null) return [];
    final pName = sel.patientName.trim().toLowerCase();
    final pId = sel.id.trim().toLowerCase();
    final pPhone = sel.patientPhone.replaceAll(RegExp(r'[\s\-()]+'), '').toLowerCase();

    return appState.chatMessages.where((m) {
      final msgPId = (m['patient_id']?.toString() ?? '').trim().toLowerCase();
      final msgSName = (m['sender_name']?.toString() ?? '').trim().toLowerCase();
      final msgSId = (m['sender_id']?.toString() ?? '').trim().toLowerCase();

      final matchesName = pName.isNotEmpty &&
          (msgPId == pName || msgSName == pName || msgSId == pName || msgPId.contains(pName) || pName.contains(msgPId));
      final matchesId = pId.isNotEmpty &&
          (msgPId == pId || msgSName == pId || msgSId == pId || msgPId.contains(pId) || pId.contains(msgPId));
      final matchesPhone = pPhone.isNotEmpty &&
          (msgPId.contains(pPhone) || msgSId.contains(pPhone) || msgSName.contains(pPhone));

      return matchesName || matchesId || matchesPhone;
    }).toList();
  }

  Widget _buildDoctorVerificationTab(BuildContext context) {
    final appState = context.watch<AppState>();
    final onlyDoctors = appState.doctors
        .where(
          (d) =>
              !d.specialty.toLowerCase().contains('kalkaaliso') &&
              !d.specialty.toLowerCase().contains('nurse'),
        )
        .toList();

    final pendingDoctors = onlyDoctors.where((d) => !d.isVerified).toList();
    final verifiedDoctors = onlyDoctors.where((d) => d.isVerified).toList();

    return Container(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Doctor Verification Center',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Review uploaded credentials (National ID / Passport) to verify Nasiib Hospital Doctors.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: Colors.white,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Pending Approvals (${pendingDoctors.length})',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        pendingDoctors.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(40),
                                alignment: Alignment.center,
                                child: Text(
                                  'No pending verification requests found.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: pendingDoctors.length,
                                itemBuilder: (context, index) {
                                  final doc = pendingDoctors[index];
                                  return _buildVerificationRequestCard(
                                    context,
                                    appState,
                                    doc,
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 2,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: Colors.white,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.verified_rounded,
                              color: AppTheme.primaryColor,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Verified Active Doctors (${verifiedDoctors.length})',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        verifiedDoctors.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(40),
                                alignment: Alignment.center,
                                child: Text(
                                  'No verified doctors yet.',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: const Color(0xFF64748B),
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: verifiedDoctors.length,
                                itemBuilder: (context, index) {
                                  final doc = verifiedDoctors[index];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundImage: NetworkImage(
                                        doc.imageUrl,
                                      ),
                                    ),
                                    title: Text(
                                      doc.name,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: Text(
                                      doc.specialty,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                      ),
                                    ),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE0F2FE),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            color: Color(0xFF0F8CFF),
                                            size: 14,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Verified',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF0F8CFF),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationRequestCard(
    BuildContext context,
    AppState appState,
    DoctorModel doc,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: NetworkImage(doc.imageUrl),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      '${doc.specialty} • ${doc.experience}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  'Pending Verification',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                icon: const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 16,
                ),
                label: Text(
                  'Approve & Verify Doctor',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  final updated = doc.copyWith(isVerified: true);
                  appState.updateDoctor(updated);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${doc.name} has been successfully verified!',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _selectedOrderStatusFilter = 'All';

  Widget _buildTableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildTableCell(String text, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildStatusCell(String status) {
    Color bg = Colors.amber.shade50;
    Color fg = Colors.amber.shade900;

    if (status == 'Accepted' || status == 'Preparing') {
      bg = Colors.blue.shade50;
      fg = Colors.blue.shade900;
    } else if (status == 'Ready' || status == 'Out for Delivery') {
      bg = Colors.purple.shade50;
      fg = Colors.purple.shade900;
    } else if (status == 'Delivered') {
      bg = Colors.green.shade50;
      fg = Colors.green.shade900;
    } else if (status == 'Cancelled') {
      bg = Colors.red.shade50;
      fg = Colors.red.shade900;
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          status,
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: fg,
          ),
        ),
      ),
    );
  }

  void _showPharmacyOrderDetailsModal(
    BuildContext context,
    Map<String, dynamic> order,
    List<Map<String, dynamic>> allItems,
  ) {
    final orderId = order['id']?.toString() ?? '';
    final orderNum = order['order_number']?.toString() ?? '#ORD';
    final patientName = order['patient_name']?.toString() ?? 'Patient';
    final phone = order['patient_phone']?.toString() ?? '';
    final city = order['city']?.toString() ?? 'Mogadishu';
    String rawDistrict = order['district']?.toString() ?? '';
    if (rawDistrict.isEmpty || rawDistrict == 'Medicines & Skincare' || rawDistrict == 'Pharmacy') {
      final addr = (order['delivery_address'] ?? order['address'] ?? order['notes'] ?? '').toString();
      if (addr.contains(',')) {
        final parts = addr.split(',');
        if (parts.length >= 2) {
          rawDistrict = parts[parts.length - 2].trim();
        } else if (parts.isNotEmpty) {
          rawDistrict = parts[0].trim();
        }
      }
    }
    if (rawDistrict.isEmpty || rawDistrict == 'Medicines & Skincare' || rawDistrict == 'Pharmacy') {
      rawDistrict = 'Hodan';
    }
    final district = rawDistrict;
    final address = order['delivery_address']?.toString() ?? '';
    final total =
        (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final rawSubtotal = (order['subtotal'] as num?)?.toDouble();
    final subtotal = (rawSubtotal != null && rawSubtotal > 0) ? rawSubtotal : total;
    final deliveryFee = (order['delivery_fee'] as num?)?.toDouble() ?? 0.0;
    final payMethod = order['payment_method']?.toString() ?? 'EVC Plus';
    final payStatus = order['payment_status']?.toString() ?? 'Paid';

    final String currentStatus = (order['status']?.toString() ?? 'Pending')
        .trim();
    final lowerStatus = currentStatus.toLowerCase();

    final bool isPending =
        lowerStatus == 'pending' ||
        lowerStatus == 'new' ||
        lowerStatus == 'placed' ||
        lowerStatus == 'order received';
    final bool isAccepted =
        lowerStatus == 'accepted' || lowerStatus == 'approved';
    final bool isPreparing =
        lowerStatus == 'preparing' || lowerStatus == 'prep';
    final bool isReady =
        lowerStatus == 'ready' || lowerStatus == 'ready for delivery';
    final bool isOutForDelivery =
        lowerStatus == 'out for delivery' || lowerStatus == 'on the way';
    final bool isDelivered =
        lowerStatus == 'delivered' || lowerStatus == 'completed';
    final bool isCancelled =
        lowerStatus == 'cancelled' || lowerStatus == 'canceled';

    final bool canAccept = isPending;
    final bool canPrepare = isAccepted;
    final bool canReady = isPreparing;
    final bool canOutForDelivery = isReady;
    final bool canMarkDelivered = isOutForDelivery;
    final bool canCancel = !isDelivered && !isCancelled;

    final orderMedicines = allItems
        .where((item) => item['order_id']?.toString() == orderId)
        .toList();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ORDER DETAILS $orderNum',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(dialogCtx),
              ),
            ],
          ),
          content: SizedBox(
            width: 550,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Patient Information',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Name: $patientName',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Phone: $phone',
                          style: GoogleFonts.plusJakartaSans(fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delivery Location',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'City / District: $city, $district',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Address: $address',
                          style: GoogleFonts.plusJakartaSans(fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Payment Method',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            Text(
                              payMethod,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Payment Status',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            Text(
                              payStatus,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    'Ordered Medicines',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (orderMedicines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Medicine items listed in order summary ($orderNum)',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  else
                    ...orderMedicines.map((m) {
                      final name = m['medicine_name'] ?? 'Medicine';
                      final qty = m['quantity'] ?? 1;
                      final price =
                          (m['unit_price'] as num?)?.toDouble() ?? 0.0;
                      final itemTotal =
                          (m['total_price'] as num?)?.toDouble() ??
                          (price * qty);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$name x$qty',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '\$${itemTotal.toStringAsFixed(2)}',
                              style: GoogleFonts.plusJakartaSans(fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }),

                  const Divider(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Subtotal (Dawooyinka)',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        '\$${subtotal.toStringAsFixed(2)}',
                        style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Delivery Fee',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        deliveryFee > 0
                            ? '\$${deliveryFee.toStringAsFixed(2)}'
                            : '\$0.00 (Bilaash)',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: deliveryFee == 0 ? FontWeight.bold : FontWeight.normal,
                          color: deliveryFee == 0 ? const Color(0xFF10B981) : AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'TOTAL',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '\$${total.toStringAsFixed(2)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Text(
                    'Update Order Workflow Status',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: canAccept
                            ? () {
                                context.read<AppState>().updateOrderStatus(
                                  orderId,
                                  'Accepted',
                                );
                                Navigator.pop(dialogCtx);
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade600,
                        ),
                        child: const Text(
                          'Accept Order',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: canPrepare
                            ? () {
                                context.read<AppState>().updateOrderStatus(
                                  orderId,
                                  'Preparing',
                                );
                                Navigator.pop(dialogCtx);
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade600,
                        ),
                        child: const Text(
                          'Start Preparing',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: canReady
                            ? () {
                                context.read<AppState>().updateOrderStatus(
                                  orderId,
                                  'Ready for Delivery',
                                );
                                Navigator.pop(dialogCtx);
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade600,
                        ),
                        child: const Text(
                          'Ready for Delivery',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: canOutForDelivery
                            ? () {
                                Navigator.pop(dialogCtx);
                                _showDriverDispatchDialog(context, order);
                              }
                            : null,
                        icon: const Icon(Icons.two_wheeler_rounded, size: 16, color: Colors.white),
                        label: const Text(
                          'Out for Delivery (Qoondee)',
                          style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF15803D),
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade600,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: canMarkDelivered
                            ? () {
                                context.read<AppState>().updateOrderStatus(
                                  orderId,
                                  'Delivered',
                                );
                                Navigator.pop(dialogCtx);
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade600,
                        ),
                        child: const Text(
                          'Mark Delivered',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: canCancel
                            ? () {
                                context.read<AppState>().updateOrderStatus(
                                  orderId,
                                  'Cancelled',
                                );
                                Navigator.pop(dialogCtx);
                              }
                            : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          disabledForegroundColor: Colors.grey.shade400,
                        ),
                        child: const Text(
                          'Cancel Order',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDriverDispatchDialog(BuildContext context, Map<String, dynamic> order) async {
    final orderId = order['id']?.toString() ?? '';
    final orderNum = order['order_number']?.toString() ?? '#ORD';

    List<Map<String, dynamic>> drivers = [];
    try {
      final client = SupabaseService.instance.client;
      if (client != null && SupabaseService.instance.isInitialized) {
        final res = await client.from('drivers').select().eq('status', 'active');
        if (res is List && res.isNotEmpty) {
          drivers = List<Map<String, dynamic>>.from(res);
        }
      }
    } catch (_) {}

    Map<String, dynamic>? selectedDriver = drivers.isNotEmpty ? drivers.first : null;

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (dispatchCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.two_wheeler_rounded, color: Color(0xFF15803D)),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Qoondee Darawal ($orderNum)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: drivers.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'Majiraan darawallo diiwaangashan oo active ah. Fadlan marka hore darawal ka diiwaangeli "Driver Management".',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: Colors.red.shade700,
                          ),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fadlan ka dooro darawalka gaarsiinaya daawada bukaan-ka:',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<Map<String, dynamic>>(
                            value: selectedDriver,
                            isExpanded: true,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            items: drivers.map((driver) {
                              final dName = (driver['name'] ?? driver['full_name'] ?? 'Darawal').toString();
                              final dPhone = (driver['phone'] ?? driver['phone_number'] ?? '').toString();
                              return DropdownMenuItem<Map<String, dynamic>>(
                                value: driver,
                                child: Text(
                                  '$dName ${dPhone.isNotEmpty ? "($dPhone)" : ""}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() {
                                  selectedDriver = val;
                                });
                              }
                            },
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dispatchCtx),
                  child: Text(
                    'Ka noqo',
                    style: GoogleFonts.plusJakartaSans(color: Colors.grey.shade700),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final orderId = order['id'];
                    if (orderId == null) return;

                    // 1. Close dialog immediately
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }

                    // 2. Perform PRIMARY status update (Exact same way Accept & Ready work)
                    try {
                      final client = SupabaseService.instance.client;
                      if (client != null && SupabaseService.instance.isInitialized) {
                        await client
                            .from('orders')
                            .update({'status': 'Out for Delivery'})
                            .eq('id', orderId);

                        final custPhone = (order['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
                        final custId = (order['patient_id'] ?? order['user_id'] ?? '').toString();
                        final custTopic = custId.isNotEmpty ? 'user_$custId' : (custPhone.isNotEmpty ? 'user_$custPhone' : null);

                        if (custTopic != null) {
                          FcmSender().sendTopicNotification(
                            topic: custTopic,
                            title: 'Nasiib Pharmacy Delivery',
                            body: 'Dalabkaaga dawooyinka wuxuu ku jiraa jidka!',
                          );
                        }
                      }

                      // 3. Immediately update UI & trigger full reload
                      if (mounted) {
                        setState(() {
                          order['status'] = 'Out for Delivery';
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Dalabka waa loo diray darawalka!"),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                      await context.read<AppState>().fetchPharmacyOrders();
                    } catch (e) {
                      debugPrint("Primary Status Update Failed: $e");
                    }

                    // 4. Secondary non-blocking driver metadata update (if columns exist)
                    final targetDriver = selectedDriver ?? (drivers.isNotEmpty ? drivers.first : null);
                    if (targetDriver != null) {
                      final dName = (targetDriver['name'] ?? targetDriver['full_name'] ?? '').toString();
                      final dPhone = (targetDriver['phone'] ?? targetDriver['phone_number'] ?? '').toString();
                      try {
                        final client = SupabaseService.instance.client;
                        if (client != null && SupabaseService.instance.isInitialized) {
                          await client
                              .from('orders')
                              .update({
                                'rider_name': dName,
                                'rider_phone': dPhone,
                              })
                              .eq('id', orderId);
                        }
                      } catch (_) {
                        // Silently ignore if column does not exist
                      }
                    }
                  },
                  icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                  label: Text(
                    'U Dir Darawalka',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDriverActiveTasksCard(
    BuildContext context,
    Map<String, dynamic> order,
    List<Map<String, dynamic>> allItems,
  ) {
    final orderId = order['id']?.toString() ?? '';
    final orderNum = order['order_number']?.toString() ?? '#ORD';
    final patientName = order['patient_name']?.toString() ?? 'Bukaan';
    final patientPhone = order['patient_phone']?.toString() ?? 'N/A';
    final district = order['district']?.toString() ?? 'Hodan';
    final address = order['delivery_address']?.toString() ?? 'Mogadishu';
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final driverName = (order['rider_name'] ?? order['driver_name'] ?? 'Darawal').toString();
    final driverPhone = (order['rider_phone'] ?? order['driver_phone'] ?? '').toString();

    final orderItems = allItems.where((i) => i['order_id']?.toString() == orderId).toList();
    final itemsSummary = orderItems.isNotEmpty
        ? orderItems.map((i) => "${i['medicine_name'] ?? 'Dawada'} (x${i['quantity'] ?? 1})").join(', ')
        : (order['items_summary']?.toString() ?? 'Dawaa ilaa 1+');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCFCE7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      orderNum,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: const Color(0xFF15803D),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.two_wheeler_rounded, size: 14, color: Colors.orange),
                        const SizedBox(width: 4),
                        Text(
                          'On The Way',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Text(
                '\$${total.toStringAsFixed(2)}',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: const Color(0xFF15803D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.person_rounded, size: 16, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Text(
                'Bukaanka: ',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
              ),
              Text(
                patientName,
                style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.phone_rounded, size: 14, color: Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text(
                patientPhone,
                style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Cinwaanka: $district, $address',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF334155)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.medication_rounded, size: 16, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Dawooyinka: $itemsSummary',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF475569)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (driverName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.sports_motorsports_rounded, size: 16, color: Color(0xFF15803D)),
                const SizedBox(width: 6),
                Text(
                  'Darawalka: $driverName ${driverPhone.isNotEmpty ? "($driverPhone)" : ""}',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF15803D)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDriverManagementView(BuildContext context) {
    final appState = context.watch<AppState>();
    final allOrders = appState.orders;
    final activeOrders = allOrders.where((o) {
      final st = (o['status'] ?? '').toString();
      return st == 'Out for Delivery' || st == 'On The Way';
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.delivery_dining_rounded, color: Color(0xFF15803D), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Driver Management (Maamulka Darawallada)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Diiwaangeli oo maamul darawallada gaarsiinta dawooyinka ee Nasiib Hospital',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: () => _showAddDriverDialog(context),
              icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
              label: Text(
                '+ Diiwaangeli Darawal',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 13,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF15803D),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        StreamBuilder<List<Map<String, dynamic>>>(
          stream: (SupabaseService.instance.client != null && SupabaseService.instance.isInitialized)
              ? SupabaseService.instance.client!.from('drivers').stream(primaryKey: ['id'])
              : const Stream.empty(),
          builder: (context, snapshot) {
            final streamedList = snapshot.data ?? [];
            final driverList = streamedList.isNotEmpty ? streamedList : _manualDriversList;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildDriverKpiCard(
                        'Warta Darawallada',
                        '${driverList.length}',
                        Icons.people_rounded,
                        const Color(0xFF15803D),
                        const Color(0xFFDCFCE7),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDriverKpiCard(
                        'Hawlaha Hal-ka-mid ah',
                        '${activeOrders.length}',
                        Icons.two_wheeler_rounded,
                        Colors.orange.shade800,
                        Colors.orange.shade50,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Darawallada Diiwaangashan (${driverList.length})',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      if (driverList.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Center(
                            child: Column(
                              children: [
                                const Icon(Icons.two_wheeler_rounded, size: 48, color: AppTheme.textLight),
                                const SizedBox(height: 12),
                                Text(
                                  'Weli darawal ma diiwaangashana. Guji "+ Diiwaangeli Darawal" si aad u ku darto.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: driverList.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final d = driverList[index];
                            final driverId = d['id']?.toString() ?? '';
                            final dName = (d['name'] ?? d['full_name'] ?? 'Darawal').toString();
                            final dPhone = (d['phone'] ?? d['phone_number'] ?? 'N/A').toString();
                            final dStatus = (d['status'] ?? 'active').toString();

                            return ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFDCFCE7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.person_pin_rounded, color: Color(0xFF15803D), size: 20),
                              ),
                              title: Text(
                                dName,
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              subtitle: Text(
                                'Tel: $dPhone',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      dStatus.toUpperCase(),
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF15803D),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                    tooltip: 'Tirtir Darawalka',
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Tirtir Darawalka'),
                                          content: Text('Ma ziirtaa inaad tirtirto darawalka "$dName"?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx, false),
                                              child: const Text('Ka noqo'),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                              onPressed: () => Navigator.pop(ctx, true),
                                              child: const Text('Tirtir', style: TextStyle(color: Colors.white)),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirm == true && driverId.isNotEmpty) {
                                        try {
                                          final client = SupabaseService.instance.client;
                                          if (client != null && SupabaseService.instance.isInitialized) {
                                            await client.from('drivers').delete().eq('id', driverId);
                                          }
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Darawalka waa la tirtiray!'),
                                                backgroundColor: Color(0xFF15803D),
                                              ),
                                            );
                                          }
                                          _fetchDrivers();
                                          setState(() {});
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Cillad: $e'), backgroundColor: Colors.red),
                                            );
                                          }
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _manualDriversList = [];

  Future<void> _fetchDrivers() async {
    try {
      final client = SupabaseService.instance.client;
      if (client != null && SupabaseService.instance.isInitialized) {
        final res = await client.from('drivers').select();
        if (res is List && mounted) {
          setState(() {
            _manualDriversList = List<Map<String, dynamic>>.from(res);
          });
        }
      }
    } catch (_) {}
  }

  Widget _buildDriverKpiCard(String label, String value, IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
              ),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddDriverDialog(BuildContext context) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_add_rounded, color: Color(0xFF15803D)),
              ),
              const SizedBox(width: 12),
              Text(
                'Diiwaangeli Darawal Cusub',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Magaca Darawalka',
                    hintText: 'e.g. Maxamed Cali',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Nambarka Taleefanka',
                    hintText: 'e.g. 615001122 ama +252615001122',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('Ka noqo', style: GoogleFonts.plusJakartaSans(color: Colors.grey.shade700)),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final rawPhone = phoneController.text.trim();

                if (name.isEmpty || rawPhone.isEmpty) return;

                final phone = rawPhone.startsWith('+') ? rawPhone : '+252$rawPhone';

                try {
                  final client = SupabaseService.instance.client;
                  if (client != null && SupabaseService.instance.isInitialized) {
                    await client.from('drivers').insert({
                      'name': name,
                      'phone': phone,
                      'status': 'active',
                    });
                  }

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Darawalka "$name" si guul leh ayaa loo diiwaangeliyay!'),
                        backgroundColor: const Color(0xFF15803D),
                      ),
                    );
                  }

                  _fetchDrivers();
                  setState(() {});
                  Navigator.pop(dialogCtx);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Cillad ayaa dhacday: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF15803D),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                'Kaydi Darawalka',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPharmacyOrderPanel(BuildContext context) {
    final appState = context.watch<AppState>();
    final allOrders = appState.orders;
    final allItems = appState.orderItems;

    final pendingCount = allOrders
        .where((o) => o['status'] == 'Pending')
        .length;

    List<Map<String, dynamic>> filteredOrders = allOrders;
    if (_selectedOrderStatusFilter != 'All') {
      filteredOrders = allOrders
          .where(
            (o) => (o['status'] ?? 'Pending') == _selectedOrderStatusFilter,
          )
          .toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Pharmacy Order Panel (Real-time)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF10B981).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '🟢 Live Connected',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage pharmacy orders, prescriptions, and deliveries in real time',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),

            if (pendingCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notifications_active_rounded,
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '🔔 New Orders ($pendingCount)',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),

        const SizedBox(height: 24),

        // Status Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children:
                [
                  'All',
                  'Pending',
                  'Accepted',
                  'Preparing',
                  'Ready',
                  'Out for Delivery',
                  'Delivered',
                  'Cancelled',
                ].map((status) {
                  final isSelected = _selectedOrderStatusFilter == status;
                  int count = 0;
                  if (status == 'All') {
                    count = allOrders.length;
                  } else {
                    count = allOrders
                        .where((o) => (o['status'] ?? 'Pending') == status)
                        .length;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text('$status ($count)'),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _selectedOrderStatusFilter = status;
                          });
                        }
                      },
                      selectedColor: AppTheme.primaryColor,
                      backgroundColor: Colors.white,
                      labelStyle: GoogleFonts.plusJakartaSans(
                        color: isSelected ? Colors.white : AppTheme.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),

        const SizedBox(height: 20),

        // Active Driver Deliveries Section
        Builder(
          builder: (context) {
            final activeDriverOrders = allOrders.where((o) {
              final st = (o['status'] ?? '').toString();
              return st == 'Out for Delivery' || st == 'On The Way';
            }).toList();

            if (activeDriverOrders.isNotEmpty && (_selectedOrderStatusFilter == 'All' || _selectedOrderStatusFilter == 'Out for Delivery')) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFDCFCE7), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFF15803D),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Driver Active Deliveries (Hawlaha Darawallada Hal-ka-mid ah)',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF15803D),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF15803D),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${activeDriverOrders.length}',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...activeDriverOrders.map((o) => _buildDriverActiveTasksCard(context, o, allItems)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),

        // Orders List Container
        if (filteredOrders.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.shopping_bag_outlined,
                  size: 48,
                  color: AppTheme.textLight,
                ),
                const SizedBox(height: 12),
                Text(
                  'Majiraan wax dalab ah oo ku jira "$_selectedOrderStatusFilter"',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1.2),
                1: FlexColumnWidth(1.5),
                2: FlexColumnWidth(1.1),
                3: FlexColumnWidth(1.0),
                4: FlexColumnWidth(1.0),
                5: FlexColumnWidth(1.1),
                6: FlexColumnWidth(1.2),
                7: FlexColumnWidth(1.1),
              },
              children: [
                // Table Header
                TableRow(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  children: [
                    _buildTableHeaderCell('Order #'),
                    _buildTableHeaderCell('Patient Name'),
                    _buildTableHeaderCell('District'),
                    _buildTableHeaderCell('Total'),
                    _buildTableHeaderCell('Payment'),
                    _buildTableHeaderCell('Status'),
                    _buildTableHeaderCell('Time'),
                    _buildTableHeaderCell('Action'),
                  ],
                ),
                // Table Rows
                ...filteredOrders.map((order) {
                  final orderNum = order['order_number']?.toString() ?? '#ORD';
                  final patientName =
                      order['patient_name']?.toString() ?? 'Patient';
                  String rawDistrict = order['district']?.toString() ?? '';
                  if (rawDistrict.isEmpty || rawDistrict == 'Medicines & Skincare' || rawDistrict == 'Pharmacy') {
                    final addr = (order['delivery_address'] ?? order['address'] ?? order['notes'] ?? order['reason_for_visit'] ?? '').toString();
                    if (addr.contains(',')) {
                      final parts = addr.split(',');
                      if (parts.length >= 2) {
                        rawDistrict = parts[parts.length - 2].trim();
                      } else if (parts.isNotEmpty) {
                        rawDistrict = parts[0].trim();
                      }
                    }
                  }
                  if (rawDistrict.isEmpty || rawDistrict == 'Medicines & Skincare' || rawDistrict == 'Pharmacy') {
                    rawDistrict = 'Hodan';
                  }
                  final district = rawDistrict;
                  final total =
                      (order['total_amount'] as num?)?.toDouble() ?? 0.0;
                  final payMethod =
                      order['payment_method']?.toString() ?? 'EVC Plus';
                  final payStatus =
                      order['payment_status']?.toString() ?? 'Paid';
                  final status = order['status']?.toString() ?? 'Pending';
                  final createdAt = order['created_at']?.toString() ?? '';

                  return TableRow(
                    children: [
                      _buildTableCell(orderNum, isBold: true),
                      _buildTableCell(patientName),
                      _buildTableCell(district),
                      _buildTableCell(
                        '\$${total.toStringAsFixed(2)}',
                        isBold: true,
                      ),
                      _buildTableCell('$payMethod ($payStatus)'),
                      _buildStatusCell(status),
                      _buildTableCell(
                        createdAt.length > 10
                            ? createdAt.substring(11, 16)
                            : 'Today',
                      ),
                      TableCell(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: ElevatedButton(
                            onPressed: () => _showPharmacyOrderDetailsModal(
                              context,
                              order,
                              allItems,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            child: Text(
                              'View Order',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }
}

class CarePlusLineChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paintBlue = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintGreen = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF2563EB).withOpacity(0.20),
        const Color(0xFF2563EB).withOpacity(0.0),
      ],
    );

    // Points for Blue Line (Appointments)
    final bluePoints = [
      Offset(0, size.height * 0.55),
      Offset(size.width * 0.16, size.height * 0.40),
      Offset(size.width * 0.33, size.height * 0.36),
      Offset(size.width * 0.50, size.height * 0.15),
      Offset(size.width * 0.66, size.height * 0.28),
      Offset(size.width * 0.83, size.height * 0.28),
      Offset(size.width, size.height * 0.45),
    ];

    // Points for Green Line (Completed)
    final greenPoints = [
      Offset(0, size.height * 0.80),
      Offset(size.width * 0.16, size.height * 0.70),
      Offset(size.width * 0.33, size.height * 0.68),
      Offset(size.width * 0.50, size.height * 0.52),
      Offset(size.width * 0.66, size.height * 0.60),
      Offset(size.width * 0.83, size.height * 0.58),
      Offset(size.width, size.height * 0.72),
    ];

    // Path Blue
    final pathBlue = Path()..moveTo(bluePoints[0].dx, bluePoints[0].dy);
    for (int i = 0; i < bluePoints.length - 1; i++) {
      final p1 = bluePoints[i];
      final p2 = bluePoints[i + 1];
      final controlP1 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p1.dy);
      final controlP2 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p2.dy);
      pathBlue.cubicTo(
        controlP1.dx,
        controlP1.dy,
        controlP2.dx,
        controlP2.dy,
        p2.dx,
        p2.dy,
      );
    }

    // Path Fill Blue
    final pathFill = Path.from(pathBlue)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = fillGradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      )
      ..style = PaintingStyle.fill;

    canvas.drawPath(pathFill, fillPaint);
    canvas.drawPath(pathBlue, paintBlue);

    // Path Green
    final pathGreen = Path()..moveTo(greenPoints[0].dx, greenPoints[0].dy);
    for (int i = 0; i < greenPoints.length - 1; i++) {
      final p1 = greenPoints[i];
      final p2 = greenPoints[i + 1];
      final controlP1 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p1.dy);
      final controlP2 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p2.dy);
      pathGreen.cubicTo(
        controlP1.dx,
        controlP1.dy,
        controlP2.dx,
        controlP2.dy,
        p2.dx,
        p2.dy,
      );
    }
    canvas.drawPath(pathGreen, paintGreen);

    // Draw Dots on Blue Line
    final dotPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;
    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    for (var pt in bluePoints) {
      canvas.drawCircle(pt, 5, dotPaint);
      canvas.drawCircle(pt, 2.5, whitePaint);
    }

    // Draw Dots on Green Line
    final greenDotPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.fill;
    for (var pt in greenPoints) {
      canvas.drawCircle(pt, 4, greenDotPaint);
      canvas.drawCircle(pt, 2, whitePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SparklineChartPainter extends CustomPainter {
  final Color color;
  SparklineChartPainter({this.color = const Color(0xFF10B981)});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final path = Path();
    final w = size.width;
    final h = size.height;

    path.moveTo(0, h * 0.75);
    path.cubicTo(w * 0.25, h * 0.90, w * 0.35, h * 0.20, w * 0.55, h * 0.45);
    path.cubicTo(w * 0.70, h * 0.65, w * 0.85, h * 0.10, w, h * 0.15);

    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withOpacity(0.35),
          color.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}