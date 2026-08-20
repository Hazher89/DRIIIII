import 'package:flutter/material.dart';

import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import 'eco_driving_badge.dart';
import 'partner_modern_ui.dart';

/// Bedriftskort: tydelig oversikt + ekstra synlig ECO Driving.
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
    this.ecoDrivingDeadline,
    this.ecoDrivingCompletedAt,
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
  final DateTime? ecoDrivingDeadline;
  final DateTime? ecoDrivingCompletedAt;

  bool get _ecoDone => ecoDrivingStatus == EcoDrivingStatus.completed;
  bool get _ecoOverdue => ecoDrivingStatus == EcoDrivingStatus.overdue;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final maviList = PartnerMaviVehicleOverview.filterMavi(
      maviVehicles,
      includeInactive: !isActive,
    );
    const ecoGreen = Color(0xFF166534);
    const accent = Color(0xFF15803D);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final surface = !isActive
        ? PartnerModernUi.border(context).withValues(alpha: 0.22)
        : _ecoDone
            ? (isDark ? const Color(0xFF14532D).withValues(alpha: 0.28) : const Color(0xFFF0FDF4))
            : _ecoOverdue
                ? (isDark ? const Color(0xFF7C2D12).withValues(alpha: 0.22) : const Color(0xFFFFF7ED))
                : PartnerModernUi.surface(context);

    final borderColor = !isActive
        ? const Color(0xFF9CA3AF)
        : _ecoDone
            ? const Color(0xFF4ADE80)
            : _ecoOverdue
                ? const Color(0xFFFDBA74)
                : PartnerModernUi.border(context).withValues(alpha: 0.9);

    return Opacity(
      opacity: isActive ? 1 : 0.78,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: surface,
              border: Border.all(
                color: borderColor,
                width: (_ecoDone || _ecoOverdue) && isActive ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: (_ecoDone && isActive
                          ? ecoGreen
                          : const Color(0xFF0F172A))
                      .withValues(alpha: _ecoDone && isActive ? 0.12 : 0.05),
                  blurRadius: _ecoDone && isActive ? 16 : 12,
                  offset: const Offset(0, 5),
                  spreadRadius: -2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 4,
                    color: !isActive
                        ? const Color(0xFF9CA3AF)
                        : _ecoDone
                            ? const Color(0xFF16A34A)
                            : _ecoOverdue
                                ? const Color(0xFFEA580C)
                                : accent,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _ecoDone && isActive
                                      ? const Color(0xFFDCFCE7)
                                      : PartnerModernUi.border(context)
                                          .withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Text(
                                  initial,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
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
                                        fontSize: 14,
                                        height: 1.2,
                                        letterSpacing: -0.25,
                                        color: PartnerModernUi.textPrimary(context),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        if ((orgNumber ?? '').trim().isNotEmpty)
                                          orgNumber!.trim(),
                                        if ((ownerName ?? '').trim().isNotEmpty)
                                          ownerName!.trim(),
                                      ].where((e) => e.isNotEmpty).join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: PartnerModernUi.muted(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _statusPill(context),
                            ],
                          ),
                          const SizedBox(height: 10),
                          EcoDrivingBadge(
                            status: ecoDrivingStatus,
                            prominent: true,
                            deadline: ecoDrivingDeadline,
                            completedAt: ecoDrivingCompletedAt,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _Kpi(
                                  label: 'MAVI',
                                  value: '$maviCount',
                                  color: accent,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _Kpi(
                                  label: 'Portaler',
                                  value: '${ownerAccounts + driverAccounts}',
                                  hint: '$ownerAccounts BA · $driverAccounts sjåfør',
                                  color: const Color(0xFF2563EB),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _Kpi(
                                  label: 'SMS',
                                  value: '${smsPhones.length}',
                                  hint: routesOwnerOnly ? 'Kun BA' : 'BA+sjåfør',
                                  color: const Color(0xFF7C3AED),
                                ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isActive ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF))
            .withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isActive ? 'Aktiv' : 'Av',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: isActive ? const Color(0xFF15803D) : const Color(0xFF6B7280),
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.color,
    this.hint,
  });

  final String label;
  final String value;
  final String? hint;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: PartnerModernUi.border(context).withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: PartnerModernUi.border(context).withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: PartnerModernUi.muted(context),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              height: 1.05,
              letterSpacing: -0.3,
              color: color,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 1),
            Text(
              hint!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: PartnerModernUi.muted(context),
              ),
            ),
          ],
        ],
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
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: PartnerModernUi.surface(context),
            border: Border.all(
              color: PartnerModernUi.border(context),
              width: 1.4,
            ),
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
