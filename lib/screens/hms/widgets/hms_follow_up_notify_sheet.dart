import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/hms/hms_follow_up_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Konfigurasjon for HMS-varsel / oppfølging (mail + push).
class HmsFollowUpNotifyConfig {
  final String companyId;
  final String module;
  final String referenceType;
  final String referenceId;
  final String title;
  final String? summary;
  final int deviationCount;
  final List<String> involvedProfileIds;
  final bool requireDueDate;
  final DateTime? initialDueAt;
  final String headline;
  final String? subtitle;

  const HmsFollowUpNotifyConfig({
    required this.companyId,
    required this.module,
    required this.referenceType,
    required this.referenceId,
    required this.title,
    this.summary,
    this.deviationCount = 1,
    this.involvedProfileIds = const [],
    this.requireDueDate = false,
    this.initialDueAt,
    this.headline = 'Send oppfølging',
    this.subtitle,
  });
}

/// Avansert mottakervalg + e-post/push før HMS-utsending.
class HmsFollowUpNotifySheet extends StatefulWidget {
  final HmsFollowUpNotifyConfig config;

  const HmsFollowUpNotifySheet({super.key, required this.config});

  /// Viser arket. Returnerer true hvis sendt, false hvis avbrutt.
  static Future<bool> show(
    BuildContext context, {
    required HmsFollowUpNotifyConfig config,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => HmsFollowUpNotifySheet(config: config),
    );
    return result == true;
  }

  @override
  State<HmsFollowUpNotifySheet> createState() => _HmsFollowUpNotifySheetState();
}

class _HmsFollowUpNotifySheetState extends State<HmsFollowUpNotifySheet> {
  final _search = TextEditingController();
  final _summary = TextEditingController();
  final _df = DateFormat('dd.MM.yyyy');

  List<UserProfile> _profiles = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _sending = false;
  bool _sendEmail = true;
  bool _sendPush = true;
  DateTime? _dueAt;
  String? _error;

  HmsFollowUpNotifyConfig get c => widget.config;

  @override
  void initState() {
    super.initState();
    _summary.text = c.summary ?? '';
    _dueAt = c.initialDueAt ??
        (c.requireDueDate || c.deviationCount > 0
            ? DateTime.now().add(const Duration(days: 7))
            : null);
    _selected.addAll(c.involvedProfileIds.where((e) => e.isNotEmpty));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _summary.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await SupabaseService.fetchProfiles(companyId: c.companyId);
      list.sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _profiles = list.where((p) => p.isActive).toList();
        // Behold involverte selv om de mangler i listen (sjeldent).
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kunne ikke laste brukere: $e';
        _loading = false;
      });
    }
  }

  List<UserProfile> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _profiles;
    return _profiles.where((p) {
      return p.fullName.toLowerCase().contains(q) ||
          p.email.toLowerCase().contains(q) ||
          (p.jobTitle ?? '').toLowerCase().contains(q);
    }).toList();
  }

  String get _preview {
    final module = switch (c.module) {
      'ticket' => 'avvik',
      'safety_round' => 'vernerunde',
      'sja' => 'SJA',
      'risk_assessment' => 'risikoanalyse',
      _ => 'HMS',
    };
    final due = _dueAt != null ? ' Frist: ${_df.format(_dueAt!)}.' : '';
    if (c.deviationCount > 1) {
      return 'Et $module er sendt til deg med ${c.deviationCount} punkter '
          'som må følges opp.$due';
    }
    return 'Et $module («${c.title}») er sendt til deg for oppfølging.$due';
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _dueAt = picked);
  }

  Future<void> _send() async {
    if (_selected.isEmpty) {
      setState(() => _error = 'Velg minst én mottaker');
      return;
    }
    if (!_sendEmail && !_sendPush) {
      setState(() => _error = 'Velg e-post og/eller push-varsel');
      return;
    }
    if (c.requireDueDate && _dueAt == null) {
      setState(() => _error = 'Velg oppfølgingsfrist');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await HmsFollowUpService.createAndNotify(
        companyId: c.companyId,
        module: c.module,
        referenceType: c.referenceType,
        referenceId: c.referenceId,
        title: c.title,
        summary: _summary.text.trim().isEmpty ? null : _summary.text.trim(),
        deviationCount: c.deviationCount,
        dueAt: _dueAt,
        recipientIds: _selected.toList(),
        sendEmail: _sendEmail,
        sendPush: _sendPush,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kunne ikke sende: $e';
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.55,
        maxChildSize: 0.98,
        builder: (context, scrollController) {
          return Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.headline, style: DriftProTheme.labelLg),
                            if (c.subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                c.subtitle!,
                                style: DriftProTheme.bodySm
                                    .copyWith(color: Colors.grey.shade700),
                              ),
                            ],
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _sending
                            ? null
                            : () => Navigator.pop(context, false),
                        child: const Text('Hopp over'),
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  const Expanded(child: DriftProLoadingCenter())
                else
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: DriftProTheme.primaryGreen.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            _preview,
                            style: const TextStyle(fontSize: 13, height: 1.35),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text('Kanal', style: DriftProTheme.labelSm),
                        const SizedBox(height: 4),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _sendEmail,
                          onChanged: (v) =>
                              setState(() => _sendEmail = v ?? true),
                          title: const Text('E-post'),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _sendPush,
                          onChanged: (v) =>
                              setState(() => _sendPush = v ?? true),
                          title: const Text('Push-varsel'),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Oppfølgingsfrist'),
                          subtitle: Text(
                            _dueAt == null
                                ? (c.requireDueDate
                                    ? 'Påkrevd — velg dato'
                                    : 'Valgfritt')
                                : _df.format(_dueAt!),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_dueAt != null && !c.requireDueDate)
                                IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => setState(() => _dueAt = null),
                                ),
                              IconButton(
                                icon: const Icon(Icons.event),
                                onPressed: _pickDue,
                              ),
                            ],
                          ),
                          onTap: _pickDue,
                        ),
                        Text(
                          'Systemet sender ny e-post/push dagen før fristen '
                          'hvis oppfølgingen fortsatt er åpen.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _summary,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Oppsummering til mottakere',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text(
                              'Mottakere (${_selected.length})',
                              style: DriftProTheme.labelSm,
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _selected
                                    ..clear()
                                    ..addAll(c.involvedProfileIds);
                                });
                              },
                              child: const Text('Kun involverte'),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _selected
                                    ..clear()
                                    ..addAll(_profiles.map((p) => p.id));
                                });
                              },
                              child: const Text('Alle'),
                            ),
                          ],
                        ),
                        if (c.involvedProfileIds.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Involverte er forhåndsvalgt — legg til eller fjern før sending.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextField(
                          controller: _search,
                          decoration: const InputDecoration(
                            hintText: 'Søk navn, e-post, stilling…',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        ..._filtered.map((p) {
                          final selected = _selected.contains(p.id);
                          final involved = c.involvedProfileIds.contains(p.id);
                          return CheckboxListTile(
                            value: selected,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selected.add(p.id);
                                } else {
                                  _selected.remove(p.id);
                                }
                              });
                            },
                            title: Text(p.fullName),
                            subtitle: Text(
                              [
                                if (involved) 'Involvert',
                                if (p.jobTitle != null &&
                                    p.jobTitle!.trim().isNotEmpty)
                                  p.jobTitle!.trim(),
                                p.email,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        }),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _sending ? null : _send,
                          icon: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send_outlined),
                          label: Text(
                            _sending ? 'Sender…' : 'Send varsel',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
