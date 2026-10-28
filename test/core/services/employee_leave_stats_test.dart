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
        startDate: DateTime(2026, 2, 2),
        endDate: DateTime(2026, 2, 2),
        status: AbsenceStatus.godkjent,
      ),
      Absence(
        id: '3',
        userId: 'u1',
        companyId: 'c',
        type: AbsenceType.sykmelding,
        startDate: DateTime(2026, 3, 2),
        endDate: DateTime(2026, 3, 6),
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
    // 3 egen (5–7.jan) + 1 sykt barn (2.feb) + 5 sykmelding (2–6.mar)
    expect(summary.totalFravaerDays, 9);
    expect(summary.totalSykmeldingDays, 5);
    expect(summary.averageAbsencePercent, greaterThan(0));
  });

  test('overlappende sykmeldinger telles én gang (person-dager)', () {
    final ref = DateTime(2026, 3, 10);
    const employee = UserProfile(
      id: 'u1',
      email: 'a@test.no',
      fullName: 'Overlap',
    );
    final absences = [
      Absence(
        id: 's1',
        userId: 'u1',
        companyId: 'c',
        type: AbsenceType.sykmelding,
        startDate: DateTime(2026, 3, 2),
        endDate: DateTime(2026, 3, 6),
        status: AbsenceStatus.godkjent,
      ),
      Absence(
        id: 's2',
        userId: 'u1',
        companyId: 'c',
        type: AbsenceType.sykmelding,
        startDate: DateTime(2026, 3, 4),
        endDate: DateTime(2026, 3, 8),
        status: AbsenceStatus.godkjent,
      ),
    ];

    final days = EmployeeLeaveSnapshot.uniqueBusinessDaysInWindow(
      absences: absences,
      rangeStart: DateTime(2026, 1, 1),
      rangeEnd: ref,
      types: {AbsenceType.sykmelding},
    );
    // 2–8. mar = 5 virkedager (ikke 5+3=8)
    expect(days, 5);
  });

  test('sykmelding teller i fraværsprosent', () {
    final ref = DateTime(2026, 10, 28);
    const employee = UserProfile(
      id: 'u1',
      email: 'ingrid@test.no',
      fullName: 'Ingrid',
    );
    final absences = [
      Absence(
        id: 's1',
        userId: 'u1',
        companyId: 'c',
        type: AbsenceType.sykmelding,
        startDate: DateTime(2026, 1, 2),
        endDate: DateTime(2026, 3, 5),
        status: AbsenceStatus.godkjent,
      ),
    ];

    final snap = EmployeeLeaveSnapshot.compute(
      employee: employee,
      employeeAbsences: absences,
      referenceDate: ref,
    );

    expect(snap.sykmeldingDays, greaterThan(40));
    expect(snap.totalFravaerDager, snap.sykmeldingDays);
    expect(snap.absenceRatePercent(ref), greaterThan(9.9));
  });
}
