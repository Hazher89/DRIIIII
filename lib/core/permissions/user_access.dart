import '../../models/user_profile.dart';
import 'access_catalog.dart';
import 'access_keys.dart';

/// Løser effektive tilganger for en bruker (sider + funksjoner).
class UserAccess {
  final UserProfile profile;
  final Map<String, bool> _resolved;

  UserAccess(this.profile) : _resolved = _resolve(profile);

  static UserAccess? of(UserProfile? profile) =>
      profile == null ? null : UserAccess(profile);

  static Map<String, bool> _resolve(UserProfile profile) {
    if (profile.role == UserRole.superadmin) {
      return {for (final k in AccessKeys.allKeys) k: true};
    }

    if (!profile.isApproved || profile.isPartnerPortalUser) {
      return {for (final k in AccessKeys.allKeys) k: false, AccessKeys.more: true};
    }

    final normalized = AccessCatalog.normalize(profile.accessSettings, profile.role);
    return {for (final e in normalized.entries) e.key: e.value == true};
  }

  bool can(String key) {
    if (profile.role == UserRole.superadmin) return true;
    if (!profile.isApproved) return false;
    if (profile.role == UserRole.ansatt &&
        (key == AccessKeys.avdelinger || key == AccessKeys.avdelingerRediger)) {
      return false;
    }
    return _resolved[key] ?? false;
  }

  bool canAny(Iterable<String> keys) => keys.any(can);

  Map<String, dynamic> toSettingsMap() =>
      {for (final e in _resolved.entries) e.key: e.value};

  // Navigasjon
  bool get canDashboard => can(AccessKeys.dashboard);
  bool get canSurveys => can(AccessKeys.surveys);
  bool get canFravaer => can(AccessKeys.fravaer);
  bool get canAvvik => can(AccessKeys.avvik);
  bool get canHms => can(AccessKeys.hms);
  bool get canPartnersTab => can(AccessKeys.partners);
  bool get canStempling => can(AccessKeys.stempling);
  bool get canStemplingAdmin => can(AccessKeys.stemplingAdmin);
  bool get canStemplingMobile => can(AccessKeys.stemplingMobile);
  bool get canStemplingSettings => can(AccessKeys.stemplingInnstillinger);
  bool get canMore => can(AccessKeys.more);

  // Mer-meny
  bool get canDepartments =>
      profile.role != UserRole.ansatt && can(AccessKeys.avdelinger);
  bool get canEmployeesList => can(AccessKeys.ansatte);
  bool get canPersonalFolder => can(AccessKeys.personalmappe);
  bool get canNotifications => can(AccessKeys.varsler);
  bool get canSurveysMenu => can(AccessKeys.undersokelser);
  bool get canWhistleblowing => can(AccessKeys.whistleblowing);
  bool get canKiosk => can(AccessKeys.kiosk);
  bool get canAccessControl => can(AccessKeys.tilgangskontroll);
  bool get canUserApproval => can(AccessKeys.brukergodkjenning);
  bool get canPartnersMenu => can(AccessKeys.samarbeidspartnere);
  bool get canProfile => can(AccessKeys.profil);
  bool get canAppSettings => can(AccessKeys.appInnstillinger);

  // Handlinger
  bool get canApproveLeave => can(AccessKeys.fravaerGodkjenn);
  bool get canRegisterLeaveForOthers => can(AccessKeys.fravaerRegistrerAndre);
  bool get canVacationAdmin => can(AccessKeys.ferieAdmin);
  bool get canApproveTickets => can(AccessKeys.avvikGodkjenn);
  bool get canCoordinateTickets => can(AccessKeys.avvikKoordinere);
  bool get canTicketAdmin => can(AccessKeys.avvikAdmin);
  bool get canEditEmployees => can(AccessKeys.ansatteRediger);
  bool get canEditDepartments => can(AccessKeys.avdelingerRediger);
  bool get canBuildSurveys => can(AccessKeys.surveyBygge);
  bool get canSurveyResults => can(AccessKeys.surveyResultater);
  bool get canPartnersAdmin => can(AccessKeys.partnersAdmin);
  bool get canFleetRoutes => can(AccessKeys.fleetRuter);

  /// Hovedfanen «Ruter & planlegging» + ruter per bedrift.
  bool get canPartnerRoutePlanning =>
      canFleetRoutes || canPartnersTabRuter || canPartnersAdmin;
  bool get canPartnersCreate => can(AccessKeys.partnersCreate);
  bool get canPartnersDelete => can(AccessKeys.partnersDelete);
  bool get canPartnersEdit => can(AccessKeys.partnersEdit);
  bool get canPartnersVehicleRental => can(AccessKeys.partnersVehicleRental);
  bool get canPartnersVehicleRentalApprove => can(AccessKeys.partnersVehicleRentalApprove);

  bool get canPartnersTabOversikt => can(AccessKeys.partnersTabOversikt);
  bool get canPartnersTabBilkontroll => can(AccessKeys.partnersTabBilkontroll);
  bool get canPartnersTabRuter => can(AccessKeys.partnersTabRuter);
  bool get canPartnersTabDokumenter => can(AccessKeys.partnersTabDokumenter);
  bool get canPartnersTabLoyver => can(AccessKeys.partnersTabLoyver);
  bool get canPartnersTabOppfolging => can(AccessKeys.partnersTabOppfolging);
  bool get canPartnersTabOppsummering => can(AccessKeys.partnersTabOppsummering);
  bool get canPartnersTabFri => can(AccessKeys.partnersTabFri);
  bool get canPartnersTabBotTrekk => can(AccessKeys.partnersTabBotTrekk);

  // HMS undermoduler
  bool get canHmsRisk => can(AccessKeys.hmsRisikovurdering);
  bool get canHmsSja => can(AccessKeys.hmsSja);
  bool get canHmsSafetyRound => can(AccessKeys.hmsSikkerhetsrunde);
  bool get canHmsRiskMatrix => can(AccessKeys.hmsRisikomatrise);
  bool get canHmsEquipment => can(AccessKeys.hmsUtstyr);
  bool get canHmsEquipmentAdmin => can(AccessKeys.hmsUtstyrAdmin);
  bool get canHmsEquipmentService => can(AccessKeys.hmsUtstyrService);
  bool get canHmsEquipmentManuals => can(AccessKeys.hmsUtstyrServicehefte);
  bool get canHmsCompetence => can(AccessKeys.hmsKompetanse);
  bool get canHmsDocuments => can(AccessKeys.hmsDokumenter);

  bool get dataScopeCompany =>
      profile.role == UserRole.admin || profile.role == UserRole.superadmin;
}

extension UserProfileAccess on UserProfile {
  UserAccess get access => UserAccess(this);
  bool get isSuperAdmin => role == UserRole.superadmin;
}
