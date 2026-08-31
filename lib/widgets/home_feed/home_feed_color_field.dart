import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// Fargevelger med forhåndsvalg, hex og gjennomsiktighet.
class HomeFeedColorField extends StatefulWidget {
  const HomeFeedColorField({
    super.key,
    required this.label,
    required this.colorHex,
    required this.opacity,
    required this.onChanged,
    this.showOpacity = true,
  });

  final String label;
  final String colorHex;
  final double opacity;
  final void Function(String hex, double opacity) onChanged;
  final bool showOpacity;

  static const presets = [
    '#FFFFFF',
    '#000000',
    '#1B5E20',
    '#0D47A1',
    '#E53935',
    '#FFA726',
    '#29B6F6',
    '#E8E8E8',
    '#FFD700',
    '#9C27B0',
  ];

  @override
  State<HomeFeedColorField> createState() => _HomeFeedColorFieldState();
}

class _HomeFeedColorFieldState extends State<HomeFeedColorField> {
  late TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _hexCtrl = TextEditingController(text: widget.colorHex);
  }

  @override
  void didUpdateWidget(covariant HomeFeedColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.colorHex != widget.colorHex &&
        _hexCtrl.text.toUpperCase() != widget.colorHex.toUpperCase()) {
      _hexCtrl.text = widget.colorHex;
    }
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  Color _preview() => _parseHex(widget.colorHex, widget.opacity);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: HomeFeedColorField.presets.map((hex) {
            final selected = hex.toUpperCase() == widget.colorHex.toUpperCase();
            return InkWell(
              onTap: () => widget.onChanged(hex, widget.opacity),
              borderRadius: BorderRadius.circular(99),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _parseHex(hex, 1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? DriftProTheme.primaryGreen
                        : Colors.grey.withValues(alpha: 0.4),
                    width: selected ? 3 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _preview(),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _hexCtrl,
                decoration: const InputDecoration(
                  labelText: 'Hex (#RRGGBB)',
                  isDense: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[#0-9A-Fa-f]')),
                  LengthLimitingTextInputFormatter(7),
                ],
                onChanged: (v) {
                  var h = v.trim();
                  if (!h.startsWith('#')) h = '#$h';
                  if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(h)) {
                    widget.onChanged(h.toUpperCase(), widget.opacity);
                  }
                },
              ),
            ),
          ],
        ),
        if (widget.showOpacity) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Gjennomsiktighet'),
              Expanded(
                child: Slider(
                  value: widget.opacity.clamp(0, 1),
                  min: 0,
                  max: 1,
                  divisions: 20,
                  label: '${(widget.opacity * 100).round()}%',
                  onChanged: (v) =>
                      widget.onChanged(widget.colorHex, v),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text('${(widget.opacity * 100).round()}%'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

Color _parseHex(String hex, double opacity) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) {
    final v = int.tryParse(h, radix: 16);
    if (v != null) {
      return Color(v | 0xFF000000).withValues(alpha: opacity.clamp(0, 1));
    }
  }
  return Colors.white.withValues(alpha: opacity.clamp(0, 1));
}
