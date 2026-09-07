import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/hms/mavi_hms_handbook.dart';
import '../../../core/routing/app_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Moderne lesevisning for HMS-håndbokdokumenter.
class HmsHandbookDocScreen extends StatefulWidget {
  const HmsHandbookDocScreen({super.key, required this.docId});

  final String docId;

  @override
  State<HmsHandbookDocScreen> createState() => _HmsHandbookDocScreenState();
}

class _HmsHandbookDocScreenState extends State<HmsHandbookDocScreen> {
  String? _body;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = MaviHmsHandbook.byId(widget.docId);
    if (doc == null) {
      setState(() => _error = 'Fant ikke dokumentet');
      return;
    }
    try {
      final data = await rootBundle.load(doc.assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final raw = utf8.decode(bytes, allowMalformed: true);
      setState(() {
        _body = _clean(raw);
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e);
    }
  }

  static String _clean(String raw) {
    var t = raw
        .replaceAll(RegExp(r'FORMTEXT|FORMCHECKBOX'), '')
        .replaceAll('\u00a0', ' ')
        .replaceAll('\uFFFD', '')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    t = t.replaceAll(RegExp(r'^\s+', multiLine: true), '');
    // Drop redundant first title line if it duplicates doc title later in UI.
    return t;
  }

  List<_DocBlock> get _parsed {
    final body = _body ?? '';
    final out = <_DocBlock>[];
    for (final raw in body.split(RegExp(r'\n\s*\n'))) {
      final text = raw.trim();
      if (text.isEmpty) continue;
      out.add(_DocBlock.parse(text));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final doc = MaviHmsHandbook.byId(widget.docId);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? DriftProTheme.surfaceDark : const Color(0xFFF3F5F2);
    final ink =
        isDark ? Colors.white.withValues(alpha: 0.92) : const Color(0xFF152018);
    final muted =
        isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF5A6B5E);

    if (doc == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: const Text('Dokument'),
          backgroundColor: bg,
          elevation: 0,
        ),
        body: const Center(child: Text('Dokumentet finnes ikke')),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      body: _error != null
          ? _ErrorPane(message: '$_error', onRetry: _load)
          : _body == null
              ? const DriftProLoadingCenter()
              : CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      backgroundColor: bg,
                      foregroundColor: ink,
                      title: Text(
                        doc.shortLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      actions: [
                        if (doc.modulePath != null)
                          IconButton(
                            tooltip: doc.moduleLabel ?? 'Åpne modul',
                            onPressed: () => _openModule(doc),
                            icon: const Icon(Icons.open_in_new_rounded),
                          ),
                      ],
                    ),
                    SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _DocHero(doc: doc, isDark: isDark),
                                if (doc.modulePath != null &&
                                    doc.moduleLabel != null) ...[
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: () => _openModule(doc),
                                    icon: const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 18,
                                    ),
                                    label: Text(doc.moduleLabel!),
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          DriftProTheme.primaryGreen,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size.fromHeight(48),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 18),
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    20,
                                    18,
                                    22,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? DriftProTheme.cardDark
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: isDark
                                        ? null
                                        : [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.04),
                                              blurRadius: 18,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (var i = 0;
                                          i < _parsed.length;
                                          i++) ...[
                                        if (i > 0) const SizedBox(height: 16),
                                        _BlockView(
                                          block: _parsed[i],
                                          ink: ink,
                                          muted: muted,
                                          isDark: isDark,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'MAVI Logistikk AS · HMS / QHSE',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  void _openModule(HmsHandbookDoc doc) {
    final p = doc.modulePath!;
    if (p == AppPaths.hms) {
      context.go(p);
    } else {
      context.push(p);
    }
  }
}

class _DocHero extends StatelessWidget {
  const _DocHero({required this.doc, required this.isDark});
  final HmsHandbookDoc doc;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            DriftProTheme.primaryGreenDark,
            DriftProTheme.primaryGreen,
            DriftProTheme.primaryGreen.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (doc.vedleggNr != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _badgeLabel(doc.vedleggNr!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                doc.category.title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            doc.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.25,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            doc.summary,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 14.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  static String _badgeLabel(String raw) {
    if (raw.toLowerCase() == 'landax') return 'Landax';
    if (raw.toLowerCase() == 'export') return 'Eksport';
    if (raw.toLowerCase().startsWith('hoved')) return 'Hoveddok.';
    return 'Vedlegg $raw';
  }
}

enum _BlockKind { heading, bullets, paragraph }

class _DocBlock {
  const _DocBlock(this.kind, this.lines);
  final _BlockKind kind;
  final List<String> lines;

  factory _DocBlock.parse(String text) {
    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return const _DocBlock(_BlockKind.paragraph, ['']);
    }

    final first = lines.first;
    final bulletish = lines.every(
      (l) =>
          l.startsWith('•') ||
          l.startsWith('-') ||
          l.startsWith('*') ||
          RegExp(r'^\d+[.)]\s').hasMatch(l),
    );
    if (bulletish && lines.length >= 2) {
      return _DocBlock(
        _BlockKind.bullets,
        [
          for (final l in lines)
            l
                .replaceFirst(RegExp(r'^[•\-*]\s*'), '')
                .replaceFirst(RegExp(r'^\d+[.)]\s*'), '')
                .trim(),
        ],
      );
    }

    final isHeading = lines.length == 1 &&
        first.length <= 64 &&
        !first.endsWith('.') &&
        !first.endsWith(':') &&
        (first == first.toUpperCase() && RegExp(r'[A-ZÆØÅ]').hasMatch(first) ||
            first.length <= 40);

    if (isHeading || (lines.length == 1 && first.endsWith(':'))) {
      return _DocBlock(_BlockKind.heading, [first.replaceAll(RegExp(r':$'), '')]);
    }

    return _DocBlock(_BlockKind.paragraph, lines);
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({
    required this.block,
    required this.ink,
    required this.muted,
    required this.isDark,
  });

  final _DocBlock block;
  final Color ink;
  final Color muted;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    switch (block.kind) {
      case _BlockKind.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            block.lines.first,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.3,
              letterSpacing: -0.2,
              color: isDark
                  ? DriftProTheme.primaryGreen.withValues(alpha: 0.95)
                  : DriftProTheme.primaryGreenDark,
            ),
          ),
        );
      case _BlockKind.bullets:
        return Column(
          children: [
            for (final line in block.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 8, right: 10),
                      decoration: BoxDecoration(
                        color: DriftProTheme.primaryGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        line,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      case _BlockKind.paragraph:
        return SelectableText(
          block.lines.join('\n'),
          style: TextStyle(
            fontSize: 15.5,
            height: 1.55,
            color: ink,
          ),
        );
    }
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined,
                size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Kunne ikke åpne dokumentet',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Prøv igjen. Hvis feilen fortsetter, oppdater appen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Prøv igjen')),
          ],
        ),
      ),
    );
  }
}
