import '../../../models/survey/survey_advanced.dart';

/// Ett komplett respondent-tema — endrer bakgrunn, kort, knapper og tekst.
class SurveyThemePreset {
  const SurveyThemePreset({
    required this.id,
    required this.name,
    required this.category,
    required this.primaryHex,
    required this.backgroundHex,
    required this.cardHex,
    required this.textHex,
    required this.accentHex,
    this.darkMode = false,
    this.buttonStyle = 'rounded',
  });

  final String id;
  final String name;
  final String category;
  final String primaryHex;
  final String backgroundHex;
  final String cardHex;
  final String textHex;
  final String accentHex;
  final bool darkMode;
  final String buttonStyle;

  SurveyThemeConfig toConfig(String surveyId) => SurveyThemeConfig(
        surveyId: surveyId,
        primaryHex: primaryHex,
        backgroundHex: backgroundHex,
        cardHex: cardHex,
        textHex: textHex,
        accentHex: accentHex,
        darkModeForRespondent: darkMode,
        buttonStyle: buttonStyle,
      );
}

/// 200+ ferdige tema — generert + håndplukkede profiler.
class SurveyThemePresets {
  SurveyThemePresets._();

  static List<SurveyThemePreset>? _cache;

  static List<SurveyThemePreset> get all {
    _cache ??= _buildAll();
    return _cache!;
  }

  static List<String> get categories =>
      all.map((t) => t.category).toSet().toList()..sort();

  static SurveyThemePreset? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  static SurveyThemePreset byNameOrDefault(String name) {
    for (final t in all) {
      if (t.name == name || t.id == name) return t;
    }
    return all.first;
  }

  static String _hex(int r, int g, int b) =>
      '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';

  static List<SurveyThemePreset> _buildAll() {
    final out = <SurveyThemePreset>[];

    void add(SurveyThemePreset p) => out.add(p);

    // DriftPro signatur + klassikere
    const classics = [
      ('driftpro-green', 'DriftPro Grønn', 'Signatur', '#1B5E20', '#F7F9F8', '#FFFFFF', '#0F172A', '#0D47A1', false),
      ('nordic-light', 'Nordisk Lys', 'Signatur', '#37474F', '#ECEFF1', '#FFFFFF', '#263238', '#546E7A', false),
      ('midnight-pro', 'Midnight Pro', 'Signatur', '#64B5F6', '#0D1117', '#161B22', '#E6EDF3', '#238636', true),
      ('corporate-blue', 'Corporate Blå', 'Business', '#1565C0', '#E3F2FD', '#FFFFFF', '#0D47A1', '#0277BD', false),
      ('executive-slate', 'Executive Skifer', 'Business', '#455A64', '#ECEFF1', '#FFFFFF', '#263238', '#78909C', false),
      ('gold-premium', 'Premium Gull', 'Business', '#F9A825', '#FFF8E1', '#FFFFFF', '#4E342E', '#FF8F00', false),
    ];
    for (final c in classics) {
      add(SurveyThemePreset(
        id: c.$1,
        name: c.$2,
        category: c.$3,
        primaryHex: c.$4,
        backgroundHex: c.$5,
        cardHex: c.$6,
        textHex: c.$7,
        accentHex: c.$8,
        darkMode: c.$9,
      ));
    }

    // HSL-genererte paletter — 24 nyanser × 4 varianter = 96 tema
    const variantDefs = [
      ('Lys', false, 0.96, 0.45, 1.0),
      ('Pastell', false, 0.94, 0.35, 0.85),
      ('Kraftig', false, 0.92, 0.55, 1.0),
      ('Mørk', true, 0.12, 0.65, 0.95),
    ];

    for (var h = 0; h < 360; h += 15) {
      for (final v in variantDefs) {
        final primary = _hslHex(h.toDouble(), v.$4, v.$5);
        final bg = v.$3 > 0.5 ? _hslHex(h.toDouble(), 0.08, v.$3) : _hslHex(h.toDouble(), 0.15, v.$3);
        final card = v.$3 > 0.5 ? '#FFFFFF' : _hslHex(h.toDouble(), 0.12, 0.18);
        final text = v.$2 ? '#F1F5F9' : '#0F172A';
        final accent = _hslHex((h + 30) % 360, v.$4, v.$5);
        add(SurveyThemePreset(
          id: 'h${h}_${v.$1.toLowerCase()}',
          name: 'Hue $h ${v.$1}',
          category: v.$2 ? 'Mørk' : 'Farger',
          primaryHex: primary,
          backgroundHex: bg,
          cardHex: card,
          textHex: text,
          accentHex: accent,
          darkMode: v.$2,
          buttonStyle: h % 30 == 0 ? 'pill' : 'rounded',
        ));
      }
    }

    // Natur-inspirerte (40)
    const nature = [
      ('Skog', '#2E7D32', '#E8F5E9', '#FFFFFF', '#1B5E20', '#558B2F'),
      ('Fjord', '#00897B', '#E0F2F1', '#FFFFFF', '#004D40', '#26A69A'),
      ('Hav', '#0277BD', '#E1F5FE', '#FFFFFF', '#01579B', '#0288D1'),
      ('Sand', '#8D6E63', '#EFEBE9', '#FFFFFF', '#4E342E', '#A1887F'),
      ('Lavendel', '#7E57C2', '#EDE7F6', '#FFFFFF', '#4527A0', '#9575CD'),
      ('Soloppgang', '#FF7043', '#FBE9E7', '#FFFFFF', '#BF360C', '#FF5722'),
      ('Isbre', '#4FC3F7', '#E1F5FE', '#FFFFFF', '#0277BD', '#81D4FA'),
      ('Mynte', '#26A69A', '#E0F2F1', '#FFFFFF', '#00695C', '#4DB6AC'),
      ('Bær', '#EC407A', '#FCE4EC', '#FFFFFF', '#880E4F', '#F06292'),
      ('Oliven', '#9E9D24', '#F0F4C3', '#FFFFFF', '#827717', '#C0CA33'),
    ];
    for (final n in nature) {
      for (var i = 0; i < 4; i++) {
        final dark = i == 3;
        add(SurveyThemePreset(
          id: '${n.$1.toLowerCase()}_$i',
          name: '${n.$1}${dark ? ' Mørk' : i == 0 ? '' : ' ${i + 1}'}',
          category: 'Natur',
          primaryHex: n.$2,
          backgroundHex: dark ? '#1A1A1A' : n.$3,
          cardHex: dark ? '#2D2D2D' : n.$4,
          textHex: dark ? '#ECEFF1' : n.$5,
          accentHex: n.$6,
          darkMode: dark,
          buttonStyle: i == 1 ? 'pill' : 'rounded',
        ));
      }
    }

    // Neon / moderne (30)
    const neonBases = [
      ('Neon Lime', '#76FF03', '#212121'),
      ('Electric Blue', '#2979FF', '#0A0A0A'),
      ('Hot Pink', '#FF4081', '#1A1A2E'),
      ('Cyber Purple', '#E040FB', '#0F0F23'),
      ('Amber Glow', '#FFAB00', '#1C1C1C'),
      ('Turquoise', '#00E5FF', '#0D1117'),
    ];
    for (final n in neonBases) {
      for (var i = 0; i < 5; i++) {
        add(SurveyThemePreset(
          id: 'neon_${n.$1.toLowerCase().replaceAll(' ', '_')}_$i',
          name: '${n.$1} ${i + 1}',
          category: 'Neon',
          primaryHex: n.$2,
          backgroundHex: n.$3,
          cardHex: '#1E1E2E',
          textHex: '#F8FAFC',
          accentHex: n.$2,
          darkMode: true,
          buttonStyle: i % 2 == 0 ? 'pill' : 'rounded',
        ));
      }
    }

    // Minimal / monokrom (20)
    for (var g = 0; g < 20; g++) {
      final l = 0.15 + g * 0.04;
      final bg = _hslHex(0, 0, l > 0.5 ? 0.97 : 0.08);
      final card = _hslHex(0, 0, l > 0.5 ? 1.0 : 0.14);
      final text = l > 0.5 ? '#111827' : '#F9FAFB';
      final primary = _hslHex(0, 0, l > 0.5 ? 0.25 : 0.75);
      add(SurveyThemePreset(
        id: 'mono_$g',
        name: 'Monokrom ${g + 1}',
        category: 'Minimal',
        primaryHex: primary,
        backgroundHex: bg,
        cardHex: card,
        textHex: text,
        accentHex: primary,
        darkMode: l <= 0.5,
        buttonStyle: g % 3 == 0 ? 'square' : 'rounded',
      ));
    }

    // Ekstra premium-varianter (24) → totalt 200+
    const premiumNames = [
      'Aurora', 'Glacier', 'Ember', 'Citrus', 'Plum', 'Oceanic',
      'Sage', 'Crimson', 'Slate Pro', 'Cloud', 'Espresso', 'Mist',
    ];
    for (var i = 0; i < premiumNames.length; i++) {
      final h = (i * 27) % 360;
      add(SurveyThemePreset(
        id: 'premium_$i',
        name: premiumNames[i],
        category: 'Premium',
        primaryHex: _hslHex(h.toDouble(), 0.55, 0.45),
        backgroundHex: _hslHex(h.toDouble(), 0.12, 0.96),
        cardHex: '#FFFFFF',
        textHex: '#111827',
        accentHex: _hslHex((h + 40) % 360, 0.6, 0.5),
        buttonStyle: i % 2 == 0 ? 'pill' : 'rounded',
      ));
      add(SurveyThemePreset(
        id: 'premium_dark_$i',
        name: '${premiumNames[i]} Dark',
        category: 'Premium',
        primaryHex: _hslHex(h.toDouble(), 0.7, 0.65),
        backgroundHex: _hslHex(h.toDouble(), 0.2, 0.08),
        cardHex: _hslHex(h.toDouble(), 0.15, 0.14),
        textHex: '#F8FAFC',
        accentHex: _hslHex((h + 40) % 360, 0.75, 0.6),
        darkMode: true,
        buttonStyle: 'rounded',
      ));
    }

    return out;
  }

  static String _hslHex(double h, double s, double l) {
    h = h % 360;
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = l - c / 2;
    double r, g, b;
    if (h < 60) {
      r = c; g = x; b = 0;
    } else if (h < 120) {
      r = x; g = c; b = 0;
    } else if (h < 180) {
      r = 0; g = c; b = x;
    } else if (h < 240) {
      r = 0; g = x; b = c;
    } else if (h < 300) {
      r = x; g = 0; b = c;
    } else {
      r = c; g = 0; b = x;
    }
    return _hex(
      ((r + m) * 255).round().clamp(0, 255),
      ((g + m) * 255).round().clamp(0, 255),
      ((b + m) * 255).round().clamp(0, 255),
    );
  }
}
