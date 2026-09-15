import 'package:flutter/material.dart';

import '../../core/services/assistant/assistant_fab_prefs.dart';
import '../../core/services/chat/partner_chat_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Mer → Chat-innstillinger: visningsnavn + chat-boble (MAVI).
class ChatUserSettingsScreen extends StatefulWidget {
  const ChatUserSettingsScreen({super.key});

  @override
  State<ChatUserSettingsScreen> createState() => _ChatUserSettingsScreenState();
}

class _ChatUserSettingsScreenState extends State<ChatUserSettingsScreen> {
  final _nameCtrl = TextEditingController();
  UserProfile? _profile;
  bool _loading = true;
  bool _savingName = false;
  bool _savingFab = false;
  bool _fabEnabled = true;
  String? _error;
  DateTime? _changedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await SupabaseService.fetchEffectiveUserProfile();
      if (profile == null) throw Exception('Ikke innlogget');
      final meta = await PartnerChatService.fetchMyChatDisplayName();
      final fab = await AssistantFabPrefs.isEnabled(profile.id);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _nameCtrl.text = (meta['chat_display_name'] as String?)?.trim().isNotEmpty == true
            ? meta['chat_display_name'] as String
            : profile.fullName;
        final raw = meta['chat_display_name_changed_at'];
        _changedAt = raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
        _fabEnabled = fab;
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

  bool get _isMavi => _profile?.isMaviEmployee == true;

  String? get _nextChangeHint {
    final at = _changedAt;
    if (at == null) return null;
    final next = at.add(const Duration(days: 30));
    if (next.isBefore(DateTime.now())) return null;
    final d = next.day.toString().padLeft(2, '0');
    final m = next.month.toString().padLeft(2, '0');
    return 'Neste endring mulig $d.$m.${next.year}';
  }

  Future<void> _saveName() async {
    if (_savingName) return;
    setState(() => _savingName = true);
    try {
      await PartnerChatService.setMyChatDisplayName(_nameCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat-navn lagret')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _toggleFab(bool v) async {
    final p = _profile;
    if (p == null || _savingFab) return;
    setState(() {
      _fabEnabled = v;
      _savingFab = true;
    });
    try {
      await AssistantFabPrefs.setEnabled(p.id, v);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(v ? 'Chat-boble er på' : 'Chat-boble er av'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _fabEnabled = !v);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _savingFab = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat-innstillinger')),
      body: _loading
          ? const Center(child: DriftProLoadingIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                Text(
                  'Visningsnavn i chat',
                  style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Alle ser dette navnet når du skriver. Du kan endre det én gang per måned. '
                  'Superadmin kan endre andres navn når som helst.',
                  style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Chat-navn',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_nextChangeHint != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _nextChangeHint!,
                      style: TextStyle(fontSize: 12.5, color: Colors.orange.shade800),
                    ),
                  ),
                FilledButton(
                  onPressed: _savingName ? null : _saveName,
                  style: FilledButton.styleFrom(
                    backgroundColor: DriftProTheme.primaryGreen,
                  ),
                  child: _savingName
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Lagre chat-navn'),
                ),
                if (_isMavi) ...[
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Flyttbar chat-boble',
                    style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Grønn boble du kan dra rundt i appen. Kun synlig for MAVI-ansatte — '
                    'ikke partnere eller partner-ansatte.',
                    style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Vis chat-boble'),
                    subtitle: Text(_fabEnabled ? 'På' : 'Av'),
                    value: _fabEnabled,
                    activeTrackColor: DriftProTheme.primaryGreen.withValues(alpha: 0.5),
                    activeThumbColor: DriftProTheme.primaryGreen,
                    onChanged: _savingFab ? null : _toggleFab,
                  ),
                ],
              ],
            ),
    );
  }
}
