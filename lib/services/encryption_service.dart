class EncryptionService {
  /// Plain text passthrough - Base64 and XOR encoding completely removed
  static String encrypt(String plainText) => plainText;

  /// Plain text passthrough - Base64 and XOR decoding completely removed
  static String decrypt(String cipherText) => cipherText;
}
