import 'package:flutter/material.dart';

import '../../../models/survey/survey.dart';

class SurveyQuestionTypeDef {
  const SurveyQuestionTypeDef({
    required this.type,
    required this.label,
    required this.description,
    required this.icon,
    required this.group,
    this.defaultOptions = const [],
    this.defaultConditionValue,
  });

  final SurveyQuestionType type;
  final String label;
  final String description;
  final IconData icon;
  final String group;
  final List<String> defaultOptions;
  final String? defaultConditionValue;
}

/// Katalog over alle spørsmålstyper — grupper som SurveyMonkey/Kantar.
class SurveyQuestionCatalog {
  SurveyQuestionCatalog._();

  static const groups = [
    'Grunnleggende',
    'Valg',
    'Skala & vurdering',
    'Avansert',
    'Kontakt & data',
  ];

  static const all = <SurveyQuestionTypeDef>[
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.text,
      label: 'Kort tekst',
      description: 'Enkelt tekstfelt',
      icon: Icons.short_text,
      group: 'Grunnleggende',
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.paragraph,
      label: 'Lang tekst',
      description: 'Fritekst / kommentar',
      icon: Icons.notes,
      group: 'Grunnleggende',
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.single_choice,
      label: 'Enkeltvalg',
      description: 'Ett alternativ',
      icon: Icons.radio_button_checked,
      group: 'Valg',
      defaultOptions: ['Alternativ 1', 'Alternativ 2'],
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.multiple_choice,
      label: 'Flervalg',
      description: 'Flere alternativer',
      icon: Icons.check_box_outlined,
      group: 'Valg',
      defaultOptions: ['Alternativ 1', 'Alternativ 2'],
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.dropdown,
      label: 'Nedtrekksliste',
      description: 'Kompakt enkeltvalg',
      icon: Icons.arrow_drop_down_circle_outlined,
      group: 'Valg',
      defaultOptions: ['Alternativ 1', 'Alternativ 2'],
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.yes_no,
      label: 'Ja / Nei',
      description: 'Binært valg',
      icon: Icons.toggle_on_outlined,
      group: 'Valg',
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.rating,
      label: 'Stjerner (1–5)',
      description: 'Visuell vurdering',
      icon: Icons.star_outline,
      group: 'Skala & vurdering',
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.likert,
      label: 'Likert-skala',
      description: 'Enig / uenig',
      icon: Icons.view_column_outlined,
      group: 'Skala & vurdering',
      defaultOptions: ['Helt uenig', 'Uenig', 'Nøytral', 'Enig', 'Helt enig'],
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.nps,
      label: 'NPS (0–10)',
      description: 'Net Promoter Score',
      icon: Icons.insights_outlined,
      group: 'Skala & vurdering',
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.slider,
      label: 'Skyveknapp',
      description: 'Numerisk skala',
      icon: Icons.tune_outlined,
      group: 'Skala & vurdering',
      defaultOptions: ['0', '100'],
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.matrix,
      label: 'Matrise / rutenett',
      description: 'Flere rader × kolonner',
      icon: Icons.grid_on_outlined,
      group: 'Avansert',
      defaultOptions: ['Kvalitet', 'Service', 'Pris'],
      defaultConditionValue: 'Dårlig|Middels|Bra|Utmerket',
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.ranking,
      label: 'Rangering',
      description: 'Sorter prioritet',
      icon: Icons.format_list_numbered,
      group: 'Avansert',
      defaultOptions: ['Alternativ A', 'Alternativ B', 'Alternativ C'],
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.date,
      label: 'Dato',
      description: 'Kalender',
      icon: Icons.calendar_today_outlined,
      group: 'Kontakt & data',
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.time,
      label: 'Klokkeslett',
      description: 'Tidsvelger',
      icon: Icons.schedule_outlined,
      group: 'Kontakt & data',
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.number,
      label: 'Tall',
      description: 'Numerisk svar',
      icon: Icons.pin_outlined,
      group: 'Kontakt & data',
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.email,
      label: 'E-post',
      description: 'Med validering',
      icon: Icons.email_outlined,
      group: 'Kontakt & data',
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.phone,
      label: 'Telefon',
      description: 'Telefonnummer',
      icon: Icons.phone_outlined,
      group: 'Kontakt & data',
    ),
    SurveyQuestionTypeDef(
      type: SurveyQuestionType.url,
      label: 'URL / lenke',
      description: 'Webside',
      icon: Icons.link_outlined,
      group: 'Kontakt & data',
    ),
  ];

  static SurveyQuestionTypeDef? defFor(SurveyQuestionType type) {
    for (final d in all) {
      if (d.type == type) return d;
    }
    return null;
  }

  static String labelFor(SurveyQuestionType type) =>
      defFor(type)?.label ?? type.name;

  static List<String> matrixColumns(SurveyQuestion q) {
    if (q.type != SurveyQuestionType.matrix) return const [];
    final raw = q.conditionValue ?? '';
    if (raw.isEmpty) return const ['Dårlig', 'Middels', 'Bra'];
    return raw.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static void setMatrixColumns(SurveyQuestion q, List<String> columns) {
    // Brukes ved lagring — conditionValue når type er matrix og ingen betingelse
  }
}
