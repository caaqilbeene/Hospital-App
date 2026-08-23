import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../services/app_state.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/image_picker_service.dart';
import '../../widgets/network_or_asset_image.dart';
import '../auth/login_screen.dart';
import 'my_orders_screen.dart';
import 'settings_screen.dart';
import 'appointment_history_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;
    final appointments = appState.appointments;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'My Profile',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await appState.loadPatientProfileFromSupabase();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
            children: [
              // 1. Patient Avatar with Camera Icon Badge Overlay (Tap to change picture)
              Center(
                child: GestureDetector(
                  onTap: () => _showAvatarOptionsBottomSheet(context, appState),
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.primaryLight,
                            width: 4,
                          ),
                        ),
                        child: NetworkOrAssetImage(
                          imageUrl:
                              (user?.avatarUrl != null &&
                                  user!.avatarUrl.isNotEmpty)
                              ? user.avatarUrl
                              : '',

                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          borderRadius: BorderRadius.circular(48),
                        ),
                      ),

                      // Camera Icon Overlay on bottom right
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Patient Name Row with Edit pencil icon (Padded & Flexible to prevent overflow)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        user?.fullName ?? 'Patient',

                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        _showEditNameDialog(
                          context,
                          appState,
                          user?.fullName ?? 'Patient',
                        );
                      },
                      child: const Icon(
                        Icons.edit_rounded,
                        color: AppTheme.primaryColor,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Joined: ${user?.formattedJoinedDate ?? "August 2026"}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),

              const SizedBox(height: 18),

              const SizedBox(height: 18),

              // 3. Patient Profile Navigation Menu Options
              _buildMenuItem(
                context,
                icon: Icons.calendar_today_rounded,
                title: 'My Appointments History',
                subtitle: '${appointments.length} active bookings',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AppointmentHistoryScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuItem(
                context,
                icon: Icons.local_shipping_outlined,
                title: 'My Orders / Live Tracking',
                subtitle: 'Track your orders (Real-time pharmacy status)',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyOrdersScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuItem(
                context,
                icon: Icons.settings_outlined,
                title: 'Settings',
                subtitle: 'Account preferences & notifications',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuItem(
                context,
                icon: Icons.headset_mic_outlined,
                title: 'Help & Support',
                subtitle: 'Nasiib Hospital hotline & chat',
                onTap: () {},
              ),
              const SizedBox(height: 12),

              // Log Out Option
              _buildMenuItem(
                context,
                icon: Icons.logout_rounded,
                title: 'Log Out',
                subtitle: 'Log out of your account',
                isDanger: true,
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: Text(
                          'Log Out',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        content: const Text(
                          'Are you sure you want to log out?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              await context.read<AppState>().logout();
                              if (context.mounted) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LoginScreen(),
                                  ),
                                  (route) => false,
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                            ),
                            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    final iconColor = isDanger ? AppTheme.errorRed : AppTheme.primaryColor;
    final textColor = isDanger ? AppTheme.errorRed : AppTheme.textPrimary;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDF1F5)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 16,
          color: AppTheme.textLight,
        ),
      ),
    );
  }

  void _showEditNameDialog(
    BuildContext context,
    AppState appState,
    String currentName,
  ) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Badalo Magaca / Edit Name',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          content: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Qor magacaaga cusub'),
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
                final newName = controller.text.trim();
                if (newName.isNotEmpty) {
                  try {
                    await appState.updateProfile(fullName: newName);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('your name was updated.'),
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

  Future<void> _pickProfileImage(
    BuildContext context,
    AppState appState,
    ImageSource source,
  ) async {
    try {
      final bytes = await ImagePickerService.pickImageBytes(source: source);
      if (bytes != null && bytes.isNotEmpty) {
        final success = await appState.updateProfile(avatarBytes: bytes);
        if (context.mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Your profile picture was updated'),
                backgroundColor: AppTheme.primaryColor,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sawirka profile-ka waa la shubi waayay.'),
                backgroundColor: AppTheme.errorRed,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("PROFILE IMAGE PICK ERROR: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cilad ayaa dhacday: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    }
  }

  void _showAvatarOptionsBottomSheet(BuildContext context, AppState appState) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Change Profile Picture',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded, color: AppTheme.primaryColor),
                  title: Text('Choose from Gallery', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickProfileImage(context, appState, ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded, color: AppTheme.primaryColor),
                  title: Text('Take a Photo (Camera)', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickProfileImage(context, appState, ImageSource.camera);
                  },
                ),
                if ((appState.currentUser?.avatarUrl ?? '').isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: AppTheme.errorRed),
                    title: Text('Remove Profile Picture', style: GoogleFonts.plusJakartaSans(color: AppTheme.errorRed, fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(ctx);
                      appState.updateProfile(avatarUrl: '');
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }


  void _showAvatarSelector(BuildContext context, AppState appState) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Profile Picture',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAvatarOption(context, appState, ''),

                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    appState.updateProfile(avatarUrl: '');
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile picture removed!'),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.delete_rounded,
                    color: AppTheme.errorRed,
                  ),
                  label: Text(
                    'Delete Profile Picture',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.errorRed,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAvatarOption(
    BuildContext context,
    AppState appState,
    String url,
  ) {
    return GestureDetector(
      onTap: () {
        appState.updateProfile(avatarUrl: url);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your profile picture was updated'),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.network(url, width: 48, height: 48, fit: BoxFit.cover),
      ),
    );
  }
}
