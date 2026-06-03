import 'notification_channel.dart';

/// Varselinnstillinger til samarbeidspartnere (SMS/e-post fra Mavi).
class PartnerNotificationSettings {
  final String companyId;
  final int routeAckReminderHours;
  final NotificationChannel chPartnerRoute;
  final NotificationChannel chPartnerRouteOwner;
  final NotificationChannel chPartnerMeeting;
  final NotificationChannel chPartnerPortal;
  final NotificationChannel chPartnerCompose;
  final NotificationChannel chVehicleRental;
  final NotificationChannel chVehicleRentalStatus;
  final NotificationChannel chPartnerGeneral;
  final NotificationChannel chPartnerDocument;
  final NotificationChannel chPartnerDocumentFolder;
  final NotificationChannel chPartnerSharedRoutine;
  final NotificationChannel chPartnerRouteReminder;
  final NotificationChannel chPartnerRouteRejected;
  final NotificationChannel chPartnerRouteAccepted;
  final NotificationChannel chPartnerWeeklySummary;
  final NotificationChannel chPartnerMassRoute;
  final NotificationChannel chPartnerVehicleInactive;

  const PartnerNotificationSettings({
    required this.companyId,
    this.routeAckReminderHours = 24,
    this.chPartnerRoute = NotificationChannel.both,
    this.chPartnerRouteOwner = NotificationChannel.both,
    this.chPartnerMeeting = NotificationChannel.both,
    this.chPartnerPortal = NotificationChannel.both,
    this.chPartnerCompose = NotificationChannel.both,
    this.chVehicleRental = NotificationChannel.both,
    this.chVehicleRentalStatus = NotificationChannel.both,
    this.chPartnerGeneral = NotificationChannel.both,
    this.chPartnerDocument = NotificationChannel.both,
    this.chPartnerDocumentFolder = NotificationChannel.both,
    this.chPartnerSharedRoutine = NotificationChannel.email,
    this.chPartnerRouteReminder = NotificationChannel.both,
    this.chPartnerRouteRejected = NotificationChannel.both,
    this.chPartnerRouteAccepted = NotificationChannel.sms,
    this.chPartnerWeeklySummary = NotificationChannel.both,
    this.chPartnerMassRoute = NotificationChannel.both,
    this.chPartnerVehicleInactive = NotificationChannel.sms,
  });

  factory PartnerNotificationSettings.fromJson(Map<String, dynamic> json) {
    NotificationChannel ch(String key) =>
        NotificationChannel.fromDb(json[key] as String?);
    return PartnerNotificationSettings(
      companyId: json['company_id'] as String,
      routeAckReminderHours: json['route_ack_reminder_hours'] as int? ?? 24,
      chPartnerRoute: ch('ch_partner_route'),
      chPartnerRouteOwner: ch('ch_partner_route_owner'),
      chPartnerMeeting: ch('ch_partner_meeting'),
      chPartnerPortal: ch('ch_partner_portal'),
      chPartnerCompose: ch('ch_partner_compose'),
      chVehicleRental: ch('ch_vehicle_rental'),
      chVehicleRentalStatus: ch('ch_vehicle_rental_status'),
      chPartnerGeneral: ch('ch_partner_general'),
      chPartnerDocument: ch('ch_partner_document'),
      chPartnerDocumentFolder: ch('ch_partner_document_folder'),
      chPartnerSharedRoutine: ch('ch_partner_shared_routine'),
      chPartnerRouteReminder: ch('ch_partner_route_reminder'),
      chPartnerRouteRejected: ch('ch_partner_route_rejected'),
      chPartnerRouteAccepted: ch('ch_partner_route_accepted'),
      chPartnerWeeklySummary: ch('ch_partner_weekly_summary'),
      chPartnerMassRoute: ch('ch_partner_mass_route'),
      chPartnerVehicleInactive: ch('ch_partner_vehicle_inactive'),
    );
  }

  PartnerNotificationSettings copyWith({
    int? routeAckReminderHours,
    NotificationChannel? chPartnerRoute,
    NotificationChannel? chPartnerRouteOwner,
    NotificationChannel? chPartnerMeeting,
    NotificationChannel? chPartnerPortal,
    NotificationChannel? chPartnerCompose,
    NotificationChannel? chVehicleRental,
    NotificationChannel? chVehicleRentalStatus,
    NotificationChannel? chPartnerGeneral,
    NotificationChannel? chPartnerDocument,
    NotificationChannel? chPartnerDocumentFolder,
    NotificationChannel? chPartnerSharedRoutine,
    NotificationChannel? chPartnerRouteReminder,
    NotificationChannel? chPartnerRouteRejected,
    NotificationChannel? chPartnerRouteAccepted,
    NotificationChannel? chPartnerWeeklySummary,
    NotificationChannel? chPartnerMassRoute,
    NotificationChannel? chPartnerVehicleInactive,
  }) {
    return PartnerNotificationSettings(
      companyId: companyId,
      routeAckReminderHours: routeAckReminderHours ?? this.routeAckReminderHours,
      chPartnerRoute: chPartnerRoute ?? this.chPartnerRoute,
      chPartnerRouteOwner: chPartnerRouteOwner ?? this.chPartnerRouteOwner,
      chPartnerMeeting: chPartnerMeeting ?? this.chPartnerMeeting,
      chPartnerPortal: chPartnerPortal ?? this.chPartnerPortal,
      chPartnerCompose: chPartnerCompose ?? this.chPartnerCompose,
      chVehicleRental: chVehicleRental ?? this.chVehicleRental,
      chVehicleRentalStatus: chVehicleRentalStatus ?? this.chVehicleRentalStatus,
      chPartnerGeneral: chPartnerGeneral ?? this.chPartnerGeneral,
      chPartnerDocument: chPartnerDocument ?? this.chPartnerDocument,
      chPartnerDocumentFolder: chPartnerDocumentFolder ?? this.chPartnerDocumentFolder,
      chPartnerSharedRoutine: chPartnerSharedRoutine ?? this.chPartnerSharedRoutine,
      chPartnerRouteReminder: chPartnerRouteReminder ?? this.chPartnerRouteReminder,
      chPartnerRouteRejected: chPartnerRouteRejected ?? this.chPartnerRouteRejected,
      chPartnerRouteAccepted: chPartnerRouteAccepted ?? this.chPartnerRouteAccepted,
      chPartnerWeeklySummary: chPartnerWeeklySummary ?? this.chPartnerWeeklySummary,
      chPartnerMassRoute: chPartnerMassRoute ?? this.chPartnerMassRoute,
      chPartnerVehicleInactive: chPartnerVehicleInactive ?? this.chPartnerVehicleInactive,
    );
  }
}
