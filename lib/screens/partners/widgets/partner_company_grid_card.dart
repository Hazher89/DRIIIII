import 'package:flutter/material.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
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

  bool get _ecoDone => widget.ecoDrivingStatus == EcoDrivingStatus.completed;
  bool get _ecoOverdue => widget.ecoDrivingStatus == EcoDrivingStatus.overdue;

  String _shortUnit(String unit) {
    final n = MaviUnitCodes.normalize(unit);
    final m = RegExp(r'NO_O_M0*(\d+)').firstMatch(n);
    if (m != null) return 'M${m.group(1)}';
    if (n.length > 10) return n.substring(0, 10);
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final initial =
        widget.name.trim().isNotEmpty ? widget.name.trim()[0].toUpperCase() : '?';
    // Vis alle registrerte MAVI på kortet — også de deaktivert i ruteplanlegger.
    final maviList = PartnerMaviVehicleOverview.filterMavi(
      widget.maviVehicles,
      includeInactive: true,
    );
    const accent = Color(0xFF15803D);
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
            borderRadius: BorderRadius.circular(22),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: surface,
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: _hover ? 0.08 : 0.035),
                    blurRadius: _hover ? 18 : 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(width: 5, color: accentBar),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
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
                                      color: accent.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                        color: PartnerModernUi.textPrimary(context),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                            height: 1.15,
                                            letterSpacing: -0.3,
                                            color: PartnerModernUi.textPrimary(context),
                                          ),
                                        ),
                                        if ((widget.ownerName ?? '').trim().isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            widget.ownerName!.trim(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: PartnerModernUi.textPrimary(context).withValues(alpha: 0.78),
                                            ),
                                          ),
                                        ],
                                        if ((widget.orgNumber ?? '').trim().isNotEmpty)
                                          Text(
                                            'Org.nr ${widget.orgNumber!.trim()}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: PartnerModernUi.muted(context),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  _statusPill(context),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  _count(context, '${widget.maviCount}', 'biler'),
                                  _count(context, '${widget.ownerAccounts + widget.driverAccounts}', 'portal'),
                                  _count(context, '${widget.smsPhones.length}', 'SMS'),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  EcoDrivingBadge(
                                    status: widget.ecoDrivingStatus,
                                    compact: true,
                                    deadline: widget.ecoDrivingDeadline,
                                    completedAt: widget.ecoDrivingCompletedAt,
                                  ),
                                  Text(
                                    widget.routesOwnerOnly ? 'Ruter bare til ansvarlig' : 'Ruter til ansvarlig og sjåfør',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: PartnerModernUi.muted(context),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (maviList.isEmpty)
                                Text(
                                  widget.regCount > 0
                                      ? '${widget.regCount} skilt uten MAVI'
                                      : 'Ingen biler ennå',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: PartnerModernUi.muted(context),
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final v in maviList.take(10))
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: v.isActive
                                              ? accent.withValues(alpha: 0.08)
                                              : const Color(0xFFF3F4F6),
                                          borderRadius: BorderRadius.circular(999),
                                          border: v.isActive
                                              ? null
                                              : Border.all(color: const Color(0xFFD1D5DB)),
                                        ),
                                        child: Text(
                                          v.isActive
                                              ? _shortUnit(v.unitCode)
                                              : '${_shortUnit(v.unitCode)} · av',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: v.isActive
                                                ? const Color(0xFF166534)
                                                : const Color(0xFF6B7280),
                                          ),
                                        ),
                                      ),
                                    if (maviList.length > 8)
                                      Text(
                                        '+${maviList.length - 8}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: PartnerModernUi.muted(context),
                                        ),
                                      ),
                                  ],
                                ),
                              if (widget.onActivate != null) ...[
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: widget.onActivate,
                                  icon: const Icon(Icons.play_circle_outline, size: 18),
                                  label: const Text('Aktiver'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 40),
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
        ),
      ),
    );
  }

  Widget _count(BuildContext context, String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: PartnerModernUi.textPrimary(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: PartnerModernUi.muted(context),
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
