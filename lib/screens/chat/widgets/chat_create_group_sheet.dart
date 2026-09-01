import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Opprett gruppe-chat med flervalg, søk og velg alle.
Future<({String title, List<String> memberIds})?> showChatCreateGroupSheet({
  required BuildContext context,
  required String headline,
  required String privacyHint,
  required List<({String id, String title, String subtitle})> candidates,
  required String currentUserId,
  int minMembers = 1,
  bool titleOptional = false,
  String? initialTitle,
  String confirmLabel = 'Opprett gruppe',
}) {
  return showModalBottomSheet<({String title, List<String> memberIds})?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _CreateGroupSheet(
      headline: headline,
      privacyHint: privacyHint,
      candidates: candidates.where((c) => c.id != currentUserId).toList(),
      minMembers: minMembers,
      titleOptional: titleOptional,
      initialTitle: initialTitle,
      confirmLabel: confirmLabel,
    ),
  );
}

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet({
    required this.headline,
    required this.privacyHint,
    required this.candidates,
    required this.minMembers,
    this.titleOptional = false,
    this.initialTitle,
    this.confirmLabel = 'Opprett gruppe',
  });

  final String headline;
  final String privacyHint;
  final List<({String id, String title, String subtitle})> candidates;
  final int minMembers;
  final bool titleOptional;
  final String? initialTitle;
  final String confirmLabel;

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  late final TextEditingController _title;
  late final TextEditingController _search;
  final _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initialTitle ?? '');
    _search = TextEditingController();
  }

  @override
  void dispose() {
    _title.dispose();
    _search.dispose();
    super.dispose();
  }

  List<({String id, String title, String subtitle})> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return widget.candidates;
    return widget.candidates.where((c) {
      return c.title.toLowerCase().contains(q) || c.subtitle.toLowerCase().contains(q);
    }).toList();
  }

  void _selectAllVisible() {
    setState(() {
      for (final c in _filtered) {
        _selected.add(c.id);
      }
    });
  }

  void _clearAll() {
    setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final titleOk = widget.titleOptional || _title.text.trim().length >= 2;
    final canCreate = titleOk && _selected.length >= widget.minMembers;
    final filtered = _filtered;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scroll) => SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(widget.headline, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text(widget.privacyHint, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ),
            if (!widget.titleOptional)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText: 'Gruppenavn',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Søk navn, bedrift…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_selected.length} valgt · ${filtered.length} vist',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: filtered.isEmpty ? null : _selectAllVisible,
                    child: const Text('Velg alle'),
                  ),
                  TextButton(
                    onPressed: _selected.isEmpty ? null : _clearAll,
                    child: const Text('Fjern alle'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Ingen treff',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final c = filtered[i];
                        final checked = _selected.contains(c.id);
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selected.add(c.id);
                              } else {
                                _selected.remove(c.id);
                              }
                            });
                          },
                          title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(c.subtitle, style: const TextStyle(fontSize: 11)),
                          secondary: CircleAvatar(
                            backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                            child: Text(c.title.isNotEmpty ? c.title[0].toUpperCase() : '?'),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: canCreate
                    ? () => Navigator.pop(
                          context,
                          (
                            title: _title.text.trim().isEmpty
                                ? (widget.initialTitle ?? 'Gruppe')
                                : _title.text.trim(),
                            memberIds: _selected.toList(),
                          ),
                        )
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: Text(widget.confirmLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
