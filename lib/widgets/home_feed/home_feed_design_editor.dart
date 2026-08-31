import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/home_feed_item.dart';
import '../../models/home_feed_layout_config.dart';
import 'home_feed_color_field.dart';
import 'home_feed_dual_preview.dart';

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
  bool _useCustomHeightApp = false;
  bool _useCustomHeightWeb = false;
  double _heightApp = 220;
  double _heightWeb = 260;

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
    _tabs = TabController(length: 4, vsync: this);
    _titleCtrl = TextEditingController(text: widget.item.title);
    _captionCtrl = TextEditingController(text: widget.item.caption ?? '');
    _layout = widget.item.layoutConfig;
    _useCustomHeightApp = _layout.customHeightApp != null;
    _useCustomHeightWeb = _layout.customHeightWeb != null;
    _heightApp = _layout.customHeightApp ??
        _layout.resolveHeight(isWeb: false, compactPreview: false);
    _heightWeb = _layout.customHeightWeb ??
        _layout.resolveHeight(isWeb: true, compactPreview: false);
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
            Tab(text: 'Størrelse'),
            Tab(text: 'Tekst'),
            Tab(text: 'Farger'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildPreviewTab(),
          _buildSizeTab(),
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
        Text(
          'Slik ser innholdet ut for brukerne — juster i fanene og se endringene live.',
          style: DriftProTheme.bodySm.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        HomeFeedDualPreview(item: _previewItem, layout: _layout),
      ],
    );
  }

  Widget _buildSizeTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Størrelse på forsiden', style: DriftProTheme.labelLg),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: HomeFeedSizePreset.values.map((preset) {
            final selected = _layout.sizePreset == preset;
            return ChoiceChip(
              label: Text(preset.label),
              selected: selected,
              onSelected: (_) => _setLayout(
                _layout.copyWith(
                  sizePreset: preset,
                  clearCustomHeightApp: !_useCustomHeightApp,
                  clearCustomHeightWeb: !_useCustomHeightWeb,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Dekk hele forsiden (hero)'),
          subtitle: const Text('Maksimal høyde — dominerer oversikten'),
          value: _layout.fullPageHero,
          onChanged: (v) => _setLayout(_layout.copyWith(fullPageHero: v)),
        ),
        SwitchListTile(
          title: const Text('Kant-til-kant'),
          subtitle: const Text('Ingen side-margin — full bredde'),
          value: _layout.edgeToEdge,
          onChanged: (v) => _setLayout(_layout.copyWith(edgeToEdge: v)),
        ),
        const Divider(height: 28),
        Text('Egendefinert høyde', style: DriftProTheme.labelLg),
        SwitchListTile(
          title: const Text('App — egen høyde (px)'),
          value: _useCustomHeightApp,
          onChanged: (v) {
            setState(() {
              _useCustomHeightApp = v;
              _setLayout(_layout.copyWith(
                customHeightApp: v ? _heightApp : null,
                clearCustomHeightApp: !v,
              ));
            });
          },
        ),
        if (_useCustomHeightApp)
          Slider(
            value: _heightApp.clamp(80, 720),
            min: 80,
            max: 720,
            divisions: 32,
            label: '${_heightApp.round()} px',
            onChanged: (v) {
              setState(() {
                _heightApp = v;
                _setLayout(_layout.copyWith(customHeightApp: v));
              });
            },
          ),
        SwitchListTile(
          title: const Text('Web — egen høyde (px)'),
          value: _useCustomHeightWeb,
          onChanged: (v) {
            setState(() {
              _useCustomHeightWeb = v;
              _setLayout(_layout.copyWith(
                customHeightWeb: v ? _heightWeb : null,
                clearCustomHeightWeb: !v,
              ));
            });
          },
        ),
        if (_useCustomHeightWeb)
          Slider(
            value: _heightWeb.clamp(80, 720),
            min: 80,
            max: 720,
            divisions: 32,
            label: '${_heightWeb.round()} px',
            onChanged: (v) {
              setState(() {
                _heightWeb = v;
                _setLayout(_layout.copyWith(customHeightWeb: v));
              });
            },
          ),
        const Divider(height: 28),
        Text('Media', style: DriftProTheme.labelLg),
        const SizedBox(height: 8),
        SegmentedButton<HomeFeedMediaFit>(
          segments: HomeFeedMediaFit.values
              .map((f) => ButtonSegment(value: f, label: Text(f.label)))
              .toList(),
          selected: {_layout.mediaFit},
          onSelectionChanged: (s) =>
              _setLayout(_layout.copyWith(mediaFit: s.first)),
        ),
        const SizedBox(height: 12),
        Text('Hjørner: ${_layout.borderRadius.round()} px'),
        Slider(
          value: _layout.borderRadius.clamp(0, 32),
          min: 0,
          max: 32,
          divisions: 32,
          onChanged: (v) => _setLayout(_layout.copyWith(borderRadius: v)),
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
        HomeFeedDualPreview(item: _previewItem, layout: _layout),
      ],
    );
  }
}
