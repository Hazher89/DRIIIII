import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/assistant/public_montage_assistant_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/driftpro_loading_indicator.dart';

class _ChatMessage {
  const _ChatMessage({required this.text, required this.isUser});
  final String text;
  final bool isUser;
}

/// Offentlig AI-chat for monteringstjenester (ChatGPT/Gemini-stil).
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

  bool get _isEmpty => _messages.isEmpty;

  @override
  void initState() {
    super.initState();
    PublicMontageAssistantService.instance.ensureReady().then((_) {
      if (mounted) setState(() => _ready = true);
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
      _messages.add(_ChatMessage(text: answer.text, isUser: false));
      _busy = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
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

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFFAFAF9),
        body: Row(
          children: [
            if (wide) _SideRail(onNewChat: _newChat),
            Expanded(
              child: Column(
                children: [
                  _TopBar(wide: wide, onNewChat: _newChat),
                  Expanded(
                    child: _isEmpty
                        ? _EmptyHero(
                            ready: _ready,
                            onSuggestion: _send,
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: EdgeInsets.symmetric(
                              horizontal: wide ? 48 : 16,
                              vertical: 12,
                            ),
                            itemCount: _messages.length + (_busy ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (_busy && i == _messages.length) {
                                return const _TypingRow();
                              }
                              return _MessageRow(
                                message: _messages[i],
                                maxWidth: wide ? 720 : double.infinity,
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 48 : 16,
                      0,
                      wide ? 48 : 16,
                      10 + bottomInset,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Column(
                          children: [
                            if (!_isEmpty && _ready)
                              _SuggestionStrip(
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
                              'Svarer ut fra MAVI/Elkjöp monteringsoversikt · ikke pris eller booking',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black.withValues(alpha: 0.45),
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
          ],
        ),
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({required this.onNewChat});
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: const Color(0xFFF0F0EE),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'DriftPro',
              style: DriftProTheme.headingSm.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Monteringshjelper',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: onNewChat,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Ny chat'),
              style: FilledButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
              ),
            ),
            const Spacer(),
            Text(
              'Spør fritt om hva som er inkludert hos deg.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.wide, required this.onNewChat});
  final bool wide;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(
          children: [
            if (!wide) ...[
              IconButton(
                tooltip: 'Ny chat',
                onPressed: onNewChat,
                icon: const Icon(Icons.edit_outlined),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              'Montering',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black.withValues(alpha: 0.7),
              ),
            ),
            const Spacer(),
            Text(
              'MAVI × Elkjöp',
              style: TextStyle(
                fontSize: 12,
                color: Colors.black.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHero extends StatelessWidget {
  const _EmptyHero({required this.ready, required this.onSuggestion});
  final bool ready;
  final void Function(String) onSuggestion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      DriftProTheme.primaryGreen,
                      DriftProTheme.primaryGreen.withValues(alpha: 0.75),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 20),
              Text(
                'Hva lurer du på om monteringen?',
                textAlign: TextAlign.center,
                style: DriftProTheme.headingMd.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  fontSize: 26,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Spør som du vil — inkludert, ikke inkludert, eller hva du må gjøre før levering.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (final q in PublicMontageAssistantService.suggestedQueries)
                    _SuggestionCard(
                      text: q,
                      enabled: ready,
                      onTap: () => onSuggestion(q),
                    ),
                ],
              ),
            ],
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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 210,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Colors.black.withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionStrip extends StatelessWidget {
  const _SuggestionStrip({required this.onTap, required this.disabled});
  final void Function(String) onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final q in PublicMontageAssistantService.suggestedQueries.take(4))
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
  const _MessageRow({required this.message, required this.maxWidth});
  final _ChatMessage message;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: isUser
                    ? const Color(0xFF2F2F2F)
                    : DriftProTheme.primaryGreen,
                child: Icon(
                  isUser ? Icons.person_outline : Icons.auto_awesome,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUser ? 'Deg' : 'DriftPro',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      message.text,
                      style: const TextStyle(
                        fontSize: 15.5,
                        height: 1.55,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
              ),
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
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          SizedBox(width: 8),
          DriftProLoadingIndicator(size: 22),
          SizedBox(width: 12),
          Text('Tenker…', style: TextStyle(color: Colors.black54)),
        ],
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
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
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
                hintText: 'Spør om hva som helst om monteringen…',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 18,
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
                backgroundColor: const Color(0xFF1A1A1A),
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
