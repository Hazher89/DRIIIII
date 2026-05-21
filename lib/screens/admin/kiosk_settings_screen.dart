import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/infoskjerm_urls.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/tidsbanken/tidsbanken_presence_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/kiosk_settings.dart';

/// Administrator styrer hva som vises på hjem/infoskjerm (f.eks. felles skjerm på kontoret).
class KioskSettingsScreen extends StatefulWidget {
  const KioskSettingsScreen({super.key});

  @override
  State<KioskSettingsScreen> createState() => _KioskSettingsScreenState();
}

class _KioskSettingsScreenState extends State<KioskSettingsScreen> {
  KioskSettings _draft = KioskSettings.defaults;
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _tidsbankenEnabled = false;
  bool _syncingTidsbanken = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null) {
        setState(() {
          _loading = false;
          _error = 'Fant ingen bedrift.';
        });
        return;
      }
      final meta = await SupabaseService.fetchCompanyDashboardMeta(companyId);
      final tbOn = await TidsbankenPresenceService.isEnabledForCompany(companyId);
      _titleCtrl.text = meta.kiosk.customMessageTitle;
      _bodyCtrl.text = meta.kiosk.customMessageBody;
      setState(() {
        _draft = meta.kiosk;
        _tidsbankenEnabled = tbOn;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = await SupabaseService.saveCompanyKioskSettings(
        _draft.copyWith(
          customMessageTitle: _titleCtrl.text.trim(),
          customMessageBody: _bodyCtrl.text.trim(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _draft = updated;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Infoskjerm lagret')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke lagre: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Infoskjerm'),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Lagre'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Bestem hva ansatte ser på hjemskjermen. På felles skjerm bør du unngå å vise navn (GDPR).',
                      style: DriftProTheme.bodySm.copyWith(
                        color: isDark ? Colors.grey[400] : Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _infoskjermLinkCard(isDark),
                    _section('Presentasjon', isDark, [
                      _switchTile(
                        title: 'Infoskjerm-modus (større tekst)',
                        subtitle: 'Egnet for TV eller felles skjerm',
                        value: _draft.infoscreenLayoutEnabled,
                        onChanged: (v) => setState(
                            () => _draft = _draft.copyWith(infoscreenLayoutEnabled: v)),
                        isDark: isDark,
                      ),
                      _switchTile(
                        title: 'Vis klokke og dato',
                        subtitle: 'Oppdateres automatisk på dashbordet',
                        value: _draft.showClock,
                        onChanged: (v) =>
                            setState(() => _draft = _draft.copyWith(showClock: v)),
                        isDark: isDark,
                      ),
                      _switchTile(
                        title: 'Personlig hilsen med fornavn',
                        subtitle: 'Slå av på felles skjerm',
                        value: _draft.showPersonalGreeting,
                        onChanged: (v) => setState(
                            () => _draft = _draft.copyWith(showPersonalGreeting: v)),
                        isDark: isDark,
                      ),
                    ]),
                    _section('Personvern (felles skjerm)', isDark, [
                      _switchTile(
                        title: 'Vis navn på fravær / oppmøte',
                        subtitle:
                            'Krever saklig grunnlag — ikke anbefalt på offentlig skjerm',
                        value: _draft.revealNamesOnInfoscreen,
                        onChanged: (v) => setState(
                            () => _draft = _draft.copyWith(revealNamesOnInfoscreen: v)),
                        isDark: isDark,
                        warn: true,
                      ),
                    ]),
                    _section('Innhold', isDark, [
                      _switchTile(
                        title: 'Egendefinert beskjed',
                        subtitle: 'Tittel og tekst under hilsen',
                        value: _draft.showCustomMessage,
                        onChanged: (v) =>
                            setState(() => _draft = _draft.copyWith(showCustomMessage: v)),
                        isDark: isDark,
                      ),
                      if (_draft.showCustomMessage) ...[
                        TextField(
                          controller: _titleCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Overskrift',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _bodyCtrl,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Melding til ansatte',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      _switchTile(
                        title: 'Fravær i dag (samlet)',
                        subtitle:
                            'Antall per type, uten navn med mindre «vis navn» er på',
                        value: _draft.showAbsenceAggregate,
                        onChanged: (v) => setState(
                            () => _draft = _draft.copyWith(showAbsenceAggregate: v)),
                        isDark: isDark,
                      ),
                      _switchTile(
                        title: 'Avvik (åpne / kritiske)',
                        value: _draft.showTicketStats,
                        onChanged: (v) =>
                            setState(() => _draft = _draft.copyWith(showTicketStats: v)),
                        isDark: isDark,
                      ),
                      _switchTile(
                        title: 'HMS (risiko, SJA, vernerunder)',
                        value: _draft.showHmsHighlights,
                        onChanged: (v) =>
                            setState(() => _draft = _draft.copyWith(showHmsHighlights: v)),
                        isDark: isDark,
                      ),
                      _switchTile(
                        title: 'Oppmøte (på jobb nå)',
                        value: _draft.showAttendanceSummary,
                        onChanged: (v) => setState(
                            () => _draft = _draft.copyWith(showAttendanceSummary: v)),
                        isDark: isDark,
                      ),
                      _switchTile(
                        title: 'Kompakt rad (fravær / avvik / på jobb)',
                        value: _draft.showMiniStatsRow,
                        onChanged: (v) =>
                            setState(() => _draft = _draft.copyWith(showMiniStatsRow: v)),
                        isDark: isDark,
                      ),
                      _switchTile(
                        title: 'Hurtigvalg',
                        value: _draft.showQuickActions,
                        onChanged: (v) =>
                            setState(() => _draft = _draft.copyWith(showQuickActions: v)),
                        isDark: isDark,
                      ),
                      _switchTile(
                        title: 'Aktivitetsliste',
                        value: _draft.showActivityFeed,
                        onChanged: (v) =>
                            setState(() => _draft = _draft.copyWith(showActivityFeed: v)),
                        isDark: isDark,
                      ),
                    ]),
                    _section('Tidsbanken (live på jobb)', isDark, [
                      _switchTile(
                        title: 'Koble Tidsbanken (web)',
                        subtitle:
                            'Firma-ID, passord, ansattnr og PIN legges i Supabase Secrets — aldri i app-kode',
                        value: _tidsbankenEnabled,
                        onChanged: (v) async {
                          setState(() => _tidsbankenEnabled = v);
                          try {
                            await TidsbankenPresenceService.setEnabled(v);
                            if (v && mounted) {
                              setState(() => _syncingTidsbanken = true);
                              final r = await TidsbankenPresenceService.syncNow();
                              if (mounted) {
                                final n = r.clockedIn ?? 0;
                                final t = r.total;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      r.ok
                                          ? (n > 0
                                              ? 'Tidsbanken OK: $n innstemplt${t != null ? ' av $t' : ''}'
                                              : 'Tidsbanken synkronisert, men 0 innstemplt — sjekk Secrets og innlogging')
                                          : 'Synk feilet: ${r.error}',
                                    ),
                                    duration: Duration(seconds: n > 0 ? 4 : 8),
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Kunne ikke lagre: $e')),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _syncingTidsbanken = false);
                          }
                        },
                        isDark: isDark,
                      ),
                      if (_syncingTidsbanken)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: LinearProgressIndicator(),
                        ),
                      _switchTile(
                        title: 'Team online på dashbord',
                        subtitle: 'Kort med antall innstemplt + lenke til infoskjerm',
                        value: _draft.showLiveTeamBoard,
                        onChanged: (v) =>
                            setState(() => _draft = _draft.copyWith(showLiveTeamBoard: v)),
                        isDark: isDark,
                      ),
                      _switchTile(
                        title: 'Hent status fra Tidsbanken',
                        subtitle: 'Slå av for kun DriftPro-fravær på infoskjerm',
                        value: _draft.showTidsbankenPresence,
                        onChanged: (v) => setState(
                            () => _draft = _draft.copyWith(showTidsbankenPresence: v)),
                        isDark: isDark,
                      ),
                    ]),
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }

  Widget _infoskjermLinkCard(bool isDark) {
    final links = InfoskjermUrls.linksForAdmin(refreshSeconds: 120);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tv_rounded, color: DriftProTheme.primaryGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Lenke til vegg-skjerm (24/7)',
                  style: DriftProTheme.headingSm,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Åpne lenken på TV/PC i fullskjerm. Logg inn én gang med bedriftskonto — '
            'sesjonen holdes vedlike. Data oppdateres automatisk (standard hvert 2. min, '
            'Tidsbanken-synk).',
            style: DriftProTheme.bodySm.copyWith(height: 1.4),
          ),
          const SizedBox(height: 12),
          ...links.map((l) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.label, style: DriftProTheme.labelSm),
                        const SizedBox(height: 4),
                        SelectableText(
                          l.url,
                          style: DriftProTheme.bodySm.copyWith(
                            fontWeight: FontWeight.w600,
                            color: DriftProTheme.primaryGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kopier',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: l.url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Kopiert: ${l.label}')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 20),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _section(String title, bool isDark, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            title.toUpperCase(),
            style: DriftProTheme.labelSm.copyWith(
              color: isDark ? Colors.grey[500] : Colors.grey[600],
              letterSpacing: 1,
            ),
          ),
        ),
        ...children,
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _switchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
    String? subtitle,
    bool warn = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: warn
            ? DriftProTheme.warning.withValues(alpha: 0.08)
            : (isDark ? DriftProTheme.cardDark : Colors.white),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: SwitchListTile.adaptive(
        title: Text(title, style: DriftProTheme.bodyMd),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: DriftProTheme.bodySm.copyWith(
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              )
            : null,
        value: value,
        activeTrackColor: DriftProTheme.primaryGreen.withValues(alpha: 0.5),
        onChanged: onChanged,
      ),
    );
  }
}
