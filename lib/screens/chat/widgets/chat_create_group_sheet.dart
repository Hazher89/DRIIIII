import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
/// Opprett gruppe-chat med flervalg.
Future<({String title, List<String> memberIds})?> showChatCreateGroupSheet({
  required BuildContext context,
  required String headline,
  required String privacyHint,
  required List<({String id, String title, String subtitle})> candidates,
  required String currentUserId,
  int minMembers = 1,
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
    ),
  );
}

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet({
    required this.headline,
    required this.privacyHint,
    required this.candidates,
    required this.minMembers,
  });

  final String headline;
  final String privacyHint;
  final List<({String id, String title, String subtitle})> candidates;
  final int minMembers;

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _title = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        _title.text.trim().length >= 2 && _selected.length >= widget.minMembers;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
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
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Text(widget.privacyHint, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ),
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                'Velg medlemmer (${_selected.length} valgt)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: widget.candidates.length,
                itemBuilder: (_, i) {
                  final c = widget.candidates[i];
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
                          (title: _title.text.trim(), memberIds: _selected.toList()),
                        )
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text('Opprett gruppe'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
