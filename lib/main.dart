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
import 'screens/auth/login_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/driver/driver_portal_screen.dart';

import 'services/push_notification_service.dart';

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
    await PushNotificationService.instance.initialize();
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
          bool isUserAuth = false;
          try {
            isUserAuth = appState.isLoggedIn ||
                appState.currentUser != null ||
                (FirebaseAuth.instance.currentUser != null) ||
                (SupabaseService.instance.isInitialized &&
                    SupabaseService.instance.client?.auth.currentSession != null);
          } catch (e) {
            debugPrint('Auth check error: $e');
            isUserAuth = false;
          }

          final Widget patientDefaultScreen = isUserAuth
              ? const MainPatientLayout()
              : (appState.hasSeenOnboarding
                  ? const LoginScreen()
                  : const OnboardingScreen());

          return MaterialApp(
            title: 'Nasiib Hospital',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.themeData,
            onGenerateRoute: (settings) {
              final Uri uri = Uri.parse(settings.name ?? '');
              final String path = uri.path.toLowerCase();
              final String basePath = kIsWeb ? Uri.base.path.toLowerCase() : '';

              if (path.contains('/driver') || basePath.contains('/driver')) {
                return MaterialPageRoute(
                  builder: (_) => const DriverPortalScreen(),
                  settings: settings,
                );
              }

              if (path.contains('/patient') || basePath.contains('/patient')) {
                return MaterialPageRoute(
                  builder: (_) => patientDefaultScreen,
                  settings: settings,
                );
              }

              if (kIsWeb || path.contains('/admin') || basePath.contains('/admin')) {
                return MaterialPageRoute(
                  builder: (_) => const AdminDashboardScreen(),
                  settings: settings,
                );
              }

              return MaterialPageRoute(
                builder: (_) => patientDefaultScreen,
                settings: settings,
              );
            },
            routes: {
              '/driver': (context) => const DriverPortalScreen(),
              '/admin': (context) => const AdminDashboardScreen(),
              '/patient': (context) => patientDefaultScreen,
            },
          );
        },
      ),
    );
  }
}
