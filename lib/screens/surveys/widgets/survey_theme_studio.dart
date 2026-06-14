import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/survey/survey_advanced_service.dart';
import '../../../core/services/survey/survey_service.dart';
import '../../../core/services/survey/survey_theme_presets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/driftpro_theme_context.dart';
import '../../../models/survey/survey.dart';
import '../../../models/survey/survey_advanced.dart';
import 'survey_theme_preview.dart';

class SurveyThemeStudio extends StatefulWidget {
  const SurveyThemeStudio({
    super.key,
    required this.survey,
    required this.themeConfig,
    required this.snapshots,
    required this.onSurveyRefresh,
    required this.onThemeSaved,
    this.onContinueToDel,
  });

  final Survey survey;
  final SurveyThemeConfig themeConfig;
  final List<SurveyAnalyticsSnapshot> snapshots;
  final Future<void> Function() onSurveyRefresh;
  final Future<void> Function(SurveyThemeConfig) onThemeSaved;
  final VoidCallback? onContinueToDel;

  @override
  State<SurveyThemeStudio> createState() => _SurveyThemeStudioState();
}

class _SurveyThemeStudioState extends State<SurveyThemeStudio> {
  String _search = '';
  String? _category;

  List<SurveyThemePreset> get _filtered {
    final q = _search.trim().toLowerCase();
    return SurveyThemePresets.all.where((t) {
      if (_category != null && t.category != _category) return false;
      if (q.isEmpty) return true;
      return t.name.toLowerCase().contains(q) ||
          t.category.toLowerCase().contains(q) ||
          t.visualStyleLabel.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final cfg = widget.themeConfig;
    final active = SurveyThemePresets.byNameOrDefault(widget.survey.theme);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Tema', style: DriftProTheme.headingLg.copyWith(color: drift.textPrimary)),
        const SizedBox(height: 6),
        Text(
          'Premium-tema inspirert av Typeform, SurveyMonkey og moderne SaaS-design.',
          style: DriftProTheme.bodyMd.copyWith(color: drift.textMuted),
        ),
        const SizedBox(height: 16),
        if (widget.onContinueToDel != null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onContinueToDel,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Neste: Del undersøkelsen'),
            ),
          ),
        const SizedBox(height: 20),
        SurveyThemePreviewCard(
          preset: active,
          selected: true,
          compact: false,
          showLabels: false,
          onTap: null,
        ),
        const SizedBox(height: 8),
        Text('Aktivt: ${active.name}', style: DriftProTheme.labelMd.copyWith(color: drift.textPrimary)),
        const SizedBox(height: 24),
        TextField(
          decoration: InputDecoration(
            hintText: 'Søk blant ${SurveyThemePresets.all.length} tema…',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _catChip('Alle', null, drift),
              ...SurveyThemePresets.categories.map((c) => _catChip(c, c, drift)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth > 900 ? 4 : c.maxWidth > 600 ? 3 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: 1.35,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _filtered.length,
              itemBuilder: (context, i) {
                final preset = _filtered[i];
                return SurveyThemePreviewCard(
                  preset: preset,
                  selected: widget.survey.theme == preset.name,
                  compact: true,
                  onTap: () => _applyPreset(preset),
                );
              },
            );
          },
        ),
        if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Ingen tema matcher søket.', style: DriftProTheme.bodySm.copyWith(color: drift.textMuted)),
          ),
        if (_filtered.length > 48)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Viser alle ${_filtered.length} tema.',
              style: DriftProTheme.bodySm.copyWith(color: drift.textMuted),
            ),
          ),
        const SizedBox(height: 28),
        Text('Innstillinger', style: DriftProTheme.headingSm.copyWith(color: drift.textPrimary)),
        const SizedBox(height: 8),
        SwitchListTile(
          value: cfg.darkModeForRespondent,
          onChanged: (v) => widget.onThemeSaved(cfg.copyWith(darkModeForRespondent: v)),
          title: const Text('Mørk modus for respondenter'),
        ),
        SwitchListTile(
          value: cfg.showProgressBar,
          onChanged: (v) => widget.onThemeSaved(cfg.copyWith(showProgressBar: v)),
          title: const Text('Vis fremdriftslinje'),
        ),
        SwitchListTile(
          value: cfg.showEstimatedTime,
          onChanged: (v) => widget.onThemeSaved(cfg.copyWith(showEstimatedTime: v)),
          title: const Text('Vis estimert svartid'),
        ),
        const Divider(height: 40),
        Text('Arkiv', style: DriftProTheme.headingSm.copyWith(color: drift.textPrimary)),
        const SizedBox(height: 8),
        const Text('Arkiver ferdige undersøkelser for historikk.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _archive,
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Arkiver undersøkelse'),
        ),
        if (widget.snapshots.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...widget.snapshots.map(
            (s) => ListTile(
              dense: true,
              title: Text('${s.generatedAt.day}.${s.generatedAt.month}.${s.generatedAt.year}'),
              subtitle: Text('${s.completionRate.toStringAsFixed(0)}% · ${s.totalResponses} svar'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _catChip(String label, String? value, dynamic drift) {
    final selected = _category == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => setState(() => _category = selected ? null : value),
      ),
    );
  }

  Future<void> _applyPreset(SurveyThemePreset preset) async {
    await SurveyService.updateSurvey(id: widget.survey.id, theme: preset.name);
    await widget.onThemeSaved(preset.toConfig(widget.survey.id));
    await widget.onSurveyRefresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tema «${preset.name}» aktivert')),
    );
  }

  Future<void> _archive() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await SurveyAdvancedService.archiveSurvey(
      survey: widget.survey,
      archivedBy: user.id,
      note: 'Archived from Theme Studio',
    );
    await widget.onSurveyRefresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Undersøkelse arkivert')),
    );
  }
}

extension SurveyThemeConfigCopy on SurveyThemeConfig {
  SurveyThemeConfig copyWith({
    String? primaryHex,
    String? backgroundHex,
    String? cardHex,
    String? textHex,
    String? accentHex,
    String? logoUrl,
    String? fontFamily,
    String? buttonStyle,
    bool? darkModeForRespondent,
    bool? compactMode,
    bool? showProgressBar,
    bool? showEstimatedTime,
  }) {
    return SurveyThemeConfig(
      surveyId: surveyId,
      primaryHex: primaryHex ?? this.primaryHex,
      backgroundHex: backgroundHex ?? this.backgroundHex,
      cardHex: cardHex ?? this.cardHex,
      textHex: textHex ?? this.textHex,
      accentHex: accentHex ?? this.accentHex,
      logoUrl: logoUrl ?? this.logoUrl,
      fontFamily: fontFamily ?? this.fontFamily,
      buttonStyle: buttonStyle ?? this.buttonStyle,
      darkModeForRespondent: darkModeForRespondent ?? this.darkModeForRespondent,
      compactMode: compactMode ?? this.compactMode,
      showProgressBar: showProgressBar ?? this.showProgressBar,
      showEstimatedTime: showEstimatedTime ?? this.showEstimatedTime,
    );
  }
}
