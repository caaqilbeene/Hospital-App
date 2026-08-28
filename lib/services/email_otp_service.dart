import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class EmailOtpService {
  static final EmailOtpService instance = EmailOtpService._internal();
  EmailOtpService._internal();

  final Map<String, _OtpData> _activeOtps = {};

  String generateOtp(String email) {
    final cleanEmail = email.trim().toLowerCase();
    final random = Random.secure();
    final code = (100000 + random.nextInt(900000)).toString();
    _activeOtps[cleanEmail] = _OtpData(
      code: code,
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
    debugPrint("[EMAIL_OTP] Generated 6-digit OTP for $cleanEmail: $code");
    return code;
  }

  bool verifyOtp(String email, String inputCode) {
    final cleanEmail = email.trim().toLowerCase();
    final record = _activeOtps[cleanEmail];

    if (record == null) {
      debugPrint("[EMAIL_OTP] No OTP record found for $cleanEmail");
      return false;
    }

    if (DateTime.now().isAfter(record.expiresAt)) {
      debugPrint("[EMAIL_OTP] OTP for $cleanEmail has expired.");
      _activeOtps.remove(cleanEmail);
      return false;
    }

    if (record.code == inputCode.trim()) {
      debugPrint("[EMAIL_OTP] OTP verified successfully for $cleanEmail!");
      _activeOtps.remove(cleanEmail);
      return true;
    }

    debugPrint("[EMAIL_OTP] Mismatch: expected ${record.code}, got $inputCode");
    return false;
  }

  Future<bool> sendOtpEmail({
    required String email,
    required String recipientName,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final code = generateOtp(cleanEmail);

    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #f8fafc; margin: 0; padding: 20px; }
    .card { max-width: 500px; margin: 0 auto; background: #ffffff; border-radius: 16px; padding: 32px 24px; border: 1px solid #e2e8f0; text-align: center; box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
    .header { font-size: 24px; font-weight: 800; color: #0D7C66; margin-bottom: 8px; }
    .subtitle { color: #64748b; font-size: 15px; margin-bottom: 24px; line-height: 1.5; }
    .otp-box { background: #f0fdf4; border: 2px dashed #86efac; border-radius: 12px; padding: 18px 24px; margin: 24px 0; display: inline-block; }
    .otp-code { font-size: 36px; font-weight: 900; letter-spacing: 8px; color: #166534; font-family: monospace; }
    .footer { color: #94a3b8; font-size: 12px; margin-top: 24px; line-height: 1.5; }
  </style>
</head>
<body>
  <div class="card">
    <div class="header">🏥 Nasiib Hospital</div>
    <div class="subtitle">Hello <b>$recipientName</b>,<br>Use the following 6-digit verification code to complete your registration:</div>
    <div class="otp-box">
      <div class="otp-code">$code</div>
    </div>
    <div class="footer">This code will expire in <b>10 minutes</b>.<br>If you did not request this code, please ignore this email.</div>
  </div>
</body>
</html>
''';

    try {
      final fallbackUrl = Uri.parse('https://formsubmit.co/ajax/$cleanEmail');
      await http.post(
        fallbackUrl,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          '_subject': 'Nasiib Hospital - Your OTP Code is $code',
          '_template': 'table',
          'Hospital': 'Nasiib Hospital',
          'Verification Code': code,
          'Message': 'Your Nasiib Hospital verification code is $code. It expires in 10 minutes.',
        }),
      ).timeout(const Duration(seconds: 4));
      debugPrint("[EMAIL_OTP] Direct email dispatch sent to $cleanEmail");
    } catch (e) {
      debugPrint("[EMAIL_OTP] Dispatch exception: $e");
    }

    return true;
  }
}

class _OtpData {
  final String code;
  final DateTime expiresAt;
  _OtpData({required this.code, required this.expiresAt});
}
