import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../services/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _smsReminders = true;
  String _selectedLanguage = 'English';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadPatientProfileFromSupabase();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. ACCOUNT VERIFICATION SECTION
              Text(
                'Account Verification',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEDF2F7)),
                ),
                child: Column(
                  children: [
                    // Phone number row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Phone Number',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    (user?.phoneNumber != null && user!.phoneNumber.isNotEmpty)
                                        ? user.phoneNumber
                                        : 'Not provided',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () {
                                      _showEditFieldDialog(
                                        context,
                                        appState,
                                        title: 'Edit Phone Number',
                                        hint: 'Enter your new phone number',
                                        initialValue: user?.phoneNumber ?? '',
                                        onSave: (val) async {
                                          await appState.updateProfile(
                                            phoneNumber: val,
                                          );
                                        },
                                      );
                                    },
                                    child: const Icon(
                                      Icons.edit_rounded,
                                      color: AppTheme.primaryColor,
                                      size: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: (user?.phoneNumber != null && user!.phoneNumber.isNotEmpty)
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                (user?.phoneNumber != null && user!.phoneNumber.isNotEmpty)
                                    ? Icons.verified_rounded
                                    : Icons.info_outline_rounded,
                                color: (user?.phoneNumber != null && user!.phoneNumber.isNotEmpty)
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFFD97706),
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                (user?.phoneNumber != null && user!.phoneNumber.isNotEmpty)
                                    ? 'Verified'
                                    : 'Unverified',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: (user?.phoneNumber != null && user!.phoneNumber.isNotEmpty)
                                      ? const Color(0xFF15803D)
                                      : const Color(0xFFD97706),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: Color(0xFFEDF2F7)),
                    ),

                    // Email Address row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Email Address',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    (user?.email != null && user!.email.isNotEmpty)
                                        ? user.email
                                        : 'Not provided',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () {
                                      _showEditFieldDialog(
                                        context,
                                        appState,
                                        title: 'Edit Email Address',
                                        hint: 'Enter your new email',
                                        initialValue: user?.email ?? '',
                                        onSave: (val) async {
                                          try {
                                            await appState.updateProfile(email: val);
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('your email was updated.'),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Supabase Error: $e'),
                                                  backgroundColor: AppTheme.errorRed,
                                                ),
                                              );
                                            }
                                            rethrow;
                                          }
                                        },
                                      );
                                    },
                                    child: const Icon(
                                      Icons.edit_rounded,
                                      color: AppTheme.primaryColor,
                                      size: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: (user?.email != null && user!.email.isNotEmpty)
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                (user?.email != null && user!.email.isNotEmpty)
                                    ? Icons.verified_rounded
                                    : Icons.info_outline_rounded,
                                color: (user?.email != null && user!.email.isNotEmpty)
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFFD97706),
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                (user?.email != null && user!.email.isNotEmpty)
                                    ? 'Verified'
                                    : 'Unverified',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: (user?.email != null && user!.email.isNotEmpty)
                                      ? const Color(0xFF15803D)
                                      : const Color(0xFFD97706),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // 2. PREFERENCES SECTION
              Text(
                'Notification Preferences',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEDF2F7)),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      activeThumbColor: AppTheme.primaryColor,
                      title: Text(
                        'Push Notifications',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        'Receive appointment status & chat alerts',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      value: appState.pushNotificationsEnabled,
                      onChanged: (val) {
                        context.read<AppState>().setPushNotificationsEnabled(
                          val,
                        );
                      },
                    ),
                    const Divider(color: Color(0xFFEDF2F7), height: 1),
                    SwitchListTile(
                      activeThumbColor: AppTheme.primaryColor,
                      title: Text(
                        'SMS Reminders',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        'Receive OTP & payment text messages',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      value: _smsReminders,
                      onChanged: (val) {
                        setState(() => _smsReminders = val);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // 3. LANGUAGE SECTION
              Text(
                'App Language',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEDF2F7)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Language / Luqadda',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    DropdownButton<String>(
                      value: _selectedLanguage,
                      underline: const SizedBox(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedLanguage = val);
                        }
                      },
                      items: ['English', 'Somali'].map((lang) {
                        return DropdownMenuItem<String>(
                          value: lang,
                          child: Text(
                            lang,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditFieldDialog(
    BuildContext context,
    AppState appState, {
    required String title,
    required String hint,
    required String initialValue,
    required Future<void> Function(String) onSave,
  }) {
    final controller = TextEditingController(text: initialValue);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final val = controller.text.trim();
                if (val.isNotEmpty) {
                  try {
                    await onSave(val);
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  } catch (_) {
                    // keep dialog open on error
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}
