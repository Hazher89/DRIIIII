import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/routing/app_router.dart';
import '../../core/services/assistant/assistant_flag_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import 'driftpro_assistant_sheet.dart';

/// Global chat-knapp — **kun web**, når assistenten er slått på.
///
/// Plassert øverst til høyre (over brand-bar) så den ikke dekker
/// bunnnavigasjon (avvik, fravær, osv.).
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

  bool get _showFab => kIsWeb && _flag.enabled;

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

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showFab)
          Positioned(
            top: 6,
            right: 10,
            child: SafeArea(
              bottom: false,
              left: false,
              right: false,
              child: _AssistantLaunchChip(
                title: _flag.displayTitle,
                onPressed: _openChat,
              ),
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
    return Material(
      elevation: 3,
      shadowColor: Colors.black26,
      color: DriftProTheme.primaryGreen,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.chat_bubble_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                title.length > 18 ? '${title.substring(0, 17)}…' : title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
