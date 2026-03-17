enum AttendanceStatus { on_duty, off_duty }

class EmployeeAttendance {
  final String id;
  final String userId;
  final String companyId;
  final AttendanceStatus status;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final DateTime lastUpdated;
  final String? fullName; // Joined from profiles
  final String? avatarUrl; // Joined from profiles

  EmployeeAttendance({
    required this.id,
    required this.userId,
    required this.companyId,
    required this.status,
    this.checkInAt,
    this.checkOutAt,
    required this.lastUpdated,
    this.fullName,
    this.avatarUrl,
  });

  factory EmployeeAttendance.fromJson(Map<String, dynamic> json) {
    return EmployeeAttendance(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      companyId: json['company_id'] as String,
      status: AttendanceStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => AttendanceStatus.off_duty,
      ),
      checkInAt: json['check_in_at'] != null ? DateTime.parse(json['check_in_at']) : null,
      checkOutAt: json['check_out_at'] != null ? DateTime.parse(json['check_out_at']) : null,
      lastUpdated: DateTime.parse(json['last_updated']),
      fullName: json['profiles']?['full_name'],
      avatarUrl: json['profiles']?['avatar_url'],
    );
  }

  bool get isOnDuty => status == AttendanceStatus.on_duty;
}
