import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/hms/mavi_hms_handbook.dart';
import '../../../core/routing/app_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Leser ett HMS-håndbokdokument — robust lasting og ryddig lesevisning.
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
    return t;
  }

  List<String> get _blocks {
    final body = _body ?? '';
    return body
        .split(RegExp(r'\n\s*\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final doc = MaviHmsHandbook.byId(widget.docId);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? DriftProTheme.surfaceDark : const Color(0xFFF7F8F6);
    final ink = isDark ? Colors.white.withValues(alpha: 0.92) : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.5);

    if (doc == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(title: const Text('Dokument'), backgroundColor: bg, elevation: 0),
        body: const Center(child: Text('Dokumentet finnes ikke')),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(doc.shortLabel),
        backgroundColor: bg,
        elevation: 0,
      ),
      body: _error != null
          ? _ErrorPane(message: '$_error', onRetry: _load)
          : _body == null
              ? const DriftProLoadingCenter()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isDark ? DriftProTheme.cardDark : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: DriftProTheme.primaryGreen.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (doc.vedleggNr != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Vedlegg ${doc.vedleggNr}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: DriftProTheme.primaryGreen,
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              Text(
                                'MAVI Logistikk',
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            doc.title,
                            style: DriftProTheme.headingSm.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            doc.summary,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (doc.modulePath != null && doc.moduleLabel != null) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () {
                          final p = doc.modulePath!;
                          if (p == AppPaths.hms) {
                            context.go(p);
                          } else {
                            context.push(p);
                          }
                        },
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(doc.moduleLabel!),
                        style: FilledButton.styleFrom(
                          backgroundColor: DriftProTheme.primaryGreen,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    for (final block in _blocks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _BodyBlock(text: block, ink: ink, isDark: isDark),
                      ),
                  ],
                ),
    );
  }
}

class _BodyBlock extends StatelessWidget {
  const _BodyBlock({
    required this.text,
    required this.ink,
    required this.isDark,
  });

  final String text;
  final Color ink;
  final bool isDark;

  bool get _isHeading {
    final first = text.split('\n').first.trim();
    if (first.length > 72) return false;
    if (first == first.toUpperCase() && RegExp(r'[A-ZÆØÅ]').hasMatch(first)) {
      return true;
    }
    // Short title-like lines without ending punctuation
    return first.length <= 42 &&
        !first.endsWith('.') &&
        !first.startsWith('•') &&
        text.split('\n').length == 1;
  }

  @override
  Widget build(BuildContext context) {
    if (_isHeading) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w800,
          height: 1.35,
          color: DriftProTheme.primaryGreen.withValues(alpha: isDark ? 0.95 : 1),
        ),
      );
    }
    return SelectableText(
      text,
      style: TextStyle(
        fontSize: 15,
        height: 1.55,
        color: ink,
      ),
    );
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
            Icon(Icons.description_outlined, size: 40, color: Colors.grey.shade400),
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
