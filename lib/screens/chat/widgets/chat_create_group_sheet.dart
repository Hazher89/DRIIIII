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
  late final FocusNode _titleFocus;
  final _selected = <String>{};

  static const _minTitleLength = 2;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initialTitle ?? '');
    _search = TextEditingController();
    _titleFocus = FocusNode();
    if (!widget.titleOptional) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _titleFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _search.dispose();
    _titleFocus.dispose();
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

  bool get _titleOk =>
      widget.titleOptional || _title.text.trim().length >= _minTitleLength;

  bool get _membersOk => _selected.length >= widget.minMembers;

  bool get _canCreate => _titleOk && _membersOk;

  String? get _blockingHint {
    if (_canCreate) return null;
    if (!_titleOk && !_membersOk) {
      return 'Skriv gruppenavn og velg minst ${widget.minMembers} medlem(mer).';
    }
    if (!_titleOk) {
      final missing = _minTitleLength - _title.text.trim().length;
      if (_title.text.trim().isEmpty) {
        return 'Gi gruppen et navn — fyll inn feltet «Gruppenavn» over.';
      }
      return 'Gruppenavn må ha minst $_minTitleLength tegn (${missing > 0 ? ' $missing til' : ''}).';
    }
    if (!_membersOk) {
      final need = widget.minMembers - _selected.length;
      return 'Velg minst ${widget.minMembers} medlem(mer) ($need til).';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final titleLen = _title.text.trim().length;

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
                  focusNode: _titleFocus,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Gruppenavn *',
                    hintText: 'F.eks. «Bil-eiere Oslo» eller «Sjåfør-team Nord»',
                    helperText: _titleOk
                        ? 'Navn er klart'
                        : 'Påkrevd — minst $_minTitleLength tegn',
                    helperStyle: TextStyle(
                      color: _titleOk ? DriftProTheme.primaryGreen : Colors.orange.shade800,
                      fontSize: 11,
                    ),
                    counterText: '$titleLen / $_minTitleLength',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: _titleOk ? Colors.grey.shade400 : Colors.orange.shade400,
                        width: _titleOk ? 1 : 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: DriftProTheme.primaryGreen, width: 2),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (_canCreate) {
                      Navigator.pop(
                        context,
                        (title: _title.text.trim(), memberIds: _selected.toList()),
                      );
                    }
                  },
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
            if (_blockingHint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.orange.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _blockingHint!,
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade900, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _canCreate
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
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
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
