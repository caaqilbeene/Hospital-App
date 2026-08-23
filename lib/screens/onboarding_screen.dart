import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../services/app_state.dart';
import '../widgets/network_or_asset_image.dart';
import 'auth/login_screen.dart';

// ====================================================================================
// 🎯 MEESHA SAWIRKA ONBOARDING-KA LAGU BADALAYO:
// 🎯 Qor magaca sawirka aad ku shubtay folder-ka 'assets/images/'
// 🎯 Tusaale: 'onboarding.png' ama 'doctor.jpg' ama 'assets/images/sawir.png'
// ====================================================================================
const String ONBOARDING_IMAGE_NAME = 'sawir.png';
// ====================================================================================

String _resolveAssetOrUrl(String input, String fallback) {
  final clean = input.trim();
  if (clean.isEmpty) return fallback;
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

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final String finalImageUrl = _resolveAssetOrUrl(
      ONBOARDING_IMAGE_NAME,
      appState.hospitalInfo.bannerUrl,
    );

    return Scaffold(
      backgroundColor: const Color(
        0xFFD5F0ED,
      ), // Soft teal background matching Image 4
      body: SafeArea(
        top: false,
        bottom:
            false, // Ensures the white container extends all the way to the bottom
        child: Column(
          children: [
            // Top Doctor Image Area (Fitted beautifully with smooth curved bottom)
            Expanded(
              flex: 6,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(32),
                      ),
                      child: NetworkOrAssetImage(
                        imageUrl: finalImageUrl,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom White Rounded Card Container (Matching Image 4)
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                left: 28,
                right: 28,
                top: 36,
                bottom:
                    24 +
                    MediaQuery.of(
                      context,
                    ).padding.bottom, // Safe padding for bottom navigation bar
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Find the best doctors\nin your vicinity',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'With the help of our intelligent algorithms, now locate the best doctors around your vicinity at total ease with your account',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Carousel Indicator Pill
                  Container(
                    width: 24,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Next Green Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Next',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
