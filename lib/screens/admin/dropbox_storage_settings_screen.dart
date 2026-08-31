import 'package:flutter/material.dart';

import '../../core/services/storage/company_file_storage.dart';
import '../../core/services/storage/supabase_dropbox_migration_service.dart';
import '../../core/services/storage/dropbox_storage_modules.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/open_external_url.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Koble bedriftens Dropbox (OAuth — ikke passord i appen).
class DropboxStorageSettingsScreen extends StatefulWidget {
  const DropboxStorageSettingsScreen({super.key});

  @override
  State<DropboxStorageSettingsScreen> createState() =>
      _DropboxStorageSettingsScreenState();
}

class _DropboxStorageSettingsScreenState extends State<DropboxStorageSettingsScreen> {
  bool _loading = true;
  bool _busy = false;
  int _pendingMigration = 0;
  Map<String, dynamic>? _status;
  @override
  void initState() {
    super.initState();
    _load();
    _handleOAuthReturn();
  }

  void _handleOAuthReturn() {
    final q = Uri.base.queryParameters['dropbox'];
    if (q != 'connected') return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Skylagring er koblet! Nye filer lagres nå eksternt.'),
          duration: Duration(seconds: 6),
        ),
      );
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await CompanyFileStorage.dropboxStatus();
      var pending = 0;
      try {
        pending = await SupabaseDropboxMigrationService.countPendingMigration();
      } catch (_) {
        // Migreringstall er valgfritt — skal ikke blokkere Dropbox-status.
      }
      if (mounted) {
        setState(() {
          _status = s;
          _pendingMigration = pending;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke laste: $e')),
        );
      }
    }
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await SupabaseService.ensureSessionLinkedToCompany();
      final url = await CompanyFileStorage.getDropboxAuthUrl();
      if (url == null || url.isEmpty) {
        throw Exception('Ingen OAuth-URL fra server');
      }
      final opened = await openExternalUrl(url);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Kunne ikke åpne innlogging. Godkjenn tilgang i nettleseren, deretter trykk Oppdater.',
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Logg inn og godkjenn tilgang. Kom tilbake hit og trykk Oppdater.',
            ),
            duration: Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tilkobling feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _migrateBatch() async {
    setState(() => _busy = true);
    try {
      final result = await SupabaseDropboxMigrationService.migrateBatch(limit: 25);
      await _load();
      if (!mounted) return;
      final detail = result.errors.isEmpty
          ? ''
          : '\n${result.errors.join('\n')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Migrert: ${result.migrated} · feilet: ${result.failed} · hoppet over: ${result.skipped}$detail',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Migrering feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final locked = _status?['disconnect_locked'] != false;
    if (locked) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dropbox er låst mot frakobling. Lås opp først (kun superadmin).',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deaktiver skylagring midlertidig?'),
        content: const Text(
          'Tilkoblingen slettes ikke — refresh-token beholdes. '
          'Du kan reaktivere uten ny innlogging. '
          'Nye filopplastinger vil feile til Dropbox er aktiv igjen.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Deaktiver')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await CompanyFileStorage.disconnectDropbox();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Skylagring deaktivert (token beholdt)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlockDisconnect() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lås opp frakobling?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kun superadmin. Skriv nøyaktig:\nLÅS OPP DROPBOX',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'LÅS OPP DROPBOX',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lås opp'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await CompanyFileStorage.setDisconnectLocked(
        locked: false,
        confirmPhrase: ctrl.text.trim(),
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lås åpnet — husk å låse igjen etterpå.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      ctrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lockDisconnect() async {
    setState(() => _busy = true);
    try {
      await CompanyFileStorage.setDisconnectLocked(locked: true);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dropbox er låst mot frakobling.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reactivate() async {
    setState(() => _busy = true);
    try {
      final ok = await CompanyFileStorage.reactivateDropbox();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Skylagring reaktivert og låst.'
                : 'Ingen lagret tilkobling — koble på nytt via «Koble til».',
          ),
          backgroundColor: ok ? null : Colors.orange,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connected = _status?['connected'] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fillagring'),
        actions: [
          IconButton(
            tooltip: 'Oppdater',
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.cloud_outlined,
                              size: 32,
                              color: const Color(0xFF0061FF),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Ubegrenset fillagring',
                                style: DriftProTheme.headingSm,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Nye filer krever aktiv Dropbox-tilkobling. DriftPro (web, iOS og Android) '
                          'lagrer alle filer, bilder og PDF-er der — ikke i Supabase Storage. '
                          'Supabase forblir backend for data og brukere. '
                          'Filene ligger under Apps/DriftPro/company_…/kategori/dato/.',
                          style: DriftProTheme.bodyMd.copyWith(
                            color: isDark ? Colors.white70 : Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Åpne f.eks. tickets → 2026-07-17 for å se avviksbilder. '
                          'Tomme kategori-mapper betyr bare at det ikke er lastet opp noe den dagen.',
                          style: DriftProTheme.bodySm.copyWith(
                            color: isDark ? Colors.white54 : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Viktig: Vi lagrer aldri passordet ditt. Du logger inn '
                          'via en sikker side (OAuth), som bank-ID.',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Etter godkjenning kommer du tilbake til driftpro.no med bekreftelse.',
                          style: TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Status', style: DriftProTheme.headingSm),
                        const SizedBox(height: 8),
                        if (connected) ...[
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.check_circle, color: Colors.green),
                            title: Text(_status?['account_email']?.toString() ?? 'Tilkoblet'),
                            subtitle: Text(
                              'Mappe: ${_status?['root_folder'] ?? '/'}\n'
                              'Lås: ${(_status?['disconnect_locked'] != false) ? 'På — kan ikke kobles fra ved et uhell' : 'Av — frakobling mulig'}\n'
                              'Helse: ${_status?['last_health_ok_at'] != null ? 'OK' : (_status?['needs_reauth'] == true ? 'Trenger ny innlogging' : 'Venter')}'
                              '${_status?['last_health_error'] != null ? '\nSiste feil: ${_status!['last_health_error']}' : ''}',
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_status?['disconnect_locked'] != false) ...[
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _unlockDisconnect,
                              icon: const Icon(Icons.lock_open),
                              label: const Text('Lås opp frakobling (superadmin)'),
                            ),
                          ] else ...[
                            FilledButton.icon(
                              onPressed: _busy ? null : _lockDisconnect,
                              icon: const Icon(Icons.lock),
                              label: const Text('Lås Dropbox igjen'),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _disconnect,
                              icon: const Icon(Icons.pause_circle_outline),
                              label: const Text('Deaktiver midlertidig'),
                            ),
                          ],
                        ] else ...[
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.cloud_off_outlined),
                            title: Text('Ikke aktiv'),
                            subtitle: Text(
                              'Koble skylagring, eller reaktiver lagret tilkobling. '
                              'Uten aktiv Dropbox kan ingen nye filer lastes opp.',
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _busy ? null : _connect,
                            icon: _busy
                                ? SizedBox(width: 18, height: 18, child: DriftProLoadingIndicator(size: 18))
                                : const Icon(Icons.link),
                            label: const Text('Koble skylagring (sikker innlogging)'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _reactivate,
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('Reaktiver lagret tilkobling'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (connected) ...[
                  if (_pendingMigration > 0) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: const Color(0xFFFFF8E1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Migrer gamle filer fra Supabase',
                              style: DriftProTheme.headingSm,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$_pendingMigration fil(er) ligger fortsatt i Supabase med gamle stier. '
                              'Kjør migrering én gang — deretter lagres alt nytt direkte i skylagring.',
                              style: DriftProTheme.bodySm,
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _busy ? null : _migrateBatch,
                              icon: _busy
                                  ? SizedBox(width: 18, height: 18, child: DriftProLoadingIndicator(size: 18))
                                  : const Icon(Icons.cloud_upload_outlined),
                              label: Text('Migrer neste batch (max 25)'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Automatiske mapper', style: DriftProTheme.headingSm),
                          const SizedBox(height: 4),
                          Text(
                            'Alle opplastinger (ruter, avvik, dokumenter, bilder m.m.) '
                            'lagres automatisk i riktig mappe i skylagring.',
                            style: DriftProTheme.bodySm.copyWith(
                              color: isDark ? Colors.white60 : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...DropboxStorageModule.values.map(
                            (m) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: const Icon(Icons.folder_outlined, size: 20),
                              title: Text(m.label, style: DriftProTheme.bodyMd),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Mappestruktur i skylagring',
                  style: DriftProTheme.labelLg,
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '/DriftPro/\n'
                    '  company_<din-bedrift-id>/\n'
                    '    routes/          ← rute-PDF (tildelt)\n'
                    '    partner_deductions/ ← bot/trekk bevis\n'
                    '    sap_inbox/       ← rute-PDF fra e-post\n'
                    '    tickets/         ← avvik-bilder\n'
                    '    dms/             ← dokumenter\n'
                    '    partners/        ← partner-filer\n'
                    '    employees/       ← ansattfiler\n'
                    '    hms/             ← HMS, SJA, utstyr\n'
                    '    whistleblowing/  ← varsling',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Oppsett (én gang)',
                  style: DriftProTheme.labelLg,
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. Opprett app i utviklerportal for skylagring\n'
                  '2. Legg redirect-URL i appen (se README)\n'
                  '3. Legg app-nøkler og redirect-URI i Supabase Secrets\n'
                  '4. Deploy edge function for fillagring',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
              ],
            ),
    );
  }
}
