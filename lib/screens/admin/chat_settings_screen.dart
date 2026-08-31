import 'package:flutter/material.dart';

import '../../core/services/chat/chat_flag_service.dart';
import '../../core/services/supabase_service.dart';
import '../../models/user_profile.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/driftpro_theme_context.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Superadmin: slå partner-chat av/på for MAVI og/eller partnere — live uten rebuild.
class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key});

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _mavi = true;
  bool _partners = true;
  String? _error;
  String? _companyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await SupabaseService.fetchEffectiveUserProfile();
      if (profile == null) {
        setState(() {
          _error = 'Kunne ikke hente brukerprofil.';
          _loading = false;
        });
        return;
      }
      if (profile.role != UserRole.superadmin) {
        setState(() {
          _error = 'Kun superadmin kan styre chat-systemet.';
          _loading = false;
        });
        return;
      }
      final companyId = profile.companyId;
      if (companyId == null) {
        setState(() {
          _error = 'Ingen bedrift knyttet til profilen.';
          _loading = false;
        });
        return;
      }
      final flag = await ChatFlagService.fetchForCompany(companyId);
      if (!mounted) return;
      setState(() {
        _companyId = companyId;
        _mavi = flag.maviEnabled;
        _partners = flag.partnersEnabled;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _publish({required bool mavi, required bool partners}) async {
    if (_companyId == null || _saving) return;
    final prevMavi = _mavi;
    final prevPartners = _partners;
    setState(() {
      _mavi = mavi;
      _partners = partners;
      _saving = true;
    });
    try {
      final flag = await ChatFlagService.setFlags(
        maviEnabled: mavi,
        partnersEnabled: partners,
      );
      if (!mounted) return;
      setState(() {
        _mavi = flag.maviEnabled;
        _partners = flag.partnersEnabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Oppdatert live — chat skjules/vises med en gang på web og app'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mavi = prevMavi;
        _partners = prevPartners;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke lagre: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Partner-chat')),
      body: _loading
          ? const Center(child: DriftProLoadingIndicator(size: 48))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Material(
                      color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.bolt, color: DriftProTheme.primaryGreen),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Bryterne publiserer med en gang. Web og mobil oppdateres live — '
                                'ingen ny build eller IPA. Chat forsvinner fra meny/dock når flagget slås av.',
                                style: TextStyle(fontSize: 12, height: 1.45, color: drift.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SwitchListTile(
                      title: const Text('Chat for MAVI-ansatte', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: const Text(
                        'Vis «Meldinger» i Partnere / rute-modulen for interne brukere',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _mavi,
                      activeThumbColor: DriftProTheme.primaryGreen,
                      onChanged: _saving
                          ? null
                          : (v) => _publish(mavi: v, partners: _partners),
                    ),
                    const Divider(),
                    SwitchListTile(
                      title: const Text('Chat for partnere', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: const Text(
                        'Vis «Meldinger» i partnerportalen (dock / Mer) for bil-eier, sjåfør og ansatt',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _partners,
                      activeThumbColor: DriftProTheme.primaryGreen,
                      onChanged: _saving
                          ? null
                          : (v) => _publish(mavi: _mavi, partners: v),
                    ),
                    if (_saving) ...[
                      const SizedBox(height: 16),
                      const Center(child: DriftProLoadingIndicator(size: 28)),
                    ],
                  ],
                ),
    );
  }
}
