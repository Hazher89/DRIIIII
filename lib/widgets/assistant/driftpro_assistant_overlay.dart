import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/routing/app_paths.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/assistant/assistant_fab_position_store.dart';
import '../../core/services/assistant/assistant_flag_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import 'driftpro_assistant_sheet.dart';

/// Global Spør DriftPro-knapp når assistenten er slått på (web + mobil).
///
/// Kompakt ikon som kan dras fritt. Posisjon huskes per bruker.
/// Ingen Material/Tooltip (unngår grå hover-overlay på web).
class DriftProAssistantOverlay extends StatefulWidget {
  const DriftProAssistantOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<DriftProAssistantOverlay> createState() =>
      _DriftProAssistantOverlayState();
}

class _DriftProAssistantOverlayState extends State<DriftProAssistantOverlay>
    with WidgetsBindingObserver {
  static const _fabSize = 52.0;
  static const _edgePad = 8.0;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<AssistantFlag>? _flagSub;
  Timer? _poll;
  String? _companyId;
  String? _userId;
  AssistantFlag _flag = AssistantFlag.disabled;
  bool _sheetOpen = false;

  /// Top-left of FAB in logical pixels. Null = use default bottom-right.
  Offset? _fabOffset;
  bool _dragging = false;
  Offset? _panStartFab;
  Offset? _panStartGlobal;
  bool _movedEnough = false;

  bool get _showFab {
    if (!_flag.enabled) return false;
    final candidates = <String>[];
    try {
      candidates.add(GoRouter.of(context).state.uri.path);
    } catch (_) {}
    if (kIsWeb) {
      try {
        candidates.add(Uri.base.path);
      } catch (_) {}
    }
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
      final userId = profile?.id ??
          Supabase.instance.client.auth.currentUser?.id;
      if (!mounted) return;
      final userChanged = userId != _userId;
      if (companyId != _companyId) {
        _companyId = companyId;
        _bindFlag(companyId);
      } else {
        await _refreshFlag();
      }
      if (userChanged) {
        _userId = userId;
        unawaited(_loadFabPosition());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _companyId = null;
        _userId = null;
        _flag = AssistantFlag.disabled;
        _fabOffset = null;
      });
    }
  }

  Future<void> _loadFabPosition() async {
    final uid = _userId;
    if (uid == null || uid.isEmpty) {
      if (mounted) setState(() => _fabOffset = null);
      return;
    }
    final saved = await AssistantFabPositionStore.loadAsync(uid);
    if (!mounted) return;
    setState(() {
      _fabOffset = saved == null ? null : Offset(saved.left, saved.top);
    });
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

  Offset _defaultOffset(Size size) {
    final bottomNav = MediaQuery.paddingOf(context).bottom + 72;
    return Offset(
      size.width - _fabSize - 14,
      size.height - _fabSize - bottomNav,
    );
  }

  Offset _clamp(Offset raw, Size size) {
    final maxX = math.max(_edgePad, size.width - _fabSize - _edgePad);
    final maxY = math.max(_edgePad, size.height - _fabSize - _edgePad);
    return Offset(
      raw.dx.clamp(_edgePad, maxX),
      raw.dy.clamp(_edgePad, maxY),
    );
  }

  void _onPanStart(DragStartDetails details, Size size) {
    final current = _clamp(_fabOffset ?? _defaultOffset(size), size);
    _dragging = true;
    _movedEnough = false;
    _panStartFab = current;
    _panStartGlobal = details.globalPosition;
    setState(() => _fabOffset = current);
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final startFab = _panStartFab;
    final startGlobal = _panStartGlobal;
    if (startFab == null || startGlobal == null) return;
    final delta = details.globalPosition - startGlobal;
    if (delta.distance > 6) _movedEnough = true;
    setState(() {
      _fabOffset = _clamp(startFab + delta, size);
    });
  }

  void _onPanEnd(Size size) {
    final uid = _userId;
    final pos = _fabOffset;
    final moved = _movedEnough;
    _dragging = false;
    _panStartFab = null;
    _panStartGlobal = null;
    _movedEnough = false;
    if (pos != null && uid != null && uid.isNotEmpty && moved) {
      final clamped = _clamp(pos, size);
      AssistantFabPositionStore.save(
        uid,
        left: clamped.dx,
        top: clamped.dy,
      );
      setState(() => _fabOffset = clamped);
    } else if (mounted) {
      setState(() {});
    }
  }

  void _onPanCancel() {
    _dragging = false;
    _panStartFab = null;
    _panStartGlobal = null;
    _movedEnough = false;
    if (mounted) setState(() {});
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final pos = _clamp(_fabOffset ?? _defaultOffset(size), size);

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            widget.child,
            if (_showFab)
              Positioned(
                left: pos.dx,
                top: pos.dy,
                width: _fabSize,
                height: _fabSize,
                child: _DraggableFab(
                  title: _flag.displayTitle,
                  dragging: _dragging,
                  onTap: () => unawaited(_openChat()),
                  onPanStart: (d) => _onPanStart(d, size),
                  onPanUpdate: (d) => _onPanUpdate(d, size),
                  onPanEnd: () => _onPanEnd(size),
                  onPanCancel: _onPanCancel,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DraggableFab extends StatelessWidget {
  const _DraggableFab({
    required this.title,
    required this.dragging,
    required this.onTap,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
  });

  final String title;
  final bool dragging;
  final VoidCallback onTap;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onPanCancel;

  @override
  Widget build(BuildContext context) {
    // Ingen Material / InkWell / Tooltip — de gir grå hover-overlay på Flutter web.
    return MouseRegion(
      cursor: dragging
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: (_) => onPanEnd(),
        onPanCancel: onPanCancel,
        child: Semantics(
          button: true,
          label: title,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: DriftProTheme.primaryGreen,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dragging ? 0.28 : 0.18),
                  blurRadius: dragging ? 10 : 6,
                  offset: Offset(0, dragging ? 4 : 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(
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
