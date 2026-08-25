import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/assistant/assistant_flag_service.dart';
import '../../core/theme/app_theme.dart';
import 'driftpro_assistant_sheet.dart';

/// Viser flytende chat-ikon når selskapet har slått på assistenten remote.
class DriftProAssistantHost extends StatefulWidget {
  const DriftProAssistantHost({
    super.key,
    required this.companyId,
    required this.child,
  });

  final String? companyId;
  final Widget child;

  @override
  State<DriftProAssistantHost> createState() => _DriftProAssistantHostState();
}

class _DriftProAssistantHostState extends State<DriftProAssistantHost>
    with WidgetsBindingObserver {
  StreamSubscription<AssistantFlag>? _sub;
  AssistantFlag _flag = AssistantFlag.disabled;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bind(widget.companyId);
  }

  @override
  void didUpdateWidget(covariant DriftProAssistantHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      _bind(widget.companyId);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshOnce();
    }
  }

  void _bind(String? companyId) {
    _sub?.cancel();
    _poll?.cancel();
    _sub = null;
    _poll = null;

    if (companyId == null || companyId.isEmpty) {
      setState(() => _flag = AssistantFlag.disabled);
      return;
    }

    _sub = AssistantFlagService.watch(companyId).listen((flag) {
      if (!mounted) return;
      setState(() => _flag = flag);
    });

    // Fallback hvis Realtime ikke er aktivert for companies.
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _refreshOnce());
  }

  Future<void> _refreshOnce() async {
    final id = widget.companyId;
    if (id == null || id.isEmpty) return;
    final flag = await AssistantFlagService.fetchForCompany(id);
    if (!mounted) return;
    if (flag.enabled != _flag.enabled || flag.title != _flag.title) {
      setState(() => _flag = flag);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_flag.enabled)
          Positioned(
            right: 16,
            bottom: 72,
            child: SafeArea(
              child: FloatingActionButton(
                heroTag: 'driftpro-assistant-fab',
                backgroundColor: DriftProTheme.primaryGreen,
                foregroundColor: Colors.white,
                tooltip: _flag.displayTitle,
                onPressed: () => showDriftProAssistantSheet(
                  context,
                  title: _flag.displayTitle,
                ),
                child: const Icon(Icons.chat_bubble_outline_rounded),
              ),
            ),
          ),
      ],
    );
  }
}
