import 'package:driftpro/core/constants/vacation_year_window.dart';
import 'package:driftpro/core/services/absence/absence_service.dart';
import 'package:driftpro/models/absence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VacationYearWindow dekker historikk + neste år', () {
    final now = VacationYearWindow.currentYear;
    expect(VacationYearWindow.toYear, now + 1);
    expect(VacationYearWindow.years, contains(now));
    expect(VacationYearWindow.years, contains(now + 1));
    expect(VacationYearWindow.years, contains(now - 5));
    expect(VacationYearWindow.years, isNot(contains(now + 2)));
    expect(VacationYearWindow.yearsNewestFirst.first, now + 1);
  });

  test('godkjente feriedager fordeles per kalenderår', () {
    final absence = Absence(
      id: '1',
      userId: 'u',
      companyId: 'c',
      type: AbsenceType.ferie,
      startDate: DateTime(2025, 12, 29),
      endDate: DateTime(2026, 1, 2),
      status: AbsenceStatus.godkjent,
    );

    expect(AbsenceService.approvedVacationDaysInYear([absence], 2025), 3);
    expect(AbsenceService.approvedVacationDaysInYear([absence], 2026), 1);
    expect(AbsenceService.approvedVacationDaysInYear([absence], 2027), 0);
  });
}
