import 'package:flutter/material.dart';

import '../../core/services/assistant/assistant_flag_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/driftpro_theme_context.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import 'widgets/info_page_scaffold.dart';

/// Admin: slå DriftPro-assistenten av/på remote (uten app-oppdatering).
class AssistantSettingsScreen extends StatefulWidget {
  const AssistantSettingsScreen({super.key});

  @override
  State<AssistantSettingsScreen> createState() => _AssistantSettingsScreenState();
}

class _AssistantSettingsScreenState extends State<AssistantSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  String? _error;
  final _titleCtrl = TextEditingController(text: 'Spør DriftPro');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await SupabaseService.fetchEffectiveUserProfile();
      final companyId = profile?.companyId;
      if (companyId == null) {
        setState(() {
          _error = 'Ingen bedrift knyttet til profilen.';
          _loading = false;
        });
        return;
      }
      final flag = await AssistantFlagService.fetchForCompany(companyId);
      if (!mounted) return;
      setState(() {
        _enabled = flag.enabled;
        if (flag.title != null && flag.title!.trim().isNotEmpty) {
          _titleCtrl.text = flag.title!.trim();
        }
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

  Future<void> _save(bool enabled) async {
    setState(() {
      _saving = true;
      _error = null;
      _enabled = enabled;
    });
    try {
      await AssistantFlagService.setEnabled(
        enabled: enabled,
        title: _titleCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Assistenten er synlig for alle i selskapet nå.'
                : 'Assistenten er skjult. Ingen trenger å oppdatere appen.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enabled = !enabled;
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;

    if (_loading) {
      return const Scaffold(
        body: Center(child: DriftProLoadingIndicator()),
      );
    }

    return InfoPageScaffold(
      title: 'DriftPro-assistent',
      subtitle: 'Slå chatten av eller på for hele selskapet — uten ny app-install',
      icon: Icons.smart_toy_outlined,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: drift.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: drift.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Vis chat-ikon',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Når på, dukker assistenten opp nederst til høyre for alle '
                  'innloggede brukere (web og app).',
                  style: TextStyle(color: drift.textMuted, fontSize: 13),
                ),
                value: _enabled,
                activeThumbColor: Colors.white,
                activeTrackColor: DriftProTheme.primaryGreen,
                onChanged: _saving ? null : _save,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Tittel i chatten',
                  border: OutlineInputBorder(),
                  helperText: 'F.eks. «Spør DriftPro»',
                ),
                onEditingComplete: () {
                  if (_enabled) _save(true);
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: DriftProTheme.error, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Assistenten søker i SOP-opplæring, bilutleie-regler og hjelpetekster. '
          'Den bruker ingen betalt AI-tjeneste.',
          style: DriftProTheme.bodySm.copyWith(color: drift.textMuted, height: 1.4),
        ),
      ],
    );
  }
}
