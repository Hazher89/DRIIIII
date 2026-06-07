import 'package:flutter/material.dart';

import '../../core/services/storage/company_file_storage.dart';
import '../../core/services/storage/supabase_dropbox_migration_service.dart';
import '../../core/services/storage/dropbox_storage_modules.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/open_external_url.dart';

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
          content: Text('Dropbox er koblet! Nye filer lagres nå i Dropbox.'),
          duration: Duration(seconds: 6),
        ),
      );
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await CompanyFileStorage.dropboxStatus();
      final pending = await SupabaseDropboxMigrationService.countPendingMigration();
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
              'Kunne ikke åpne Dropbox. Godkjenn tilgang i nettleseren, deretter trykk Oppdater.',
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Logg inn hos Dropbox og godkjenn. Kom tilbake hit og trykk Oppdater.',
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Koble fra Dropbox?'),
        content: const Text(
          'Nye filer lagres igjen kun i Supabase. Eksisterende filer i Dropbox blir liggende der.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Koble fra')),
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
          const SnackBar(content: Text('Dropbox frakoblet')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
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
        title: const Text('Dropbox-lagring'),
        actions: [
          IconButton(
            tooltip: 'Oppdater',
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                                'Ubegrenset fillagring via Dropbox',
                                style: DriftProTheme.headingSm,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Supabase har begrenset plass. Når Dropbox er koblet lagrer '
                          'DriftPro alle filer i Dropbox — automatisk sortert i mapper '
                          'per funksjon (ruter, HMS, dokumenter, osv.) per bedrift.',
                          style: DriftProTheme.bodyMd.copyWith(
                            color: isDark ? Colors.white70 : Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Viktig: Vi lagrer aldri Dropbox-passordet ditt. Du logger inn '
                          'via Dropboxes sikre side (OAuth), som bank-ID.',
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
                              'Mappe: ${_status?['root_folder'] ?? '/DriftPro'}\n'
                              'Lagring: ${((_status?['large_file_threshold_bytes'] as int?) ?? 0) == 0 ? 'Alltid Dropbox' : 'Supabase under ${((_status?['large_file_threshold_bytes'] as int?) ?? 0) / 1048576} MB'}',
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _disconnect,
                            icon: const Icon(Icons.link_off),
                            label: const Text('Koble fra Dropbox'),
                          ),
                        ] else ...[
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.cloud_off_outlined),
                            title: Text('Ikke koblet'),
                            subtitle: Text(
                              'Koble Dropbox for å lagre alle filer utenfor Supabase-kvoten.',
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _busy ? null : _connect,
                            icon: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.link),
                            label: const Text('Koble Dropbox (sikker innlogging)'),
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
                              'Kjør migrering én gang — deretter lagres alt nytt direkte i Dropbox.',
                              style: DriftProTheme.bodySm,
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _busy ? null : _migrateBatch,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
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
                            'lagres automatisk i riktig mappe under Dropbox.',
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
                  'Mappestruktur i Dropbox',
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
                  '1. Opprett app på dropbox.com/developers\n'
                  '2. Legg redirect-URL i appen:\n'
                  '   …/functions/v1/dropbox-storage?action=oauth_callback\n'
                  '3. Legg DROPBOX_APP_KEY, DROPBOX_APP_SECRET og DROPBOX_REDIRECT_URI i Supabase Secrets\n'
                  '4. Deploy edge function dropbox-storage',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
              ],
            ),
    );
  }
}
