import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../models/hms_document.dart';
import '../supabase_service.dart';

class EmployeeDocumentService {
  EmployeeDocumentService._();

  static Future<List<HmsDocument>> fetchForUser({
    required String userId,
    String? companyId,
    bool employeeVisibleOnly = false,
  }) async {
    var q = SupabaseService.client.from('documents').select().eq('user_id', userId);
    if (companyId != null) q = q.eq('company_id', companyId);
    if (employeeVisibleOnly) q = q.eq('employee_visible', true);
    final data = await q.order('created_at', ascending: false);
    return (data as List)
        .map((e) => HmsDocument.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<String> uploadFile({
    required String companyId,
    required String userId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final path =
        '$companyId/employee_files/$userId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    return SupabaseService.uploadFile('documents', path, bytes);
  }

  /// Superadmin/leder laster opp for ansatt.
  static Future<HmsDocument> uploadForEmployee({
    required String userId,
    required String companyId,
    required String uploadedBy,
    required HmsDocumentType type,
    required String title,
    required String fileUrl,
    String? fileName,
    int? fileSize,
    String? description,
    DateTime? expiresAt,
    bool employeeVisible = false,
    String? courseId,
    List<String> tags = const [],
  }) async {
    try {
      final id = await SupabaseService.client.rpc(
        'upsert_employee_document',
        params: {
          'p_user_id': userId,
          'p_company_id': companyId,
          'p_document_type': type.name,
          'p_title': title,
          'p_file_url': fileUrl,
          'p_file_name': fileName,
          'p_file_size': fileSize,
          'p_description': description,
          'p_expires_at': expiresAt?.toIso8601String().split('T').first,
          'p_employee_visible': employeeVisible,
          'p_course_id': courseId,
          'p_tags': tags,
        },
      );
      final row = await SupabaseService.client
          .from('documents')
          .select()
          .eq('id', id)
          .single();
      return HmsDocument.fromJson(row);
    } catch (_) {
      // Fallback: egen insert hvis RPC mangler
      final row = await SupabaseService.client
          .from('documents')
          .insert({
            'id': const Uuid().v4(),
            'user_id': userId,
            'company_id': companyId,
            'document_type': type.name,
            'title': title,
            'file_url': fileUrl,
            'file_name': fileName,
            'file_size': fileSize,
            'description': description,
            'expires_at': expiresAt?.toIso8601String().split('T').first,
            'uploaded_by': uploadedBy,
            'employee_visible': employeeVisible,
            if (courseId != null) 'course_id': courseId,
            'tags': tags,
          })
          .select()
          .single();
      return HmsDocument.fromJson(row);
    }
  }

  static Future<void> setEmployeeVisible({
    required String documentId,
    required bool visible,
  }) async {
    await SupabaseService.client
        .from('documents')
        .update({'employee_visible': visible})
        .eq('id', documentId);
  }

  static Future<void> deleteDocument(String documentId) async {
    await SupabaseService.client.from('documents').delete().eq('id', documentId);
  }
}
