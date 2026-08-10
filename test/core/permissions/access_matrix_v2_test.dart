import 'package:flutter_test/flutter_test.dart';

import 'package:driftpro/core/permissions/access_actions.dart';
import 'package:driftpro/core/permissions/access_normalize.dart';
import 'package:driftpro/core/permissions/access_presets.dart';
import 'package:driftpro/models/user_profile.dart';

void main() {
  test('v1 fravaer_godkjenn migrates to area approve', () {
    final v2 = AccessNormalize.toV2({
      'fravaer': true,
      'fravaer_godkjenn': true,
      'avvik': true,
    }, UserRole.ansatt);
    final doc = AccessSettingsDoc.fromJson(v2);
    expect(doc.get('fravaer', AccessAction.view), isTrue);
    expect(doc.get('fravaer', AccessAction.approve), isTrue);
    expect(doc.toLegacyBoolMap()['fravaer_godkjenn'], isTrue);
  });

  test('leader preset includes partners and approve', () {
    final doc = AccessSettingsDoc.fromJson(AccessPresets.forRoleV2(UserRole.leder));
    expect(doc.get('partners', AccessAction.view), isTrue);
    expect(doc.get('fravaer', AccessAction.approve), isTrue);
    expect(doc.get('more', AccessAction.view), isTrue);
  });

  test('allOff keeps more.view', () {
    final doc = AccessSettingsDoc.fromJson(AccessPresets.allOffV2());
    expect(doc.get('more', AccessAction.view), isTrue);
    expect(doc.get('fravaer', AccessAction.view), isFalse);
  });
}
