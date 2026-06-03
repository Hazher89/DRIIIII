import 'package:flutter/material.dart';

import '../../../models/partner/partner_links.dart';
import 'partner_modern_ui.dart';

/// Kompakt bedriftskort for rutenett.
class PartnerCompanyGridCard extends StatelessWidget {
  const PartnerCompanyGridCard({
    super.key,
    required this.name,
    required this.orgNumber,
    required this.maviVehicles,
    required this.maviCount,
    required this.regCount,
    required this.isActive,
    required this.routesOwnerOnly,
    required this.ownerAccounts,
    required this.driverAccounts,
    required this.smsPhones,
    required this.onTap,
    this.ownerName,
    this.onActivate,
  });

  final String name;
  final String? orgNumber;
  final List<PartnerVehicle> maviVehicles;
  final int maviCount;
  final int regCount;
  final bool isActive;
  final bool routesOwnerOnly;
  final int ownerAccounts;
  final int driverAccounts;
  final List<String> smsPhones;
  final VoidCallback onTap;
  final String? ownerName;
  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final maviList = PartnerMaviVehicleOverview.filterMavi(
      maviVehicles,
      includeInactive: !isActive,
    );

    return Opacity(
      opacity: isActive ? 1 : 0.72,
      child: Material(
        color: isActive ? PartnerModernUi.surface(context) : PartnerModernUi.border(context).withValues(alpha: 0.25),
        elevation: 0,
        shadowColor: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive ? PartnerModernUi.border(context) : const Color(0xFF9CA3AF),
              ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: PartnerModernUi.border(context).withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        initial,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: PartnerModernUi.textPrimary(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              height: 1.25,
                              color: PartnerModernUi.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              _statusPill(context),
                              if (maviCount > 0) ...[
                                const SizedBox(width: 6),
                                _miniPill(context, '$maviCount MAVI'),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: PartnerModernUi.muted(context),
                    ),
                  ],
                ),
                if (orgNumber != null && orgNumber!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    orgNumber!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: PartnerModernUi.muted(context),
                    ),
                  ),
                ],
                if (ownerName != null && ownerName!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    ownerName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
                  ),
                ],
                const SizedBox(height: 10),
                _statLine(
                  context,
                  label: 'Registrert',
                  value: '$ownerAccounts bedriftsansvarlig${ownerAccounts == 1 ? '' : 'e'} · '
                      '$driverAccounts sjåfør${driverAccounts == 1 ? '' : 'er'}',
                  icon: Icons.badge_outlined,
                ),
                const SizedBox(height: 6),
                _statLine(
                  context,
                  label: 'Rute-SMS',
                  value: routesOwnerOnly
                      ? 'Kun bedriftsansvarlig'
                      : 'Bedriftsansvarlig + sjåfør',
                  icon: routesOwnerOnly ? Icons.person_outline : Icons.groups_2_outlined,
                ),
                const SizedBox(height: 6),
                _statLine(
                  context,
                  label: 'SMS-nummer',
                  value: smsPhones.isEmpty
                      ? 'Ingen registrert'
                      : '${smsPhones.length} nummer · ${smsPhones.take(2).join(' · ')}'
                          '${smsPhones.length > 2 ? ' · +${smsPhones.length - 2}' : ''}',
                  icon: Icons.sms_outlined,
                ),
                const SizedBox(height: 10),
                PartnerMaviVehicleOverview(vehicles: maviList, dense: true, muted: !isActive),
                if (onActivate != null) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: onActivate,
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: const Text('Aktiver'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 36),
                      backgroundColor: const Color(0xFF15803D),
                    ),
                  ),
                ],
                if (regCount > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '$regCount registrering${regCount == 1 ? '' : 'er'} (kun skilt)',
                    style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
                  ),
                ],
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _statusPill(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: (isActive ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF)).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isActive ? 'Aktiv' : 'Deaktivert',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isActive ? const Color(0xFF15803D) : const Color(0xFF6B7280),
        ),
      ),
    );
  }

  Widget _miniPill(BuildContext context, String t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: PartnerModernUi.border(context).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        t,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: PartnerModernUi.muted(context)),
      ),
    );
  }

  Widget _statLine(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: PartnerModernUi.muted(context)),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: PartnerModernUi.textPrimary(context).withValues(alpha: 0.78),
                  ),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Kort for å opprette ny bedrift.
class PartnerCompanyAddCard extends StatelessWidget {
  const PartnerCompanyAddCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PartnerModernUi.surface(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: PartnerModernUi.border(context),
              width: 1.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 32, color: PartnerModernUi.textPrimary(context)),
              const SizedBox(height: 8),
              Text(
                'Ny bedrift',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: PartnerModernUi.textPrimary(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Én eller masse Brreg',
                style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
