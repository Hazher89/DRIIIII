import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/absence.dart';
import 'manager_leave_helpers.dart';

class ManagerLeaveApprovalsPanel extends StatelessWidget {
  const ManagerLeaveApprovalsPanel({
    super.key,
    required this.pending,
    required this.onApprove,
    required this.onReject,
    required this.onOpen,
  });

  final List<Absence> pending;
  final Future<void> Function(Absence absence) onApprove;
  final Future<void> Function(Absence absence) onReject;
  final void Function(Absence absence) onOpen;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : const Color(0xFFE8EEF0),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Søknader til godkjenning',
                        style: DriftProTheme.labelLg.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pending.isEmpty
                            ? 'Ingen saker som krever handling'
                            : '${pending.length} ${pending.length == 1 ? 'søknad venter' : 'søknader venter'}',
                        style: DriftProTheme.caption.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (pending.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: DriftProTheme.warning.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${pending.length}',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 28, 18, 36),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: DriftProTheme.success.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: DriftProTheme.success,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ingen ventende søknader akkurat nå',
                    style: DriftProTheme.labelMd.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Nye ferie- og fraværssøknader dukker opp her.',
                    style: DriftProTheme.caption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 720) {
                  return Column(
                    children: [
                      for (final a in pending)
                        _ApprovalMobileCard(
                          absence: a,
                          isDark: isDark,
                          onApprove: () => onApprove(a),
                          onReject: () => onReject(a),
                          onOpen: () => onOpen(a),
                        ),
                    ],
                  );
                }
                return _ApprovalsTable(
                  pending: pending,
                  isDark: isDark,
                  onApprove: onApprove,
                  onReject: onReject,
                  onOpen: onOpen,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ApprovalsTable extends StatelessWidget {
  const _ApprovalsTable({
    required this.pending,
    required this.isDark,
    required this.onApprove,
    required this.onReject,
    required this.onOpen,
  });

  final List<Absence> pending;
  final bool isDark;
  final Future<void> Function(Absence) onApprove;
  final Future<void> Function(Absence) onReject;
  final void Function(Absence) onOpen;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.sizeOf(context).width - 64,
        ),
        child: DataTable(
          headingRowHeight: 42,
          dataRowMinHeight: 64,
          dataRowMaxHeight: 78,
          horizontalMargin: 18,
          columnSpacing: 22,
          headingTextStyle: DriftProTheme.caption.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF64748B),
            letterSpacing: 0.2,
          ),
          columns: const [
            DataColumn(label: Text('ANSATT')),
            DataColumn(label: Text('TYPE')),
            DataColumn(label: Text('PERIODE')),
            DataColumn(label: Text('VARIGHET')),
            DataColumn(label: Text('SØKT')),
            DataColumn(label: Text('HANDLINGER')),
          ],
          rows: [
            for (final a in pending)
              DataRow(
                cells: [
                  DataCell(
                    InkWell(
                      onTap: () => onOpen(a),
                      child: _EmployeeCell(
                        name: a.userName ?? 'Ansatt',
                        avatarUrl: a.userAvatarUrl,
                      ),
                    ),
                  ),
                  DataCell(_TypeBadge(type: a.type)),
                  DataCell(Text(
                    ManagerLeaveHelpers.formatShortPeriod(a),
                    style: DriftProTheme.bodySm.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  )),
                  DataCell(Text(
                    '${ManagerLeaveHelpers.daysFor(a)} dager',
                    style: DriftProTheme.bodySm.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  )),
                  DataCell(Text(
                    a.createdAt == null
                        ? '—'
                        : DateFormat('d. MMM', 'nb_NO').format(a.createdAt!),
                    style: DriftProTheme.caption,
                  )),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton(
                          onPressed: () => onApprove(a),
                          style: FilledButton.styleFrom(
                            backgroundColor: DriftProTheme.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Godkjenn'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => onReject(a),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF64748B),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Avslå'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalMobileCard extends StatelessWidget {
  const _ApprovalMobileCard({
    required this.absence,
    required this.isDark,
    required this.onApprove,
    required this.onReject,
    required this.onOpen,
  });

  final Absence absence;
  final bool isDark;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark
                  ? DriftProTheme.dividerDark
                  : const Color(0xFFF1F5F9),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _EmployeeCell(
                    name: absence.userName ?? 'Ansatt',
                    avatarUrl: absence.userAvatarUrl,
                  ),
                ),
                _TypeBadge(type: absence.type),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${ManagerLeaveHelpers.formatPeriod(absence)} · '
              '${ManagerLeaveHelpers.daysFor(absence)} dager',
              style: DriftProTheme.bodySm.copyWith(fontWeight: FontWeight.w600),
            ),
            if (absence.createdAt != null) ...[
              const SizedBox(height: 2),
              Text(
                'Søkt ${DateFormat('d. MMM yyyy', 'nb_NO').format(absence.createdAt!)}',
                style: DriftProTheme.caption,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onApprove,
                    style: FilledButton.styleFrom(
                      backgroundColor: DriftProTheme.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Godkjenn'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Avslå'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeCell extends StatelessWidget {
  const _EmployeeCell({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((p) => p.isEmpty ? '' : p[0].toUpperCase())
            .join();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.14),
          backgroundImage:
              (avatarUrl != null && avatarUrl!.isNotEmpty)
                  ? NetworkImage(avatarUrl!)
                  : null,
          child: (avatarUrl == null || avatarUrl!.isEmpty)
              ? Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: DriftProTheme.primaryGreen,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: DriftProTheme.bodySm.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final AbsenceType type;

  @override
  Widget build(BuildContext context) {
    final color = ManagerLeaveHelpers.colorForType(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
