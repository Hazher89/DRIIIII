import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/hms/mavi_hms_handbook.dart';
import '../../../core/routing/app_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Leser ett HMS-håndbokdokument med tydelig CTA til riktig modul.
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
      final raw = await rootBundle.loadString(doc.assetPath);
      setState(() => _body = _clean(raw));
    } catch (e) {
      setState(() => _error = e);
    }
  }

  static String _clean(String raw) {
    var t = raw
        .replaceAll(RegExp(r'FORMTEXT|FORMCHECKBOX'), '')
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    // Strip leading junk whitespace lines
    t = t.replaceAll(RegExp(r'^[\s\t]+', multiLine: true), '');
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final doc = MaviHmsHandbook.byId(widget.docId);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? DriftProTheme.surfaceDark : const Color(0xFFF7F8F6);

    if (doc == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dokument')),
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
          ? Center(child: Text('Kunne ikke laste: $_error'))
          : _body == null
              ? const DriftProLoadingCenter()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? DriftProTheme.cardDark : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (doc.vedleggNr != null)
                            Text(
                              'Vedlegg ${doc.vedleggNr}',
                              style: DriftProTheme.caption.copyWith(
                                color: DriftProTheme.primaryGreen,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            doc.title,
                            style: DriftProTheme.headingSm.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            doc.summary,
                            style: DriftProTheme.bodyMd.copyWith(
                              height: 1.4,
                              color: Colors.black.withValues(alpha: isDark ? 0.65 : 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (doc.modulePath != null && doc.moduleLabel != null) ...[
                      const SizedBox(height: 14),
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
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SelectableText(
                      _body!,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
    );
  }
}
