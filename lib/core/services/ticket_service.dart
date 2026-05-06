import '../../models/ticket.dart';
import '../../models/user_profile.dart';

/// Aggregerte tall for avvik-dashboard (beregnes på klientsiden fra full liste).
class TicketDashboardStats {
  final int total;
  final int aapen;
  final int underBehandling;
  final int tiltakUtfort;
  final int lukket;
  final int kritiskAapne;
  final int forfalt; // forfalt frist (åpne/under behandling)
  final int medBilder;

  const TicketDashboardStats({
    required this.total,
    required this.aapen,
    required this.underBehandling,
    required this.tiltakUtfort,
    required this.lukket,
    required this.kritiskAapne,
    required this.forfalt,
    required this.medBilder,
  });

  factory TicketDashboardStats.fromTickets(List<Ticket> tickets) {
    final now = DateTime.now();
    int a = 0, u = 0, t = 0, l = 0, k = 0, f = 0, img = 0;
    for (final x in tickets) {
      if (x.status == TicketStatus.aapen) {
        a++;
      } else if (x.status == TicketStatus.underBehandling) {
        u++;
      } else if (x.status == TicketStatus.tiltakUtfort) {
        t++;
      } else if (x.status == TicketStatus.lukket) {
        l++;
      }
      final openish =
          x.status == TicketStatus.aapen || x.status == TicketStatus.underBehandling;
      if (openish &&
          x.severity == TicketSeverity.kritisk) {
        k++;
      }
      if (openish && x.dueDate != null) {
        final d = DateTime(x.dueDate!.year, x.dueDate!.month, x.dueDate!.day);
        if (d.isBefore(DateTime(now.year, now.month, now.day))) {
          f++;
        }
      }
      if (x.imageUrls.isNotEmpty) {
        img++;
      }
    }
    return TicketDashboardStats(
      total: tickets.length,
      aapen: a,
      underBehandling: u,
      tiltakUtfort: t,
      lukket: l,
      kritiskAapne: k,
      forfalt: f,
      medBilder: img,
    );
  }
}

extension TicketRoles on UserProfile {
  /// Leder og administratorer kan bruke kontrollsenter og full saksbehandling.
  bool get canCoordinateTickets => isLeader;
}
