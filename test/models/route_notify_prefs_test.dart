import 'package:flutter_test/flutter_test.dart';

import 'package:driftpro/models/partner/route_notify_prefs.dart';

void main() {
  group('RouteNotifyPrefs', () {
    test('dbChannels reflects toggles', () {
      expect(
        const RouteNotifyPrefs(app: true, sms: false, email: true).dbChannels,
        ['app', 'email'],
      );
      expect(RouteNotifyPrefs.none.dbChannels, isEmpty);
      expect(RouteNotifyPrefs.all.dbChannels, ['app', 'sms', 'email']);
    });

    test('fromChannels parses', () {
      final p = RouteNotifyPrefs.fromChannels(const ['SMS', 'app']);
      expect(p.app, isTrue);
      expect(p.sms, isTrue);
      expect(p.email, isFalse);
    });

    test('shortLabel', () {
      expect(RouteNotifyPrefs.none.shortLabel, 'Uten varsel');
      expect(
        const RouteNotifyPrefs(app: true, sms: true, email: false).shortLabel,
        'App + SMS',
      );
    });
  });

  group('RouteNotifyDelivery', () {
    test('fromJson + badge', () {
      final d = RouteNotifyDelivery.fromJson({
        'share_id': 'abc',
        'dispatch_status': 'sent',
        'notify_channels': ['app', 'sms'],
        'sms_queued': false,
        'sms_sent': true,
        'sms_failed': false,
        'email_queued': false,
        'email_sent': false,
        'email_failed': false,
        'push_queued': true,
        'push_sent': false,
        'push_failed': false,
        'driver_has_app_token': true,
        'driver_has_phone': true,
        'needs_attention': false,
      });
      expect(d.prefs.app, isTrue);
      expect(d.prefs.email, isFalse);
      expect(d.smsOk, isTrue);
      expect(d.appOk, isTrue);
      expect(d.badgeLabel, contains('App'));
      expect(d.badgeLabel, contains('SMS'));
    });
  });
}
