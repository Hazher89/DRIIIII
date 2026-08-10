import 'package:flutter/material.dart';

import '../../../core/permissions/access_actions.dart';
import '../../../core/permissions/access_area_catalog.dart';
import '../../../core/permissions/access_normalize.dart';
import '../../../core/permissions/access_presets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';

/// Hierarkisk tilgangsmatrise: område × (les/opprett/endre/slett/godkjenn).
class PermissionMatrixEditor extends StatefulWidget {
  final Map<String, dynamic> settings;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;
  final UserRole? roleForPresets;

  const PermissionMatrixEditor({
    super.key,
    required this.settings,
    required this.onChanged,
    this.readOnly = false,
    this.roleForPresets,
  });

  @override
  State<PermissionMatrixEditor> createState() => _PermissionMatrixEditorState();
}

class _PermissionMatrixEditorState extends State<PermissionMatrixEditor> {
  final _search = TextEditingController();
  final Set<String> _expanded = {};
  String _query = '';

  AccessSettingsDoc get _doc => AccessSettingsDoc.fromJson(widget.settings);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _emit(AccessSettingsDoc doc) {
    doc.applyInheritanceRules();
    widget.onChanged(doc.toJson());
  }

  void _toggle(String areaId, AccessAction action, bool value) {
    final doc = _doc;
    doc.set(areaId, action, value);
    if (value) {
      doc.set(areaId, AccessAction.view, true);
      doc.ensureParentViews(areaId);
    } else if (action == AccessAction.view) {
      doc.setAreaAll(areaId, false, cascadeChildren: true);
    }
    _emit(doc);
  }

  void _quickArea(String areaId, _QuickMode mode) {
    final doc = _doc;
    final def = AccessAreaCatalog.byId[areaId];
    if (def == null) return;
    switch (mode) {
      case _QuickMode.off:
        doc.setAreaAll(areaId, false);
        break;
      case _QuickMode.viewOnly:
        doc.setAreaAll(areaId, false, cascadeChildren: false);
        doc.set(areaId, AccessAction.view, true);
        doc.ensureParentViews(areaId);
        break;
      case _QuickMode.full:
        doc.setAreaAll(areaId, true, cascadeChildren: false);
        doc.ensureParentViews(areaId);
        break;
      case _QuickMode.approver:
        doc.set(areaId, AccessAction.view, true);
        if (def.supports(AccessAction.approve)) {
          doc.set(areaId, AccessAction.approve, true);
        }
        doc.ensureParentViews(areaId);
        break;
    }
    _emit(doc);
  }

  void _setAll(bool on) {
    final doc = on
        ? AccessSettingsDoc.fromJson(AccessPresets.allOnV2())
        : AccessSettingsDoc.fromJson(AccessPresets.allOffV2());
    _emit(doc);
  }

  void _applyRolePreset(UserRole role) {
    _emit(AccessSettingsDoc.fromJson(AccessPresets.forRoleV2(role)));
  }

  bool _matchesQuery(AccessAreaDef area) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    if (area.title.toLowerCase().contains(q)) return true;
    if (area.id.toLowerCase().contains(q)) return true;
    if ((area.subtitle ?? '').toLowerCase().contains(q)) return true;
    return AccessAreaCatalog.descendants(area.id).any((id) {
      final c = AccessAreaCatalog.byId[id];
      return c != null &&
          (c.title.toLowerCase().contains(q) || c.id.toLowerCase().contains(q));
    });
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final enabled = doc.countEnabledActions();
    final total = doc.totalPossibleActions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$enabled av $total handlinger aktive',
                style: DriftProTheme.headingSm.copyWith(
                  color: DriftProTheme.primaryGreen,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Les / Opprett / Endre / Slett / Godkjenn per område. '
                'Slå av et område for å skjule det helt.',
                style: DriftProTheme.caption,
              ),
              if (!widget.readOnly) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => _setAll(true),
                      child: const Text('Gi alt'),
                    ),
                    OutlinedButton(
                      onPressed: () => _setAll(false),
                      child: const Text('Fjern alt'),
                    ),
                    if (widget.roleForPresets != null)
                      OutlinedButton(
                        onPressed: () =>
                            _applyRolePreset(widget.roleForPresets!),
                        child: Text(
                          'Mal: ${AccessPresets.presetTitle(widget.roleForPresets!)}',
                        ),
                      ),
                    PopupMenuButton<UserRole>(
                      tooltip: 'Bruk rolle-mal',
                      onSelected: _applyRolePreset,
                      itemBuilder: (_) => [
                        for (final r in [
                          UserRole.ansatt,
                          UserRole.leder,
                          UserRole.admin,
                          UserRole.superadmin,
                        ])
                          PopupMenuItem(
                            value: r,
                            child: Text(AccessPresets.presetTitle(r)),
                          ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome, size: 18),
                            SizedBox(width: 6),
                            Text('Rolle-mal'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: 'Søk område eller funksjon…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        const SizedBox(height: 12),
        ...AccessAreaCatalog.roots
            .where(_matchesQuery)
            .map((a) => _areaCard(a, depth: 0)),
      ],
    );
  }

  Widget _areaCard(AccessAreaDef area, {required int depth}) {
    final children = AccessAreaCatalog.childrenOf(area.id)
        .where(_matchesQuery)
        .toList();
    final hasChildren = AccessAreaCatalog.childrenOf(area.id).isNotEmpty;
    final expanded = _expanded.contains(area.id) || _query.isNotEmpty;
    final doc = _doc;
    final viewOn = doc.get(area.id, AccessAction.view);

    return Card(
      margin: EdgeInsets.only(left: depth * 8.0, bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: hasChildren
                ? IconButton(
                    icon: Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                    ),
                    onPressed: () => setState(() {
                      if (expanded) {
                        _expanded.remove(area.id);
                      } else {
                        _expanded.add(area.id);
                      }
                    }),
                  )
                : const SizedBox(width: 40),
            title: Text(area.title, style: DriftProTheme.labelLg),
            subtitle: area.subtitle != null
                ? Text(area.subtitle!, style: DriftProTheme.caption)
                : Text(area.id, style: DriftProTheme.caption),
            trailing: widget.readOnly
                ? null
                : PopupMenuButton<_QuickMode>(
                    tooltip: 'Hurtigvalg',
                    onSelected: (m) => _quickArea(area.id, m),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _QuickMode.viewOnly,
                        child: Text('Kun les'),
                      ),
                      PopupMenuItem(
                        value: _QuickMode.full,
                        child: Text('Full tilgang'),
                      ),
                      PopupMenuItem(
                        value: _QuickMode.approver,
                        child: Text('Godkjenner'),
                      ),
                      PopupMenuItem(
                        value: _QuickMode.off,
                        child: Text('Fjern'),
                      ),
                    ],
                    child: const Icon(Icons.more_vert, size: 20),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final action in AccessAction.all)
                  if (area.supports(action))
                    FilterChip(
                      label: Text(action.label),
                      selected: doc.get(area.id, action),
                      onSelected: widget.readOnly
                          ? null
                          : (v) => _toggle(area.id, action, v),
                      selectedColor:
                          DriftProTheme.primaryGreen.withValues(alpha: 0.25),
                      checkmarkColor: DriftProTheme.primaryGreen,
                      visualDensity: VisualDensity.compact,
                    ),
              ],
            ),
          ),
          if (hasChildren && expanded && viewOn)
            ...children.map((c) => _areaCard(c, depth: depth + 1)),
          if (hasChildren && expanded && !viewOn && children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Slå på «Les» for å styre underområder.',
                style: DriftProTheme.caption.copyWith(color: Colors.orange[800]),
              ),
            ),
        ],
      ),
    );
  }
}

enum _QuickMode { off, viewOnly, full, approver }
