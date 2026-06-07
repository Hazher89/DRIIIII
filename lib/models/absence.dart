enum AbsenceType {
  egenmelding,
  syktBarn,
  ferie,
  permisjon,
  sykmelding;

  String get dbValue {
    switch (this) {
      case AbsenceType.egenmelding: return 'egenmelding';
      case AbsenceType.syktBarn: return 'sykt_barn';
      case AbsenceType.ferie: return 'ferie';
      case AbsenceType.permisjon: return 'permisjon';
      case AbsenceType.sykmelding: return 'sykmelding';
    }
  }

  String get label {
    switch (this) {
      case AbsenceType.egenmelding: return 'Egenmelding';
      case AbsenceType.syktBarn: return 'Sykt barn';
      case AbsenceType.ferie: return 'Ferie';
      case AbsenceType.permisjon: return 'Permisjon';
      case AbsenceType.sykmelding: return 'Sykmelding';
    }
  }

  static AbsenceType fromDb(String value) {
    switch (value) {
      case 'egenmelding': return AbsenceType.egenmelding;
      case 'sykt_barn': return AbsenceType.syktBarn;
      case 'ferie': return AbsenceType.ferie;
      case 'permisjon': return AbsenceType.permisjon;
      case 'sykmelding': return AbsenceType.sykmelding;
      default: return AbsenceType.egenmelding;
    }
  }
}

enum AbsenceStatus {
  ventende,
  godkjent,
  avvist;

  String get label {
    switch (this) {
      case AbsenceStatus.ventende: return 'Ventende';
      case AbsenceStatus.godkjent: return 'Godkjent';
      case AbsenceStatus.avvist: return 'Avvist';
    }
  }
}

class Absence {
  final String id;
  final String userId;
  final String companyId;
  final String? departmentId;
  final AbsenceType type;
  final DateTime startDate;
  final DateTime endDate;
  final AbsenceStatus status;
  final String? comment;
  final int? quotaYear;
  final int? totalDays;
  final int? vacationDayCount;
  final String? approvedBy;
  final DateTime? approvedAt;
  final List<String> attachmentUrls;
  final DateTime? createdAt;

  // Joined fields
  final String? userName;
  final String? userAvatarUrl;

  const Absence({
    required this.id,
    required this.userId,
    required this.companyId,
    this.departmentId,
    required this.type,
    required this.startDate,
    required this.endDate,
    this.status = AbsenceStatus.ventende,
    this.comment,
    this.quotaYear,
    this.totalDays,
    this.vacationDayCount,
    this.approvedBy,
    this.approvedAt,
    this.attachmentUrls = const [],
    this.createdAt,
    this.userName,
    this.userAvatarUrl,
  });

  factory Absence.fromJson(Map<String, dynamic> json) {
    return Absence(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      companyId: json['company_id'] as String,
      departmentId: json['department_id'] as String?,
      type: AbsenceType.fromDb(json['type'] as String),
      startDate: _parseCalendarDate(json['start_date'] as String),
      endDate: _parseCalendarDate(json['end_date'] as String),
      status: AbsenceStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => AbsenceStatus.ventende,
      ),
      comment: json['comment'] as String?,
      quotaYear: json['quota_year'] as int?,
      totalDays: json['total_days'] as int?,
      vacationDayCount: json['vacation_day_count'] as int?,
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      attachmentUrls: (json['attachment_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      userName: json['profiles'] != null
          ? json['profiles']['full_name'] as String?
          : null,
      userAvatarUrl: json['profiles'] != null
          ? json['profiles']['avatar_url'] as String?
          : null,
    );
  }

  Map<String, dynamic> toInsertJson({String? approverId}) => {
    'user_id': userId,
    'company_id': companyId,
    'department_id': departmentId,
    'type': type.dbValue,
    'start_date': startDate.toIso8601String().split('T').first,
    'end_date': endDate.toIso8601String().split('T').first,
    'status': status.name,
    'comment': comment,
    'quota_year': quotaYear ?? startDate.year,
    if (status == AbsenceStatus.godkjent && approverId != null) ...{
      'approved_by': approverId,
      'approved_at': DateTime.now().toUtc().toIso8601String(),
    },
  };

  bool get isActive {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return !today.isBefore(s) && !today.isAfter(e);
  }

  /// Kalenderdato uten tidssone-forskyvning (viktig for «fravær i dag»).
  static DateTime _parseCalendarDate(String raw) {
    final datePart = raw.split('T').first;
    final parts = datePart.split('-');
    if (parts.length == 3) {
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    }
    return DateTime.parse(raw);
  }
}

class AbsenceQuota {
  final String id;
  final String userId;
  final int year;
  final int vacationDaysTotal;
  final int vacationDaysUsed;
  final int vacationDaysCarriedOver;
  final int egenmeldingDaysUsed;
  final int egenmeldingPeriodsUsed;
  final int syktBarnDaysUsed;

  const AbsenceQuota({
    required this.id,
    required this.userId,
    required this.year,
    this.vacationDaysTotal = 25,
    this.vacationDaysUsed = 0,
    this.vacationDaysCarriedOver = 0,
    this.egenmeldingDaysUsed = 0,
    this.egenmeldingPeriodsUsed = 0,
    this.syktBarnDaysUsed = 0,
  });

  factory AbsenceQuota.fromJson(Map<String, dynamic> json) {
    return AbsenceQuota(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      year: json['year'] as int,
      vacationDaysTotal: json['vacation_days_total'] as int? ?? 25,
      vacationDaysUsed: json['vacation_days_used'] as int? ?? 0,
      vacationDaysCarriedOver:
          json['vacation_days_carried_over'] as int? ?? 0,
      egenmeldingDaysUsed: json['egenmelding_days_used'] as int? ?? 0,
      egenmeldingPeriodsUsed:
          json['egenmelding_periods_used'] as int? ?? 0,
      syktBarnDaysUsed: json['sykt_barn_days_used'] as int? ?? 0,
    );
  }

  int get totalVacationDays => vacationDaysTotal + vacationDaysCarriedOver;
  int get vacationDaysRemaining => totalVacationDays - vacationDaysUsed;
  double get vacationUsagePercent =>
      totalVacationDays > 0 ? vacationDaysUsed / totalVacationDays : 0;

  /// Dager som kan overføres til neste år (begrenses av bedriftens maks).
  int carryoverEligible(int maxCarryover) {
    final r = vacationDaysRemaining;
    if (r <= 0) return 0;
    return r > maxCarryover ? maxCarryover : r;
  }
}
