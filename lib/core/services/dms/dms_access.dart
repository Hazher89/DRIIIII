import '../../../models/dms/dms_folder.dart';
import '../../../models/dms/dms_permission.dart';
import '../../../models/user_profile.dart';

/// Tilgangskontroll for DMS — kun MAVI-ansatte (ikke samarbeidspartnere).
class DmsAccess {
  DmsAccess._();

  static bool canAccessFolder(
    DmsFolder folder, {
    required UserProfile? user,
    Iterable<DmsPermission> permissions = const [],
  }) {
    if (user == null) return false;
    if (user.isPartnerPortalUser) return false;
    if (user.isAdmin) return true;
    if (!user.isMaviEmployee) return false;
    if (folder.isSharedMavi) return true;
    if (!folder.isPrivate) return true;
    if (folder.createdBy == user.id) return true;
    return permissions.any((p) => p.userId == user.id);
  }

  static List<DmsFolder> filterVisibleFolders(
    Iterable<DmsFolder> folders, {
    required UserProfile? user,
    Map<String, List<DmsPermission>> permissionsByFolderId = const {},
  }) {
    return folders
        .where(
          (f) => canAccessFolder(
            f,
            user: user,
            permissions: permissionsByFolderId[f.id] ?? const [],
          ),
        )
        .toList();
  }
}
