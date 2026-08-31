import 'package:flutter/material.dart';

/// Forhåndsvisning: auto = faktisk plattform, ellers simulert app eller web.
enum HomeFeedPreviewPlatform {
  auto,
  app,
  web,
}

enum HomeFeedSizePreset {
  compact('compact', 'Kompakt'),
  medium('medium', 'Medium'),
  large('large', 'Stor'),
  hero('hero', 'Hero'),
  full('full', 'Full bredde');

  const HomeFeedSizePreset(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static HomeFeedSizePreset fromDb(String? raw) {
    return HomeFeedSizePreset.values.firstWhere(
      (e) => e.dbValue == raw?.trim().toLowerCase(),
      orElse: () => HomeFeedSizePreset.medium,
    );
  }
}

enum HomeFeedTextSize {
  xs('xs', 11),
  sm('sm', 13),
  md('md', 16),
  lg('lg', 20),
  xl('xl', 26),
  display('display', 34);

  const HomeFeedTextSize(this.dbValue, this.fontSize);
  final String dbValue;
  final double fontSize;

  static HomeFeedTextSize fromDb(String? raw) {
    return HomeFeedTextSize.values.firstWhere(
      (e) => e.dbValue == raw?.trim().toLowerCase(),
      orElse: () => HomeFeedTextSize.md,
    );
  }
}

enum HomeFeedTextPosition {
  below('below', 'Under media'),
  overlayTop('overlay_top', 'Over media — topp'),
  overlayCenter('overlay_center', 'Over media — midt'),
  overlayBottom('overlay_bottom', 'Over media — bunn'),
  hidden('hidden', 'Skjul tekst');

  const HomeFeedTextPosition(this.dbValue, this.label);
  final String dbValue;
  final String label;

  bool get isOverlay =>
      this == overlayTop || this == overlayCenter || this == overlayBottom;

  static HomeFeedTextPosition fromDb(String? raw) {
    return HomeFeedTextPosition.values.firstWhere(
      (e) => e.dbValue == raw?.trim().toLowerCase(),
      orElse: () => HomeFeedTextPosition.below,
    );
  }
}

enum HomeFeedMediaFit {
  cover('cover', 'Fyll (cover)'),
  contain('contain', 'Tilpass (contain)');

  const HomeFeedMediaFit(this.dbValue, this.label);
  final String dbValue;
  final String label;

  BoxFit get boxFit =>
      this == HomeFeedMediaFit.contain ? BoxFit.contain : BoxFit.cover;

  static HomeFeedMediaFit fromDb(String? raw) {
    return HomeFeedMediaFit.values.firstWhere(
      (e) => e.dbValue == raw?.trim().toLowerCase(),
      orElse: () => HomeFeedMediaFit.cover,
    );
  }
}

class HomeFeedTextStyleConfig {
  const HomeFeedTextStyleConfig({
    this.size = HomeFeedTextSize.md,
    this.colorHex = '#FFFFFF',
    this.opacity = 1,
    this.bold = true,
  });

  final HomeFeedTextSize size;
  final String colorHex;
  final double opacity;
  final bool bold;

  Color get color => _parseHex(colorHex, opacity);

  TextStyle toTextStyle({Color? fallback}) {
    return TextStyle(
      fontSize: size.fontSize,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: color.alpha == 0 ? fallback : color,
      height: 1.25,
    );
  }

  Map<String, dynamic> toJson() => {
        'size': size.dbValue,
        'color': colorHex,
        'opacity': opacity,
        'bold': bold,
      };

  factory HomeFeedTextStyleConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HomeFeedTextStyleConfig();
    return HomeFeedTextStyleConfig(
      size: HomeFeedTextSize.fromDb(json['size'] as String?),
      colorHex: (json['color'] as String?)?.trim().isNotEmpty == true
          ? (json['color'] as String).trim()
          : '#FFFFFF',
      opacity: (json['opacity'] as num?)?.toDouble().clamp(0, 1) ?? 1,
      bold: json['bold'] != false,
    );
  }

  HomeFeedTextStyleConfig copyWith({
    HomeFeedTextSize? size,
    String? colorHex,
    double? opacity,
    bool? bold,
  }) {
    return HomeFeedTextStyleConfig(
      size: size ?? this.size,
      colorHex: colorHex ?? this.colorHex,
      opacity: opacity ?? this.opacity,
      bold: bold ?? this.bold,
    );
  }
}

class HomeFeedLayoutConfig {
  const HomeFeedLayoutConfig({
    this.sizePreset = HomeFeedSizePreset.medium,
    this.customHeightApp,
    this.customHeightWeb,
    this.mediaFit = HomeFeedMediaFit.cover,
    this.borderRadius = 16,
    this.edgeToEdge = false,
    this.fullPageHero = false,
    this.textPosition = HomeFeedTextPosition.below,
    this.textAlign = TextAlign.left,
    this.overlayColorHex = '#000000',
    this.overlayOpacity = 0.45,
    this.titleStyle = const HomeFeedTextStyleConfig(
      size: HomeFeedTextSize.lg,
      colorHex: '#FFFFFF',
      bold: true,
    ),
    this.captionStyle = const HomeFeedTextStyleConfig(
      size: HomeFeedTextSize.sm,
      colorHex: '#E8E8E8',
      bold: false,
    ),
  });

  final HomeFeedSizePreset sizePreset;
  final double? customHeightApp;
  final double? customHeightWeb;
  final HomeFeedMediaFit mediaFit;
  final double borderRadius;
  final bool edgeToEdge;
  final bool fullPageHero;
  final HomeFeedTextPosition textPosition;
  final TextAlign textAlign;
  final String overlayColorHex;
  final double overlayOpacity;
  final HomeFeedTextStyleConfig titleStyle;
  final HomeFeedTextStyleConfig captionStyle;

  static const defaults = HomeFeedLayoutConfig();

  double resolveHeight({
    required bool isWeb,
    bool compactPreview = false,
  }) {
    if (fullPageHero) {
      return isWeb ? 520 : 420;
    }
    if (!isWeb && customHeightApp != null) {
      return customHeightApp!.clamp(80, 720);
    }
    if (isWeb && customHeightWeb != null) {
      return customHeightWeb!.clamp(80, 720);
    }
    switch (sizePreset) {
      case HomeFeedSizePreset.compact:
        return compactPreview ? 120 : (isWeb ? 160 : 140);
      case HomeFeedSizePreset.medium:
        return compactPreview ? 180 : (isWeb ? 260 : 220);
      case HomeFeedSizePreset.large:
        return compactPreview ? 240 : (isWeb ? 360 : 300);
      case HomeFeedSizePreset.hero:
        return compactPreview ? 300 : (isWeb ? 480 : 380);
      case HomeFeedSizePreset.full:
        return compactPreview ? 360 : (isWeb ? 560 : 440);
    }
  }

  EdgeInsets resolvePadding({required bool isWeb}) {
    if (edgeToEdge || fullPageHero) {
      return EdgeInsets.symmetric(vertical: isWeb ? 12 : 8);
    }
    return EdgeInsets.fromLTRB(16, isWeb ? 12 : 8, 16, 8);
  }

  double resolveTotalHeight({
    required bool isWeb,
    required bool hasTitle,
    required bool hasCaption,
    bool compactPreview = false,
  }) {
    var h = resolveHeight(isWeb: isWeb, compactPreview: compactPreview);
    if (textPosition == HomeFeedTextPosition.below &&
        (hasTitle || hasCaption)) {
      if (hasTitle) h += titleStyle.size.fontSize * 2.6;
      if (hasCaption) h += captionStyle.size.fontSize * 2.4;
      h += 24;
    }
    return h;
  }

  Color get overlayColor => _parseHex(overlayColorHex, overlayOpacity);

  Map<String, dynamic> toJson() => {
        'size_preset': sizePreset.dbValue,
        if (customHeightApp != null) 'height_app': customHeightApp,
        if (customHeightWeb != null) 'height_web': customHeightWeb,
        'media_fit': mediaFit.dbValue,
        'border_radius': borderRadius,
        'edge_to_edge': edgeToEdge,
        'full_page_hero': fullPageHero,
        'text_position': textPosition.dbValue,
        'text_align': _textAlignToDb(textAlign),
        'overlay_color': overlayColorHex,
        'overlay_opacity': overlayOpacity,
        'title_style': titleStyle.toJson(),
        'caption_style': captionStyle.toJson(),
      };

  factory HomeFeedLayoutConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return defaults;
    return HomeFeedLayoutConfig(
      sizePreset: HomeFeedSizePreset.fromDb(json['size_preset'] as String?),
      customHeightApp: (json['height_app'] as num?)?.toDouble(),
      customHeightWeb: (json['height_web'] as num?)?.toDouble(),
      mediaFit: HomeFeedMediaFit.fromDb(json['media_fit'] as String?),
      borderRadius: (json['border_radius'] as num?)?.toDouble() ?? 16,
      edgeToEdge: json['edge_to_edge'] == true,
      fullPageHero: json['full_page_hero'] == true,
      textPosition:
          HomeFeedTextPosition.fromDb(json['text_position'] as String?),
      textAlign: _textAlignFromDb(json['text_align'] as String?),
      overlayColorHex: (json['overlay_color'] as String?)?.trim().isNotEmpty ==
              true
          ? (json['overlay_color'] as String).trim()
          : '#000000',
      overlayOpacity:
          (json['overlay_opacity'] as num?)?.toDouble().clamp(0, 1) ?? 0.45,
      titleStyle: HomeFeedTextStyleConfig.fromJson(
        json['title_style'] as Map<String, dynamic>?,
      ),
      captionStyle: HomeFeedTextStyleConfig.fromJson(
        json['caption_style'] as Map<String, dynamic>?,
      ),
    );
  }

  HomeFeedLayoutConfig copyWith({
    HomeFeedSizePreset? sizePreset,
    double? customHeightApp,
    double? customHeightWeb,
    bool clearCustomHeightApp = false,
    bool clearCustomHeightWeb = false,
    HomeFeedMediaFit? mediaFit,
    double? borderRadius,
    bool? edgeToEdge,
    bool? fullPageHero,
    HomeFeedTextPosition? textPosition,
    TextAlign? textAlign,
    String? overlayColorHex,
    double? overlayOpacity,
    HomeFeedTextStyleConfig? titleStyle,
    HomeFeedTextStyleConfig? captionStyle,
  }) {
    return HomeFeedLayoutConfig(
      sizePreset: sizePreset ?? this.sizePreset,
      customHeightApp:
          clearCustomHeightApp ? null : (customHeightApp ?? this.customHeightApp),
      customHeightWeb:
          clearCustomHeightWeb ? null : (customHeightWeb ?? this.customHeightWeb),
      mediaFit: mediaFit ?? this.mediaFit,
      borderRadius: borderRadius ?? this.borderRadius,
      edgeToEdge: edgeToEdge ?? this.edgeToEdge,
      fullPageHero: fullPageHero ?? this.fullPageHero,
      textPosition: textPosition ?? this.textPosition,
      textAlign: textAlign ?? this.textAlign,
      overlayColorHex: overlayColorHex ?? this.overlayColorHex,
      overlayOpacity: overlayOpacity ?? this.overlayOpacity,
      titleStyle: titleStyle ?? this.titleStyle,
      captionStyle: captionStyle ?? this.captionStyle,
    );
  }

  static String _textAlignToDb(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return 'center';
      case TextAlign.right:
      case TextAlign.end:
        return 'right';
      default:
        return 'left';
    }
  }

  static TextAlign _textAlignFromDb(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.left;
    }
  }
}

Color _parseHex(String hex, double opacity) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) {
    final v = int.tryParse(h, radix: 16);
    if (v != null) {
      return Color(v | 0xFF000000).withValues(alpha: opacity.clamp(0, 1));
    }
  }
  if (h.length == 8) {
    final v = int.tryParse(h, radix: 16);
    if (v != null) {
      return Color(v).withValues(alpha: opacity.clamp(0, 1));
    }
  }
  return Colors.white.withValues(alpha: opacity.clamp(0, 1));
}

String colorToHex(Color color, {bool includeAlpha = false}) {
  if (includeAlpha) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  }
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}
