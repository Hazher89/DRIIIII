import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/driftpro_theme_context.dart';
import '../../../models/partner/route_notify_prefs.dart';

/// Kompakt varselvalg: dropdown med én/flere/alle kanaler + én handlingsknapp.
class RoutePublishNotifyButtons extends StatefulWidget {
  const RoutePublishNotifyButtons({
    super.key,
    required this.busy,
    required this.onPublish,
    this.showWithoutNotify = true,
    this.compact = false,
    this.initialPrefs = RouteNotifyPrefs.all,
  });

  final bool busy;
  final Future<void> Function(RouteNotifyPrefs? prefs) onPublish;
  final bool showWithoutNotify;
  final bool compact;
  final RouteNotifyPrefs initialPrefs;

  @override
  State<RoutePublishNotifyButtons> createState() =>
      _RoutePublishNotifyButtonsState();
}

class _RoutePublishNotifyButtonsState extends State<RoutePublishNotifyButtons> {
  late RouteNotifyPrefs _prefs;

  @override
  void initState() {
    super.initState();
    _prefs = widget.initialPrefs;
  }

  @override
  void didUpdateWidget(covariant RoutePublishNotifyButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPrefs != widget.initialPrefs &&
        oldWidget.busy &&
        !widget.busy) {
      // keep local selection across parent rebuilds
    }
  }

  void _setPrefs(RouteNotifyPrefs next) {
    setState(() => _prefs = next);
  }

  Future<void> _openChannelMenu() async {
    final result = await showModalBottomSheet<RouteNotifyPrefs>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NotifyChannelSheet(initial: _prefs),
    );
    if (result != null && mounted) _setPrefs(result);
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final hasNotify = _prefs.anyEnabled;
    final pad = widget.compact ? 10.0 : 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Varsel til sjåfør',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: widget.compact ? 13 : 14,
            color: drift.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: drift.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: widget.busy ? null : _openChannelMenu,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: pad, vertical: pad),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: drift.borderSubtle),
              ),
              child: Row(
                children: [
                  Icon(
                    hasNotify
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    color: hasNotify
                        ? DriftProTheme.primaryGreen
                        : Colors.blueGrey,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasNotify ? _prefs.shortLabel : 'Uten varsel',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasNotify
                              ? 'Trykk for å velge App / SMS / E-post'
                              : 'Ingen melding sendes ved publisering',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: drift.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, color: drift.textMuted),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: widget.compact ? 10 : 12),
        FilledButton.icon(
          onPressed: widget.busy
              ? null
              : () => widget.onPublish(hasNotify ? _prefs : null),
          style: FilledButton.styleFrom(
            backgroundColor: hasNotify
                ? DriftProTheme.primaryGreen
                : Colors.blueGrey.shade700,
            minimumSize: Size(double.infinity, widget.compact ? 46 : 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: Icon(hasNotify ? Icons.send_rounded : Icons.save_outlined),
          label: Text(
            hasNotify ? 'Del ut med ${_prefs.shortLabel}' : 'Lagre uten varsel',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
        if (widget.showWithoutNotify && hasNotify) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: widget.busy ? null : () => widget.onPublish(null),
            child: Text(
              'Eller lagre uten varsel',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: drift.textMuted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NotifyChannelSheet extends StatefulWidget {
  const _NotifyChannelSheet({required this.initial});

  final RouteNotifyPrefs initial;

  @override
  State<_NotifyChannelSheet> createState() => _NotifyChannelSheetState();
}

class _NotifyChannelSheetState extends State<_NotifyChannelSheet> {
  late bool _app;
  late bool _sms;
  late bool _email;

  @override
  void initState() {
    super.initState();
    _app = widget.initial.app;
    _sms = widget.initial.sms;
    _email = widget.initial.email;
  }

  bool get _all => _app && _sms && _email;
  bool get _none => !_app && !_sms && !_email;

  RouteNotifyPrefs get _prefs => RouteNotifyPrefs(
        app: _app,
        sms: _sms,
        email: _email,
      );

  void _toggleAll(bool selected) {
    setState(() {
      _app = selected;
      _sms = selected;
      _email = selected;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF7F8F6),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Velg varselkanaler',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  'Velg én, flere eller alle. Du kan også lagre uten varsel.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                _channelTile(
                  title: 'Alle kanaler',
                  subtitle: 'App + SMS + e-post',
                  icon: Icons.select_all_rounded,
                  selected: _all,
                  onTap: () => _toggleAll(!_all),
                ),
                const SizedBox(height: 6),
                _channelTile(
                  title: 'App (push)',
                  subtitle: 'Varsel i DriftPro på mobil',
                  icon: Icons.phone_iphone_outlined,
                  selected: _app,
                  onTap: () => setState(() => _app = !_app),
                ),
                const SizedBox(height: 6),
                _channelTile(
                  title: 'SMS',
                  subtitle: 'Tekstmelding til sjåfør/eier',
                  icon: Icons.sms_outlined,
                  selected: _sms,
                  onTap: () => setState(() => _sms = !_sms),
                ),
                const SizedBox(height: 6),
                _channelTile(
                  title: 'E-post',
                  subtitle: 'E-post med PDF-lenke',
                  icon: Icons.email_outlined,
                  selected: _email,
                  onTap: () => setState(() => _email = !_email),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _prefs),
                  style: FilledButton.styleFrom(
                    backgroundColor: DriftProTheme.primaryGreen,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: Text(
                    _none ? 'Bruk uten varsel' : 'Bruk ${_prefs.shortLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _channelTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0xFFE8F5E9) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? DriftProTheme.primaryGreen.withValues(alpha: 0.45)
                  : Colors.black12,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected
                    ? DriftProTheme.primaryGreen
                    : Colors.blueGrey.shade600,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: selected
                    ? DriftProTheme.primaryGreen
                    : Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
