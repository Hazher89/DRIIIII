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

  test('avslått dashboard blir liggende av etter lagring', () {
    final doc = AccessSettingsDoc.fromJson(
      AccessPresets.forRoleV2(UserRole.ansatt),
    );
    doc.set('dashboard', AccessAction.view, false);
    final saved = doc.toJson();
    expect(saved['areas']['dashboard']['view'], isFalse);

    final loaded = AccessNormalize.toV2(saved, UserRole.ansatt);
    final again = AccessSettingsDoc.fromJson(loaded);
    expect(again.get('dashboard', AccessAction.view), isFalse);
  });

  test('v2 uten nøkkel betyr av, ikke rolle-mal', () {
    final saved = AccessSettingsDoc.fromJson(
      AccessPresets.forRoleV2(UserRole.ansatt),
    ).toJson();
    final areas = Map<String, dynamic>.from(saved['areas'] as Map);
    areas.remove('dashboard');
    saved['areas'] = areas;

    final loaded = AccessNormalize.toV2(saved, UserRole.ansatt);
    final again = AccessSettingsDoc.fromJson(loaded);
    expect(again.get('dashboard', AccessAction.view), isFalse);
  });

  test('allOff keeps more.view', () {
    final doc = AccessSettingsDoc.fromJson(AccessPresets.allOffV2());
    expect(doc.get('more', AccessAction.view), isTrue);
    expect(doc.get('fravaer', AccessAction.view), isFalse);
  });
}
