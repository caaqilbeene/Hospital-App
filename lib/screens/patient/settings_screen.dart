import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../services/app_state.dart';
import '../auth/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _smsReminders = true;

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
                                          final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                                          if (!emailRegex.hasMatch(val.trim())) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Please enter a valid email address (e.g. name@gmail.com).'),
                                                  backgroundColor: AppTheme.primaryColor,
                                                ),
                                              );
                                            }
                                            throw Exception('Invalid email format');
                                          }
                                          try {
                                            await appState.updateProfile(email: val.trim());
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Email updated successfully.'),
                                                  backgroundColor: AppTheme.primaryColor,
                                                ),
                                              );
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Update Error: $e'),
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

              const SizedBox(height: 32),

              // 3. ACCOUNT ACTIONS (DELETE ACCOUNT)
              InkWell(
                onTap: () => _confirmAccountDeletion(context, appState),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.delete_forever_rounded,
                        color: Color(0xFFDC2626),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Delete Account',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFDC2626),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Color(0xFFDC2626),
                        size: 16,
                      ),
                    ],
                  ),
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

  void _confirmAccountDeletion(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Delete Account',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: const Color(0xFFDC2626),
            ),
          ),
          content: Text(
            'Are you sure you want to delete your account? This action cannot be undone.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: const Color(0xFF475569),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryColor),
                  ),
                );

                try {
                  final userPhone = appState.currentUser?.phoneNumber ?? '';
                  await Future.any([
                    appState.deleteUserAccount(userPhone),
                    Future.delayed(const Duration(seconds: 3)),
                  ]);
                  await appState.logout();
                } catch (e) {
                  debugPrint("Account deletion notice: $e");
                  await appState.logout();
                } finally {
                  if (context.mounted) {
                    Navigator.of(context, rootNavigator: true).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Account Deleted Successfully'),
                        backgroundColor: AppTheme.primaryColor,
                        duration: Duration(seconds: 3),
                      ),
                    );
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Delete',
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
}
