import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/assistant/assistant_corpus.dart';
import '../../core/services/assistant/knowledge_assistant_engine.dart';
import '../../core/services/assistant/knowledge_assistant_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/driftpro_theme_context.dart';

class _ChatMessage {
  _ChatMessage({required this.text, required this.isUser, this.answer});

  final String text;
  final bool isUser;
  final KnowledgeAnswer? answer;
}

Future<void> showDriftProAssistantSheet(
  BuildContext context, {
  String title = 'Spør DriftPro',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DriftProAssistantSheet(title: title),
  );
}

class DriftProAssistantSheet extends StatefulWidget {
  const DriftProAssistantSheet({super.key, this.title = 'Spør DriftPro'});

  final String title;

  @override
  State<DriftProAssistantSheet> createState() => _DriftProAssistantSheetState();
}

class _DriftProAssistantSheetState extends State<DriftProAssistantSheet> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatMessage>[
    _ChatMessage(
      text:
          'Hei! Jeg bruker MAVI/DriftPro-dokumentasjon (SOP, bilutleie, hjelp) '
          'og Gemini når det er satt opp. Spør fritt — svarene skal følge '
          'dere sine regler, ikke generelle internett-svar.',
      isUser: false,
    ),
  ];
  bool _busy = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    KnowledgeAssistantService.instance.ensureReady().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final q = (preset ?? _ctrl.text).trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _messages.add(_ChatMessage(text: q, isUser: true));
      if (preset == null) _ctrl.clear();
    });
    _scrollToEnd();

    final answer = await KnowledgeAssistantService.instance.ask(q);
    if (!mounted) return;
    setState(() {
      _messages.add(
        _ChatMessage(text: answer.text, isUser: false, answer: answer),
      );
      _busy = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height * 0.88;

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.smart_toy_outlined, color: DriftProTheme.primaryGreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: DriftProTheme.headingSm,
                        ),
                        Text(
                          'Basert på opplæring og hjelpetekster',
                          style: DriftProTheme.bodySm.copyWith(
                            color: drift.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (!_ready)
              const LinearProgressIndicator(minHeight: 2)
            else
              const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: _messages.length + (_busy ? 1 : 0),
                itemBuilder: (context, i) {
                  if (_busy && i == _messages.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Søker i kunnskapsbasen…'),
                      ),
                    );
                  }
                  final m = _messages[i];
                  return _Bubble(
                    message: m,
                    onOpenSource: (path) {
                      Navigator.pop(context);
                      context.push(path);
                    },
                  );
                },
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final q in KnowledgeAssistantService.suggestedQueries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(q, style: const TextStyle(fontSize: 12)),
                        onPressed: _busy ? null : () => _send(q),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Still et spørsmål…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : () => _send(),
                    style: FilledButton.styleFrom(
                      backgroundColor: DriftProTheme.primaryGreen,
                      minimumSize: const Size(48, 48),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Icon(Icons.send_rounded),
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

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onOpenSource});

  final _ChatMessage message;
  final void Function(String path) onOpenSource;

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final isUser = message.isUser;
    final bg = isUser
        ? DriftProTheme.primaryGreen.withValues(alpha: 0.12)
        : drift.surface;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.88,
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: drift.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              message.text,
              style: DriftProTheme.bodyMd.copyWith(height: 1.35),
            ),
            if (message.answer != null && message.answer!.hits.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final hit in message.answer!.hits)
                    if (hit.chunk.routePath != null)
                      ActionChip(
                        avatar: Icon(
                          _iconFor(hit.chunk.source),
                          size: 16,
                        ),
                        label: Text(
                          hit.chunk.title.length > 28
                              ? '${hit.chunk.title.substring(0, 28)}…'
                              : hit.chunk.title,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () => onOpenSource(hit.chunk.routePath!),
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _iconFor(KnowledgeSourceKind kind) {
    switch (kind) {
      case KnowledgeSourceKind.sop:
        return Icons.school_outlined;
      case KnowledgeSourceKind.rental:
        return Icons.directions_car_outlined;
      case KnowledgeSourceKind.help:
        return Icons.help_outline;
    }
  }
}
