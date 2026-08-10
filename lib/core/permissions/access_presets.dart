import '../../models/user_profile.dart';
import 'access_actions.dart';
import 'access_area_catalog.dart';
import 'access_normalize.dart';

/// Forhåndsdefinerte tilgangspakker (v2 area/action + legacy bool).
class AccessPresets {
  AccessPresets._();

  static Map<String, dynamic> employee() =>
      AccessSettingsDoc.fromJson(employeeV2()).toLegacyBoolMap();

  static Map<String, dynamic> departmentLeader() =>
      AccessSettingsDoc.fromJson(departmentLeaderV2()).toLegacyBoolMap();

  static Map<String, dynamic> companyAdmin() =>
      AccessSettingsDoc.fromJson(companyAdminV2()).toLegacyBoolMap();

  static Map<String, dynamic> forRole(UserRole role) =>
      AccessSettingsDoc.fromJson(forRoleV2(role)).toLegacyBoolMap();

  static Map<String, dynamic> forRoleV2(UserRole role) {
    switch (role) {
      case UserRole.leder:
        return departmentLeaderV2();
      case UserRole.admin:
        return companyAdminV2();
      case UserRole.superadmin:
        return allOnV2();
      case UserRole.samarbeidspartner:
        return partnerPortalV2();
      case UserRole.ansatt:
        return employeeV2();
    }
  }

  static Map<String, dynamic> employeeV2() {
    final doc = AccessSettingsDoc.empty();
    void on(String id, [Set<AccessAction>? actions]) {
      final def = AccessAreaCatalog.byId[id];
      if (def == null) return;
      final acts = actions ?? {AccessAction.view};
      for (final a in acts) {
        if (def.supports(a)) doc.set(id, a, true);
      }
      doc.ensureParentViews(id);
    }

    on('dashboard');
    on('more');
    on('more.profil');
    on('fravaer', {AccessAction.view, AccessAction.create});
    on('fravaer.mine', {AccessAction.view, AccessAction.create});
    on('avvik', {AccessAction.view, AccessAction.create});
    on('avvik.nytt', {AccessAction.view, AccessAction.create});
    on('more.whistleblowing', {AccessAction.view, AccessAction.create});
    on('stempling');
    on('stempling.mobile');
    return doc.toJson();
  }

  static Map<String, dynamic> departmentLeaderV2() {
    final doc = AccessSettingsDoc.fromJson(employeeV2());
    void on(String id, [Set<AccessAction>? actions]) {
      final def = AccessAreaCatalog.byId[id];
      if (def == null) return;
      final acts = actions ?? def.actions;
      for (final a in acts) {
        if (def.supports(a)) doc.set(id, a, true);
      }
      doc.ensureParentViews(id);
    }

    on('more.ansatte', AccessAreaCatalog.crud);
    on('admin.ansatte_rediger', {AccessAction.view, AccessAction.edit});
    on('more.avdelinger');
    on('fravaer', AccessAreaCatalog.crudApprove);
    on('fravaer.team');
    on('fravaer.godkjenn', {AccessAction.view, AccessAction.approve});
    on('fravaer.registrer_andre', {AccessAction.view, AccessAction.create});
    on('fravaer.ferie_admin', {AccessAction.view, AccessAction.edit});
    on('avvik', AccessAreaCatalog.crudApprove);
    on('avvik.behandle', {AccessAction.view, AccessAction.approve});
    on('avvik.koordinere', {AccessAction.view, AccessAction.edit});
    on('surveys');
    on('surveys.results');
    on('hms');
    for (final id in [
      'hms.risiko',
      'hms.sja',
      'hms.vernerunde',
      'hms.utstyr',
      'hms.utstyr.admin',
      'hms.utstyr.service',
      'hms.utstyr.servicehefte',
      'hms.kompetanse',
      'hms.dokumenter',
      'hms.opplaering',
    ]) {
      on(id, AccessAreaCatalog.byId[id]?.actions);
    }
    on('partners', AccessAreaCatalog.crudApprove);
    on('partners.admin', AccessAreaCatalog.crud);
    on('partners.fleet', AccessAreaCatalog.viewCreateEdit);
    on('partners.create', {AccessAction.view, AccessAction.create});
    on('partners.edit', {AccessAction.view, AccessAction.edit});
    on('partners.delete', {AccessAction.view, AccessAction.delete});
    on('partners.vehicle_rental', AccessAreaCatalog.crudApprove);
    on('partners.vehicle_rental.approve',
        {AccessAction.view, AccessAction.approve});
    for (final a in AccessAreaCatalog.areas.where(
      (x) => x.id.startsWith('partners.tabs.'),
    )) {
      on(a.id, a.actions);
    }
    on('stempling.admin', {AccessAction.view, AccessAction.edit});
    on('stempling.innstillinger', {AccessAction.view, AccessAction.edit});
    on('more.partnere');
    return doc.toJson();
  }

  static Map<String, dynamic> companyAdminV2() {
    final doc = AccessSettingsDoc.fromJson(allOnV2());
    doc.set('more.varsler', AccessAction.view, false);
    doc.set('more.varsler', AccessAction.edit, false);
    doc.set('more.brukergodkjenning', AccessAction.view, false);
    doc.set('more.brukergodkjenning', AccessAction.approve, false);
    doc.set('uniform', AccessAction.view, false);
    doc.set('uniform', AccessAction.edit, false);
    doc.set('uniform.admin', AccessAction.view, false);
    doc.set('uniform.admin', AccessAction.edit, false);
    doc.set('more', AccessAction.view, true);
    return doc.toJson();
  }

  static Map<String, dynamic> allOnV2() {
    final doc = AccessSettingsDoc.empty();
    for (final area in AccessAreaCatalog.areas) {
      for (final a in area.actions) {
        doc.set(area.id, a, true);
      }
    }
    return doc.toJson();
  }

  static Map<String, dynamic> allOffV2() {
    final doc = AccessSettingsDoc.empty();
    doc.set('more', AccessAction.view, true);
    return doc.toJson();
  }

  static Map<String, dynamic> partnerPortalV2() {
    final doc = AccessSettingsDoc.empty();
    doc.set('dashboard', AccessAction.view, true);
    doc.set('more', AccessAction.view, true);
    doc.set('partners', AccessAction.view, true);
    doc.set('more.profil', AccessAction.view, true);
    return doc.toJson();
  }

  static String presetTitle(UserRole role) {
    switch (role) {
      case UserRole.ansatt:
        return 'Ansatt (kun egne data)';
      case UserRole.leder:
        return 'Avdelingsleder (egen avdeling)';
      case UserRole.admin:
        return 'Administrator';
      case UserRole.superadmin:
        return 'Superadmin – alt på';
      case UserRole.samarbeidspartner:
        return 'Samarbeidspartner';
    }
  }
}
