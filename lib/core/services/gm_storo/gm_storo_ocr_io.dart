import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

Future<String?> recognizeLabelFromPath(String? path) async {
  if (path == null || path.isEmpty) return null;
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(path));
    final text = result.text.trim();
    return text.isEmpty ? null : text;
  } catch (_) {
    return null;
  } finally {
    await recognizer.close();
  }
}
