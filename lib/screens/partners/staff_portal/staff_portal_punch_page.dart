import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/services/partner/partner_workforce_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_workforce.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import '../widgets/partner_portal_page_shell.dart';

/// Enkel stempling for partner-ansatte.
class StaffPortalPunchPage extends StatefulWidget {
  final Partner partner;
  final UserProfile profile;

  const StaffPortalPunchPage({
    super.key,
    required this.partner,
    required this.profile,
  });

  @override
  State<StaffPortalPunchPage> createState() => _StaffPortalPunchPageState();
}

class _StaffPortalPunchPageState extends State<StaffPortalPunchPage> {
  List<PartnerTimeEntry> _mine = [];
  bool _loading = true;
  bool _busy = false;
  bool _clockedIn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final entries = await PartnerWorkforceService.listEntries(
        partnerId: widget.partner.id,
        from: DateTime.now().subtract(const Duration(days: 14)),
      );
      // Filter to own entries via open punch state
      final open = entries.where((e) => e.isOpen).toList();
      if (!mounted) return;
      setState(() {
        _mine = entries;
        _clockedIn = open.isNotEmpty;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _punch() async {
    setState(() => _busy = true);
    try {
      final res = await PartnerWorkforceService.punch();
      if (!mounted) return;
      final action = res['action']?.toString() ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'punch_in' ? 'Stemplet inn' : 'Stemplet ut',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE dd.MM HH:mm');
    return PartnerPortalPageShell(
      title: 'Stempling',
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        IconButton(
          tooltip: 'Logg ut',
          icon: const Icon(Icons.logout),
          onPressed: () => signOutFromPortal(context),
        ),
      ],
      body: _loading
          ? const DriftProLoadingCenter()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(widget.partner.name, style: DriftProTheme.headingSm),
                const SizedBox(height: 8),
                Text(
                  _clockedIn ? 'Du er stemplet inn' : 'Du er stemplet ut',
                  style: DriftProTheme.bodyMd,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 64,
                  child: FilledButton(
                    onPressed: _busy ? null : _punch,
                    style: FilledButton.styleFrom(
                      backgroundColor: _clockedIn
                          ? Colors.red.shade700
                          : DriftProTheme.primaryGreen,
                    ),
                    child: Text(
                      _clockedIn ? 'Stemple ut' : 'Stemple inn',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text('Siste 14 dager', style: DriftProTheme.labelLg),
                const SizedBox(height: 8),
                ..._mine.take(20).map(
                  (e) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      e.isOpen
                          ? 'Inn ${fmt.format(e.clockIn.toLocal())}'
                          : '${fmt.format(e.clockIn.toLocal())} → ${fmt.format(e.clockOut!.toLocal())}',
                    ),
                    subtitle: e.duration != null
                        ? Text('${(e.duration!.inMinutes / 60).toStringAsFixed(1)} timer')
                        : null,
                  ),
                ),
              ],
            ),
    );
  }
}
