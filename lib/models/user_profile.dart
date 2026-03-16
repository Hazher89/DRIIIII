enum UserRole { ansatt, leder, admin, superadmin }

class UserProfile {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String? departmentId;
  final String? companyId;
  final String? avatarUrl;
  final String? employeeNumber;
  final String? phone;
  final String? address;
  final String? jobTitle;
  final DateTime? hireDate;
  final bool isSafetyRepresentative;
  final bool isActive;
  final bool isOnboarded;
  final DateTime? createdAt;
  final Map<String, dynamic>? accessSettings;

  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    this.role = UserRole.ansatt,
    this.departmentId,
    this.companyId,
    this.avatarUrl,
    this.employeeNumber,
    this.phone,
    this.address,
    this.jobTitle,
    this.hireDate,
    this.isSafetyRepresentative = false,
    this.isActive = true,
    this.isOnboarded = false,
    this.createdAt,
    this.accessSettings,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      role: UserRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => UserRole.ansatt,
      ),
      departmentId: json['department_id'] as String?,
      companyId: json['company_id'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      employeeNumber: json['employee_number'] as String?,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      jobTitle: json['job_title'] as String?,
      hireDate: json['hire_date'] != null
          ? DateTime.parse(json['hire_date'] as String)
          : null,
      isSafetyRepresentative:
          json['is_safety_representative'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      isOnboarded: json['is_onboarded'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      accessSettings: json['access_settings'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'full_name': fullName,
    'role': role.name,
    'department_id': departmentId,
    'company_id': companyId,
    'avatar_url': avatarUrl,
    'employee_number': employeeNumber,
    'phone': phone,
    'address': address,
    'job_title': jobTitle,
    'hire_date': hireDate?.toIso8601String(),
    'is_safety_representative': isSafetyRepresentative,
    'is_active': isActive,
    'is_onboarded': isOnboarded,
  };

  bool get isLeader => role == UserRole.leder || isAdmin;
  bool get isAdmin =>
      role == UserRole.admin || role == UserRole.superadmin;

  String get initials {
    final parts = fullName.split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }
}
