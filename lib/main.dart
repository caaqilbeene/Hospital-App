import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'config/app_theme.dart';
import 'services/app_state.dart';
import 'services/supabase_service.dart';
import 'services/firebase_auth_service.dart';
import 'screens/patient/main_patient_layout.dart';
import 'screens/onboarding_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Supabase configuration asynchronously
    await SupabaseService.instance.initialize();
  } catch (e) {
    debugPrint('Supabase initialization error: $e');
  }

  try {
    // Initialize Firebase configuration safely
    await FirebaseAuthService.instance.initialize();
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  runApp(const NasiibHospitalApp());
}

class NasiibHospitalApp extends StatelessWidget {
  const NasiibHospitalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => AppState(),
      child: Consumer<AppState>(
        builder: (context, appState, child) {
          final isUserAuth = appState.isLoggedIn &&
              (appState.currentUser != null || FirebaseAuth.instance.currentUser != null);

          return MaterialApp(
            title: 'Nasiib Hospital',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.themeData,
            home: kIsWeb
                ? const AdminDashboardScreen()
                : (isUserAuth
                    ? const MainPatientLayout()
                    : const OnboardingScreen()),
          );
        },
      ),
    );
  }
}
