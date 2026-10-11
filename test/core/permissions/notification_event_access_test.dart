import 'package:flutter_test/flutter_test.dart';

import 'package:driftpro/core/permissions/access_presets.dart';
import 'package:driftpro/core/permissions/notification_event_access.dart';
import 'package:driftpro/core/permissions/user_access.dart';
import 'package:driftpro/models/user_profile.dart';

UserProfile _person({
  required UserRole role,
  required Map<String, dynamic> access,
  String? employeeNumber,
}) {
  return UserProfile(
    id: 'p1',
    email: 'a@driftpro.no',
    fullName: 'Test',
    role: role,
    isApproved: true,
    isActive: true,
    employeeNumber: employeeNumber,
    accessSettings: access,
  );
}

void main() {
  test('ansatt ser bare egne sider', () {
    final person = _person(
      role: UserRole.ansatt,
      access: AccessPresets.employeeV2(),
    );
    final access = person.access;
    bool see(String id) => NotificationEventAccess.visible(
          access: access,
          profile: person,
          eventId: id,
        );

    expect(see('absence_decision'), isTrue);
    expect(see('general'), isTrue);
    expect(see('absence_request'), isFalse);
    expect(see('ticket_status'), isFalse);
    expect(see('hms_general'), isFalse);
    expect(see('equipment'), isFalse);
    expect(see('user_approval'), isFalse);
    expect(see('partner_route_ack_internal'), isFalse);
  });

  test('avdelingsleder ser sidene i preset', () {
    final person = _person(
      role: UserRole.leder,
      access: AccessPresets.departmentLeaderV2(),
    );
    final access = person.access;
    bool see(String id) => NotificationEventAccess.visible(
          access: access,
          profile: person,
          eventId: id,
        );

    expect(see('absence_request'), isTrue);
    expect(see('hms_general'), isTrue);
    expect(see('equipment'), isTrue);
    expect(see('partner_rental_internal'), isTrue);
    expect(see('user_approval'), isFalse);
  });

  test('superadmin uten HMS-side ser ikke HMS-varsler', () {
    final raw = Map<String, dynamic>.from(AccessPresets.allOnV2());
    final areas = Map<String, dynamic>.from(raw['areas'] as Map);
    final hms = Map<String, dynamic>.from(areas['hms'] as Map);
    hms['view'] = false;
    areas['hms'] = hms;
    raw['areas'] = areas;
    final person = _person(
      role: UserRole.superadmin,
      access: raw,
      employeeNumber: '1',
    );
    final access = person.access;
    expect(
      NotificationEventAccess.visible(
        access: access,
        profile: person,
        eventId: 'hms_general',
      ),
      isFalse,
    );
    expect(
      NotificationEventAccess.visible(
        access: access,
        profile: person,
        eventId: 'equipment',
      ),
      isFalse,
    );
    expect(
      NotificationEventAccess.visible(
        access: access,
        profile: person,
        eventId: 'absence_decision',
      ),
      isTrue,
    );
  });
}
