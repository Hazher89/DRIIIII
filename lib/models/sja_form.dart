import 'package:flutter/material.dart';

enum SjaStatus {
  utkast,
  venterSignatur,
  signert,
  godkjent,
  avvist,
  iGang,
  utlopt,
}

extension SjaStatusExtension on SjaStatus {
  String get label {
    switch (this) {
      case SjaStatus.utkast:
        return 'Utkast';
      case SjaStatus.venterSignatur:
        return 'Venter signatur';
      case SjaStatus.signert:
        return 'Signert';
      case SjaStatus.godkjent:
        return 'Godkjent';
      case SjaStatus.avvist:
        return 'Avvist';
      case SjaStatus.iGang:
        return 'I gang';
      case SjaStatus.utlopt:
        return 'Utløpt';
    }
  }

  Color get color {
    switch (this) {
      case SjaStatus.utkast:
        return Colors.grey;
      case SjaStatus.venterSignatur:
        return Colors.amber;
      case SjaStatus.signert:
        return Colors.blue;
      case SjaStatus.godkjent:
        return Colors.green;
      case SjaStatus.avvist:
        return Colors.red;
      case SjaStatus.iGang:
        return Colors.teal;
      case SjaStatus.utlopt:
        return Colors.deepOrange;
    }
  }

  String get dbValue {
    switch (this) {
      case SjaStatus.venterSignatur:
        return 'venter_signatur';
      case SjaStatus.iGang:
        return 'i_gang';
      case SjaStatus.utlopt:
        return 'utlopt';
      default:
        return name;
    }
  }

  static SjaStatus fromDb(String? value) {
    switch (value) {
      case 'venter_signatur':
        return SjaStatus.venterSignatur;
      case 'i_gang':
        return SjaStatus.iGang;
      case 'utlopt':
        return SjaStatus.utlopt;
      case 'signert':
        return SjaStatus.signert;
      case 'godkjent':
        return SjaStatus.godkjent;
      case 'avvist':
        return SjaStatus.avvist;
      default:
        return SjaStatus.utkast;
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
  final DateTime? validFrom;
  final DateTime? validUntil;
  final int activeWindowHours;
  final String? qrToken;
  final int requiredSignatures;
  final DateTime? workStartedAt;
  final String? responsiblePerson;

  // Joined fields
  final String? creatorName;
  final String? responsiblePersonName;

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
    this.validFrom,
    this.validUntil,
    this.activeWindowHours = 8,
    this.qrToken,
    this.requiredSignatures = 1,
    this.workStartedAt,
    this.responsiblePerson,
    this.creatorName,
    this.responsiblePersonName,
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
      status: SjaStatusExtension.fromDb(json['status'] as String?),
      hazards: (json['hazards'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      measures: (json['measures'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      requiredPpe: (json['required_ppe'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      signedBy: (json['signed_by'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      signatureUrls: (json['signature_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      validFrom: json['valid_from'] != null
          ? DateTime.parse(json['valid_from'] as String)
          : null,
      validUntil: json['valid_until'] != null
          ? DateTime.parse(json['valid_until'] as String)
          : null,
      activeWindowHours: json['active_window_hours'] as int? ?? 8,
      qrToken: json['qr_token'] as String?,
      requiredSignatures: json['required_signatures'] as int? ?? 1,
      workStartedAt: json['work_started_at'] != null
          ? DateTime.parse(json['work_started_at'] as String)
          : null,
      responsiblePerson: json['responsible_person'] as String?,
      creatorName: json['profiles'] != null
          ? json['profiles']['full_name'] as String?
          : null,
      responsiblePersonName: json['responsible'] != null
          ? json['responsible']['full_name'] as String?
          : null,
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'company_id': companyId,
        'department_id': departmentId,
        'created_by': createdBy,
        'title': title,
        'work_description': workDescription,
        'location': location,
        'planned_date': plannedDate.toIso8601String().split('T').first,
        'status': status.dbValue,
        'hazards': hazards,
        'measures': measures,
        'required_ppe': requiredPpe,
        'active_window_hours': activeWindowHours,
        'required_signatures': requiredSignatures,
        if (responsiblePerson != null) 'responsible_person': responsiblePerson,
      };

  bool get isExpired =>
      validUntil != null && validUntil!.isBefore(DateTime.now());

  bool get canStartWork =>
      status == SjaStatus.signert || status == SjaStatus.godkjent;

  Duration? get remainingWindow {
    if (validUntil == null) return null;
    final diff = validUntil!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }
}
