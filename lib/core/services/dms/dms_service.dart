import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/dms/dms_folder.dart';
import '../../../models/dms/dms_file.dart';
import '../../../models/dms/dms_permission.dart';
import '../../utils/file_type_resolver.dart';
import '../storage/company_file_storage.dart';
import '../storage/storage_file_access.dart';
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

  static Future<DmsFolder?> fetchFolder(String id) async {
    final row = await client.from('dms_folders').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return DmsFolder.fromJson(row);
  }

  static Future<DmsFolder> createFolder({
    required String name,
    String? parentId,
    required String companyId,
    String? description,
    String? passwordHash,
    bool isPrivate = false,
    bool isSharedMavi = false,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Ingen innlogget bruker funnet.');

    final payload = <String, dynamic>{
      'name': name,
      'parent_id': parentId,
      'company_id': companyId,
      'created_by': user.id,
      'is_private': isPrivate,
      'is_shared_mavi': isSharedMavi,
    };
    if (description != null && description.isNotEmpty) {
      payload['description'] = description;
    }
    if (passwordHash != null && passwordHash.isNotEmpty) {
      payload['password_hash'] = passwordHash;
    }

    Map<String, dynamic> data;
    try {
      data = await client.from('dms_folders').insert(payload).select().single();
    } catch (e) {
      payload.remove('password_hash');
      payload.remove('is_private');
      payload.remove('is_shared_mavi');
      payload.remove('description');
      data = await client.from('dms_folders').insert({
        'name': name,
        'parent_id': parentId,
        'company_id': companyId,
        'created_by': user.id,
      }).select().single();
    }

    return DmsFolder.fromJson(data);
  }

  /// Opprett mappe + deling til ansatte/avdelinger i én operasjon.
  static Future<DmsFolder> createFolderWithSharing({
    required String name,
    String? parentId,
    required String companyId,
    String? description,
    String? passwordHash,
    bool isPrivate = false,
    bool isSharedMavi = false,
    List<String> shareUserIds = const [],
    List<String> shareDepartmentIds = const [],
  }) async {
    final folder = await createFolder(
      name: name,
      parentId: parentId,
      companyId: companyId,
      description: description,
      passwordHash: passwordHash,
      isPrivate: isPrivate,
      isSharedMavi: isSharedMavi,
    );
    if (isSharedMavi) {
      await grantPermissionToAllMaviEmployees(
        folderId: folder.id,
        companyId: companyId,
      );
    }
    for (final uid in shareUserIds) {
      await grantPermission(
        folderId: folder.id,
        userId: uid,
        type: DmsPermissionType.read,
      );
    }
    for (final deptId in shareDepartmentIds) {
      await grantPermissionToDepartment(
        folderId: folder.id,
        departmentId: deptId,
        companyId: companyId,
      );
    }
    return folder;
  }

  static Future<void> updateFolder(
    String id, {
    String? name,
    String? description,
    String? passwordHash,
    bool clearPassword = false,
    bool? isPrivate,
  }) async {
    final patch = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (name != null) patch['name'] = name;
    if (description != null) patch['description'] = description;
    if (clearPassword) {
      patch['password_hash'] = null;
    } else if (passwordHash != null) {
      patch['password_hash'] = passwordHash;
    }
    if (isPrivate != null) patch['is_private'] = isPrivate;
    await client.from('dms_folders').update(patch).eq('id', id);
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
    String storageProvider = 'supabase',
    String? externalUrl,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Ingen innlogget bruker funnet.');
    
    final extension = FileTypeResolver.extensionFromName(name) ??
        FileTypeResolver.extensionFromStoragePath(storagePath);

    final data = await client.from('dms_files').insert({
      'company_id': companyId,
      'folder_id': folderId,
      'name': name,
      'storage_path': storagePath,
      'file_size': fileSize,
      'extension': extension,
      'created_by': user.id,
      'storage_provider': storageProvider,
      if (externalUrl != null) 'external_url': externalUrl,
      'file_size_bytes': fileSize,
    }).select().single();

    return DmsFile.fromJson(data);
  }

  static Future<DmsFile> uploadFile({
    required Uint8List bytes,
    required String fileName,
    String? folderId,
    required String companyId,
  }) async {
    final storagePath =
        'company_$companyId/${folderId ?? "root"}/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    final stored = await CompanyFileStorage.upload(
      supabaseBucket: 'documents',
      storagePath: storagePath,
      bytes: bytes,
      category: 'dms',
      fileName: fileName,
    );

    return createFile(
      name: fileName,
      storagePath: CompanyFileStorage.toStorageReference(stored),
      fileSize: bytes.length,
      folderId: folderId,
      companyId: companyId,
      storageProvider: stored.provider,
      externalUrl: stored.publicOrSignedUrl,
    );
  }

  static Future<void> renameFile(String id, String newName) async {
    await client.from('dms_files').update({'name': newName}).eq('id', id);
  }

  static Future<void> moveFile(String fileId, String? targetFolderId) async {
    await client
        .from('dms_files')
        .update({'folder_id': targetFolderId})
        .eq('id', fileId);
  }

  static Future<int> countFolderContents(String folderId, String companyId) async {
    final sub = await client
        .from('dms_folders')
        .select('id')
        .eq('parent_id', folderId)
        .eq('company_id', companyId);
    final files = await client
        .from('dms_files')
        .select('id')
        .eq('folder_id', folderId)
        .eq('company_id', companyId);
    return (sub as List).length + (files as List).length;
  }

  static Future<void> deleteFile(String fileId, String storagePath) async {
    await client.from('dms_files').delete().eq('id', fileId);
    await client.storage.from('documents').remove([storagePath]);
  }

  // ── Advanced Features ──

  static Future<List<DmsFolder>> fetchSharedMaviFolders(String companyId) async {
    final data = await client
        .from('dms_folders')
        .select()
        .eq('company_id', companyId)
        .eq('is_shared_mavi', true)
        .order('name', ascending: true) as List<dynamic>;
    return data.map((e) => DmsFolder.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<DmsFolder>> fetchAllFolders(String companyId) async {
    final data = await client
        .from('dms_folders')
        .select()
        .eq('company_id', companyId)
        .order('name', ascending: true) as List<dynamic>;
    return data.map((e) => DmsFolder.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<DmsFile>> fetchStarredFiles(String companyId) async {
    final data = await client
        .from('dms_files')
        .select()
        .eq('company_id', companyId)
        .eq('is_starred', true)
        .order('updated_at', ascending: false)
        .limit(100) as List<dynamic>;
    return data.map((e) => DmsFile.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<DmsFile>> fetchRecentFiles(String companyId, {int limit = 50}) async {
    final data = await client
        .from('dms_files')
        .select()
        .eq('company_id', companyId)
        .order('updated_at', ascending: false)
        .limit(limit) as List<dynamic>;
    return data.map((e) => DmsFile.fromJson(e as Map<String, dynamic>)).toList();
  }

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

  static Future<String> getDownloadUrl(
    String storagePath, {
    String? storageProvider,
  }) async {
    if (storageProvider == 'dropbox' ||
        CompanyFileStorage.isDropboxReference(storagePath)) {
      return CompanyFileStorage.resolveDisplayUrl(storagePath);
    }
    return StorageFileAccess.resolveViewUrl(storagePath);
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

  static Future<void> revokePermission({
    String? folderId,
    String? fileId,
    required String userId,
  }) async {
    var q = client.from('dms_permissions').delete().eq('user_id', userId);
    if (folderId != null) q = q.eq('folder_id', folderId);
    if (fileId != null) q = q.eq('file_id', fileId);
    await q;
  }

  /// Gir alle ansatte i avdelingen lesetilgang automatisk.
  static Future<int> grantPermissionToDepartment({
    String? folderId,
    String? fileId,
    required String departmentId,
    required String companyId,
    DmsPermissionType type = DmsPermissionType.read,
  }) async {
    final employees = (await SupabaseService.fetchMaviEmployees(companyId: companyId))
        .where((p) => p.departmentId == departmentId)
        .toList();
    for (final p in employees) {
      await grantPermission(
        folderId: folderId,
        fileId: fileId,
        userId: p.id,
        type: type,
      );
    }
    return employees.length;
  }

  /// Felles mappe — gi lesetilgang til alle interne MAVI-ansatte.
  static Future<int> grantPermissionToAllMaviEmployees({
    required String folderId,
    required String companyId,
    DmsPermissionType type = DmsPermissionType.read,
  }) async {
    final employees = await SupabaseService.fetchMaviEmployees(companyId: companyId);
    for (final p in employees) {
      await grantPermission(
        folderId: folderId,
        userId: p.id,
        type: type,
      );
    }
    return employees.length;
  }

  static Future<Uint8List> downloadFileBytes(
    String storagePath, {
    String? storageProvider,
  }) async {
    if (storageProvider == 'dropbox' ||
        CompanyFileStorage.isDropboxReference(storagePath)) {
      final url = await CompanyFileStorage.resolveDisplayUrl(storagePath);
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        throw StateError('Kunne ikke hente fil fra Dropbox');
      }
      return res.bodyBytes;
    }
    final path = storagePath.replaceFirst(RegExp(r'^/'), '');
    return client.storage.from('documents').download(path);
  }

  static Future<List<DmsPermission>> fetchPermissions({String? folderId, String? fileId}) async {
    var query = client.from('dms_permissions').select();
    if (folderId != null) query = query.eq('folder_id', folderId);
    if (fileId != null) query = query.eq('file_id', fileId);
    
    final data = await query as List<dynamic>;
    return data.map((e) => DmsPermission.fromJson(e as Map<String, dynamic>)).toList();
  }
}
