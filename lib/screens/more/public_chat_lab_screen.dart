import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/user_access.dart';
import '../../core/routing/app_paths.dart';
import '../../core/services/assistant/knowledge_assistant_service.dart';
import '../../core/services/assistant/public_chat_knowledge_service.dart';
import '../../core/services/assistant/public_montage_assistant_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Superadmin-lab: mate CCC-chatten eller intern Spør DriftPro.
class PublicChatLabScreen extends StatefulWidget {
  const PublicChatLabScreen({
    super.key,
    this.channel = PublicChatKnowledgeService.channelPublic,
  });

  /// `public` = /montering CCC-chat, `internal` = Spør DriftPro for ansatte.
  final String channel;

  @override
  State<PublicChatLabScreen> createState() => _PublicChatLabScreenState();
}

class _PublicChatLabScreenState extends State<PublicChatLabScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  String? _companyId;
  bool _allowed = false;
  List<PublicChatKnowledgeEntry> _rows = const [];
  PublicChatKnowledgeStats? _stats;

  bool get _isInternal =>
      widget.channel == PublicChatKnowledgeService.channelInternal;

  String get _labTitle =>
      _isInternal ? 'DriftPro Assistent-lab' : 'CCC Chat Lab';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _bootstrap();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await SupabaseService.fetchEffectiveUserProfile();
      if (profile == null || !profile.isSuperAdmin || profile.companyId == null) {
        setState(() {
          _allowed = false;
          _loading = false;
          _error = 'Kun superadmin har tilgang til $_labTitle.';
        });
        return;
      }
      _companyId = profile.companyId;
      _allowed = true;
      await _reload();
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _reload() async {
    final companyId = _companyId;
    if (companyId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await PublicChatKnowledgeService.instance.listForCompany(
        companyId,
        channel: widget.channel,
      );
      final stats = await PublicChatKnowledgeService.instance.statsFor(rows);
      if (_isInternal) {
        await KnowledgeAssistantService.instance.reload();
      } else {
        await PublicMontageAssistantService.instance.reloadKnowledge();
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      setState(() {
        _loading = false;
        _error = msg.contains('public_chat_knowledge') ||
                msg.contains('schema cache') ||
                msg.contains('does not exist') ||
                msg.contains('channel')
            ? 'Database mangler Chat Lab / channel. Kjør migrasjonene '
                '20260907180000_public_chat_knowledge_lab.sql og '
                '20260907230000_assistant_knowledge_channel.sql i Supabase.'
            : msg;
      });
    }
  }

  Future<void> _openEditor({PublicChatKnowledgeEntry? existing, String? kind}) async {
    final companyId = _companyId;
    if (companyId == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _KnowledgeEditorSheet(
        companyId: companyId,
        channel: widget.channel,
        existing: existing,
        initialKind: kind ?? existing?.kind ?? 'rule',
        isInternal: _isInternal,
      ),
    );
    if (saved == true) await _reload();
  }

  Future<void> _uploadDocs() async {
    final companyId = _companyId;
    if (companyId == null) return;
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'txt', 'md'],
    );
    if (picked == null || picked.files.isEmpty) return;
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: DriftProLoadingIndicator()),
    );

    try {
      for (final f in picked.files) {
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        final mime = f.extension?.toLowerCase() == 'pdf'
            ? 'application/pdf'
            : 'text/plain';
        final ingested =
            await PublicChatKnowledgeService.instance.ingestFile(
          companyId: companyId,
          fileName: f.name,
          bytes: bytes,
          mimeType: mime,
        );
        await PublicChatKnowledgeService.instance.upsert(
          companyId: companyId,
          kind: 'document',
          title: f.name.replaceAll(RegExp(r'\.(pdf|txt|md)$', caseSensitive: false), ''),
          content: ingested.text,
          tags: _isInternal
              ? const ['dokument', 'opplastet', 'intern']
              : const ['dokument', 'opplastet'],
          priority: 70,
          channel: widget.channel,
          sourceFilename: f.name,
          storagePath: ingested.storagePath,
          mimeType: ingested.mime,
          byteSize: ingested.bytes,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lastet opp ${picked.files.length} fil(er)')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? DriftProTheme.surfaceDark : const Color(0xFFF4F6F3);

    if (_loading && _rows.isEmpty) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(title: Text(_labTitle), backgroundColor: bg),
        body: const Center(child: DriftProLoadingIndicator()),
      );
    }

    if (!_allowed) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(title: Text(_labTitle), backgroundColor: bg),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error ?? 'Ingen tilgang', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final stats = _stats;
    final liveChunks = _isInternal
        ? KnowledgeAssistantService.instance.liveChunkCount
        : PublicMontageAssistantService.instance.liveChunkCount;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(_labTitle),
        backgroundColor: bg,
        elevation: 0,
        actions: [
          if (!_isInternal)
            IconButton(
              tooltip: 'Åpne offentlig chat',
              onPressed: () => context.push(AppPaths.chatt),
              icon: const Icon(Icons.open_in_new_rounded),
            ),
          IconButton(
            tooltip: 'Oppdater',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: DriftProTheme.primaryGreen,
          unselectedLabelColor: Colors.black54,
          indicatorColor: DriftProTheme.primaryGreen,
          tabs: const [
            Tab(text: 'Oversikt'),
            Tab(text: 'Kunnskap'),
            Tab(text: 'Q&A'),
            Tab(text: 'Last opp'),
            Tab(text: 'Test-lab'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(kind: 'rule'),
        backgroundColor: DriftProTheme.primaryGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Ny kunnskap'),
      ),
      body: Column(
        children: [
          if (_error != null)
            Material(
              color: Colors.orange.shade50,
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded),
                title: Text(_error!, style: const TextStyle(fontSize: 13)),
                trailing: TextButton(onPressed: _reload, child: const Text('Prøv')),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _OverviewTab(
                  isInternal: _isInternal,
                  stats: stats,
                  liveChunks: liveChunks,
                  onUpload: _uploadDocs,
                  onNewRule: () => _openEditor(kind: 'rule'),
                  onNewQa: () => _openEditor(kind: 'qa'),
                  onOpenChat: _isInternal
                      ? null
                      : () => context.push(AppPaths.chatt),
                ),
                _KnowledgeListTab(
                  rows: _rows,
                  onEdit: (e) => _openEditor(existing: e),
                  onToggleActive: (e) async {
                    await PublicChatKnowledgeService.instance
                        .setActive(id: e.id, active: !e.active);
                    await _reload();
                  },
                  onTogglePublished: (e) async {
                    await PublicChatKnowledgeService.instance
                        .setPublished(id: e.id, published: !e.published);
                    await _reload();
                  },
                  onDelete: (e) async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Slette?'),
                        content: Text('Slett «${e.title}» permanent?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Avbryt'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Slett'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await PublicChatKnowledgeService.instance
                          .delete(e.id, storagePath: e.storagePath);
                      await _reload();
                    }
                  },
                ),
                _KnowledgeListTab(
                  rows: _rows.where((e) => e.kind == 'qa').toList(),
                  emptyHint: _isInternal
                      ? 'Ingen Q&A ennå. Lær Spør DriftPro typiske MAVI-spørsmål.'
                      : 'Ingen Q&A ennå. Lær chatten typiske spørsmål og fasitsvar.',
                  onEdit: (e) => _openEditor(existing: e),
                  onToggleActive: (e) async {
                    await PublicChatKnowledgeService.instance
                        .setActive(id: e.id, active: !e.active);
                    await _reload();
                  },
                  onTogglePublished: (e) async {
                    await PublicChatKnowledgeService.instance
                        .setPublished(id: e.id, published: !e.published);
                    await _reload();
                  },
                  onDelete: (e) async {
                    await PublicChatKnowledgeService.instance
                        .delete(e.id, storagePath: e.storagePath);
                    await _reload();
                  },
                ),
                _UploadTab(
                  isInternal: _isInternal,
                  onUpload: _uploadDocs,
                  onPaste: () => _openEditor(kind: 'document'),
                ),
                _TestLabTab(isInternal: _isInternal),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.isInternal,
    required this.stats,
    required this.liveChunks,
    required this.onUpload,
    required this.onNewRule,
    required this.onNewQa,
    this.onOpenChat,
  });

  final bool isInternal;
  final PublicChatKnowledgeStats? stats;
  final int liveChunks;
  final VoidCallback onUpload;
  final VoidCallback onNewRule;
  final VoidCallback onNewQa;
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                DriftProTheme.primaryGreenDark,
                DriftProTheme.primaryGreen,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isInternal
                    ? 'Treningslab for Spør DriftPro'
                    : 'Verdenslab for CCC-chatten',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isInternal
                    ? 'Last opp PDF-er, skriv HMS-regler, lær Q&A og test svarene. '
                        'Publisert kunnskap mates inn i Spør DriftPro for alle MAVI-ansatte '
                        '(i tillegg til innebygd HMS-håndbok og opplæring).'
                    : 'Last opp PDF-er, skriv rutiner, lær Q&A-fasit og test svarene live. '
                        'Alt som er publisert mates direkte inn i /montering.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeroChip(label: '${stats?.published ?? 0} publisert'),
                  _HeroChip(label: '$liveChunks live i chat'),
                  _HeroChip(label: '${stats?.qa ?? 0} Q&A'),
                  _HeroChip(label: '${stats?.documents ?? 0} dokumenter'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Hurtighandlinger',
          style: DriftProTheme.headingSm.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Last opp PDF/TXT'),
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
              ),
            ),
            OutlinedButton.icon(
              onPressed: onNewRule,
              icon: const Icon(Icons.rule_folder_outlined),
              label: const Text('Ny rutineregel'),
            ),
            OutlinedButton.icon(
              onPressed: onNewQa,
              icon: const Icon(Icons.school_outlined),
              label: const Text('Lær Q&A'),
            ),
            if (onOpenChat != null)
              OutlinedButton.icon(
                onPressed: onOpenChat,
                icon: const Icon(Icons.forum_outlined),
                label: const Text('Åpne /montering'),
              ),
          ],
        ),
        const SizedBox(height: 22),
        _GuideCard(
          title: isInternal
              ? 'Slik blir Spør DriftPro smartere'
              : 'Slik blir chatten smartere hver dag',
          bullets: isInternal
              ? const [
                  'HMS-håndbok, ISO 14000 og opplæring er allerede innebygd.',
                  'Last opp ekstra prosedyrer som PDF/TXT når noe mangler.',
                  'Skriv «Regel / rutine» for harde MAVI-regler.',
                  'Bruk Q&A for typiske ansatt-spørsmål med fasitsvar.',
                  'Test i Test-lab før du publiserer.',
                ]
              : const [
                  'Last opp prosedyrer og FAQ som PDF/TXT — teksten indeksers automatisk.',
                  'Skriv «Regel / rutine» for harde regler (f.eks. «ombooking kun når scannet»).',
                  'Bruk Q&A-trening for typiske CCC-spørsmål med fasitsvar i deres språk.',
                  'Test i Test-lab før du publiserer — slå av upubliserte utkast.',
                  'Skriv svarstil som «tone» for å styre hvordan chatten formulerer seg.',
                ],
        ),
      ],
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.title, required this.bullets});
  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          for (final b in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle, size: 16, color: DriftProTheme.primaryGreen),
                  const SizedBox(width: 8),
                  Expanded(child: Text(b, style: const TextStyle(height: 1.4, fontSize: 14))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KnowledgeListTab extends StatelessWidget {
  const _KnowledgeListTab({
    required this.rows,
    required this.onEdit,
    required this.onToggleActive,
    required this.onTogglePublished,
    required this.onDelete,
    this.emptyHint,
  });

  final List<PublicChatKnowledgeEntry> rows;
  final void Function(PublicChatKnowledgeEntry) onEdit;
  final void Function(PublicChatKnowledgeEntry) onToggleActive;
  final void Function(PublicChatKnowledgeEntry) onTogglePublished;
  final void Function(PublicChatKnowledgeEntry) onDelete;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            emptyHint ?? 'Ingen kunnskap ennå. Legg til regler, Q&A eller dokumenter.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black.withValues(alpha: 0.55)),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final e = rows[i];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onEdit(e),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          e.kindLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: DriftProTheme.primaryGreen,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!e.active)
                        const _MiniBadge(label: 'Pauset', color: Colors.orange),
                      if (!e.published)
                        const _MiniBadge(label: 'Utkast', color: Colors.blueGrey),
                      const Spacer(),
                      Text(
                        'P${e.priority}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black.withValues(alpha: 0.4),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (e.preferredAnswer ?? e.content).trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      height: 1.35,
                      color: Colors.black.withValues(alpha: 0.55),
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => onTogglePublished(e),
                        child: Text(e.published ? 'Avpubliser' : 'Publiser'),
                      ),
                      TextButton(
                        onPressed: () => onToggleActive(e),
                        child: Text(e.active ? 'Pause' : 'Aktiver'),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => onDelete(e),
                        icon: const Icon(Icons.delete_outline, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

class _UploadTab extends StatelessWidget {
  const _UploadTab({
    required this.onUpload,
    required this.onPaste,
    this.isInternal = false,
  });
  final VoidCallback onUpload;
  final VoidCallback onPaste;
  final bool isInternal;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.25),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(Icons.cloud_upload_rounded,
                  size: 48, color: DriftProTheme.primaryGreen),
              const SizedBox(height: 12),
              const Text(
                'Last opp PDF eller tekst',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                isInternal
                    ? 'Teksten ekstraheres og indekseres for Spør DriftPro '
                        '(MAVI-ansatte). Originalfil lagres når storage-bucket er på plass.'
                    : 'Teksten ekstraheres og indekseres for CCC-chatten. '
                        'Originalfil lagres når storage-bucket er på plass.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.55),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.upload_file),
                label: const Text('Velg filer'),
                style: FilledButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onPaste,
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Lim inn tekst manuelt'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TestLabTab extends StatefulWidget {
  const _TestLabTab({this.isInternal = false});

  final bool isInternal;

  @override
  State<_TestLabTab> createState() => _TestLabTabState();
}

class _TestLabTabState extends State<_TestLabTab> {
  final _ctrl = TextEditingController();
  String? _answer;
  bool _busy = false;
  List<String> _hits = const [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _answer = null;
      _hits = const [];
    });
    if (widget.isInternal) {
      await KnowledgeAssistantService.instance.reload();
      final res = await KnowledgeAssistantService.instance.ask(q);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _answer = res.text;
        _hits = [
          for (final h in res.hits.take(4))
            '${h.chunk.sourceLabel}: ${h.chunk.title} (${h.score.toStringAsFixed(0)})',
        ];
      });
      return;
    }
    await PublicMontageAssistantService.instance.reloadKnowledge();
    final res = await PublicMontageAssistantService.instance.ask(q);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _answer = res.text;
      _hits = [
        for (final h in res.hits.take(4))
          '${h.chunk.sourceLabel}: ${h.chunk.title} (${h.score.toStringAsFixed(0)})',
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        TextField(
          controller: _ctrl,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: widget.isInternal
                ? 'Test et MAVI-spørsmål (HMS, opplæring, DriftPro)…'
                : 'Test et CCC-spørsmål…',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onSubmitted: (_) => _ask(),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _busy ? null : _ask,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.science_outlined),
          label: Text(_busy ? 'Tester…' : 'Kjør test'),
          style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
        ),
        if (_answer != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: SelectableText(_answer!, style: const TextStyle(height: 1.5, fontSize: 15)),
          ),
          if (_hits.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Kilder brukt',
              style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            for (final h in _hits)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $h', style: const TextStyle(fontSize: 13, height: 1.35)),
              ),
          ],
        ],
      ],
    );
  }
}

class _KnowledgeEditorSheet extends StatefulWidget {
  const _KnowledgeEditorSheet({
    required this.companyId,
    required this.channel,
    this.existing,
    required this.initialKind,
    this.isInternal = false,
  });

  final String companyId;
  final String channel;
  final PublicChatKnowledgeEntry? existing;
  final String initialKind;
  final bool isInternal;

  @override
  State<_KnowledgeEditorSheet> createState() => _KnowledgeEditorSheetState();
}

class _KnowledgeEditorSheetState extends State<_KnowledgeEditorSheet> {
  late String _kind;
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final TextEditingController _question;
  late final TextEditingController _answer;
  late final TextEditingController _tags;
  late double _priority;
  bool _published = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _kind = e?.kind ?? widget.initialKind;
    _title = TextEditingController(text: e?.title ?? '');
    _content = TextEditingController(text: e?.content ?? '');
    _question = TextEditingController(text: e?.question ?? '');
    _answer = TextEditingController(text: e?.preferredAnswer ?? '');
    _tags = TextEditingController(text: e?.tags.join(', ') ?? '');
    _priority = (e?.priority ?? 60).toDouble();
    _published = e?.published ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _question.dispose();
    _answer.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    try {
      final tags = _tags.text
          .split(RegExp(r'[,;]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      await PublicChatKnowledgeService.instance.upsert(
        id: widget.existing?.id,
        companyId: widget.companyId,
        kind: _kind,
        title: title,
        content: _content.text,
        question: _question.text.isEmpty ? null : _question.text,
        preferredAnswer: _answer.text.isEmpty ? null : _answer.text,
        tags: tags,
        priority: _priority.round(),
        published: _published,
        channel: widget.existing?.channel ?? widget.channel,
        sourceFilename: widget.existing?.sourceFilename,
        storagePath: widget.existing?.storagePath,
        mimeType: widget.existing?.mimeType,
        byteSize: widget.existing?.byteSize,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFFF7F8F6),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Text(
                    widget.existing == null ? 'Ny kunnskap' : 'Rediger kunnskap',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  const Spacer(),
                  TextButton(onPressed: _saving ? null : _save, child: const Text('Lagre')),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final k in const [
                        ('rule', 'Regel'),
                        ('qa', 'Q&A'),
                        ('document', 'Dokument'),
                        ('playbook', 'Playbook'),
                        ('tone', 'Svarstil'),
                        ('note', 'Notat'),
                      ])
                        ChoiceChip(
                          label: Text(k.$2),
                          selected: _kind == k.$1,
                          onSelected: (_) => setState(() => _kind = k.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Tittel',
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  if (_kind == 'qa') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _question,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: widget.isInternal
                            ? 'Typisk spørsmål fra MAVI-ansatt'
                            : 'Typisk spørsmål fra CCC/butikk',
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _answer,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Fasitsvar (slik chatten bør svare)',
                        filled: true,
                        fillColor: Colors.white,
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: _content,
                    maxLines: 10,
                    decoration: InputDecoration(
                      labelText: _kind == 'qa'
                          ? 'Ekstra kontekst (valgfritt)'
                          : 'Innhold / rutinetekst',
                      filled: true,
                      fillColor: Colors.white,
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tags,
                    decoration: const InputDecoration(
                      labelText: 'Tags (kommaseparert)',
                      hintText: 'ombooking, SA, montering',
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Prioritet: ${_priority.round()}'),
                  Slider(
                    value: _priority,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    activeColor: DriftProTheme.primaryGreen,
                    onChanged: (v) => setState(() => _priority = v),
                  ),
                  SwitchListTile(
                    value: _published,
                    onChanged: (v) => setState(() => _published = v),
                    title: const Text('Publisert til /montering'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
