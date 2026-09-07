import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/assistant/public_montage_assistant_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/driftpro_loading_indicator.dart';

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.copied = false,
    this.followUps = const [],
  });
  final String text;
  final bool isUser;
  final bool copied;
  final List<String> followUps;

  _ChatMessage copyWith({bool? copied}) => _ChatMessage(
        text: text,
        isUser: isUser,
        copied: copied ?? this.copied,
        followUps: followUps,
      );
}

/// Offentlig AI-chat for CCC & butikk — avansert DriftPro-design.
class PublicServiceChatScreen extends StatefulWidget {
  const PublicServiceChatScreen({super.key});

  @override
  State<PublicServiceChatScreen> createState() =>
      _PublicServiceChatScreenState();
}

class _PublicServiceChatScreenState extends State<PublicServiceChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _messages = <_ChatMessage>[];
  bool _busy = false;
  bool _ready = false;
  int _liveChunks = 0;
  String _topic = 'alle';

  bool get _isEmpty => _messages.isEmpty;

  static const _topics = <({String id, String label, IconData icon})>[
    (id: 'alle', label: 'Alt', icon: Icons.auto_awesome),
    (id: 'booking', label: 'Booking', icon: Icons.event_available_outlined),
    (id: 'montering', label: 'Montering', icon: Icons.handyman_outlined),
    (id: 'endring', label: 'Endringer', icon: Icons.edit_note_rounded),
    (id: 'status', label: 'Status', icon: Icons.local_shipping_outlined),
  ];

  static const _topicSuggestions = <String, List<String>>{
    'alle': PublicMontageAssistantService.suggestedQueries,
    'booking': [
      'Kan kunden få levering tidligere enn booket dato?',
      'Kunden vil ha levering etter kl. 19 i vinduet — hva gjør vi?',
      'Hvordan kansellerer vi leveringen riktig?',
      'Curbside til deliverysite — hvordan?',
    ],
    'montering': [
      'Hva er inkludert ved montering av vaskemaskin?',
      'Er side-by-side enkel eller avansert montering?',
      'Kunden glemte en tjeneste — hvordan fikser vi det?',
      'Det trengs fire personer — hva setter vi opp?',
    ],
    'endring': [
      'Hvordan endrer vi adresse eller telefon på ordren?',
      'Kunden vil endre etasje / portkode — hva skriver vi?',
      'Curbside til deliverysite — hvordan?',
      'Kunden glemte en tjeneste — hvordan fikser vi det?',
    ],
    'status': [
      'Når kommer varene inn på HUB?',
      'Vare ikke hentet fra butikk — kan den leveres likevel?',
      'Blir denne levert i dag hvis den er forsinket?',
      'Hvordan kansellerer vi leveringen riktig?',
    ],
  };

  @override
  void initState() {
    super.initState();
    PublicMontageAssistantService.instance.ensureReady().then((_) {
      if (mounted) {
        setState(() {
          _ready = true;
          _liveChunks =
              PublicMontageAssistantService.instance.liveChunkCount;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final q = (preset ?? _controller.text).trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _messages.add(_ChatMessage(text: q, isUser: true));
      _busy = true;
      if (preset == null) _controller.clear();
    });
    _scrollToEnd();

    final answer = await PublicMontageAssistantService.instance.ask(q);
    if (!mounted) return;
    setState(() {
      _messages.add(
        _ChatMessage(
          text: answer.text,
          isUser: false,
          followUps: answer.followUps,
        ),
      );
      _busy = false;
      _liveChunks = PublicMontageAssistantService.instance.liveChunkCount;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 160,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _newChat() {
    setState(() {
      _messages.clear();
      _busy = false;
    });
    _focus.requestFocus();
  }

  Future<void> _copy(int index) async {
    final m = _messages[index];
    await Clipboard.setData(ClipboardData(text: m.text));
    setState(() {
      _messages[index] = m.copyWith(copied: true);
    });
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    if (index < _messages.length) {
      setState(() => _messages[index] = _messages[index].copyWith(copied: false));
    }
  }

  List<String> get _suggestions =>
      _topicSuggestions[_topic] ?? PublicMontageAssistantService.suggestedQueries;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7F4),
        body: Row(
          children: [
            if (wide)
              _SideRail(
                onNewChat: _newChat,
                topic: _topic,
                liveChunks: _liveChunks,
                ready: _ready,
                onTopic: (id) => setState(() => _topic = id),
                topics: _topics,
              ),
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFBFCF9), Color(0xFFF3F5F0)],
                  ),
                ),
                child: Column(
                  children: [
                    _TopBar(
                      wide: wide,
                      onNewChat: _newChat,
                      ready: _ready,
                      liveChunks: _liveChunks,
                    ),
                    if (!wide)
                      _TopicStrip(
                        topic: _topic,
                        topics: _topics,
                        onTopic: (id) => setState(() => _topic = id),
                      ),
                    Expanded(
                      child: _isEmpty
                          ? _EmptyHero(
                              ready: _ready,
                              suggestions: _suggestions,
                              onSuggestion: _send,
                            )
                          : ListView.builder(
                              controller: _scroll,
                              padding: EdgeInsets.symmetric(
                                horizontal: wide ? 40 : 14,
                                vertical: 10,
                              ),
                              itemCount: _messages.length + (_busy ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (_busy && i == _messages.length) {
                                  return const _TypingRow();
                                }
                                return _MessageRow(
                                  message: _messages[i],
                                  maxWidth: wide ? 760 : double.infinity,
                                  onCopy: _messages[i].isUser
                                      ? null
                                      : () => _copy(i),
                                  onFollowUp: _busy ? null : _send,
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        wide ? 40 : 14,
                        0,
                        wide ? 40 : 14,
                        10 + bottomInset,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Column(
                            children: [
                              if (!_isEmpty && _ready)
                                _SuggestionStrip(
                                  suggestions: _suggestions.take(4).toList(),
                                  onTap: _send,
                                  disabled: _busy,
                                ),
                              _Composer(
                                controller: _controller,
                                focusNode: _focus,
                                busy: _busy || !_ready,
                                onSend: () => _send(),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _ready
                                    ? 'Live kunnskapsbase · $_liveChunks trenede bits · konkrete handlinger for CCC & butikk'
                                    : 'Laster kunnskapsbase…',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.black.withValues(alpha: 0.42),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.onNewChat,
    required this.topic,
    required this.onTopic,
    required this.topics,
    required this.liveChunks,
    required this.ready,
  });

  final VoidCallback onNewChat;
  final String topic;
  final void Function(String) onTopic;
  final List<({String id, String label, IconData icon})> topics;
  final int liveChunks;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 288,
      decoration: const BoxDecoration(
        color: Color(0xFF151A16),
        border: Border(right: BorderSide(color: Color(0xFF243028))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        DriftProTheme.primaryGreen,
                        DriftProTheme.primaryGreen.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DriftPro',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'CCC & butikk',
                        style: TextStyle(color: Color(0xFF9BB0A2), fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onNewChat,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Ny samtale'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'TEMA',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            for (final t in topics)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: topic == t.id
                      ? DriftProTheme.primaryGreen.withValues(alpha: 0.22)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onTopic(t.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            t.icon,
                            size: 18,
                            color: topic == t.id
                                ? const Color(0xFFB8E0C0)
                                : const Color(0xFF8FA396),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            t.label,
                            style: TextStyle(
                              color: topic == t.id ? Colors.white : const Color(0xFFB7C7BC),
                              fontWeight:
                                  topic == t.id ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: ready
                              ? const Color(0xFF5DDC7B)
                              : Colors.orangeAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        ready ? 'Kunnskap live' : 'Laster…',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$liveChunks trenede bits fra Chat Lab',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11.5,
                      height: 1.3,
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
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.wide,
    required this.onNewChat,
    required this.ready,
    required this.liveChunks,
  });
  final bool wide;
  final VoidCallback onNewChat;
  final bool ready;
  final int liveChunks;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 4),
        child: Row(
          children: [
            if (!wide)
              IconButton(
                tooltip: 'Ny chat',
                onPressed: onNewChat,
                icon: const Icon(Icons.edit_outlined),
              ),
            Text(
              'Operativ hjelp',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black.withValues(alpha: 0.78),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: ready
                    ? DriftProTheme.primaryGreen.withValues(alpha: 0.12)
                    : Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                ready ? 'Live · $liveChunks' : 'Laster',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: ready
                      ? DriftProTheme.primaryGreenDark
                      : Colors.orange.shade800,
                ),
              ),
            ),
            const Spacer(),
            Text(
              'MAVI × Elkjøp',
              style: TextStyle(
                fontSize: 12,
                color: Colors.black.withValues(alpha: 0.38),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicStrip extends StatelessWidget {
  const _TopicStrip({
    required this.topic,
    required this.topics,
    required this.onTopic,
  });
  final String topic;
  final List<({String id, String label, IconData icon})> topics;
  final void Function(String) onTopic;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final t in topics)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(t.icon, size: 16),
                label: Text(t.label),
                selected: topic == t.id,
                onSelected: (_) => onTopic(t.id),
                selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.18),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyHero extends StatelessWidget {
  const _EmptyHero({
    required this.ready,
    required this.suggestions,
    required this.onSuggestion,
  });
  final bool ready;
  final List<String> suggestions;
  final void Function(String) onSuggestion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        DriftProTheme.primaryGreenDark,
                        DriftProTheme.primaryGreen,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: DriftProTheme.primaryGreen.withValues(alpha: 0.28),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.hub_outlined, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 22),
                Text(
                  'Hva skal fikses nå?',
                  textAlign: TextAlign.center,
                  style: DriftProTheme.headingMd.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    fontSize: 28,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Smarte, konkrete steg for ombooking, tjenester, montering og status — '
                  'skrevet for CCC og butikk.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: Colors.black.withValues(alpha: 0.52),
                  ),
                ),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final q in suggestions.take(8))
                      _SuggestionCard(
                        text: q,
                        enabled: ready,
                        onTap: () => onSuggestion(q),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.text,
    required this.enabled,
    required this.onTap,
  });
  final String text;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 230,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13.2,
              height: 1.35,
              color: Colors.black.withValues(alpha: 0.78),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionStrip extends StatelessWidget {
  const _SuggestionStrip({
    required this.suggestions,
    required this.onTap,
    required this.disabled,
  });
  final List<String> suggestions;
  final void Function(String) onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final q in suggestions)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: ActionChip(
                label: Text(q, style: const TextStyle(fontSize: 12)),
                onPressed: disabled ? null : () => onTap(q),
                backgroundColor: Colors.white,
                side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.maxWidth,
    this.onCopy,
    this.onFollowUp,
  });
  final _ChatMessage message;
  final double maxWidth;
  final VoidCallback? onCopy;
  final void Function(String)? onFollowUp;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: isUser ? const Color(0xFF1C2420) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: isUser
                      ? null
                      : Border.all(color: Colors.black.withValues(alpha: 0.05)),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isUser ? 0.08 : 0.03),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: isUser
                              ? Colors.white.withValues(alpha: 0.15)
                              : DriftProTheme.primaryGreen,
                          child: Icon(
                            isUser ? Icons.person_outline : Icons.bolt_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isUser ? 'Deg' : 'DriftPro',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            color: isUser
                                ? Colors.white.withValues(alpha: 0.9)
                                : const Color(0xFF1A1A1A),
                          ),
                        ),
                        const Spacer(),
                        if (onCopy != null)
                          TextButton.icon(
                            onPressed: onCopy,
                            icon: Icon(
                              message.copied
                                  ? Icons.check
                                  : Icons.copy_rounded,
                              size: 14,
                              color: Colors.black45,
                            ),
                            label: Text(
                              message.copied ? 'Kopiert' : 'Kopier',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black45,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      message.text,
                      style: TextStyle(
                        fontSize: 15.2,
                        height: 1.55,
                        color: isUser ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isUser &&
                  message.followUps.isNotEmpty &&
                  onFollowUp != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in message.followUps)
                      ActionChip(
                        label: Text(f, style: const TextStyle(fontSize: 12.5)),
                        onPressed: () => onFollowUp!(f),
                        backgroundColor: Colors.white,
                        side: BorderSide(
                          color: DriftProTheme.primaryGreen
                              .withValues(alpha: 0.35),
                        ),
                        avatar: const Icon(
                          Icons.arrow_outward_rounded,
                          size: 14,
                          color: DriftProTheme.primaryGreen,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingRow extends StatelessWidget {
  const _TypingRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DriftProLoadingIndicator(size: 18),
              SizedBox(width: 10),
              Text('Skriver svar…', style: TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: DriftProTheme.primaryGreen.withValues(alpha: 0.28),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: !busy,
              minLines: 1,
              maxLines: 6,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Spør som CCC/butikk — ombooking, SA, montering…',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 2, right: 2),
            child: IconButton.filled(
              onPressed: busy ? null : onSend,
              style: IconButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.black26,
              ),
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
