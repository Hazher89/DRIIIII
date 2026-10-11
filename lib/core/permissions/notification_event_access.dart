import '../../models/user_profile.dart';
import 'access_actions.dart';
import 'user_access.dart';

/// Hvilke varseltyper en bruker får se og endre.
/// Samme regler som `profile_notification_event_open` i databasen.
class NotificationEventAccess {
  NotificationEventAccess._();

  static bool visible({
    required UserAccess access,
    required UserProfile profile,
    required String eventId,
    bool departmentLeader = false,
  }) {
    if (!profile.isActive || !profile.isApproved) return false;
    if (profile.isPartnerPortalUser) {
      return _partnerEvents.contains(eventId) && access.canArea('partners');
    }
    if (_partnerEvents.contains(eventId)) return false;

    bool open(String area, [AccessAction action = AccessAction.view]) =>
        access.canArea(area, action);

    switch (eventId) {
      case 'absence_decision':
        return open('fravaer');
      case 'absence_request':
        return open('fravaer.godkjenn', AccessAction.approve) ||
            open('fravaer', AccessAction.approve) ||
            open('fravaer.team') ||
            (departmentLeader && open('fravaer'));
      case 'ticket_status':
        return open('avvik') || open('avvik.nytt');
      case 'ticket_new':
      case 'ticket_assigned':
      case 'ticket_critical':
        return open('avvik.behandle', AccessAction.approve) ||
            open('avvik.koordinere') ||
            open('avvik.admin') ||
            (departmentLeader && open('avvik'));
      case 'hms_risk_assigned':
      case 'hms_ros_avvik_signal':
        return open('hms.risiko');
      case 'hms_sja_assigned':
      case 'hms_sja_expired':
        return open('hms.sja');
      case 'hms_general':
        return open('hms') || open('hms.risiko') || open('hms.sja');
      case 'equipment':
        return open('hms.utstyr');
      case 'user_approval':
        return open('more.brukergodkjenning');
      case 'partner_route_ack_internal':
      case 'partner_route_pending_internal':
      case 'sap_route_received':
        return open('partners') ||
            open('partners.fleet') ||
            open('partners.tabs.ruter');
      case 'partner_rental_internal':
        return open('partners.vehicle_rental');
      case 'partner_document_internal':
        return open('partners.tabs.dokumenter') || open('partners');
      case 'partner_deactivated_internal':
        return open('partners.admin') || open('partners', AccessAction.delete);
      case 'general':
        return open('dashboard') || open('more');
      default:
        return false;
    }
  }

  static const _partnerEvents = {
    'partner_route',
    'partner_route_owner',
    'partner_route_reminder',
    'partner_route_rejected',
    'partner_route_accepted',
    'partner_mass_route',
    'partner_document',
    'partner_document_folder',
    'partner_shared_routine',
    'partner_portal',
    'partner_weekly_summary',
    'partner_meeting',
    'partner_compose',
    'vehicle_rental',
    'vehicle_rental_status',
    'partner_vehicle_inactive',
    'partner_general',
  };
}
