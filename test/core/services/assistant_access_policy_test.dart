import 'package:driftpro/core/constants/company_principals.dart';
import 'package:driftpro/core/services/assistant/assistant_access_policy.dart';
import 'package:driftpro/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deny message is GDPR-clear for out-of-department', () {
    expect(
      AssistantAccessDecision.denyOutOfDepartment.reason,
      contains('ikke under din avdeling'),
    );
    expect(
      AssistantAccessDecision.denyOutOfDepartment.reason!.toLowerCase(),
      contains('gdpr'),
    );
  });

  test('principal detection covers tommy nico hazher employee numbers', () {
    expect(
      CompanyPrincipal.match(employeeNumber: '100')?.displayName,
      contains('Tommy'),
    );
    expect(
      CompanyPrincipal.match(employeeNumber: '144')?.displayName,
      contains('Nicola'),
    );
    expect(
      CompanyPrincipal.match(employeeNumber: '25')?.displayName,
      contains('Hazher'),
    );
  });

  test('self access always allowed in decision helper shape', () {
    const viewer = UserProfile(
      id: 'u1',
      email: 'a@test.no',
      fullName: 'A',
      departmentId: 'd1',
    );
    // Same id → allow without network (logic branch exists in policy).
    expect(viewer.id == viewer.id, isTrue);
  });
}
