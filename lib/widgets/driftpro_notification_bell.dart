import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/constants/app_icons.dart';
import '../core/permissions/user_access.dart';
import '../core/services/notification/notification_inbox_service.dart';
import '../core/services/supabase_service.dart';
import '../core/theme/app_theme.dart';
import '../models/user_profile.dart';
import 'driftpro_loading_indicator.dart';

/// Global varselbjelle — kun hendelser brukeren har tilgang til.
class DriftproNotificationBell extends StatefulWidget {
  const DriftproNotificationBell({super.key});

  @override
  State<DriftproNotificationBell> createState() => _DriftproNotificationBellState();
}

class _DriftproNotificationBellState extends State<DriftproNotificationBell> {
  NotificationInboxSummary? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final profile = await SupabaseService.fetchCurrentUserProfile();
    final access = UserAccess.of(profile);
    if (access == null ||
        (!access.canNotifications && !access.canPartnersMenu && !access.profile.isSuperAdmin)) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final summary = await NotificationInboxService.load(
        access: access,
        excludeDismissed: true,
      );
      if (mounted) {
        setState(() {
          _summary = summary;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _dismissShown(NotificationInboxSummary? summary) async {
    if (summary == null || summary.items.isEmpty) return;
    await NotificationInboxService.dismiss(
      summary.items.map((i) => i.dismissKey),
    );
    await _refresh();
  }

  Future<void> _openSheet() async {
    await _refresh();
    if (!mounted) return;
    final summary = _summary;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Varsler',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (summary != null && summary.items.isNotEmpty)
                      TextButton(
                        onPressed: () async {
                          await NotificationInboxService.dismissAll();
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: const Text('Tøm varsler'),
                      ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.push('/more');
                      },
                      child: const Text('Varselsenter'),
                    ),
                  ],
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: const DriftProLoadingCenter(),
                  )
                else if (summary == null || summary.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Ingen uleste varsler akkurat nå.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.55,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: summary.items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final item = summary.items[i];
                        final icon = switch (item.kind) {
                          'failed' => Icons.error_outline,
                          'skipped' => Icons.block,
                          'sent' => Icons.check_circle_outline,
                          _ => Icons.schedule_send_outlined,
                        };
                        final color = switch (item.kind) {
                          'failed' => DriftProTheme.error,
                          'skipped' => Colors.orange.shade800,
                          'sent' => DriftProTheme.primaryGreen,
                          _ => Colors.blue.shade700,
                        };
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          leading: Icon(icon, color: color),
                          title: Text(
                            item.title,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.detailLine,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                          trailing: Text(
                            DateFormat('d.M HH:mm').format(item.createdAt.toLocal()),
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    await _dismissShown(summary);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: SupabaseService.fetchCurrentUserProfile(),
      builder: (context, snap) {
        final profile = snap.data;
        final access = UserAccess.of(profile);
        if (access == null ||
            (!access.canNotifications &&
                !access.canPartnersMenu &&
                !access.profile.isSuperAdmin)) {
          return const SizedBox.shrink();
        }
        final count = _summary?.unreadCount ?? 0;
        return IconButton(
          tooltip: 'Varsler',
          onPressed: _openSheet,
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text('$count', style: const TextStyle(fontSize: 9)),
            child: Icon(
              AppIcons.notification,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black87,
            ),
          ),
        );
      },
    );
  }
}
