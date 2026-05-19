enum UserRole { ansatt, leder, admin, superadmin, samarbeidspartner }

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
  final DateTime? birthDate;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final bool isSafetyRepresentative;
  final bool isActive;
  final bool isOnboarded;
  final bool isApproved;
  final DateTime? createdAt;
  final Map<String, dynamic>? accessSettings;
  /// Når satt, representerer brukeren en ekstern samarbeidspartner (portal).
  final String? partnerId;
  /// Når satt, ser portalbrukeren kun ruter for dette MAVI-kjøretøyet.
  final String? partnerVehicleId;

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
    this.birthDate,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.isSafetyRepresentative = false,
    this.isActive = true,
    this.isOnboarded = false,
    this.isApproved = false,
    this.createdAt,
    this.accessSettings,
    this.partnerId,
    this.partnerVehicleId,
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
      birthDate: json['birth_date'] != null
          ? DateTime.parse(json['birth_date'] as String)
          : null,
      emergencyContactName: json['emergency_contact_name'] as String?,
      emergencyContactPhone: json['emergency_contact_phone'] as String?,
      isSafetyRepresentative:
          json['is_safety_representative'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      isOnboarded: json['is_onboarded'] as bool? ?? false,
      isApproved: json['is_approved'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      accessSettings: json['access_settings'] as Map<String, dynamic>?,
      partnerId: json['partner_id'] as String?,
      partnerVehicleId: json['partner_vehicle_id'] as String?,
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
    'birth_date': birthDate?.toIso8601String(),
    'emergency_contact_name': emergencyContactName,
    'emergency_contact_phone': emergencyContactPhone,
    'is_safety_representative': isSafetyRepresentative,
    'is_active': isActive,
    'is_onboarded': isOnboarded,
    'is_approved': isApproved,
    'partner_id': partnerId,
    'partner_vehicle_id': partnerVehicleId,
  };

  UserProfile copyWith({
    String? email,
    String? fullName,
    UserRole? role,
    bool? isOnboarded,
    bool? isApproved,
    bool? isActive,
    String? companyId,
    String? partnerId,
    String? partnerVehicleId,
  }) {
    return UserProfile(
      id: id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      departmentId: departmentId,
      companyId: companyId ?? this.companyId,
      avatarUrl: avatarUrl,
      employeeNumber: employeeNumber,
      phone: phone,
      address: address,
      jobTitle: jobTitle,
      hireDate: hireDate,
      birthDate: birthDate,
      emergencyContactName: emergencyContactName,
      emergencyContactPhone: emergencyContactPhone,
      isSafetyRepresentative: isSafetyRepresentative,
      isActive: isActive ?? this.isActive,
      isOnboarded: isOnboarded ?? this.isOnboarded,
      isApproved: isApproved ?? this.isApproved,
      createdAt: createdAt,
      accessSettings: accessSettings,
      partnerId: partnerId ?? this.partnerId,
      partnerVehicleId: partnerVehicleId ?? this.partnerVehicleId,
    );
  }

  bool get isPartnerPortalUser =>
      partnerId != null || role == UserRole.samarbeidspartner;
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
