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
  String _group = 'Alle';

  static const _groups = <String, List<String>>{
    'Hjem': ['dashboard', 'surveys', 'fravaer', 'avvik', 'stempling'],
    'HMS': ['hms', 'uniform'],
    'Partnere': ['partners'],
    'Mer og admin': ['more', 'admin.ansatte_rediger', 'admin.avdelinger_rediger'],
  };

  static const _tips = <String, String>{
    'dashboard':
        'Forsiden. Les av = Hjem forsvinner, og appen åpner neste side brukeren har.',
    'surveys': 'Undersøkelser. Opprett/Endre gjelder den som lager skjema.',
    'fravaer':
        'Ferie og fravær. Godkjenn = leder kan svare på andres søknader.',
    'avvik': 'Avvik og RUH. Ansatte har ikke dette som standard.',
    'hms': 'HMS, risiko, SJA, opplæring og dokumenter.',
    'uniform': 'Uniform- og kontrollkamera.',
    'partners': 'Samarbeidspartnere, ruter, bot/trekk og chat.',
    'stempling': 'Stempling inn og ut.',
    'more': 'Mer-menyen. Selve fanen kan ikke fjernes, men innholdet kan.',
  };

  static const _actionHelp = <String, String>{
    'Les': 'Ser siden og egne data. Av = siden er borte.',
    'Opprett': 'Kan lage nye saker, søknader eller poster.',
    'Endre': 'Kan endre det som allerede finnes.',
    'Slett': 'Kan slette. Brukes sjelden — GDPR.',
    'Godkjenn': 'Kan godkjenne eller avvise andres saker.',
  };

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

  bool _inGroup(AccessAreaDef area) {
    if (_group == 'Alle') return true;
    final ids = _groups[_group] ?? const <String>[];
    final root = area.id.split('.').first;
    if (area.id.startsWith('admin.')) {
      return ids.contains(area.id);
    }
    return ids.contains(root) || ids.contains(area.id);
  }

  bool _matchesQuery(AccessAreaDef area) {
    if (!_inGroup(area)) return false;
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
              const Text(
                'Les av betyr at siden forsvinner med en gang. '
                'Endringen lagres av seg selv. Minste tilgang gjelder (GDPR).',
                style: TextStyle(
                  color: Color(0xFF1A2E24),
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final e in _actionHelp.entries)
                    Tooltip(
                      message: e.value,
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${e.key}: ${e.value}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1A2E24),
                          ),
                        ),
                        backgroundColor: Colors.white,
                      ),
                    ),
                ],
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in ['Alle', ..._groups.keys])
              ChoiceChip(
                label: Text(name),
                selected: _group == name,
                onSelected: (_) => setState(() => _group = name),
                selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.25),
                labelStyle: TextStyle(
                  color: const Color(0xFF1A2E24),
                  fontWeight: _group == name ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
          ],
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
            title: Text(
              area.title,
              style: const TextStyle(
                color: Color(0xFF1A2E24),
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              _tips[area.id] ??
                  area.subtitle ??
                  'Underområde. Krever Les på siden over.',
              style: const TextStyle(color: Color(0xFF3D4F45), height: 1.3),
            ),
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
                    Tooltip(
                      message: _actionHelp[action.label] ?? action.label,
                      child: FilterChip(
                        label: Text(action.label),
                        selected: doc.get(area.id, action),
                        onSelected: widget.readOnly
                            ? null
                            : (v) => _toggle(area.id, action, v),
                        selectedColor: DriftProTheme.primaryGreen
                            .withValues(alpha: 0.28),
                        checkmarkColor: DriftProTheme.primaryGreen,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: doc.get(area.id, action)
                              ? const Color(0xFF145C32)
                              : const Color(0xFF1A2E24),
                          fontWeight: FontWeight.w700,
                        ),
                        side: BorderSide(
                          color: doc.get(area.id, action)
                              ? DriftProTheme.primaryGreen
                              : const Color(0xFFB7C4BC),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
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
