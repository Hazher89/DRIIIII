import 'package:flutter/material.dart';

import '../../../core/constants/partner_sms_templates.dart';
import '../../../core/theme/app_theme.dart';
import 'partner_ui.dart';

/// Maler + meldingsfelt for partner-SMS.
class PartnerSmsMessageSection extends StatelessWidget {
  final TextEditingController messageCtrl;
  final VoidCallback? onChanged;
  final int minLines;

  const PartnerSmsMessageSection({
    super.key,
    required this.messageCtrl,
    this.onChanged,
    this.minLines = 5,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Velg mal eller skriv egen tekst',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.grey[200] : Colors.grey[900],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in kPartnerSmsTemplates)
              ActionChip(
                label: Text(t.title, style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  messageCtrl.text = t.body;
                  onChanged?.call();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: messageCtrl,
          onChanged: (_) => onChanged?.call(),
          decoration: const InputDecoration(
            labelText: 'SMS-melding',
            hintText: 'Meldingen sendes til valgte mottakere…',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          minLines: minLines,
          maxLines: 10,
          maxLength: 1071,
        ),
        const SizedBox(height: 4),
        Text(
          '${messageCtrl.text.trim().length} / 1071 tegn',
          style: TextStyle(fontSize: 11, color: PartnerUi.mutedText(context)),
        ),
      ],
    );
  }
}
