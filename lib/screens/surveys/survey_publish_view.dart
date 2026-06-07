import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/survey/survey_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/driftpro_colors.dart';
import '../../core/theme/driftpro_theme_context.dart';
import '../../core/services/supabase_service.dart';
import '../../models/survey/survey.dart';
import '../../models/user_profile.dart';

class SurveyPublishView extends StatefulWidget {
  final Survey survey;
  final Future<void> Function()? onSurveyChanged;

  const SurveyPublishView({
    super.key,
    required this.survey,
    this.onSurveyChanged,
  });

  @override
  State<SurveyPublishView> createState() => _SurveyPublishViewState();
}

class _SurveyPublishViewState extends State<SurveyPublishView> {
  late Survey _survey;
  bool _saving = false;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    _survey = widget.survey;
    _expiresAt = _survey.expiresAt;
  }

  @override
  void didUpdateWidget(covariant SurveyPublishView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.survey.id != widget.survey.id ||
        oldWidget.survey.totalResponses != widget.survey.totalResponses) {
      _survey = widget.survey;
      _expiresAt = _survey.expiresAt;
    }
  }

  Future<void> _update({bool? isActive, DateTime? expiresAt, bool clearExpiry = false}) async {
    setState(() => _saving = true);
    try {
      await SurveyService.updateSurvey(
        id: _survey.id,
        isActive: isActive,
        expiresAt: expiresAt,
        clearExpiresAt: clearExpiry,
      );
      final fresh = await SurveyService.fetchSurveyById(_survey.id);
      if (!mounted) return;
      setState(() {
        _survey = fresh;
        _expiresAt = fresh.expiresAt;
      });
      await widget.onSurveyChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      helpText: 'Velg utløpsdato',
    );
    if (picked != null) {
      await _update(expiresAt: picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final origin = Uri.base.origin.isEmpty ? 'https://driftpro.no' : Uri.base.origin;
    final publicLink = '$origin/?survey=${_survey.id}';
    final shortLink = '$origin/s/${_survey.id}';
    final previewLink = '$origin/s/${_survey.id}?preview=true';
    final smartText = 'Hei! Vi vil gjerne ha din tilbakemelding. Svar her: $shortLink';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Publiser & Del', style: DriftProTheme.headingLg.copyWith(color: drift.textPrimary)),
              const SizedBox(height: 8),
              Text(
                _survey.isActive
                    ? 'Undersøkelsen er åpen og klar for svar.'
                    : 'Undersøkelsen er lukket — aktiver for å ta imot nye svar.',
                style: DriftProTheme.bodyMd.copyWith(color: drift.textMuted),
              ),
              const SizedBox(height: 24),
              _buildStatusPanel(drift),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _shareButton(Icons.copy_all_outlined, 'Kopier melding', () {
                    Clipboard.setData(ClipboardData(text: smartText));
                    _snack('Meldingsmal kopiert');
                  }),
                  _shareButton(Icons.link_outlined, 'Kopier kortlenke', () {
                    Clipboard.setData(ClipboardData(text: shortLink));
                    _snack('Kortlenke kopiert');
                  }),
                  _shareButton(Icons.preview_outlined, 'Kopier preview-lenke', () {
                    Clipboard.setData(ClipboardData(text: previewLink));
                    _snack('Preview-lenke kopiert');
                  }),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                decoration: drift.surfaceDecoration(radius: 16, elevated: true),
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.public, color: DriftProTheme.primaryGreen, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Offentlig lenke', style: DriftProTheme.headingMd.copyWith(color: drift.textPrimary)),
                              const SizedBox(height: 4),
                              Text(
                                'Del med hvem som helst — krever ikke innlogging.',
                                style: DriftProTheme.bodySm.copyWith(color: drift.textMuted),
                              ),
                            ],
                          ),
                        ),
                        _statusBadge(_survey.isActive),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _linkRow(publicLink, drift),
                    const SizedBox(height: 12),
                    _linkRow(shortLink, drift, label: 'Kortlenke'),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: drift.surfaceMuted,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: drift.borderSubtle),
                      ),
                      child: Text(
                        'Tips: bruk kortlenke i SMS, preview-lenke for intern QA, og full lenke i e-post.',
                        style: DriftProTheme.bodySm.copyWith(color: drift.textMuted),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(child: _statTile(Icons.analytics_outlined, '${_survey.totalResponses}', 'Totalt svar', drift)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _statTile(
                            Icons.calendar_today_outlined,
                            '${_survey.createdAt.day}.${_survey.createdAt.month}.${_survey.createdAt.year}',
                            'Opprettet',
                            drift,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () => _showInternalShareSheet(context),
                        icon: const Icon(Icons.people),
                        label: const Text('Del direkte med ansatte', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DriftProTheme.primaryGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _buildStatusPanel(DriftProColors drift) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: drift.surfaceDecoration(radius: 14),
      child: Column(
        children: [
          SwitchListTile(
            value: _survey.isActive,
            onChanged: _saving ? null : (v) => _update(isActive: v),
            title: const Text('Undersøkelsen er aktiv'),
            subtitle: Text(
              _survey.isActive ? 'Respondenter kan sende inn svar' : 'Nye svar er blokkert',
              style: DriftProTheme.bodySm.copyWith(color: drift.textMuted),
            ),
            secondary: Icon(
              _survey.isActive ? Icons.lock_open_outlined : Icons.lock_outline,
              color: _survey.isActive ? Colors.green : Colors.orange,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: const Text('Utløpsdato'),
            subtitle: Text(
              _expiresAt == null
                  ? 'Ingen utløp — åpen til den stenges manuelt'
                  : 'Utløper ${_expiresAt!.day}.${_expiresAt!.month}.${_expiresAt!.year}',
            ),
            trailing: _saving
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'set') {
                        await _pickExpiry();
                      } else if (action == 'clear') {
                        await _update(clearExpiry: true);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'set', child: Text('Sett dato')),
                      if (_expiresAt != null)
                        const PopupMenuItem(value: 'clear', child: Text('Fjern utløp')),
                    ],
                    child: const Icon(Icons.more_vert),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _shareButton(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
    );
  }

  Widget _statusBadge(bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (active ? Colors.green : Colors.red).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        active ? 'Aktiv' : 'Lukket',
        style: TextStyle(color: active ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _linkRow(String link, DriftProColors drift, {String? label}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label, style: DriftProTheme.bodySm.copyWith(color: drift.textMuted)),
          const SizedBox(height: 6),
        ],
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: drift.surfaceMuted,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: drift.borderSubtle),
          ),
          child: Row(
            children: [
              Expanded(child: SelectableText(link, style: const TextStyle(fontSize: 14, color: Colors.blue))),
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Kopier',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: link));
                  _snack('Lenke kopiert');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statTile(IconData icon, String value, String label, DriftProColors drift) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: drift.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: drift.textMuted, size: 20),
          const SizedBox(height: 12),
          Text(value, style: DriftProTheme.headingMd.copyWith(color: drift.textPrimary)),
          const SizedBox(height: 4),
          Text(label, style: DriftProTheme.bodySm.copyWith(color: drift.textMuted)),
        ],
      ),
    );
  }

  void _showInternalShareSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _InternalShareSheet(survey: _survey),
    );
  }
}

class _InternalShareSheet extends StatefulWidget {
  final Survey survey;
  const _InternalShareSheet({required this.survey});

  @override
  State<_InternalShareSheet> createState() => _InternalShareSheetState();
}

class _InternalShareSheetState extends State<_InternalShareSheet> {
  List<UserProfile> _allUsers = [];
  bool _isLoading = true;
  final Set<String> _selectedUsers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId != null) {
      final users = await SupabaseService.fetchMaviEmployees(companyId: companyId);
      if (mounted) {
        setState(() {
          _allUsers = users;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    return Container(
      decoration: BoxDecoration(
        color: drift.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Del med ansatte', style: DriftProTheme.headingMd.copyWith(color: drift.textPrimary)),
          const SizedBox(height: 8),
          Text(
            'Velg ansatte du vil sende lenke til (via valgt kanal).',
            style: DriftProTheme.bodySm.copyWith(color: drift.textMuted),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _allUsers.length,
                    itemBuilder: (context, index) {
                      final user = _allUsers[index];
                      return CheckboxListTile(
                        title: Text(user.fullName),
                        subtitle: Text(user.role.name, style: TextStyle(color: drift.textMuted, fontSize: 12)),
                        value: _selectedUsers.contains(user.id),
                        activeColor: DriftProTheme.primaryGreen,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedUsers.add(user.id);
                            } else {
                              _selectedUsers.remove(user.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _selectedUsers.isEmpty
                  ? null
                  : () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Invitasjon klar for ${_selectedUsers.length} ansatte')),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Send invitasjon', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
