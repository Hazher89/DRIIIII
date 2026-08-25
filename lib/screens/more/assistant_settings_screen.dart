import 'package:flutter/material.dart';

import '../../core/services/assistant/assistant_flag_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/driftpro_theme_context.dart';
import '../../widgets/assistant/driftpro_assistant_sheet.dart';
import '../../widgets/driftpro_loading_indicator.dart';

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
  bool _sqlMissing = false;
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
      _sqlMissing = false;
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
      final title = flag.title?.trim();
      setState(() {
        _enabled = flag.enabled;
        // Ikke overskriv med tilfeldig tekst brukeren skrev som «spørsmål».
        if (title != null &&
            title.isNotEmpty &&
            title.length <= 40 &&
            !title.contains('?')) {
          _titleCtrl.text = title;
        } else if (_titleCtrl.text.contains('?')) {
          _titleCtrl.text = 'Spør DriftPro';
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

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('set_company_assistant_enabled') ||
        msg.contains('assistant_enabled') ||
        msg.contains('could not find the function') ||
        msg.contains('schema cache') ||
        msg.contains('does not exist')) {
      return 'Database-funksjonen mangler. Kjør filen '
          '20260825150000_assistant_enabled.sql i Supabase SQL Editor, '
          'deretter last siden på nytt.';
    }
    return e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  Future<void> _save(bool enabled) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _enabled = enabled;
    });
    try {
      var title = _titleCtrl.text.trim();
      if (title.isEmpty || title.contains('?') || title.length > 40) {
        title = 'Spør DriftPro';
        _titleCtrl.text = title;
      }
      await AssistantFlagService.setEnabled(enabled: enabled, title: title);
      if (!mounted) return;
      setState(() => _sqlMissing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Chat-ikonet er nå synlig for alle i selskapet.'
                : 'Chat-ikonet er skjult for alle.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final friendly = _friendlyError(e);
      setState(() {
        _enabled = !enabled;
        _error = friendly;
        _sqlMissing = friendly.contains('Database-funksjonen mangler');
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openChat() {
    var title = _titleCtrl.text.trim();
    if (title.isEmpty || title.contains('?') || title.length > 40) {
      title = 'Spør DriftPro';
    }
    showDriftProAssistantSheet(context, title: title);
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;

    if (_loading) {
      return Scaffold(
        backgroundColor: drift.scaffold,
        body: const Center(child: DriftProLoadingIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: drift.scaffold,
      appBar: AppBar(
        title: const Text('DriftPro-assistent'),
        backgroundColor: DriftProTheme.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFE082)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dette er ikke chatten',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFF5D4037),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Her slår du bare chat-ikonet av/på for hele selskapet. '
                  'For å stille spørsmål: trykk «Åpne chat» under, eller bruk '
                  'det grønne chat-ikonet nederst til høyre når det er på.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: Color(0xFF5D4037),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openChat,
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Åpne chat og still spørsmål'),
            style: FilledButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
              minimumSize: const Size(double.infinity, 52),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 20),
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
                Text(
                  'Synlighet for alle',
                  style: DriftProTheme.headingSm.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'Når dette er på, ser alle innloggede brukere chat-ikonet '
                  '(web og app) uten ny install.',
                  style: TextStyle(color: drift.textMuted, fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Vis chat-ikon',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  value: _enabled,
                  onChanged: _saving ? null : (v) => _save(v),
                ),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                TextField(
                  controller: _titleCtrl,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Navn på chat-vinduet',
                    border: OutlineInputBorder(),
                    helperText: 'Ikke skriv spørsmål her — bare tittel, f.eks. Spør DriftPro',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: DriftProTheme.error, fontSize: 13, height: 1.35),
                  ),
                ],
                if (_sqlMissing) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Du kan fortsatt bruke «Åpne chat» over mens SQL kjøres.',
                    style: TextStyle(color: drift.textMuted, fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Hvordan Google «lærer» MAVI-reglene\n'
            'Vi trener ikke en egen modell. Ved hvert spørsmål henter DriftPro '
            'relevante utdrag (SOP, bilutleie, hjelp) og sender dem til Gemini '
            'som kontekst. Da svarer Google ut fra MAVI sine tekster.\n\n'
            'Gemini-oppsett (engangs):\n'
            '1) Gå til aistudio.google.com → Get API key\n'
            '2) Opprett nøkkel i et Google-prosjekt\n'
            '3) I Supabase: Edge Functions → Secrets → GEMINI_API_KEY = nøkkelen\n'
            '4) Deploy funksjonen driftpro-assistant\n'
            '5) Valgfritt: GEMINI_MODEL = gemini-2.0-flash\n\n'
            'Uten Gemini-nøkkel faller chatten tilbake til lokalt dokumentsøk.',
            style: DriftProTheme.bodySm.copyWith(color: drift.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
