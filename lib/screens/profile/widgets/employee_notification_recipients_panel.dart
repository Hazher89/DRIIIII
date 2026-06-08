import 'package:flutter/material.dart';

import '../../../core/services/notification/employee_notification_recipients_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/notification_channel.dart';
import '../../../models/notification_recipient_row.dart';
import 'notification_channel_picker.dart';

enum _ViewMode { byEmployee, byEvent }

/// Hvem får hvilke varsler — lagres umiddelbart i Supabase.
class EmployeeNotificationRecipientsPanel extends StatefulWidget {
  const EmployeeNotificationRecipientsPanel({
    super.key,
    this.initialEventId,
  });

  /// Åpne direkte på en varseltype (f.eks. partner_route_pending_internal).
  final String? initialEventId;

  @override
  State<EmployeeNotificationRecipientsPanel> createState() =>
      _EmployeeNotificationRecipientsPanelState();
}

class _EmployeeNotificationRecipientsPanelState
    extends State<EmployeeNotificationRecipientsPanel> {
  List<NotificationRecipientRow> _rows = [];
  String? _companyId;
  bool _loading = true;
  String? _error;
  _ViewMode _viewMode = _ViewMode.byEmployee;
  String _search = '';
  String? _selectedProfileId;
  String? _selectedEventId;
  String? _savingKey;
  bool _sendingDigest = false;

  static const _pendingRoutesEventId = 'partner_route_pending_internal';

  @override
  void initState() {
    super.initState();
    if (widget.initialEventId != null) {
      _viewMode = _ViewMode.byEvent;
      _selectedEventId = widget.initialEventId;
    }
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
          _rows = [];
          _loading = false;
        });
        return;
      }
      final rows = await EmployeeNotificationRecipientsService.fetchMatrix(cid);
      if (!mounted) return;
      setState(() {
        _companyId = cid;
        _rows = rows;
        _loading = false;
        _selectedProfileId ??= _employees.firstOrNull?.id;
        _selectedEventId ??=
            widget.initialEventId ?? _events.firstOrNull?.id;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<_EmployeeSummary> get _employees {
    final map = <String, _EmployeeSummary>{};
    for (final r in _rows) {
      map.putIfAbsent(
        r.profileId,
        () => _EmployeeSummary(
          id: r.profileId,
          name: r.profileName,
          email: r.profileEmail,
          role: r.profileRole,
          department: r.departmentName,
        ),
      );
    }
    final list = map.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    if (_search.trim().isEmpty) return list;
    final q = _search.toLowerCase();
    return list
        .where(
          (e) =>
              e.name.toLowerCase().contains(q) ||
              e.email.toLowerCase().contains(q) ||
              e.role.toLowerCase().contains(q) ||
              (e.department ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  List<_EventSummary> get _events {
    final map = <String, _EventSummary>{};
    for (final r in _rows) {
      map.putIfAbsent(
        r.eventId,
        () => _EventSummary(
          id: r.eventId,
          title: r.eventTitle,
          category: r.categoryGroup,
          rule: r.defaultRecipientRule,
        ),
      );
    }
    return map.values.toList()
      ..sort((a, b) {
        final c = a.category.compareTo(b.category);
        return c != 0 ? c : a.title.compareTo(b.title);
      });
  }

  int _activeCountForProfile(String profileId) =>
      _rows.where((r) => r.profileId == profileId && r.subscribed && r.channel != NotificationChannel.none).length;

  int _activeCountForEvent(String eventId) =>
      _rows.where((r) => r.eventId == eventId && r.subscribed && r.channel != NotificationChannel.none).length;

  Future<void> _setChannel(NotificationRecipientRow row, NotificationChannel channel) async {
    if (_companyId == null) return;
    final key = '${row.profileId}:${row.eventId}';
    final subscribed = channel != NotificationChannel.none;
    setState(() {
      _savingKey = key;
      _rows = _rows
          .map(
            (r) => r.profileId == row.profileId && r.eventId == row.eventId
                ? r.copyWith(subscribed: subscribed, channel: channel, isExplicit: true)
                : r,
          )
          .toList();
    });
    try {
      await EmployeeNotificationRecipientsService.setSubscription(
        companyId: _companyId!,
        profileId: row.profileId,
        eventId: row.eventId,
        subscribed: subscribed,
        channel: channel,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              subscribed
                  ? '${row.profileName}: «${row.eventTitle}» → ${channel.label}'
                  : '${row.profileName} får ikke «${row.eventTitle}»',
            ),
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
      if (mounted) setState(() => _savingKey = null);
    }
  }

  Future<void> _sendPendingRoutesDigest() async {
    if (_companyId == null) return;
    setState(() => _sendingDigest = true);
    try {
      final result = await EmployeeNotificationRecipientsService
          .sendPendingRoutesDigestNow(companyId: _companyId!);
      if (!mounted) return;
      final ok = result['ok'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message'] as String? ??
                (ok ? 'Oppsummering sendt' : 'Kunne ikke sende'),
          ),
          backgroundColor: ok ? null : Colors.orange.shade800,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke sende: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingDigest = false);
    }
  }

  void _openPendingRoutesRecipients() {
    setState(() {
      _viewMode = _ViewMode.byEvent;
      _selectedEventId = _pendingRoutesEventId;
      _search = '';
    });
  }

  Future<void> _resetProfile(String profileId) async {
    if (_companyId == null) return;
    final emp = _employees.firstWhere((e) => e.id == profileId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tilbakestill standard'),
        content: Text(
          'Fjerne alle manuelle valg for ${emp.name} og bruke systemets standardregler?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tilbakestill')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await EmployeeNotificationRecipientsService.resetSubscriptions(
        companyId: _companyId!,
        profileId: profileId,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Standard gjenopprettet for ${emp.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
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

    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              _infoBanner(),
              const SizedBox(height: 10),
              _pendingRoutesActionBar(),
              const SizedBox(height: 10),
              SegmentedButton<_ViewMode>(
                segments: const [
                  ButtonSegment(
                    value: _ViewMode.byEmployee,
                    label: Text('Per ansatt'),
                    icon: Icon(Icons.person_outline, size: 18),
                  ),
                  ButtonSegment(
                    value: _ViewMode.byEvent,
                    label: Text('Per varseltype'),
                    icon: Icon(Icons.notifications_outlined, size: 18),
                  ),
                ],
                selected: {_viewMode},
                onSelectionChanged: (s) => setState(() => _viewMode = s.first),
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: InputDecoration(
                  hintText: _viewMode == _ViewMode.byEmployee
                      ? 'Søk ansatt…'
                      : 'Søk varseltype…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: wide ? _buildWide() : _buildNarrow(),
          ),
        ),
      ],
    );
  }

  Widget _buildWide() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _viewMode == _ViewMode.byEmployee
              ? _employeeList()
              : _eventList(),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 3,
          child: _viewMode == _ViewMode.byEmployee
              ? _eventsForSelectedEmployee()
              : _employeesForSelectedEvent(),
        ),
      ],
    );
  }

  Widget _buildNarrow() {
    if (_viewMode == _ViewMode.byEmployee) {
      if (_selectedProfileId == null) return _employeeList();
      return Column(
        children: [
          _narrowBackBar(
            title: _employees
                    .where((e) => e.id == _selectedProfileId)
                    .firstOrNull
                    ?.name ??
                'Ansatt',
            onBack: () => setState(() => _selectedProfileId = null),
            onReset: () => _resetProfile(_selectedProfileId!),
          ),
          Expanded(child: _eventsForSelectedEmployee()),
        ],
      );
    }
    if (_selectedEventId == null) return _eventList();
    return Column(
      children: [
        _narrowBackBar(
          title: _events.where((e) => e.id == _selectedEventId).firstOrNull?.title ?? 'Varsel',
          onBack: () => setState(() => _selectedEventId = null),
        ),
        Expanded(child: _employeesForSelectedEvent()),
      ],
    );
  }

  Widget _narrowBackBar({
    required String title,
    required VoidCallback onBack,
    VoidCallback? onReset,
  }) {
    return Material(
      color: Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
            Expanded(child: Text(title, style: DriftProTheme.labelLg)),
            if (onReset != null)
              TextButton(onPressed: onReset, child: const Text('Standard')),
          ],
        ),
      ),
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kun valgte mottakere får SMS/e-post. Ingen varsler sendes automatisk '
            'til alle ledere eller admin — du må aktivt velge hvem som skal motta hva.',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          Text(
            'Automatisk daglig SMS «ruter venter på partner-aksept» er slått av. '
            'Velg mottakere under, og send oppsummering manuelt når du trenger den.\n\n'
            'Andre varsler som tidligere kunne gå til mange (nå kun ved eksplisitt valg): '
            'partner avviste rute, SAP rute-PDF, bilutleie internt, ny ansatt venter godkjenning, '
            'fravær, utstyr og generelle HMS-varsler.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _pendingRoutesActionBar() {
    final selectedCount = _activeCountForEvent(_pendingRoutesEventId);
    final onPendingEvent = _selectedEventId == _pendingRoutesEventId;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route_outlined, color: DriftProTheme.primaryGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ruter venter på partner-aksept',
                    style: DriftProTheme.labelLg,
                  ),
                ),
                Chip(
                  label: Text('$selectedCount valgt'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Daglig automatisk SMS er av. Velg hvem som skal få oppsummeringen, '
              'og trykk «Send nå» når du vil varsle dem.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onPendingEvent ? null : _openPendingRoutesRecipients,
                  icon: const Icon(Icons.people_outline, size: 18),
                  label: const Text('Velg mottakere'),
                ),
                FilledButton.icon(
                  onPressed: _sendingDigest || selectedCount == 0
                      ? null
                      : _sendPendingRoutesDigest,
                  icon: _sendingDigest
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Send oppsummering nå'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _employeeList() {
    final items = _employees;
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final e = items[i];
        final selected = e.id == _selectedProfileId;
        final active = _activeCountForProfile(e.id);
        return ListTile(
          selected: selected,
          title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${e.role}${e.department != null ? ' · ${e.department}' : ''}'),
          trailing: Chip(
            label: Text('$active'),
            visualDensity: VisualDensity.compact,
          ),
          onTap: () => setState(() => _selectedProfileId = e.id),
        );
      },
    );
  }

  Widget _eventList() {
    final q = _search.toLowerCase();
    final items = _events
        .where(
          (e) =>
              q.isEmpty ||
              e.title.toLowerCase().contains(q) ||
              e.category.toLowerCase().contains(q),
        )
        .toList();
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final e = items[i];
        final selected = e.id == _selectedEventId;
        final active = _activeCountForEvent(e.id);
        return ListTile(
          selected: selected,
          title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            e.id == _pendingRoutesEventId
                ? '${e.category} · manuell oppsummering'
                : e.category,
          ),
          trailing: Chip(label: Text('$active'), visualDensity: VisualDensity.compact),
          onTap: () => setState(() => _selectedEventId = e.id),
        );
      },
    );
  }

  Widget _eventsForSelectedEmployee() {
    final pid = _selectedProfileId;
    if (pid == null) {
      return const Center(child: Text('Velg en ansatt'));
    }
    final emp = _employees.where((e) => e.id == pid).firstOrNull;
    final events = _rows.where((r) => r.profileId == pid).toList();
    String? lastGroup;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (emp != null && MediaQuery.sizeOf(context).width >= 900) ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(emp.name, style: DriftProTheme.headingSm),
                    Text('${emp.email} · ${emp.role}'),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _resetProfile(pid),
                child: const Text('Tilbakestill standard'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        ...events.expand((row) {
          final widgets = <Widget>[];
          if (row.categoryGroup != lastGroup) {
            lastGroup = row.categoryGroup;
            widgets.add(
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Text(row.categoryGroup, style: DriftProTheme.labelLg),
              ),
            );
          }
          widgets.add(_subscriptionTile(row));
          return widgets;
        }),
      ],
    );
  }

  Widget _employeesForSelectedEvent() {
    final eid = _selectedEventId;
    if (eid == null) {
      return const Center(child: Text('Velg en varseltype'));
    }
    final event = _events.where((e) => e.id == eid).firstOrNull;
    final rows = _rows.where((r) => r.eventId == eid).toList();
    final q = _search.toLowerCase();
    final filtered = q.isEmpty
        ? rows
        : rows.where(
            (r) =>
                r.profileName.toLowerCase().contains(q) ||
                r.profileEmail.toLowerCase().contains(q),
          );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (event != null && MediaQuery.sizeOf(context).width >= 900) ...[
          Text(event.title, style: DriftProTheme.headingSm),
          Text(
            event.id == _pendingRoutesEventId
                ? 'Automatisk daglig utsending er av — kun manuelt eller ved valg'
                : 'Kun eksplisitt valgte mottakere får varsel',
          ),
          const SizedBox(height: 8),
        ],
        ...filtered.map(_subscriptionTile),
      ],
    );
  }

  Widget _subscriptionTile(NotificationRecipientRow row) {
    final key = '${row.profileId}:${row.eventId}';
    final saving = _savingKey == key;
    final effectiveChannel =
        row.subscribed && row.channel != NotificationChannel.none ? row.channel : NotificationChannel.none;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _viewMode == _ViewMode.byEmployee ? row.eventTitle : row.profileName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              _viewMode == _ViewMode.byEmployee
                  ? (row.isExplicit ? 'Manuelt valg' : 'Ikke valgt')
                  : '${row.profileRole}${row.departmentName != null ? ' · ${row.departmentName}' : ''}${row.isExplicit ? ' · manuelt' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            if (saving)
              const LinearProgressIndicator(minHeight: 2)
            else
              NotificationChannelPicker(
                compact: true,
                value: effectiveChannel,
                onChanged: (ch) => _setChannel(row, ch),
              ),
          ],
        ),
      ),
    );
  }

}

class _EmployeeSummary {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? department;

  _EmployeeSummary({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.department,
  });
}

class _EventSummary {
  final String id;
  final String title;
  final String category;
  final String rule;

  _EventSummary({
    required this.id,
    required this.title,
    required this.category,
    required this.rule,
  });
}
