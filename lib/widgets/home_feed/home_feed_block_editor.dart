import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/home_feed_content_config.dart';
import '../../models/home_feed_item.dart';
import '../../models/home_feed_layout_config.dart';
import 'home_feed_color_field.dart';
import 'home_feed_interactive_preview.dart';

/// Avansert editor — innhold, layout, planlegging, grid og karusell.
class HomeFeedBlockEditor extends StatefulWidget {
  const HomeFeedBlockEditor({
    super.key,
    required this.item,
    required this.onSave,
    this.allItems = const [],
  });

  final HomeFeedItem item;
  final Future<void> Function(HomeFeedItem updated) onSave;
  final List<HomeFeedItem> allItems;

  static Future<bool?> open(
    BuildContext context, {
    required HomeFeedItem item,
    required Future<void> Function(HomeFeedItem updated) onSave,
    List<HomeFeedItem> allItems = const [],
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => HomeFeedBlockEditor(
          item: item,
          onSave: onSave,
          allItems: allItems,
        ),
      ),
    );
  }

  @override
  State<HomeFeedBlockEditor> createState() => _HomeFeedBlockEditorState();
}

class _HomeFeedBlockEditorState extends State<HomeFeedBlockEditor>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late TextEditingController _titleCtrl;
  late TextEditingController _captionCtrl;
  late TextEditingController _bodyCtrl;
  late TextEditingController _youtubeCtrl;
  late TextEditingController _linkUrlCtrl;
  late TextEditingController _linkBtnCtrl;
  late TextEditingController _badgeCtrl;
  late HomeFeedLayoutConfig _layout;
  late HomeFeedContentConfig _content;
  DateTime? _scheduleStart;
  DateTime? _scheduleEnd;
  Set<HomeFeedTargetPortal> _portals = {};
  int _priority = 0;
  bool _pinned = false;
  bool _saving = false;

  HomeFeedItem get _previewItem => widget.item.copyWith(
        title: _titleCtrl.text.trim(),
        caption: _captionCtrl.text.trim().isEmpty
            ? null
            : _captionCtrl.text.trim(),
        layoutConfig: _layout,
        contentConfig: _content,
        scheduleStart: _scheduleStart,
        scheduleEnd: _scheduleEnd,
        targetPortals: _portals.toList(),
        priority: _priority,
        pinned: _pinned,
      );

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    final item = widget.item;
    _titleCtrl = TextEditingController(text: item.title);
    _captionCtrl = TextEditingController(text: item.caption ?? '');
    _bodyCtrl = TextEditingController(text: item.contentConfig.textBlock.body);
    _youtubeCtrl =
        TextEditingController(text: item.contentConfig.youtube.videoUrl);
    _linkUrlCtrl = TextEditingController(text: item.contentConfig.link.url);
    _linkBtnCtrl =
        TextEditingController(text: item.contentConfig.link.buttonLabel);
    _badgeCtrl =
        TextEditingController(text: item.contentConfig.badge.label ?? '');
    _layout = item.layoutConfig;
    _content = item.contentConfig;
    _scheduleStart = item.scheduleStart;
    _scheduleEnd = item.scheduleEnd;
    _portals = item.targetPortals.toSet();
    _priority = item.priority;
    _pinned = item.pinned;
    _titleCtrl.addListener(() => setState(() {}));
    _captionCtrl.addListener(() => setState(() {}));
    _bodyCtrl.addListener(_syncContent);
    _youtubeCtrl.addListener(_syncContent);
    _linkUrlCtrl.addListener(_syncContent);
    _linkBtnCtrl.addListener(_syncContent);
  }

  void _syncContent() {
    setState(() {
      _content = _content.copyWith(
        textBlock: _content.textBlock.copyWith(body: _bodyCtrl.text),
        youtube: _content.youtube.copyWith(videoUrl: _youtubeCtrl.text.trim()),
        link: _content.link.copyWith(
          url: _linkUrlCtrl.text.trim(),
          buttonLabel: _linkBtnCtrl.text.trim().isEmpty
              ? 'Les mer'
              : _linkBtnCtrl.text.trim(),
        ),
        badge: HomeFeedBadgeConfig(
          label: _badgeCtrl.text.trim().isEmpty ? null : _badgeCtrl.text.trim(),
          showCountdown: _content.badge.showCountdown,
          countdownTarget: _content.badge.countdownTarget,
        ),
      );
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _titleCtrl.dispose();
    _captionCtrl.dispose();
    _bodyCtrl.dispose();
    _youtubeCtrl.dispose();
    _linkUrlCtrl.dispose();
    _linkBtnCtrl.dispose();
    _badgeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_previewItem);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke lagre: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Rediger ${widget.item.contentType.label.toLowerCase()}'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Lagre'),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Forhåndsvisning'),
            Tab(text: 'Innhold'),
            Tab(text: 'Tekst & farger'),
            Tab(text: 'Grid'),
            Tab(text: 'Planlegging'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _previewTab(),
          _contentTab(),
          _textColorsTab(),
          _gridTab(),
          _scheduleTab(),
        ],
      ),
    );
  }

  Widget _previewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        HomeFeedInteractivePreview(
          item: _previewItem,
          layout: _layout,
          onLayoutChanged: (layout) => setState(() => _layout = layout),
          onContentChanged: (content) => setState(() => _content = content),
        ),
      ],
    );
  }

  Widget _contentTab() {
    final type = widget.item.contentType;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(labelText: 'Tittel'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _captionCtrl,
          decoration: const InputDecoration(labelText: 'Undertekst'),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        if (type == HomeFeedContentType.text) ...[
          TextField(
            controller: _bodyCtrl,
            decoration: const InputDecoration(
              labelText: 'Brødtekst',
              alignLabelWithHint: true,
            ),
            maxLines: 6,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<HomeFeedThemePreset>(
            value: _content.textBlock.theme,
            decoration: const InputDecoration(labelText: 'Tema'),
            items: HomeFeedThemePreset.values
                .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _content = _content.copyWith(
                  textBlock: _content.textBlock.copyWith(theme: v),
                );
              });
            },
          ),
        ],
        if (type == HomeFeedContentType.youtube) ...[
          TextField(
            controller: _youtubeCtrl,
            decoration: const InputDecoration(
              labelText: 'YouTube-lenke',
              hintText: 'https://youtube.com/watch?v=...',
            ),
          ),
          if (_content.youtube.resolvedVideoId != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Video-ID: ${_content.youtube.resolvedVideoId}',
                style: DriftProTheme.bodySm.copyWith(
                  color: DriftProTheme.primaryGreen,
                ),
              ),
            ),
        ],
        if (type == HomeFeedContentType.link) ...[
          TextField(
            controller: _linkUrlCtrl,
            decoration: const InputDecoration(labelText: 'Lenke-URL'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _linkBtnCtrl,
            decoration: const InputDecoration(labelText: 'Knappetekst'),
          ),
        ],
        if (type == HomeFeedContentType.carousel) ...[
          Text('Karusell-modus', style: DriftProTheme.labelLg),
          Wrap(
            spacing: 8,
            children: HomeFeedCarouselMode.values.map((mode) {
              return ChoiceChip(
                label: Text(mode.label),
                selected: _content.carousel.mode == mode,
                onSelected: (_) => setState(() {
                  _content = _content.copyWith(
                    carousel: HomeFeedCarouselConfig(
                      mode: mode,
                      intervalMs: _content.carousel.intervalMs,
                      slideIds: _content.carousel.slideIds,
                    ),
                  );
                }),
              );
            }).toList(),
          ),
          Text('Intervall: ${_content.carousel.intervalMs ~/ 1000} sek'),
          Slider(
            value: _content.carousel.intervalMs.toDouble(),
            min: 3000,
            max: 30000,
            divisions: 27,
            onChanged: (v) => setState(() {
              _content = _content.copyWith(
                carousel: HomeFeedCarouselConfig(
                  mode: _content.carousel.mode,
                  intervalMs: v.round(),
                  slideIds: _content.carousel.slideIds,
                ),
              );
            }),
          ),
          Text(
            'Slides: ${widget.item.carouselSlides.length} (legg til under elementlisten)',
            style: DriftProTheme.bodySm,
          ),
        ],
        if (type == HomeFeedContentType.spacer) ...[
          Text(
            'Juster høyde i fanen Forhåndsvisning — dra i app- og web-rammene.',
            style: DriftProTheme.bodySm.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            'App: ${_content.spacer.heightApp.round()} px · '
            'Web: ${_content.spacer.heightWeb.round()} px',
            style: DriftProTheme.labelMd,
          ),
        ],
        const Divider(height: 28),
        TextField(
          controller: _badgeCtrl,
          decoration: const InputDecoration(
            labelText: 'Badge (f.eks. Ny, Viktig)',
          ),
        ),
        SwitchListTile(
          title: const Text('Nedtelling'),
          value: _content.badge.showCountdown,
          onChanged: (v) => setState(() {
            _content = _content.copyWith(
              badge: HomeFeedBadgeConfig(
                label: _content.badge.label,
                showCountdown: v,
                countdownTarget: _content.badge.countdownTarget ??
                    DateTime.now().add(const Duration(hours: 24)),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _textColorsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          children: HomeFeedTextPosition.values.map((pos) {
            return ChoiceChip(
              label: Text(pos.label),
              selected: _layout.textPosition == pos,
              onSelected: (_) => setState(() {
                _layout = _layout.copyWith(textPosition: pos);
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        HomeFeedColorField(
          label: 'Tittelfarge',
          colorHex: _layout.titleStyle.colorHex,
          opacity: _layout.titleStyle.opacity,
          showOpacity: false,
          onChanged: (hex, opacity) => setState(() {
            _layout = _layout.copyWith(
              titleStyle: _layout.titleStyle.copyWith(
                colorHex: hex,
                opacity: opacity,
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: HomeFeedTextSize.values.map((size) {
            return ChoiceChip(
              label: Text('${size.fontSize.round()}'),
              selected: _layout.titleStyle.size == size,
              onSelected: (_) => setState(() {
                _layout = _layout.copyWith(
                  titleStyle: _layout.titleStyle.copyWith(size: size),
                );
              }),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _gridTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Kolonne-bredde (1–12)', style: DriftProTheme.labelLg),
        Text('App: ${_layout.colSpanApp} / 12'),
        Slider(
          value: _layout.colSpanApp.toDouble(),
          min: 1,
          max: 12,
          divisions: 11,
          label: '${_layout.colSpanApp}',
          onChanged: (v) => setState(() {
            _layout = _layout.copyWith(colSpanApp: v.round());
          }),
        ),
        Text('Web: ${_layout.colSpanWeb} / 12'),
        Slider(
          value: _layout.colSpanWeb.toDouble(),
          min: 1,
          max: 12,
          divisions: 11,
          label: '${_layout.colSpanWeb}',
          onChanged: (v) => setState(() {
            _layout = _layout.copyWith(colSpanWeb: v.round());
          }),
        ),
      ],
    );
  }

  Widget _scheduleTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          title: const Text('Vis fra'),
          subtitle: Text(_scheduleStart?.toLocal().toString() ?? 'Alltid'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              firstDate: DateTime(2024),
              lastDate: DateTime(2030),
              initialDate: _scheduleStart ?? DateTime.now(),
            );
            if (d == null || !mounted) return;
            setState(() => _scheduleStart = d);
          },
        ),
        ListTile(
          title: const Text('Vis til'),
          subtitle: Text(_scheduleEnd?.toLocal().toString() ?? 'Ingen slutt'),
          trailing: const Icon(Icons.event_busy),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              firstDate: DateTime(2024),
              lastDate: DateTime(2030),
              initialDate: _scheduleEnd ?? DateTime.now(),
            );
            if (d == null || !mounted) return;
            setState(() => _scheduleEnd = d);
          },
        ),
        if (widget.item.audience == HomeFeedAudience.partner) ...[
          const Divider(height: 24),
          Text('Målgruppe (partner)', style: DriftProTheme.labelLg),
          ...HomeFeedTargetPortal.values.map((p) {
            return CheckboxListTile(
              title: Text(p.label),
              value: _portals.contains(p),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _portals.add(p);
                } else {
                  _portals.remove(p);
                }
              }),
            );
          }),
        ],
        const Divider(height: 24),
        Text('Prioritet: $_priority'),
        Slider(
          value: _priority.toDouble(),
          min: 0,
          max: 10,
          divisions: 10,
          onChanged: (v) => setState(() => _priority = v.round()),
        ),
        SwitchListTile(
          title: const Text('Fest øverst (pin)'),
          value: _pinned,
          onChanged: (v) => setState(() => _pinned = v),
        ),
      ],
    );
  }
}
