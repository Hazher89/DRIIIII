import 'package:flutter_test/flutter_test.dart';

import 'package:driftpro/core/services/work_steps/work_steps_privacy.dart';

void main() {
  test('work steps privacy constants exist for Apple/Google review', () {
    expect(kWorkStepsConsentVersion, 'work_steps_v1');
    expect(kWorkStepsConsentBody, contains('frivillig'));
    expect(kWorkStepsConsentBody, contains('Apple Helse'));
    expect(kWorkStepsConsentDetail, contains('Ingen GPS-sporing'));
    expect(kIosHealthShareUsageDescription, contains('MAVI'));
    expect(kAndroidHealthConnectRationale, contains('No continuous tracking'));
  });
}
