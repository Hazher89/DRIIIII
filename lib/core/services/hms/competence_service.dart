import '../../../models/hms/competence_course.dart';
import '../../../models/hms_document.dart';
import '../supabase_service.dart';

class CompetenceService {
  CompetenceService._();

  static Future<List<CompetenceCourse>> fetchCourses(String companyId) async {
    final data = await SupabaseService.client
        .from('competence_courses')
        .select()
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('sort_order')
        .order('name');
    return (data as List)
        .map((e) => CompetenceCourse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> seedDefaults(String companyId) async {
    try {
      await SupabaseService.client.rpc(
        'seed_default_competence_courses',
        params: {'p_company_id': companyId},
      );
    } catch (_) {
      // RPC may not exist yet
    }
  }

  static Future<CompetenceCourse> saveCourse(CompetenceCourse course) async {
    if (course.id.isEmpty) {
      final row = await SupabaseService.client
          .from('competence_courses')
          .insert(course.toJson())
          .select()
          .single();
      return CompetenceCourse.fromJson(row);
    }
    final row = await SupabaseService.client
        .from('competence_courses')
        .update(course.toJson())
        .eq('id', course.id)
        .select()
        .single();
    return CompetenceCourse.fromJson(row);
  }

  static Future<List<HmsDocument>> fetchCompetenceDocuments({
    required String companyId,
    String? userId,
    String? courseId,
  }) async {
    var q = SupabaseService.client
        .from('documents')
        .select()
        .eq('company_id', companyId);
    if (userId != null) q = q.eq('user_id', userId);
    if (courseId != null) q = q.eq('course_id', courseId);
    final data = await q.order('created_at', ascending: false);
    return (data as List)
        .map((e) => HmsDocument.fromJson(e as Map<String, dynamic>))
        .where(
          (d) =>
              d.documentType == HmsDocumentType.kursbevis ||
              d.documentType == HmsDocumentType.sertifikat ||
              d.courseId != null,
        )
        .toList();
  }
}
