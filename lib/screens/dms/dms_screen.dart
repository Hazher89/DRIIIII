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
  List<DmsFolder> _allFolders = []; // Cached for search
  List<DmsFile> _allFiles = [];     // Cached for search
  
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
    final combined = [..._folders, ..._files];
    if (_searchQuery.isEmpty) return combined;
    return combined.where((item) {
      final name = item is DmsFolder ? item.name : (item as DmsFile).name;
      return name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.bgLight,
      drawer: isDesktop ? null : _buildSidebar(isDark),
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
      title: Text(_selectedItems.isEmpty ? 'Dokumentarkiv 4.0' : '${_selectedItems.length} valgt', 
          style: DriftProTheme.headingLg.copyWith(color: _selectedItems.isEmpty ? null : DriftProTheme.primaryGreen)),
      centerTitle: false,
      actions: [
        if (_selectedItems.isNotEmpty) ...[
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: _deleteSelected),
          IconButton(icon: const Icon(Icons.share_outlined), onPressed: () {}),
          const VerticalDivider(),
        ],
        IconButton(
          icon: Icon(_viewMode == DmsViewMode.grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
          onPressed: () => setState(() => _viewMode = _viewMode == DmsViewMode.grid ? DmsViewMode.list : DmsViewMode.grid),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSidebar(bool isDark) {
    return Column(
      children: [
        const SizedBox(height: 20),
        _sidebarItem(Icons.folder_copy_outlined, 'Alle filer', DmsCategory.all),
        _sidebarItem(Icons.access_time_rounded, 'Nylige', DmsCategory.recent),
        _sidebarItem(Icons.star_outline_rounded, 'Stjernemerket', DmsCategory.starred),
        _sidebarItem(Icons.people_outline_rounded, 'Delt med meg', DmsCategory.shared),
        const Divider(height: 32, indent: 20, endIndent: 20),
        _sidebarItem(Icons.image_outlined, 'Bilder', DmsCategory.images),
        _sidebarItem(Icons.description_outlined, 'Dokumenter', DmsCategory.docs),
        const Spacer(),
        _buildStorageCard(isDark),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _sidebarItem(IconData icon, String title, DmsCategory cat) {
    final isActive = _activeCategory == cat;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        onTap: () => setState(() {
          _activeCategory = cat;
          // Implement specific filtering here if needed
        }),
        leading: Icon(icon, color: isActive ? DriftProTheme.primaryGreen : Colors.grey, size: 22),
        title: Text(title, style: DriftProTheme.labelMd.copyWith(
          color: isActive ? DriftProTheme.primaryGreen : null,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        )),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: isActive ? DriftProTheme.primaryGreen.withOpacity(0.08) : null,
        dense: true,
      ),
    );
  }

  Widget _buildStorageCard(bool isDark) {
    final usedMB = (_stats['total_size'] as int) / (1024 * 1024);
    final progress = usedMB / 1024; // Limit to 1GB for demo
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lagring', style: DriftProTheme.labelSm),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey.withOpacity(0.1),
            valueColor: const AlwaysStoppedAnimation(DriftProTheme.primaryGreen),
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Text('${usedMB.toStringAsFixed(1)} MB av 1.0 GB brukt', style: DriftProTheme.bodySm.copyWith(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildStatsBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? DriftProTheme.cardDark : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200),
              ),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: const InputDecoration(
                  hintText: 'Søk i alt...',
                  icon: Icon(Icons.search, size: 20),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(bool isDark) {
    final items = _filteredItems;
    if (items.isEmpty) return _buildEmptyState();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDashboardHead(isDark),
          if (_viewMode == DmsViewMode.list)
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                if (item is DmsFolder) return _buildFileListItem(folder: item, isDark: isDark);
                return _buildFileListItem(file: item as DmsFile, isDark: isDark);
              },
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.85,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                if (item is DmsFolder) return _buildFolderGridItem(item, isDark);
                return _buildFileGridItem(item as DmsFile, isDark);
              },
            ),
          const SizedBox(height: 100), // Space for FAB
        ],
      ),
    );
  }

  Widget _buildDashboardHead(bool isDark) {
    if (_files.isEmpty || _breadcrumb.length > 1) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Text('Nylig brukt', style: DriftProTheme.headingMd.copyWith(fontSize: 16)),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _files.take(5).length,
            itemBuilder: (context, index) => _buildRecentCard(_files[index], isDark),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Text('Alle elementer', style: DriftProTheme.headingMd.copyWith(fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildRecentCard(DmsFile file, bool isDark) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _getFileIcon(file.extension, size: 32),
          const Spacer(),
          Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: DriftProTheme.labelSm),
          Text(file.extension?.toUpperCase() ?? 'FIL', style: DriftProTheme.bodySm.copyWith(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildFolderGridItem(DmsFolder folder, bool isDark) {
    final isSelected = _selectedItems.contains(folder.id);
    return InkWell(
      onLongPress: () => _toggleSelection(folder.id),
      onTap: _selectedItems.isNotEmpty ? () => _toggleSelection(folder.id) : () => _navigateToFolder(folder.id, folder.name),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? DriftProTheme.primaryGreen.withOpacity(0.05) : (isDark ? DriftProTheme.cardDark : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? DriftProTheme.primaryGreen : (isDark ? DriftProTheme.dividerDark : Colors.grey.shade100)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                const Icon(Icons.folder_rounded, color: Colors.amber, size: 64),
                if (isSelected) const CircleAvatar(radius: 10, backgroundColor: DriftProTheme.primaryGreen, child: Icon(Icons.check, size: 12, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 8),
            Text(folder.name, style: DriftProTheme.labelMd, textAlign: TextAlign.center, maxLines: 1),
            Text('Mappe', style: DriftProTheme.bodySm.copyWith(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildFileGridItem(DmsFile file, bool isDark) {
    final isSelected = _selectedItems.contains(file.id);
    return InkWell(
      onLongPress: () => _toggleSelection(file.id),
      onTap: _selectedItems.isNotEmpty ? () => _toggleSelection(file.id) : () => _openFile(file),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? DriftProTheme.primaryGreen.withOpacity(0.05) : (isDark ? DriftProTheme.cardDark : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? DriftProTheme.primaryGreen : (isDark ? DriftProTheme.dividerDark : Colors.grey.shade100)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                _getFileIcon(file.extension, size: 64),
                if (isSelected) const CircleAvatar(radius: 10, backgroundColor: DriftProTheme.primaryGreen, child: Icon(Icons.check, size: 12, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(file.name, style: DriftProTheme.labelMd, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text('${(file.fileSize ?? 0) / 1024 ~/ 1} KB', style: DriftProTheme.bodySm.copyWith(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildFileListItem({DmsFolder? folder, DmsFile? file, required bool isDark}) {
    final id = folder?.id ?? file!.id;
    final isSelected = _selectedItems.contains(id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? DriftProTheme.primaryGreen.withOpacity(0.05) : (isDark ? DriftProTheme.cardDark : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSelected ? DriftProTheme.primaryGreen : (isDark ? DriftProTheme.dividerDark : Colors.grey.shade100)),
      ),
      child: ListTile(
        leading: folder != null ? const Icon(Icons.folder_rounded, color: Colors.amber) : _getFileIcon(file!.extension),
        title: Text(folder?.name ?? file!.name, style: DriftProTheme.labelMd),
        subtitle: Text(folder != null ? 'Mappe' : '${(file!.fileSize ?? 0) / 1024 ~/ 1} KB • ${file.extension?.toUpperCase()}', style: DriftProTheme.bodySm),
        trailing: _buildMenu(folder: folder, file: file),
        onTap: _selectedItems.isNotEmpty ? () => _toggleSelection(id) : (folder != null ? () => _navigateToFolder(folder.id, folder.name) : () => _openFile(file!)),
        onLongPress: () => _toggleSelection(id),
      ),
    );
  }

  Widget _getFileIcon(String? ext, {double size = 24}) {
     switch (ext?.toLowerCase()) {
        case 'pdf': return Icon(Icons.picture_as_pdf_rounded, color: Colors.red.shade400, size: size);
        case 'docx':
        case 'doc': return Icon(Icons.description_rounded, color: Colors.blue.shade400, size: size);
        case 'xlsx':
        case 'xls': return Icon(Icons.table_chart_rounded, color: Colors.green.shade400, size: size);
        case 'png':
        case 'jpg':
        case 'jpeg': return Icon(Icons.image_rounded, color: Colors.orange.shade400, size: size);
        default: return Icon(Icons.insert_drive_file_rounded, color: Colors.grey, size: size);
      }
  }

  Widget _buildBreadcrumb(bool isDark) {
    return Container(
      height: 44,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _breadcrumb.length,
        separatorBuilder: (_, __) => const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
        itemBuilder: (context, index) {
          final item = _breadcrumb[index];
          final isLast = index == _breadcrumb.length - 1;
          return InkWell(
            onTap: isLast ? null : () => _navigateToFolder(item['id'], item['name']!),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  item['name']!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                    color: isLast ? (isDark ? Colors.white : Colors.black) : Colors.grey,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: DriftProTheme.primaryGreen.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.folder_open_rounded, size: 80, color: DriftProTheme.primaryGreen.withOpacity(0.2)),
          ),
          const SizedBox(height: 24),
          Text('Ingen dokumenter funnet', style: DriftProTheme.headingMd),
          const SizedBox(height: 8),
          const Text('Last opp din første fil for å komme i gang', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _showUploadOptions,
            icon: const Icon(Icons.upload_outlined),
            label: const Text('Kom i gang nå'),
          ),
        ],
      ),
    );
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedItems.contains(id)) {
        _selectedItems.remove(id);
      } else {
        _selectedItems.add(id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    // Implement batch delete logic
    setState(() => _selectedItems.clear());
    _loadData();
  }

  Widget _buildMenu({DmsFolder? folder, DmsFile? file}) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 20, color: Colors.grey),
      onSelected: (val) {
        if (val == 'rename') _rename(folder: folder, file: file);
        if (val == 'delete') _delete(folder: folder, file: file);
        if (val == 'permissions') _managePermissions(folder: folder, file: file);
        if (val == 'download' && file != null) _openFile(file);
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'rename', 
          child: Row(children: [const Icon(Icons.edit_outlined, size: 18), const SizedBox(width: 12), Text(AppStrings.rename)])
        ),
        PopupMenuItem(
          value: 'permissions', 
          child: Row(children: [const Icon(Icons.lock_outline_rounded, size: 18), const SizedBox(width: 12), Text(AppStrings.permissions)])
        ),
        if (file != null) PopupMenuItem(
          value: 'download', 
          child: Row(children: [const Icon(Icons.download_outlined, size: 18), const SizedBox(width: 12), Text('Last ned')])
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete', 
          child: Row(children: [const Icon(Icons.delete_outline, size: 18, color: Colors.red), const SizedBox(width: 12), Text(AppStrings.delete, style: const TextStyle(color: Colors.red))])
        ),
      ],
    );
  }

  void _showUploadOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _uploadOption(Icons.create_new_folder_rounded, 'Ny mappe', Colors.amber, _createFolder),
                _uploadOption(Icons.upload_file_rounded, 'Last opp fil', Colors.blue, _uploadFile),
                _uploadOption(Icons.folder_shared_rounded, 'Last opp mappe', Colors.purple, _uploadFolder),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _uploadOption(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: DriftProTheme.labelSm),
        ],
      ),
    );
  }

  // ── Original Actions Restored ───────────────────────────────────────────
  
  Future<void> _createFolder() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ny mappe'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Mappenavn')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppStrings.cancel)),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Opprett')),
        ],
      )
    );

    if (_companyId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selskap ikke funnet. Vennligst sjekk profilen din.'), backgroundColor: Colors.orange));
      return;
    }
    if (name != null && name.isNotEmpty) {
      await DmsService.createFolder(name: name, parentId: _currentFolderId, companyId: _companyId!);
      _loadData();
    }
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result != null && result.files.single.bytes != null) {
      if (_companyId == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kan ikke laste opp: Selskap ikke funnet.'), backgroundColor: Colors.red));
        return;
      }
      setState(() => _isLoading = true);
      try {
        await DmsService.uploadFile(
          bytes: result.files.single.bytes!,
          fileName: result.files.single.name,
          folderId: _currentFolderId,
          companyId: _companyId!,
        );
        _loadData();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil ved opplasting: $e'), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadFolder() async {
    // For web/desktop, picking a directory often requires platform specific handling.
    // In file_picker, getDirectoryPath is used for desktop. 
    // On web, we suggest users to select multiple files.
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (result != null && result.files.isNotEmpty) {
      if (_companyId == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kan ikke laste opp: Selskap ikke funnet.'), backgroundColor: Colors.red));
        return;
      }
      setState(() => _isLoading = true);
      try {
        // Create a sub-folder for the upload batch if desired, or just upload to current.
        for (var file in result.files) {
          if (file.bytes != null) {
             await DmsService.uploadFile(
              bytes: file.bytes!,
              fileName: file.name,
              folderId: _currentFolderId,
              companyId: _companyId!,
            );
          }
        }
        _loadData();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil ved mappeopplasting: $e'), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _onFilesDropped(List<XFile> files) async {
    setState(() => _isDragging = false);
    if (_companyId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kan ikke laste opp: Selskap ikke funnet.'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _isLoading = true);
    try {
      for (var file in files) {
        final bytes = await file.readAsBytes();
        await DmsService.uploadFile(
          bytes: bytes,
          fileName: file.name,
          folderId: _currentFolderId,
          companyId: _companyId!,
        );
      }
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil ved drop-upload: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rename({DmsFolder? folder, DmsFile? file}) async {
    final ctrl = TextEditingController(text: folder?.name ?? file?.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.rename),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppStrings.cancel)),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: Text(AppStrings.save)),
        ],
      )
    );

    if (name != null && name.isNotEmpty) {
      if (folder != null) await DmsService.renameFolder(folder.id, name);
      if (file != null) await DmsService.renameFile(file.id, name);
      _loadData();
    }
  }

  Future<void> _delete({DmsFolder? folder, DmsFile? file}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bekreft sletting'),
        content: Text('Vil du slette ${folder?.name ?? file?.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(AppStrings.delete)
          ),
        ],
      )
    );

    if (confirm == true) {
      if (folder != null) await DmsService.deleteFolder(folder.id);
      if (file != null) await DmsService.deleteFile(file.id, file.storagePath);
      _loadData();
    }
  }

  Future<void> _openFile(DmsFile file) async {
    try {
      final url = await DmsService.getDownloadUrl(file.storagePath);
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke åpne fil: $e')));
    }
  }

  void _managePermissions({DmsFolder? folder, DmsFile? file}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PermissionsManagementSheet(folder: folder, file: file, companyId: _companyId!),
    );
  }
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
    try {
      final permsFut = DmsService.fetchPermissions(folderId: widget.folder?.id, fileId: widget.file?.id);
      final usersFut = SupabaseService.fetchProfiles(companyId: widget.companyId);
      
      final res = await Future.wait([permsFut, usersFut]);
      setState(() {
        _permissions = res[0] as List<DmsPermission>;
        _allUsers = res[1] as List<UserProfile>;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tilgangsstyring', style: DriftProTheme.headingMd),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: DriftProTheme.primaryGreen.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, size: 16, color: DriftProTheme.primaryGreen),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.folder?.name ?? widget.file?.name ?? '', style: DriftProTheme.labelSm)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
              itemCount: _allUsers.length,
              itemBuilder: (context, index) {
                final user = _allUsers[index];
                final perm = _permissions.firstWhere((p) => p.userId == user.id, orElse: () => DmsPermission(id: '', userId: user.id, type: DmsPermissionType.read));
                final hasExplicitPerm = _permissions.any((p) => p.userId == user.id);
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: DriftProTheme.primaryGreen.withOpacity(0.1),
                        child: Text(user.fullName?[0] ?? '?', style: const TextStyle(color: DriftProTheme.primaryGreen)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.fullName ?? user.email, style: DriftProTheme.labelMd),
                            Text(user.role?.name.toUpperCase() ?? 'BRUKER', style: DriftProTheme.bodySm.copyWith(color: Colors.grey)),
                          ],
                        ),
                      ),
                      DropdownButton<DmsPermissionType>(
                        value: perm.type,
                        underline: Container(),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                        onChanged: (val) async {
                          if (val != null) {
                            await DmsService.grantPermission(
                              folderId: widget.folder?.id,
                              fileId: widget.file?.id,
                              userId: user.id,
                              type: val,
                            );
                            _load();
                          }
                        },
                        items: DmsPermissionType.values.map((e) => DropdownMenuItem(value: e, child: Text(e.name.toUpperCase(), style: DriftProTheme.labelSm))).toList(),
                      ),
                    ],
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
