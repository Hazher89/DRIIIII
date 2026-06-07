import '../../permissions/user_access.dart';

// isSuperAdmin via UserProfileAccess extension

/// Filtrerer varselinnboks etter brukerens faktiske tilganger.
class NotificationInboxScope {
  NotificationInboxScope._();

  static bool canSeeAuditEntry(UserAccess access, {String? category, String? settingKey}) {
    if (access.profile.isSuperAdmin) return true;

    final key = (settingKey ?? category ?? '').toLowerCase();
    if (key.isEmpty) return access.canNotifications;

    if (_isPartnerScope(key)) {
      return access.canPartnersMenu ||
          access.canPartnersAdmin ||
          access.canPartnersTab ||
          access.canNotifications;
    }
    if (key.contains('absence') || key.contains('fravaer') || key.contains('leave')) {
      return access.canFravaer || access.canApproveLeave;
    }
    if (key.contains('ticket') || key.contains('avvik')) {
      return access.canAvvik || access.canApproveTickets;
    }
    if (key.contains('survey') || key.contains('undersok')) {
      return access.canSurveys || access.canSurveysMenu;
    }
    if (key.startsWith('hms') || key.contains('equipment') || key.contains('competence')) {
      return access.canHms;
    }
    if (key.contains('sap')) {
      return access.canPartnersMenu || access.canNotifications;
    }

    return access.canNotifications;
  }

  static bool canSeeFailedOutbox(UserAccess access, {required bool isPartnerScope}) {
    if (access.profile.isSuperAdmin) return true;
    return access.canNotifications;
  }

  static bool _isPartnerScope(String key) {
    return key.startsWith('partner') ||
        key.contains('vehicle_rental') ||
        key.contains('portal') ||
        key == 'partner_route' ||
        key == 'partner_mass_route';
  }
}
