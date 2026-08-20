import 'package:flutter_test/flutter_test.dart';

import 'package:driftpro/core/permissions/route_access_map.dart';
import 'package:driftpro/core/permissions/user_access.dart';
import 'package:driftpro/core/routing/app_paths.dart';
import 'package:driftpro/models/user_profile.dart';

UserAccess _access(Map<String, Map<String, bool>> areas) {
  return UserAccess(
    UserProfile(
      id: 'u1',
      email: 'test@example.com',
      fullName: 'Test',
      role: UserRole.ansatt,
      isApproved: true,
      isOnboarded: true,
      accessSettings: {
        'version': 2,
        'areas': areas,
      },
    ),
  );
}

void main() {
  test('partner ruter-tab krever ruteplanlegging', () {
    final denied = _access({
      'partners': {'view': true},
      'partners.fleet': {'view': false},
      'partners.tabs.ruter': {'view': false},
      'partners.admin': {'view': false},
      'more': {'view': true},
    });
    final allowed = _access({
      'partners': {'view': true},
      'partners.fleet': {'view': true, 'create': true, 'edit': true},
      'more': {'view': true},
    });

    final uri = Uri.parse('${AppPaths.partners}?tab=ruter');
    expect(RouteAccessMap.allowsUri(denied, uri), isFalse);
    expect(RouteAccessMap.allowsUri(allowed, uri), isTrue);
  });

  test('partner detalj-fane dokumenter krever egen nøkkel', () {
    final denied = _access({
      'partners': {'view': true},
      'partners.tabs.oversikt': {'view': true},
      'partners.tabs.dokumenter': {'view': false},
      'more': {'view': true},
    });
    final allowed = _access({
      'partners': {'view': true},
      'partners.tabs.dokumenter': {'view': true},
      'more': {'view': true},
    });

    final uri = Uri.parse('${AppPaths.partners}/bedrift/abc?tab=dokumenter');
    expect(RouteAccessMap.allowsUri(denied, uri), isFalse);
    expect(RouteAccessMap.allowsUri(allowed, uri), isTrue);
  });

  test('tilgangskontroll-sti er beskyttet', () {
    final denied = _access({
      'more': {'view': true},
      'more.tilgangskontroll': {'view': false},
    });
    final uri = Uri.parse(AppPaths.moreTilgangskontroll);
    expect(RouteAccessMap.allowsUri(denied, uri), isFalse);
  });
}
