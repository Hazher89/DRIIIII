import 'dart:math';

/// Karusell / shuffle / rotasjon.
enum HomeFeedCarouselMode {
  manual('manual', 'Manuell (sveip)'),
  rotate('rotate', 'Auto-rotasjon'),
  shuffle('shuffle', 'Shuffle'),
  weighted('weighted', 'Vektet shuffle');

  const HomeFeedCarouselMode(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static HomeFeedCarouselMode fromDb(String? raw) {
    return HomeFeedCarouselMode.values.firstWhere(
      (e) => e.dbValue == raw?.trim().toLowerCase(),
      orElse: () => HomeFeedCarouselMode.manual,
    );
  }
}

/// Portal-målgruppe for partner-innhold.
enum HomeFeedTargetPortal {
  owner('owner', 'Bil-eier'),
  driver('driver', 'Sjåfør'),
  staff('staff', 'Ansatt');

  const HomeFeedTargetPortal(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static HomeFeedTargetPortal? fromDb(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'owner':
        return HomeFeedTargetPortal.owner;
      case 'driver':
        return HomeFeedTargetPortal.driver;
      case 'staff':
        return HomeFeedTargetPortal.staff;
      default:
        return null;
    }
  }
}

/// DriftPro-temamal for tekst-only blokker.
enum HomeFeedThemePreset {
  custom('custom', 'Egendefinert'),
  maviGreen('mavi_green', 'MAVI grønn'),
  info('info', 'Info blå'),
  warning('warning', 'Advarsel'),
  danger('danger', 'Viktig rød');

  const HomeFeedThemePreset(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static HomeFeedThemePreset fromDb(String? raw) {
    return HomeFeedThemePreset.values.firstWhere(
      (e) => e.dbValue == raw?.trim().toLowerCase(),
      orElse: () => HomeFeedThemePreset.custom,
    );
  }
}

class HomeFeedLinkConfig {
  const HomeFeedLinkConfig({
    this.url = '',
    this.buttonLabel = 'Les mer',
    this.internalRoute,
    this.openExternal = false,
  });

  final String url;
  final String buttonLabel;
  final String? internalRoute;
  final bool openExternal;

  Map<String, dynamic> toJson() => {
        'url': url,
        'button_label': buttonLabel,
        if (internalRoute != null) 'internal_route': internalRoute,
        'open_external': openExternal,
      };

  factory HomeFeedLinkConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HomeFeedLinkConfig();
    return HomeFeedLinkConfig(
      url: (json['url'] as String?)?.trim() ?? '',
      buttonLabel: (json['button_label'] as String?)?.trim().isNotEmpty == true
          ? (json['button_label'] as String).trim()
          : 'Les mer',
      internalRoute: (json['internal_route'] as String?)?.trim(),
      openExternal: json['open_external'] == true,
    );
  }

  HomeFeedLinkConfig copyWith({
    String? url,
    String? buttonLabel,
    String? internalRoute,
    bool? openExternal,
  }) {
    return HomeFeedLinkConfig(
      url: url ?? this.url,
      buttonLabel: buttonLabel ?? this.buttonLabel,
      internalRoute: internalRoute ?? this.internalRoute,
      openExternal: openExternal ?? this.openExternal,
    );
  }
}

class HomeFeedYoutubeConfig {
  const HomeFeedYoutubeConfig({
    this.videoUrl = '',
    this.videoId,
    this.autoplay = true,
    this.muted = true,
  });

  final String videoUrl;
  final String? videoId;
  final bool autoplay;
  final bool muted;

  String? get resolvedVideoId => videoId ?? extractYoutubeId(videoUrl);

  String? get thumbnailUrl {
    final id = resolvedVideoId;
    if (id == null || id.isEmpty) return null;
    return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
  }

  String? get embedUrl {
    final id = resolvedVideoId;
    if (id == null || id.isEmpty) return null;
    final params = <String>[
      if (autoplay) 'autoplay=1',
      if (muted) 'mute=1',
      'rel=0',
    ];
    final q = params.isEmpty ? '' : '?${params.join('&')}';
    return 'https://www.youtube.com/embed/$id$q';
  }

  static String? extractYoutubeId(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    if (uri == null) return null;
    if (uri.host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    if (uri.host.contains('youtube.com')) {
      final v = uri.queryParameters['v'];
      if (v != null && v.isNotEmpty) return v;
      final segments = uri.pathSegments;
      if (segments.length >= 2 &&
          (segments[0] == 'embed' || segments[0] == 'shorts')) {
        return segments[1];
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'video_url': videoUrl,
        if (videoId != null) 'video_id': videoId,
        'autoplay': autoplay,
        'muted': muted,
      };

  factory HomeFeedYoutubeConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HomeFeedYoutubeConfig();
    return HomeFeedYoutubeConfig(
      videoUrl: (json['video_url'] as String?)?.trim() ??
          (json['youtube_url'] as String?)?.trim() ??
          '',
      videoId: (json['video_id'] as String?)?.trim(),
      autoplay: json['autoplay'] == true,
      muted: json['muted'] != false,
    );
  }

  HomeFeedYoutubeConfig copyWith({
    String? videoUrl,
    String? videoId,
    bool? autoplay,
    bool? muted,
  }) {
    return HomeFeedYoutubeConfig(
      videoUrl: videoUrl ?? this.videoUrl,
      videoId: videoId ?? this.videoId,
      autoplay: autoplay ?? this.autoplay,
      muted: muted ?? this.muted,
    );
  }
}

class HomeFeedTextBlockConfig {
  const HomeFeedTextBlockConfig({
    this.body = '',
    this.backgroundColorHex = '#1B5E20',
    this.backgroundOpacity = 0.12,
    this.theme = HomeFeedThemePreset.custom,
    this.maxLines,
  });

  final String body;
  final String backgroundColorHex;
  final double backgroundOpacity;
  final HomeFeedThemePreset theme;
  final int? maxLines;

  Map<String, dynamic> toJson() => {
        'body': body,
        'background_color': backgroundColorHex,
        'background_opacity': backgroundOpacity,
        'theme': theme.dbValue,
        if (maxLines != null) 'max_lines': maxLines,
      };

  factory HomeFeedTextBlockConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HomeFeedTextBlockConfig();
    return HomeFeedTextBlockConfig(
      body: (json['body'] as String?) ?? '',
      backgroundColorHex:
          (json['background_color'] as String?)?.trim().isNotEmpty == true
              ? (json['background_color'] as String).trim()
              : '#1B5E20',
      backgroundOpacity:
          (json['background_opacity'] as num?)?.toDouble().clamp(0, 1) ?? 0.12,
      theme: HomeFeedThemePreset.fromDb(json['theme'] as String?),
      maxLines: (json['max_lines'] as num?)?.toInt(),
    );
  }

  HomeFeedTextBlockConfig copyWith({
    String? body,
    String? backgroundColorHex,
    double? backgroundOpacity,
    HomeFeedThemePreset? theme,
    int? maxLines,
  }) {
    return HomeFeedTextBlockConfig(
      body: body ?? this.body,
      backgroundColorHex: backgroundColorHex ?? this.backgroundColorHex,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      theme: theme ?? this.theme,
      maxLines: maxLines ?? this.maxLines,
    );
  }
}

class HomeFeedSpacerConfig {
  const HomeFeedSpacerConfig({this.heightApp = 24, this.heightWeb = 32});

  final double heightApp;
  final double heightWeb;

  Map<String, dynamic> toJson() => {
        'height_app': heightApp,
        'height_web': heightWeb,
      };

  factory HomeFeedSpacerConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HomeFeedSpacerConfig();
    return HomeFeedSpacerConfig(
      heightApp: (json['height_app'] as num?)?.toDouble() ?? 24,
      heightWeb: (json['height_web'] as num?)?.toDouble() ?? 32,
    );
  }
}

class HomeFeedCarouselConfig {
  const HomeFeedCarouselConfig({
    this.mode = HomeFeedCarouselMode.manual,
    this.intervalMs = 8000,
    this.slideIds = const [],
    this.weights = const {},
    this.pauseOnHover = true,
  });

  final HomeFeedCarouselMode mode;
  final int intervalMs;
  final List<String> slideIds;
  final Map<String, int> weights;
  final bool pauseOnHover;

  Map<String, dynamic> toJson() => {
        'mode': mode.dbValue,
        'interval_ms': intervalMs,
        'slide_ids': slideIds,
        if (weights.isNotEmpty) 'weights': weights,
        'pause_on_hover': pauseOnHover,
      };

  factory HomeFeedCarouselConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HomeFeedCarouselConfig();
    final rawIds = json['slide_ids'];
    final ids = rawIds is List
        ? rawIds.map((e) => e.toString()).toList()
        : <String>[];
    final rawWeights = json['weights'];
    final w = <String, int>{};
    if (rawWeights is Map) {
      rawWeights.forEach((k, v) {
        if (v is num) w[k.toString()] = v.toInt();
      });
    }
    return HomeFeedCarouselConfig(
      mode: HomeFeedCarouselMode.fromDb(json['mode'] as String?),
      intervalMs: (json['interval_ms'] as num?)?.toInt().clamp(2000, 120000) ??
          8000,
      slideIds: ids,
      weights: w,
      pauseOnHover: json['pause_on_hover'] != false,
    );
  }

  List<String> shuffledSlideIds({Random? random}) {
    final rng = random ?? Random();
    if (mode == HomeFeedCarouselMode.shuffle) {
      final copy = List<String>.from(slideIds);
      copy.shuffle(rng);
      return copy;
    }
    if (mode == HomeFeedCarouselMode.weighted && weights.isNotEmpty) {
      final pool = <String>[];
      for (final id in slideIds) {
        final w = weights[id] ?? 1;
        for (var i = 0; i < w.clamp(1, 10); i++) {
          pool.add(id);
        }
      }
      pool.shuffle(rng);
      return pool.toSet().toList();
    }
    return slideIds;
  }
}

class HomeFeedScheduleConfig {
  const HomeFeedScheduleConfig({this.start, this.end});

  final DateTime? start;
  final DateTime? end;

  bool get isScheduled => start != null || end != null;

  bool isActiveAt(DateTime now) {
    if (start != null && now.isBefore(start!)) return false;
    if (end != null && now.isAfter(end!)) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
        if (start != null) 'start': start!.toUtc().toIso8601String(),
        if (end != null) 'end': end!.toUtc().toIso8601String(),
      };

  factory HomeFeedScheduleConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HomeFeedScheduleConfig();
    return HomeFeedScheduleConfig(
      start: _parse(json['start']),
      end: _parse(json['end']),
    );
  }

  static DateTime? _parse(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }
}

class HomeFeedBadgeConfig {
  const HomeFeedBadgeConfig({
    this.label,
    this.showCountdown = false,
    this.countdownTarget,
  });

  final String? label;
  final bool showCountdown;
  final DateTime? countdownTarget;

  Map<String, dynamic> toJson() => {
        if (label != null) 'label': label,
        'show_countdown': showCountdown,
        if (countdownTarget != null)
          'countdown_target': countdownTarget!.toUtc().toIso8601String(),
      };

  factory HomeFeedBadgeConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HomeFeedBadgeConfig();
    return HomeFeedBadgeConfig(
      label: (json['label'] as String?)?.trim(),
      showCountdown: json['show_countdown'] == true,
      countdownTarget: json['countdown_target'] != null
          ? DateTime.tryParse(json['countdown_target'].toString())
          : null,
    );
  }
}

/// Samlet content_json for alle blokktyper.
class HomeFeedContentConfig {
  const HomeFeedContentConfig({
    this.youtube = const HomeFeedYoutubeConfig(),
    this.link = const HomeFeedLinkConfig(),
    this.textBlock = const HomeFeedTextBlockConfig(),
    this.spacer = const HomeFeedSpacerConfig(),
    this.carousel = const HomeFeedCarouselConfig(),
    this.badge = const HomeFeedBadgeConfig(),
    this.altText,
    this.feedbackEnabled = false,
  });

  final HomeFeedYoutubeConfig youtube;
  final HomeFeedLinkConfig link;
  final HomeFeedTextBlockConfig textBlock;
  final HomeFeedSpacerConfig spacer;
  final HomeFeedCarouselConfig carousel;
  final HomeFeedBadgeConfig badge;
  final String? altText;
  final bool feedbackEnabled;

  static const empty = HomeFeedContentConfig();

  Map<String, dynamic> toJson() => {
        ...youtube.toJson(),
        ...link.toJson(),
        ...textBlock.toJson(),
        ...spacer.toJson(),
        ...carousel.toJson(),
        ...badge.toJson(),
        if (altText != null) 'alt_text': altText,
        'feedback_enabled': feedbackEnabled,
      };

  factory HomeFeedContentConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return empty;
    return HomeFeedContentConfig(
      youtube: HomeFeedYoutubeConfig.fromJson(json),
      link: HomeFeedLinkConfig.fromJson(json),
      textBlock: HomeFeedTextBlockConfig.fromJson(json),
      spacer: HomeFeedSpacerConfig.fromJson(json),
      carousel: HomeFeedCarouselConfig.fromJson(json),
      badge: HomeFeedBadgeConfig.fromJson(json),
      altText: (json['alt_text'] as String?)?.trim(),
      feedbackEnabled: json['feedback_enabled'] == true,
    );
  }

  HomeFeedContentConfig copyWith({
    HomeFeedYoutubeConfig? youtube,
    HomeFeedLinkConfig? link,
    HomeFeedTextBlockConfig? textBlock,
    HomeFeedSpacerConfig? spacer,
    HomeFeedCarouselConfig? carousel,
    HomeFeedBadgeConfig? badge,
    String? altText,
    bool? feedbackEnabled,
  }) {
    return HomeFeedContentConfig(
      youtube: youtube ?? this.youtube,
      link: link ?? this.link,
      textBlock: textBlock ?? this.textBlock,
      spacer: spacer ?? this.spacer,
      carousel: carousel ?? this.carousel,
      badge: badge ?? this.badge,
      altText: altText ?? this.altText,
      feedbackEnabled: feedbackEnabled ?? this.feedbackEnabled,
    );
  }
}
