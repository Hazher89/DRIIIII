class SmsLogFilters {
  final String? search;
  final String? category;
  final String? status;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? recipient;
  final String? sender;
  final String? phone;

  const SmsLogFilters({
    this.search,
    this.category,
    this.status,
    this.fromDate,
    this.toDate,
    this.recipient,
    this.sender,
    this.phone,
  });

  bool get hasActiveFilters =>
      (search?.trim().isNotEmpty ?? false) ||
      category != null ||
      status != null ||
      fromDate != null ||
      toDate != null ||
      (recipient?.trim().isNotEmpty ?? false) ||
      (sender?.trim().isNotEmpty ?? false) ||
      (phone?.trim().isNotEmpty ?? false);

  SmsLogFilters copyWith({
    String? search,
    String? category,
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
    String? recipient,
    String? sender,
    String? phone,
    bool clearCategory = false,
    bool clearStatus = false,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return SmsLogFilters(
      search: search ?? this.search,
      category: clearCategory ? null : (category ?? this.category),
      status: clearStatus ? null : (status ?? this.status),
      fromDate: clearFrom ? null : (fromDate ?? this.fromDate),
      toDate: clearTo ? null : (toDate ?? this.toDate),
      recipient: recipient ?? this.recipient,
      sender: sender ?? this.sender,
      phone: phone ?? this.phone,
    );
  }
}
