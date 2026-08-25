import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('training guides are bundled', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final keys = manifest
        .listAssets()
        .where((k) => k.contains('hms/training/guides/'))
        .toList();
    expect(keys, isNotEmpty);
    expect(keys, contains('assets/hms/training/guides/driftpro_avvik.txt'));
  });
}
