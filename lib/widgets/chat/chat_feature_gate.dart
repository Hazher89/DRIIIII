import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/chat/chat_flag_service.dart';
import '../../core/services/supabase_service.dart';
import '../../models/user_profile.dart';

/// Skjuler [child] når chat er av for gitt målgruppe. Oppdateres live via Realtime.
class ChatFeatureGate extends StatefulWidget {
  const ChatFeatureGate({
    super.key,
    required this.companyId,
    required this.audience,
    required this.child,
    this.disabledPlaceholder,
    this.onDisabled,
  });

  final String companyId;
  final ChatAudience audience;
  final Widget child;
  final Widget? disabledPlaceholder;
  final VoidCallback? onDisabled;

  @override
  State<ChatFeatureGate> createState() => _ChatFeatureGateState();
}

enum ChatAudience { mavi, partners }

class _ChatFeatureGateState extends State<ChatFeatureGate> {
  ChatFlag _flag = ChatFlag.allEnabled;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    ChatFlagService.watch(widget.companyId).listen((flag) {
      if (!mounted) return;
      final wasEnabled = _isEnabled(_flag);
      final nowEnabled = _isEnabled(flag);
      setState(() {
        _flag = flag;
        _ready = true;
      });
      if (wasEnabled && !nowEnabled) {
        widget.onDisabled?.call();
      }
    });
  }

  bool _isEnabled(ChatFlag flag) => switch (widget.audience) {
        ChatAudience.mavi => flag.maviEnabled,
        ChatAudience.partners => flag.partnersEnabled,
      };

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    if (!_isEnabled(_flag)) {
      return widget.disabledPlaceholder ?? const SizedBox.shrink();
    }
    return widget.child;
  }
}

/// Fullskjerm når chat er deaktivert eller bruker navigerer dit mens av.
class ChatDisabledScreen extends StatelessWidget {
  const ChatDisabledScreen({super.key, this.audience = ChatAudience.mavi});

  final ChatAudience audience;

  @override
  Widget build(BuildContext context) {
    final msg = audience == ChatAudience.partners
        ? 'Meldinger er midlertidig avslått for partnere. Kontakt MAVI kjørekontor ved spørsmål.'
        : 'Chat er midlertidig avslått for MAVI-ansatte. Superadmin kan slå det på igjen under Mer → Partner-chat.';

    return Scaffold(
      appBar: AppBar(title: const Text('Meldinger')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Chat er av',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(msg, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700, height: 1.4)),
              const SizedBox(height: 20),
              OutlinedButton(onPressed: () => Navigator.maybePop(context), child: const Text('Tilbake')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resolver companyId og audience fra profil.
Future<({String companyId, ChatAudience audience})?> resolveChatContext() async {
  final profile = await SupabaseService.fetchEffectiveUserProfile();
  if (profile == null) return null;

  String? companyId = profile.companyId;
  if (companyId == null && profile.partnerId != null) {
    // Partner-portal: hent company via partner om nødvendig
    companyId = profile.companyId;
  }

  companyId ??= await SupabaseService.getCurrentCompanyId();
  if (companyId == null) return null;

  final audience = profile.isPartnerPortalUser ? ChatAudience.partners : ChatAudience.mavi;
  return (companyId: companyId, audience: audience);
}

/// Lukker skjermen live når chat slås av (rom pushet oppå hub).
class ChatRoomLiveGate extends StatefulWidget {
  const ChatRoomLiveGate({
    super.key,
    required this.profile,
    required this.child,
  });

  final UserProfile profile;
  final Widget child;

  @override
  State<ChatRoomLiveGate> createState() => _ChatRoomLiveGateState();
}

class _ChatRoomLiveGateState extends State<ChatRoomLiveGate> {
  StreamSubscription<ChatFlag>? _sub;
  var _wasEnabled = true;

  @override
  void initState() {
    super.initState();
    final companyId = widget.profile.companyId;
    if (companyId == null || companyId.isEmpty) return;
    _sub = ChatFlagService.watch(companyId).listen((flag) {
      if (!mounted) return;
      final audience =
          widget.profile.isPartnerPortalUser ? ChatAudience.partners : ChatAudience.mavi;
      final enabled = audience == ChatAudience.partners
          ? flag.partnersEnabled
          : flag.maviEnabled;
      if (_wasEnabled && !enabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      }
      _wasEnabled = enabled;
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel() ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Hub-wrapper: viser chat eller disabled-skjerm, live oppdatert.
class ChatHubGate extends StatefulWidget {
  const ChatHubGate({super.key, required this.child});

  final Widget child;

  @override
  State<ChatHubGate> createState() => _ChatHubGateState();
}

class _ChatHubGateState extends State<ChatHubGate> {
  ({String companyId, ChatAudience audience})? _ctx;

  @override
  void initState() {
    super.initState();
    resolveChatContext().then((ctx) {
      if (mounted) setState(() => _ctx = ctx);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctx = _ctx;
    if (ctx == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<ChatFlag>(
      stream: ChatFlagService.watch(ctx.companyId),
      builder: (context, snap) {
        final flag = snap.data ?? ChatFlag.allEnabled;
        final enabled = ctx.audience == ChatAudience.partners
            ? flag.partnersEnabled
            : flag.maviEnabled;

        if (!enabled) {
          return ChatDisabledScreen(audience: ctx.audience);
        }
        return widget.child;
      },
    );
  }
}
