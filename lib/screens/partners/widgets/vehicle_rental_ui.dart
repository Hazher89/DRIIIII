import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/vehicle_rental_agreement.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/vehicle_rental.dart';

Color vehicleRentalStatusColor(String status) {
  switch (status) {
    case 'approved':
      return DriftProTheme.error;
    case 'pending_return_mavi':
      return Colors.deepOrange.shade800;
    case 'returned':
      return DriftProTheme.success;
    case 'pending_mavi':
      return DriftProTheme.warning;
    case 'pending_owner':
      return DriftProTheme.accentBlue;
    case 'rejected':
      return DriftProTheme.error;
    default:
      return Colors.grey.shade600;
  }
}

IconData vehicleRentalStatusIcon(String status) {
  switch (status) {
    case 'approved':
      return Icons.lock;
    case 'pending_return_mavi':
      return Icons.assignment_return;
    case 'returned':
      return Icons.check_circle;
    case 'pending_mavi':
      return Icons.hourglass_top;
    case 'pending_owner':
      return Icons.edit_document;
    case 'rejected':
      return Icons.cancel;
    default:
      return Icons.directions_car;
  }
}

Widget vehicleRentalStatusChip(VehicleRental rental, {bool compact = false}) {
  final color = vehicleRentalStatusColor(rental.status);
  return Container(
    padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(vehicleRentalStatusIcon(rental.status), size: compact ? 12 : 14, color: color),
        SizedBox(width: compact ? 4 : 6),
        Text(
          rental.statusLabel,
          style: TextStyle(
            fontSize: compact ? 10 : 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    ),
  );
}

String vehicleRentalPeriodLabel(VehicleRental r) {
  final fmtTs = DateFormat('d.M.y HH:mm', 'nb');
  if (r.rentalStartAt != null && r.rentalEndAt != null) {
    return '${fmtTs.format(r.rentalStartAt!.toLocal())} – ${fmtTs.format(r.rentalEndAt!.toLocal())}';
  }
  if (r.rentalStartAt != null) return 'Fra ${fmtTs.format(r.rentalStartAt!.toLocal())}';
  if (r.rentalEndAt != null) return 'Til ${fmtTs.format(r.rentalEndAt!.toLocal())}';
  if (r.rentalStart == null && r.rentalEnd == null) return 'Periode ikke satt';
  final fmt = DateFormat('d.M.y', 'nb');
  if (r.rentalStart != null && r.rentalEnd != null) {
    return '${fmt.format(r.rentalStart!)} – ${fmt.format(r.rentalEnd!)}';
  }
  if (r.rentalStart != null) return 'Fra ${fmt.format(r.rentalStart!)}';
  return 'Til ${fmt.format(r.rentalEnd!)}';
}

String vehicleRentalAgreementText(VehicleRental rental) {
  return VehicleRentalAgreement.body(
    registrationNumber: rental.registrationNumber ?? '—',
    vehicleMake: rental.vehicleMake ?? '—',
    unitCode: rental.unitCode,
    lenderName: rental.lenderPartnerName,
    lenderOrgNumber: rental.lenderPartnerOrgNumber,
    borrowerName: rental.borrowerPartnerName,
    borrowerOrgNumber: rental.borrowerPartnerOrgNumber,
    rentalPeriodLabel: vehicleRentalPeriodLabel(rental),
  );
}

class VehicleRentalStatsRow extends StatelessWidget {
  final int pendingOwner;
  final int pendingMavi;
  final int onLoan;
  final int pendingReturn;
  final int returned;

  const VehicleRentalStatsRow({
    super.key,
    required this.pendingOwner,
    required this.pendingMavi,
    required this.onLoan,
    required this.pendingReturn,
    required this.returned,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _StatChip(label: 'Bileier', count: pendingOwner, color: DriftProTheme.accentBlue),
          _StatChip(label: 'MAVI utleie', count: pendingMavi, color: DriftProTheme.warning),
          _StatChip(label: 'Utleid', count: onLoan, color: DriftProTheme.error),
          _StatChip(label: 'Retur', count: pendingReturn, color: Colors.deepOrange),
          _StatChip(label: 'Ferdig', count: returned, color: DriftProTheme.success),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.08), color.withValues(alpha: 0.18)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color),
          ),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class VehicleRentalMobileCard extends StatelessWidget {
  final VehicleRental rental;
  final VoidCallback? onTap;
  final Widget? action;
  final bool showBlockedBanner;

  const VehicleRentalMobileCard({
    super.key,
    required this.rental,
    this.onTap,
    this.action,
    this.showBlockedBanner = true,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = vehicleRentalStatusColor(rental.status);
    final blocked = rental.isBlockedOnLoan && showBlockedBanner;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: blocked ? DriftProTheme.error.withValues(alpha: 0.45) : statusColor.withValues(alpha: 0.2),
          width: blocked ? 2 : 1,
        ),
      ),
      color: blocked
          ? Colors.red.shade50
          : rental.isReturned
              ? Colors.green.shade50
              : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.directions_car, color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${MaviUnitCodes.normalize(rental.unitCode ?? '—')} · ${rental.registrationNumber ?? '—'}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        Text(
                          rental.vehicleMake ?? '—',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  vehicleRentalStatusChip(rental, compact: true),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${rental.lenderPartnerName ?? 'Utleier'} → ${rental.borrowerPartnerName ?? 'Låntaker'}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                vehicleRentalPeriodLabel(rental),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
              if (rental.approvedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Utleid ${DateFormat('d.M.y HH:mm', 'nb').format(rental.approvedAt!.toLocal())}',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
              if (rental.returnApprovedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Returnert ${DateFormat('d.M.y HH:mm', 'nb').format(rental.returnApprovedAt!.toLocal())}',
                  style: TextStyle(fontSize: 10, color: DriftProTheme.success),
                ),
              ],
              if (blocked) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: DriftProTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock, size: 16, color: DriftProTheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          rental.isApproved
                              ? 'Reg.nr blokkert — bilen er utlånt til ${rental.borrowerPartnerName ?? 'låntaker'}'
                              : 'Retur sendt — venter MAVI-godkjenning',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: DriftProTheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 12),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 6 obligatoriske bilder — mobil: 2 kolonner, full bredde.
class VehicleRentalPhotoGrid extends StatelessWidget {
  final Map<String, String> photos;
  final bool readOnly;
  final Future<void> Function(String slotKey, Uint8List bytes)? onCapture;

  const VehicleRentalPhotoGrid({
    super.key,
    required this.photos,
    this.readOnly = false,
    this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: VehicleRentalPhotoSlot.slots.map((slot) {
            final path = photos[slot.key];
            final done = path != null && path.isNotEmpty;
            return SizedBox(
              width: width.clamp(140, 220),
              child: Material(
                color: done ? Colors.green.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: readOnly || onCapture == null ? null : () => _pick(context, slot.key),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: done ? Colors.green.shade400 : Colors.grey.shade400,
                        width: done ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          done ? Icons.check_circle : slot.icon,
                          color: done ? Colors.green.shade700 : Colors.grey.shade600,
                          size: 30,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          slot.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: done ? Colors.green.shade900 : Colors.grey.shade800,
                          ),
                        ),
                        if (done)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('OK', style: TextStyle(fontSize: 10, color: Colors.green.shade700)),
                          )
                        else if (!readOnly)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Trykk for bilde', style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _pick(BuildContext context, String slotKey) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await onCapture!(slotKey, bytes);
  }
}

class VehicleRentalDetailSection extends StatelessWidget {
  final VehicleRental rental;
  final bool showReturnData;

  const VehicleRentalDetailSection({
    super.key,
    required this.rental,
    this.showReturnData = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        vehicleRentalStatusChip(rental),
        const SizedBox(height: 12),
        _InfoBlock(
          title: 'Leieavtale',
          child: SelectableText(
            vehicleRentalAgreementText(rental),
            style: const TextStyle(fontSize: 12, height: 1.45),
          ),
        ),
        if (rental.fuelLevel != null) ...[
          const SizedBox(height: 12),
          _InfoBlock(
            title: 'Utleie — tilstand ved overlevering',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Drivstoff: ${rental.fuelLevel}'),
                Text('Km: ${rental.odometerKm ?? '—'}'),
                if (rental.ownerComment != null && rental.ownerComment!.isNotEmpty)
                  Text('Kommentar: ${rental.ownerComment}'),
                if (rental.photos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Bilder ved utleie', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(height: 8),
                  VehicleRentalPhotoGrid(photos: rental.photos, readOnly: true),
                ],
              ],
            ),
          ),
        ],
        if (showReturnData && rental.returnFuelLevel != null) ...[
          const SizedBox(height: 12),
          _InfoBlock(
            title: 'Retur — tilstand',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Drivstoff: ${rental.returnFuelLevel}'),
                Text('Km: ${rental.returnOdometerKm ?? '—'}'),
                if (rental.returnComment != null && rental.returnComment!.isNotEmpty)
                  Text('Kommentar: ${rental.returnComment}'),
                if (rental.returnPhotos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Bilder ved retur', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(height: 8),
                  VehicleRentalPhotoGrid(photos: rental.returnPhotos, readOnly: true),
                ],
              ],
            ),
          ),
        ],
        if (rental.maviCheckoutComment != null && rental.maviCheckoutComment!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _InfoBlock(
            title: 'MAVI ved utleie',
            child: Text(rental.maviCheckoutComment!),
          ),
        ],
        if (rental.maviReturnComment != null && rental.maviReturnComment!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _InfoBlock(
            title: 'MAVI ved retur',
            child: Text(rental.maviReturnComment!),
          ),
        ],
      ],
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final String title;
  final Widget child;

  const _InfoBlock({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

Future<void> showVehicleRentalDetailSheet(
  BuildContext context, {
  required VehicleRental rental,
  Widget? actions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${rental.registrationNumber ?? '—'} · ${rental.vehicleMake ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                VehicleRentalDetailSection(rental: rental),
                if (actions != null) ...[
                  const SizedBox(height: 16),
                  actions,
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget vehicleRentalListTile(
  VehicleRental rental, {
  VoidCallback? onTap,
  Widget? trailing,
}) {
  return VehicleRentalMobileCard(
    rental: rental,
    onTap: onTap,
    action: trailing,
  );
}
