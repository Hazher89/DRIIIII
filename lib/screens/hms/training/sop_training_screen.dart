import 'package:flutter/material.dart';

import '../../../core/services/hms/sop_training_models.dart';
import '../../../core/services/hms/sop_training_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import 'sop_training_widgets.dart';

/// Opplæring — intelligent søk i Hub Driftsrutiner (SOP-HUB-001).
class SopTrainingScreen extends StatefulWidget {
  const SopTrainingScreen({super.key});

  @override
  State<SopTrainingScreen> createState() => _SopTrainingScreenState();
}

class _SopTrainingScreenState extends State<SopTrainingScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  SopTrainingDocument? _doc;
  bool _loading = true;
  String? _error;
  String _query = '';
  String? _systemFilter;
  List<SopSearchHit> _hits = const [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onQueryChanged);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onQueryChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await SopTrainingService.instance.load();
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onQueryChanged() {
    final q = _searchCtrl.text.trim();
    setState(() {
      _query = q;
      _hits = q.isEmpty ? const [] : SopTrainingService.instance.search(q);
      if (_systemFilter != null && q.isEmpty) {
        _applySystemFilter(_systemFilter!);
      }
    });
  }

  void _applySystemFilter(String system) {
    setState(() {
      _systemFilter = system;
      _searchCtrl.text = system;
      _query = system;
      _hits = SopTrainingService.instance.search(system);
    });
  }

  void _clearFilters() {
    setState(() {
      _systemFilter = null;
      _searchCtrl.clear();
      _query = '';
      _hits = const [];
    });
  }

  void _openEntry(SopTrainingEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SopEntryDetailSheet(
        entry: entry,
        query: _query,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      body: _loading
          ? const DriftProLoadingCenter()
          : _error != null
              ? _buildError(isDark)
              : CustomScrollView(
                  slivers: [
                    _buildHeroHeader(isDark),
                    _buildSystemFilters(isDark),
                    if (_query.isEmpty) ..._buildLandingSlivers(isDark),
                    if (_query.isNotEmpty) ..._buildResultsSlivers(isDark),
                  ],
                ),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: DriftProTheme.error),
            const SizedBox(height: 12),
            Text('Kunne ikke laste SOP', style: DriftProTheme.headingSm),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: DriftProTheme.caption),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Prøv igjen')),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildHeroHeader(bool isDark) {
    final doc = _doc!;
    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              DriftProTheme.primaryGreenDark,
              DriftProTheme.accentBlueDark,
              isDark ? const Color(0xFF0A1628) : DriftProTheme.accentBlue,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Opplæring',
                            style: DriftProTheme.headingMd.copyWith(color: Colors.white),
                          ),
                          Text(
                            doc.version.isNotEmpty
                                ? '${doc.documentNumber} · v${doc.version}'
                                : doc.documentNumber,
                            style: DriftProTheme.caption.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '${doc.entries.length} emner',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  doc.subtitle,
                  style: DriftProTheme.bodyMd.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Material(
                  elevation: 8,
                  shadowColor: Colors.black45,
                  borderRadius: BorderRadius.circular(16),
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    style: DriftProTheme.bodyMd,
                    decoration: InputDecoration(
                      hintText: 'Spør på norsk — f.eks. «Hvordan behandle kolli Undelivered?»',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              onPressed: _clearFilters,
                              icon: const Icon(Icons.close_rounded),
                            )
                          : null,
                      filled: true,
                      fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    textInputAction: TextInputAction.search,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Smart søk forstår synonymer, engelske systemord og hele spørsmål',
                  style: DriftProTheme.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildSystemFilters(bool isDark) {
    final doc = _doc!;
    return SliverToBoxAdapter(
      child: Container(
        color: isDark ? DriftProTheme.surfaceDark : const Color(0xFFF0F4F8),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filtrer på system',
              style: DriftProTheme.caption.copyWith(
                fontWeight: FontWeight.w800,
                color: DriftProTheme.primaryGreenDark,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final system in doc.systems)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(system),
                        onPressed: () => _applySystemFilter(system),
                        backgroundColor: _systemFilter == system
                            ? DriftProTheme.primaryGreen.withValues(alpha: 0.15)
                            : (isDark ? DriftProTheme.cardDark : Colors.white),
                        side: BorderSide(
                          color: _systemFilter == system
                              ? DriftProTheme.primaryGreen
                              : Colors.grey.shade300,
                        ),
                        labelStyle: TextStyle(
                          color: _systemFilter == system
                              ? DriftProTheme.primaryGreenDark
                              : (isDark ? Colors.white : const Color(0xFF1A2B3C)),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLandingSlivers(bool isDark) {
    final doc = _doc!;
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        sliver: SliverToBoxAdapter(
          child: Text('Populære søk', style: DriftProTheme.headingSm),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in SopTrainingService.suggestedQueries)
                ActionChip(
                  avatar: Icon(Icons.trending_up, size: 16, color: DriftProTheme.accentBlue),
                  label: Text(q),
                  onPressed: () {
                    _searchCtrl.text = q;
                    _searchFocus.unfocus();
                  },
                ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        sliver: SliverToBoxAdapter(
          child: Text('Seksjoner i SOP', style: DriftProTheme.headingSm),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        sliver: SliverList.separated(
          itemCount: doc.sections.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final section = doc.sections[i];
            final count = doc.entries.where((e) => e.section == section).length;
            return _SectionCard(
              isDark: isDark,
              title: section,
              count: count,
              onTap: () {
                _searchCtrl.text = section.split('—').first.trim();
              },
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _buildResultsSlivers(bool isDark) {
    final topHit = _hits.isNotEmpty ? _hits.first : null;
    return [
      if (topHit != null && topHit.isHighConfidence)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: _AiAnswerCard(
              hit: topHit,
              query: _query,
              isDark: isDark,
              onTap: () => _openEntry(topHit.entry),
            ),
          ),
        ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, topHit?.isHighConfidence == true ? 12 : 16, 16, 8),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: DriftProTheme.accentBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  topHit?.isHighConfidence == true
                      ? 'Flere relevante treff'
                      : '${_hits.length} treff for «$_query»',
                  style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
      if (_hits.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off_rounded, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('Ingen treff', style: DriftProTheme.headingSm),
                  const SizedBox(height: 6),
                  Text(
                    'Prøv et annet søkeord — f.eks. Goran, FO Search eller returer.',
                    textAlign: TextAlign.center,
                    style: DriftProTheme.caption,
                  ),
                ],
              ),
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverList.separated(
            itemCount: _hits.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final hit = _hits[i];
              return _ResultCard(
                hit: hit,
                query: _query,
                isDark: isDark,
                onTap: () => _openEntry(hit.entry),
              );
            },
          ),
        ),
    ];
  }
}

class _AiAnswerCard extends StatelessWidget {
  const _AiAnswerCard({
    required this.hit,
    required this.query,
    required this.isDark,
    required this.onTap,
  });

  final SopSearchHit hit;
  final String query;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(18),
      elevation: 3,
      shadowColor: DriftProTheme.accentBlue.withValues(alpha: 0.25),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                DriftProTheme.accentBlue.withValues(alpha: 0.08),
                DriftProTheme.primaryGreen.withValues(alpha: 0.1),
              ],
            ),
            border: Border.all(color: DriftProTheme.accentBlue.withValues(alpha: 0.25)),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: DriftProTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Anbefalt svar fra SOP',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(hit.confidence * 100).round()}% treff',
                    style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                hit.entry.title,
                style: DriftProTheme.labelMd.copyWith(
                  fontWeight: FontWeight.w800,
                  color: DriftProTheme.primaryGreenDark,
                ),
              ),
              const SizedBox(height: 8),
              SopHighlightedText(
                text: hit.answer,
                query: query,
                style: DriftProTheme.bodyMd.copyWith(
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1A2B3C),
                ),
              ),
              if (hit.entry.section.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  hit.entry.section,
                  style: DriftProTheme.caption.copyWith(color: DriftProTheme.accentBlue),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Trykk for full prosedyre',
                    style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.isDark,
    required this.title,
    required this.count,
    required this.onTap,
  });

  final bool isDark;
  final String title;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.folder_open_rounded, color: DriftProTheme.primaryGreen),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: DriftProTheme.labelMd)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: DriftProTheme.accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$count', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.hit,
    required this.query,
    required this.isDark,
    required this.onTap,
  });

  final SopSearchHit hit;
  final String query;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final entry = hit.entry;
    final priorityColor = sopPriorityColor(entry.priority);

    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: isDark ? 0 : 1,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (entry.priority == 'KRITISK'
                      ? DriftProTheme.error
                      : DriftProTheme.primaryGreen)
                  .withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: DriftProTheme.accentBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(sopKindIcon(entry.kind), size: 14, color: DriftProTheme.accentBlue),
                        const SizedBox(width: 4),
                        Text(
                          sopKindLabel(entry.kind),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  if (entry.system != null) ...[
                    const SizedBox(width: 6),
                    _pill(entry.system!, DriftProTheme.primaryGreen),
                  ],
                  if (entry.priority != null) ...[
                    const SizedBox(width: 6),
                    _pill(entry.priority!, priorityColor),
                  ],
                  const Spacer(),
                  const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                entry.title,
                style: DriftProTheme.labelLg.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1A2B3C),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (entry.section.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  [entry.section, entry.subsection].where((s) => s.isNotEmpty).join(' › '),
                  style: DriftProTheme.caption.copyWith(
                    color: DriftProTheme.accentBlue,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? DriftProTheme.surfaceDark
                      : const Color(0xFFF7FAF8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: SopHighlightedText(
                  text: hit.answer.isNotEmpty ? hit.answer : hit.snippet,
                  query: query,
                  style: DriftProTheme.bodyMd.copyWith(
                    height: 1.45,
                    color: isDark ? Colors.white70 : const Color(0xFF2C3E50),
                  ),
                  maxLines: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

class _SopEntryDetailSheet extends StatelessWidget {
  const _SopEntryDetailSheet({
    required this.entry,
    required this.query,
  });

  final SopTrainingEntry entry;
  final String query;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final related = SopTrainingService.instance.relatedEntries(entry);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? DriftProTheme.cardDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: DriftProTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(sopKindIcon(entry.kind), color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sopKindLabel(entry.kind), style: DriftProTheme.caption),
                        SopHighlightedText(
                          text: entry.title,
                          query: query,
                          style: DriftProTheme.headingSm,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (entry.section.isNotEmpty) ...[
                const SizedBox(height: 14),
                _metaRow(Icons.map_outlined, 'Seksjon', entry.section),
              ],
              if (entry.subsection.isNotEmpty)
                _metaRow(Icons.subdirectory_arrow_right, 'Underseksjon', entry.subsection),
              if (entry.system != null)
                _metaRow(Icons.hub_outlined, 'System', entry.system!),
              if (entry.priority != null)
                _metaRow(
                  Icons.flag_outlined,
                  'Prioritet',
                  entry.priority!,
                  valueColor: sopPriorityColor(entry.priority),
                ),
              const SizedBox(height: 18),
              Text('Hva skal du gjøre?', style: DriftProTheme.labelLg),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? DriftProTheme.surfaceDark
                      : DriftProTheme.primaryGreen.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
                  ),
                ),
                child: SopHighlightedText(
                  text: entry.answer,
                  query: query,
                  style: DriftProTheme.bodyMd.copyWith(height: 1.55, fontSize: 15),
                ),
              ),
              if (entry.relatedColumns.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('Detaljer', style: DriftProTheme.labelLg),
                const SizedBox(height: 8),
                for (final col in entry.relatedColumns.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _metaRow(Icons.table_rows_outlined, col.key, col.value),
                  ),
              ],
              if (related.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Relaterte oppgaver', style: DriftProTheme.labelLg),
                const SizedBox(height: 8),
                for (final r in related)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: isDark ? DriftProTheme.surfaceDark : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        leading: Icon(sopKindIcon(r.kind), color: DriftProTheme.accentBlue),
                        title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: r.system != null ? Text(r.system!) : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(context);
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => _SopEntryDetailSheet(entry: r, query: query),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _metaRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(label, style: DriftProTheme.caption),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              style: DriftProTheme.bodyMd.copyWith(
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
