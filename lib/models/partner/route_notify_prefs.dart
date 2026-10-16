/// Valg av varselkanaler ved ruteutsendelse (app / SMS / e-post).
class RouteNotifyPrefs {
  const RouteNotifyPrefs({
    this.app = true,
    this.sms = true,
    this.email = true,
  });

  final bool app;
  final bool sms;
  final bool email;

  static const all = RouteNotifyPrefs();
  static const none = RouteNotifyPrefs(app: false, sms: false, email: false);
  static const smsOnly = RouteNotifyPrefs(app: false, sms: true, email: false);
  static const pushOnly = RouteNotifyPrefs(app: true, sms: false, email: false);
  static const smsAndPush = RouteNotifyPrefs(app: true, sms: true, email: false);
  static const smsAndEmail = RouteNotifyPrefs(app: false, sms: true, email: true);

  bool get anyEnabled => app || sms || email;

  bool get noneEnabled => !anyEnabled;

  List<String> get dbChannels {
    final list = <String>[];
    if (app) list.add('app');
    if (sms) list.add('sms');
    if (email) list.add('email');
    return list;
  }

  factory RouteNotifyPrefs.fromChannels(Iterable<String>? channels) {
    if (channels == null) return all;
    final set = channels.map((e) => e.toLowerCase().trim()).toSet();
    if (set.isEmpty) return none;
    return RouteNotifyPrefs(
      app: set.contains('app'),
      sms: set.contains('sms'),
      email: set.contains('email'),
    );
  }

  RouteNotifyPrefs copyWith({bool? app, bool? sms, bool? email}) {
    return RouteNotifyPrefs(
      app: app ?? this.app,
      sms: sms ?? this.sms,
      email: email ?? this.email,
    );
  }

  String get shortLabel {
    if (noneEnabled) return 'Uten varsel';
    final parts = <String>[
      if (app) 'App',
      if (sms) 'SMS',
      if (email) 'E-post',
    ];
    return parts.join(' + ');
  }

  String get publishLabel {
    if (noneEnabled) return 'Registrer uten varsel';
    return 'Del ut med $shortLabel';
  }

  String successMessage(int routeCount) {
    if (noneEnabled) {
      return 'Publisert $routeCount rute(r) uten varsel.';
    }
    return 'Publisert $routeCount rute(r). Varsel: $shortLabel.';
  }
}

/// Leveringsstatus for én rute (fra get_partner_route_notify_delivery).
class RouteNotifyDelivery {
  const RouteNotifyDelivery({
    required this.shareId,
    required this.dispatchStatus,
    required this.prefs,
    required this.smsQueued,
    required this.smsSent,
    required this.smsFailed,
    required this.emailQueued,
    required this.emailSent,
    required this.emailFailed,
    required this.pushQueued,
    required this.pushSent,
    required this.pushFailed,
    required this.driverHasAppToken,
    required this.driverHasPhone,
    required this.needsAttention,
    this.pdfStoragePath,
    this.storageOk,
    this.errorSummary,
    this.partnerVehicleId,
    this.shareDate,
    this.title,
  });

  final String shareId;
  final String dispatchStatus;
  final RouteNotifyPrefs prefs;
  final bool smsQueued;
  final bool smsSent;
  final bool smsFailed;
  final bool emailQueued;
  final bool emailSent;
  final bool emailFailed;
  final bool pushQueued;
  final bool pushSent;
  final bool pushFailed;
  final bool driverHasAppToken;
  final bool driverHasPhone;
  final bool needsAttention;
  final String? pdfStoragePath;
  final bool? storageOk;
  final String? errorSummary;
  final String? partnerVehicleId;
  final DateTime? shareDate;
  final String? title;

  factory RouteNotifyDelivery.fromJson(Map<String, dynamic> json) {
    final channels = (json['notify_channels'] as List?)
            ?.map((e) => '$e')
            .toList() ??
        const ['app', 'sms', 'email'];
    DateTime? shareDate;
    final rawDate = json['share_date'];
    if (rawDate != null) {
      shareDate = DateTime.tryParse(rawDate.toString());
    }
    return RouteNotifyDelivery(
      shareId: json['share_id'] as String,
      dispatchStatus: (json['dispatch_status'] as String?) ?? 'staged',
      prefs: RouteNotifyPrefs.fromChannels(channels),
      smsQueued: json['sms_queued'] as bool? ?? false,
      smsSent: json['sms_sent'] as bool? ?? false,
      smsFailed: json['sms_failed'] as bool? ?? false,
      emailQueued: json['email_queued'] as bool? ?? false,
      emailSent: json['email_sent'] as bool? ?? false,
      emailFailed: json['email_failed'] as bool? ?? false,
      pushQueued: json['push_queued'] as bool? ?? false,
      pushSent: json['push_sent'] as bool? ?? false,
      pushFailed: json['push_failed'] as bool? ?? false,
      driverHasAppToken: json['driver_has_app_token'] as bool? ?? false,
      driverHasPhone: json['driver_has_phone'] as bool? ?? false,
      needsAttention: json['needs_attention'] as bool? ?? false,
      pdfStoragePath: (json['pdf_storage_path'] as String?)?.trim(),
      storageOk: json['storage_ok'] as bool?,
      errorSummary: (json['error_summary'] as String?)?.trim(),
      partnerVehicleId: json['partner_vehicle_id'] as String?,
      shareDate: shareDate,
      title: (json['title'] as String?)?.trim(),
    );
  }

  bool get appOk => pushSent || pushQueued;
  bool get smsOk => smsSent || smsQueued;
  bool get emailOk => emailSent || emailQueued;

  String get badgeLabel {
    if (dispatchStatus == 'registered') return 'Uten varsel';
    if (dispatchStatus != 'sent') return 'Kladd';
    final parts = <String>[
      if (prefs.app) (appOk ? 'App ✓' : (driverHasAppToken ? 'App…' : 'App ✗')),
      if (prefs.sms) (smsOk ? 'SMS ✓' : (driverHasPhone ? 'SMS…' : 'SMS ✗')),
      if (prefs.email) (emailOk ? 'E-post ✓' : 'E-post…'),
    ];
    if (parts.isEmpty) return 'Uten varsel';
    return parts.join(' · ');
  }

  RouteNotifyDelivery copyWith({
    bool? needsAttention,
    String? errorSummary,
    bool? storageOk,
  }) {
    return RouteNotifyDelivery(
      shareId: shareId,
      dispatchStatus: dispatchStatus,
      prefs: prefs,
      smsQueued: smsQueued,
      smsSent: smsSent,
      smsFailed: smsFailed,
      emailQueued: emailQueued,
      emailSent: emailSent,
      emailFailed: emailFailed,
      pushQueued: pushQueued,
      pushSent: pushSent,
      pushFailed: pushFailed,
      driverHasAppToken: driverHasAppToken,
      driverHasPhone: driverHasPhone,
      needsAttention: needsAttention ?? this.needsAttention,
      pdfStoragePath: pdfStoragePath,
      storageOk: storageOk ?? this.storageOk,
      errorSummary: errorSummary ?? this.errorSummary,
      partnerVehicleId: partnerVehicleId,
      shareDate: shareDate,
      title: title,
    );
  }
}
