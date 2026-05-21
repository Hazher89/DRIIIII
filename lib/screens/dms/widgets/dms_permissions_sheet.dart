import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/dms/dms_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/department.dart';
import '../../../models/dms/dms_file.dart';
import '../../../models/dms/dms_folder.dart';
import '../../../models/dms/dms_permission.dart';
import '../../../models/user_profile.dart';

class DmsPermissionsSheet extends StatefulWidget {
  final DmsFolder? folder;
  final DmsFile? file;
  final String companyId;

  const DmsPermissionsSheet({
    super.key,
    this.folder,
    this.file,
    required this.companyId,
  });

  static void show(
    BuildContext context, {
    DmsFolder? folder,
    DmsFile? file,
    required String companyId,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DmsPermissionsSheet(
        folder: folder,
        file: file,
        companyId: companyId,
      ),
    );
  }

  @override
  State<DmsPermissionsSheet> createState() => _DmsPermissionsSheetState();
}

class _DmsPermissionsSheetState extends State<DmsPermissionsSheet>
    with SingleTickerProviderStateMixin {
  List<DmsPermission> _permissions = [];
  List<UserProfile> _allUsers = [];
  List<Department> _departments = [];
  bool _isLoading = true;
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final res = await Future.wait([
      DmsService.fetchPermissions(
        folderId: widget.folder?.id,
        fileId: widget.file?.id,
      ),
      SupabaseService.fetchProfiles(companyId: widget.companyId),
      SupabaseService.fetchDepartments(companyId: widget.companyId),
    ]);
    if (!mounted) return;
    setState(() {
      _permissions = res[0] as List<DmsPermission>;
      _allUsers = (res[1] as List<UserProfile>)
          .where((u) => u.isApproved && !u.isPartnerPortalUser)
          .toList();
      _departments = res[2] as List<Department>;
      _isLoading = false;
    });
  }

  Future<void> _toggleUser(UserProfile user, bool grant) async {
    if (grant) {
      await DmsService.grantPermission(
        folderId: widget.folder?.id,
        fileId: widget.file?.id,
        userId: user.id,
        type: DmsPermissionType.read,
      );
    } else {
      await DmsService.revokePermission(
        folderId: widget.folder?.id,
        fileId: widget.file?.id,
        userId: user.id,
      );
    }
    await _load();
  }

  Future<void> _shareDepartment(Department dept) async {
    final n = await DmsService.grantPermissionToDepartment(
      folderId: widget.folder?.id,
      fileId: widget.file?.id,
      departmentId: dept.id,
      companyId: widget.companyId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tilgang gitt til $n ansatte i ${dept.name}')),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.folder?.name ?? widget.file?.name ?? 'element';

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Del & tilgang: $title', style: DriftProTheme.headingMd),
          const SizedBox(height: 4),
          const Text(
            'Valgte ansatte og avdelinger får automatisk tilgang.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          if (widget.file != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  try {
                    final url = await DmsService.getDownloadUrl(
                      widget.file!.storagePath,
                      storageProvider: widget.file!.storageProvider,
                    );
                    await Clipboard.setData(ClipboardData(text: url));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Lenke kopiert')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Feil: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.link),
                label: const Text('Kopier nedlastingslenke'),
              ),
            ),
          TabBar(
            controller: _tabs,
            tabs: const [Tab(text: 'Ansatte'), Tab(text: 'Avdelinger')],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [
                      ListView.builder(
                        itemCount: _allUsers.length,
                        itemBuilder: (_, i) {
                          final user = _allUsers[i];
                          final hasAccess =
                              _permissions.any((p) => p.userId == user.id);
                          return SwitchListTile(
                            title: Text(user.fullName),
                            subtitle: Text(user.email),
                            value: hasAccess,
                            onChanged: (v) => _toggleUser(user, v),
                          );
                        },
                      ),
                      ListView.builder(
                        itemCount: _departments.length,
                        itemBuilder: (_, i) {
                          final d = _departments[i];
                          final count = _allUsers
                              .where((u) => u.departmentId == d.id)
                              .length;
                          return ListTile(
                            leading: const Icon(Icons.groups_outlined),
                            title: Text(d.name),
                            subtitle: Text('$count ansatte'),
                            trailing: FilledButton(
                              onPressed: () => _shareDepartment(d),
                              child: const Text('Del med alle'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
