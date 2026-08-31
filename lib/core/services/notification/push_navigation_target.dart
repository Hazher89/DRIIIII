/// Parsed push-varsel som skal åpne riktig sted i appen.
enum PushNavKind {
  partnerRoute,
  partnerDeduction,
  partnerInspection,
  partnerTimesheet,
  hmsTicket,
  hmsRisk,
  hmsSja,
  hmsSafetyRound,
  hmsGeneric,
  unknown,
}

class PushNavigationTarget {
  const PushNavigationTarget({
    required this.kind,
    this.id,
    this.referenceType,
    this.category,
    this.raw = const {},
  });

  final PushNavKind kind;
  final String? id;
  final String? referenceType;
  final String? category;
  final Map<String, String> raw;

  bool get isPartnerScope => switch (kind) {
        PushNavKind.partnerRoute ||
        PushNavKind.partnerDeduction ||
        PushNavKind.partnerInspection ||
        PushNavKind.partnerTimesheet =>
          true,
        _ => false,
      };

  String? get portalTab => switch (kind) {
        PushNavKind.partnerRoute => 'ruter',
        PushNavKind.partnerDeduction ||
        PushNavKind.partnerInspection ||
        PushNavKind.partnerTimesheet =>
          'mer',
        _ => null,
      };

  String? get maviPath => switch (kind) {
        PushNavKind.hmsTicket => '/avvik',
        PushNavKind.hmsRisk => '/hms/risiko',
        PushNavKind.hmsSja => '/hms/sja',
        PushNavKind.hmsSafetyRound => '/hms/vernerunde',
        PushNavKind.hmsGeneric => '/hms',
        PushNavKind.partnerDeduction => '/partners?tab=bot-trekk',
        PushNavKind.partnerInspection => '/partners?tab=bilkontroll',
        _ => null,
      };

  static PushNavigationTarget? fromMap(Map<String, dynamic> data) {
    if (data.isEmpty) return null;

    final type = _str(data['type']) ?? _str(data['category']);
    final routeShareId = _str(data['route_share_id']);
    final caseId = _str(data['case_id']);
    final inspectionId = _str(data['inspection_id']);
    final entryId = _str(data['entry_id']);
    final refType = _str(data['reference_type']);
    final refId = _str(data['reference_id']);

    PushNavKind kind;
    String? id;

    switch (type) {
      case 'partner_route':
        kind = PushNavKind.partnerRoute;
        id = routeShareId ?? refId;
      case 'partner_deduction':
        kind = PushNavKind.partnerDeduction;
        id = caseId ?? refId;
      case 'partner_inspection':
      case 'partner_vehicle_inspection':
        kind = PushNavKind.partnerInspection;
        id = inspectionId ?? refId;
      case 'partner_workforce_punch':
      case 'partner_staff_punch':
        kind = PushNavKind.partnerTimesheet;
        id = entryId ?? refId;
      default:
        if (routeShareId != null) {
          kind = PushNavKind.partnerRoute;
          id = routeShareId;
        } else if (caseId != null) {
          kind = PushNavKind.partnerDeduction;
          id = caseId;
        } else if (inspectionId != null) {
          kind = PushNavKind.partnerInspection;
          id = inspectionId;
        } else if (refType != null && refId != null) {
          kind = _kindFromReferenceType(refType);
          id = refId;
        } else {
          return null;
        }
    }

    final raw = <String, String>{};
    for (final e in data.entries) {
      final v = e.value;
      if (v != null) raw[e.key] = v.toString();
    }

    return PushNavigationTarget(
      kind: kind,
      id: id,
      referenceType: refType,
      category: _str(data['category']),
      raw: raw,
    );
  }

  static PushNavKind _kindFromReferenceType(String refType) {
    switch (refType) {
      case 'tickets':
        return PushNavKind.hmsTicket;
      case 'risk_assessments':
        return PushNavKind.hmsRisk;
      case 'sja_forms':
        return PushNavKind.hmsSja;
      case 'safety_rounds':
        return PushNavKind.hmsSafetyRound;
      default:
        return PushNavKind.hmsGeneric;
    }
  }

  static String? _str(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}
