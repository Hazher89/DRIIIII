import '../../permissions/user_access.dart';
import '../../services/supabase_service.dart';
import '../../../models/notification_audit_entry.dart';
import 'notification_audit_service.dart';
import 'notification_inbox_scope.dart';

class NotificationInboxItem {
  final String dismissKey;
  final String title;
  final String subtitle;
  final String detailLine;
  final DateTime createdAt;
  final String kind;
  final String? category;
  final String channelLabel;
  final bool isDismissed;

  const NotificationInboxItem({
    required this.dismissKey,
    required this.title,
    required this.subtitle,
    required this.detailLine,
    required this.createdAt,
    required this.kind,
    this.category,
    required this.channelLabel,
    this.isDismissed = false,
  });
}

class NotificationInboxSummary {
  final List<NotificationInboxItem> items;

  const NotificationInboxSummary({required this.items});

  int get unreadCount => items.where((i) => !i.isDismissed).length;
}

class NotificationInboxService {
  NotificationInboxService._();

  static String _formatRecipient(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '—';
    final digits = t.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10 && digits.startsWith('47')) {
      return '+${digits.substring(0, 2)} ${digits.substring(2, 4)} ${digits.substring(4, 6)} ${digits.substring(6)}';
    }
    if (digits.length == 8) {
      return '+47 ${digits.substring(0, 2)} ${digits.substring(2, 4)} ${digits.substring(4)}';
    }
    return t;
  }

  static Future<NotificationInboxSummary> load({
    required UserAccess access,
    int limit = 40,
    bool excludeDismissed = true,
  }) async {
    final items = <NotificationInboxItem>[];

    try {
      final audit = await NotificationAuditService.fetch(
        limit: limit,
        offset: 0,
        excludeDismissed: excludeDismissed,
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

    final dismissedKeys = excludeDismissed ? await _fetchDismissedKeys() : <String>{};

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
          final dismissKey = 'sms_fail_${map['id']}';
          if (excludeDismissed && dismissedKeys.contains(dismissKey)) continue;
          final cat = map['category'] as String?;
          if (!NotificationInboxScope.canSeeFailedOutbox(
            access,
            isPartnerScope: (cat ?? '').contains('partner'),
          )) {
            continue;
          }
          final phone = map['to_phone'] as String? ?? '';
          items.add(NotificationInboxItem(
            dismissKey: dismissKey,
            title: 'SMS — sending feilet',
            subtitle: map['description'] as String? ?? 'Kunne ikke sende melding',
            detailLine: 'Til: ${_formatRecipient(phone)}',
            createdAt: DateTime.parse(map['created_at'] as String),
            kind: 'failed',
            category: cat,
            channelLabel: 'SMS',
          ));
        }
      } catch (_) {}
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return NotificationInboxSummary(
      items: items.take(limit).toList(),
    );
  }

  static Future<Set<String>> _fetchDismissedKeys() async {
    try {
      final uid = SupabaseService.client.auth.currentUser?.id;
      if (uid == null) return {};
      final rows = await SupabaseService.client
          .from('notification_inbox_dismissals')
          .select('dismiss_key')
          .eq('user_id', uid)
          .limit(500);
      return (rows as List)
          .map((e) => (e as Map<String, dynamic>)['dismiss_key'] as String)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static NotificationInboxItem _fromAudit(NotificationAuditEntry a) {
    final recipient = _formatRecipient(a.recipient);
    final what = a.messagePreview ?? a.description ?? a.category ?? 'Varsel';
    final partner = a.partnerName?.trim();
    final detailParts = <String>[
      'Til: $recipient',
      if (partner != null && partner.isNotEmpty) 'Bedrift: $partner',
      if (a.skipReason != null && a.deliveryStatus == 'skipped') a.skipReasonLabel,
    ];

    return NotificationInboxItem(
      dismissKey: a.id,
      title: '${a.channelLabel} — ${a.deliveryStatusLabel}',
      subtitle: what,
      detailLine: detailParts.join(' · '),
      createdAt: a.createdAt,
      kind: a.deliveryStatus == 'skipped'
          ? 'skipped'
          : a.deliveryStatus == 'failed'
              ? 'failed'
              : a.deliveryStatus == 'sent'
                  ? 'sent'
                  : 'queued',
      category: a.category ?? a.settingKey,
      channelLabel: a.channelLabel,
      isDismissed: a.isDismissed,
    );
  }

  static Future<void> dismiss(Iterable<String> dismissKeys) async {
    final keys = dismissKeys.where((k) => k.isNotEmpty).toList();
    if (keys.isEmpty) return;
    await SupabaseService.client.rpc('dismiss_notification_inbox', params: {
      'p_keys': keys,
    });
  }

  static Future<int> dismissAll() async {
    final n = await SupabaseService.client.rpc('dismiss_all_notification_inbox');
    return (n as num?)?.toInt() ?? 0;
  }
}
