import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../models/hms/hms_sja_step.dart';
import '../../../models/hms/hms_ticket_template.dart';
import '../../../models/risk_assessment.dart';
import '../../../models/sja_form.dart';
import '../../../models/ticket.dart';
import '../storage/company_file_storage.dart';
import '../supabase_service.dart';

/// Sentral HMS-API mot Supabase (Avvik, ROS, SJA og koblinger).
class HmsEcosystemService {
  HmsEcosystemService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static bool get isConfigured => SupabaseService.isConfigured;

  // ── Avvik ────────────────────────────────────────────────────────────────

  static Future<List<HmsTicketTemplate>> fetchTicketTemplates({
    String? companyId,
  }) async {
    if (!isConfigured) return const [];
    var query = _client.from('hms_ticket_templates').select();
    if (companyId != null) {
      query = query.or('company_id.is.null,company_id.eq.$companyId');
    } else {
      query = query.isFilter('company_id', null);
    }
    final data = await query.order('sort_order') as List<dynamic>;
    return data
        .map((e) => HmsTicketTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String avvikStoragePath(String companyId) {
    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    return '$companyId/avvik/$year/$month/${const Uuid().v4()}.jpg';
  }

  static Future<String> uploadAvvikMedia({
    required String companyId,
    required Uint8List bytes,
    String extension = 'jpg',
  }) async {
    final now = DateTime.now();
    final fileName = '${const Uuid().v4()}.$extension';
    final path =
        '$companyId/avvik/${now.year}/${now.month.toString().padLeft(2, '0')}/$fileName';
    final stored = await CompanyFileStorage.upload(
      supabaseBucket: 'avvik',
      storagePath: path,
      bytes: bytes,
      category: 'tickets',
      fileName: fileName,
    );
    return CompanyFileStorage.toStorageReference(stored);
  }

  static Future<String> uploadRiskAssessmentFile({
    required String companyId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        '$companyId/ros/${DateTime.now().year}/${const Uuid().v4()}_$safeName';
    final stored = await CompanyFileStorage.upload(
      supabaseBucket: 'risk-assessments',
      storagePath: path,
      bytes: bytes,
      category: 'risk',
      fileName: fileName,
    );
    return CompanyFileStorage.toStorageReference(stored);
  }

  static Future<List<HmsTicketLeaderAction>> fetchLeaderActions(
    String ticketId,
  ) async {
    final data = await _client
        .from('hms_ticket_leader_actions')
        .select('*, profiles(full_name)')
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: false) as List<dynamic>;
    return data
        .map((e) => HmsTicketLeaderAction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> addLeaderAction({
    required String ticketId,
    required String companyId,
    required String actionType,
    required String body,
    Map<String, dynamic> metadata = const {},
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Ikke innlogget');
    await _client.from('hms_ticket_leader_actions').insert({
      'ticket_id': ticketId,
      'company_id': companyId,
      'actor_id': userId,
      'action_type': actionType,
      'body': body,
      'metadata': metadata,
    });
  }

  static Future<void> escalateTicket({
    required String ticketId,
    required String escalatedTo,
    required String reason,
  }) async {
    await _client.from('tickets').update({
      'escalated_to': escalatedTo,
      'escalated_at': DateTime.now().toIso8601String(),
      'escalation_reason': reason,
      'status': TicketStatus.underBehandling.dbValue,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', ticketId);
  }

  static Future<HmsTicketSensitive?> fetchTicketSensitive(
    String ticketId,
  ) async {
    try {
      final row = await _client
          .from('hms_ticket_sensitive')
          .select()
          .eq('ticket_id', ticketId)
          .maybeSingle();
      if (row == null) return null;
      return HmsTicketSensitive.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  static Future<void> upsertTicketSensitive({
    required HmsTicketSensitive data,
    required String companyId,
    required String createdBy,
  }) async {
    await _client.from('hms_ticket_sensitive').upsert(
      data.toUpsertJson(companyId: companyId, createdBy: createdBy),
      onConflict: 'ticket_id',
    );
  }

  // ── ROS ──────────────────────────────────────────────────────────────────

  static Future<List<HmsRosTemplate>> fetchRosTemplates({
    String? companyId,
  }) async {
    if (!isConfigured) return const [];
    var query = _client.from('hms_ros_templates').select();
    if (companyId != null) {
      query = query.or('company_id.is.null,company_id.eq.$companyId');
    }
    final data = await query.order('sort_order') as List<dynamic>;
    return data
        .map((e) => HmsRosTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<HmsRosAvvikSignal>> fetchActiveRosSignals(
    String companyId,
  ) async {
    final data = await _client
        .from('hms_ros_avvik_signals')
        .select()
        .eq('company_id', companyId)
        .eq('status', 'active')
        .order('created_at', ascending: false) as List<dynamic>;
    return data
        .map((e) => HmsRosAvvikSignal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<RiskAssessment?> fetchRiskAssessmentById(String id) async {
    return SupabaseService.fetchRiskAssessmentById(id);
  }

  static Future<void> updateRiskAssessment(
    String id,
    Map<String, dynamic> patch,
  ) async {
    final merged = Map<String, dynamic>.from(patch);
    merged['updated_at'] = DateTime.now().toIso8601String();
    await _client.from('risk_assessments').update(merged).eq('id', id);
  }

  static Future<void> acknowledgeRosSignal(String signalId) async {
    await _client.from('hms_ros_avvik_signals').update({
      'status': 'acknowledged',
      'acknowledged_by': _client.auth.currentUser?.id,
      'acknowledged_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', signalId);
  }

  // ── SJA ──────────────────────────────────────────────────────────────────

  static Future<SjaForm?> fetchSjaById(String id) async {
    return SupabaseService.fetchSjaFormById(id);
  }

  static Future<SjaForm?> fetchSjaByQrToken(String token) async {
    final row = await _client
        .from('sja_forms')
        .select('*, profiles(full_name)')
        .eq('qr_token', token)
        .maybeSingle();
    if (row == null) return null;
    return SjaForm.fromJson(row);
  }

  static Future<List<HmsSjaStep>> fetchSjaSteps(String sjaId) async {
    final data = await _client
        .from('hms_sja_steps')
        .select()
        .eq('sja_id', sjaId)
        .order('step_order') as List<dynamic>;
    return data
        .map((e) => HmsSjaStep.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<HmsSjaSignature>> fetchSjaSignatures(String sjaId) async {
    final data = await _client
        .from('hms_sja_signatures')
        .select('*, profiles(full_name)')
        .eq('sja_id', sjaId)
        .order('signed_at') as List<dynamic>;
    return data
        .map((e) => HmsSjaSignature.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> replaceSjaSteps({
    required String sjaId,
    required String companyId,
    required List<HmsSjaStep> steps,
  }) async {
    await _client.from('hms_sja_steps').delete().eq('sja_id', sjaId);
    if (steps.isEmpty) return;
    await _client.from('hms_sja_steps').insert(
      steps
          .map((s) => s.toInsertJson(companyId: companyId))
          .toList(growable: false),
    );
  }

  static Future<String> registerSjaSignature({
    required String sjaId,
    String method = 'digital',
    String? signatureUrl,
    bool pinVerified = false,
  }) async {
    final result = await _client.rpc(
      'hms_register_sja_signature',
      params: {
        'p_sja_id': sjaId,
        'p_method': method,
        'p_signature_url': signatureUrl,
        'p_pin_verified': pinVerified,
        'p_device_info': {},
      },
    );
    return result?.toString() ?? '';
  }

  static Future<void> startSjaWork(String sjaId) async {
    await _client.rpc('hms_start_sja_work', params: {'p_sja_id': sjaId});
  }

  static Future<void> saveSjaAsTemplate({
    required SjaForm sja,
    required List<HmsSjaStep> steps,
    required String templateKey,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Ikke innlogget');
    await _client.from('hms_sja_templates').upsert({
      'company_id': sja.companyId,
      'department_id': sja.departmentId,
      'created_by': userId,
      'source_sja_id': sja.id,
      'template_key': templateKey,
      'title': sja.title,
      'work_description': sja.workDescription,
      'location': sja.location,
      'required_ppe': sja.requiredPpe,
      'steps': steps
          .map((s) => {
                'operation': s.operation,
                'hazard': s.hazard,
                'measure': s.measure,
                'probability': s.probability,
                'consequence': s.consequence,
              })
          .toList(),
      'hazards': sja.hazards,
      'measures': sja.measures,
      'active_window_hours': sja.activeWindowHours,
    }, onConflict: 'company_id,template_key');
  }

  // ── Offline ──────────────────────────────────────────────────────────────

  static Future<String> enqueueOfflineSync({
    required String entityType,
    required String clientId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    final result = await _client.rpc(
      'hms_enqueue_offline_sync',
      params: {
        'p_entity_type': entityType,
        'p_client_id': clientId,
        'p_operation': operation,
        'p_payload': payload,
      },
    );
    return result?.toString() ?? '';
  }
}

class HmsRosTemplate {
  final String id;
  final String templateKey;
  final String title;
  final String? description;
  final String? area;
  final String? scenarioCategory;
  final int initialProbability;
  final int initialConsequence;
  final String? existingMeasures;
  final String? proposedMeasures;

  const HmsRosTemplate({
    required this.id,
    required this.templateKey,
    required this.title,
    this.description,
    this.area,
    this.scenarioCategory,
    this.initialProbability = 3,
    this.initialConsequence = 3,
    this.existingMeasures,
    this.proposedMeasures,
  });

  factory HmsRosTemplate.fromJson(Map<String, dynamic> json) {
    return HmsRosTemplate(
      id: json['id'] as String,
      templateKey: json['template_key'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      area: json['area'] as String?,
      scenarioCategory: json['scenario_category'] as String?,
      initialProbability: json['initial_probability'] as int? ?? 3,
      initialConsequence: json['initial_consequence'] as int? ?? 3,
      existingMeasures: json['existing_measures'] as String?,
      proposedMeasures: json['proposed_measures'] as String?,
    );
  }
}
