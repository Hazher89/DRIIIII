import 'package:driftpro/core/constants/leave_rules.dart';
import 'package:driftpro/core/services/absence/absence_service.dart';
import 'package:driftpro/core/services/absence/leave_period_usage_service.dart';
import 'package:driftpro/models/absence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sykt barn-kvote er 15 dager ved 2+ barn under 12', () {
    expect(LeaveRules.syktBarnDaysLimit(0), 10);
    expect(LeaveRules.syktBarnDaysLimit(1), 10);
    expect(LeaveRules.syktBarnDaysLimit(2), 15);
    expect(LeaveRules.syktBarnDaysLimit(5), 15);
  });

  test('validering avviser sykt barn over kvote for 1 barn', () {
    final usage = LeavePeriodUsageService.compute(
      absences: [
        Absence(
          id: '1',
          userId: 'u',
          companyId: 'c',
          type: AbsenceType.syktBarn,
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 10),
          status: AbsenceStatus.godkjent,
          totalDays: 10,
        ),
      ],
      hireDate: DateTime(2020, 6, 7),
      referenceDate: DateTime(2026, 2, 1),
    );

    final err = AbsenceService.validateRequest(
      type: AbsenceType.syktBarn,
      start: DateTime(2026, 2, 1),
      end: DateTime(2026, 2, 1),
      quota: null,
      company: const CompanyLeaveSettings(),
      periodUsage: usage,
      childrenUnder12: 1,
    );

    expect(err, isNotNull);
    expect(err, contains('overskredet'));
  });
}
