import 'gm_storo_ocr_stub.dart'
    if (dart.library.io) 'gm_storo_ocr_io.dart' as impl;

Future<String?> recognizeLabelFromPath(String? path) =>
    impl.recognizeLabelFromPath(path);
