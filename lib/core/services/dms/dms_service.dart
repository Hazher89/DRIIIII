import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/dms/dms_folder.dart';
import '../../../models/dms/dms_file.dart';
import '../../../models/dms/dms_permission.dart';
import '../supabase_service.dart';

class DmsService {
  static SupabaseClient get client => Supabase.instance.client;

  // ── Folders ──────────────────────────────────────────────────────────────

  static Future<List<DmsFolder>> fetchFolders({String? parentId, required String companyId}) async {
    var query = client.from('dms_folders').select().eq('company_id', companyId);
    if (parentId == null) {
      query = query.filter('parent_id', 'is', null);
    } else {
      query = query.eq('parent_id', parentId);
    }
    
    final data = await query.order('name', ascending: true) as List<dynamic>;
    return data.map((e) => DmsFolder.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<DmsFolder> createFolder({
    required String name,
    String? parentId,
    required String companyId,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Ingen innlogget bruker funnet.');
    
    final data = await client.from('dms_folders').insert({
      'name': name,
      'parent_id': parentId,
      'company_id': companyId,
      'created_by': user.id,
    }).select().single();
    
    return DmsFolder.fromJson(data);
  }

  static Future<void> renameFolder(String id, String newName) async {
    await client.from('dms_folders').update({'name': newName}).eq('id', id);
  }

  static Future<void> deleteFolder(String id) async {
    await client.from('dms_folders').delete().eq('id', id);
  }

  // ── Files ────────────────────────────────────────────────────────────────

  static Future<List<DmsFile>> fetchFiles({String? folderId, required String companyId}) async {
    var query = client.from('dms_files').select().eq('company_id', companyId);
    if (folderId == null) {
      query = query.filter('folder_id', 'is', null);
    } else {
      query = query.eq('folder_id', folderId);
    }
    
    final data = await query.order('name', ascending: true) as List<dynamic>;
    return data.map((e) => DmsFile.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<DmsFile> createFile({
    required String name,
    required String storagePath,
    required int fileSize,
    String? folderId,
    required String companyId,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Ingen innlogget bruker funnet.');
    
    final extension = name.split('.').last;

    final data = await client.from('dms_files').insert({
      'company_id': companyId,
      'folder_id': folderId,
      'name': name,
      'storage_path': storagePath,
      'file_size': fileSize,
      'extension': extension,
      'created_by': user.id,
    }).select().single();

    return DmsFile.fromJson(data);
  }

  static Future<DmsFile> uploadFile({
    required Uint8List bytes,
    required String fileName,
    String? folderId,
    required String companyId,
  }) async {
    final storagePath = 'company_$companyId/${folderId ?? "root"}/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    // 1. Upload to Storage
    try {
      await client.storage.from('documents').uploadBinary(storagePath, bytes);
    } catch (e) {
      await client.storage.from('documents').upload(storagePath, bytes);
    }

    // 2. Create DB Record
    return await createFile(
      name: fileName,
      storagePath: storagePath,
      fileSize: bytes.length,
      folderId: folderId,
      companyId: companyId,
    );
  }

  static Future<void> renameFile(String id, String newName) async {
    await client.from('dms_files').update({'name': newName}).eq('id', id);
  }

  static Future<void> deleteFile(String fileId, String storagePath) async {
    await client.from('dms_files').delete().eq('id', fileId);
    await client.storage.from('documents').remove([storagePath]);
  }

  // ── Advanced Features ──

  static Future<List<DmsFile>> searchAllFiles(String query, String companyId) async {
    final response = await client
        .from('dms_files')
        .select()
        .eq('company_id', companyId)
        .ilike('name', '%$query%')
        .limit(20);
    return (response as List).map((e) => DmsFile.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Map<String, dynamic>> getStorageStats(String companyId) async {
    final response = await client
        .from('dms_files')
        .select('file_size')
        .eq('company_id', companyId);
    
    final files = response as List;
    int totalSize = 0;
    for (var f in files) {
      totalSize += (f['file_size'] as int? ?? 0);
    }
    
    return {
      'total_files': files.length,
      'total_size': totalSize,
    };
  }

  static Future<void> toggleStar(String fileId, bool isStarred) async {
    // Note: requires a 'is_starred' column in the database
    // We can add this to the table if needed
    await client.from('dms_files').update({'is_starred': !isStarred}).eq('id', fileId);
  }

  static Future<String> getDownloadUrl(String storagePath) async {
    return client.storage.from('documents').createSignedUrl(storagePath, 3600);
  }

  // ── Permissions ──────────────────────────────────────────────────────────

  static Future<void> grantPermission({
    String? folderId,
    String? fileId,
    required String userId,
    required DmsPermissionType type,
  }) async {
    await client.from('dms_permissions').upsert({
      'folder_id': folderId,
      'file_id': fileId,
      'user_id': userId,
      'permission_type': type.name,
    });
  }

  static Future<List<DmsPermission>> fetchPermissions({String? folderId, String? fileId}) async {
    var query = client.from('dms_permissions').select();
    if (folderId != null) query = query.eq('folder_id', folderId);
    if (fileId != null) query = query.eq('file_id', fileId);
    
    final data = await query as List<dynamic>;
    return data.map((e) => DmsPermission.fromJson(e as Map<String, dynamic>)).toList();
  }
}
