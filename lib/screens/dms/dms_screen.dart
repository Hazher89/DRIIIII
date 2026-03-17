import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/dms/dms_service.dart';
import '../../core/services/supabase_service.dart';
import '../../models/dms/dms_folder.dart';
import '../../models/dms/dms_file.dart';
import '../../models/dms/dms_permission.dart';
import '../../models/user_profile.dart';
import '../../core/constants/app_strings.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'file_viewer_screen.dart';

class DmsScreen extends StatefulWidget {
  final String? initialFolderId;
  final String? initialFolderName;

  const DmsScreen({super.key, this.initialFolderId, this.initialFolderName});

  @override
  State<DmsScreen> createState() => _DmsScreenState();
}

enum DmsViewMode { grid, list }
enum DmsCategory { all, recent, starred, shared, images, docs }

class _DmsScreenState extends State<DmsScreen> {
  bool _isLoading = true;
  List<DmsFolder> _folders = [];
  List<DmsFile> _files = [];
  
  String? _currentFolderId;
  List<Map<String, String?>> _breadcrumb = [];
  String? _companyId;
  
  DmsViewMode _viewMode = DmsViewMode.grid;
  DmsCategory _activeCategory = DmsCategory.all;
  String _searchQuery = '';
  Set<String> _selectedItems = {};
  bool _isDragging = false;
  Map<String, dynamic> _stats = {'total_files': 0, 'total_size': 0};

  @override
  void initState() {
    super.initState();
    _currentFolderId = widget.initialFolderId;
    _breadcrumb.add({'id': null, 'name': 'Hovedarkiv'});
    if (widget.initialFolderId != null) {
      _breadcrumb.add({'id': widget.initialFolderId, 'name': widget.initialFolderName});
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _companyId ??= await SupabaseService.getCurrentCompanyId();
      if (_companyId == null) return;

      final foldersFut = DmsService.fetchFolders(parentId: _currentFolderId, companyId: _companyId!);
      final filesFut = DmsService.fetchFiles(folderId: _currentFolderId, companyId: _companyId!);
      final statsFut = DmsService.getStorageStats(_companyId!);

      final results = await Future.wait([foldersFut, filesFut, statsFut]);
      
      setState(() {
        _folders = results[0] as List<DmsFolder>;
        _files = results[1] as List<DmsFile>;
        _stats = results[2] as Map<String, dynamic>;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil ved lasting: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToFolder(String? id, String name) {
    setState(() {
      _currentFolderId = id;
      _activeCategory = DmsCategory.all;
      final index = _breadcrumb.indexWhere((element) => element['id'] == id);
      if (index != -1) {
        _breadcrumb = _breadcrumb.sublist(0, index + 1);
      } else {
        _breadcrumb.add({'id': id, 'name': name});
      }
    });
    _loadData();
  }

  List<dynamic> get _filteredItems {
    if (_searchQuery.isEmpty) return [..._folders, ..._files];
    return [..._folders, ..._files].where((item) {
      final name = item is DmsFolder ? item.name : (item as DmsFile).name;
      return name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> _performGlobalSearch(String query) async {
    if (query.length < 3) return;
    setState(() => _isLoading = true);
    try {
      final files = await DmsService.searchAllFiles(query, _companyId!);
      setState(() {
        _activeCategory = DmsCategory.all;
        _files = files;
        _folders = []; 
      });
    } catch (e) {
      debugPrint('Search error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.bgLight,
      appBar: _buildAppBar(isDark),
      body: Row(
        children: [
          if (isDesktop) Container(
            width: 280,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200)),
            ),
            child: _buildSidebar(isDark),
          ),
          Expanded(
            child: Column(
              children: [
                _buildBreadcrumb(isDark),
                _buildStatsBanner(isDark),
                Expanded(
                  child: DropTarget(
                    onDragDone: (detail) => _onFilesDropped(detail.files),
                    onDragEntered: (detail) => setState(() => _isDragging = true),
                    onDragExited: (detail) => setState(() => _isDragging = false),
                    child: Stack(
                      children: [
                        _isLoading 
                          ? const Center(child: CircularProgressIndicator())
                          : _buildMainContent(isDark),
                        if (_isDragging)
                          Container(
                            color: DriftProTheme.primaryGreen.withOpacity(0.15),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.cloud_upload_outlined, size: 80, color: DriftProTheme.primaryGreen),
                                  const SizedBox(height: 16),
                                  Text('Slipp filer her for å laste opp', style: DriftProTheme.headingMd),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedItems.isEmpty ? FloatingActionButton.extended(
        onPressed: _showUploadOptions,
        icon: const Icon(Icons.add),
        label: const Text('Ny / Last opp'),
        backgroundColor: DriftProTheme.primaryGreen,
      ) : null,
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      title: Text(_selectedItems.isEmpty ? 'Dokumentarkiv' : '${_selectedItems.length} valgt'),
      actions: [
        if (_selectedItems.isNotEmpty) ...[
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: _deleteSelected),
          IconButton(icon: const Icon(Icons.share_outlined), onPressed: () {}),
        ],
        IconButton(
          icon: Icon(_viewMode == DmsViewMode.grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
          onPressed: () => setState(() => _viewMode = _viewMode == DmsViewMode.grid ? DmsViewMode.list : DmsViewMode.grid),
        ),
      ],
    );
  }

  Widget _buildSidebar(bool isDark) {
    return ListView(
      children: [
        const SizedBox(height: 20),
        _sidebarItem(Icons.folder_copy_outlined, 'Alle filer', DmsCategory.all),
        _sidebarItem(Icons.access_time_rounded, 'Nylige', DmsCategory.recent),
        _sidebarItem(Icons.star_outline_rounded, 'Stjernemerket', DmsCategory.starred),
        _sidebarItem(Icons.people_outline_rounded, 'Delt med meg', DmsCategory.shared),
        const Divider(height: 32, indent: 20, endIndent: 20),
        _sidebarItem(Icons.image_outlined, 'Bilder', DmsCategory.images),
        _sidebarItem(Icons.description_outlined, 'Dokumenter', DmsCategory.docs),
      ],
    );
  }

  Widget _sidebarItem(IconData icon, String title, DmsCategory cat) {
    final isActive = _activeCategory == cat;
    return ListTile(
      onTap: () {
        setState(() => _activeCategory = cat);
        if (cat == DmsCategory.all) {
          _navigateToFolder(null, 'Hovedarkiv');
        } else {
          _loadData(); // Re-filter if needed
        }
      },
      leading: Icon(icon, color: isActive ? DriftProTheme.primaryGreen : Colors.grey),
      title: Text(title, style: TextStyle(color: isActive ? DriftProTheme.primaryGreen : null)),
      selected: isActive,
    );
  }

  Widget _buildStatsBanner(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        onChanged: (val) {
          setState(() => _searchQuery = val);
          if (val.length > 2) _performGlobalSearch(val);
          else if (val.isEmpty) _loadData();
        },
        decoration: InputDecoration(
          hintText: 'Søk i hele arkivet...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty 
              ? IconButton(icon: const Icon(Icons.close), onPressed: () {
                  setState(() => _searchQuery = '');
                  _loadData();
                }) 
              : null,
          filled: true,
          fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildBreadcrumb(bool isDark) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _breadcrumb.length,
        separatorBuilder: (_, __) => const Icon(Icons.chevron_right, size: 16),
        itemBuilder: (context, index) {
          final item = _breadcrumb[index];
          return InkWell(
            onTap: () => _navigateToFolder(item['id'], item['name']!),
            child: Center(child: Text(item['name']!, style: TextStyle(fontWeight: index == _breadcrumb.length-1 ? FontWeight.bold : FontWeight.normal))),
          );
        },
      ),
    );
  }

  Widget _buildMainContent(bool isDark) {
    final items = _filteredItems;
    if (items.isEmpty) return const Center(child: Text('Ingen filer funnet'));

    if (_viewMode == DmsViewMode.list) {
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          if (item is DmsFolder) return _buildListItem(folder: item, isDark: isDark);
          return _buildListItem(file: item as DmsFile, isDark: isDark);
        },
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 150, mainAxisSpacing: 16, crossAxisSpacing: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is DmsFolder) return _buildGridItem(folder: item, isDark: isDark);
        return _buildGridItem(file: item as DmsFile, isDark: isDark);
      },
    );
  }

  Widget _buildListItem({DmsFolder? folder, DmsFile? file, required bool isDark}) {
    return ListTile(
      leading: Icon(folder != null ? Icons.folder : Icons.insert_drive_file, color: folder != null ? Colors.amber : DriftProTheme.primaryGreen),
      title: Text(folder?.name ?? file!.name),
      onTap: folder != null ? () => _navigateToFolder(folder.id, folder.name) : () => _openFile(file!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined, color: Colors.blue),
            tooltip: 'Del / Skjul for ansatte',
            onPressed: () => _managePermissions(folder: folder, file: file),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Slett',
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Er du sikker?'),
                content: Text('Vil du virkelig slette ${folder?.name ?? file!.name}?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _delete(folder: folder, file: file);
                    }, 
                    child: const Text('Slett', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridItem({DmsFolder? folder, DmsFile? file, required bool isDark}) {
    return InkWell(
      onTap: folder != null ? () => _navigateToFolder(folder.id, folder.name) : () => _openFile(file!),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(folder != null ? Icons.folder : Icons.insert_drive_file, size: 48, color: folder != null ? Colors.amber : DriftProTheme.primaryGreen),
                const SizedBox(height: 8),
                Text(folder?.name ?? file!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.person_add_outlined, size: 18, color: Colors.blue),
                  onPressed: () => _managePermissions(folder: folder, file: file),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  onPressed: () => _delete(folder: folder, file: file),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }



  Future<void> _openFile(DmsFile file) async {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FileViewerScreen(file: file)));
  }

  void _managePermissions({DmsFolder? folder, DmsFile? file}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PermissionsManagementSheet(folder: folder, file: file, companyId: _companyId!),
    );
  }

  void _showUploadOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.create_new_folder), title: const Text('Ny mappe'), onTap: () { Navigator.pop(context); _createFolder(); }),
          ListTile(leading: const Icon(Icons.upload_file), title: const Text('Last opp fil'), onTap: () { Navigator.pop(context); _uploadFile(); }),
        ],
      ),
    );
  }

  Future<void> _createFolder() async {
    // Basic impl
    final name = 'Ny mappe ${DateTime.now().millisecondsSinceEpoch}';
    await DmsService.createFolder(name: name, parentId: _currentFolderId, companyId: _companyId!);
    _loadData();
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result != null && result.files.single.bytes != null) {
      await DmsService.uploadFile(bytes: result.files.single.bytes!, fileName: result.files.single.name, folderId: _currentFolderId, companyId: _companyId!);
      _loadData();
    }
  }

  Future<void> _onFilesDropped(List<XFile> files) async {
    for (var file in files) {
      final bytes = await file.readAsBytes();
      await DmsService.uploadFile(bytes: bytes, fileName: file.name, folderId: _currentFolderId, companyId: _companyId!);
    }
    _loadData();
  }

  Future<void> _rename({DmsFolder? folder, DmsFile? file}) async {
    await DmsService.renameFolder(folder?.id ?? '', 'Nytt navn');
    _loadData();
  }

  Future<void> _delete({DmsFolder? folder, DmsFile? file}) async {
    if (folder != null) await DmsService.deleteFolder(folder.id);
    if (file != null) await DmsService.deleteFile(file.id, file.storagePath);
    _loadData();
  }

  void _deleteSelected() {}
}

class _PermissionsManagementSheet extends StatefulWidget {
  final DmsFolder? folder;
  final DmsFile? file;
  final String companyId;
  const _PermissionsManagementSheet({this.folder, this.file, required this.companyId});
  @override
  State<_PermissionsManagementSheet> createState() => _PermissionsManagementSheetState();
}

class _PermissionsManagementSheetState extends State<_PermissionsManagementSheet> {
  List<DmsPermission> _permissions = [];
  List<UserProfile> _allUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final permsFut = DmsService.fetchPermissions(folderId: widget.folder?.id, fileId: widget.file?.id);
    final usersFut = SupabaseService.fetchProfiles(companyId: widget.companyId);
    final res = await Future.wait([permsFut, usersFut]);
    setState(() {
      _permissions = res[0] as List<DmsPermission>;
      _allUsers = res[1] as List<UserProfile>;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(color: isDark ? DriftProTheme.cardDark : Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.all(24),
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Del / Skjul for ansatte', style: DriftProTheme.headingMd),
              if (widget.file != null)
                TextButton.icon(
                  onPressed: () async {
                    try {
                      final url = await DmsService.getDownloadUrl(widget.file!.storagePath);
                      Clipboard.setData(ClipboardData(text: url));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offentlig lenke kopiert!')));
                      }
                    } catch(e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil: $e')));
                    }
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('Kopier lenke'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Bestem hvem som skal se dette dokumentet/mappen. Skru av for å skjule.', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
              itemCount: _allUsers.length,
              itemBuilder: (context, index) {
                final user = _allUsers[index];
                final hasAccess = _permissions.any((p) => p.userId == user.id);
                return ListTile(
                  title: Text(user.fullName),
                  trailing: Switch.adaptive(
                    value: hasAccess, 
                    onChanged: (val) async {
                      await DmsService.grantPermission(folderId: widget.folder?.id, fileId: widget.file?.id, userId: user.id, type: DmsPermissionType.view);
                      _load();
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
