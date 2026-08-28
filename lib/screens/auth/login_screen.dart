import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/app_theme.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/somali_phone_formatter.dart';
import '../../widgets/network_or_asset_image.dart';
import 'otp_screen.dart';
import 'signup_screen.dart';

// ====================================================================================
// 🎯 MEESHA SAWIRKA / LOGO-GA LAGU BADALAYO (LOGIN SCREEN):
// 🎯 Haddii aad rabto inaad badasho sawirka logo-ga, kaliya halkan ku qor magaca sawirka:
// ====================================================================================
const String LOGIN_LOGO_IMAGE_NAME = 'images/logo.jpeg';
// ====================================================================================

String _resolveLoginAsset(String input) {
  final clean = input.trim();
  if (clean.startsWith('http://') ||
      clean.startsWith('https://') ||
      clean.startsWith('data:')) {
    return clean;
  }
  if (clean.startsWith('assets/')) {
    return clean;
  }
  return 'assets/$clean';
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final logoPath = _resolveLoginAsset(LOGIN_LOGO_IMAGE_NAME);

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
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo / Brand Icon Header (Height 100, Width 100, BoxFit.contain, transparent)
              Center(
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: NetworkOrAssetImage(
                    imageUrl: logoPath,
                    width: 100,
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Nasiib Hospital',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Welcome to Nasiib Hospital.\nPlease enter your phone number.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 36),

              Text(
                'Phone Number',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.phone_rounded,
                    color: AppTheme.primaryColor,
                  ),
                  hintText: '+252 61 XXXXXXX',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: const Color(0xFF94A3B8),
                  ),
                  fillColor: const Color(0xFFF8FAFC),
                  filled: true,
                ),
              ),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () async {
                    if (_isLoading) return;

                    final rawPhone = _phoneController.text.trim();

                    // 1. Empty Phone Check
                    if (rawPhone.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter your phone number.'),
                          backgroundColor: AppTheme.primaryColor,
                        ),
                      );
                      return;
                    }

                    // 2. Extract base digits and build 4 exact variants
                    String digits = rawPhone.replaceAll(RegExp(r'\D'), '');
                    if (digits.startsWith('252') && digits.length >= 12) {
                      digits = digits.substring(3);
                    }
                    if (digits.startsWith('0') && digits.length >= 10) {
                      digits = digits.substring(1);
                    }

                    if (digits.length < 7) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a valid phone number.'),
                          backgroundColor: AppTheme.primaryColor,
                        ),
                      );
                      return;
                    }

                    final String vBase = digits;
                    final String vZero = '0$digits';
                    final String v252 = '252$digits';
                    final String vPlus252 = '+252$digits';

                    final fullE164Number = vPlus252;
                    final List<String> possibleFormats = [
                      vBase,
                      vZero,
                      v252,
                      vPlus252,
                    ].toSet().toList();

                    setState(() => _isLoading = true);

                    // 2. Pre-Auth Patient Existence Check across Supabase & Firestore
                    bool exists = false;

                    try {
                      final client = SupabaseService.instance.client;
                      if (client != null && SupabaseService.instance.isInitialized) {
                        try {
                          final supaCheck = await client
                              .from('patients')
                              .select('id')
                              .or(
                                '${possibleFormats.map((f) => 'phone_number.eq."$f"').join(',')},${possibleFormats.map((f) => 'phone.eq."$f"').join(',')}',
                              )
                              .maybeSingle()
                              .timeout(const Duration(seconds: 3));
                          if (supaCheck != null) exists = true;
                        } catch (e) {
                          debugPrint("Supabase existence check notice: $e");
                        }
                      }
                    } catch (e) {
                      debugPrint("Supabase pre-auth check exception: $e");
                    }

                    // Fallback to Firestore users collection check
                    if (!exists) {
                      try {
                        for (final id in possibleFormats) {
                          final doc = await FirebaseFirestore.instance
                              .collection('users')
                              .doc(id)
                              .get()
                              .timeout(const Duration(seconds: 2));
                          if (doc.exists && doc.data() != null && doc.data()!.isNotEmpty) {
                            exists = true;
                            break;
                          }
                        }

                        if (!exists) {
                          final q1 = await FirebaseFirestore.instance
                              .collection('users')
                              .where('phoneNumber', whereIn: possibleFormats)
                              .limit(1)
                              .get()
                              .timeout(const Duration(seconds: 2));
                          if (q1.docs.isNotEmpty) exists = true;
                        }
                      } catch (e) {
                        debugPrint("Firestore fallback check notice: $e");
                      }
                    }

                    if (!exists) {
                      if (!mounted) return;
                      setState(() => _isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'This account is not registered. Please sign up first.',
                          ),
                          backgroundColor: AppTheme.primaryColor,
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return;
                    }

                    // 4. Real Firebase Phone Verification
                    await FirebaseAuthService.instance.sendOtp(
                      phoneNumber: fullE164Number,
                      onFailed: (errorMsg) {
                        if (!mounted) return;
                        setState(() => _isLoading = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Firebase OTP failed: $errorMsg'),
                            backgroundColor: AppTheme.primaryColor,
                          ),
                        );
                      },
                      onCodeSent: (verificationId) {
                        if (!mounted) return;
                        setState(() => _isLoading = false);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OtpScreen(
                              phoneNumber: fullE164Number,
                              verificationId: verificationId,
                            ),
                          ),
                        );
                      },
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Send OTP',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 36),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Don\'t have an account? ',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignupScreen()),
                      );
                    },
                    child: Text(
                      'Sign Up',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
