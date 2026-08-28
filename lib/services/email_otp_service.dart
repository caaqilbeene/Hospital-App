import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class EmailOtpService {
  static final EmailOtpService instance = EmailOtpService._internal();
  EmailOtpService._internal();

  final Map<String, _OtpData> _activeOtps = {};

  final String _gmailUser = 'drmuktarabdullahi0@gmail.com';
  final String _gmailPass = 'gdghntzbjqnbwubx';

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
    .header { font-size: 26px; font-weight: 800; color: #0D7C66; margin-bottom: 8px; }
    .subtitle { color: #475569; font-size: 16px; font-weight: 600; margin-bottom: 6px; }
    .desc { color: #64748b; font-size: 14px; margin-bottom: 24px; line-height: 1.5; }
    .otp-box { background: #f0fdf4; border: 2px dashed #86efac; border-radius: 14px; padding: 20px 28px; margin: 24px 0; display: inline-block; }
    .otp-code { font-size: 38px; font-weight: 900; letter-spacing: 8px; color: #166534; font-family: monospace; }
    .footer { color: #94a3b8; font-size: 12px; margin-top: 24px; line-height: 1.5; }
  </style>
</head>
<body>
  <div class="card">
    <div class="header">🏥 Nasiib Hospital</div>
    <div class="subtitle">Welcome to Nasiib Hospital!</div>
    <div class="desc">Hello <b>$recipientName</b>,<br>Please enter the following 6-digit verification code in the app to complete your account registration:</div>
    <div class="otp-box">
      <div class="otp-code">$code</div>
    </div>
    <div class="footer">This code will expire in <b>10 minutes</b>.<br>If you did not request this code, please ignore this email.</div>
  </div>
</body>
</html>
''';

    try {
      final smtpServer = gmail(_gmailUser, _gmailPass);
      final message = Message()
        ..from = Address(_gmailUser, 'Nasiib Hospital')
        ..recipients.add(cleanEmail)
        ..subject = 'Nasiib Hospital - Your 6-Digit OTP Code is $code'
        ..html = htmlContent;

      final sendReport = await send(message, smtpServer);
      debugPrint("[EMAIL_OTP] Gmail SMTP dispatch SUCCESS: ${sendReport.toString()}");
      return true;
    } catch (e) {
      debugPrint("[EMAIL_OTP] Gmail SMTP dispatch error: $e");
      return true;
    }
  }

  Future<int> sendBroadcastEmail({
    required String subject,
    required String announcementBody,
    required List<String> recipientEmails,
  }) async {
    if (recipientEmails.isEmpty) return 0;
    int sentCount = 0;

    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #f8fafc; margin: 0; padding: 20px; }
    .card { max-width: 550px; margin: 0 auto; background: #ffffff; border-radius: 16px; padding: 32px 24px; border: 1px solid #e2e8f0; box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
    .header { font-size: 24px; font-weight: 800; color: #0D7C66; margin-bottom: 8px; text-align: center; }
    .badge { display: inline-block; background: #e6f4ea; color: #0D7C66; font-size: 12px; font-weight: 700; padding: 4px 12px; border-radius: 20px; margin-bottom: 16px; }
    .title { font-size: 18px; font-weight: 700; color: #0f172a; margin-bottom: 12px; }
    .message-box { background: #f8fafc; border-left: 4px solid #0D7C66; border-radius: 8px; padding: 18px 20px; margin: 20px 0; color: #334155; font-size: 15px; line-height: 1.6; white-space: pre-wrap; }
    .footer { color: #94a3b8; font-size: 12px; margin-top: 28px; line-height: 1.5; text-align: center; border-top: 1px solid #f1f5f9; padding-top: 16px; }
  </style>
</head>
<body>
  <div class="card">
    <div style="text-align: center;">
      <div class="header">🏥 Nasiib Hospital</div>
      <div class="badge">Official Announcement</div>
    </div>
    <div class="title">$subject</div>
    <div class="message-box">$announcementBody</div>
    <div class="footer">
      Waxaa fariintan si rasmi ah kuugu soo diray <b>Nasiib Hospital</b>.<br>
      Mahadsanid inaad dooratay adeegyadayada caafimaad.
    </div>
  </div>
</body>
</html>
''';

    try {
      final smtpServer = gmail(_gmailUser, _gmailPass);
      final validEmails = recipientEmails
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.contains('@') && e.contains('.'))
          .toSet()
          .toList();

      for (final target in validEmails) {
        try {
          final message = Message()
            ..from = Address(_gmailUser, 'Nasiib Hospital')
            ..recipients.add(target)
            ..subject = '🏥 Nasiib Hospital: $subject'
            ..html = htmlContent;

          await send(message, smtpServer);
          sentCount++;
          debugPrint("[BROADCAST_EMAIL] Sent announcement to $target");
        } catch (err) {
          debugPrint("[BROADCAST_EMAIL] Error sending to $target: $err");
        }
      }
    } catch (e) {
      debugPrint("[BROADCAST_EMAIL] SMTP general error: $e");
    }
    return sentCount;
  }
}

class _OtpData {
  final String code;
  final DateTime expiresAt;
  _OtpData({required this.code, required this.expiresAt});
}
