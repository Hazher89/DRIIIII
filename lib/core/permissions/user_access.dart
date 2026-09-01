import '../../models/user_profile.dart';
import 'access_actions.dart';
import 'access_area_catalog.dart';
import 'access_keys.dart';
import 'access_normalize.dart';

/// Løser effektive tilganger for en bruker (områder + handlinger, v1-kompatibel).
class UserAccess {
  final UserProfile profile;
  final AccessSettingsDoc _doc;
  final Map<String, bool> _legacyResolved;

  UserAccess(this.profile)
      : _doc = _resolveDoc(profile),
        _legacyResolved = _resolveLegacy(profile);

  static UserAccess? of(UserProfile? profile) =>
      profile == null ? null : UserAccess(profile);

  static AccessSettingsDoc _resolveDoc(UserProfile profile) {
    if (profile.role == UserRole.superadmin) {
      final d = AccessSettingsDoc.empty();
      for (final area in AccessAreaCatalog.areas) {
        for (final a in area.actions) {
          d.set(area.id, a, true);
        }
      }
      return d;
    }

    if (!profile.isApproved || profile.isPartnerPortalUser) {
      final d = AccessSettingsDoc.empty();
      d.set('more', AccessAction.view, true);
      return d;
    }

    return AccessSettingsDoc.fromJson(
      AccessNormalize.toV2(profile.accessSettings, profile.role),
    );
  }

  static Map<String, bool> _resolveLegacy(UserProfile profile) {
    if (profile.role == UserRole.superadmin) {
      return {
        for (final k in AccessKeys.allKeys) k: true,
        AccessKeys.partnersVehicleRental: true,
        AccessKeys.partnersVehicleRentalApprove: true,
      };
    }
    if (!profile.isApproved || profile.isPartnerPortalUser) {
      return {
        for (final k in AccessKeys.allKeys) k: false,
        AccessKeys.more: true,
      };
    }
    final legacy = AccessNormalize.toLegacy(profile.accessSettings, profile.role);
    return {for (final e in legacy.entries) e.key: e.value == true};
  }

  /// Ny API: sjekk område + handling.
  bool canArea(String areaId, [AccessAction action = AccessAction.view]) {
    if (profile.role == UserRole.superadmin) return true;
    if (!profile.isApproved) return false;
    if (profile.role == UserRole.ansatt &&
        (areaId == 'more.avdelinger' ||
            areaId == 'admin.avdelinger_rediger' ||
            areaId.startsWith('more.avdelinger'))) {
      return false;
    }
    final def = AccessAreaCatalog.byId[areaId];
    if (def != null && !def.supports(action)) return false;

    // Parent view required
    for (final p in AccessAreaCatalog.ancestors(areaId)) {
      if (!_doc.get(p, AccessAction.view)) return false;
    }
    return _doc.get(areaId, action);
  }

  /// Legacy bool-nøkkel (AccessKeys.*).
  bool can(String key) {
    if (profile.role == UserRole.superadmin) return true;
    if (!profile.isApproved) return false;
    if (profile.role == UserRole.ansatt &&
        (key == AccessKeys.avdelinger || key == AccessKeys.avdelingerRediger)) {
      return false;
    }
    final mapped = AccessAreaCatalog.legacyKeyMap[key];
    if (mapped != null) {
      return canArea(mapped.area, mapped.action);
    }
    return _legacyResolved[key] ?? false;
  }

  bool canAny(Iterable<String> keys) => keys.any(can);

  Map<String, dynamic> toSettingsMap() => _doc.toJson();

  Map<String, dynamic> toLegacySettingsMap() =>
      {for (final e in _legacyResolved.entries) e.key: e.value};

  AccessSettingsDoc get document => _doc;

  // Navigasjon
  bool get canDashboard => can(AccessKeys.dashboard);
  bool get canSurveys => can(AccessKeys.surveys);
  bool get canFravaer => can(AccessKeys.fravaer);
  bool get canAvvik => can(AccessKeys.avvik);
  bool get canHms => can(AccessKeys.hms);
  bool get canPartnersTab => can(AccessKeys.partners);
  bool get canStempling => can(AccessKeys.stempling);
  bool get canUniformMonitor => can(AccessKeys.uniformMonitor);
  bool get canUniformMonitorAdmin => can(AccessKeys.uniformMonitorAdmin);
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
  bool get canHomeFeedAdmin =>
      profile.isSuperAdmin ||
      canArea('more.forside', AccessAction.edit) ||
      can(AccessKeys.forsideRedigering);
  bool get canAccessControl => can(AccessKeys.tilgangskontroll);
  bool get canUserApproval => can(AccessKeys.brukergodkjenning);
  bool get canPartnersMenu => can(AccessKeys.samarbeidspartnere);
  bool get canProfile => can(AccessKeys.profil);
  bool get canAppSettings => can(AccessKeys.appInnstillinger);

  // Handlinger
  bool get canApproveLeave =>
      canArea('fravaer', AccessAction.approve) ||
      canArea('fravaer.godkjenn', AccessAction.approve) ||
      can(AccessKeys.fravaerGodkjenn);
  bool get canRegisterLeaveForOthers =>
      canArea('fravaer.registrer_andre', AccessAction.create) ||
      can(AccessKeys.fravaerRegistrerAndre);
  bool get canVacationAdmin => can(AccessKeys.ferieAdmin);
  bool get canApproveTickets =>
      canArea('avvik', AccessAction.approve) ||
      canArea('avvik.behandle', AccessAction.approve) ||
      can(AccessKeys.avvikGodkjenn);
  bool get canCoordinateTickets => can(AccessKeys.avvikKoordinere);
  bool get canTicketAdmin => can(AccessKeys.avvikAdmin);
  bool get canEditEmployees => can(AccessKeys.ansatteRediger);
  bool get canEditDepartments => can(AccessKeys.avdelingerRediger);
  bool get canBuildSurveys => can(AccessKeys.surveyBygge);
  bool get canSurveyResults => can(AccessKeys.surveyResultater);
  bool get canPartnersAdmin => can(AccessKeys.partnersAdmin);
  bool get canFleetRoutes => can(AccessKeys.fleetRuter);

  bool get canPartnerRoutePlanning =>
      canFleetRoutes || canPartnersTabRuter || canPartnersAdmin;
  bool get canPartnersCreate =>
      canArea('partners', AccessAction.create) || can(AccessKeys.partnersCreate);
  bool get canPartnersDelete =>
      canArea('partners', AccessAction.delete) || can(AccessKeys.partnersDelete);
  bool get canPartnersEdit =>
      canArea('partners', AccessAction.edit) || can(AccessKeys.partnersEdit);
  bool get canPartnersVehicleRental => can(AccessKeys.partnersVehicleRental);
  bool get canPartnersVehicleRentalApprove =>
      canArea('partners.vehicle_rental', AccessAction.approve) ||
      can(AccessKeys.partnersVehicleRentalApprove);

  bool get canPartnersTabOversikt => can(AccessKeys.partnersTabOversikt);
  bool get canPartnersTabBilkontroll => can(AccessKeys.partnersTabBilkontroll);
  bool get canPartnersTabRuter => can(AccessKeys.partnersTabRuter);
  bool get canPartnersTabDokumenter => can(AccessKeys.partnersTabDokumenter);
  bool get canPartnersTabLoyver => can(AccessKeys.partnersTabLoyver);
  bool get canPartnersTabOppfolging => can(AccessKeys.partnersTabOppfolging);
  bool get canPartnersTabOppsummering => can(AccessKeys.partnersTabOppsummering);
  bool get canPartnersTabFri => can(AccessKeys.partnersTabFri);
  bool get canPartnersTabBotTrekk => can(AccessKeys.partnersTabBotTrekk);
  bool get canPartnersTabSms => canArea('partners.tabs.sms');
  bool get canPartnersChat => canArea('partners.chat');
  bool get canPartnersChatBroadcast => canArea('partners.chat.broadcast', AccessAction.create);
  bool get canPartnersChatModerate => canArea('partners.chat.moderate');

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
  bool get canHmsTraining => canArea('hms.opplaering');

  bool get dataScopeCompany =>
      profile.role == UserRole.admin || profile.role == UserRole.superadmin;
}

extension UserProfileAccess on UserProfile {
  UserAccess get access => UserAccess(this);
  bool get isSuperAdmin => role == UserRole.superadmin;
}
