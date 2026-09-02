import '../supabase_service.dart';
import 'assistant_memory_service.dart';

/// Skriver lærte fakta når noe skjer i drift — ikke bare når noen chatter.
abstract final class AssistantEventLearning {
  /// Rute publisert/sendt til bil/sjåfør.
  static Future<void> onRouteDispatched({
    required String companyId,
    required int routeCount,
    List<String> vehicleLabels = const [],
    DateTime? routeDate,
  }) async {
    if (routeCount <= 0) return;
    final day = routeDate ?? DateTime.now();
    final d =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final vehicles = vehicleLabels.where((e) => e.trim().isNotEmpty).toList();
    final vehiclePart = vehicles.isEmpty
        ? ''
        : ' Biler: ${vehicles.take(12).join(', ')}'
            '${vehicles.length > 12 ? '…' : ''}.';
    await AssistantMemoryService.remember(
      companyId: companyId,
      kind: 'route_event',
      subjectKey: 'route:$d',
      content:
          'Ruteutsending $d: $routeCount rute(r) publisert.$vehiclePart',
      visibility: 'company',
      sourceQuery: 'event:route_dispatch',
    );
  }

  /// Fravær/ferie godkjent eller avvist.
  static Future<void> onAbsenceDecision({
    required String companyId,
    required String userId,
    required String employeeName,
    required String typeLabel,
    required String statusLabel,
    required DateTime start,
    required DateTime end,
    String? departmentId,
  }) async {
    final range =
        '${_d(start)}–${_d(end)}';
    final visibility = departmentId != null && departmentId.isNotEmpty
        ? 'department:$departmentId'
        : 'principals';
    await AssistantMemoryService.remember(
      companyId: companyId,
      kind: 'leave_event',
      subjectKey: 'leave:$userId',
      subjectUserId: userId,
      content:
          '$employeeName: $typeLabel $statusLabel ($range).',
      visibility: visibility,
      sourceQuery: 'event:absence_decision',
    );
  }

  /// Vernerunde fullført/arkivert.
  static Future<void> onSafetyRoundCompleted({
    required String companyId,
    required String title,
    String? location,
    String? archiveNumber,
    String? conductorName,
  }) async {
    final loc = (location ?? '').trim();
    final ark = (archiveNumber ?? '').trim();
    final who = (conductorName ?? '').trim();
    await AssistantMemoryService.remember(
      companyId: companyId,
      kind: 'hms_event',
      subjectKey: 'safety_round',
      content:
          'Vernerunde fullført: «$title»'
          '${loc.isEmpty ? '' : ' ($loc)'}'
          '${ark.isEmpty ? '' : ', arkiv $ark'}'
          '${who.isEmpty ? '' : ' — $who'}.',
      visibility: 'company',
      sourceQuery: 'event:safety_round_complete',
    );
  }

  static String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}
