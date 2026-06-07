import '../core/constants/leave_rules.dart';
import '../core/utils/leave_period_window.dart';

/// Bruk av egenmelding/sykt barn i gjeldende 12-måneders periode.
class LeavePeriodUsage {
  final LeavePeriodWindow window;
  final int egenmeldingDaysUsed;
  final int egenmeldingPeriodsUsed;
  final int syktBarnDaysUsed;

  const LeavePeriodUsage({
    required this.window,
    this.egenmeldingDaysUsed = 0,
    this.egenmeldingPeriodsUsed = 0,
    this.syktBarnDaysUsed = 0,
  });

  int egenmeldingDaysRemaining(int maxDays) =>
      (maxDays - egenmeldingDaysUsed).clamp(0, maxDays);

  int syktBarnDaysRemaining(int maxDays) =>
      (maxDays - syktBarnDaysUsed).clamp(0, maxDays);

  bool isEgenmeldingExhausted(int maxDays) =>
      egenmeldingDaysRemaining(maxDays) <= 0 ||
      egenmeldingPeriodsUsed >= LeaveRules.egenmeldingMaxPeriodsPerYear;
}
