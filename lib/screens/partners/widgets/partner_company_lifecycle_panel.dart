import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/permissions/user_access.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import 'partner_modern_ui.dart';

/// Farlige bedriftshandlinger — kompakt kort nederst under Bedrift (ikke i header).
class PartnerCompanyLifecyclePanel extends StatelessWidget {
  const PartnerCompanyLifecyclePanel({
    super.key,
    required this.partner,
    required this.profile,
    required this.onChanged,
    this.onDeleted,
    this.initiallyExpanded = false,
  });

  final Partner partner;
  final UserProfile? profile;
  final Future<void> Function() onChanged;
  final VoidCallback? onDeleted;
  /// Beholdt for bakoverkompatibilitet — panelet er alltid kompakt.
  final bool initiallyExpanded;

  bool get _canManage =>
      profile?.access.canPartnersAdmin == true ||
      profile?.access.canPartnersDelete == true;

  bool get _canDelete =>
      profile?.access.canPartnersDelete == true ||
      profile?.access.canPartnersAdmin == true;

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String? typedConfirm,
  }) async {
    final ctrl = typedConfirm != null ? TextEditingController() : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (typedConfirm != null && ctrl != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    labelText: 'Skriv $typedConfirm for å bekrefte',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setSt(() {}),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
              onPressed: typedConfirm == null || ctrl == null
                  ? () => Navigator.pop(ctx, true)
                  : (ctrl.text.trim().toUpperCase() == typedConfirm
                      ? () => Navigator.pop(ctx, true)
                      : null),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
    ctrl?.dispose();
    return ok == true;
  }

  Future<void> _deactivate(BuildContext context) async {
    final ok = await _confirm(
      context,
      title: 'Deaktiver bedrift?',
      message:
          '«${partner.name}» fjernes fra Bedrifter-listen og ruteplanlegging. '
          'Alle MAVI-biler blir grå og får ikke nye ruter. '
          'Ingen SMS (inkl. felles meldinger). Portal-brukere kan ikke logge inn på driftpro.no. '
          'Du kan aktivere igjen under Deaktiverte bedrifter.',
      confirmLabel: 'Deaktiver',
    );
    if (!ok || !context.mounted) return;

    try {
      final report = await PartnerService.deactivatePartnerCompany(partner.id);
      await onChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bedrift deaktivert · ${report.vehicles} bil(er) · ${report.portals} portal(er)',
          ),
        ),
      );
      Navigator.of(context).pop(false);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kunne ikke deaktivere: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _activate(BuildContext context) async {
    final ok = await _confirm(
      context,
      title: 'Aktiver bedrift?',
      message:
          '«${partner.name}» vises igjen på Bedrifter. MAVI-biler kan få ruter, SMS og portal-innlogging gjenopprettes.',
      confirmLabel: 'Aktiver',
    );
    if (!ok || !context.mounted) return;

    try {
      final report = await PartnerService.activatePartnerCompany(partner.id);
      await onChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bedrift aktivert · ${report.vehicles} bil(er) · ${report.portals} portal(er)',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kunne ikke aktivere: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deletePermanent(BuildContext context) async {
    final ok = await _confirm(
      context,
      title: 'Slett bedrift permanent?',
      message:
          '«${partner.name}» og ALT tilhørende slettes for alltid: ruter, dokumenter, portaler, kjøretøy, historikk og filer. '
          'Dette kan ikke angres.',
      confirmLabel: 'Slett permanent',
      typedConfirm: 'SLETT',
    );
    if (!ok || !context.mounted) return;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const PopScope(
          canPop: false,
          child: Center(child: DriftProLoadingCenter()),
        ),
      ),
    );

    try {
      await PartnerService.deletePartner(partner.id);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bedrift slettet permanent')),
      );
      onDeleted?.call();
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sletting feilet: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canManage) return const SizedBox.shrink();

    const orange = Color(0xFFEA580C);
    const red = Color(0xFFDC2626);

    return PartnerModernSection(
      icon: Icons.shield_outlined,
      title: 'Farlige handlinger',
      subtitle: partner.isActive
          ? 'Deaktiver skjuler bedriften midlertidig. Slett er permanent.'
          : 'Bedriften er deaktivert. Aktiver for å bruke den igjen, eller slett.',
      children: [
        if (partner.isActive)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _deactivate(context),
              icon: const Icon(Icons.pause_circle_filled_rounded),
              label: const Text('Deaktiver bedrift'),
              style: FilledButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 46),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _activate(context),
              icon: const Icon(Icons.play_circle_filled_rounded),
              label: const Text('Aktiver bedrift'),
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 46),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        if (_canDelete) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _deletePermanent(context),
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('Slett bedrift permanent'),
              style: FilledButton.styleFrom(
                backgroundColor: red,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 46),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
