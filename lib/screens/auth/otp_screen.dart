import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../config/app_theme.dart';
import '../../services/app_state.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/network_or_asset_image.dart';
import '../patient/main_patient_layout.dart';

// ====================================================================================
// 🎯 MEESHA SAWIRKA / LOGO-GA LAGU BADALAYO (OTP SCREEN):
// 🎯 Haddii aad rabto inaad badasho sawirka logo-ga, kaliya halkan ku qor magaca sawirka:
// ====================================================================================
const String OTP_LOGO_IMAGE_NAME = 'images/logo.jpeg';
// ====================================================================================

String _resolveOtpAsset(String input) {
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

class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final String? name;
  final String? email;
  final bool isEmailOtp;
  const OtpScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.name,
    this.email,
    this.isEmailOtp = false,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  late String _currentVerificationId;
  int _secondsRemaining = 59;
  Timer? _timer;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _currentVerificationId = widget.verificationId;
    _startTimer();
  }

  void _startTimer() {
    _secondsRemaining = 59;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _verifyAndProceed() async {
    if (_isVerifying) return;

    final code = _controllers.map((c) => c.text.trim()).join();
    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter all 6 digits of the OTP code!'),
        ),
      );
      return;
    }

    setState(() => _isVerifying = true);

    bool success = false;
    String? authUserId;

    if (widget.isEmailOtp && widget.email != null && widget.email!.isNotEmpty) {
      try {
        success = await SupabaseService.instance.verifyEmailOtp(
          widget.email!,
          code,
        );
        authUserId = SupabaseService.instance.client?.auth.currentUser?.id;
      } catch (e) {
        debugPrint("[EMAIL_OTP_VERIFY] Error: $e");
        success = false;
      }
    } else {
      success = await FirebaseAuthService.instance.verifyOtp(
        verificationId: _currentVerificationId,
        smsCode: code,
      );
      authUserId = FirebaseAuth.instance.currentUser?.uid;
    }

    setState(() => _isVerifying = false);

    if (success) {
      if (!mounted) return;
      final String uid = authUserId ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
      
      // Ensure normalized phone in E.164 (+252...)
      String normPhone = widget.phoneNumber.trim();
      if (normPhone.isNotEmpty && !normPhone.startsWith('+')) {
        String digits = normPhone.replaceAll(RegExp(r'\D'), '');
        if (digits.startsWith('252')) {
          digits = digits.substring(3);
        } else if (digits.startsWith('0')) {
          digits = digits.substring(1);
        }
        normPhone = '+252$digits';
      }

      // Strict OTP Gate: If signing up, create user profile ONLY after successful OTP verification
      if (widget.name != null && widget.name!.isNotEmpty) {
        final String name = widget.name!.trim().isNotEmpty ? widget.name!.trim() : 'Patient';
        final String email = widget.email ?? '';

        try {
          final client = SupabaseService.instance.client;
          if (client != null && SupabaseService.instance.isInitialized) {
            await client.from('patients').upsert({
              'id': uid,
              'user_id': uid,
              'full_name': name,
              'phone_number': normPhone.isNotEmpty ? normPhone : email,
              'phone': normPhone,
              'email': email,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            }).select();
          }
        } catch (e) {
          debugPrint('SUPABASE_INSERT_ERROR: $e');
        }

        context.read<AppState>().registerUser(
          name: name,
          phone: normPhone.isNotEmpty ? normPhone : email,
          email: email,
        );
      } else {
        await context.read<AppState>().loadPatientProfileFromSupabase(normPhone.isNotEmpty ? normPhone : widget.email);
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainPatientLayout()),
        (route) => false,
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid or expired OTP code! Please check and try again.'),
          backgroundColor: AppTheme.primaryColor,
        ),
      );
    }
  }

  void _resendOtp() async {
    if (_secondsRemaining > 0) return;
    
    _startTimer();
    
    if (widget.isEmailOtp && widget.email != null && widget.email!.isNotEmpty) {
      try {
        await SupabaseService.instance.sendEmailOtp(widget.email!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('A new OTP code has been sent to ${widget.email}'),
              backgroundColor: AppTheme.primaryColor,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to resend Email OTP: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      await FirebaseAuthService.instance.sendOtp(
        phoneNumber: widget.phoneNumber,
        onCodeSent: (newVerificationId) {
          setState(() {
            _currentVerificationId = newVerificationId;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('A new OTP code has been sent to your phone.'),
                backgroundColor: AppTheme.primaryColor,
              ),
            );
          }
        },
        onFailed: (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to resend SMS: $error'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Colors.white, // Clean white background as requested (no dots)
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
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 12),

              // Logo / Brand Icon Header (Matching Login and Signup)
              Center(
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: NetworkOrAssetImage(
                    imageUrl: _resolveOtpAsset(OTP_LOGO_IMAGE_NAME),
                    width: 100,
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              const SizedBox(height: 16),
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

              const SizedBox(height: 32),

              // White Card Box (Matching Image 5)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 28,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFF0F3F5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'Enter Your OTP Code',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.isEmailOtp && widget.email != null && widget.email!.isNotEmpty
                          ? 'A 6-digit verification code has been sent to your email:\n${widget.email}'
                          : 'A 6-digit code has been sent to\n${widget.phoneNumber}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // 6 Box Input Row (Matching Image 5)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) {
                        return SizedBox(
                          width: 44,
                          height: 52,
                          child: TextField(
                            controller: _controllers[index],
                            focusNode: _focusNodes[index],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 1,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              filled: true,
                              fillColor: const Color(0xFFF3F4F6),
                              contentPadding: EdgeInsets.zero,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (val) {
                              if (val.isNotEmpty && index < 5) {
                                _focusNodes[index + 1].requestFocus();
                              } else if (val.isEmpty && index > 0) {
                                _focusNodes[index - 1].requestFocus();
                              }
                              if (_controllers.every(
                                (c) => c.text.isNotEmpty,
                              )) {
                                _verifyAndProceed();
                              }
                            },
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 20),

                    // Resend Code & Need Help? Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            if (_secondsRemaining == 0) {
                              _startTimer();
                              await FirebaseAuthService.instance.sendOtp(
                                phoneNumber: widget.phoneNumber,
                                onFailed: (errorMsg) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Resend failed: $errorMsg',
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                },
                                onCodeSent: (newVerificationId) {
                                  if (mounted) {
                                    setState(() {
                                      _currentVerificationId =
                                          newVerificationId;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'OTP code has been resent!',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              );
                            }
                          },
                          child: Text(
                            'Resend Code',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {},
                          child: Text(
                            'Need Help?',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Progress Slider / Line Timer (Matching Image 5)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: _secondsRemaining / 59,
                        backgroundColor: const Color(0xFFE5E7EB),
                        color: AppTheme.primaryColor,
                        minHeight: 6,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_secondsRemaining}s remaining',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    if (_isVerifying) return;
                    _verifyAndProceed();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Verify & Continue',
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
