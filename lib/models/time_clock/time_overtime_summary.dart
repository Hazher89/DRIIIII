class TimeOvertimeDaily {
  const TimeOvertimeDaily({
    required this.date,
    required this.shiftHours,
    required this.regularHours,
    required this.overtimeHours,
    required this.dailyLimit,
    required this.exceedsDailyLimit,
  });

  final DateTime date;
  final double shiftHours;
  final double regularHours;
  final double overtimeHours;
  final double dailyLimit;
  final bool exceedsDailyLimit;

  factory TimeOvertimeDaily.fromJson(Map<String, dynamic> json) {
    return TimeOvertimeDaily(
      date: DateTime.parse(json['date'] as String),
      shiftHours: (json['shift_hours'] as num?)?.toDouble() ?? 0,
      regularHours: (json['regular_hours'] as num?)?.toDouble() ?? 0,
      overtimeHours: (json['overtime_hours'] as num?)?.toDouble() ?? 0,
      dailyLimit: (json['daily_limit'] as num?)?.toDouble() ?? 9,
      exceedsDailyLimit: json['exceeds_daily_limit'] as bool? ?? false,
    );
  }
}

class TimeOvertimeLimits {
  const TimeOvertimeLimits({
    required this.weeklyOvertime,
    required this.weeklyMax,
    required this.weeklyExceeded,
    required this.fourWeekOvertime,
    required this.fourWeekMax,
    required this.fourWeekExceeded,
    required this.annualOvertime,
    required this.annualMax,
    required this.annualExceeded,
  });

  final double weeklyOvertime;
  final double weeklyMax;
  final bool weeklyExceeded;
  final double fourWeekOvertime;
  final double fourWeekMax;
  final bool fourWeekExceeded;
  final double annualOvertime;
  final double annualMax;
  final bool annualExceeded;

  factory TimeOvertimeLimits.fromJson(Map<String, dynamic> json) {
    return TimeOvertimeLimits(
      weeklyOvertime: (json['weekly_overtime'] as num?)?.toDouble() ?? 0,
      weeklyMax: (json['weekly_max'] as num?)?.toDouble() ?? 10,
      weeklyExceeded: json['weekly_exceeded'] as bool? ?? false,
      fourWeekOvertime: (json['four_week_overtime'] as num?)?.toDouble() ?? 0,
      fourWeekMax: (json['four_week_max'] as num?)?.toDouble() ?? 25,
      fourWeekExceeded: json['four_week_exceeded'] as bool? ?? false,
      annualOvertime: (json['annual_overtime'] as num?)?.toDouble() ?? 0,
      annualMax: (json['annual_max'] as num?)?.toDouble() ?? 200,
      annualExceeded: json['annual_exceeded'] as bool? ?? false,
    );
  }
}

class TimeOvertimeLegal {
  const TimeOvertimeLegal({
    required this.dailyLimitHours,
    required this.weeklyLimitHours,
    required this.overtimeSupplementPct,
    required this.overtimeRegime,
  });

  final double dailyLimitHours;
  final double weeklyLimitHours;
  final double overtimeSupplementPct;
  final String overtimeRegime;

  factory TimeOvertimeLegal.fromJson(Map<String, dynamic> json) {
    return TimeOvertimeLegal(
      dailyLimitHours: (json['daily_limit_hours'] as num?)?.toDouble() ?? 9,
      weeklyLimitHours: (json['weekly_limit_hours'] as num?)?.toDouble() ?? 40,
      overtimeSupplementPct: (json['overtime_supplement_pct'] as num?)?.toDouble() ?? 40,
      overtimeRegime: json['overtime_regime'] as String? ?? 'standard',
    );
  }

  String get regimeLabel =>
      overtimeRegime == 'tariff' ? 'Tariffavtale (§10-6 femte ledd)' : 'Standard (§10-6 fjerde ledd)';
}

class TimeOvertimeSummary {
  const TimeOvertimeSummary({
    required this.weekStart,
    required this.weekEnd,
    required this.exempt,
    required this.legal,
    required this.weekShiftHours,
    required this.weekRegularHours,
    required this.weekOvertimeHours,
    required this.weekSupplementHours,
    this.agreedWeeklyHours,
    required this.daily,
    required this.limits,
  });

  final DateTime weekStart;
  final DateTime weekEnd;
  final bool exempt;
  final TimeOvertimeLegal legal;
  final double weekShiftHours;
  final double weekRegularHours;
  final double weekOvertimeHours;
  final double weekSupplementHours;
  final double? agreedWeeklyHours;
  final List<TimeOvertimeDaily> daily;
  final TimeOvertimeLimits limits;

  bool get hasOvertime => weekOvertimeHours > 0;
  bool get hasLimitWarning =>
      limits.weeklyExceeded || limits.fourWeekExceeded || limits.annualExceeded;

  factory TimeOvertimeSummary.fromJson(Map<String, dynamic> json) {
    final dailyList = (json['daily'] as List<dynamic>? ?? [])
        .map((e) => TimeOvertimeDaily.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    return TimeOvertimeSummary(
      weekStart: DateTime.parse(json['week_start'] as String),
      weekEnd: DateTime.parse(json['week_end'] as String),
      exempt: json['exempt'] as bool? ?? false,
      legal: TimeOvertimeLegal.fromJson(
        Map<String, dynamic>.from(json['legal'] as Map? ?? {}),
      ),
      weekShiftHours: (json['week_shift_hours'] as num?)?.toDouble() ?? 0,
      weekRegularHours: (json['week_regular_hours'] as num?)?.toDouble() ?? 0,
      weekOvertimeHours: (json['week_overtime_hours'] as num?)?.toDouble() ?? 0,
      weekSupplementHours: (json['week_supplement_hours'] as num?)?.toDouble() ?? 0,
      agreedWeeklyHours: (json['agreed_weekly_hours'] as num?)?.toDouble(),
      daily: dailyList,
      limits: TimeOvertimeLimits.fromJson(
        Map<String, dynamic>.from(json['limits'] as Map? ?? {}),
      ),
    );
  }
}

class TimeOvertimeSettings {
  const TimeOvertimeSettings({
    required this.dailyWorkLimitHours,
    required this.weeklyWorkLimitHours,
    required this.overtimeSupplementPct,
    required this.overtimeRegime,
    required this.overtimeWeeklyMax,
    required this.overtimeFourWeekMax,
    required this.overtimeAnnualMax,
  });

  final double dailyWorkLimitHours;
  final double weeklyWorkLimitHours;
  final double overtimeSupplementPct;
  final String overtimeRegime;
  final double overtimeWeeklyMax;
  final double overtimeFourWeekMax;
  final double overtimeAnnualMax;

  factory TimeOvertimeSettings.fromJson(Map<String, dynamic> json) {
    return TimeOvertimeSettings(
      dailyWorkLimitHours: (json['daily_work_limit_hours'] as num?)?.toDouble() ?? 9,
      weeklyWorkLimitHours: (json['weekly_work_limit_hours'] as num?)?.toDouble() ?? 40,
      overtimeSupplementPct: (json['overtime_supplement_pct'] as num?)?.toDouble() ?? 40,
      overtimeRegime: json['overtime_regime'] as String? ?? 'standard',
      overtimeWeeklyMax: (json['overtime_weekly_max'] as num?)?.toDouble() ?? 10,
      overtimeFourWeekMax: (json['overtime_four_week_max'] as num?)?.toDouble() ?? 25,
      overtimeAnnualMax: (json['overtime_annual_max'] as num?)?.toDouble() ?? 200,
    );
  }

  Map<String, dynamic> toPayload() => {
        'daily_work_limit_hours': dailyWorkLimitHours,
        'weekly_work_limit_hours': weeklyWorkLimitHours,
        'overtime_supplement_pct': overtimeSupplementPct,
        'overtime_regime': overtimeRegime,
      };

  TimeOvertimeSettings copyWithRegime(String regime) => TimeOvertimeSettings(
        dailyWorkLimitHours: dailyWorkLimitHours,
        weeklyWorkLimitHours: weeklyWorkLimitHours,
        overtimeSupplementPct: overtimeSupplementPct,
        overtimeRegime: regime,
        overtimeWeeklyMax: regime == 'tariff' ? 20 : 10,
        overtimeFourWeekMax: regime == 'tariff' ? 50 : 25,
        overtimeAnnualMax: regime == 'tariff' ? 300 : 200,
      );
}
