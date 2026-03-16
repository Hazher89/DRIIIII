import 'package:flutter/material.dart';

enum SjaStatus { utkast, signert, godkjent, avvist }

extension SjaStatusExtension on SjaStatus {
  String get label {
    switch (this) {
      case SjaStatus.utkast: return 'Utkast';
      case SjaStatus.signert: return 'Signert';
      case SjaStatus.godkjent: return 'Godkjent';
      case SjaStatus.avvist: return 'Avvist';
    }
  }

  Color get color {
    switch (this) {
      case SjaStatus.utkast: return Colors.grey;
      case SjaStatus.signert: return Colors.blue;
      case SjaStatus.godkjent: return Colors.green;
      case SjaStatus.avvist: return Colors.red;
    }
  }
}

class SjaForm {
  final String id;
  final String companyId;
  final String? departmentId;
  final String createdBy;
  final String title;
  final String workDescription;
  final String? location;
  final DateTime plannedDate;
  final SjaStatus status;
  final List<Map<String, dynamic>> hazards;
  final List<Map<String, dynamic>> measures;
  final List<String> requiredPpe;
  final List<String> signedBy;
  final List<String> signatureUrls;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Joined fields
  final String? creatorName;

  const SjaForm({
    required this.id,
    required this.companyId,
    this.departmentId,
    required this.createdBy,
    required this.title,
    required this.workDescription,
    this.location,
    required this.plannedDate,
    this.status = SjaStatus.utkast,
    this.hazards = const [],
    this.measures = const [],
    this.requiredPpe = const [],
    this.signedBy = const [],
    this.signatureUrls = const [],
    this.approvedBy,
    this.approvedAt,
    this.createdAt,
    this.updatedAt,
    this.creatorName,
  });

  factory SjaForm.fromJson(Map<String, dynamic> json) {
    return SjaForm(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      departmentId: json['department_id'] as String?,
      createdBy: json['created_by'] as String,
      title: json['title'] as String,
      workDescription: json['work_description'] as String,
      location: json['location'] as String?,
      plannedDate: DateTime.parse(json['planned_date'] as String),
      status: SjaStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SjaStatus.utkast,
      ),
      hazards: (json['hazards'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ?? [],
      measures: (json['measures'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ?? [],
      requiredPpe: (json['required_ppe'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      signedBy: (json['signed_by'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      signatureUrls: (json['signature_urls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] != null ? DateTime.parse(json['approved_at'] as String) : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
      creatorName: json['profiles'] != null ? json['profiles']['full_name'] as String? : null,
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'company_id': companyId,
    'department_id': departmentId,
    'created_by': createdBy,
    'title': title,
    'work_description': workDescription,
    'location': location,
    'planned_date': plannedDate.toIso8601String(),
    'status': status.name,
    'hazards': hazards,
    'measures': measures,
    'required_ppe': requiredPpe,
  };
}
