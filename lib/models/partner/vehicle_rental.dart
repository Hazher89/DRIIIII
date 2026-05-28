import 'package:flutter/material.dart' show IconData, Icons;

/// Bilutleie mellom samarbeidspartnere (bileier → låntaker, godkjent av MAVI).
class VehicleRental {
  final String id;
  final String companyId;
  final String lenderPartnerId;
  final String borrowerPartnerId;
  final String partnerVehicleId;
  final String? registrationNumber;
  final String? vehicleMake;
  final String? unitCode;
  final DateTime? rentalStart;
  final DateTime? rentalEnd;
  final DateTime? rentalStartAt;
  final DateTime? rentalEndAt;
  final String status;
  final DateTime? agreementAcceptedAt;
  final DateTime? ownerSubmittedAt;
  final DateTime? approvedAt;
  final String? approvedBy;
  final DateTime? rejectedAt;
  final String? rejectionReason;
  final String? maviCheckoutComment;
  final String? maviReturnComment;
  final String? fuelLevel;
  final int? odometerKm;
  final String? ownerComment;
  final Map<String, String> photos;
  final Map<String, String> returnPhotos;
  final String? returnFuelLevel;
  final int? returnOdometerKm;
  final String? returnComment;
  final DateTime? returnSubmittedAt;
  final DateTime? returnApprovedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Låntaker / låner navn (fylls inn av service ved listevisning).
  final String? lenderPartnerName;
  final String? borrowerPartnerName;
  final String? lenderPartnerOrgNumber;
  final String? borrowerPartnerOrgNumber;

  const VehicleRental({
    required this.id,
    required this.companyId,
    required this.lenderPartnerId,
    required this.borrowerPartnerId,
    required this.partnerVehicleId,
    this.registrationNumber,
    this.vehicleMake,
    this.unitCode,
    this.rentalStart,
    this.rentalEnd,
    this.rentalStartAt,
    this.rentalEndAt,
    required this.status,
    this.agreementAcceptedAt,
    this.ownerSubmittedAt,
    this.approvedAt,
    this.approvedBy,
    this.rejectedAt,
    this.rejectionReason,
    this.maviCheckoutComment,
    this.maviReturnComment,
    this.fuelLevel,
    this.odometerKm,
    this.ownerComment,
    this.photos = const {},
    this.returnPhotos = const {},
    this.returnFuelLevel,
    this.returnOdometerKm,
    this.returnComment,
    this.returnSubmittedAt,
    this.returnApprovedAt,
    required this.createdAt,
    required this.updatedAt,
    this.lenderPartnerName,
    this.borrowerPartnerName,
    this.lenderPartnerOrgNumber,
    this.borrowerPartnerOrgNumber,
  });

  bool get isPendingOwner => status == 'pending_owner';
  bool get isPendingMavi => status == 'pending_mavi';
  bool get isApproved => status == 'approved';
  bool get isPendingReturnMavi => status == 'pending_return_mavi';
  bool get isReturned => status == 'returned';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';

  /// Bilen er utlånt og blokkert til retur er godkjent.
  bool get isBlockedOnLoan => isApproved || isPendingReturnMavi;

  bool get photosComplete => VehicleRentalPhotoSlot.requiredKeys.every(
        (k) => (photos[k] ?? '').trim().isNotEmpty,
      );

  bool get returnPhotosComplete => VehicleRentalPhotoSlot.requiredKeys.every(
        (k) => (returnPhotos[k] ?? '').trim().isNotEmpty,
      );

  static Map<String, String> _parsePhotoMap(dynamic raw) {
    final photoMap = <String, String>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        photoMap['${e.key}'] = '${e.value ?? ''}';
      }
    }
    return photoMap;
  }

  factory VehicleRental.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is String && v.length == 10) return DateTime.tryParse(v);
      return DateTime.tryParse(v.toString());
    }

    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return VehicleRental(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      lenderPartnerId: json['lender_partner_id'] as String,
      borrowerPartnerId: json['borrower_partner_id'] as String,
      partnerVehicleId: json['partner_vehicle_id'] as String,
      registrationNumber: json['registration_number'] as String?,
      vehicleMake: json['vehicle_make'] as String?,
      unitCode: json['unit_code'] as String?,
      rentalStart: parseDate(json['rental_start']),
      rentalEnd: parseDate(json['rental_end']),
      rentalStartAt: parseTs(json['rental_start_at']),
      rentalEndAt: parseTs(json['rental_end_at']),
      status: (json['status'] as String?) ?? 'pending_owner',
      agreementAcceptedAt: parseTs(json['agreement_accepted_at']),
      ownerSubmittedAt: parseTs(json['owner_submitted_at']),
      approvedAt: parseTs(json['approved_at']),
      approvedBy: json['approved_by'] as String?,
      rejectedAt: parseTs(json['rejected_at']),
      rejectionReason: json['rejection_reason'] as String?,
      maviCheckoutComment: json['mavi_checkout_comment'] as String?,
      maviReturnComment: json['mavi_return_comment'] as String?,
      fuelLevel: json['fuel_level'] as String?,
      odometerKm: json['odometer_km'] as int?,
      ownerComment: json['owner_comment'] as String?,
      photos: _parsePhotoMap(json['photos']),
      returnPhotos: _parsePhotoMap(json['return_photos']),
      returnFuelLevel: json['return_fuel_level'] as String?,
      returnOdometerKm: json['return_odometer_km'] as int?,
      returnComment: json['return_comment'] as String?,
      returnSubmittedAt: parseTs(json['return_submitted_at']),
      returnApprovedAt: parseTs(json['return_approved_at']),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      lenderPartnerName: json['lender_partner_name'] as String?,
      borrowerPartnerName: json['borrower_partner_name'] as String?,
      lenderPartnerOrgNumber: json['lender_partner_org_number'] as String?,
      borrowerPartnerOrgNumber: json['borrower_partner_org_number'] as String?,
    );
  }

  String get statusLabel {
    switch (status) {
      case 'pending_owner':
        return 'Venter bileier';
      case 'pending_mavi':
        return 'Venter MAVI (utleie)';
      case 'approved':
        return 'Utleid · blokkert';
      case 'pending_return_mavi':
        return 'Retur venter MAVI';
      case 'returned':
        return 'Returnert · tilgjengelig';
      case 'rejected':
        return 'Avvist';
      case 'cancelled':
        return 'Kansellert';
      default:
        return status;
    }
  }
}

class VehicleRentalPhotoSlot {
  final String key;
  final String label;
  final IconData icon;

  const VehicleRentalPhotoSlot(this.key, this.label, this.icon);

  static const requiredKeys = [
    'front',
    'back',
    'right',
    'left',
    'cargo',
    'dashboard',
  ];

  static const slots = [
    VehicleRentalPhotoSlot('front', 'Front', Icons.camera_front_outlined),
    VehicleRentalPhotoSlot('back', 'Bak', Icons.camera_rear_outlined),
    VehicleRentalPhotoSlot('right', 'Høyre', Icons.arrow_forward),
    VehicleRentalPhotoSlot('left', 'Venstre', Icons.arrow_back),
    VehicleRentalPhotoSlot('cargo', 'Last/skap', Icons.inventory_2_outlined),
    VehicleRentalPhotoSlot('dashboard', 'Dashboard', Icons.speed_outlined),
  ];
}
