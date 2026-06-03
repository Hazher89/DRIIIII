import 'notification_channel.dart';

class CompanyNotificationSettings {
  final String companyId;
  final NotificationChannel chAbsenceRequest;
  final NotificationChannel chAbsenceDecision;
  final NotificationChannel chTicketNew;
  final NotificationChannel chTicketStatus;
  final NotificationChannel chTicketCritical;
  final NotificationChannel chEquipment;
  final NotificationChannel chUserApproval;
  final NotificationChannel chGeneral;
  final NotificationChannel chPartnerRoute;
  final NotificationChannel chPartnerRouteOwner;
  final NotificationChannel chPartnerMeeting;
  final NotificationChannel chPartnerPortal;
  final NotificationChannel chPartnerCompose;
  final NotificationChannel chVehicleRental;
  final NotificationChannel chVehicleRentalStatus;
  final NotificationChannel chPartnerGeneral;

  const CompanyNotificationSettings({
    required this.companyId,
    this.chAbsenceRequest = NotificationChannel.both,
    this.chAbsenceDecision = NotificationChannel.both,
    this.chTicketNew = NotificationChannel.both,
    this.chTicketStatus = NotificationChannel.both,
    this.chTicketCritical = NotificationChannel.both,
    this.chEquipment = NotificationChannel.both,
    this.chUserApproval = NotificationChannel.both,
    this.chGeneral = NotificationChannel.both,
    this.chPartnerRoute = NotificationChannel.both,
    this.chPartnerRouteOwner = NotificationChannel.both,
    this.chPartnerMeeting = NotificationChannel.both,
    this.chPartnerPortal = NotificationChannel.both,
    this.chPartnerCompose = NotificationChannel.both,
    this.chVehicleRental = NotificationChannel.both,
    this.chVehicleRentalStatus = NotificationChannel.both,
    this.chPartnerGeneral = NotificationChannel.both,
  });

  factory CompanyNotificationSettings.fromJson(
    Map<String, dynamic> employee,
    Map<String, dynamic>? partner,
  ) {
    NotificationChannel ch(Map<String, dynamic> m, String key) =>
        NotificationChannel.fromDb(m[key] as String?);

    return CompanyNotificationSettings(
      companyId: employee['company_id'] as String,
      chAbsenceRequest: ch(employee, 'ch_absence_request'),
      chAbsenceDecision: ch(employee, 'ch_absence_decision'),
      chTicketNew: ch(employee, 'ch_ticket_new'),
      chTicketStatus: ch(employee, 'ch_ticket_status'),
      chTicketCritical: ch(employee, 'ch_ticket_critical'),
      chEquipment: ch(employee, 'ch_equipment'),
      chUserApproval: ch(employee, 'ch_user_approval'),
      chGeneral: ch(employee, 'ch_general'),
      chPartnerRoute: partner != null
          ? ch(partner, 'ch_partner_route')
          : NotificationChannel.both,
      chPartnerRouteOwner: partner != null
          ? ch(partner, 'ch_partner_route_owner')
          : NotificationChannel.both,
      chPartnerMeeting: partner != null
          ? ch(partner, 'ch_partner_meeting')
          : NotificationChannel.both,
      chPartnerPortal: partner != null
          ? ch(partner, 'ch_partner_portal')
          : NotificationChannel.both,
      chPartnerCompose: partner != null
          ? ch(partner, 'ch_partner_compose')
          : NotificationChannel.both,
      chVehicleRental: partner != null
          ? ch(partner, 'ch_vehicle_rental')
          : NotificationChannel.both,
      chVehicleRentalStatus: partner != null
          ? ch(partner, 'ch_vehicle_rental_status')
          : NotificationChannel.both,
      chPartnerGeneral: partner != null
          ? ch(partner, 'ch_partner_general')
          : NotificationChannel.both,
    );
  }

  CompanyNotificationSettings copyWith({
    NotificationChannel? chAbsenceRequest,
    NotificationChannel? chAbsenceDecision,
    NotificationChannel? chTicketNew,
    NotificationChannel? chTicketStatus,
    NotificationChannel? chTicketCritical,
    NotificationChannel? chEquipment,
    NotificationChannel? chUserApproval,
    NotificationChannel? chGeneral,
    NotificationChannel? chPartnerRoute,
    NotificationChannel? chPartnerRouteOwner,
    NotificationChannel? chPartnerMeeting,
    NotificationChannel? chPartnerPortal,
    NotificationChannel? chPartnerCompose,
    NotificationChannel? chVehicleRental,
    NotificationChannel? chVehicleRentalStatus,
    NotificationChannel? chPartnerGeneral,
  }) {
    return CompanyNotificationSettings(
      companyId: companyId,
      chAbsenceRequest: chAbsenceRequest ?? this.chAbsenceRequest,
      chAbsenceDecision: chAbsenceDecision ?? this.chAbsenceDecision,
      chTicketNew: chTicketNew ?? this.chTicketNew,
      chTicketStatus: chTicketStatus ?? this.chTicketStatus,
      chTicketCritical: chTicketCritical ?? this.chTicketCritical,
      chEquipment: chEquipment ?? this.chEquipment,
      chUserApproval: chUserApproval ?? this.chUserApproval,
      chGeneral: chGeneral ?? this.chGeneral,
      chPartnerRoute: chPartnerRoute ?? this.chPartnerRoute,
      chPartnerRouteOwner: chPartnerRouteOwner ?? this.chPartnerRouteOwner,
      chPartnerMeeting: chPartnerMeeting ?? this.chPartnerMeeting,
      chPartnerPortal: chPartnerPortal ?? this.chPartnerPortal,
      chPartnerCompose: chPartnerCompose ?? this.chPartnerCompose,
      chVehicleRental: chVehicleRental ?? this.chVehicleRental,
      chVehicleRentalStatus: chVehicleRentalStatus ?? this.chVehicleRentalStatus,
      chPartnerGeneral: chPartnerGeneral ?? this.chPartnerGeneral,
    );
  }
}
