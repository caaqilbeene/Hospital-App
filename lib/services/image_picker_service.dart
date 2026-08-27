import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'stub_image_picker.dart' if (dart.library.html) 'web_image_picker.dart';

class ImagePickerService {
  static Future<Uint8List?> pickImageBytes({ImageSource source = ImageSource.gallery}) async {
    if (kIsWeb) {
      try {
        final webBytes = await pickImageBytesWeb();
        if (webBytes != null && webBytes.isNotEmpty) {
          return webBytes;
        }
      } catch (e) {
        debugPrint("pickImageBytesWeb notice: $e");
      }
    }

    // 1. Try ImagePicker with immediate downscaling and compression (Memory OOM prevention)
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        imageQuality: 50, // Downscale quality from 10MB to ~100KB on selection
        maxWidth: 800,   // Max width
        maxHeight: 800,  // Max height
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          return bytes;
        }
      }
    } catch (e) {
      debugPrint("ImagePicker notice: $e");
    }

    // 2. Fallback to FilePicker
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null && file.bytes!.isNotEmpty) {
          return file.bytes;
        }
      }
    } catch (e) {
      debugPrint("FilePicker notice: $e");
    }

    return null;
  }

  static Future<String> uploadAndGetUrl(Uint8List bytes, {required String folder}) async {
    final client = SupabaseService.instance.client;
    if (client != null && SupabaseService.instance.isInitialized) {
      final List<String> bucketsToTry = (folder == 'chat' || folder == 'chat_images')
          ? ['chat_images', 'media', 'chat-attachments', 'avatars']
          : ['avatars', 'chat_images', 'media'];
      final fileName = '${folder}_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecondsSinceEpoch % 8999))}.png';

      for (final bucket in bucketsToTry) {
        try {
          await client.storage.from(bucket).uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/png', upsert: true),
          );
          final publicUrl = client.storage.from(bucket).getPublicUrl(fileName);
          if (publicUrl.isNotEmpty) return publicUrl;
        } catch (e) {
          debugPrint("[STORAGE] Bucket '$bucket' upload attempt notice: $e");
        }
      }
    }
    return '';
  }

}

