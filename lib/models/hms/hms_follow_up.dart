class HmsFollowUp {
  final String id;
  final String companyId;
  final String module;
  final String referenceType;
  final String referenceId;
  final String title;
  final String? summary;
  final int deviationCount;
  final DateTime? followUpDueAt;
  final String status;
  final DateTime? closedAt;
  final String? closedBy;
  final String? closeNotes;
  final bool sendEmail;
  final bool sendPush;
  final String? createdBy;
  final DateTime? createdAt;
  final List<String> recipientIds;

  const HmsFollowUp({
    required this.id,
    required this.companyId,
    required this.module,
    required this.referenceType,
    required this.referenceId,
    required this.title,
    this.summary,
    this.deviationCount = 1,
    this.followUpDueAt,
    this.status = 'open',
    this.closedAt,
    this.closedBy,
    this.closeNotes,
    this.sendEmail = true,
    this.sendPush = true,
    this.createdBy,
    this.createdAt,
    this.recipientIds = const [],
  });

  bool get isOpen => status == 'open';

  factory HmsFollowUp.fromJson(Map<String, dynamic> json) {
    final recipients = <String>[];
    final rawRecipients = json['hms_follow_up_recipients'];
    if (rawRecipients is List) {
      for (final r in rawRecipients) {
        if (r is Map && r['profile_id'] != null) {
          recipients.add(r['profile_id'].toString());
        }
      }
    }
    return HmsFollowUp(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      module: json['module'] as String? ?? 'hms',
      referenceType: json['reference_type'] as String? ?? '',
      referenceId: json['reference_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String?,
      deviationCount: (json['deviation_count'] as num?)?.toInt() ?? 1,
      followUpDueAt: json['follow_up_due_at'] != null
          ? DateTime.tryParse(json['follow_up_due_at'].toString())
          : null,
      status: json['status'] as String? ?? 'open',
      closedAt: json['closed_at'] != null
          ? DateTime.tryParse(json['closed_at'].toString())
          : null,
      closedBy: json['closed_by'] as String?,
      closeNotes: json['close_notes'] as String?,
      sendEmail: json['send_email'] as bool? ?? true,
      sendPush: json['send_push'] as bool? ?? true,
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      recipientIds: recipients,
    );
  }
}
