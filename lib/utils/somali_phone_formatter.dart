import 'package:flutter/services.dart';

/// Custom TextInputFormatter for Somali phone numbers:
/// - If starts with '0' (e.g., 061..., 062..., 068..., 077...): capped strictly at 10 digits.
/// - If starts without '0' (e.g., 61..., 62..., 68..., 77...): capped strictly at 9 digits.
class SomaliPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Retain only numeric digits
    final cleanText = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (cleanText.isEmpty) {
      return newValue.copyWith(text: '');
    }

    final int maxLen = cleanText.startsWith('0') ? 10 : 9;
    if (cleanText.length > maxLen) {
      final truncated = cleanText.substring(0, maxLen);
      return TextEditingValue(
        text: truncated,
        selection: TextSelection.collapsed(offset: truncated.length),
      );
    }

    return TextEditingValue(
      text: cleanText,
      selection: TextSelection.collapsed(offset: cleanText.length),
    );
  }
}

/// Validates Somali Phone Numbers based on length rules:
/// Returns error message String if invalid, or null if valid.
String? validateSomaliPhoneNumber(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Fadlan geli nambarka taleefanka';
  }
  final clean = value.trim().replaceAll(RegExp(r'\D'), '');
  if (clean.startsWith('0')) {
    if (clean.length != 10) {
      return 'Nambarka 0 ka bilaabanaya waa inuu yahay 10 god (Tusaale: 061XXXXXXX)';
    }
  } else {
    if (clean.length != 9) {
      return 'Nambarka 6 ka bilaabanaya waa inuu yahay 9 god (Tusaale: 61XXXXXXX)';
    }
  }
  return null;
}
