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

  test('rangerer ansatte med mest fravær hittil i år', () {
    final members = [
      const UserProfile(id: 'u1', email: 'a@test.no', fullName: 'Anna Nord', departmentId: 'd1'),
      const UserProfile(id: 'u2', email: 'b@test.no', fullName: 'Bjørn Sol', departmentId: 'd1'),
      const UserProfile(id: 'u3', email: 'c@test.no', fullName: 'Cecilie Berg', departmentId: 'd1'),
    ];
    final ref = DateTime(2026, 6, 10);
    final absences = [
      Absence(
        id: '1',
        userId: 'u1',
        companyId: 'c',
        departmentId: 'd1',
        type: AbsenceType.ferie,
        startDate: DateTime(2026, 3, 2),
        endDate: DateTime(2026, 3, 6),
        status: AbsenceStatus.godkjent,
      ),
      Absence(
        id: '2',
        userId: 'u2',
        companyId: 'c',
        departmentId: 'd1',
        type: AbsenceType.egenmelding,
        startDate: DateTime(2026, 5, 1),
        endDate: DateTime(2026, 5, 10),
        status: AbsenceStatus.godkjent,
      ),
      Absence(
        id: '3',
        userId: 'u3',
        companyId: 'c',
        departmentId: 'd1',
        type: AbsenceType.syktBarn,
        startDate: DateTime(2026, 6, 9),
        endDate: DateTime(2026, 6, 9),
        status: AbsenceStatus.godkjent,
      ),
    ];

    final stats = DepartmentAbsenceStats.forDepartment(
      departmentId: 'd1',
      members: members,
      allAbsences: absences,
      referenceDate: ref,
    );

    expect(stats.topByAbsence.length, 3);
    expect(stats.topByAbsence.first.fullName, 'Bjørn Sol');
    expect(stats.topByAbsence.first.totalDaysYtd, 10);
    expect(stats.topByAbsence[1].fullName, 'Anna Nord');
    expect(stats.topByAbsence.last.fullName, 'Cecilie Berg');
    expect(stats.totalDaysYtd, greaterThan(10));
    expect(stats.typeBreakdownYtd[AbsenceType.egenmelding], 10);
    expect(stats.monthlyTrend.length, 6);
  });
}
