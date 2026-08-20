import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/partner/partner.dart';

/// Profesjonell ECO Driving-badge for partnerkort, detalj og eierportal.
class EcoDrivingBadge extends StatelessWidget {
  const EcoDrivingBadge({
    super.key,
    required this.status,
    this.compact = false,
    this.showLabel = true,
    this.prominent = false,
    this.deadline,
    this.completedAt,
  });

  final EcoDrivingStatus status;
  final bool compact;
  final bool showLabel;
  /// Full-bredde stripe på bedriftskort — ekstra synlig når kurset er tatt.
  final bool prominent;
  final DateTime? deadline;
  final DateTime? completedAt;

  factory EcoDrivingBadge.forPartner(
    Partner partner, {
    bool compact = false,
    bool showLabel = true,
    bool prominent = false,
  }) {
    return EcoDrivingBadge(
      status: partner.ecoDrivingStatus,
      compact: compact,
      showLabel: showLabel,
      prominent: prominent,
      deadline: partner.ecoDrivingDeadline,
      completedAt: partner.ecoDrivingCompletedAt,
    );
  }

  static final _dateFmt = DateFormat('d. MMM yyyy', 'nb_NO');

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(status);
    if (prominent) return _prominentBanner(style);
    return _pill(style);
  }

  Widget _pill(_EcoStyle style) {
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
              _shortLabel(style),
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.15,
                color: style.fg,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _prominentBanner(_EcoStyle style) {
    final done = status == EcoDrivingStatus.completed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: done
              ? const [Color(0xFFDCFCE7), Color(0xFFBBF7D0)]
              : [style.bg, style.bg.withValues(alpha: 0.85)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: style.border,
          width: done ? 1.4 : 1,
        ),
        boxShadow: done
            ? [
                BoxShadow(
                  color: style.fg.withValues(alpha: 0.14),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(style.icon, size: 18, color: style.fg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  style.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.1,
                    color: style.fg,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _detailLine(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: style.fg.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          if (done)
            Icon(Icons.verified_rounded, size: 20, color: style.fg),
        ],
      ),
    );
  }

  String _shortLabel(_EcoStyle style) {
    if (!compact) return style.label;
    return switch (status) {
      EcoDrivingStatus.completed => 'ECO · tatt',
      EcoDrivingStatus.overdue => 'ECO · forsinket',
      EcoDrivingStatus.required => 'ECO · 3 mnd',
    };
  }

  String _detailLine() {
    switch (status) {
      case EcoDrivingStatus.completed:
        if (completedAt != null) {
          return 'Gjennomført ${_dateFmt.format(completedAt!)}';
        }
        return 'Kurset er gjennomført';
      case EcoDrivingStatus.overdue:
        if (deadline != null) {
          return 'Frist utløpt ${_dateFmt.format(deadline!)}';
        }
        return 'Fristen er overskredet — må tas snarest';
      case EcoDrivingStatus.required:
        if (deadline != null) {
          return 'Frist ${_dateFmt.format(deadline!)}';
        }
        return 'Må tas innen 3 måneder';
    }
  }

  static _EcoStyle _styleFor(EcoDrivingStatus status) {
    switch (status) {
      case EcoDrivingStatus.completed:
        return const _EcoStyle(
          label: 'ECO Driving — gjennomført',
          icon: Icons.eco_rounded,
          fg: Color(0xFF166534),
          bg: Color(0xFFDCFCE7),
          border: Color(0xFF4ADE80),
        );
      case EcoDrivingStatus.overdue:
        return const _EcoStyle(
          label: 'ECO Driving — forsinket',
          icon: Icons.warning_amber_rounded,
          fg: Color(0xFF9A3412),
          bg: Color(0xFFFFEDD5),
          border: Color(0xFFFDBA74),
        );
      case EcoDrivingStatus.required:
        return const _EcoStyle(
          label: 'ECO Driving — mangler',
          icon: Icons.eco_outlined,
          fg: Color(0xFF854D0E),
          bg: Color(0xFFFEF9C3),
          border: Color(0xFFFDE047),
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
    final accent = completed ? const Color(0xFF166534) : const Color(0xFFB45309);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: completed,
            onChanged: onCompletedChanged,
            secondary: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                completed ? Icons.eco_rounded : Icons.eco_outlined,
                color: accent,
              ),
            ),
            title: Text(
              dense ? 'ECO Driving Kurs' : 'Har tatt ECO Driving Kurs',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: accent,
              ),
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
            child: EcoDrivingBadge(
              status: status,
              compact: true,
              deadline: deadline,
            ),
          ),
        ],
      ),
    );
  }
}
