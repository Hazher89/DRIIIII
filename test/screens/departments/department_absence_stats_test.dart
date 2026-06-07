import 'package:driftpro/core/constants/leave_rules.dart';
import 'package:driftpro/models/absence.dart';
import 'package:driftpro/models/user_profile.dart';
import 'package:driftpro/screens/departments/widgets/department_absence_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('beregner fravær per avdeling for i dag', () {
    final members = [
      const UserProfile(id: 'u1', email: 'a@test.no', fullName: 'A', departmentId: 'd1'),
      const UserProfile(id: 'u2', email: 'b@test.no', fullName: 'B', departmentId: 'd1'),
    ];
    final today = DateTime(2026, 6, 7);
    final absences = [
      Absence(
        id: '1',
        userId: 'u1',
        companyId: 'c',
        departmentId: 'd1',
        type: AbsenceType.ferie,
        startDate: today,
        endDate: today.add(const Duration(days: 2)),
        status: AbsenceStatus.godkjent,
      ),
      Absence(
        id: '2',
        userId: 'u2',
        companyId: 'c',
        departmentId: 'd1',
        type: AbsenceType.egenmelding,
        startDate: today,
        endDate: today,
        status: AbsenceStatus.ventende,
      ),
    ];

    final stats = DepartmentAbsenceStats.forDepartment(
      departmentId: 'd1',
      members: members,
      allAbsences: absences,
      referenceDate: today,
    );

    expect(stats.memberCount, 2);
    expect(stats.onVacationToday, 1);
    expect(stats.awayToday, 1);
    expect(stats.pendingCount, 1);
    expect(stats.presentCount, 1);
    expect(stats.presentPercent, 50);
  });

  test('rangerer ansatte med samme saldo som Team & kalender', () {
    final members = [
      UserProfile(
        id: 'u1',
        email: 'a@test.no',
        fullName: 'Anna Nord',
        departmentId: 'd1',
        hireDate: DateTime(2026, 1, 12),
      ),
      const UserProfile(
        id: 'u2',
        email: 'b@test.no',
        fullName: 'Bjørn Sol',
        departmentId: 'd1',
      ),
    ];
    final ref = DateTime(2026, 6, 10);
    final absences = [
      Absence(
        id: '1',
        userId: 'u1',
        companyId: 'c',
        departmentId: 'd1',
        type: AbsenceType.syktBarn,
        startDate: DateTime(2026, 1, 12),
        endDate: DateTime(2026, 1, 12),
        status: AbsenceStatus.godkjent,
      ),
      Absence(
        id: '2',
        userId: 'u2',
        companyId: 'c',
        departmentId: 'd1',
        type: AbsenceType.egenmelding,
        startDate: DateTime(2025, 6, 16),
        endDate: DateTime(2025, 6, 18),
        status: AbsenceStatus.godkjent,
      ),
      Absence(
        id: '3',
        userId: 'u2',
        companyId: 'c',
        departmentId: 'd1',
        type: AbsenceType.egenmelding,
        startDate: DateTime(2026, 2, 20),
        endDate: DateTime(2026, 2, 20),
        status: AbsenceStatus.godkjent,
      ),
    ];

    final stats = DepartmentAbsenceStats.forDepartment(
      departmentId: 'd1',
      members: members,
      allAbsences: absences,
      referenceDate: ref,
      company: const CompanyLeaveSettings(),
    );

    expect(stats.topByAbsence.length, 2);
    expect(stats.topByAbsence.first.fullName, 'Bjørn Sol');
    expect(stats.topByAbsence.first.totalDaysYtd, 4);
    expect(stats.topByAbsence.first.egenDays, 4);
    expect(stats.topByAbsence.last.fullName, 'Anna Nord');
    expect(stats.topByAbsence.last.syktDays, 1);
    expect(stats.totalDaysYtd, 5);
    expect(stats.registeredEgenDays, 4);
    expect(stats.registeredSyktDays, 1);
    expect(stats.typeBreakdownYtd[AbsenceType.egenmelding], 4);
    expect(stats.typeBreakdownYtd[AbsenceType.syktBarn], 1);
  });
}
