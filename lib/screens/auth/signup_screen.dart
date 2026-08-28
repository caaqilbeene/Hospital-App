import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_theme.dart';
import '../../services/email_otp_service.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/somali_phone_formatter.dart';
import '../../widgets/network_or_asset_image.dart';
import 'otp_screen.dart';

// ====================================================================================
// 🎯 MEESHA LOGO-GA / SAWIRKA SIGNUP-KA LAGU BADALAYO:
// 🎯 Qor magaca sawirka aad ku shubtay folder-ka 'assets/images/'
// 🎯 Tusaale: 'logo.png' ama 'signup_logo.png' ama 'assets/images/logo.png'
// ====================================================================================
// ====================================================================================
// 🎯 MEESHA SAWIRKA / LOGO-GA LAGU BADALAYO (SIGNUP SCREEN):
// 🎯 Haddii aad rabto inaad badasho sawirka logo-ga, kaliya halkan ku qor magaca sawirka:
// ====================================================================================
const String SIGNUP_LOGO_IMAGE_NAME = 'images/logo.jpeg';
// ====================================================================================

String _resolveSignupAsset(String input) {
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

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final logoPath = _resolveSignupAsset(SIGNUP_LOGO_IMAGE_NAME);

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
          'Create Account',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: NetworkOrAssetImage(
                    imageUrl: _resolveSignupAsset(SIGNUP_LOGO_IMAGE_NAME),
                    width: 100,
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Full Name Input
              Text(
                'Full Name',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [TitleCaseTextInputFormatter()],
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.person_outline_rounded,
                    color: AppTheme.primaryColor,
                  ),
                  hintText: 'Full Name',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: const Color(0xFF94A3B8),
                  ),
                  fillColor: const Color(0xFFF8FAFC),
                  filled: true,
                ),
              ),
              const SizedBox(height: 20),

              // Phone Number Input
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
              const SizedBox(height: 20),

              // Email Input (Saved for notifications)
              Text(
                'Email Address',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.email_outlined,
                    color: AppTheme.primaryColor,
                  ),
                  hintText: 'patient@example.com',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: const Color(0xFF94A3B8),
                  ),
                  fillColor: const Color(0xFFF8FAFC),
                  filled: true,
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () async {
                    if (_isLoading) return;

                    final rawName = _nameController.text.trim();
                    final name = rawName
                        .split(' ')
                        .map(
                          (w) => w.isEmpty
                              ? ''
                              : w[0].toUpperCase() + w.substring(1),
                        )
                        .join(' ');
                    final rawPhone = _phoneController.text.trim();
                    final email = _emailController.text.trim();

                    // 1. Empty Name Validation
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter your full name.'),
                          backgroundColor: AppTheme.primaryColor,
                        ),
                      );
                      return;
                    }

                    // 2. Empty Phone Validation
                    if (rawPhone.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter your phone number.'),
                          backgroundColor: AppTheme.primaryColor,
                        ),
                      );
                      return;
                    }

                    // 3. Email Format & Validity Validation
                    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    if (email.isEmpty || !emailRegex.hasMatch(email)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a valid email address (e.g. name@gmail.com).'),
                          backgroundColor: AppTheme.primaryColor,
                        ),
                      );
                      return;
                    }

                    // 4. Extract base digits and build 4 exact variants
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

                    // 2. Check if account already exists strictly in Supabase public.patients
                    bool alreadyExists = false;
                    try {
                      final client = SupabaseService.instance.client;
                      if (client != null &&
                          SupabaseService.instance.isInitialized) {
                        try {
                          final supaCheck = await client
                              .from('patients')
                              .select('id')
                              .inFilter('phone_number', possibleFormats)
                              .limit(1)
                              .maybeSingle();
                          if (supaCheck != null) alreadyExists = true;
                        } catch (_) {}

                        if (!alreadyExists) {
                          try {
                            final supaCheck2 = await client
                                .from('patients')
                                .select('id')
                                .inFilter('phone', possibleFormats)
                                .limit(1)
                                .maybeSingle();
                            if (supaCheck2 != null) alreadyExists = true;
                          } catch (_) {}
                        }
                      }
                    } catch (e) {
                      debugPrint("Supabase signup check error: $e");
                    }

                    if (alreadyExists) {
                      if (!mounted) return;
                      setState(() => _isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'This phone number is already registered. Please log in or use another number.',
                          ),
                          backgroundColor: AppTheme.primaryColor,
                        ),
                      );
                      return;
                    }

                    // Send 6-digit Email Verification OTP directly to client's Gmail
                    try {
                      await EmailOtpService.instance.sendOtpEmail(
                        email: email,
                        recipientName: name,
                      );

                      if (!mounted) return;
                      setState(() => _isLoading = false);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OtpScreen(
                            phoneNumber: fullE164Number,
                            verificationId: 'EMAIL_OTP',
                            name: name,
                            email: email,
                            isEmailOtp: true,
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      setState(() => _isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to send verification code to $email: $e'),
                          backgroundColor: AppTheme.primaryColor,
                        ),
                      );
                    }
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
                          'Create Account',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TitleCaseTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final String text = newValue.text;
    final List<String> words = text.split(' ');
    final List<String> capitalizedWords = words.map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1);
    }).toList();

    final String result = capitalizedWords.join(' ');

    return newValue.copyWith(
      text: result,
      selection: TextSelection.collapsed(
        offset: newValue.selection.end.clamp(0, result.length),
      ),
    );
  }
}
