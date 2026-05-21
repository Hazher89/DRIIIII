/// Filter for partner-modul SMS-logg (kun samarbeid-scope i RPC).
class PartnerSmsLogFilters {
  final String? search;
  final String? category;
  final String? status;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? recipient;
  final String? sender;
  final String? phone;
  final String? partnerId;
  final String sort;

  const PartnerSmsLogFilters({
    this.search,
    this.category,
    this.status,
    this.fromDate,
    this.toDate,
    this.recipient,
    this.sender,
    this.phone,
    this.partnerId,
    this.sort = 'created_desc',
  });

  bool get hasActiveFilters =>
      (search?.trim().isNotEmpty ?? false) ||
      category != null ||
      status != null ||
      fromDate != null ||
      toDate != null ||
      (recipient?.trim().isNotEmpty ?? false) ||
      (sender?.trim().isNotEmpty ?? false) ||
      (phone?.trim().isNotEmpty ?? false) ||
      (partnerId?.trim().isNotEmpty ?? false);

  PartnerSmsLogFilters copyWith({
    String? search,
    String? category,
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
    String? recipient,
    String? sender,
    String? phone,
    String? partnerId,
    String? sort,
    bool clearCategory = false,
    bool clearStatus = false,
    bool clearFrom = false,
    bool clearTo = false,
    bool clearPartner = false,
  }) {
    return PartnerSmsLogFilters(
      search: search ?? this.search,
      category: clearCategory ? null : (category ?? this.category),
      status: clearStatus ? null : (status ?? this.status),
      fromDate: clearFrom ? null : (fromDate ?? this.fromDate),
      toDate: clearTo ? null : (toDate ?? this.toDate),
      recipient: recipient ?? this.recipient,
      sender: sender ?? this.sender,
      phone: phone ?? this.phone,
      partnerId: clearPartner ? null : (partnerId ?? this.partnerId),
      sort: sort ?? this.sort,
    );
  }
}
