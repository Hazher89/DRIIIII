import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/absence/department_leave_conflict_service.dart';
import '../../../core/theme/app_theme.dart';
/// Tips til leder/superadmin: andre i avdelingen har ferie/fravær samme dato.
class DepartmentLeaveTipCard extends StatelessWidget {
  final List<DepartmentLeaveOverlap> overlaps;
  final String? departmentName;
  final bool compact;
  final bool isApprovalContext;

  const DepartmentLeaveTipCard({
    super.key,
    required this.overlaps,
    this.departmentName,
    this.compact = false,
    this.isApprovalContext = false,
  });

  @override
  Widget build(BuildContext context) {
    if (overlaps.isEmpty) return const SizedBox.shrink();

    final approvedVacation =
        DepartmentLeaveConflictService.approvedVacation(overlaps);
    final pending = DepartmentLeaveConflictService.pendingAny(overlaps);
    final df = DateFormat('d. MMM', 'nb');

    final isCritical = approvedVacation.isNotEmpty;
    final color = isCritical ? Colors.orange.shade800 : DriftProTheme.warning;
    final bg = isCritical
        ? Colors.orange.withValues(alpha: 0.12)
        : DriftProTheme.warning.withValues(alpha: 0.1);

    return Container(
      margin: compact
          ? const EdgeInsets.fromLTRB(16, 0, 16, 12)
          : const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isCritical ? Icons.groups_2_outlined : Icons.lightbulb_outline,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isApprovalContext
                          ? (isCritical
                              ? 'Tips før godkjenning'
                              : 'Avdelingstips')
                          : 'Kollegaer i samme periode',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                        fontSize: compact ? 13 : 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _headline(
                        departmentName: departmentName,
                        approvedVacation: approvedVacation.length,
                        pending: pending.length,
                      ),
                      style: DriftProTheme.bodySm,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...overlaps.take(compact ? 3 : 8).map((o) => _overlapRow(o, df)),
          if (overlaps.length > (compact ? 3 : 8))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '+ ${overlaps.length - (compact ? 3 : 8)} til…',
                style: DriftProTheme.caption,
              ),
            ),
          if (isApprovalContext && isCritical) ...[
            const SizedBox(height: 8),
            Text(
              'Vurder bemanning i ${departmentName ?? "avdelingen"} før du godkjenner.',
              style: DriftProTheme.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _headline({
    String? departmentName,
    required int approvedVacation,
    required int pending,
  }) {
    final dept = departmentName ?? 'avdelingen';
    if (approvedVacation > 0 && pending > 0) {
      return '$approvedVacation har allerede godkjent ferie og $pending har ventende fravær i $dept i samme periode.';
    }
    if (approvedVacation > 0) {
      return approvedVacation == 1
          ? '1 kollega har allerede godkjent ferie i $dept i samme periode.'
          : '$approvedVacation kollegaer har allerede godkjent ferie i $dept i samme periode.';
    }
    if (pending > 0) {
      return '$pending kollega${pending == 1 ? "" : "er"} har ventende fravær i $dept som overlapper.';
    }
    return 'Andre i $dept har fravær som overlapper denne perioden.';
  }

  Widget _overlapRow(DepartmentLeaveOverlap o, DateFormat df) {
    final name = o.other.userName ?? 'Ukjent';
    final period =
        '${df.format(o.overlapStart)} – ${df.format(o.overlapEnd)} (${o.overlapDays} d.)';
    final statusColor = o.isApproved
        ? DriftProTheme.success
        : DriftProTheme.warning;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            o.isVacation ? Icons.beach_access : Icons.event_busy,
            size: 16,
            color: statusColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DriftProTheme.bodySm.copyWith(color: Colors.black87),
                children: [
                  TextSpan(
                    text: name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' · ${o.other.type.label} · $period · '),
                  TextSpan(
                    text: o.isApproved ? 'Godkjent' : 'Venter',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
