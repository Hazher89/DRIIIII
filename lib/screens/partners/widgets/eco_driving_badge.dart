import 'package:flutter/material.dart';

import '../../../models/partner/partner.dart';

/// Profesjonell ECO Driving-badge for partnerkort, detalj og eierportal.
class EcoDrivingBadge extends StatelessWidget {
  const EcoDrivingBadge({
    super.key,
    required this.status,
    this.compact = false,
    this.showLabel = true,
  });

  final EcoDrivingStatus status;
  final bool compact;
  final bool showLabel;

  factory EcoDrivingBadge.forPartner(
    Partner partner, {
    bool compact = false,
    bool showLabel = true,
  }) {
    return EcoDrivingBadge(
      status: partner.ecoDrivingStatus,
      compact: compact,
      showLabel: showLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(status, compact: compact);
    final padH = compact ? 7.0 : 10.0;
    final padV = compact ? 4.0 : 6.0;
    final iconSize = compact ? 14.0 : 16.0;
    final fontSize = compact ? 10.0 : 12.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: iconSize, color: style.fg),
          if (showLabel) ...[
            const SizedBox(width: 5),
            Text(
              style.label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: style.fg,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static _EcoStyle _styleFor(EcoDrivingStatus status, {required bool compact}) {
    switch (status) {
      case EcoDrivingStatus.completed:
        return const _EcoStyle(
          label: 'ECO Driving',
          icon: Icons.eco_rounded,
          fg: Color(0xFF166534),
          bg: Color(0xFFDCFCE7),
          border: Color(0xFF86EFAC),
        );
      case EcoDrivingStatus.overdue:
        return _EcoStyle(
          label: compact ? 'ECO · forsinket' : 'ECO Driving — forsinket',
          icon: Icons.eco_outlined,
          fg: const Color(0xFF9A3412),
          bg: const Color(0xFFFFEDD5),
          border: const Color(0xFFFDBA74),
        );
      case EcoDrivingStatus.required:
        return _EcoStyle(
          label: compact ? 'ECO · 3 mnd' : 'ECO Driving — innen 3 mnd',
          icon: Icons.eco_outlined,
          fg: const Color(0xFF854D0E),
          bg: const Color(0xFFFEF9C3),
          border: const Color(0xFFFDE047),
        );
    }
  }
}

class _EcoStyle {
  const _EcoStyle({
    required this.label,
    required this.icon,
    required this.fg,
    required this.bg,
    required this.border,
  });

  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
  final Color border;
}

/// Kort seksjon for å registrere / oppdatere ECO Driving-status.
class EcoDrivingCourseEditor extends StatelessWidget {
  const EcoDrivingCourseEditor({
    super.key,
    required this.completed,
    required this.deadline,
    required this.onCompletedChanged,
    this.dense = false,
  });

  final bool completed;
  final DateTime? deadline;
  final ValueChanged<bool> onCompletedChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final status = completed
        ? EcoDrivingStatus.completed
        : EcoDrivingStatus.fromDeadline(deadline);
    final deadlineLabel = deadline == null
        ? null
        : '${deadline!.day.toString().padLeft(2, '0')}.'
            '${deadline!.month.toString().padLeft(2, '0')}.'
            '${deadline!.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: completed,
          onChanged: onCompletedChanged,
          secondary: Icon(
            completed ? Icons.eco_rounded : Icons.eco_outlined,
            color: completed ? const Color(0xFF166534) : Colors.grey[600],
          ),
          title: Text(
            dense ? 'ECO Driving Kurs' : 'Har tatt ECO Driving Kurs',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            completed
                ? 'Kurset er registrert som gjennomført'
                : deadlineLabel != null
                    ? 'Frist: $deadlineLabel (3 måneder)'
                    : 'Må tas innen 3 måneder',
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: EcoDrivingBadge(status: status, compact: true),
        ),
      ],
    );
  }
}
