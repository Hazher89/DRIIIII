import 'package:flutter/material.dart';

import '../../../core/services/partner/partner_workforce_service.dart';
import '../../../models/partner/partner.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/partner_workforce_owner_hub.dart';

class OwnerPortalTimesheetPage extends StatefulWidget {
  final Partner partner;
  final bool isSuperAdmin;

  const OwnerPortalTimesheetPage({
    super.key,
    required this.partner,
    this.isSuperAdmin = false,
  });

  @override
  State<OwnerPortalTimesheetPage> createState() => _OwnerPortalTimesheetPageState();
}

class _OwnerPortalTimesheetPageState extends State<OwnerPortalTimesheetPage> {
  final _hubController = PartnerWorkforceOwnerHubController();
  bool _loading = true;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _checkEnabled();
  }

  Future<void> _checkEnabled() async {
    try {
      final enabled = await PartnerWorkforceService.isEnabled(widget.partner.id);
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PartnerPortalPageShell(
      title: 'Timeliste & timerbank',
      floatingActionButton: _enabled
          ? FloatingActionButton.extended(
              onPressed: () => _hubController.addManualEntry(),
              icon: const Icon(Icons.add),
              label: const Text('Legg til timer'),
            )
          : null,
      body: _loading
          ? const DriftProLoadingCenter()
          : !_enabled
              ? RefreshIndicator(
                  onRefresh: _checkEnabled,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: const [
                      SizedBox(height: 80),
                      Center(
                        child: Text('Timer er ikke aktivert for denne bedriften.'),
                      ),
                    ],
                  ),
                )
              : PartnerWorkforceOwnerHub(
                  partner: widget.partner,
                  isSuperAdmin: widget.isSuperAdmin,
                  controller: _hubController,
                ),
    );
  }
}
