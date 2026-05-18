import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/dms/dms_password.dart';
import '../../core/services/dms/dms_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/dms/dms_file.dart';
import '../../models/dms/dms_folder.dart';
import 'file_viewer_screen.dart';
import 'widgets/dms_create_folder_sheet.dart';
import 'widgets/dms_permissions_sheet.dart';

class DmsScreen extends StatefulWidget {
  final String? initialFolderId;
  final String? initialFolderName;

  const DmsScreen({super.key, this.initialFolderId, this.initialFolderName});

  @override
  State<DmsScreen> createState() => _DmsScreenState();
}

enum DmsViewMode { grid, list }

enum DmsSort { nameAsc, nameDesc, dateDesc, sizeDesc }

class _DmsScreenState extends State<DmsScreen> {
  bool _isLoading = true;
  List<DmsFolder> _folders = [];
  List<DmsFile> _files = [];
  String? _currentFolderId;
  DmsFolder? _currentFolder;
  final List<Map<String, String?>> _breadcrumb = [];
  String? _companyId;
  DmsViewMode _viewMode = DmsViewMode.list;
  String _searchQuery = '';
  bool _isDragging = false;
  DmsSort _sort = DmsSort.nameAsc;
  final Set<String> _unlockedFolderIds = {};
  Map<String, dynamic> _stats = {'total_files': 0, 'total_size': 0};

  bool get _canGoBack => _breadcrumb.length > 1;

  String get _currentTitle {
    if (_breadcrumb.isEmpty) return 'Dokumentarkiv';
    return _breadcrumb.last['name'] ?? 'Dokumentarkiv';
  }

  @override
  void initState() {
    super.initState();
    _currentFolderId = widget.initialFolderId;
    _breadcrumb.add({'id': null, 'name': 'Hovedarkiv'});
    if (widget.initialFolderId != null) {
      _breadcrumb.add({
        'id': widget.initialFolderId,
        'name': widget.initialFolderName ?? 'Mappe',
      });
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _companyId ??= await SupabaseService.getCurrentCompanyId();
      if (_companyId == null) return;

      if (_currentFolderId != null) {
        _currentFolder = await DmsService.fetchFolder(_currentFolderId!);
      } else {
        _currentFolder = null;
      }

      final results = await Future.wait([
        DmsService.fetchFolders(
          parentId: _currentFolderId,
          companyId: _companyId!,
        ),
        DmsService.fetchFiles(
          folderId: _currentFolderId,
          companyId: _companyId!,
        ),
        DmsService.getStorageStats(_companyId!),
      ]);

      if (!mounted) return;
      setState(() {
        _folders = _sortedFolders(results[0] as List<DmsFolder>);
        _files = _sortedFiles(results[1] as List<DmsFile>);
        _stats = results[2] as Map<String, dynamic>;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved lasting: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<DmsFolder> _sortedFolders(List<DmsFolder> list) {
    final copy = List<DmsFolder>.from(list);
    switch (_sort) {
      case DmsSort.nameAsc:
        copy.sort((a, b) => a.name.compareTo(b.name));
      case DmsSort.nameDesc:
        copy.sort((a, b) => b.name.compareTo(a.name));
      case DmsSort.dateDesc:
        copy.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case DmsSort.sizeDesc:
        copy.sort((a, b) => a.name.compareTo(b.name));
    }
    return copy;
  }

  List<DmsFile> _sortedFiles(List<DmsFile> list) {
    final copy = List<DmsFile>.from(list);
    switch (_sort) {
      case DmsSort.nameAsc:
        copy.sort((a, b) => a.name.compareTo(b.name));
      case DmsSort.nameDesc:
        copy.sort((a, b) => b.name.compareTo(a.name));
      case DmsSort.dateDesc:
        copy.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case DmsSort.sizeDesc:
        copy.sort((a, b) => (b.fileSize ?? 0).compareTo(a.fileSize ?? 0));
    }
    return copy;
  }

  void _goBack() {
    if (!_canGoBack) return;
    final parent = _breadcrumb[_breadcrumb.length - 2];
    _navigateToFolder(parent['id'], parent['name'] ?? 'Hovedarkiv', skipLockCheck: true);
  }

  Future<void> _enterFolder(DmsFolder folder) async {
    if (folder.isPasswordProtected && !_unlockedFolderIds.contains(folder.id)) {
      final ok = await _promptFolderPassword(folder);
      if (!ok) return;
      _unlockedFolderIds.add(folder.id);
    }
    _navigateToFolder(folder.id, folder.name);
  }

  Future<bool> _promptFolderPassword(DmsFolder folder) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_outline),
        title: Text('${folder.name} er passordbeskyttet'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Skriv passord',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(
            ctx,
            DmsPassword.verify(ctrl.text, folder.passwordHash),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              DmsPassword.verify(ctrl.text, folder.passwordHash),
            ),
            child: const Text('Åpne mappe'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (ok != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feil passord')),
      );
    }
    return ok == true;
  }

  void _navigateToFolder(
    String? id,
    String name, {
    bool skipLockCheck = false,
  }) {
    setState(() {
      _currentFolderId = id;
      final index = _breadcrumb.indexWhere((e) => e['id'] == id);
      if (index != -1) {
        _breadcrumb.removeRange(index + 1, _breadcrumb.length);
      } else {
        _breadcrumb.add({'id': id, 'name': name});
      }
    });
    _loadData();
  }

  List<dynamic> get _filteredItems {
    final all = <dynamic>[..._folders, ..._files];
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all.where((item) {
      final name = item is DmsFolder ? item.name : (item as DmsFile).name;
      return name.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _performGlobalSearch(String query) async {
    if (query.length < 3 || _companyId == null) return;
    setState(() => _isLoading = true);
    try {
      final files = await DmsService.searchAllFiles(query, _companyId!);
      setState(() {
        _files = files;
        _folders = [];
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Navn A–Å'),
              onTap: () {
                setState(() => _sort = DmsSort.nameAsc);
                Navigator.pop(ctx);
                _loadData();
              },
            ),
            ListTile(
              title: const Text('Navn Å–A'),
              onTap: () {
                setState(() => _sort = DmsSort.nameDesc);
                Navigator.pop(ctx);
                _loadData();
              },
            ),
            ListTile(
              title: const Text('Nyeste først'),
              onTap: () {
                setState(() => _sort = DmsSort.dateDesc);
                Navigator.pop(ctx);
                _loadData();
              },
            ),
            ListTile(
              title: const Text('Største filer'),
              onTap: () {
                setState(() => _sort = DmsSort.sizeDesc);
                Navigator.pop(ctx);
                _loadData();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showActionsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: const Text('Ny mappe (smart)'),
              subtitle: Text(
                _currentFolderId == null
                    ? 'I hovedarkiv'
                    : 'Inne i $_currentTitle',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _createFolderSmart();
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Last opp fil(er)'),
              onTap: () {
                Navigator.pop(ctx);
                _uploadFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.sort),
              title: const Text('Sorter'),
              onTap: () {
                Navigator.pop(ctx);
                _showSortMenu();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createFolderSmart() async {
    if (_companyId == null) return;
    final ok = await DmsCreateFolderSheet.show(
      context,
      companyId: _companyId!,
      parentFolderId: _currentFolderId,
      parentFolderName: _currentTitle,
    );
    if (ok == true) _loadData();
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || _companyId == null) return;
    for (final f in result.files) {
      if (f.bytes == null) continue;
      await DmsService.uploadFile(
        bytes: f.bytes!,
        fileName: f.name,
        folderId: _currentFolderId,
        companyId: _companyId!,
      );
    }
    _loadData();
  }

  Future<void> _onFilesDropped(List<XFile> files) async {
    if (_companyId == null) return;
    for (final file in files) {
      final bytes = await file.readAsBytes();
      await DmsService.uploadFile(
        bytes: bytes,
        fileName: file.name,
        folderId: _currentFolderId,
        companyId: _companyId!,
      );
    }
    _loadData();
  }

  Future<void> _downloadFile(DmsFile file) async {
    try {
      final url = await DmsService.getDownloadUrl(file.storagePath);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nedlasting feilet: $e')),
        );
      }
    }
  }

  void _openFile(DmsFile file) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FileViewerScreen(file: file)),
    );
  }

  Future<void> _renameFolder(DmsFolder folder) async {
    final ctrl = TextEditingController(text: folder.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gi nytt navn'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await DmsService.renameFolder(folder.id, name);
    _loadData();
  }

  Future<void> _renameFile(DmsFile file) async {
    final ctrl = TextEditingController(text: file.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gi nytt navn'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await DmsService.renameFile(file.id, name);
    _loadData();
  }

  Future<void> _deleteFolder(DmsFolder folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett mappe?'),
        content: Text(
          '«${folder.name}» og alt innhold slettes permanent.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DmsService.deleteFolder(folder.id);
    _loadData();
  }

  Future<void> _deleteFile(DmsFile file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett fil?'),
        content: Text('«${file.name}» slettes permanent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DmsService.deleteFile(file.id, file.storagePath);
    _loadData();
  }

  void _showItemMenu({DmsFolder? folder, DmsFile? file}) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (folder != null) ...[
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Åpne mappe'),
                onTap: () {
                  Navigator.pop(ctx);
                  _enterFolder(folder);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Gi nytt navn'),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameFolder(folder);
                },
              ),
            ],
            if (file != null) ...[
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Forhåndsvis / les'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openFile(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Last ned'),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadFile(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Gi nytt navn'),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameFile(file);
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.people_outline, color: Colors.blue),
              title: const Text('Del & tilgang'),
              onTap: () {
                Navigator.pop(ctx);
                if (_companyId != null) {
                  DmsPermissionsSheet.show(
                    context,
                    folder: folder,
                    file: file,
                    companyId: _companyId!,
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Slett', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                if (folder != null) {
                  _deleteFolder(folder);
                } else if (file != null) {
                  _deleteFile(file);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.bgLight,
      appBar: AppBar(
        leading: _canGoBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Tilbake til forrige mappe',
                onPressed: _goBack,
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_currentTitle, style: const TextStyle(fontSize: 18)),
            if (!_isLoading)
              Text(
                _currentFolder?.description?.isNotEmpty == true
                    ? _currentFolder!.description!
                    : '${_folders.length} mapper · ${_files.length} filer',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: 'Sorter',
            onPressed: _showSortMenu,
          ),
          IconButton(
            icon: Icon(
              _viewMode == DmsViewMode.grid
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
            ),
            onPressed: () => setState(() {
              _viewMode = _viewMode == DmsViewMode.grid
                  ? DmsViewMode.list
                  : DmsViewMode.grid;
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildBreadcrumb(isDark),
          _buildSearchAndStats(isDark),
          Expanded(
            child: DropTarget(
              onDragDone: (d) => _onFilesDropped(d.files),
              onDragEntered: (_) => setState(() => _isDragging = true),
              onDragExited: (_) => setState(() => _isDragging = false),
              child: Stack(
                children: [
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildMainContent(isDark),
                  if (_isDragging)
                    Container(
                      color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                      child: Center(
                        child: Text(
                          'Slipp for å laste opp her',
                          style: DriftProTheme.headingMd.copyWith(
                            color: DriftProTheme.primaryGreen,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showActionsMenu,
        icon: const Icon(Icons.add),
        label: Text(_currentFolderId == null ? 'Ny / Last opp' : 'Legg til'),
        backgroundColor: DriftProTheme.primaryGreen,
      ),
    );
  }

  Widget _buildBreadcrumb(bool isDark) {
    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.grey.shade50,
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _breadcrumb.length,
          separatorBuilder: (_, __) =>
              Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade500),
          itemBuilder: (_, index) {
            final item = _breadcrumb[index];
            final isLast = index == _breadcrumb.length - 1;
            return Center(
              child: InkWell(
                onTap: isLast
                    ? null
                    : () => _navigateToFolder(
                          item['id'],
                          item['name'] ?? 'Hovedarkiv',
                          skipLockCheck: true,
                        ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (index == 0)
                        const Icon(Icons.home_outlined, size: 16),
                      if (index == 0) const SizedBox(width: 4),
                      Text(
                        item['name'] ?? '',
                        style: TextStyle(
                          fontWeight:
                              isLast ? FontWeight.bold : FontWeight.normal,
                          color: isLast
                              ? DriftProTheme.primaryGreen
                              : null,
                          decoration:
                              isLast ? null : TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchAndStats(bool isDark) {
    final totalSize = _stats['total_size'] as int? ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Søk i arkivet…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() => _searchQuery = '');
                        _loadData();
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) {
              setState(() => _searchQuery = v);
              if (v.length > 2) {
                _performGlobalSearch(v);
              } else if (v.isEmpty) {
                _loadData();
              }
            },
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Bedrift: ${_stats['total_files'] ?? 0} filer · ${_formatBytes(totalSize)}',
              style: DriftProTheme.caption,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(bool isDark) {
    final items = _filteredItems;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Ingen treff'
                  : 'Tom mappe – opprett eller last opp',
              style: DriftProTheme.bodyMd.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _createFolderSmart,
                  icon: const Icon(Icons.create_new_folder),
                  label: const Text('Ny mappe'),
                ),
                FilledButton.icon(
                  onPressed: _uploadFile,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Last opp'),
                  style: FilledButton.styleFrom(
                    backgroundColor: DriftProTheme.primaryGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_viewMode == DmsViewMode.grid) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          if (item is DmsFolder) return _gridFolder(item);
          return _gridFile(item as DmsFile);
        },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        if (item is DmsFolder) return _listFolder(item, isDark);
        return _listFile(item as DmsFile, isDark);
      },
    );
  }

  Widget _folderBadges(DmsFolder folder) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (folder.isPasswordProtected)
          const Icon(Icons.lock, size: 14, color: Colors.orange),
        if (folder.isPrivate)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.visibility_off, size: 14, color: Colors.blueGrey),
          ),
      ],
    );
  }

  Widget _listFolder(DmsFolder folder, bool isDark) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Icon(Icons.folder, color: Colors.amber.shade700, size: 36),
        title: Row(
          children: [
            Expanded(child: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.w600))),
            _folderBadges(folder),
          ],
        ),
        subtitle: folder.description != null && folder.description!.isNotEmpty
            ? Text(folder.description!, maxLines: 1, overflow: TextOverflow.ellipsis)
            : const Text('Dobbelttrykk for meny · trykk for å åpne'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _enterFolder(folder),
        onLongPress: () => _showItemMenu(folder: folder),
      ),
    );
  }

  Widget _listFile(DmsFile file, bool isDark) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Icon(Icons.insert_drive_file, color: DriftProTheme.primaryGreen, size: 32),
        title: Text(file.name),
        subtitle: Text(
          '${file.extension?.toUpperCase() ?? "FIL"} · ${_formatBytes(file.fileSize ?? 0)}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showItemMenu(file: file),
        ),
        onTap: () => _openFile(file),
        onLongPress: () => _showItemMenu(file: file),
      ),
    );
  }

  Widget _gridFolder(DmsFolder folder) {
    return InkWell(
      onTap: () => _enterFolder(folder),
      onLongPress: () => _showItemMenu(folder: folder),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Icon(Icons.folder, size: 48, color: Colors.amber.shade700),
                  _folderBadges(folder),
                ],
              ),
              const SizedBox(height: 8),
              Text(folder.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gridFile(DmsFile file) {
    return InkWell(
      onTap: () => _openFile(file),
      onLongPress: () => _showItemMenu(file: file),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insert_drive_file, size: 44, color: DriftProTheme.primaryGreen),
              const SizedBox(height: 8),
              Text(file.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
