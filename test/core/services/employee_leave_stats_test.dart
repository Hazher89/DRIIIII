import 'package:driftpro/core/constants/leave_rules.dart';
import 'package:driftpro/core/services/absence/employee_leave_stats.dart';
import 'package:driftpro/models/absence.dart';
import 'package:driftpro/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kvotebruk og fraværsrate beregnes separat', () {
    const company = CompanyLeaveSettings();
    final ref = DateTime(2026, 6, 7);
    const employee = UserProfile(
      id: 'u1',
      email: 'a@test.no',
      fullName: 'Rafal Test',
      departmentId: 'd1',
    );
    final absences = [
      Absence(
        id: '1',
        userId: 'u1',
        companyId: 'c',
        type: AbsenceType.egenmelding,
        startDate: DateTime(2026, 1, 5),
        endDate: DateTime(2026, 1, 8),
        status: AbsenceStatus.godkjent,
      ),
    ];

    final snap = EmployeeLeaveSnapshot.compute(
      employee: employee,
      employeeAbsences: absences,
      company: company,
      referenceDate: ref,
    );

    expect(snap.egenDaysTotal, 4);
    expect(snap.quotaUsagePercent, closeTo(33.33, 0.1));
    expect(snap.absenceRatePercent(ref), greaterThan(0));
    expect(snap.absenceRatePercent(ref), lessThan(10));
  });

  test('teamsnitt bruker fraværsdager / virkedager YTD', () {
    const company = CompanyLeaveSettings();
    final ref = DateTime(2026, 6, 7);
    final employees = [
      const UserProfile(
        id: 'u1',
        email: 'a@test.no',
        fullName: 'A',
        departmentId: 'd1',
      ),
      const UserProfile(
        id: 'u2',
        email: 'b@test.no',
        fullName: 'B',
        departmentId: 'd1',
      ),
    ];
    final absences = [
      Absence(
        id: '1',
        userId: 'u1',
        companyId: 'c',
        type: AbsenceType.egenmelding,
        startDate: DateTime(2026, 1, 5),
        endDate: DateTime(2026, 1, 7),
        status: AbsenceStatus.godkjent,
      ),
      Absence(
        id: '2',
        userId: 'u2',
        companyId: 'c',
        type: AbsenceType.syktBarn,
        startDate: DateTime(2026, 2, 1),
        endDate: DateTime(2026, 2, 1),
        status: AbsenceStatus.godkjent,
      ),
    ];

    final summary = TeamLeaveSummary.compute(
      employees: employees,
      allAbsences: absences,
      company: company,
      referenceDate: ref,
    );

    expect(summary.employeeCount, 2);
    expect(summary.totalFravaerDays, 4);
    expect(summary.averageAbsencePercent, greaterThan(0));
    expect(summary.averageAbsencePercent, lessThan(10));
  });
}
