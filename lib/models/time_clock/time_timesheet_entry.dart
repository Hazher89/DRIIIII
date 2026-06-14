class TimeTimesheetEntry {
  const TimeTimesheetEntry({
    required this.id,
    required this.profileId,
    required this.companyId,
    required this.workDate,
    required this.workTypeId,
    this.startTime,
    this.endTime,
    required this.hours,
    this.departmentId,
    this.project,
    this.activity,
    this.invoiceNote,
    this.note,
    this.isLocked = false,
    this.isApproved = false,
    this.source = 'manual',
    this.workTypeCode,
    this.workTypeName,
    this.workTypeColor,
    this.payrollCode,
    this.regularHours = 0,
    this.overtimeHours = 0,
    this.overtimeReason,
  });

  final String id;
  final String profileId;
  final String companyId;
  final DateTime workDate;
  final String workTypeId;
  final String? startTime;
  final String? endTime;
  final double hours;
  final String? departmentId;
  final String? project;
  final String? activity;
  final String? invoiceNote;
  final String? note;
  final bool isLocked;
  final bool isApproved;
  final String source;
  final String? workTypeCode;
  final String? workTypeName;
  final String? workTypeColor;
  final String? payrollCode;
  final double regularHours;
  final double overtimeHours;
  final String? overtimeReason;

  TimeTimesheetEntry copyWith({
    String? workTypeId,
    String? startTime,
    String? endTime,
    double? hours,
    String? departmentId,
    String? project,
    String? activity,
    String? invoiceNote,
    String? note,
    String? overtimeReason,
  }) {
    return TimeTimesheetEntry(
      id: id,
      profileId: profileId,
      companyId: companyId,
      workDate: workDate,
      workTypeId: workTypeId ?? this.workTypeId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      hours: hours ?? this.hours,
      departmentId: departmentId ?? this.departmentId,
      project: project ?? this.project,
      activity: activity ?? this.activity,
      invoiceNote: invoiceNote ?? this.invoiceNote,
      note: note ?? this.note,
      isLocked: isLocked,
      isApproved: isApproved,
      source: source,
      workTypeCode: workTypeCode,
      workTypeName: workTypeName,
      workTypeColor: workTypeColor,
      payrollCode: payrollCode,
      regularHours: regularHours,
      overtimeHours: overtimeHours,
      overtimeReason: overtimeReason ?? this.overtimeReason,
    );
  }

  Map<String, dynamic> toUpsertPayload() => {
        if (id.isNotEmpty) 'id': id,
        'profile_id': profileId,
        'work_date': workDate.toIso8601String().split('T').first,
        'work_type_id': workTypeId,
        if (startTime != null) 'start_time': startTime,
        if (endTime != null) 'end_time': endTime,
        'hours': hours,
        if (departmentId != null) 'department_id': departmentId,
        if (project != null) 'project': project,
        if (activity != null) 'activity': activity,
        if (invoiceNote != null) 'invoice_note': invoiceNote,
        if (note != null) 'note': note,
        if (overtimeReason != null) 'overtime_reason': overtimeReason,
      };

  factory TimeTimesheetEntry.fromJson(Map<String, dynamic> json) {
    return TimeTimesheetEntry(
      id: json['id'] as String,
      profileId: json['profile_id'] as String,
      companyId: json['company_id'] as String,
      workDate: DateTime.parse(json['work_date'] as String),
      workTypeId: json['work_type_id'] as String,
      startTime: json['start_time'] as String?,
      endTime: json['end_time'] as String?,
      hours: (json['hours'] as num?)?.toDouble() ?? 0,
      departmentId: json['department_id'] as String?,
      project: json['project'] as String?,
      activity: json['activity'] as String?,
      invoiceNote: json['invoice_note'] as String?,
      note: json['note'] as String?,
      isLocked: json['is_locked'] as bool? ?? false,
      isApproved: json['is_approved'] as bool? ?? false,
      source: json['source'] as String? ?? 'manual',
      workTypeCode: json['work_type'] != null
          ? (json['work_type'] as Map)['code'] as String?
          : json['work_type_code'] as String?,
      workTypeName: json['work_type'] != null
          ? (json['work_type'] as Map)['name'] as String?
          : json['work_type_name'] as String?,
      workTypeColor: json['work_type'] != null
          ? (json['work_type'] as Map)['color_hex'] as String?
          : json['work_type_color'] as String?,
      payrollCode: json['work_type'] != null
          ? (json['work_type'] as Map)['payroll_code'] as String?
          : json['payroll_code'] as String?,
      regularHours: (json['regular_hours'] as num?)?.toDouble() ?? 0,
      overtimeHours: (json['overtime_hours'] as num?)?.toDouble() ?? 0,
      overtimeReason: json['overtime_reason'] as String?,
    );
  }
}
