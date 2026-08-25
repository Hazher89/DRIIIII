import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/assistant/assistant_flag_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import 'driftpro_assistant_sheet.dart';

/// Global chat-FAB over hele appen (alle sider) når assistenten er slått på.
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

  @override
  void initState() {
    super.initState();
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
    if (_sheetOpen || !mounted) return;
    _sheetOpen = true;
    try {
      await showDriftProAssistantSheet(
        context,
        title: _flag.displayTitle,
      );
    } finally {
      _sheetOpen = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _flagSub?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_flag.enabled)
          Positioned(
            right: 16,
            bottom: 80,
            child: SafeArea(
              child: Material(
                elevation: 6,
                shape: const CircleBorder(),
                color: DriftProTheme.primaryGreen,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _openChat,
                  child: Tooltip(
                    message: _flag.displayTitle,
                    child: const SizedBox(
                      width: 56,
                      height: 56,
                      child: Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
