import '../../constants/leave_rules.dart';
import '../../../models/leave_period_usage.dart';

/// Om ansatt kan søke egenmelding i gjeldende periode.
class LeaveEligibility {
  LeaveEligibility._();

  static bool isEgenmeldingExhausted({
    required LeavePeriodUsage? usage,
    required int maxDays,
    int maxPeriods = LeaveRules.egenmeldingMaxPeriodsPerYear,
  }) {
    if (usage == null) return false;
    return usage.egenmeldingDaysRemaining(maxDays) <= 0 ||
        usage.egenmeldingPeriodsUsed >= maxPeriods;
  }

  static String exhaustionReason({
    required LeavePeriodUsage usage,
    required int maxDays,
    int maxPeriods = LeaveRules.egenmeldingMaxPeriodsPerYear,
  }) {
    final daysLeft = usage.egenmeldingDaysRemaining(maxDays);
    final periodsLeft = maxPeriods - usage.egenmeldingPeriodsUsed;
    if (daysLeft <= 0 && periodsLeft <= 0) {
      return 'Du har brukt alle $maxDays dager og alle $maxPeriods egenmeldingsperioder '
          'i perioden ${usage.window.formatRange()}.';
    }
    if (daysLeft <= 0) {
      return 'Du har brukt alle $maxDays egenmeldingsdager '
          'i perioden ${usage.window.formatRange()}.';
    }
    return 'Du har brukt alle $maxPeriods egenmeldingsperioder '
        'i perioden ${usage.window.formatRange()}.';
  }
}
