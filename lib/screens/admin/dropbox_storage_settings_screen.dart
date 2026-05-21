import 'package:flutter/material.dart';

import '../../core/services/storage/company_file_storage.dart';
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
  Map<String, dynamic>? _status;
  Map<String, bool> _modules = DropboxStorageModule.defaultsEnabled();

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
          content: Text('Dropbox er koblet! Store filer lagres nå i Dropbox.'),
          duration: Duration(seconds: 6),
        ),
      );
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await CompanyFileStorage.dropboxStatus();
      if (mounted) {
        setState(() {
          _status = s;
          _modules = DropboxStorageModule.fromStatusJson(s);
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

  Future<void> _toggleModule(DropboxStorageModule mod, bool value) async {
    setState(() {
      _modules = Map.from(_modules)..[mod.key] = value;
      _busy = true;
    });
    try {
      final updated = await CompanyFileStorage.updateStorageModules(_modules);
      if (mounted) {
        setState(() => _modules = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${mod.label}: ${value ? "Dropbox" : "kun Supabase"}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: $e')),
        );
        await _load();
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
                          'Supabase har begrenset plass (f.eks. 500 MB). DriftPro lagrer '
                          'små filer i Supabase og filer over 1 MB i mappen '
                          'DriftPro på din Dropbox — organisert per bedrift.',
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
                              'Grense Supabase: ${((_status?['large_file_threshold_bytes'] as int?) ?? 1048576) / 1048576} MB',
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
                              'Koble Dropbox for å lagre PDF-ruter, avviksbilder og dokumenter utover 1 MB.',
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
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Moduler som bruker Dropbox', style: DriftProTheme.headingSm),
                          const SizedBox(height: 4),
                          Text(
                            'Filer over 1 MB i påslåtte moduler lagres i Dropbox. '
                            'Avslåtte moduler bruker alltid Supabase.',
                            style: DriftProTheme.bodySm.copyWith(
                              color: isDark ? Colors.white60 : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...DropboxStorageModule.values.map(
                            (m) => SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(m.label, style: DriftProTheme.bodyMd),
                              value: _modules[m.key] ?? true,
                              onChanged: _busy
                                  ? null
                                  : (v) => _toggleModule(m, v),
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
                    '    routes/          ← rute-PDF\n'
                    '    tickets/         ← avvik-bilder\n'
                    '    dms/             ← dokumenter\n'
                    '    partners/        ← partner-filer\n'
                    '    employees/       ← ansattfiler',
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
