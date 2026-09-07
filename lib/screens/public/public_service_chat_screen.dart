import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/assistant/public_montage_assistant_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/driftpro_loading_indicator.dart';

class _ChatMessage {
  const _ChatMessage({required this.text, required this.isUser});
  final String text;
  final bool isUser;
}

/// Offentlig monteringchat — ingen innlogging (driftpro.no/chatt).
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
  final _messages = <_ChatMessage>[
    const _ChatMessage(
      isUser: false,
      text:
          'Hei! Jeg hjelper deg med monteringstjenestene MAVI utfører hos deg '
          '(Elkjöp). Spør gjerne om hva som er inkludert, hva du må gjøre, '
          'eller hva som ikke er inkludert.',
    ),
  ];
  bool _busy = false;
  bool _ready = false;

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
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 880;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F6F4),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _Atmosphere(),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: wide ? 920 : double.infinity,
                  ),
                  child: Column(
                    children: [
                      _Header(wide: wide),
                      Expanded(
                        child: ListView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(
                            wide ? 28 : 16,
                            8,
                            wide ? 28 : 16,
                            16,
                          ),
                          itemCount: _messages.length + (_busy ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (_busy && i == _messages.length) {
                              return const _TypingBubble();
                            }
                            final m = _messages[i];
                            return _Bubble(message: m);
                          },
                        ),
                      ),
                      if (_ready)
                        _SuggestionRow(
                          onTap: (q) => _send(q),
                          disabled: _busy,
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          wide ? 28 : 16,
                          8,
                          wide ? 28 : 16,
                          12 + bottomInset,
                        ),
                        child: _Composer(
                          controller: _controller,
                          focusNode: _focus,
                          busy: _busy || !_ready,
                          onSend: () => _send(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Basert på tjenesteoversikt · Ikke pris eller booking',
                          style: DriftProTheme.caption.copyWith(
                            color: Colors.black54,
                          ),
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
    );
  }
}

class _Atmosphere extends StatelessWidget {
  const _Atmosphere();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE8F5EE),
            Color(0xFFF3F6F4),
            Color(0xFFE3EEF7),
          ],
        ),
      ),
      child: CustomPaint(painter: _GridPainter()),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.03)
      ..strokeWidth = 1;
    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Header extends StatelessWidget {
  const _Header({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 12, wide ? 28 : 16, 4),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: DriftProTheme.primaryGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Text(
              'D',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DriftPro',
                  style: DriftProTheme.headingMd.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Spør om monteringstjenester hos deg',
                  style: DriftProTheme.bodySm.copyWith(color: Colors.black54),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse('https://driftpro.no'),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('driftpro.no'),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        decoration: BoxDecoration(
          color: isUser ? DriftProTheme.primaryGreen : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: SelectableText(
          message.text,
          style: TextStyle(
            color: isUser ? Colors.white : Colors.black87,
            height: 1.4,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const SizedBox(
          width: 28,
          height: 28,
          child: DriftProLoadingIndicator(size: 22),
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.onTap, required this.disabled});
  final void Function(String) onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final q in PublicMontageAssistantService.suggestedQueries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
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
    return Material(
      elevation: 2,
      shadowColor: Colors.black12,
      borderRadius: BorderRadius.circular(18),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !busy,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Spør om vaskemaskin, TV, komfyr…',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            IconButton.filled(
              onPressed: busy ? null : onSend,
              style: IconButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
