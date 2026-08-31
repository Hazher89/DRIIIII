import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/services/home_feed_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/home_feed_item.dart';
import '../../models/home_feed_layout_config.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import '../../widgets/home_feed/home_feed_design_editor.dart';
import '../../widgets/home_feed/home_feed_dual_preview.dart';
import '../../widgets/home_feed_banner.dart';

/// Rediger live forside-innhold for MAVI ansatte eller partnere.
class HomeFeedAdminScreen extends StatefulWidget {
  const HomeFeedAdminScreen({super.key});

  @override
  State<HomeFeedAdminScreen> createState() => _HomeFeedAdminScreenState();
}

class _HomeFeedAdminScreenState extends State<HomeFeedAdminScreen> {
  HomeFeedAudience _audience = HomeFeedAudience.mavi;
  List<HomeFeedItem> _items = const [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await HomeFeedService.fetchAllForAdmin(_audience);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const [
        'png',
        'jpg',
        'jpeg',
        'webp',
        'gif',
        'mp4',
        'mov',
        'webm',
        'pdf',
        'doc',
        'docx',
        'txt',
      ],
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final bytes = file.bytes ??
        (!kIsWeb && file.path != null
            ? await File(file.path!).readAsBytes()
            : null);
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kunne ikke lese filen.')),
      );
      return;
    }

    final contentType = HomeFeedService.guessContentType(
      file.name,
      mime: file.extension,
    );
    if (contentType == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Støttede filer: bilde, video eller PDF/dokument.'),
        ),
      );
      return;
    }

    setState(() => _uploading = true);
    try {
      final storagePath = await HomeFeedService.uploadMedia(
        audience: _audience,
        contentType: contentType,
        fileName: file.name,
        bytes: Uint8List.fromList(bytes),
      );

      final created = await HomeFeedService.createItem(
        audience: _audience,
        contentType: contentType,
        storagePath: storagePath,
        title: _stripExtension(file.name),
        fileName: file.name,
        sortOrder: _items.length,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Publisert — tilpass utseende når du vil.')),
      );
      await _load();
      if (!mounted) return;
      await _openDesignEditor(created);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opplasting feilet: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return name;
    return name.substring(0, dot);
  }

  Future<void> _openDesignEditor(HomeFeedItem item) async {
    final ok = await HomeFeedDesignEditor.open(
      context,
      item: item,
      onSave: (updated) async {
        await HomeFeedService.updateItem(updated);
        await _load();
      },
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lagret — vises live i app og web.')),
      );
    }
  }

  Future<void> _toggleActive(HomeFeedItem item) async {
    try {
      await HomeFeedService.updateItem(item.copyWith(isActive: !item.isActive));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke lagre: $e')),
      );
    }
  }

  Future<void> _delete(HomeFeedItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett innhold?'),
        content: Text(
          item.title.isNotEmpty ? item.title : item.fileName ?? 'Dette elementet',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DriftProTheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await HomeFeedService.deleteItem(item.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke slette: $e')),
      );
    }
  }

  Future<void> _move(int index, int delta) async {
    final next = index + delta;
    if (next < 0 || next >= _items.length) return;
    final copy = List<HomeFeedItem>.from(_items);
    final item = copy.removeAt(index);
    copy.insert(next, item);
    setState(() => _items = copy);
    try {
      await HomeFeedService.reorderItems(copy);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke sortere: $e')),
      );
      await _load();
    }
  }

  HomeFeedItem? get _previewItem {
    final active = _items.where((e) => e.isActive).toList();
    if (active.isEmpty) return null;
    return active.first;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Forside-innhold'),
      ),
      floatingActionButton: _uploading
          ? null
          : FloatingActionButton.extended(
              onPressed: _pickAndUpload,
              icon: const Icon(Icons.upload_file),
              label: const Text('Last opp'),
            ),
      body: _loading
          ? const DriftProLoadingCenter()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Last opp bilde, video eller dokument — tilpass størrelse, tekst og farger '
                  'med live forhåndsvisning for app og web. Endringer vises umiddelbart uten ny bygg.',
                  style: DriftProTheme.bodySm.copyWith(
                    color: isDark ? Colors.grey[400] : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<HomeFeedAudience>(
                  segments: HomeFeedAudience.values
                      .map(
                        (a) => ButtonSegment(
                          value: a,
                          label: Text(a.label),
                          icon: Icon(
                            a == HomeFeedAudience.mavi
                                ? Icons.groups_outlined
                                : Icons.handshake_outlined,
                          ),
                        ),
                      )
                      .toList(),
                  selected: {_audience},
                  onSelectionChanged: (s) {
                    setState(() => _audience = s.first);
                    _load();
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Forhåndsvisning (live)',
                  style: DriftProTheme.labelLg.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (_previewItem != null)
                  HomeFeedDualPreview(
                    item: _previewItem!,
                    layout: _previewItem!.layoutConfig,
                  )
                else
                  HomeFeedBanner(audience: _audience, compact: true),
                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.orange)),
                  ),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Ingen innhold for ${_audience.label.toLowerCase()} ennå.',
                      textAlign: TextAlign.center,
                      style: DriftProTheme.bodyMd,
                    ),
                  )
                else
                  ...List.generate(_items.length, (i) {
                    final item = _items[i];
                    return _AdminItemTile(
                      item: item,
                      index: i,
                      total: _items.length,
                      onToggle: () => _toggleActive(item),
                      onDesign: () => _openDesignEditor(item),
                      onDelete: () => _delete(item),
                      onMoveUp: i > 0 ? () => _move(i, -1) : null,
                      onMoveDown: i < _items.length - 1 ? () => _move(i, 1) : null,
                    );
                  }),
                if (_uploading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: DriftProLoadingIndicator()),
                  ),
                const SizedBox(height: 80),
              ],
            ),
    );
  }
}

class _AdminItemTile extends StatelessWidget {
  const _AdminItemTile({
    required this.item,
    required this.index,
    required this.total,
    required this.onToggle,
    required this.onDesign,
    required this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });

  final HomeFeedItem item;
  final int index;
  final int total;
  final VoidCallback onToggle;
  final VoidCallback onDesign;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    IconData typeIcon;
    switch (item.contentType) {
      case HomeFeedContentType.image:
        typeIcon = Icons.image_outlined;
      case HomeFeedContentType.video:
        typeIcon = Icons.videocam_outlined;
      case HomeFeedContentType.document:
        typeIcon = Icons.description_outlined;
    }

    final layoutHint = item.layoutConfig.fullPageHero
        ? ' · hero'
        : ' · ${item.layoutConfig.sizePreset.label.toLowerCase()}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isDark ? DriftProTheme.cardDark : DriftProTheme.cardLight,
      child: ListTile(
        leading: Icon(typeIcon),
        title: Text(
          item.title.isNotEmpty ? item.title : item.fileName ?? 'Uten tittel',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${item.contentType.label}$layoutHint${item.isActive ? '' : ' · skjult'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onMoveUp != null)
              IconButton(
                tooltip: 'Flytt opp',
                icon: const Icon(Icons.arrow_upward),
                onPressed: onMoveUp,
              ),
            if (onMoveDown != null)
              IconButton(
                tooltip: 'Flytt ned',
                icon: const Icon(Icons.arrow_downward),
                onPressed: onMoveDown,
              ),
            IconButton(
              tooltip: item.isActive ? 'Skjul' : 'Vis',
              icon: Icon(item.isActive ? Icons.visibility : Icons.visibility_off),
              onPressed: onToggle,
            ),
            IconButton(
              tooltip: 'Tilpass design',
              icon: const Icon(Icons.tune),
              onPressed: onDesign,
            ),
            IconButton(
              tooltip: 'Slett',
              icon: const Icon(Icons.delete_outline, color: DriftProTheme.error),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
