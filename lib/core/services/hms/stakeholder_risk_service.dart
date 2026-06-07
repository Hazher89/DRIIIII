import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/hms/stakeholder_risk_assessment.dart';
import '../../hms/stakeholder_risk_template_loader.dart';

class StakeholderRiskService {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<List<StakeholderRiskAssessment>> fetchAll(String companyId) async {
    final data = await client
        .from('stakeholder_risk_assessments')
        .select()
        .eq('company_id', companyId)
        .order('updated_at', ascending: false) as List<dynamic>;
    return data
        .map((e) => StakeholderRiskAssessment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<StakeholderRiskAssessment?> fetchById(String id) async {
    final row = await client
        .from('stakeholder_risk_assessments')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return StakeholderRiskAssessment.fromJson(row);
  }

  static Future<StakeholderRiskAssessment> createFromTemplate({
    required String companyId,
    required String createdBy,
    String? title,
    int? year,
  }) async {
    final content = await StakeholderRiskTemplateLoader.loadTemplate();
    final assessment = StakeholderRiskAssessment(
      id: '',
      companyId: companyId,
      createdBy: createdBy,
      title: title ?? 'Interessepart og risikovurdering ${year ?? DateTime.now().year}',
      assessmentYear: year ?? DateTime.now().year,
      status: 'aktiv',
      content: content,
    );
    final data = await client
        .from('stakeholder_risk_assessments')
        .insert(assessment.toInsertJson())
        .select()
        .single();
    return StakeholderRiskAssessment.fromJson(data);
  }

  static Future<StakeholderRiskAssessment> update(
    StakeholderRiskAssessment assessment,
  ) async {
    final data = await client
        .from('stakeholder_risk_assessments')
        .update(assessment.toUpdateJson())
        .eq('id', assessment.id)
        .select()
        .single();
    return StakeholderRiskAssessment.fromJson(data);
  }

  static Future<void> delete(String id) async {
    await client.from('stakeholder_risk_assessments').delete().eq('id', id);
  }
}
