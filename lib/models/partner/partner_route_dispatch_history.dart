/// Én rad i MAVI rute-utsendingshistorikk.
class PartnerRouteDispatchHistoryRow {
  const PartnerRouteDispatchHistoryRow({
    required this.shareId,
    required this.partnerId,
    this.partnerName,
    this.unitCode,
    this.registrationNumber,
    this.title,
    required this.shareDate,
    required this.dispatchStatus,
    this.shiftName,
    this.routeStartAt,
    this.sentAt,
    this.sentBy,
    this.sentByName,
    this.ackStatus,
    this.ackAt,
    this.pdfOpenedAt,
    this.pdfOpenedBy,
    this.pdfOpenedByName,
    this.pdfOpenCount = 0,
    this.notifyChannels = const [],
    this.customerCount,
  });

  final String shareId;
  final String partnerId;
  final String? partnerName;
  final String? unitCode;
  final String? registrationNumber;
  final String? title;
  final DateTime shareDate;
  final String dispatchStatus;
  final String? shiftName;
  final DateTime? routeStartAt;
  final DateTime? sentAt;
  final String? sentBy;
  final String? sentByName;
  final String? ackStatus;
  final DateTime? ackAt;
  final DateTime? pdfOpenedAt;
  final String? pdfOpenedBy;
  final String? pdfOpenedByName;
  final int pdfOpenCount;
  final List<String> notifyChannels;
  final int? customerCount;

  factory PartnerRouteDispatchHistoryRow.fromJson(Map<String, dynamic> json) {
    DateTime? ts(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    DateTime day(dynamic v) {
      final p = DateTime.tryParse(v.toString());
      if (p == null) return DateTime.now();
      return DateTime(p.year, p.month, p.day);
    }

    final channels = (json['notify_channels'] as List?)
            ?.map((e) => '$e')
            .toList() ??
        const <String>[];

    return PartnerRouteDispatchHistoryRow(
      shareId: json['share_id'] as String,
      partnerId: json['partner_id'] as String,
      partnerName: json['partner_name'] as String?,
      unitCode: json['unit_code'] as String?,
      registrationNumber: json['registration_number'] as String?,
      title: json['title'] as String?,
      shareDate: day(json['share_date']),
      dispatchStatus: (json['dispatch_status'] as String?) ?? 'sent',
      shiftName: json['shift_name'] as String?,
      routeStartAt: ts(json['route_start_at']),
      sentAt: ts(json['sent_at']),
      sentBy: json['sent_by'] as String?,
      sentByName: json['sent_by_name'] as String?,
      ackStatus: json['ack_status'] as String?,
      ackAt: ts(json['ack_at']),
      pdfOpenedAt: ts(json['pdf_opened_at']),
      pdfOpenedBy: json['pdf_opened_by'] as String?,
      pdfOpenedByName: json['pdf_opened_by_name'] as String?,
      pdfOpenCount: json['pdf_open_count'] as int? ?? 0,
      notifyChannels: channels,
      customerCount: json['customer_count'] as int?,
    );
  }

  bool get wasNotified => dispatchStatus == 'sent';
  bool get pdfWasOpened => pdfOpenedAt != null;

  String get maviLabel {
    final u = (unitCode ?? '').trim();
    if (u.isNotEmpty) return u;
    return registrationNumber ?? '—';
  }
}
