import 'package:driftpro/core/services/absence/leave_period_usage_service.dart';
import 'package:driftpro/core/utils/leave_period_window.dart';
import 'package:driftpro/models/absence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hireDate = DateTime(2020, 6, 7);

  test('periode forankres på ansettelsesdato', () {
    final window = LeavePeriodWindow.forReference(
      hireDate: hireDate,
      referenceDate: DateTime(2026, 1, 12),
    );
    expect(window.periodStart, DateTime(2025, 6, 7));
    expect(window.periodEnd, DateTime(2026, 6, 6));
    expect(window.formatRange(), '07.06.2025 – 06.06.2026');
    expect(window.anchoredToHireDate, isTrue);
  });

  test('egenmelding teller løpende over årsskifte uten nullstilling', () {
    final absences = [
      Absence(
        id: '1',
        userId: 'u',
        companyId: 'c',
        type: AbsenceType.egenmelding,
        startDate: DateTime(2025, 12, 29),
        endDate: DateTime(2025, 12, 31),
        status: AbsenceStatus.godkjent,
        totalDays: 3,
      ),
      Absence(
        id: '2',
        userId: 'u',
        companyId: 'c',
        type: AbsenceType.egenmelding,
        startDate: DateTime(2026, 1, 12),
        endDate: DateTime(2026, 1, 14),
        status: AbsenceStatus.godkjent,
        totalDays: 3,
      ),
    ];

    final usage = LeavePeriodUsageService.compute(
      absences: absences,
      hireDate: hireDate,
      referenceDate: DateTime(2026, 1, 12),
    );

    expect(usage.egenmeldingPeriodsUsed, 2);
    expect(usage.egenmeldingDaysUsed, 6);
    expect(usage.window.contains(DateTime(2026, 1, 12)), isTrue);
  });

  test('sykt barn påvirker ikke egenmelding', () {
    final absences = [
      Absence(
        id: '1',
        userId: 'u',
        companyId: 'c',
        type: AbsenceType.syktBarn,
        startDate: DateTime(2026, 2, 1),
        endDate: DateTime(2026, 2, 2),
        status: AbsenceStatus.godkjent,
        totalDays: 2,
      ),
      Absence(
        id: '2',
        userId: 'u',
        companyId: 'c',
        type: AbsenceType.egenmelding,
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 1),
        status: AbsenceStatus.godkjent,
        totalDays: 1,
      ),
    ];

    final usage = LeavePeriodUsageService.compute(
      absences: absences,
      hireDate: hireDate,
      referenceDate: DateTime(2026, 3, 1),
    );

    expect(usage.syktBarnDaysUsed, 2);
    expect(usage.egenmeldingDaysUsed, 1);
    expect(usage.egenmeldingPeriodsUsed, 1);
  });
}
