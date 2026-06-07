import 'package:flutter/material.dart';

import '../../../core/permissions/access_catalog.dart';
import '../../../core/permissions/access_keys.dart';
import '../../../core/theme/app_theme.dart';

/// Komplett av/på-matrise for alle DriftPro-moduler (superadmin).
class PermissionMatrixEditor extends StatefulWidget {
  final Map<String, dynamic> settings;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  const PermissionMatrixEditor({
    super.key,
    required this.settings,
    required this.onChanged,
    this.readOnly = false,
  });

  @override
  State<PermissionMatrixEditor> createState() => _PermissionMatrixEditorState();
}

class _PermissionMatrixEditorState extends State<PermissionMatrixEditor> {
  final Set<String> _expanded = {};
  int _viewTab = 0;

  void _set(String key, bool value) {
    final next = Map<String, dynamic>.from(widget.settings);
    next[key] = value;
    widget.onChanged(next);
  }

  void _setSection(List<String> keys, bool value) {
    final next = Map<String, dynamic>.from(widget.settings);
    for (final k in keys) {
      next[k] = value;
    }
    widget.onChanged(next);
  }

  void _setAll(bool value) {
    widget.onChanged({for (final k in AccessKeys.allKeys) k: value, AccessKeys.more: true});
  }

  List<AccessSection> get _visibleSections {
    if (_viewTab == 1) {
      return AccessCatalog.sections
          .where((s) => s.id == AccessCatalog.varslerSectionId)
          .toList();
    }
    return AccessCatalog.sections
        .where((s) => s.id != AccessCatalog.varslerSectionId)
        .toList();
  }

  bool get _varslerEnabled => widget.settings[AccessKeys.varsler] == true;

  @override
  Widget build(BuildContext context) {
    final enabled = AccessCatalog.countEnabled(widget.settings);
    final total = AccessKeys.allKeys.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$enabled av $total aktive',
                      style: DriftProTheme.headingSm.copyWith(
                        color: DriftProTheme.primaryGreen,
                      ),
                    ),
                    Text(
                      'Avkryssede elementer vises i appen. Resten skjules helt (GDPR).',
                      style: DriftProTheme.caption,
                    ),
                  ],
                ),
              ),
              if (!widget.readOnly) ...[
                TextButton(
                  onPressed: () => _setAll(true),
                  child: const Text('Alt på'),
                ),
                TextButton(
                  onPressed: () => _setAll(false),
                  child: const Text('Alt av'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              icon: Icon(Icons.grid_view_outlined, size: 18),
              label: Text('Moduler'),
            ),
            ButtonSegment(
              value: 1,
              icon: Icon(Icons.notifications_outlined, size: 18),
              label: Text('Varsel'),
            ),
          ],
          selected: {_viewTab},
          onSelectionChanged: (s) => setState(() {
            _viewTab = s.first;
            if (_viewTab == 1) {
              _expanded.add(AccessCatalog.varslerSectionId);
            }
          }),
        ),
        if (_viewTab == 1) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.18)),
            ),
            child: Text(
              _varslerEnabled
                  ? 'Brukeren får varselsenter under Mer og kan endre varselinnstillinger '
                      '(inkl. i Samarbeid → SMS).'
                  : 'Uten denne tilgangen skjules varselsenteret og varselinnstillinger, '
                      'selv om brukeren har tilgang til Samarbeidspartnere.',
              style: DriftProTheme.caption,
            ),
          ),
        ],
        const SizedBox(height: 12),
        ..._visibleSections.map(_sectionCard),
      ],
    );
  }

  Widget _sectionCard(AccessSection section) {
    final expanded = _expanded.contains(section.id);
    final sectionOn =
        section.keys.where((k) => widget.settings[k] == true).length;
    final sectionTotal = section.keys.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            title: Text(
              section.title.isEmpty ? ' ' : section.title,
              style: DriftProTheme.labelLg,
            ),
            subtitle: section.subtitle != null
                ? Text(section.subtitle!, style: DriftProTheme.caption)
                : Text('$sectionOn / $sectionTotal aktive', style: DriftProTheme.caption),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.readOnly) ...[
                  IconButton(
                    tooltip: 'Slå på alle i seksjonen',
                    icon: const Icon(Icons.done_all, size: 20),
                    onPressed: () => _setSection(section.keys, true),
                  ),
                  IconButton(
                    tooltip: 'Slå av alle i seksjonen',
                    icon: const Icon(Icons.remove_done, size: 20),
                    onPressed: () => _setSection(section.keys, false),
                  ),
                ],
                Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: () => setState(() {
              if (expanded) {
                _expanded.remove(section.id);
              } else {
                _expanded.add(section.id);
              }
            }),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: section.keys.map(_toggle).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _toggle(String key) {
    final desc = AccessKeys.description(key);
    return SwitchListTile.adaptive(
      dense: true,
      title: Text(AccessKeys.label(key), style: DriftProTheme.bodyMd),
      subtitle: desc.isNotEmpty ? Text(desc, style: DriftProTheme.caption) : null,
      value: widget.settings[key] == true,
      activeTrackColor: DriftProTheme.primaryGreen,
      onChanged: widget.readOnly ? null : (v) => _set(key, v),
    );
  }
}
