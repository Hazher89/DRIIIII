import '../../models/user_profile.dart';
import 'access_actions.dart';
import 'access_area_catalog.dart';
import 'access_normalize.dart';
import 'access_presets.dart';

/// Lovforankrede tilgangspakker for vernetjeneste / medvirkning.
///
/// - Verneombud: AML kap. 6
/// - Hovedverneombud: AML § 6-1 (koordinering)
/// - Tillitsvalgt: AML kap. 8–9
/// - AMU-medlem: AML kap. 7
abstract final class StatutoryRoleAccess {
  static Map<String, dynamic> verneombudV2() {
    final doc = AccessSettingsDoc.fromJson(AccessPresets.employeeV2());
    _grantHmsFull(doc);
    _grantAvvikHms(doc);
    _on(doc, 'more.ansatte', {AccessAction.view});
    _on(doc, 'surveys', {AccessAction.view});
    _on(doc, 'surveys.results', {AccessAction.view});
    return doc.toJson();
  }

  /// Hovedverneombud = verneombud + bredere HMS-admin (koordinering).
  static Map<String, dynamic> hovedverneombudV2() {
    final doc = AccessSettingsDoc.fromJson(verneombudV2());
    _on(doc, 'hms.utstyr.admin', AccessAreaCatalog.byId['hms.utstyr.admin']?.actions);
    _on(doc, 'avvik.admin', {AccessAction.view, AccessAction.edit});
    _on(doc, 'more.ansatte', {AccessAction.view, AccessAction.edit});
    return doc.toJson();
  }

  static Map<String, dynamic> tillitsvalgtV2() {
    final doc = AccessSettingsDoc.fromJson(AccessPresets.employeeV2());
    void viewHms(String id) => _on(doc, id, {AccessAction.view});
    _on(doc, 'hms');
    for (final id in [
      'hms.dokumenter',
      'hms.kompetanse',
      'hms.opplaering',
      'hms.risiko',
      'hms.sja',
      'hms.vernerunde',
    ]) {
      viewHms(id);
    }
    _on(doc, 'avvik', {AccessAction.view, AccessAction.create});
    _on(doc, 'avvik.nytt', {AccessAction.view, AccessAction.create});
    _on(doc, 'more.ansatte', {AccessAction.view});
    _on(doc, 'fravaer', {AccessAction.view, AccessAction.create});
    _on(doc, 'fravaer.mine', {AccessAction.view, AccessAction.create});
    _on(doc, 'fravaer.team', {AccessAction.view});
    _on(doc, 'surveys', {AccessAction.view});
    _on(doc, 'surveys.results', {AccessAction.view});
    return doc.toJson();
  }

  /// AMU: systematisk innsyn i HMS + avvik (AML kap. 7) — ikke personlig fraværsadmin.
  static Map<String, dynamic> amuMemberV2() {
    final doc = AccessSettingsDoc.fromJson(AccessPresets.employeeV2());
    _grantHmsFull(doc);
    _grantAvvikHms(doc);
    _on(doc, 'more.ansatte', {AccessAction.view});
    _on(doc, 'surveys', {AccessAction.view});
    _on(doc, 'surveys.results', {AccessAction.view});
    _on(doc, 'fravaer.team', {AccessAction.view});
    return doc.toJson();
  }

  static Map<String, dynamic> mergePackage(
    Map<String, dynamic>? base,
    Map<String, dynamic> package,
    UserRole role,
  ) {
    final doc = AccessSettingsDoc.fromJson(AccessNormalize.toV2(base, role));
    final pkg = AccessSettingsDoc.fromJson(package);
    _orIn(doc, pkg);
    return doc.toJson();
  }

  static Map<String, dynamic> rebuildAccessSettings({
    required UserRole role,
    required Map<String, dynamic>? current,
    required bool isSafetyRepresentative,
    required bool isUnionRepresentative,
    bool isChiefSafetyRepresentative = false,
    bool isAmuMember = false,
  }) {
    final roleDoc = AccessSettingsDoc.fromJson(AccessPresets.forRoleV2(role));
    final currentDoc = AccessSettingsDoc.fromJson(
      AccessNormalize.toV2(current, role),
    );

    final out = AccessSettingsDoc.fromJson(roleDoc.toJson());
    for (final area in AccessAreaCatalog.areas) {
      for (final a in area.actions) {
        if (currentDoc.get(area.id, a)) out.set(area.id, a, true);
      }
    }

    final activePackages = <AccessSettingsDoc>[];
    if (isChiefSafetyRepresentative) {
      activePackages.add(AccessSettingsDoc.fromJson(hovedverneombudV2()));
    } else if (isSafetyRepresentative) {
      activePackages.add(AccessSettingsDoc.fromJson(verneombudV2()));
    }
    if (isUnionRepresentative) {
      activePackages.add(AccessSettingsDoc.fromJson(tillitsvalgtV2()));
    }
    if (isAmuMember) {
      activePackages.add(AccessSettingsDoc.fromJson(amuMemberV2()));
    }

    final allStatutory = [
      AccessSettingsDoc.fromJson(hovedverneombudV2()),
      AccessSettingsDoc.fromJson(verneombudV2()),
      AccessSettingsDoc.fromJson(tillitsvalgtV2()),
      AccessSettingsDoc.fromJson(amuMemberV2()),
    ];

    // Fjern alt som kun kom fra lovpakker, deretter legg på aktive.
    for (final pkg in allStatutory) {
      _stripUnlessNeeded(out, pkg, keepers: [roleDoc, ...activePackages]);
    }
    for (final pkg in activePackages) {
      _orIn(out, pkg);
    }

    return out.toJson();
  }

  static void _grantHmsFull(AccessSettingsDoc doc) {
    _on(doc, 'hms');
    for (final id in [
      'hms.risiko',
      'hms.sja',
      'hms.vernerunde',
      'hms.risikomatrise',
      'hms.utstyr',
      'hms.utstyr.service',
      'hms.utstyr.servicehefte',
      'hms.kompetanse',
      'hms.dokumenter',
      'hms.opplaering',
    ]) {
      _on(doc, id, AccessAreaCatalog.byId[id]?.actions);
    }
    _on(doc, 'hms.vernerunde', AccessAreaCatalog.crudApprove);
  }

  static void _grantAvvikHms(AccessSettingsDoc doc) {
    _on(doc, 'avvik', AccessAreaCatalog.crudApprove);
    _on(doc, 'avvik.nytt', {AccessAction.view, AccessAction.create});
    _on(doc, 'avvik.behandle', {AccessAction.view, AccessAction.approve});
    _on(doc, 'avvik.koordinere', {AccessAction.view, AccessAction.edit});
  }

  static void _on(
    AccessSettingsDoc doc,
    String id, [
    Set<AccessAction>? actions,
  ]) {
    final def = AccessAreaCatalog.byId[id];
    if (def == null) return;
    final acts = actions ?? {AccessAction.view};
    for (final a in acts) {
      if (def.supports(a)) doc.set(id, a, true);
    }
    doc.ensureParentViews(id);
  }

  static void _orIn(AccessSettingsDoc target, AccessSettingsDoc pkg) {
    for (final area in AccessAreaCatalog.areas) {
      for (final a in area.actions) {
        if (pkg.get(area.id, a)) target.set(area.id, a, true);
      }
    }
  }

  static void _stripUnlessNeeded(
    AccessSettingsDoc target,
    AccessSettingsDoc pkg, {
    required List<AccessSettingsDoc> keepers,
  }) {
    for (final area in AccessAreaCatalog.areas) {
      for (final a in area.actions) {
        if (!pkg.get(area.id, a)) continue;
        final keptByOther = keepers.any((k) => k.get(area.id, a));
        if (!keptByOther) target.set(area.id, a, false);
      }
    }
  }

  static const verneombudLawHint =
      'Iht. arbeidsmiljøloven kap. 6: innsyn og oppfølging av HMS, '
      'vernerunder, risiko/SJA, avvik og dokumentasjon. '
      'Ledelsen (Tommy/Nico/Hazher) kan justere enkeltmoduler manuelt.';

  static const hovedverneombudLawHint =
      'Hovedverneombud (AML § 6-1): koordinerer vernetjenesten, full HMS '
      'inkl. utstyr-admin. Innebærer også verneombud-tilganger.';

  static const tillitsvalgtLawHint =
      'Iht. arbeidsmiljøloven kap. 8–9: info/drøfting om arbeidsforhold, '
      'HMS-oversikt og avvik. Ikke automatisk full tilgang til andres '
      'fraværsbehandling. Ledelsen kan justere manuelt.';

  static const amuLawHint =
      'AMU-medlem (arbeidsmiljøloven kap. 7): systematisk innsyn i HMS, '
      'avvik og vernetiltak for utvalgsarbeid. Ikke personlig fraværsadmin.';
}
