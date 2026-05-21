import 'package:flutter/material.dart';

import '../../../core/services/wallboard/nrk_news_feed_service.dart';
import '../../../core/theme/wallboard_palette.dart';

/// NRK-lignende rulletekst nederst på infoskjermen.
class WallboardNewsTicker extends StatelessWidget {
  final List<NrkHeadline> headlines;

  const WallboardNewsTicker({super.key, required this.headlines});

  @override
  Widget build(BuildContext context) {
    if (headlines.isEmpty) {
      return Container(
        height: 40,
        color: WallboardPalette.tickerBg,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Text(
          'NRK Nyheter — henter siste overskrifter …',
          style: TextStyle(color: WallboardPalette.textMuted, fontSize: 12),
        ),
      );
    }

    final text = headlines.map((h) => h.title).join('     •     ');

    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: WallboardPalette.tickerBg,
        border: Border(top: BorderSide(color: WallboardPalette.tickerBorder)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: WallboardPalette.nrkBadge,
            alignment: Alignment.center,
            child: const Text(
              'NRK',
              style: TextStyle(
                color: WallboardPalette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return _ScrollingText(
                  text: text,
                  maxWidth: constraints.maxWidth,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollingText extends StatefulWidget {
  final String text;
  final double maxWidth;

  const _ScrollingText({required this.text, required this.maxWidth});

  @override
  State<_ScrollingText> createState() => _ScrollingTextState();
}

class _ScrollingTextState extends State<_ScrollingText>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
  }

  @override
  void didUpdateWidget(_ScrollingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller?.dispose();
      _controller = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _setup() {
    if (!mounted) return;
    const style = TextStyle(
      color: WallboardPalette.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    );
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final textW = painter.width + 48;
    final travel = textW + widget.maxWidth;
    final seconds = (travel / 55).clamp(18.0, 120.0);

    _controller?.dispose();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: seconds.round()),
    )..repeat();

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    if (ctrl == null) return const SizedBox.shrink();

    const style = TextStyle(
      color: WallboardPalette.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    );

    return ClipRect(
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (context, child) {
          final t = ctrl.value;
          final painter = TextPainter(
            text: TextSpan(text: widget.text, style: style),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout();
          final textW = painter.width + 48;
          final offset = widget.maxWidth - t * (textW + widget.maxWidth);

          return Transform.translate(
            offset: Offset(offset, 0),
            child: Row(
              children: [
                Text(widget.text, style: style, maxLines: 1),
                const SizedBox(width: 48),
                Text(widget.text, style: style, maxLines: 1),
              ],
            ),
          );
        },
      ),
    );
  }
}
