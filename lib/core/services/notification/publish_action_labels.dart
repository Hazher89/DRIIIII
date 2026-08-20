import '../../../models/notification_channel.dart';
import '../../../models/partner/route_notify_prefs.dart';
import 'partner_notification_settings_service.dart';

/// Knappetekster for publisering basert på varselinnstillinger.
class PublishActionLabels {
  PublishActionLabels._();

  static String publishLabel(NotificationChannel channel) {
    switch (channel) {
      case NotificationChannel.none:
        return 'Publiser uten varsel';
      case NotificationChannel.sms:
        return 'Publiser og send SMS';
      case NotificationChannel.email:
        return 'Publiser og send e-post';
      case NotificationChannel.both:
        return 'Publiser og send SMS + e-post';
    }
  }

  static String publishShortLabel(NotificationChannel channel) {
    switch (channel) {
      case NotificationChannel.none:
        return 'Uten varsel';
      case NotificationChannel.sms:
        return 'Med SMS';
      case NotificationChannel.email:
        return 'Med e-post';
      case NotificationChannel.both:
        return 'SMS + e-post';
    }
  }

  static String publishLabelForPrefs(RouteNotifyPrefs prefs) => prefs.publishLabel;

  static String publishShortLabelForPrefs(RouteNotifyPrefs prefs) => prefs.shortLabel;

  static Future<String> singleRoutePublishLabel(String companyId) async {
    final s = await PartnerNotificationSettingsService.fetch(companyId);
    return publishLabel(s.chPartnerRoute);
  }

  static Future<String> massRoutePublishLabel(String companyId) async {
    final s = await PartnerNotificationSettingsService.fetch(companyId);
    return publishLabel(s.chPartnerMassRoute);
  }

  static Future<NotificationChannel> singleRouteChannel(String companyId) async {
    final s = await PartnerNotificationSettingsService.fetch(companyId);
    return s.chPartnerRoute;
  }

  static Future<NotificationChannel> massRouteChannel(String companyId) async {
    final s = await PartnerNotificationSettingsService.fetch(companyId);
    return s.chPartnerMassRoute;
  }

  /// Map firmakanal til RouteNotifyPrefs (app alltid på når det varsles).
  static RouteNotifyPrefs prefsFromChannel(NotificationChannel channel) {
    switch (channel) {
      case NotificationChannel.none:
        return RouteNotifyPrefs.none;
      case NotificationChannel.sms:
        return const RouteNotifyPrefs(app: true, sms: true, email: false);
      case NotificationChannel.email:
        return const RouteNotifyPrefs(app: true, sms: false, email: true);
      case NotificationChannel.both:
        return RouteNotifyPrefs.all;
    }
  }

  static String successMessage({
    required int routeCount,
    required NotificationChannel channel,
    required bool notifyDriver,
    RouteNotifyPrefs? prefs,
  }) {
    if (prefs != null) {
      return prefs.successMessage(routeCount);
    }
    if (!notifyDriver || channel == NotificationChannel.none) {
      return 'Publisert $routeCount rute(r) uten varsel.';
    }
    switch (channel) {
      case NotificationChannel.sms:
        return 'Publisert $routeCount rute(r). SMS er satt i kø der telefon finnes.';
      case NotificationChannel.email:
        return 'Publisert $routeCount rute(r). E-post er satt i kø.';
      case NotificationChannel.both:
        return 'Publisert $routeCount rute(r). SMS og e-post er satt i kø.';
      case NotificationChannel.none:
        return 'Publisert $routeCount rute(r).';
    }
  }
}
