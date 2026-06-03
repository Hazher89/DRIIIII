class EmailLogFilters {
  final String? search;
  final String? category;
  final String? status;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? recipient;
  final String? sender;
  final String? partnerId;
  final String? sort;

  const EmailLogFilters({
    this.search,
    this.category,
    this.status,
    this.fromDate,
    this.toDate,
    this.recipient,
    this.sender,
    this.partnerId,
    this.sort,
  });
}
