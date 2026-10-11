import 'package:driftpro/core/constants/company_principals.dart';
import 'package:driftpro/core/permissions/leadership_chain.dart';
import 'package:driftpro/models/ticket_assignee_options.dart';
import 'package:driftpro/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile _person({
  required String id,
  required String name,
  String? employeeNumber,
  String? reportsTo,
}) {
  return UserProfile(
    id: id,
    email: '$id@example.com',
    fullName: name,
    employeeNumber: employeeNumber,
    reportsTo: reportsTo,
  );
}

void main() {
  final karwan = _person(id: 'karwan', name: 'Karwan Lian');
  final hazher = _person(id: 'hazher', name: 'Hazher Abdullah', employeeNumber: '25');
  final tommy = _person(id: 'tommy', name: 'Tommy Larsen', employeeNumber: '100');
  final ansatt = _person(id: 'ansatt', name: 'Ola Nordmann');

  final options = TicketAssigneeOptions(
    nearestLeaders: [karwan],
    superadmins: [hazher, tommy],
  );

  test('avdelingsleder sendes til Hazher, ikke seg selv', () {
    final leaders = LeadershipChain.directManagers(
      subject: karwan,
      options: options,
    );
    expect(leaders.map((p) => p.id), ['hazher']);
    expect(CompanyPrincipal.ofProfile(leaders.single), CompanyPrincipal.hazher);
  });

  test('ansatt sendes til avdelingsleder', () {
    final leaders = LeadershipChain.directManagers(
      subject: ansatt,
      options: options,
    );
    expect(leaders.map((p) => p.id), ['karwan']);
  });

  test('Hazher sendes til Tommy', () {
    final leaders = LeadershipChain.directManagers(
      subject: hazher,
      options: TicketAssigneeOptions(superadmins: [hazher, tommy]),
    );
    expect(leaders.map((p) => p.id), ['tommy']);
  });

  test('valgt leder overstyrer pyramiden', () {
    final leaders = LeadershipChain.directManagers(
      subject: _person(id: 'karwan', name: 'Karwan Lian', reportsTo: 'tommy'),
      options: options,
    );
    expect(leaders.map((p) => p.id), ['tommy']);
  });
}
