import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/services/home_feed_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/home_feed_content_config.dart';
import '../../models/home_feed_item.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import '../../widgets/home_feed/home_feed_add_block_sheet.dart';
import '../../widgets/home_feed/home_feed_block_editor.dart';
import '../../widgets/home_feed_banner.dart';

/// Avansert redigering av live forside-innhold.
class HomeFeedAdminScreen extends StatefulWidget {
  const HomeFeedAdminScreen({super.key});

  @override
  State<HomeFeedAdminScreen> createState() => _HomeFeedAdminScreenState();
}

class _HomeFeedAdminScreenState extends State<HomeFeedAdminScreen> {
  HomeFeedAudience _audience = HomeFeedAudience.mavi;
  List<HomeFeedItem> _items = const [];
  bool _loading = true;
  bool _busy = false;
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

  Future<void> _addBlock() async {
    final type = await showHomeFeedAddBlockSheet(context);
    if (type == null || !mounted) return;

    setState(() => _busy = true);
    try {
      HomeFeedItem created;
      switch (type) {
        case HomeFeedContentType.text:
          created = await HomeFeedService.createTextBlock(
            audience: _audience,
            title: 'Ny tekst',
            body: 'Skriv meldingen din her…',
            sortOrder: _items.length,
          );
        case HomeFeedContentType.youtube:
          final url = await _promptText(
            title: 'YouTube-lenke',
            hint: 'https://youtube.com/watch?v=...',
          );
          if (url == null || url.isEmpty) return;
          if (HomeFeedService.validateYoutubeUrl(url) == null) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ugyldig YouTube-lenke.')),
            );
            return;
          }
          created = await HomeFeedService.createYoutubeBlock(
            audience: _audience,
            title: 'YouTube-video',
            videoUrl: url,
            sortOrder: _items.length,
          );
        case HomeFeedContentType.link:
          final url = await _promptText(title: 'Lenke-URL', hint: 'https://…');
          if (url == null) return;
          created = await HomeFeedService.createLinkBlock(
            audience: _audience,
            title: 'Lenke',
            url: url,
            sortOrder: _items.length,
          );
        case HomeFeedContentType.spacer:
          created = await HomeFeedService.createSpacer(
            audience: _audience,
            sortOrder: _items.length,
          );
        case HomeFeedContentType.carousel:
          created = await HomeFeedService.createCarousel(
            audience: _audience,
            title: 'Karusell',
            sortOrder: _items.length,
          );
        case HomeFeedContentType.image:
        case HomeFeedContentType.video:
        case HomeFeedContentType.document:
          await _pickAndUpload(type);
          return;
      }
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      await _openEditor(created);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke opprette: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
  }) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (ok != true) {
      ctrl.dispose();
      return null;
    }
    final v = ctrl.text.trim();
    ctrl.dispose();
    return v;
  }

  Future<void> _pickAndUpload(HomeFeedContentType expectedType) async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const [
          'png', 'jpg', 'jpeg', 'webp', 'gif',
          'mp4', 'mov', 'webm',
          'pdf', 'doc', 'docx', 'txt',
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
          const SnackBar(content: Text('Ustøttet filtype.')),
        );
        return;
      }

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
      await _load();
      if (!mounted) return;
      await _openEditor(created);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opplasting feilet: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return name;
    return name.substring(0, dot);
  }

  Future<void> _openEditor(HomeFeedItem item) async {
    final ok = await HomeFeedBlockEditor.open(
      context,
      item: item,
      allItems: _items,
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

  Future<void> _duplicateToPartner(HomeFeedItem item) async {
    try {
      await HomeFeedService.duplicateToAudience(
        item,
        HomeFeedAudience.partner,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kopiert til partner-forside.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke kopiere: $e')),
      );
    }
  }

  Future<void> _addSlideToCarousel(HomeFeedItem carousel) async {
    final type = await showHomeFeedAddBlockSheet(context);
    if (type == null || type == HomeFeedContentType.carousel) return;

    setState(() => _busy = true);
    try {
      HomeFeedItem slide;
      if (type.needsMedia) {
        // Quick text/youtube for slides
        if (type == HomeFeedContentType.text) {
          slide = await HomeFeedService.createItem(
            audience: _audience,
            contentType: type,
            title: 'Slide',
            parentId: carousel.id,
            sortOrder: carousel.carouselSlides.length,
            contentConfig: const HomeFeedContentConfig(
              textBlock: HomeFeedTextBlockConfig(body: 'Ny slide'),
            ),
          );
        } else {
          await _pickAndUploadForCarousel(carousel.id, type);
          return;
        }
      } else if (type == HomeFeedContentType.youtube) {
        final url = await _promptText(
          title: 'YouTube-lenke',
          hint: 'https://youtube.com/watch?v=...',
        );
        if (url == null) return;
        slide = await HomeFeedService.createItem(
          audience: _audience,
          contentType: type,
          title: 'YouTube-slide',
          parentId: carousel.id,
          sortOrder: carousel.carouselSlides.length,
          contentConfig: HomeFeedContentConfig(
            youtube: HomeFeedYoutubeConfig(videoUrl: url),
          ),
        );
      } else {
        slide = await HomeFeedService.createItem(
          audience: _audience,
          contentType: type,
          title: type.label,
          parentId: carousel.id,
          sortOrder: carousel.carouselSlides.length,
        );
      }
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      await _openEditor(slide);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndUploadForCarousel(
    String parentId,
    HomeFeedContentType type,
  ) async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final storagePath = await HomeFeedService.uploadMedia(
      audience: _audience,
      contentType: type,
      fileName: file.name,
      bytes: Uint8List.fromList(bytes),
    );
    final carousel = _items.firstWhere((e) => e.id == parentId);
    await HomeFeedService.createItem(
      audience: _audience,
      contentType: type,
      storagePath: storagePath,
      title: _stripExtension(file.name),
      fileName: file.name,
      parentId: parentId,
      sortOrder: carousel.carouselSlides.length,
    );
    await _load();
  }

  Future<void> _toggleActive(HomeFeedItem item) async {
    await HomeFeedService.updateItem(item.copyWith(isActive: !item.isActive));
    await _load();
  }

  Future<void> _delete(HomeFeedItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett innhold?'),
        content: Text(item.title.isNotEmpty ? item.title : item.contentType.label),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await HomeFeedService.deleteItem(item.id);
    await _load();
  }

  Future<void> _move(int index, int delta) async {
    final next = index + delta;
    if (next < 0 || next >= _items.length) return;
    final copy = List<HomeFeedItem>.from(_items);
    final item = copy.removeAt(index);
    copy.insert(next, item);
    setState(() => _items = copy);
    await HomeFeedService.reorderItems(copy);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(title: const Text('Forside-innhold')),
      floatingActionButton: _busy
          ? null
          : FloatingActionButton.extended(
              onPressed: _addBlock,
              icon: const Icon(Icons.add),
              label: const Text('Legg til'),
            ),
      body: _loading
          ? const DriftProLoadingCenter()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Bygg forsiden med tekst, YouTube, bilder, karusell og lenker. '
                    'Juster grid, planlegging og målgruppe — endringer vises live uten ny bygg.',
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
                    style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  HomeFeedBanner(audience: _audience, compact: true),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.orange)),
                  ],
                  const SizedBox(height: 16),
                  if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.dashboard_customize_outlined,
                            size: 48,
                            color: Colors.grey.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Ingen innhold for ${_audience.label.toLowerCase()} ennå.\n'
                            'Trykk «Legg til» for å starte.',
                            textAlign: TextAlign.center,
                            style: DriftProTheme.bodyMd,
                          ),
                        ],
                      ),
                    )
                  else
                    ...List.generate(_items.length, (i) {
                      final item = _items[i];
                      return _AdminBlockTile(
                        item: item,
                        onEdit: () => _openEditor(item),
                        onToggle: () => _toggleActive(item),
                        onDelete: () => _delete(item),
                        onMoveUp: i > 0 ? () => _move(i, -1) : null,
                        onMoveDown:
                            i < _items.length - 1 ? () => _move(i, 1) : null,
                        onDuplicateToPartner: _audience == HomeFeedAudience.mavi
                            ? () => _duplicateToPartner(item)
                            : null,
                        onAddSlide: item.contentType ==
                                HomeFeedContentType.carousel
                            ? () => _addSlideToCarousel(item)
                            : null,
                      );
                    }),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: DriftProLoadingIndicator()),
                    ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}

class _AdminBlockTile extends StatelessWidget {
  const _AdminBlockTile({
    required this.item,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
    this.onDuplicateToPartner,
    this.onAddSlide,
  });

  final HomeFeedItem item;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onDuplicateToPartner;
  final VoidCallback? onAddSlide;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final layout = item.layoutConfig;
    final meta = <String>[
      item.contentType.label,
      '${layout.colSpanApp}/12 app',
      if (item.pinned) 'festet',
      if (item.isScheduled) 'planlagt',
      if (!item.isActive) 'skjult',
      if (item.contentType == HomeFeedContentType.carousel)
        '${item.carouselSlides.length} slides',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isDark ? DriftProTheme.cardDark : DriftProTheme.cardLight,
      child: Column(
        children: [
          ListTile(
            leading: Icon(item.contentType.icon, color: DriftProTheme.primaryGreen),
            title: Text(
              item.title.isNotEmpty ? item.title : item.contentType.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(meta),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onMoveUp != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: onMoveUp,
                  ),
                if (onMoveDown != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_downward),
                    onPressed: onMoveDown,
                  ),
                IconButton(
                  icon: Icon(
                    item.isActive ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: onToggle,
                ),
                IconButton(
                  icon: const Icon(Icons.tune),
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: DriftProTheme.error),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
          if (onDuplicateToPartner != null || onAddSlide != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Wrap(
                spacing: 8,
                children: [
                  if (onDuplicateToPartner != null)
                    OutlinedButton.icon(
                      onPressed: onDuplicateToPartner,
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Kopier til partner'),
                    ),
                  if (onAddSlide != null)
                    OutlinedButton.icon(
                      onPressed: onAddSlide,
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                      label: const Text('Legg til slide'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
