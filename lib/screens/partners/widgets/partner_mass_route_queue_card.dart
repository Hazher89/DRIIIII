import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import 'partner_route_pdf_actions.dart';
import 'partner_route_pdf_thumbnail.dart';

/// Kompakt rute-kort — PDF-forside dominerer, detaljer i eget panel.
class PartnerMassRouteQueueCard extends StatelessWidget {
  final PartnerRouteShare share;
  final FleetPartnerVehicleRow row;
  final Color accent;
  final Color accentDark;
  final bool checked;
  final bool shiftMissing;
  final bool busy;
  final String? shiftId;
  final String? shiftLabel;
  final String? lane;
  final DateTime routeDay;
  final TimeOfDay startTime;
  final List<FleetShiftDefinition> routeShifts;
  final List<FleetPartnerVehicleRow> maviFleet;
  final TextEditingController noteController;
  final ValueChanged<bool?> onChecked;
  final VoidCallback onRemove;
  final ValueChanged<String> onReassignVehicle;
  final Future<void> Function(DateTime date) onDateChanged;
  final ValueChanged<String> onShiftChanged;
  final ValueChanged<TimeOfDay> onStartChanged;
  final VoidCallback? onOpenDetails;

  const PartnerMassRouteQueueCard({
    super.key,
    required this.share,
    required this.row,
    required this.accent,
    required this.accentDark,
    required this.checked,
    required this.shiftMissing,
    required this.busy,
    required this.shiftId,
    required this.shiftLabel,
    required this.lane,
    required this.routeDay,
    required this.startTime,
    required this.routeShifts,
    required this.maviFleet,
    required this.noteController,
    required this.onChecked,
    required this.onRemove,
    required this.onReassignVehicle,
    required this.onDateChanged,
    required this.onShiftChanged,
    required this.onStartChanged,
    this.onOpenDetails,
  });

  String get _fileLabel =>
      (share.title ?? share.pdfStoragePath.split('/').last).split('—').last.trim();

  String get _mavi => MaviUnitCodes.compactLabel(row.vehicle.unitCode);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateLabel = DateFormat('d.M.y', 'nb').format(routeDay);
    final laneLabel = lane != null ? 'Lane $lane · ' : '';

    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenDetails,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: shiftMissing
                  ? Colors.amber.shade600
                  : checked
                      ? accent.withValues(alpha: 0.55)
                      : isDark
                          ? DriftProTheme.dividerDark
                          : Colors.grey.shade200,
              width: shiftMissing || checked ? 2 : 1,
            ),
            boxShadow: DriftProTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PartnerRoutePdfThumbnail(
                      share: share,
                      driverLabel: _mavi,
                      showFullPage: true,
                      onTapOpen: () => PartnerRoutePdfActions.openPdf(context, share),
                    ),
                    Positioned(
                      top: 6,
                      left: 2,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                        child: Checkbox(
                          value: checked,
                          activeColor: accentDark,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          onChanged: busy ? null : onChecked,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (shiftMissing)
                            _chip('Mangler skift', Colors.amber.shade800, Colors.amber.shade100),
                          if (checked && !shiftMissing) ...[
                            const SizedBox(width: 4),
                            _chip('Valgt', accentDark, accent.withValues(alpha: 0.15)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fileLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$laneLabel${shiftLabel ?? 'Velg skift'} · $dateLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => PartnerRoutePdfActions.openPdf(context, share),
                            icon: const Icon(Icons.open_in_new, size: 14),
                            label: const Text('PDF', style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Detaljer',
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          onPressed: onOpenDetails,
                          icon: const Icon(Icons.tune),
                        ),
                        IconButton(
                          tooltip: 'Slett',
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          onPressed: busy ? null : onRemove,
                          icon: const Icon(Icons.delete_outline, color: DriftProTheme.error),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  /// Full skjema for redigering i bottom sheet.
  static Widget buildDetailsForm({
    required BuildContext context,
    required PartnerRouteShare share,
    required FleetPartnerVehicleRow row,
    required Color accentDark,
    required bool shiftMissing,
    required bool checked,
    required bool busy,
    required String? shiftId,
    required String? shiftLabel,
    required String? lane,
    required DateTime routeDay,
    required TimeOfDay startTime,
    required List<FleetShiftDefinition> routeShifts,
    required List<FleetPartnerVehicleRow> maviFleet,
    required TextEditingController noteController,
    required ValueChanged<String> onReassignVehicle,
    required Future<void> Function(DateTime date) onDateChanged,
    required ValueChanged<String> onShiftChanged,
    required ValueChanged<TimeOfDay> onStartChanged,
    required VoidCallback onRemove,
  }) {
    final dateLabel = DateFormat('EEE d.M.y', 'nb').format(routeDay);
    final startLabel =
        '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
    final fileLabel =
        (share.title ?? share.pdfStoragePath.split('/').last).split('—').last.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(fileLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          MaviUnitCodes.fleetDriverLabel(row.vehicle.unitCode, row.partner.name),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        if (lane != null) ...[
          const SizedBox(height: 2),
          Text('Lane $lane', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: share.partnerVehicleId,
          isExpanded: true,
          decoration: _fieldDeco('Bytt sjåfør / MAVI'),
          items: maviFleet
              .map(
                (r) => DropdownMenuItem(
                  value: r.vehicle.id,
                  child: Text(
                    MaviUnitCodes.fleetDriverLabel(r.vehicle.unitCode, r.partner.name),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (vid) {
                  if (vid != null && vid != share.partnerVehicleId) onReassignVehicle(vid);
                },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: noteController,
          maxLines: 3,
          decoration: _fieldDeco('Kommentar til sjåfør'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: shiftId,
          isExpanded: true,
          decoration: _fieldDeco('Skiftplan').copyWith(
            errorText: shiftMissing && checked ? 'Velg dag- eller kveldsrute' : null,
          ),
          items: routeShifts
              .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
              .toList(),
          onChanged: busy ? null : (v) { if (v != null) onShiftChanged(v); },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: routeDay,
                          firstDate: DateTime.now().subtract(const Duration(days: 30)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) await onDateChanged(picked);
                      },
                icon: const Icon(Icons.event, size: 18),
                label: Text(dateLabel, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: startTime,
                        );
                        if (picked != null) onStartChanged(picked);
                      },
                icon: const Icon(Icons.schedule, size: 18),
                label: Text('Start $startLabel'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => PartnerRoutePdfActions.openPdf(context, share),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Åpne PDF'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: busy ? null : onRemove,
          icon: const Icon(Icons.delete_outline, color: DriftProTheme.error),
          label: const Text('Slett fra kø', style: TextStyle(color: DriftProTheme.error)),
        ),
      ],
    );
  }

  static InputDecoration _fieldDeco(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      );
}
