import 'package:flutter/material.dart';

import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import 'eco_driving_badge.dart';
import 'partner_modern_ui.dart';

/// Smart bedriftskort: rolig oversikt først, detaljer ved hover/utvid.
class PartnerCompanyGridCard extends StatefulWidget {
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

  @override
  State<PartnerCompanyGridCard> createState() => _PartnerCompanyGridCardState();
}

class _PartnerCompanyGridCardState extends State<PartnerCompanyGridCard> {
  bool _hover = false;
  bool _pinnedOpen = false;

  bool get _ecoDone => widget.ecoDrivingStatus == EcoDrivingStatus.completed;
  bool get _ecoOverdue => widget.ecoDrivingStatus == EcoDrivingStatus.overdue;
  bool get _detailsOpen => _hover || _pinnedOpen;

  @override
  Widget build(BuildContext context) {
    final initial =
        widget.name.trim().isNotEmpty ? widget.name.trim()[0].toUpperCase() : '?';
    final maviList = PartnerMaviVehicleOverview.filterMavi(
      widget.maviVehicles,
      includeInactive: !widget.isActive,
    );
    const accent = Color(0xFF15803D);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final surface = !widget.isActive
        ? PartnerModernUi.border(context).withValues(alpha: 0.18)
        : PartnerModernUi.surface(context);

    final borderColor = !widget.isActive
        ? const Color(0xFF9CA3AF)
        : _ecoOverdue
            ? const Color(0xFFFDBA74)
            : _ecoDone
                ? const Color(0xFF86EFAC)
                : PartnerModernUi.border(context);

    final accentBar = !widget.isActive
        ? const Color(0xFF9CA3AF)
        : _ecoDone
            ? const Color(0xFF16A34A)
            : _ecoOverdue
                ? const Color(0xFFEA580C)
                : accent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Opacity(
        opacity: widget.isActive ? 1 : 0.82,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: surface,
                border: Border.all(
                  color: _detailsOpen
                      ? accent.withValues(alpha: 0.55)
                      : borderColor,
                  width: _detailsOpen ? 1.4 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(
                      alpha: _detailsOpen ? 0.08 : 0.04,
                    ),
                    blurRadius: _detailsOpen ? 16 : 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(height: 3, color: accentBar),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  initial,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
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
                                      widget.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        height: 1.2,
                                        letterSpacing: -0.2,
                                        color: PartnerModernUi.textPrimary(
                                          context,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if ((widget.orgNumber ?? '')
                                            .trim()
                                            .isNotEmpty)
                                          widget.orgNumber!.trim(),
                                        if ((widget.ownerName ?? '')
                                            .trim()
                                            .isNotEmpty)
                                          widget.ownerName!.trim(),
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
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: _detailsOpen
                                    ? 'Skjul detaljer'
                                    : 'Vis detaljer',
                                onPressed: () => setState(
                                  () => _pinnedOpen = !_pinnedOpen,
                                ),
                                icon: Icon(
                                  _detailsOpen
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  size: 20,
                                  color: PartnerModernUi.muted(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              EcoDrivingBadge(
                                status: widget.ecoDrivingStatus,
                                compact: true,
                                deadline: widget.ecoDrivingDeadline,
                                completedAt: widget.ecoDrivingCompletedAt,
                              ),
                              _metaChip(
                                context,
                                Icons.directions_car_outlined,
                                '${widget.maviCount} MAVI',
                              ),
                              _metaChip(
                                context,
                                Icons.people_outline,
                                '${widget.ownerAccounts + widget.driverAccounts} portal',
                              ),
                              _metaChip(
                                context,
                                Icons.sms_outlined,
                                '${widget.smsPhones.length} SMS',
                              ),
                            ],
                          ),
                          AnimatedCrossFade(
                            firstChild: const SizedBox(width: double.infinity),
                            secondChild: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: _detailsPanel(
                                context,
                                maviList,
                                isDark: isDark,
                              ),
                            ),
                            crossFadeState: _detailsOpen
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 180),
                            sizeCurve: Curves.easeOutCubic,
                          ),
                          if (widget.onActivate != null) ...[
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: widget.onActivate,
                              icon: const Icon(
                                Icons.play_circle_outline,
                                size: 18,
                              ),
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailsPanel(
    BuildContext context,
    List<PartnerVehicle> maviList, {
    required bool isDark,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8FAF9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: PartnerModernUi.border(context).withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _detailStat(
                  context,
                  'BA',
                  '${widget.ownerAccounts}',
                  const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _detailStat(
                  context,
                  'Sjåfør',
                  '${widget.driverAccounts}',
                  const Color(0xFF0F766E),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _detailStat(
                  context,
                  'SMS',
                  widget.routesOwnerOnly ? 'Kun BA' : 'BA+sjåfør',
                  const Color(0xFF7C3AED),
                ),
              ),
            ],
          ),
          if (maviList.isNotEmpty) ...[
            const SizedBox(height: 8),
            PartnerMaviVehicleOverview(
              vehicles: maviList.take(6).toList(),
              dense: true,
              muted: !widget.isActive,
            ),
            if (maviList.length > 6)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+${maviList.length - 6} flere — åpne bedrift',
                  style: TextStyle(
                    fontSize: 10,
                    color: PartnerModernUi.muted(context),
                  ),
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                widget.regCount > 0
                    ? '${widget.regCount} registrering(er) uten MAVI-kode'
                    : 'Ingen MAVI-biler registrert',
                style: TextStyle(
                  fontSize: 11,
                  color: PartnerModernUi.muted(context),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Trykk kortet for å åpne bedriften',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: PartnerModernUi.muted(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailStat(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: PartnerModernUi.border(context).withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: PartnerModernUi.muted(context),
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: PartnerModernUi.border(context).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: PartnerModernUi.muted(context)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: PartnerModernUi.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (widget.isActive
                ? const Color(0xFF22C55E)
                : const Color(0xFF9CA3AF))
            .withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        widget.isActive ? 'Aktiv' : 'Av',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: widget.isActive
              ? const Color(0xFF15803D)
              : const Color(0xFF6B7280),
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
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: PartnerModernUi.surface(context),
            border: Border.all(
              color: PartnerModernUi.border(context),
              width: 1.2,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: PartnerModernUi.border(context),
              radius: 14,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF15803D).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 26,
                      color: Color(0xFF15803D),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ny bedrift',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: -0.2,
                      color: PartnerModernUi.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Én eller Brreg-masse',
                    style: TextStyle(
                      fontSize: 11,
                      color: PartnerModernUi.muted(context),
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
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(r);
    // Lightweight dashed feel via opacity — full dash path is overkill here.
    canvas.drawPath(path, paint..color = color.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
