import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/constants/app_icons.dart';
import '../core/permissions/user_access.dart';
import '../core/services/notification/notification_inbox_service.dart';
import '../core/services/supabase_service.dart';
import '../core/theme/app_theme.dart';
import '../models/user_profile.dart';

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
      final summary = await NotificationInboxService.load(access: access);
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
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.push('/more');
                      },
                      child: const Text('Åpne varselsenter'),
                    ),
                  ],
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (summary == null || summary.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Ingen varsler i ditt tilgangsområde akkurat nå.',
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
                        final icon = item.kind == 'failed'
                            ? Icons.error_outline
                            : item.kind == 'skipped'
                                ? Icons.block
                                : Icons.schedule_send_outlined;
                        final color = item.kind == 'failed'
                            ? DriftProTheme.error
                            : item.kind == 'skipped'
                                ? Colors.orange.shade800
                                : DriftProTheme.primaryGreen;
                        return ListTile(
                          leading: Icon(icon, color: color),
                          title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(item.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
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
        final count = _summary?.totalBadge ?? 0;
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
