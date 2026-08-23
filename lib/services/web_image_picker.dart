import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List?> pickImageBytesWeb() {
  final completer = Completer<Uint8List?>();
  try {
    final uploadInput = html.FileUploadInputElement()..accept = 'image/*';
    uploadInput.click();

    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        final reader = html.FileReader();
        reader.readAsArrayBuffer(files[0]);
        reader.onLoadEnd.listen((e) {
          final res = reader.result;
          if (res is Uint8List) {
            completer.complete(res);
          } else if (res is List<int>) {
            completer.complete(Uint8List.fromList(res));
          } else if (res is ByteBuffer) {
            completer.complete(res.asUint8List());
          } else {
            completer.complete(null);
          }
        });
      } else {
        completer.complete(null);
      }
    });
  } catch (err) {
    completer.complete(null);
  }

  return completer.future;
}
