import '../../models/user_profile.dart';
import 'access_actions.dart';
import 'access_area_catalog.dart';
import 'access_keys.dart';
import 'access_presets.dart';

/// Mutable v2 access_settings dokument.
class AccessSettingsDoc {
  AccessSettingsDoc(this.areas);

  final Map<String, Map<String, bool>> areas;

  static const version = 2;

  factory AccessSettingsDoc.empty() => AccessSettingsDoc({});

  factory AccessSettingsDoc.fromJson(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return AccessSettingsDoc.empty();
    if (raw['version'] == 2 && raw['areas'] is Map) {
      final areas = <String, Map<String, bool>>{};
      final src = Map<String, dynamic>.from(raw['areas'] as Map);
      for (final e in src.entries) {
        if (e.value is Map) {
          areas[e.key] = {
            for (final a in (e.value as Map).entries)
              a.key.toString(): a.value == true,
          };
        } else if (e.value == true) {
          areas[e.key] = {AccessAction.view.dbKey: true};
        }
      }
      return AccessSettingsDoc(areas);
    }
    return AccessSettingsDoc.fromLegacyV1(raw);
  }

  /// Konverter flat bool-map (v1) til areas.
  factory AccessSettingsDoc.fromLegacyV1(Map<String, dynamic> raw) {
    final doc = AccessSettingsDoc.empty();
    for (final e in raw.entries) {
      if (e.key == 'version' || e.key == 'areas') continue;
      if (e.value != true) continue;
      final mapped = AccessAreaCatalog.legacyKeyMap[e.key];
      if (mapped != null) {
        doc.set(mapped.area, mapped.action, true);
        // Ensure view on same area when granting an action.
        doc.set(mapped.area, AccessAction.view, true);
      } else {
        // Unknown key: treat as area id with view.
        doc.set(e.key, AccessAction.view, true);
      }
    }
    return doc;
  }

  bool get(String areaId, AccessAction action) =>
      areas[areaId]?[action.dbKey] == true;

  void set(String areaId, AccessAction action, bool value) {
    final def = AccessAreaCatalog.byId[areaId];
    if (def != null && !def.supports(action)) return;
    final cur = Map<String, bool>.from(areas[areaId] ?? {});
    cur[action.dbKey] = value;
    areas[areaId] = cur;
  }

  /// Slå på/av alle støttede handlinger for et område (+ valgfritt barn).
  void setAreaAll(String areaId, bool value, {bool cascadeChildren = true}) {
    final def = AccessAreaCatalog.byId[areaId];
    if (def == null) return;
    for (final a in def.actions) {
      set(areaId, a, value);
    }
    if (cascadeChildren) {
      for (final childId in AccessAreaCatalog.descendants(areaId)) {
        final child = AccessAreaCatalog.byId[childId];
        if (child == null) continue;
        for (final a in child.actions) {
          set(childId, a, value);
        }
      }
    }
  }

  void setViewOnly(String areaId) {
    final def = AccessAreaCatalog.byId[areaId];
    if (def == null) return;
    for (final a in def.actions) {
      set(areaId, a, a == AccessAction.view);
    }
  }

  void ensureParentViews(String areaId) {
    for (final p in AccessAreaCatalog.ancestors(areaId)) {
      set(p, AccessAction.view, true);
    }
  }

  void applyInheritanceRules() {
    // Child view ⇒ parent view
    for (final areaId in areas.keys.toList()) {
      if (get(areaId, AccessAction.view)) {
        ensureParentViews(areaId);
      }
    }
    // Parent without view ⇒ wipe children
    for (final root in AccessAreaCatalog.roots) {
      _wipeIfNoView(root.id);
    }
  }

  void _wipeIfNoView(String areaId) {
    if (!get(areaId, AccessAction.view)) {
      for (final childId in AccessAreaCatalog.descendants(areaId)) {
        areas.remove(childId);
      }
      return;
    }
    for (final c in AccessAreaCatalog.childrenOf(areaId)) {
      _wipeIfNoView(c.id);
    }
  }

  Map<String, dynamic> toJson() {
    applyInheritanceRules();
    // Always keep Mer visible for shell.
    set('more', AccessAction.view, true);
    return {
      'version': version,
      'areas': {
        for (final e in areas.entries)
          if (e.value.values.any((v) => v))
            e.key: {for (final a in e.value.entries) a.key: a.value},
      },
    };
  }

  /// Flat legacy map for UI/kode som fortsatt bruker AccessKeys.
  Map<String, dynamic> toLegacyBoolMap() {
    final out = AccessKeys.allOff();
    for (final e in AccessAreaCatalog.legacyKeyMap.entries) {
      final area = e.value.area;
      final action = e.value.action;
      out[e.key] = get(area, action);
      // Also true if view is granted on mapped area for view-keys.
      if (action == AccessAction.view && get(area, AccessAction.view)) {
        out[e.key] = true;
      }
    }
    // Special: approve keys also check area.approve
    if (get('fravaer', AccessAction.approve) ||
        get('fravaer.godkjenn', AccessAction.approve)) {
      out[AccessKeys.fravaerGodkjenn] = true;
    }
    if (get('avvik', AccessAction.approve) ||
        get('avvik.behandle', AccessAction.approve)) {
      out[AccessKeys.avvikGodkjenn] = true;
    }
    out[AccessKeys.more] = true;
    // Vehicle rental keys (missing from allKeys historically)
    out[AccessKeys.partnersVehicleRental] =
        get('partners.vehicle_rental', AccessAction.view);
    out[AccessKeys.partnersVehicleRentalApprove] =
        get('partners.vehicle_rental', AccessAction.approve) ||
            get('partners.vehicle_rental.approve', AccessAction.approve);
    return out;
  }

  int countEnabledActions() {
    var n = 0;
    for (final area in AccessAreaCatalog.areas) {
      for (final a in area.actions) {
        if (get(area.id, a)) n++;
      }
    }
    return n;
  }

  int get totalPossibleActions {
    var n = 0;
    for (final area in AccessAreaCatalog.areas) {
      n += area.actions.length;
    }
    return n;
  }
}

/// Normaliser rå access_settings til v2 JSON klar for lagring/UI.
class AccessNormalize {
  AccessNormalize._();

  static Map<String, dynamic> toV2(
    Map<String, dynamic>? raw,
    UserRole role,
  ) {
    final preset = AccessSettingsDoc.fromJson(AccessPresets.forRoleV2(role));
    final doc = raw == null || raw.isEmpty
        ? preset
        : AccessSettingsDoc.fromJson(raw);

    // Fill missing areas from preset (only where area absent).
    for (final area in AccessAreaCatalog.areas) {
      if (!doc.areas.containsKey(area.id)) {
        final presetArea = preset.areas[area.id];
        if (presetArea != null) {
          doc.areas[area.id] = Map<String, bool>.from(presetArea);
        }
      }
    }

    // Hard locks for ansatt
    if (role == UserRole.ansatt) {
      doc.set('more.avdelinger', AccessAction.view, false);
      doc.set('admin.avdelinger_rediger', AccessAction.edit, false);
      doc.set('admin.avdelinger_rediger', AccessAction.view, false);
      doc.set('more.tilgangskontroll', AccessAction.view, false);
      doc.set('more.brukergodkjenning', AccessAction.view, false);
    }

    doc.set('more', AccessAction.view, true);
    doc.applyInheritanceRules();
    return doc.toJson();
  }

  /// Bakoverkompatibel flat bool-map (AccessKeys).
  static Map<String, dynamic> toLegacy(
    Map<String, dynamic>? raw,
    UserRole role,
  ) {
    final v2 = toV2(raw, role);
    return AccessSettingsDoc.fromJson(v2).toLegacyBoolMap();
  }
}
