import 'package:flutter/material.dart';

import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import 'eco_driving_badge.dart';
import 'partner_modern_ui.dart';

/// Kompakt, moderne bedriftskort for rutenett.
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
    this.ecoDrivingStatus = EcoDrivingStatus.required,
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
  final EcoDrivingStatus ecoDrivingStatus;

  bool get _ecoDone => ecoDrivingStatus == EcoDrivingStatus.completed;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final maviList = PartnerMaviVehicleOverview.filterMavi(
      maviVehicles,
      includeInactive: !isActive,
    );
    const ecoGreen = Color(0xFF166534);
    const accent = Color(0xFF15803D);
    final surface = !isActive
        ? PartnerModernUi.border(context).withValues(alpha: 0.22)
        : _ecoDone
            ? const Color(0xFFF0FDF4)
            : PartnerModernUi.surface(context);
    final borderColor = !isActive
        ? const Color(0xFF9CA3AF)
        : _ecoDone
            ? const Color(0xFF86EFAC)
            : PartnerModernUi.border(context).withValues(alpha: 0.85);

    return Opacity(
      opacity: isActive ? 1 : 0.78,
      child: Material(
        color: Colors.transparent,
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  surface,
                  Color.lerp(surface, Colors.white, 0.35) ?? surface,
                ],
              ),
              border: Border.all(
                color: borderColor,
                width: _ecoDone && isActive ? 1.4 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: (_ecoDone && isActive ? ecoGreen : const Color(0xFF0F172A))
                      .withValues(alpha: _ecoDone && isActive ? 0.12 : 0.06),
                  blurRadius: _ecoDone && isActive ? 18 : 14,
                  offset: const Offset(0, 6),
                  spreadRadius: -2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: !isActive
                            ? const [Color(0xFF9CA3AF), Color(0xFFD1D5DB)]
                            : _ecoDone
                                ? const [Color(0xFF16A34A), Color(0xFF86EFAC)]
                                : [accent.withValues(alpha: 0.75), accent.withValues(alpha: 0.25)],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: _ecoDone && isActive
                                        ? const [Color(0xFFDCFCE7), Color(0xFFBBF7D0)]
                                        : [
                                            PartnerModernUi.border(context).withValues(alpha: 0.55),
                                            PartnerModernUi.border(context).withValues(alpha: 0.28),
                                          ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: (_ecoDone && isActive ? ecoGreen : PartnerModernUi.border(context))
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  initial,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                    letterSpacing: -0.3,
                                    color: _ecoDone && isActive
                                        ? ecoGreen
                                        : PartnerModernUi.textPrimary(context),
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
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                        height: 1.2,
                                        letterSpacing: -0.2,
                                        color: PartnerModernUi.textPrimary(context),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 5,
                                      runSpacing: 4,
                                      children: [
                                        _statusPill(context),
                                        if (maviCount > 0) _miniPill(context, '$maviCount MAVI'),
                                        EcoDrivingBadge(
                                          status: ecoDrivingStatus,
                                          compact: true,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: PartnerModernUi.muted(context).withValues(alpha: 0.7),
                              ),
                            ],
                          ),
                          if ((orgNumber ?? '').trim().isNotEmpty ||
                              (ownerName ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              [
                                if ((orgNumber ?? '').trim().isNotEmpty) orgNumber!.trim(),
                                if ((ownerName ?? '').trim().isNotEmpty) ownerName!.trim(),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.2,
                                color: PartnerModernUi.muted(context),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _metaChip(
                                context,
                                icon: Icons.badge_outlined,
                                label: '$ownerAccounts+$driverAccounts',
                                tip: '$ownerAccounts bedriftsansvarlig · $driverAccounts sjåfør',
                              ),
                              _metaChip(
                                context,
                                icon: routesOwnerOnly
                                    ? Icons.person_outline_rounded
                                    : Icons.groups_2_outlined,
                                label: routesOwnerOnly ? 'Kun BA' : 'BA+sjåfør',
                                tip: routesOwnerOnly
                                    ? 'Rute-SMS kun til bedriftsansvarlig'
                                    : 'Rute-SMS til bedriftsansvarlig og sjåfør',
                              ),
                              _metaChip(
                                context,
                                icon: Icons.sms_outlined,
                                label: smsPhones.isEmpty ? '0 SMS' : '${smsPhones.length} SMS',
                                tip: smsPhones.isEmpty
                                    ? 'Ingen SMS-nummer'
                                    : smsPhones.take(3).join(' · '),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Flexible(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: PartnerMaviVehicleOverview(
                                vehicles: maviList,
                                dense: true,
                                muted: !isActive,
                              ),
                            ),
                          ),
                          if (onActivate != null) ...[
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: onActivate,
                              icon: const Icon(Icons.play_circle_outline, size: 18),
                              label: const Text('Aktiver'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 36),
                                backgroundColor: accent,
                              ),
                            ),
                          ],
                          if (regCount > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '$regCount registrering${regCount == 1 ? '' : 'er'} (kun skilt)',
                              style: TextStyle(
                                fontSize: 10,
                                color: PartnerModernUi.muted(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isActive ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF)).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: PartnerModernUi.border(context).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: PartnerModernUi.muted(context),
        ),
      ),
    );
  }

  Widget _metaChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String tip,
  }) {
    return Tooltip(
      message: tip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: PartnerModernUi.border(context).withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: PartnerModernUi.border(context).withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: PartnerModernUi.muted(context)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: PartnerModernUi.textPrimary(context).withValues(alpha: 0.82),
              ),
            ),
          ],
        ),
      ),
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
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                PartnerModernUi.surface(context),
                PartnerModernUi.border(context).withValues(alpha: 0.18),
              ],
            ),
            border: Border.all(
              color: PartnerModernUi.border(context),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 6),
                spreadRadius: -2,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF15803D).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.add_rounded, size: 28, color: Color(0xFF15803D)),
              ),
              const SizedBox(height: 10),
              Text(
                'Ny bedrift',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: -0.2,
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
