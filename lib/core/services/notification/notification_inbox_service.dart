import '../../permissions/user_access.dart';
import '../../services/supabase_service.dart';
import '../../../models/notification_audit_entry.dart';
import 'notification_audit_service.dart';
import 'notification_inbox_scope.dart';

class NotificationInboxItem {
  final String id;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final String kind;
  final String? category;

  const NotificationInboxItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    required this.kind,
    this.category,
  });
}

class NotificationInboxSummary {
  final List<NotificationInboxItem> items;
  final int skippedCount;
  final int failedQueueCount;

  const NotificationInboxSummary({
    required this.items,
    this.skippedCount = 0,
    this.failedQueueCount = 0,
  });

  int get totalBadge => skippedCount + failedQueueCount + items.length;
}

class NotificationInboxService {
  NotificationInboxService._();

  static Future<NotificationInboxSummary> load({
    required UserAccess access,
    int limit = 40,
  }) async {
    final items = <NotificationInboxItem>[];

    try {
      final audit = await NotificationAuditService.fetch(
        limit: limit,
        offset: 0,
      );
      for (final a in audit) {
        if (!NotificationInboxScope.canSeeAuditEntry(
          access,
          category: a.category,
          settingKey: a.settingKey,
        )) {
          continue;
        }
        items.add(_fromAudit(a));
      }
    } catch (_) {}

    var skipped = 0;
    var failed = 0;
    for (final i in items) {
      if (i.kind == 'skipped') skipped++;
      if (i.kind == 'failed') failed++;
    }

    if (access.profile.isSuperAdmin) {
      try {
        final failedSms = await SupabaseService.client
            .from('sms_outbox')
            .select('id, created_at, category, description, error_message, to_phone')
            .filter('sent_at', 'is', null)
            .not('error_message', 'is', null)
            .order('created_at', ascending: false)
            .limit(15);
        for (final row in failedSms as List) {
          final map = Map<String, dynamic>.from(row as Map);
          final cat = map['category'] as String?;
          if (!NotificationInboxScope.canSeeFailedOutbox(
            access,
            isPartnerScope: (cat ?? '').contains('partner'),
          )) {
            continue;
          }
          failed++;
          items.add(NotificationInboxItem(
            id: 'sms_fail_${map['id']}',
            title: 'SMS ikke sendt',
            subtitle: map['description'] as String? ??
                map['error_message'] as String? ??
                map['to_phone'] as String? ??
                'Ukjent',
            createdAt: DateTime.parse(map['created_at'] as String),
            kind: 'failed',
            category: cat,
          ));
        }
      } catch (_) {}
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return NotificationInboxSummary(
      items: items.take(limit).toList(),
      skippedCount: skipped,
      failedQueueCount: failed,
    );
  }

  static NotificationInboxItem _fromAudit(NotificationAuditEntry a) {
    final isSkipped = a.status == 'skipped';
    return NotificationInboxItem(
      id: a.id,
      title: isSkipped ? 'Varsel hoppet over' : 'Varsel i kø',
      subtitle: [
        if (a.description != null && a.description!.isNotEmpty) a.description,
        if (a.skipReason != null && a.skipReason!.isNotEmpty) a.skipReason,
        if (a.recipient.isNotEmpty) '→ ${a.recipient}',
      ].whereType<String>().join(' · '),
      createdAt: a.createdAt,
      kind: isSkipped ? 'skipped' : 'queued',
      category: a.category ?? a.settingKey,
    );
  }
}
