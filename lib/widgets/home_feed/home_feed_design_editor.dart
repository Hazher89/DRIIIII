import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/home_feed_item.dart';
import '../../models/home_feed_layout_config.dart';
import 'home_feed_color_field.dart';
import 'home_feed_interactive_preview.dart';

/// Visuell editor — størrelse, tekst, farger og live app/web-forhåndsvisning.
class HomeFeedDesignEditor extends StatefulWidget {
  const HomeFeedDesignEditor({
    super.key,
    required this.item,
    required this.onSave,
  });

  final HomeFeedItem item;
  final Future<void> Function(HomeFeedItem updated) onSave;

  static Future<bool?> open(
    BuildContext context, {
    required HomeFeedItem item,
    required Future<void> Function(HomeFeedItem updated) onSave,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => HomeFeedDesignEditor(item: item, onSave: onSave),
      ),
    );
  }

  @override
  State<HomeFeedDesignEditor> createState() => _HomeFeedDesignEditorState();
}

class _HomeFeedDesignEditorState extends State<HomeFeedDesignEditor>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late TextEditingController _titleCtrl;
  late TextEditingController _captionCtrl;
  late HomeFeedLayoutConfig _layout;
  bool _saving = false;

  HomeFeedItem get _previewItem => widget.item.copyWith(
        title: _titleCtrl.text.trim(),
        caption: _captionCtrl.text.trim().isEmpty
            ? null
            : _captionCtrl.text.trim(),
        layoutConfig: _layout,
      );

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _titleCtrl = TextEditingController(text: widget.item.title);
    _captionCtrl = TextEditingController(text: widget.item.caption ?? '');
    _layout = widget.item.layoutConfig;
    _titleCtrl.addListener(() => setState(() {}));
    _captionCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _titleCtrl.dispose();
    _captionCtrl.dispose();
    super.dispose();
  }

  void _setLayout(HomeFeedLayoutConfig layout) {
    setState(() => _layout = layout);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = widget.item.copyWith(
        title: _titleCtrl.text.trim(),
        caption: _captionCtrl.text.trim().isEmpty
            ? null
            : _captionCtrl.text.trim(),
        layoutConfig: _layout,
      );
      await widget.onSave(updated);
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
        title: const Text('Tilpass forside'),
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
            Tab(text: 'Tekst'),
            Tab(text: 'Farger'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildPreviewTab(),
          _buildTextTab(),
          _buildColorsTab(),
        ],
      ),
    );
  }

  Widget _buildPreviewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        HomeFeedInteractivePreview(
          item: _previewItem,
          layout: _layout,
          onLayoutChanged: (layout) {
            setState(() => _layout = layout);
          },
        ),
      ],
    );
  }

  Widget _buildTextTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(
            labelText: 'Tittel',
            hintText: 'F.eks. Velkommen til ny sesong',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _captionCtrl,
          decoration: const InputDecoration(
            labelText: 'Undertekst',
            hintText: 'Valgfri beskrivelse',
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 20),
        Text('Plassering', style: DriftProTheme.labelLg),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: HomeFeedTextPosition.values.map((pos) {
            return ChoiceChip(
              label: Text(pos.label),
              selected: _layout.textPosition == pos,
              onSelected: (_) =>
                  _setLayout(_layout.copyWith(textPosition: pos)),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text('Justering', style: DriftProTheme.labelLg),
        SegmentedButton<TextAlign>(
          segments: const [
            ButtonSegment(
              value: TextAlign.left,
              label: Text('Venstre'),
              icon: Icon(Icons.format_align_left),
            ),
            ButtonSegment(
              value: TextAlign.center,
              label: Text('Midt'),
              icon: Icon(Icons.format_align_center),
            ),
            ButtonSegment(
              value: TextAlign.right,
              label: Text('Høyre'),
              icon: Icon(Icons.format_align_right),
            ),
          ],
          selected: {_layout.textAlign},
          onSelectionChanged: (s) =>
              _setLayout(_layout.copyWith(textAlign: s.first)),
        ),
        const Divider(height: 28),
        _textStyleSection(
          title: 'Tittel',
          style: _layout.titleStyle,
          onChanged: (s) => _setLayout(_layout.copyWith(titleStyle: s)),
        ),
        const SizedBox(height: 20),
        _textStyleSection(
          title: 'Undertekst',
          style: _layout.captionStyle,
          onChanged: (s) => _setLayout(_layout.copyWith(captionStyle: s)),
        ),
      ],
    );
  }

  Widget _textStyleSection({
    required String title,
    required HomeFeedTextStyleConfig style,
    required ValueChanged<HomeFeedTextStyleConfig> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: DriftProTheme.labelLg),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: HomeFeedTextSize.values.map((size) {
            return ChoiceChip(
              label: Text('${size.fontSize.round()}'),
              selected: style.size == size,
              onSelected: (_) => onChanged(style.copyWith(size: size)),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Fet skrift'),
          value: style.bold,
          onChanged: (v) => onChanged(style.copyWith(bold: v)),
        ),
      ],
    );
  }

  Widget _buildColorsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        HomeFeedColorField(
          label: 'Tittelfarge',
          colorHex: _layout.titleStyle.colorHex,
          opacity: _layout.titleStyle.opacity,
          showOpacity: false,
          onChanged: (hex, opacity) => _setLayout(
            _layout.copyWith(
              titleStyle: _layout.titleStyle.copyWith(
                colorHex: hex,
                opacity: opacity,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        HomeFeedColorField(
          label: 'Undertekstfarge',
          colorHex: _layout.captionStyle.colorHex,
          opacity: _layout.captionStyle.opacity,
          showOpacity: false,
          onChanged: (hex, opacity) => _setLayout(
            _layout.copyWith(
              captionStyle: _layout.captionStyle.copyWith(
                colorHex: hex,
                opacity: opacity,
              ),
            ),
          ),
        ),
        if (_layout.textPosition.isOverlay) ...[
          const SizedBox(height: 24),
          HomeFeedColorField(
            label: 'Overlay bak tekst',
            colorHex: _layout.overlayColorHex,
            opacity: _layout.overlayOpacity,
            onChanged: (hex, opacity) => _setLayout(
              _layout.copyWith(
                overlayColorHex: hex,
                overlayOpacity: opacity,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        HomeFeedInteractivePreview(
          item: _previewItem,
          layout: _layout,
          onLayoutChanged: _setLayout,
          showToolbar: false,
        ),
      ],
    );
  }
}
