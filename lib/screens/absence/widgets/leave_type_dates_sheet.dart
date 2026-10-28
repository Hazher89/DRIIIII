import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/absence/absence_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';

Future<void> showLeaveTypeDatesSheet(
  BuildContext context, {
  required String title,
  required List<Absence> absences,
  Map<String, String>? approverNames,
  void Function(Absence absence)? onTap,
}) {
  final sorted = [...absences]
    ..sort((a, b) => b.startDate.compareTo(a.startDate));
  final df = DateFormat('d. MMM yyyy', 'nb_NO');

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (_, scroll) {
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              Text(
                title,
                style: DriftProTheme.headingSm.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sorted.isEmpty
                    ? 'Ingen registreringer i valgt periode'
                    : '${sorted.length} ${sorted.length == 1 ? 'periode' : 'perioder'}',
                style: DriftProTheme.caption,
              ),
              const SizedBox(height: 14),
              if (sorted.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Ingenting å vise her for valgt år/periode.',
                    style: DriftProTheme.bodySm,
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ...sorted.map((a) {
                  final days = a.type == AbsenceType.ferie
                      ? (a.vacationDayCount ??
                          AbsenceService.vacationDayCount(
                            a.startDate,
                            a.endDate,
                          ))
                      : (a.totalDays ??
                          AbsenceService.dayCount(a.startDate, a.endDate));
                  final approver = a.approvedBy == null
                      ? null
                      : approverNames?[a.approvedBy!];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? DriftProTheme.cardDark
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: onTap == null
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                onTap(a);
                              },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.grey.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${df.format(a.startDate)} – ${df.format(a.endDate)}',
                                      style: DriftProTheme.labelMd.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        a.status.label,
                                        if (approver != null)
                                          'Godkjent av $approver',
                                        if ((a.comment ?? '')
                                            .trim()
                                            .isNotEmpty)
                                          a.comment!.trim(),
                                      ].join(' · '),
                                      style: DriftProTheme.caption,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '$days d',
                                style: DriftProTheme.labelMd.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      );
    },
  );
}
