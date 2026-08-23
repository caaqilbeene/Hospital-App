import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseAuthService {
  static final FirebaseAuthService instance = FirebaseAuthService._internal();
  FirebaseAuthService._internal();

  bool isInitialized = false;

  Future<void> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      isInitialized = true;
      debugPrint("Firebase Auth Service initialized successfully.");
    } catch (e) {
      debugPrint("Firebase Auth initialization notice: $e");
    }
  }

  // Send OTP with real Firebase verifyPhoneNumber
  Future<void> sendOtp({
    required String phoneNumber,
    required Function(String errorMsg) onFailed,
    required Function(String verificationId) onCodeSent,
  }) async {
    try {
      if (kIsWeb) {
        final confirmationResult =
            await FirebaseAuth.instance.signInWithPhoneNumber(phoneNumber);
        onCodeSent(confirmationResult.verificationId);
      } else {
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: phoneNumber,
          verificationCompleted: (PhoneAuthCredential credential) async {
            await FirebaseAuth.instance.signInWithCredential(credential);
          },
          verificationFailed: (FirebaseAuthException e) {
            debugPrint("Firebase verificationFailed: ${e.code} - ${e.message}");
            onFailed(e.message ?? e.toString());
          },
          codeSent: (String verificationId, int? resendToken) {
            debugPrint("Firebase codeSent: verificationId=$verificationId");
            onCodeSent(verificationId);
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            debugPrint("Firebase codeAutoRetrievalTimeout: $verificationId");
          },
        );
      }
    } catch (e) {
      debugPrint("Firebase sendOtp error: $e");
      onFailed(e.toString());
    }
  }

  // Verify OTP with real PhoneAuthProvider credential
  Future<bool> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      if (verificationId.isEmpty) {
        debugPrint("Error: Verification ID is empty");
        return false;
      }

      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      return userCredential.user != null;
    } catch (e) {
      debugPrint("Firebase verifyOtp error: $e");
      return false;
    }
  }
}

