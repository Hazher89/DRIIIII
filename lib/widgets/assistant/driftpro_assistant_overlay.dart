import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/routing/app_paths.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/assistant/assistant_flag_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import 'driftpro_assistant_sheet.dart';

/// Global chat-knapp — **kun web**, når assistenten er slått på.
///
/// Plassert nederst til høyre over bunnnavigasjonen som et kompakt ikon,
/// så den ikke dekker AppBar, faner eller innhold.
class DriftProAssistantOverlay extends StatefulWidget {
  const DriftProAssistantOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<DriftProAssistantOverlay> createState() =>
      _DriftProAssistantOverlayState();
}

class _DriftProAssistantOverlayState extends State<DriftProAssistantOverlay>
    with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<AssistantFlag>? _flagSub;
  Timer? _poll;
  String? _companyId;
  AssistantFlag _flag = AssistantFlag.disabled;
  bool _sheetOpen = false;

  bool get _showFab {
    if (!kIsWeb || !_flag.enabled) return false;
    // Skjul intern «Spør DriftPro» på offentlig monteringchat (/chatt),
    // også når GoRouter er i errorBuilder eller utenfor router-treet.
    final candidates = <String>[];
    try {
      candidates.add(GoRouter.of(context).state.uri.path);
    } catch (_) {}
    try {
      candidates.add(Uri.base.path);
    } catch (_) {}
    for (final raw in candidates) {
      final path = raw.split('?').first;
      if (AppPaths.isPublicPath(path) ||
          path == AppPaths.chatt ||
          path == AppPaths.publicChatAlias ||
          path == AppPaths.publicChatAliasAlt ||
          path == '/chat') {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    WidgetsBinding.instance.addObserver(this);
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      unawaited(_reloadProfile());
    });
    unawaited(_reloadProfile());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshFlag());
    }
  }

  Future<void> _reloadProfile() async {
    try {
      final profile = await SupabaseService.fetchEffectiveUserProfile();
      final companyId = profile?.companyId;
      if (!mounted) return;
      if (companyId != _companyId) {
        _companyId = companyId;
        _bindFlag(companyId);
      } else {
        await _refreshFlag();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _companyId = null;
        _flag = AssistantFlag.disabled;
      });
    }
  }

  void _bindFlag(String? companyId) {
    _flagSub?.cancel();
    _poll?.cancel();
    _flagSub = null;
    _poll = null;

    if (companyId == null || companyId.isEmpty) {
      setState(() => _flag = AssistantFlag.disabled);
      return;
    }

    _flagSub = AssistantFlagService.watch(companyId).listen((flag) {
      if (!mounted) return;
      setState(() => _flag = flag);
    });
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshFlag());
    });
  }

  Future<void> _refreshFlag() async {
    final id = _companyId;
    if (id == null || id.isEmpty) return;
    final flag = await AssistantFlagService.fetchForCompany(id);
    if (!mounted) return;
    if (flag.enabled != _flag.enabled || flag.title != _flag.title) {
      setState(() => _flag = flag);
    }
  }

  Future<void> _openChat() async {
    if (_sheetOpen) return;
    final navContext = driftProRootNavigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;
    _sheetOpen = true;
    try {
      await showDriftProAssistantSheet(
        navContext,
        title: _flag.displayTitle,
      );
    } finally {
      _sheetOpen = false;
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _authSub?.cancel();
    _flagSub?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;

    final mq = MediaQuery.of(context);
    // Over bottom nav (~56–64) + home indicator, uten å dekke innholdet midt på.
    final bottom = mq.padding.bottom + 72;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showFab)
          Positioned(
            right: 14,
            bottom: bottom,
            child: _AssistantLaunchChip(
              title: _flag.displayTitle,
              onPressed: _openChat,
            ),
          ),
      ],
    );
  }
}

class _AssistantLaunchChip extends StatelessWidget {
  const _AssistantLaunchChip({
    required this.title,
    required this.onPressed,
  });

  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: title,
      child: Material(
        elevation: 4,
        shadowColor: Colors.black38,
        color: DriftProTheme.primaryGreen,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          mouseCursor: SystemMouseCursors.click,
          child: const SizedBox(
            width: 52,
            height: 52,
            child: Icon(
              Icons.chat_bubble_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
