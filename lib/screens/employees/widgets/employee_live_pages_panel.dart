import 'package:flutter/material.dart';

import '../../../core/permissions/access_actions.dart';
import '../../../core/permissions/access_area_catalog.dart';
import '../../../core/permissions/access_normalize.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';

/// Superadmin: slå hele sider av/på per ansatt. Lagres med en gang.
class EmployeeLivePagesPanel extends StatefulWidget {
  const EmployeeLivePagesPanel({
    super.key,
    required this.employee,
    required this.settings,
    required this.onSettings,
  });

  final UserProfile employee;
  final Map<String, dynamic> settings;
  final ValueChanged<Map<String, dynamic>> onSettings;

  @override
  State<EmployeeLivePagesPanel> createState() => _EmployeeLivePagesPanelState();
}

class _EmployeeLivePagesPanelState extends State<EmployeeLivePagesPanel> {
  late AccessSettingsDoc _doc;
  bool _busy = false;
  String? _status;
  final _title = TextEditingController();
  String? _linkAreaId;

  @override
  void initState() {
    super.initState();
    _doc = AccessSettingsDoc.fromJson(widget.settings);
    _linkAreaId = _linkChoices.isEmpty ? null : _linkChoices.first.id;
  }

  @override
  void didUpdateWidget(EmployeeLivePagesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings && !_busy) {
      _doc = AccessSettingsDoc.fromJson(widget.settings);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  List<AccessAreaDef> get _pages => AccessAreaCatalog.areas
      .where((a) => a.id != 'more')
      .toList();

  List<AccessAreaDef> get _linkChoices => AccessAreaCatalog.areas
      .where((a) => a.routePath != null && a.routePath!.startsWith('/'))
      .toList();

  bool _visible(AccessAreaDef area) => _doc.get(area.id, AccessAction.view);

  Future<void> _persist(String message) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final json = _doc.toJson();
      await SupabaseService.updateProfileAccess(widget.employee.id, json);
      widget.onSettings(json);
      if (!mounted) return;
      setState(() => _status = message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Kunne ikke lagre: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(AccessAreaDef area, bool on) async {
    if (on) {
      _doc.set(area.id, AccessAction.view, true);
      _doc.ensureParentViews(area.id);
    } else {
      _doc.setAreaAll(area.id, false);
    }
    await _persist(on ? '${area.title} er på' : '${area.title} er fjernet');
  }

  Future<void> _addLink() async {
    final area = _linkChoices.cast<AccessAreaDef?>().firstWhere(
          (a) => a!.id == _linkAreaId,
          orElse: () => null,
        );
    final title = _title.text.trim();
    if (area == null || title.isEmpty || area.routePath == null) return;
    _doc.liveLinks.add({
      'id': '${area.id}-${DateTime.now().millisecondsSinceEpoch}',
      'title': title,
      'path': area.routePath!,
    });
    _doc.set(area.id, AccessAction.view, true);
    _doc.ensureParentViews(area.id);
    _title.clear();
    await _persist('«$title» vises med en gang i Mer');
  }

  Future<void> _removeLink(Map<String, String> link) async {
    _doc.liveLinks.removeWhere((l) => l['id'] == link['id']);
    await _persist('«${link['title']}» er fjernet');
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.employee.role == UserRole.superadmin;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          'Sider for ${widget.employee.fullName}',
          style: DriftProTheme.headingSm,
        ),
        const SizedBox(height: 4),
        Text(
          'Av eller på med en gang — ansattens app oppdateres uten ny bygg.',
          style: DriftProTheme.caption,
        ),
        if (locked) ...[
          const SizedBox(height: 10),
          const Text(
            'Superadmin har alltid alle sider. Velg en vanlig ansatt for å skjule sider.',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
          ),
        ],
        if (_status != null) ...[
          const SizedBox(height: 8),
          Text(_status!, style: DriftProTheme.caption),
        ],
        const SizedBox(height: 12),
        for (final area in _pages)
          SwitchListTile(
            contentPadding: EdgeInsets.only(left: area.parentId == null ? 0 : 16),
            title: Text(area.title),
            subtitle: area.parentId == null
                ? null
                : Text(
                    'Under ${_parentTitle(area.parentId!)}',
                    style: DriftProTheme.caption,
                  ),
            value: locked || _visible(area),
            onChanged: locked || _busy ? null : (v) => _toggle(area, v),
          ),
        const Divider(height: 32),
        Text('Legg til snarvei i Mer', style: DriftProTheme.labelLg),
        const SizedBox(height: 4),
        Text(
          'Viser en eksisterende side med eget navn med en gang. Ingen ny bygg.',
          style: DriftProTheme.caption,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _title,
          decoration: const InputDecoration(
            labelText: 'Navn i menyen',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _linkAreaId,
          decoration: const InputDecoration(
            labelText: 'Side',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final a in _linkChoices)
              DropdownMenuItem(value: a.id, child: Text(a.title)),
          ],
          onChanged: locked ? null : (v) => setState(() => _linkAreaId = v),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: locked || _busy ? null : _addLink,
          icon: const Icon(Icons.add),
          label: const Text('Legg til — vises med en gang'),
        ),
        const SizedBox(height: 12),
        for (final link in _doc.liveLinks)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(link['title'] ?? ''),
            subtitle: Text(link['path'] ?? ''),
            trailing: IconButton(
              tooltip: 'Fjern',
              onPressed: _busy ? null : () => _removeLink(link),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
      ],
    );
  }

  String _parentTitle(String id) {
    return AccessAreaCatalog.byId[id]?.title ?? id;
  }
}
