import 'package:flutter/material.dart';

import '../../../core/services/notification/unified_notification_settings_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/notification_channel.dart';
import '../../../models/notification_event_definition.dart';
import 'notification_channel_picker.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

enum NotificationSettingsScope { all, mavi, partner }

/// Varseltyper fra Supabase — endring lagres umiddelbart.
class UnifiedNotificationSettingsPanel extends StatefulWidget {
  final NotificationSettingsScope scope;

  const UnifiedNotificationSettingsPanel({
    super.key,
    this.scope = NotificationSettingsScope.all,
  });

  @override
  State<UnifiedNotificationSettingsPanel> createState() =>
      _UnifiedNotificationSettingsPanelState();
}

class _UnifiedNotificationSettingsPanelState
    extends State<UnifiedNotificationSettingsPanel> {
  List<NotificationEventDefinition> _events = [];
  String? _companyId;
  bool _loading = true;
  String? _error;
  String? _savingEventId;
  int _routeAckReminderMinutes = 1440;
  int? _savingReminder;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      final cid = profile?.companyId;
      if (cid == null) {
        setState(() {
          _events = [];
          _loading = false;
        });
        return;
      }
      final events = await UnifiedNotificationSettingsService.fetchEvents(cid);
      var reminder = 1440;
      if (widget.scope != NotificationSettingsScope.mavi) {
        reminder =
            await UnifiedNotificationSettingsService.fetchRouteAckReminderMinutes(
          cid,
        );
      }
      if (!mounted) return;
      setState(() {
        _companyId = cid;
        _events = _scopeFilter(events);
        _routeAckReminderMinutes = reminder;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _onChannelChanged(
    NotificationEventDefinition event,
    NotificationChannel channel,
  ) async {
    if (_companyId == null) return;

    setState(() {
      _savingEventId = event.id;
      _events = _events
          .map((e) => e.id == event.id ? e.copyWith(channel: channel) : e)
          .toList();
    });

    try {
      await UnifiedNotificationSettingsService.setChannel(
        companyId: _companyId!,
        eventId: event.id,
        channel: channel,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('«${event.title}» lagret (${channel.label})'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingEventId = null);
    }
  }

  Future<void> _saveReminder(int minutes) async {
    if (_companyId == null) return;
    setState(() => _savingReminder = minutes);
    try {
      await UnifiedNotificationSettingsService.setRouteAckReminderMinutes(
        companyId: _companyId!,
        minutes: minutes,
      );
      if (mounted) {
        setState(() => _routeAckReminderMinutes = minutes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purring satt til $minutes min')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre purring: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingReminder = null);
    }
  }

  List<NotificationEventDefinition> _scopeFilter(
    List<NotificationEventDefinition> events,
  ) {
    switch (widget.scope) {
      case NotificationSettingsScope.mavi:
        return events.where((e) => e.isMavi).toList();
      case NotificationSettingsScope.partner:
        return events.where((e) => e.isPartner).toList();
      case NotificationSettingsScope.all:
        return events;
    }
  }

  List<NotificationEventDefinition> get _filtered {
    if (_filter.trim().isEmpty) return _events;
    final q = _filter.toLowerCase();
    return _events.where((e) {
      return e.title.toLowerCase().contains(q) ||
          (e.subtitle ?? '').toLowerCase().contains(q) ||
          e.categoryGroup.toLowerCase().contains(q) ||
          e.settingKey.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const DriftProLoadingCenter();
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Prøv igjen')),
            ],
          ),
        ),
      );
    }

    final showMavi = widget.scope != NotificationSettingsScope.partner;
    final showPartner = widget.scope != NotificationSettingsScope.mavi;
    final mavi = showMavi ? _filtered.where((e) => e.isMavi).toList() : <NotificationEventDefinition>[];
    final partner = showPartner ? _filtered.where((e) => e.isPartner).toList() : <NotificationEventDefinition>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Alle varseltyper hentes fra Supabase. Hver endring lagres '
                  'umiddelbart og styrer SMS/e-post i sanntid.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Søk i varsler…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Chip(
                    label: Text('${_events.length} typer'),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      '${_events.where((e) => e.channel == NotificationChannel.none).length} av',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (partner.isNotEmpty) ...[
                  _scopeHeader('Samarbeid — partnere', Icons.handshake_outlined,
                      Colors.orange.shade800),
                  ..._buildGrouped(partner),
                  const SizedBox(height: 24),
                ],
                if (mavi.isNotEmpty) ...[
                  _scopeHeader('MAVI — ansatte', Icons.badge_outlined,
                      DriftProTheme.primaryGreen),
                  ..._buildGrouped(mavi),
                ],
                if (mavi.isEmpty && partner.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('Ingen treff')),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _scopeHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Text(title, style: DriftProTheme.headingSm),
        ],
      ),
    );
  }

  Widget _routeReminderMinutesField() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 20, color: DriftProTheme.primaryGreen),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Purringstid etter utsendelse',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          SizedBox(
            width: 100,
            child: TextFormField(
              key: ValueKey(_routeAckReminderMinutes),
              initialValue: '$_routeAckReminderMinutes',
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                suffixText: 'min',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _savingReminder != null
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              onFieldSubmitted: (v) {
                final m = int.tryParse(v);
                if (m != null && m >= 15 && m <= 10080) _saveReminder(m);
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGrouped(List<NotificationEventDefinition> events) {
    final groups = <String, List<NotificationEventDefinition>>{};
    for (final e in events) {
      groups.putIfAbsent(e.categoryGroup, () => []).add(e);
    }

    final widgets = <Widget>[];
    for (final entry in groups.entries) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(entry.key, style: DriftProTheme.labelLg),
        ),
      );
      for (final event in entry.value) {
        final saving = _savingEventId == event.id;
        widgets.add(
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (saving)
                        SizedBox(width: 18, height: 18, child: DriftProLoadingIndicator(size: 18)),
                    ],
                  ),
                  if (event.subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.subtitle!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Nøkkel: ${event.settingKey}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 8),
                  NotificationChannelPicker(
                    value: event.channel,
                    onChanged: saving
                        ? (_) {}
                        : (ch) => _onChannelChanged(event, ch),
                  ),
                  if (event.id == 'partner_route_reminder')
                    _routeReminderMinutesField(),
                ],
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }
}
