import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../models/hms/stakeholder_risk_assessment.dart';

/// Laster Excel-malen «Interessepart og risikovurdering.xlsx» som strukturert JSON.
abstract final class StakeholderRiskTemplateLoader {
  static const _assetPath = 'assets/hms/stakeholder_risk_template.json';
  static StakeholderRiskContent? _cached;

  static Future<StakeholderRiskContent> loadTemplate() async {
    _cached ??= StakeholderRiskContent.fromJson(
      jsonDecode(await rootBundle.loadString(_assetPath)) as Map<String, dynamic>,
    );
    return _cloneContent(_cached!);
  }

  static StakeholderRiskContent _cloneContent(StakeholderRiskContent source) {
    final raw = jsonDecode(jsonEncode(source.toJson())) as Map<String, dynamic>;
    final cloned = StakeholderRiskContent.fromJson(raw);
    return _regenerateIds(cloned);
  }

  static StakeholderRiskContent _regenerateIds(StakeholderRiskContent content) {
    const uuid = Uuid();
    return content.copyWith(
      sections: content.sections.map((section) {
        return section.copyWith(
          groups: section.groups.map((g) {
            return StakeholderRiskGroup(
              id: uuid.v4(),
              title: g.title,
              rows: g.rows
                  .map((r) => StakeholderRiskRow(id: uuid.v4(), cells: Map.from(r.cells)))
                  .toList(),
            );
          }).toList(),
          rows: section.rows
              .map((r) => StakeholderRiskRow(id: uuid.v4(), cells: Map.from(r.cells)))
              .toList(),
        );
      }).toList(),
    );
  }

  static int? parseRiskScore(StakeholderRiskSection section, Map<String, String> cells) {
    final scoreKey = section.riskFieldMap['score'];
    if (scoreKey != null) {
      final existing = int.tryParse(cells[scoreKey]?.trim() ?? '');
      if (existing != null) return existing;
    }
    final pKey = section.riskFieldMap['probability'];
    final cKey = section.riskFieldMap['consequence'];
    if (pKey == null || cKey == null) return null;
    final p = int.tryParse(cells[pKey]?.trim() ?? '');
    final c = int.tryParse(cells[cKey]?.trim() ?? '');
    if (p == null || c == null) return null;
    return p * c;
  }

  static Map<String, String> applyAutoRiskScores(
    StakeholderRiskSection section,
    Map<String, String> cells,
  ) {
    final updated = Map<String, String>.from(cells);
    final score = parseRiskScore(section, updated);
    final scoreKey = section.riskFieldMap['score'];
    if (score != null && scoreKey != null) {
      updated[scoreKey] = score.toString();
    }
    final rpKey = section.residualFieldMap['probability'];
    final rcKey = section.residualFieldMap['consequence'];
    final rsKey = section.residualFieldMap['score'];
    if (rpKey != null && rcKey != null && rsKey != null) {
      final rp = int.tryParse(updated[rpKey]?.trim() ?? '');
      final rc = int.tryParse(updated[rcKey]?.trim() ?? '');
      if (rp != null && rc != null) {
        updated[rsKey] = (rp * rc).toString();
      }
    }
    return updated;
  }

  static String riskLevelLabel(int score) {
    if (score <= 4) return 'Lav';
    if (score <= 9) return 'Middels';
    if (score <= 14) return 'Høy';
    if (score <= 19) return 'Kritisk';
    return 'Ekstrem';
  }

  static ColorRiskTier riskTier(int score) {
    if (score <= 4) return ColorRiskTier.low;
    if (score <= 9) return ColorRiskTier.medium;
    if (score <= 14) return ColorRiskTier.high;
    return ColorRiskTier.critical;
  }
}

enum ColorRiskTier { low, medium, high, critical }
