class TidsbankenPresence {
  final String id;
  final String companyId;
  final String employeeNumber;
  final String firstName;
  final String lastName;
  final String status;
  final String statusLabel;
  final String? departmentCode;
  final String? sinceTime;
  final String? plannedFrom;
  final String? plannedTo;
  final DateTime syncedAt;

  const TidsbankenPresence({
    required this.id,
    required this.companyId,
    required this.employeeNumber,
    required this.firstName,
    required this.lastName,
    required this.status,
    required this.statusLabel,
    this.departmentCode,
    this.sinceTime,
    this.plannedFrom,
    this.plannedTo,
    required this.syncedAt,
  });

  String get fullName {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? 'Ansatt $employeeNumber' : n;
  }

  bool get isClockedIn => status == 'inne';
  bool get isPlanned => status == 'planlagt';
  bool get isAbsent => status == 'fravaer';

  factory TidsbankenPresence.fromJson(Map<String, dynamic> json) {
    return TidsbankenPresence(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      employeeNumber: json['employee_number'] as String? ?? '',
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      status: json['status'] as String? ?? 'ukjent',
      statusLabel: json['status_label'] as String? ?? '',
      departmentCode: json['department_code'] as String?,
      sinceTime: json['since_time'] as String?,
      plannedFrom: json['planned_from'] as String?,
      plannedTo: json['planned_to'] as String?,
      syncedAt: DateTime.parse(json['synced_at'] as String),
    );
  }
}

class TidsbankenSyncState {
  final String companyId;
  final DateTime? lastSyncAt;
  final int clockedInCount;
  final int totalCount;
  final String? lastError;

  const TidsbankenSyncState({
    required this.companyId,
    this.lastSyncAt,
    this.clockedInCount = 0,
    this.totalCount = 0,
    this.lastError,
  });

  factory TidsbankenSyncState.fromJson(Map<String, dynamic> json) {
    return TidsbankenSyncState(
      companyId: json['company_id'] as String,
      lastSyncAt: json['last_sync_at'] != null
          ? DateTime.parse(json['last_sync_at'] as String)
          : null,
      clockedInCount: json['clocked_in_count'] as int? ?? 0,
      totalCount: json['total_count'] as int? ?? 0,
      lastError: json['last_error'] as String?,
    );
  }
}
