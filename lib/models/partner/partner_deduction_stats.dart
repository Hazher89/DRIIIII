class PartnerDeductionStats {
  const PartnerDeductionStats({
    required this.openCount,
    required this.invoicedCount,
    required this.openAmount,
    required this.invoicedAmount,
    required this.evidenceCount,
  });

  final int openCount;
  final int invoicedCount;
  final double openAmount;
  final double invoicedAmount;
  final int evidenceCount;

  factory PartnerDeductionStats.fromJson(Map<String, dynamic> json) {
    return PartnerDeductionStats(
      openCount: (json['open_count'] as num?)?.toInt() ?? 0,
      invoicedCount: (json['invoiced_count'] as num?)?.toInt() ?? 0,
      openAmount: (json['open_amount'] as num?)?.toDouble() ?? 0,
      invoicedAmount: (json['invoiced_amount'] as num?)?.toDouble() ?? 0,
      evidenceCount: (json['evidence_count'] as num?)?.toInt() ?? 0,
    );
  }
}
