import 'notification_channel.dart';

/// Varselinnstillinger for MAVI-ansatte (fravær, avvik, intern partner-oversikt).
class MaviNotificationSettings {
  final String companyId;
  final NotificationChannel chAbsenceRequest;
  final NotificationChannel chAbsenceDecision;
  final NotificationChannel chTicketNew;
  final NotificationChannel chTicketStatus;
  final NotificationChannel chTicketCritical;
  final NotificationChannel chEquipment;
  final NotificationChannel chUserApproval;
  final NotificationChannel chGeneral;
  final NotificationChannel chPartnerRouteAckInternal;
  final NotificationChannel chPartnerRoutePendingInternal;
  final NotificationChannel chPartnerDocumentInternal;
  final NotificationChannel chSapRouteReceived;
  final NotificationChannel chPartnerRentalInternal;
  final NotificationChannel chPartnerDeactivatedInternal;

  const MaviNotificationSettings({
    required this.companyId,
    this.chAbsenceRequest = NotificationChannel.both,
    this.chAbsenceDecision = NotificationChannel.both,
    this.chTicketNew = NotificationChannel.both,
    this.chTicketStatus = NotificationChannel.both,
    this.chTicketCritical = NotificationChannel.both,
    this.chEquipment = NotificationChannel.both,
    this.chUserApproval = NotificationChannel.both,
    this.chGeneral = NotificationChannel.both,
    this.chPartnerRouteAckInternal = NotificationChannel.both,
    this.chPartnerRoutePendingInternal = NotificationChannel.both,
    this.chPartnerDocumentInternal = NotificationChannel.none,
    this.chSapRouteReceived = NotificationChannel.both,
    this.chPartnerRentalInternal = NotificationChannel.both,
    this.chPartnerDeactivatedInternal = NotificationChannel.sms,
  });

  factory MaviNotificationSettings.fromJson(Map<String, dynamic> json) {
    NotificationChannel ch(String key) =>
        NotificationChannel.fromDb(json[key] as String?);
    return MaviNotificationSettings(
      companyId: json['company_id'] as String,
      chAbsenceRequest: ch('ch_absence_request'),
      chAbsenceDecision: ch('ch_absence_decision'),
      chTicketNew: ch('ch_ticket_new'),
      chTicketStatus: ch('ch_ticket_status'),
      chTicketCritical: ch('ch_ticket_critical'),
      chEquipment: ch('ch_equipment'),
      chUserApproval: ch('ch_user_approval'),
      chGeneral: ch('ch_general'),
      chPartnerRouteAckInternal: ch('ch_partner_route_ack_internal'),
      chPartnerRoutePendingInternal: ch('ch_partner_route_pending_internal'),
      chPartnerDocumentInternal: ch('ch_partner_document_internal'),
      chSapRouteReceived: ch('ch_sap_route_received'),
      chPartnerRentalInternal: ch('ch_partner_rental_internal'),
      chPartnerDeactivatedInternal: ch('ch_partner_deactivated_internal'),
    );
  }

  MaviNotificationSettings copyWith({
    NotificationChannel? chAbsenceRequest,
    NotificationChannel? chAbsenceDecision,
    NotificationChannel? chTicketNew,
    NotificationChannel? chTicketStatus,
    NotificationChannel? chTicketCritical,
    NotificationChannel? chEquipment,
    NotificationChannel? chUserApproval,
    NotificationChannel? chGeneral,
    NotificationChannel? chPartnerRouteAckInternal,
    NotificationChannel? chPartnerRoutePendingInternal,
    NotificationChannel? chPartnerDocumentInternal,
    NotificationChannel? chSapRouteReceived,
    NotificationChannel? chPartnerRentalInternal,
    NotificationChannel? chPartnerDeactivatedInternal,
  }) {
    return MaviNotificationSettings(
      companyId: companyId,
      chAbsenceRequest: chAbsenceRequest ?? this.chAbsenceRequest,
      chAbsenceDecision: chAbsenceDecision ?? this.chAbsenceDecision,
      chTicketNew: chTicketNew ?? this.chTicketNew,
      chTicketStatus: chTicketStatus ?? this.chTicketStatus,
      chTicketCritical: chTicketCritical ?? this.chTicketCritical,
      chEquipment: chEquipment ?? this.chEquipment,
      chUserApproval: chUserApproval ?? this.chUserApproval,
      chGeneral: chGeneral ?? this.chGeneral,
      chPartnerRouteAckInternal:
          chPartnerRouteAckInternal ?? this.chPartnerRouteAckInternal,
      chPartnerRoutePendingInternal:
          chPartnerRoutePendingInternal ?? this.chPartnerRoutePendingInternal,
      chPartnerDocumentInternal:
          chPartnerDocumentInternal ?? this.chPartnerDocumentInternal,
      chSapRouteReceived: chSapRouteReceived ?? this.chSapRouteReceived,
      chPartnerRentalInternal:
          chPartnerRentalInternal ?? this.chPartnerRentalInternal,
      chPartnerDeactivatedInternal:
          chPartnerDeactivatedInternal ?? this.chPartnerDeactivatedInternal,
    );
  }
}
