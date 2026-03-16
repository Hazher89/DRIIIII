class DashboardStats {
  final int todayAbsences;
  final int openTickets;
  final int criticalTickets;
  final int highRiskCount;
  final int pendingSja;
  final int expiringDocuments;
  final int upcomingSafetyRounds;
  final int totalEmployees;
  final double absenceRate;

  const DashboardStats({
    this.todayAbsences = 0,
    this.openTickets = 0,
    this.criticalTickets = 0,
    this.highRiskCount = 0,
    this.pendingSja = 0,
    this.expiringDocuments = 0,
    this.upcomingSafetyRounds = 0,
    this.totalEmployees = 0,
    this.absenceRate = 0,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      todayAbsences: (json['today_absences'] as num?)?.toInt() ?? 0,
      openTickets: (json['open_tickets'] as num?)?.toInt() ?? 0,
      criticalTickets: (json['critical_tickets'] as num?)?.toInt() ?? 0,
      highRiskCount: (json['high_risk_count'] as num?)?.toInt() ?? 0,
      pendingSja: (json['pending_sja'] as num?)?.toInt() ?? 0,
      expiringDocuments: (json['expiring_documents'] as num?)?.toInt() ?? 0,
      upcomingSafetyRounds:
          (json['upcoming_safety_rounds'] as num?)?.toInt() ?? 0,
      totalEmployees: (json['total_employees'] as num?)?.toInt() ?? 0,
      absenceRate: (json['absence_rate'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Demo data for previewing the dashboard
  factory DashboardStats.demo() {
    return const DashboardStats(
      todayAbsences: 3,
      openTickets: 7,
      criticalTickets: 1,
      highRiskCount: 2,
      pendingSja: 4,
      expiringDocuments: 5,
      upcomingSafetyRounds: 1,
      totalEmployees: 42,
      absenceRate: 7.1,
    );
  }
}
