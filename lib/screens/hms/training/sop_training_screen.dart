import 'package:flutter/material.dart';

import '../../../core/services/hms/sop_training_models.dart';
import '../../../core/services/hms/training_library_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import 'sop_training_widgets.dart';

/// Opplæring — smart søk i SOP + arbeidsinstrukser.
class SopTrainingScreen extends StatefulWidget {
  const SopTrainingScreen({super.key});

  @override
  State<SopTrainingScreen> createState() => _SopTrainingScreenState();
}

class _SopTrainingScreenState extends State<SopTrainingScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _lib = TrainingLibraryService.instance;

  bool _loading = true;
  String? _error;
  String _query = '';
  String? _docFilter;
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
      await _lib.loadAll();
      if (!mounted) return;
      setState(() => _loading = false);
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
      _hits = q.isEmpty ? const [] : _lib.search(q, docId: _docFilter);
    });
  }

  void _setDocFilter(String? docId) {
    setState(() {
      _docFilter = docId;
      if (_query.isNotEmpty) {
        _hits = _lib.search(_query, docId: docId);
      }
    });
  }

  void _clearFilters() {
    setState(() {
      _docFilter = null;
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

  void _browseDoc(TrainingDocMeta meta) {
    setState(() {
      _docFilter = meta.id;
      _searchCtrl.text = meta.title;
      _query = meta.title;
      _hits = _lib.search(meta.title, docId: meta.id);
    });
  }

  IconData _iconFor(String name) {
    switch (name) {
      case 'hub':
        return Icons.hub_rounded;
      case 'inventory_2':
        return Icons.inventory_2_rounded;
      case 'assignment_return':
        return Icons.assignment_return_rounded;
      case 'local_shipping':
        return Icons.local_shipping_rounded;
      default:
        return Icons.menu_book_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      body: _loading
          ? const DriftProLoadingCenter()
          : _error != null
              ? _buildError(isDark)
              : CustomScrollView(
                  slivers: [
                    _buildHeroHeader(isDark),
                    _buildDocFilters(isDark),
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
            Text('Kunne ikke laste opplæring', style: DriftProTheme.headingSm),
            const SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center, style: DriftProTheme.caption),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Prøv igjen')),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildHeroHeader(bool isDark) {
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
                            style: DriftProTheme.headingMd
                                .copyWith(color: Colors.white),
                          ),
                          Text(
                            '${TrainingLibraryService.docs.length} dokumenter · ${_lib.totalEntries} emner',
                            style: DriftProTheme.caption
                                .copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome,
                              color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Smart søk',
                            style: TextStyle(
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
                  'SOP Hub + arbeidsinstrukser — spør på norsk og få stegvise svar',
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
                      hintText:
                          'Spør — f.eks. «Undelivered», «returmottak» eller «1701»',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              onPressed: _clearFilters,
                              icon: const Icon(Icons.close_rounded),
                            )
                          : null,
                      filled: true,
                      fillColor:
                          isDark ? DriftProTheme.cardDark : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    textInputAction: TextInputAction.search,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Søker i alle dokumenter samtidig — synonymer og systemord støttes',
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

  SliverToBoxAdapter _buildDocFilters(bool isDark) {
    return SliverToBoxAdapter(
      child: Container(
        color: isDark ? DriftProTheme.surfaceDark : const Color(0xFFF0F4F8),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dokumenter',
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
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('Alle'),
                      selected: _docFilter == null,
                      onSelected: (_) => _setDocFilter(null),
                      selectedColor:
                          DriftProTheme.primaryGreen.withValues(alpha: 0.18),
                      checkmarkColor: DriftProTheme.primaryGreenDark,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: _docFilter == null
                            ? DriftProTheme.primaryGreenDark
                            : (isDark
                                ? Colors.white
                                : const Color(0xFF1A2B3C)),
                      ),
                    ),
                  ),
                  for (final meta in TrainingLibraryService.docs)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: Icon(_iconFor(meta.iconName), size: 16),
                        label: Text(meta.title),
                        selected: _docFilter == meta.id,
                        onSelected: (_) => _setDocFilter(
                          _docFilter == meta.id ? null : meta.id,
                        ),
                        selectedColor: DriftProTheme.primaryGreen
                            .withValues(alpha: 0.18),
                        checkmarkColor: DriftProTheme.primaryGreenDark,
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: _docFilter == meta.id
                              ? DriftProTheme.primaryGreenDark
                              : (isDark
                                  ? Colors.white
                                  : const Color(0xFF1A2B3C)),
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
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        sliver: SliverToBoxAdapter(
          child: Text('Bibliotek', style: DriftProTheme.headingSm),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: Column(
            children: [
              for (final meta in TrainingLibraryService.docs) ...[
                _DocLibraryCard(
                  meta: meta,
                  entryCount: _lib.docById(meta.id)?.entries.length ?? 0,
                  isDark: isDark,
                  icon: _iconFor(meta.iconName),
                  onTap: () => _browseDoc(meta),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        sliver: SliverToBoxAdapter(
          child: Text('Populære søk', style: DriftProTheme.headingSm),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        sliver: SliverToBoxAdapter(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in TrainingLibraryService.suggestedQueries)
                ActionChip(
                  avatar: Icon(Icons.trending_up,
                      size: 16, color: DriftProTheme.accentBlue),
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
        padding: EdgeInsets.fromLTRB(
            16, topHit?.isHighConfidence == true ? 12 : 16, 16, 8),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 18, color: DriftProTheme.accentBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  topHit?.isHighConfidence == true
                      ? 'Flere relevante treff'
                      : '${_hits.length} treff for «$_query»',
                  style: DriftProTheme.labelMd
                      .copyWith(fontWeight: FontWeight.w800),
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
                  Icon(Icons.search_off_rounded,
                      size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('Ingen treff', style: DriftProTheme.headingSm),
                  const SizedBox(height: 6),
                  Text(
                    'Prøv et annet søkeord — f.eks. 1701, Undelivered eller returmottak.',
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
            separatorBuilder: (_, _) => const SizedBox(height: 10),
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

class _DocLibraryCard extends StatelessWidget {
  const _DocLibraryCard({
    required this.meta,
    required this.entryCount,
    required this.isDark,
    required this.icon,
    required this.onTap,
  });

  final TrainingDocMeta meta;
  final int entryCount;
  final bool isDark;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: DriftProTheme.primaryGreenDark),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.title,
                      style: DriftProTheme.labelLg
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(meta.subtitle, style: DriftProTheme.caption),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: DriftProTheme.accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$entryCount',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
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
                          'Anbefalt svar',
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
    final related = TrainingLibraryService.instance.relatedEntries(entry);

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
