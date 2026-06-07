import '../../../models/survey/survey_advanced.dart';

enum SurveyVisualStyle {
  classic,
  glass,
  gradient,
  minimal,
  bold,
  neon,
}

extension SurveyVisualStyleLabel on SurveyVisualStyle {
  String get label => switch (this) {
        SurveyVisualStyle.classic => 'Klassisk',
        SurveyVisualStyle.glass => 'Glass',
        SurveyVisualStyle.gradient => 'Gradient',
        SurveyVisualStyle.minimal => 'Minimal',
        SurveyVisualStyle.bold => 'Bold',
        SurveyVisualStyle.neon => 'Neon',
      };
}

/// Ett komplett respondent-tema — bakgrunn, kort, knapper, tekst og visuell stil.
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
    this.visualStyle = SurveyVisualStyle.classic,
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
  final SurveyVisualStyle visualStyle;

  String get visualStyleLabel => visualStyle.label;

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

/// Kuraterte premium-tema — inspirert av Typeform, SurveyMonkey, Linear, Stripe m.fl.
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

  static List<SurveyThemePreset> _buildAll() {
    final out = <SurveyThemePreset>[];
    void c(
      String id,
      String name,
      String category,
      String primary,
      String bg,
      String card,
      String text,
      String accent, {
      bool dark = false,
      String button = 'rounded',
      SurveyVisualStyle style = SurveyVisualStyle.classic,
    }) {
      out.add(SurveyThemePreset(
        id: id,
        name: name,
        category: category,
        primaryHex: primary,
        backgroundHex: bg,
        cardHex: card,
        textHex: text,
        accentHex: accent,
        darkMode: dark,
        buttonStyle: button,
        visualStyle: style,
      ));
    }

    // —— Typeform-inspirert (myke, inviterende) ——
    c('typeform-coral', 'Typeform Coral', 'Typeform', '#EE6C4D', '#FFF8F6', '#FFFFFF', '#2D3142', '#F4978E', style: SurveyVisualStyle.gradient, button: 'pill');
    c('typeform-indigo', 'Typeform Indigo', 'Typeform', '#3D5AFE', '#F5F7FF', '#FFFFFF', '#1A237E', '#536DFE', style: SurveyVisualStyle.gradient, button: 'pill');
    c('typeform-mint', 'Typeform Mint', 'Typeform', '#00B894', '#F0FDF9', '#FFFFFF', '#0F172A', '#55EFC4', style: SurveyVisualStyle.minimal, button: 'pill');
    c('typeform-slate', 'Typeform Slate', 'Typeform', '#475569', '#F8FAFC', '#FFFFFF', '#0F172A', '#64748B', style: SurveyVisualStyle.minimal);
    c('typeform-dark', 'Typeform Dark', 'Typeform', '#818CF8', '#0F172A', '#1E293B', '#F1F5F9', '#A5B4FC', dark: true, style: SurveyVisualStyle.glass, button: 'pill');

    // —— SurveyMonkey Professional ——
    c('sm-pro-green', 'SurveyMonkey Pro', 'SurveyMonkey', '#00BF6F', '#F0FDF4', '#FFFFFF', '#14532D', '#059669', style: SurveyVisualStyle.classic);
    c('sm-enterprise', 'Enterprise Blue', 'SurveyMonkey', '#0052CC', '#EFF6FF', '#FFFFFF', '#1E3A5F', '#2684FF', style: SurveyVisualStyle.bold);
    c('sm-warm', 'Warm Feedback', 'SurveyMonkey', '#E87722', '#FFF7ED', '#FFFFFF', '#7C2D12', '#FB923C', style: SurveyVisualStyle.gradient);
    c('sm-trust', 'Trust Teal', 'SurveyMonkey', '#0D9488', '#F0FDFA', '#FFFFFF', '#134E4A', '#2DD4BF', style: SurveyVisualStyle.classic);

    // —— Linear / Stripe SaaS ——
    c('linear-purple', 'Linear Purple', 'SaaS Premium', '#5E6AD2', '#FAFAFA', '#FFFFFF', '#171717', '#8B5CF6', style: SurveyVisualStyle.minimal);
    c('stripe-blurple', 'Stripe Blurple', 'SaaS Premium', '#635BFF', '#F6F9FC', '#FFFFFF', '#0A2540', '#0073E6', style: SurveyVisualStyle.minimal, button: 'pill');
    c('notion-warm', 'Notion Warm', 'SaaS Premium', '#37352F', '#FBFBFA', '#FFFFFF', '#37352F', '#787774', style: SurveyVisualStyle.minimal);
    c('vercel-mono', 'Vercel Mono', 'SaaS Premium', '#000000', '#FAFAFA', '#FFFFFF', '#171717', '#666666', style: SurveyVisualStyle.minimal, button: 'square');
    c('vercel-dark', 'Vercel Dark', 'SaaS Premium', '#FFFFFF', '#000000', '#111111', '#EDEDED', '#888888', dark: true, style: SurveyVisualStyle.minimal, button: 'square');

    // —— DriftPro signatur ——
    c('driftpro-green', 'DriftPro Grønn', 'Signatur', '#1B5E20', '#F7F9F8', '#FFFFFF', '#0F172A', '#2E7D32', style: SurveyVisualStyle.classic);
    c('driftpro-nordic', 'Nordisk Lys', 'Signatur', '#37474F', '#ECEFF1', '#FFFFFF', '#263238', '#78909C', style: SurveyVisualStyle.minimal);
    c('driftpro-forest', 'Skog Premium', 'Signatur', '#2E7D32', '#E8F5E9', '#FFFFFF', '#1B5E20', '#66BB6A', style: SurveyVisualStyle.gradient);

    // —— Glass & gradient (moderne) ——
    c('aurora-glass', 'Aurora Glass', 'Glass', '#6366F1', '#EEF2FF', '#FFFFFF', '#312E81', '#818CF8', style: SurveyVisualStyle.glass, button: 'pill');
    c('sunset-glass', 'Sunset Glass', 'Glass', '#F97316', '#FFF7ED', '#FFFFFF', '#9A3412', '#FB923C', style: SurveyVisualStyle.glass, button: 'pill');
    c('ocean-glass', 'Ocean Glass', 'Glass', '#0EA5E9', '#F0F9FF', '#FFFFFF', '#0C4A6E', '#38BDF8', style: SurveyVisualStyle.glass);
    c('midnight-glass', 'Midnight Glass', 'Glass', '#60A5FA', '#0D1117', '#161B22', '#E6EDF3', '#3B82F6', dark: true, style: SurveyVisualStyle.glass, button: 'pill');
    c('rose-glass', 'Rose Glass', 'Glass', '#EC4899', '#FDF2F8', '#FFFFFF', '#831843', '#F472B6', style: SurveyVisualStyle.glass, button: 'pill');

    // —— Business & corporate ——
    c('mckinsey-blue', 'Consulting Blue', 'Business', '#003366', '#F0F4F8', '#FFFFFF', '#1A202C', '#0066CC', style: SurveyVisualStyle.bold);
    c('gold-executive', 'Executive Gold', 'Business', '#B8860B', '#FFFBEB', '#FFFFFF', '#422006', '#D97706', style: SurveyVisualStyle.gradient);
    c('slate-corporate', 'Corporate Slate', 'Business', '#334155', '#F1F5F9', '#FFFFFF', '#0F172A', '#64748B', style: SurveyVisualStyle.minimal);
    c('navy-trust', 'Navy Trust', 'Business', '#1E3A5F', '#EFF6FF', '#FFFFFF', '#0F172A', '#3B82F6', style: SurveyVisualStyle.classic);

    // —— Healthcare & offentlig ——
    c('health-teal', 'Helse Teal', 'Helse & Offentlig', '#0D9488', '#F0FDFA', '#FFFFFF', '#134E4A', '#5EEAD4', style: SurveyVisualStyle.classic);
    c('health-calm', 'Calm Blue', 'Helse & Offentlig', '#0284C7', '#F0F9FF', '#FFFFFF', '#0C4A6E', '#38BDF8', style: SurveyVisualStyle.minimal);
    c('gov-nordic', 'Nordisk Offentlig', 'Helse & Offentlig', '#1E40AF', '#EFF6FF', '#FFFFFF', '#1E3A8A', '#60A5FA', style: SurveyVisualStyle.bold);

    // —— Kreativ & events ——
    c('creative-violet', 'Creative Violet', 'Kreativ', '#7C3AED', '#F5F3FF', '#FFFFFF', '#4C1D95', '#A78BFA', style: SurveyVisualStyle.gradient, button: 'pill');
    c('creative-coral', 'Creative Coral', 'Kreativ', '#FF6B6B', '#FFF5F5', '#FFFFFF', '#991B1B', '#FCA5A5', style: SurveyVisualStyle.gradient, button: 'pill');
    c('festival-neon', 'Festival Neon', 'Kreativ', '#A855F7', '#0F0A1A', '#1A1225', '#F3E8FF', '#C084FC', dark: true, style: SurveyVisualStyle.neon, button: 'pill');
    c('studio-amber', 'Studio Amber', 'Kreativ', '#F59E0B', '#FFFBEB', '#FFFFFF', '#78350F', '#FBBF24', style: SurveyVisualStyle.bold);

    // —— Utdanning ——
    c('edu-blue', 'Campus Blue', 'Utdanning', '#2563EB', '#EFF6FF', '#FFFFFF', '#1E40AF', '#60A5FA', style: SurveyVisualStyle.classic);
    c('edu-sage', 'Campus Sage', 'Utdanning', '#65A30D', '#F7FEE7', '#FFFFFF', '#365314', '#A3E635', style: SurveyVisualStyle.minimal);

    // —— Mørk premium ——
    c('dark-linear', 'Dark Linear', 'Mørk Premium', '#818CF8', '#09090B', '#18181B', '#FAFAFA', '#6366F1', dark: true, style: SurveyVisualStyle.glass, button: 'pill');
    c('dark-emerald', 'Dark Emerald', 'Mørk Premium', '#34D399', '#022C22', '#064E3B', '#ECFDF5', '#10B981', dark: true, style: SurveyVisualStyle.glass);
    c('dark-rose', 'Dark Rose', 'Mørk Premium', '#FB7185', '#1A0A0F', '#2D1520', '#FFF1F2', '#F43F5E', dark: true, style: SurveyVisualStyle.glass, button: 'pill');
    c('dark-ocean', 'Dark Ocean', 'Mørk Premium', '#22D3EE', '#042F2E', '#0F3D3E', '#ECFEFF', '#06B6D4', dark: true, style: SurveyVisualStyle.neon);

    // —— Natur (håndplukket) ——
    c('nature-forest', 'Skog', 'Natur', '#2E7D32', '#E8F5E9', '#FFFFFF', '#1B5E20', '#81C784', style: SurveyVisualStyle.gradient);
    c('nature-fjord', 'Fjord', 'Natur', '#00897B', '#E0F2F1', '#FFFFFF', '#004D40', '#4DB6AC', style: SurveyVisualStyle.classic);
    c('nature-arctic', 'Arktisk', 'Natur', '#0288D1', '#E1F5FE', '#FFFFFF', '#01579B', '#4FC3F7', style: SurveyVisualStyle.minimal);
    c('nature-sand', 'Sand & Stein', 'Natur', '#8D6E63', '#EFEBE9', '#FFFFFF', '#4E342E', '#BCAAA4', style: SurveyVisualStyle.minimal);
    c('nature-lavender', 'Lavendel', 'Natur', '#7E57C2', '#EDE7F6', '#FFFFFF', '#4527A0', '#B39DDB', style: SurveyVisualStyle.gradient, button: 'pill');

    // —— Neon (kontrollert, ikke generisk) ——
    c('neon-cyber', 'Cyber Blue', 'Neon', '#00D4FF', '#0A0E17', '#12182B', '#E0F7FF', '#0099CC', dark: true, style: SurveyVisualStyle.neon, button: 'pill');
    c('neon-magenta', 'Neon Magenta', 'Neon', '#FF006E', '#120008', '#1F0012', '#FFE0F0', '#FF4D94', dark: true, style: SurveyVisualStyle.neon, button: 'pill');
    c('neon-lime', 'Neon Lime', 'Neon', '#CCFF00', '#0A0F00', '#141F00', '#F0FFD6', '#99CC00', dark: true, style: SurveyVisualStyle.neon, button: 'pill');

    // —— Minimal monokrom ——
    c('mono-light', 'Ren Hvit', 'Minimal', '#18181B', '#FFFFFF', '#FFFFFF', '#18181B', '#71717A', style: SurveyVisualStyle.minimal);
    c('mono-soft', 'Soft Gray', 'Minimal', '#52525B', '#FAFAFA', '#FFFFFF', '#27272A', '#A1A1AA', style: SurveyVisualStyle.minimal);
    c('mono-dark', 'Ren Mørk', 'Minimal', '#FAFAFA', '#09090B', '#18181B', '#FAFAFA', '#A1A1AA', dark: true, style: SurveyVisualStyle.minimal, button: 'square');

    // —— Sesong & kampanje ——
    c('season-spring', 'Vårgrønn', 'Sesong', '#16A34A', '#F0FDF4', '#FFFFFF', '#14532D', '#4ADE80', style: SurveyVisualStyle.gradient, button: 'pill');
    c('season-summer', 'Sommergul', 'Sesong', '#CA8A04', '#FEFCE8', '#FFFFFF', '#713F12', '#FACC15', style: SurveyVisualStyle.gradient);
    c('season-autumn', 'Høst', 'Sesong', '#EA580C', '#FFF7ED', '#FFFFFF', '#7C2D12', '#FB923C', style: SurveyVisualStyle.gradient);
    c('season-winter', 'Vinter', 'Sesong', '#0369A1', '#F0F9FF', '#FFFFFF', '#0C4A6E', '#7DD3FC', style: SurveyVisualStyle.minimal);

    return out;
  }
}
