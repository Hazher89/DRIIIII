class TimeClockPresence {
  const TimeClockPresence({
    required this.profileId,
    required this.fullName,
    this.firstName,
    this.lastName,
    this.employeeNumber,
    this.departmentId,
    this.departmentName,
    this.isClockedIn = false,
    this.clockedInAt,
    this.workTypeCode,
    this.workTypeName,
    this.workTypeColor,
  });

  final String profileId;
  final String fullName;
  final String? firstName;
  final String? lastName;
  final String? employeeNumber;
  final String? departmentId;
  final String? departmentName;
  final bool isClockedIn;
  final DateTime? clockedInAt;
  final String? workTypeCode;
  final String? workTypeName;
  final String? workTypeColor;

  String get statusLabel {
    if (isClockedIn) {
      final since = clockedInAt != null
          ? ' siden ${_formatTime(clockedInAt!)}'
          : '';
      final wt = workTypeName ?? workTypeCode ?? 'Inne';
      return 'inne : ${workTypeCode ?? ''} $wt$since'.trim();
    }
    return 'ingen registrering';
  }

  static String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  factory TimeClockPresence.fromJson(Map<String, dynamic> json) {
    return TimeClockPresence(
      profileId: json['profile_id'] as String,
      fullName: json['full_name'] as String? ?? '',
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      employeeNumber: json['employee_number'] as String?,
      departmentId: json['department_id'] as String?,
      departmentName: json['department_name'] as String?,
      isClockedIn: json['is_clocked_in'] as bool? ?? false,
      clockedInAt: json['clocked_in_at'] != null
          ? DateTime.tryParse(json['clocked_in_at'] as String)
          : null,
      workTypeCode: json['work_type_code'] as String?,
      workTypeName: json['work_type_name'] as String?,
      workTypeColor: json['work_type_color'] as String?,
    );
  }
}
