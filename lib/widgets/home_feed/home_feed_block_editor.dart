import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/home_feed_content_config.dart';
import '../../models/home_feed_item.dart';
import '../../models/home_feed_layout_config.dart';
import 'home_feed_block_view.dart';
import 'home_feed_color_field.dart';
import 'home_feed_interactive_preview.dart';

/// Samlet studio: mobil-forhåndsvisning + alle tilpasninger på ett sted.
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

class _HomeFeedBlockEditorState extends State<HomeFeedBlockEditor> {
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
  bool _previewAsWeb = false;

  final Set<String> _expanded = {'innhold', 'tekst'};

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

  bool get _overlayMode => _layout.textPosition.isOverlay;

  @override
  void initState() {
    super.initState();
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
    _badgeCtrl.addListener(_syncContent);
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

  void _setTextMode({required bool overlay, required bool hidden}) {
    setState(() {
      if (hidden) {
        _layout = _layout.copyWith(textPosition: HomeFeedTextPosition.hidden);
        return;
      }
      if (!overlay) {
        _layout = _layout.copyWith(textPosition: HomeFeedTextPosition.below);
        return;
      }
      final keep = _layout.textPosition.isOverlay
          ? _layout.textPosition
          : HomeFeedTextPosition.overlayBottom;
      _layout = _layout.copyWith(textPosition: keep);
    });
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
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 920;
          final preview = _PhoneAppPreview(
            item: _previewItem,
            layout: _layout,
            asWeb: _previewAsWeb,
            onAsWebChanged: (v) => setState(() => _previewAsWeb = v),
            onLayoutChanged: (layout) => setState(() => _layout = layout),
            onContentChanged: (content) => setState(() => _content = content),
          );
          final controls = _buildControls();

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 380,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF121418)
                          : const Color(0xFFF2F3F5),
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: preview,
                  ),
                ),
                Expanded(child: controls),
              ],
            );
          }

          return Column(
            children: [
              SizedBox(
                height: (constraints.maxHeight * 0.42).clamp(280.0, 420.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF121418)
                        : const Color(0xFFF2F3F5),
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                  ),
                  child: preview,
                ),
              ),
              Expanded(child: controls),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControls() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          'Alt du endrer oppdateres i mobilvisningen til venstre '
          '(eller over på mobil).',
          style: DriftProTheme.bodySm.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        _section(
          id: 'innhold',
          title: 'Innhold',
          subtitle: 'Tittel, tekst og media',
          icon: Icons.edit_note_outlined,
          children: _contentFields(),
        ),
        _section(
          id: 'tekst',
          title: 'Tekst på bilde / video',
          subtitle: 'Under, oppå eller skjult',
          icon: Icons.text_fields,
          children: _textPlacementFields(),
        ),
        _section(
          id: 'stil',
          title: 'Farger & skrift',
          subtitle: 'Fritt valg av farge, størrelse og stil',
          icon: Icons.palette_outlined,
          children: _styleFields(),
        ),
        _section(
          id: 'storrelse',
          title: 'Størrelse & utseende',
          subtitle: 'Høyde, hjørner, hero',
          icon: Icons.aspect_ratio,
          children: [
            HomeFeedLayoutToolbar(
              layout: _layout,
              onLayoutChanged: (layout) => setState(() => _layout = layout),
            ),
          ],
        ),
        _section(
          id: 'grid',
          title: 'Bredde i grid',
          subtitle: 'Kolonner i app og web',
          icon: Icons.grid_view_outlined,
          children: _gridFields(),
        ),
        _section(
          id: 'plan',
          title: 'Planlegging',
          subtitle: 'Når, hvem og prioritet',
          icon: Icons.schedule_outlined,
          children: _scheduleFields(),
        ),
      ],
    );
  }

  Widget _section({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    final open = _expanded.contains(id);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: open,
        onExpansionChanged: (v) => setState(() {
          if (v) {
            _expanded.add(id);
          } else {
            _expanded.remove(id);
          }
        }),
        leading: Icon(icon, color: DriftProTheme.primaryGreen),
        title: Text(title, style: DriftProTheme.labelLg),
        subtitle: Text(subtitle, style: DriftProTheme.bodySm),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: children,
      ),
    );
  }

  List<Widget> _contentFields() {
    final type = widget.item.contentType;
    return [
      TextField(
        controller: _titleCtrl,
        decoration: const InputDecoration(
          labelText: 'Tittel',
          hintText: 'Tekst som vises under eller oppå media',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _captionCtrl,
        decoration: const InputDecoration(
          labelText: 'Undertekst',
          hintText: 'Valgfri beskrivelse',
        ),
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
        const SizedBox(height: 8),
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
          'Slides: ${widget.item.carouselSlides.length} '
          '(legg til under elementlisten)',
          style: DriftProTheme.bodySm,
        ),
      ],
      if (type == HomeFeedContentType.spacer) ...[
        Text(
          'Juster høyde i mobilvisningen — dra i bunnen av forhåndsvisningen.',
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
        contentPadding: EdgeInsets.zero,
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
    ];
  }

  List<Widget> _textPlacementFields() {
    final modeHidden = _layout.textPosition == HomeFeedTextPosition.hidden;
    final modeOverlay = _overlayMode;
    final modeBelow = !modeHidden && !modeOverlay;

    return [
      Text(
        'Velg først hvor teksten skal ligge i forhold til bilde/video:',
        style: DriftProTheme.bodySm.copyWith(color: Colors.grey[700]),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _PlacementCard(
              selected: modeBelow,
              icon: Icons.vertical_align_bottom,
              title: 'Under',
              hint: 'Tekst under media',
              onTap: () => _setTextMode(overlay: false, hidden: false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PlacementCard(
              selected: modeOverlay,
              icon: Icons.layers_outlined,
              title: 'Oppå',
              hint: 'Tekst over media',
              onTap: () => _setTextMode(overlay: true, hidden: false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PlacementCard(
              selected: modeHidden,
              icon: Icons.visibility_off_outlined,
              title: 'Skjul',
              hint: 'Ingen tekst',
              onTap: () => _setTextMode(overlay: false, hidden: true),
            ),
          ),
        ],
      ),
      if (modeOverlay) ...[
        const SizedBox(height: 16),
        Text('Hvor på bildet?', style: DriftProTheme.labelLg),
        const SizedBox(height: 8),
        SegmentedButton<HomeFeedTextPosition>(
          segments: const [
            ButtonSegment(
              value: HomeFeedTextPosition.overlayTop,
              label: Text('Topp'),
              icon: Icon(Icons.vertical_align_top, size: 18),
            ),
            ButtonSegment(
              value: HomeFeedTextPosition.overlayCenter,
              label: Text('Midt'),
              icon: Icon(Icons.vertical_align_center, size: 18),
            ),
            ButtonSegment(
              value: HomeFeedTextPosition.overlayBottom,
              label: Text('Bunn'),
              icon: Icon(Icons.vertical_align_bottom, size: 18),
            ),
          ],
          selected: {
            _layout.textPosition.isOverlay
                ? _layout.textPosition
                : HomeFeedTextPosition.overlayBottom,
          },
          onSelectionChanged: (s) => setState(() {
            _layout = _layout.copyWith(textPosition: s.first);
          }),
        ),
      ],
      if (!modeHidden) ...[
        const SizedBox(height: 16),
        Text('Justering', style: DriftProTheme.labelLg),
        const SizedBox(height: 8),
        SegmentedButton<TextAlign>(
          segments: const [
            ButtonSegment(
              value: TextAlign.left,
              icon: Icon(Icons.format_align_left),
              label: Text('Venstre'),
            ),
            ButtonSegment(
              value: TextAlign.center,
              icon: Icon(Icons.format_align_center),
              label: Text('Midt'),
            ),
            ButtonSegment(
              value: TextAlign.right,
              icon: Icon(Icons.format_align_right),
              label: Text('Høyre'),
            ),
          ],
          selected: {_layout.textAlign},
          onSelectionChanged: (s) => setState(() {
            _layout = _layout.copyWith(textAlign: s.first);
          }),
        ),
      ],
    ];
  }

  List<Widget> _styleFields() {
    return [
      _textStyleBlock(
        title: 'Tittel',
        style: _layout.titleStyle,
        onChanged: (s) => setState(() {
          _layout = _layout.copyWith(titleStyle: s);
        }),
      ),
      const SizedBox(height: 20),
      _textStyleBlock(
        title: 'Undertekst',
        style: _layout.captionStyle,
        onChanged: (s) => setState(() {
          _layout = _layout.copyWith(captionStyle: s);
        }),
      ),
      if (_overlayMode) ...[
        const SizedBox(height: 20),
        HomeFeedColorField(
          label: 'Skygge bak tekst (overlay)',
          colorHex: _layout.overlayColorHex,
          opacity: _layout.overlayOpacity,
          onChanged: (hex, opacity) => setState(() {
            _layout = _layout.copyWith(
              overlayColorHex: hex,
              overlayOpacity: opacity,
            );
          }),
        ),
      ],
    ];
  }

  Widget _textStyleBlock({
    required String title,
    required HomeFeedTextStyleConfig style,
    required ValueChanged<HomeFeedTextStyleConfig> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: DriftProTheme.labelLg),
        const SizedBox(height: 8),
        HomeFeedColorField(
          label: 'Farge',
          colorHex: style.colorHex,
          opacity: style.opacity,
          onChanged: (hex, opacity) => onChanged(
            style.copyWith(colorHex: hex, opacity: opacity),
          ),
        ),
        const SizedBox(height: 12),
        Text('Skriftstørrelse', style: DriftProTheme.labelMd),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: HomeFeedTextSize.values.map((size) {
            return ChoiceChip(
              label: Text('${size.fontSize.round()}'),
              selected: style.size == size,
              onSelected: (_) => onChanged(style.copyWith(size: size)),
            );
          }).toList(),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Fet skrift'),
          value: style.bold,
          onChanged: (v) => onChanged(style.copyWith(bold: v)),
        ),
      ],
    );
  }

  List<Widget> _gridFields() {
    return [
      Text('App: ${_layout.colSpanApp} / 12', style: DriftProTheme.labelMd),
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
      Text('Web: ${_layout.colSpanWeb} / 12', style: DriftProTheme.labelMd),
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
    ];
  }

  List<Widget> _scheduleFields() {
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
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
        contentPadding: EdgeInsets.zero,
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
            contentPadding: EdgeInsets.zero,
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
        contentPadding: EdgeInsets.zero,
        title: const Text('Fest øverst (pin)'),
        value: _pinned,
        onChanged: (v) => setState(() => _pinned = v),
      ),
    ];
  }
}

class _PlacementCard extends StatelessWidget {
  const _PlacementCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final green = DriftProTheme.primaryGreen;
    return Material(
      color: selected ? green.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? green : Colors.grey.withValues(alpha: 0.35),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? green : Colors.grey[700]),
              const SizedBox(height: 6),
              Text(
                title,
                style: DriftProTheme.labelMd.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? green : null,
                ),
              ),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: DriftProTheme.bodySm.copyWith(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mobilramme som viser innholdet nøyaktig som i appen.
class _PhoneAppPreview extends StatefulWidget {
  const _PhoneAppPreview({
    required this.item,
    required this.layout,
    required this.asWeb,
    required this.onAsWebChanged,
    required this.onLayoutChanged,
    required this.onContentChanged,
  });

  final HomeFeedItem item;
  final HomeFeedLayoutConfig layout;
  final bool asWeb;
  final ValueChanged<bool> onAsWebChanged;
  final ValueChanged<HomeFeedLayoutConfig> onLayoutChanged;
  final ValueChanged<HomeFeedContentConfig> onContentChanged;

  @override
  State<_PhoneAppPreview> createState() => _PhoneAppPreviewState();
}

class _PhoneAppPreviewState extends State<_PhoneAppPreview> {
  double? _dragHeight;
  bool _dragging = false;

  bool get _isSpacer => widget.item.contentType == HomeFeedContentType.spacer;

  double get _minH => _isSpacer ? 8 : 80;
  double get _maxH => _isSpacer ? 120 : 720;

  double get _baseHeight {
    if (_isSpacer) {
      return widget.asWeb
          ? widget.item.contentConfig.spacer.heightWeb
          : widget.item.contentConfig.spacer.heightApp;
    }
    return widget.layout.resolveHeight(
      isWeb: widget.asWeb,
      compactPreview: false,
    );
  }

  double get _displayHeight =>
      (_dragHeight ?? _baseHeight).clamp(_minH, _maxH);

  void _applyHeight(double height) {
    final clamped = height.clamp(_minH, _maxH);
    if (_isSpacer) {
      final spacer = widget.item.contentConfig.spacer;
      widget.onContentChanged(
        widget.item.contentConfig.copyWith(
          spacer: HomeFeedSpacerConfig(
            heightApp: widget.asWeb ? spacer.heightApp : clamped,
            heightWeb: widget.asWeb ? clamped : spacer.heightWeb,
          ),
        ),
      );
      return;
    }
    widget.onLayoutChanged(
      widget.layout.copyWith(
        customHeightApp:
            widget.asWeb ? widget.layout.customHeightApp : clamped,
        customHeightWeb:
            widget.asWeb ? clamped : widget.layout.customHeightWeb,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _PhoneAppPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging &&
        (oldWidget.layout != widget.layout ||
            oldWidget.asWeb != widget.asWeb ||
            oldWidget.item.contentConfig != widget.item.contentConfig)) {
      _dragHeight = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final feedBg = isDark ? const Color(0xFF0E1114) : const Color(0xFFF7F8FA);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Icon(
                widget.asWeb ? Icons.laptop_mac : Icons.phone_iphone,
                size: 18,
                color: DriftProTheme.primaryGreen,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.asWeb
                      ? 'Web-forhåndsvisning'
                      : 'Slik ser det ut i appen',
                  style: DriftProTheme.labelMd.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SegmentedButton<bool>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(value: false, label: Text('App')),
                  ButtonSegment(value: true, label: Text('Web')),
                ],
                selected: {widget.asWeb},
                onSelectionChanged: (s) => widget.onAsWebChanged(s.first),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: AspectRatio(
                aspectRatio: widget.asWeb ? 9 / 14 : 9 / 19.5,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(
                      widget.asWeb ? 16 : 36,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  padding: EdgeInsets.all(widget.asWeb ? 8 : 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      widget.asWeb ? 10 : 28,
                    ),
                    child: ColoredBox(
                      color: feedBg,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!widget.asWeb) _statusBar(isDark),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                            child: Text(
                              'Forside',
                              style: DriftProTheme.labelLg.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
                              child: HomeFeedBlockView(
                                item: widget.item.copyWith(
                                  layoutConfig: widget.layout,
                                ),
                                previewPlatform: widget.asWeb
                                    ? HomeFeedPreviewPlatform.web
                                    : HomeFeedPreviewPlatform.app,
                                compactPreview: false,
                                interactive: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              Text(
                'Høyde: ${_displayHeight.round()} px'
                '${_dragging ? ' (dra)' : ''}',
                style: DriftProTheme.bodySm.copyWith(
                  color: _dragging
                      ? DriftProTheme.primaryGreen
                      : Colors.grey[600],
                  fontWeight: _dragging ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) {
                  final next = (_displayHeight + d.delta.dy)
                      .clamp(_minH, _maxH);
                  setState(() {
                    _dragging = true;
                    _dragHeight = next;
                  });
                  _applyHeight(next);
                },
                onVerticalDragEnd: (_) => setState(() {
                  _dragging = false;
                  _dragHeight = null;
                }),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: DriftProTheme.primaryGreen.withValues(
                        alpha: _dragging ? 0.2 : 0.1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: DriftProTheme.primaryGreen.withValues(
                          alpha: _dragging ? 0.7 : 0.3,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.drag_handle_rounded,
                          color: DriftProTheme.primaryGreen,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Dra for høyde',
                          style: DriftProTheme.bodySm.copyWith(
                            color: DriftProTheme.primaryGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusBar(bool isDark) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      color: feedBarColor(isDark),
      child: Row(
        children: [
          Text(
            '9:41',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const Spacer(),
          Icon(
            Icons.signal_cellular_alt,
            size: 12,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.wifi,
            size: 12,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.battery_full,
            size: 12,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ],
      ),
    );
  }

  Color feedBarColor(bool isDark) =>
      isDark ? const Color(0xFF0E1114) : const Color(0xFFF7F8FA);
}
