/// Innstillinger for hjem/infoskjerm, styrt av admin.
/// Personvern: [revealNamesOnInfoscreen] bør være av på delte skjermer.
class KioskSettings {
  final bool infoscreenLayoutEnabled;
  final bool showClock;
  final bool showPersonalGreeting;
  final bool showCustomMessage;
  final String customMessageTitle;
  final String customMessageBody;
  final bool showAbsenceAggregate;
  final bool showTicketStats;
  final bool showHmsHighlights;
  final bool showAttendanceSummary;
  final bool showQuickActions;
  final bool showActivityFeed;
  final bool showMiniStatsRow;
  final bool revealNamesOnInfoscreen;
  final bool showLiveTeamBoard;
  final bool showTidsbankenPresence;

  const KioskSettings({
    this.infoscreenLayoutEnabled = false,
    this.showClock = true,
    this.showPersonalGreeting = true,
    this.showCustomMessage = false,
    this.customMessageTitle = '',
    this.customMessageBody = '',
    this.showAbsenceAggregate = true,
    this.showTicketStats = true,
    this.showHmsHighlights = true,
    this.showAttendanceSummary = true,
    this.showQuickActions = true,
    this.showActivityFeed = true,
    this.showMiniStatsRow = true,
    this.revealNamesOnInfoscreen = false,
    this.showLiveTeamBoard = true,
    this.showTidsbankenPresence = true,
  });

  static const KioskSettings defaults = KioskSettings();

  factory KioskSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return defaults;
    bool b(String k, bool d) => json[k] is bool ? json[k] as bool : d;
    String s(String k, String d) => json[k] is String ? json[k] as String : d;
    return KioskSettings(
      infoscreenLayoutEnabled: b('infoscreen_layout_enabled', defaults.infoscreenLayoutEnabled),
      showClock: b('show_clock', defaults.showClock),
      showPersonalGreeting: b('show_personal_greeting', defaults.showPersonalGreeting),
      showCustomMessage: b('show_custom_message', defaults.showCustomMessage),
      customMessageTitle: s('custom_message_title', defaults.customMessageTitle),
      customMessageBody: s('custom_message_body', defaults.customMessageBody),
      showAbsenceAggregate: b('show_absence_aggregate', defaults.showAbsenceAggregate),
      showTicketStats: b('show_ticket_stats', defaults.showTicketStats),
      showHmsHighlights: b('show_hms_highlights', defaults.showHmsHighlights),
      showAttendanceSummary: b('show_attendance_summary', defaults.showAttendanceSummary),
      showQuickActions: b('show_quick_actions', defaults.showQuickActions),
      showActivityFeed: b('show_activity_feed', defaults.showActivityFeed),
      showMiniStatsRow: b('show_mini_stats_row', defaults.showMiniStatsRow),
      revealNamesOnInfoscreen: b('reveal_names_on_infoscreen', defaults.revealNamesOnInfoscreen),
      showLiveTeamBoard: b('show_live_team_board', defaults.showLiveTeamBoard),
      showTidsbankenPresence: b('show_tidsbanken_presence', defaults.showTidsbankenPresence),
    );
  }

  Map<String, dynamic> toJson() => {
        'infoscreen_layout_enabled': infoscreenLayoutEnabled,
        'show_clock': showClock,
        'show_personal_greeting': showPersonalGreeting,
        'show_custom_message': showCustomMessage,
        'custom_message_title': customMessageTitle,
        'custom_message_body': customMessageBody,
        'show_absence_aggregate': showAbsenceAggregate,
        'show_ticket_stats': showTicketStats,
        'show_hms_highlights': showHmsHighlights,
        'show_attendance_summary': showAttendanceSummary,
        'show_quick_actions': showQuickActions,
        'show_activity_feed': showActivityFeed,
        'show_mini_stats_row': showMiniStatsRow,
        'reveal_names_on_infoscreen': revealNamesOnInfoscreen,
        'show_live_team_board': showLiveTeamBoard,
        'show_tidsbanken_presence': showTidsbankenPresence,
      };

  KioskSettings copyWith({
    bool? infoscreenLayoutEnabled,
    bool? showClock,
    bool? showPersonalGreeting,
    bool? showCustomMessage,
    String? customMessageTitle,
    String? customMessageBody,
    bool? showAbsenceAggregate,
    bool? showTicketStats,
    bool? showHmsHighlights,
    bool? showAttendanceSummary,
    bool? showQuickActions,
    bool? showActivityFeed,
    bool? showMiniStatsRow,
    bool? revealNamesOnInfoscreen,
    bool? showLiveTeamBoard,
    bool? showTidsbankenPresence,
  }) {
    return KioskSettings(
      infoscreenLayoutEnabled: infoscreenLayoutEnabled ?? this.infoscreenLayoutEnabled,
      showClock: showClock ?? this.showClock,
      showPersonalGreeting: showPersonalGreeting ?? this.showPersonalGreeting,
      showCustomMessage: showCustomMessage ?? this.showCustomMessage,
      customMessageTitle: customMessageTitle ?? this.customMessageTitle,
      customMessageBody: customMessageBody ?? this.customMessageBody,
      showAbsenceAggregate: showAbsenceAggregate ?? this.showAbsenceAggregate,
      showTicketStats: showTicketStats ?? this.showTicketStats,
      showHmsHighlights: showHmsHighlights ?? this.showHmsHighlights,
      showAttendanceSummary: showAttendanceSummary ?? this.showAttendanceSummary,
      showQuickActions: showQuickActions ?? this.showQuickActions,
      showActivityFeed: showActivityFeed ?? this.showActivityFeed,
      showMiniStatsRow: showMiniStatsRow ?? this.showMiniStatsRow,
      revealNamesOnInfoscreen: revealNamesOnInfoscreen ?? this.revealNamesOnInfoscreen,
      showLiveTeamBoard: showLiveTeamBoard ?? this.showLiveTeamBoard,
      showTidsbankenPresence: showTidsbankenPresence ?? this.showTidsbankenPresence,
    );
  }
}
