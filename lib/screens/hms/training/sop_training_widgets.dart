import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/hms/sop_training_models.dart';

/// Marker søkeord i tekst med utheving.
class SopHighlightedText extends StatelessWidget {
  const SopHighlightedText({
    super.key,
    required this.text,
    this.query = '',
    this.style,
    this.maxLines,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DriftProTheme.bodyMd;
    final q = query.trim();
    if (q.isEmpty) {
      return Text(text, style: base, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }

    final terms = q
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2)
        .toList();
    if (terms.isEmpty) {
      return Text(text, style: base, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }

    final pattern = terms.map(RegExp.escape).join('|');
    final re = RegExp(pattern, caseSensitive: false);
    final spans = <TextSpan>[];
    var start = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start)));
      }
      spans.add(TextSpan(
        text: text.substring(m.start, m.end),
        style: base.copyWith(
          backgroundColor: DriftProTheme.warning.withValues(alpha: 0.35),
          fontWeight: FontWeight.w800,
          color: DriftProTheme.primaryGreenDark,
        ),
      ));
      start = m.end;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));

    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: base, children: spans),
    );
  }
}

Color sopPriorityColor(String? priority) {
  switch (priority?.toUpperCase()) {
    case 'KRITISK':
      return DriftProTheme.error;
    case 'HØY':
      return DriftProTheme.riskHigh;
    case 'MODERAT':
      return DriftProTheme.warning;
    case 'LAV':
      return DriftProTheme.success;
    default:
      return DriftProTheme.accentBlue;
  }
}

IconData sopKindIcon(SopEntryKind kind) {
  switch (kind) {
    case SopEntryKind.procedure:
      return Icons.checklist_rounded;
    case SopEntryKind.system:
      return Icons.hub_outlined;
    case SopEntryKind.alert:
      return Icons.warning_amber_rounded;
    case SopEntryKind.info:
      return Icons.lightbulb_outline_rounded;
    case SopEntryKind.definition:
      return Icons.menu_book_outlined;
    case SopEntryKind.escalation:
      return Icons.support_agent_rounded;
    case SopEntryKind.paragraph:
      return Icons.article_outlined;
  }
}

String sopKindLabel(SopEntryKind kind) {
  switch (kind) {
    case SopEntryKind.procedure:
      return 'Oppgave';
    case SopEntryKind.system:
      return 'System';
    case SopEntryKind.alert:
      return 'Viktig';
    case SopEntryKind.info:
      return 'Tips';
    case SopEntryKind.definition:
      return 'Definisjon';
    case SopEntryKind.escalation:
      return 'Eskalering';
    case SopEntryKind.paragraph:
      return 'Beskrivelse';
  }
}
