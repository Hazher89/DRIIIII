import 'package:flutter_test/flutter_test.dart';

import 'package:driftpro/core/permissions/access_actions.dart';
import 'package:driftpro/core/permissions/access_normalize.dart';
import 'package:driftpro/core/permissions/access_presets.dart';
import 'package:driftpro/core/permissions/statutory_role_access.dart';
import 'package:driftpro/models/user_profile.dart';

void main() {
  test('verneombud package unlocks HMS vernerunde create', () {
    final doc = AccessSettingsDoc.fromJson(StatutoryRoleAccess.verneombudV2());
    expect(doc.get('hms', AccessAction.view), isTrue);
    expect(doc.get('hms.vernerunde', AccessAction.view), isTrue);
    expect(doc.get('hms.vernerunde', AccessAction.create), isTrue);
    expect(doc.get('hms.risiko', AccessAction.view), isTrue);
    expect(doc.get('avvik', AccessAction.view), isTrue);
  });

  test('hovedverneombud includes utstyr admin', () {
    final doc =
        AccessSettingsDoc.fromJson(StatutoryRoleAccess.hovedverneombudV2());
    expect(doc.get('hms.vernerunde', AccessAction.create), isTrue);
    expect(doc.get('hms.utstyr.admin', AccessAction.view), isTrue);
  });

  test('tillitsvalgt does not get leave approve for others', () {
    final doc = AccessSettingsDoc.fromJson(StatutoryRoleAccess.tillitsvalgtV2());
    expect(doc.get('fravaer.team', AccessAction.view), isTrue);
    expect(doc.get('fravaer.godkjenn', AccessAction.approve), isFalse);
    expect(doc.get('hms.dokumenter', AccessAction.view), isTrue);
  });

  test('amu member gets hms overview without leave approve', () {
    final doc = AccessSettingsDoc.fromJson(StatutoryRoleAccess.amuMemberV2());
    expect(doc.get('hms.risiko', AccessAction.view), isTrue);
    expect(doc.get('avvik.behandle', AccessAction.approve), isTrue);
    expect(doc.get('fravaer.godkjenn', AccessAction.approve), isFalse);
  });

  test('rebuild grants verneombud on top of employee role', () {
    final settings = StatutoryRoleAccess.rebuildAccessSettings(
      role: UserRole.ansatt,
      current: AccessPresets.employeeV2(),
      isSafetyRepresentative: true,
      isUnionRepresentative: false,
    );
    final doc = AccessSettingsDoc.fromJson(settings);
    expect(doc.get('hms.vernerunde', AccessAction.create), isTrue);
    expect(doc.get('fravaer.mine', AccessAction.create), isTrue);
  });

  test('rebuild strips verneombud when turned off', () {
    final withVo = StatutoryRoleAccess.rebuildAccessSettings(
      role: UserRole.ansatt,
      current: AccessPresets.employeeV2(),
      isSafetyRepresentative: true,
      isUnionRepresentative: false,
    );
    final without = StatutoryRoleAccess.rebuildAccessSettings(
      role: UserRole.ansatt,
      current: withVo,
      isSafetyRepresentative: false,
      isUnionRepresentative: false,
    );
    final doc = AccessSettingsDoc.fromJson(without);
    expect(doc.get('hms.vernerunde', AccessAction.create), isFalse);
    expect(doc.get('fravaer.mine', AccessAction.view), isTrue);
  });

  test('department leader preset has team leave HMS tickets', () {
    final doc = AccessSettingsDoc.fromJson(AccessPresets.departmentLeaderV2());
    expect(doc.get('more.ansatte', AccessAction.view), isTrue);
    expect(doc.get('fravaer.team', AccessAction.view), isTrue);
    expect(doc.get('fravaer.godkjenn', AccessAction.approve), isTrue);
    expect(doc.get('avvik.behandle', AccessAction.approve), isTrue);
    expect(doc.get('hms.vernerunde', AccessAction.view), isTrue);
  });
}
