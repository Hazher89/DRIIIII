import 'package:flutter/material.dart';

import '../../../core/hms/hms_templates.dart';
import '../../../core/theme/app_theme.dart';

/// Velg mal før opprettelse (risiko, SJA, vernerunde).
class HmsTemplatePickerSheet extends StatelessWidget {
  final HmsModuleKind kind;
  final void Function(dynamic template) onSelected;
  final VoidCallback? onBlank;

  const HmsTemplatePickerSheet({
    super.key,
    required this.kind,
    required this.onSelected,
    this.onBlank,
  });

  static Future<void> show(
    BuildContext context, {
    required HmsModuleKind kind,
    required void Function(dynamic template) onSelected,
    VoidCallback? onBlank,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => HmsTemplatePickerSheet(
        kind: kind,
        onSelected: onSelected,
        onBlank: onBlank,
      ),
    );
  }

  List<dynamic> get _templates {
    switch (kind) {
      case HmsModuleKind.risk:
        return HmsTemplates.riskTemplates;
      case HmsModuleKind.sja:
        return HmsTemplates.sjaTemplates;
      case HmsModuleKind.safetyRound:
        return HmsTemplates.safetyRoundTemplates;
    }
  }

  String get _title {
    switch (kind) {
      case HmsModuleKind.risk:
        return 'Velg risikomal';
      case HmsModuleKind.sja:
        return 'Velg SJA-mal';
      case HmsModuleKind.safetyRound:
        return 'Velg vernerunde-mal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(_title, style: DriftProTheme.headingSm),
          const SizedBox(height: 8),
          Text(
            'Malene er klare til utfylling. Du kan redigere alt før lagring.',
            style: DriftProTheme.caption,
          ),
          const SizedBox(height: 16),
          if (onBlank != null)
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onBlank!();
              },
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Start blankt skjema'),
            ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight - 180),
            child: ListView(
              shrinkWrap: true,
              children: _templates.map((t) {
                final title = t is HmsRiskTemplate
                    ? t.title
                    : t is HmsSjaTemplate
                        ? t.title
                        : (t as HmsSafetyRoundTemplate).title;
                final subtitle = t is HmsRiskTemplate
                    ? t.area
                    : t is HmsSjaTemplate
                        ? t.location
                        : '${(t as HmsSafetyRoundTemplate).checklist.length} sjekkpunkter';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined,
                        color: DriftProTheme.primaryGreen),
                    title: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(context);
                      onSelected(t);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
