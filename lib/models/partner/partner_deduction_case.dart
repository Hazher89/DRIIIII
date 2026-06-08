class PartnerDeductionCase {
  const PartnerDeductionCase({
    required this.id,
    required this.companyId,
    required this.partnerId,
    required this.partnerName,
    required this.caseNumber,
    this.traceRef,
    this.traceCode,
    required this.templateId,
    required this.templateTitle,
    required this.shortDescription,
    this.comment,
    required this.amountNok,
    required this.status,
    this.createdBy,
    this.createdByName,
    required this.createdAt,
    this.notifiedAt,
    required this.smsSent,
    required this.emailSent,
    this.invoicedAt,
    this.invoicedBy,
    this.invoicedByName,
    this.evidenceCount = 0,
    this.logiqrmaCaseNumber,
    this.voucherNumber,
    this.logisticsDescription,
    this.isLocked = false,
    this.lockedAt,
    this.unlockedAt,
    this.unlockedByName,
    this.deletedAt,
    this.deletedByName,
    this.deletionComment,
  });

  final String id;
  final String companyId;
  final String partnerId;
  final String partnerName;
  final String caseNumber;
  final String? traceRef;
  final String? traceCode;
  final String templateId;
  final String templateTitle;
  final String shortDescription;
  final String? comment;
  final double amountNok;
  final String status;
  final String? createdBy;
  final String? createdByName;
  final DateTime createdAt;
  final DateTime? notifiedAt;
  final bool smsSent;
  final bool emailSent;
  final DateTime? invoicedAt;
  final String? invoicedBy;
  final String? invoicedByName;
  final int evidenceCount;
  final String? logiqrmaCaseNumber;
  final String? voucherNumber;
  final String? logisticsDescription;
  final bool isLocked;
  final DateTime? lockedAt;
  final DateTime? unlockedAt;
  final String? unlockedByName;
  final DateTime? deletedAt;
  final String? deletedByName;
  final String? deletionComment;

  bool get isDeleted => deletedAt != null || status == 'deleted';
  bool get isInvoiced => status == 'invoiced' || (invoicedAt != null && !isDeleted);
  bool get isEditable => !isLocked && !isDeleted;
  bool get hasLogiqrmaRef =>
      (logiqrmaCaseNumber?.isNotEmpty ?? false) ||
      (voucherNumber?.isNotEmpty ?? false);
  bool get isNotified => status == 'notified' || smsSent || emailSent;
  String get displayTraceRef => traceRef ?? caseNumber;

  PartnerDeductionCase copyPreservingListFields(PartnerDeductionCase source) {
    return PartnerDeductionCase(
      id: id,
      companyId: companyId,
      partnerId: partnerId,
      partnerName: source.partnerName,
      caseNumber: caseNumber,
      traceRef: traceRef,
      traceCode: traceCode,
      templateId: templateId,
      templateTitle: templateTitle,
      shortDescription: shortDescription,
      comment: comment,
      amountNok: amountNok,
      status: status,
      createdBy: createdBy,
      createdByName: createdByName,
      createdAt: createdAt,
      notifiedAt: notifiedAt,
      smsSent: smsSent,
      emailSent: emailSent,
      invoicedAt: invoicedAt,
      invoicedBy: invoicedBy,
      invoicedByName: invoicedByName,
      evidenceCount: source.evidenceCount,
      logiqrmaCaseNumber: logiqrmaCaseNumber,
      voucherNumber: voucherNumber,
      logisticsDescription: logisticsDescription,
      isLocked: isLocked,
      lockedAt: lockedAt,
      unlockedAt: unlockedAt,
      unlockedByName: unlockedByName,
      deletedAt: deletedAt,
      deletedByName: deletedByName,
      deletionComment: deletionComment,
    );
  }

  factory PartnerDeductionCase.fromJson(Map<String, dynamic> json) {
    return PartnerDeductionCase(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      partnerId: json['partner_id'] as String,
      partnerName: json['partner_name'] as String? ?? '',
      caseNumber: json['case_number'] as String,
      traceRef: json['trace_ref'] as String?,
      traceCode: json['trace_code'] as String?,
      templateId: json['template_id'] as String,
      templateTitle: json['template_title'] as String,
      shortDescription: json['short_description'] as String,
      comment: json['comment'] as String?,
      amountNok: (json['amount_nok'] as num?)?.toDouble() ?? 500,
      status: json['status'] as String? ?? 'registered',
      createdBy: json['created_by'] as String?,
      createdByName: json['created_by_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      notifiedAt: json['notified_at'] != null
          ? DateTime.parse(json['notified_at'] as String)
          : null,
      smsSent: json['sms_sent'] as bool? ?? false,
      emailSent: json['email_sent'] as bool? ?? false,
      invoicedAt: json['invoiced_at'] != null
          ? DateTime.parse(json['invoiced_at'] as String)
          : null,
      invoicedBy: json['invoiced_by'] as String?,
      invoicedByName: json['invoiced_by_name'] as String?,
      evidenceCount: (json['evidence_count'] as num?)?.toInt() ?? 0,
      logiqrmaCaseNumber: json['logiqrma_case_number'] as String?,
      voucherNumber: json['voucher_number'] as String?,
      logisticsDescription: json['logistics_description'] as String?,
      isLocked: json['is_locked'] as bool? ?? false,
      lockedAt: json['locked_at'] != null
          ? DateTime.parse(json['locked_at'] as String)
          : null,
      unlockedAt: json['unlocked_at'] != null
          ? DateTime.parse(json['unlocked_at'] as String)
          : null,
      unlockedByName: json['unlocked_by_name'] as String?,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
      deletedByName: json['deleted_by_name'] as String?,
      deletionComment: json['deletion_comment'] as String?,
    );
  }
}
