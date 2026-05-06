import 'package:flutter/material.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/ticket_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ticket.dart';
import '../../models/user_profile.dart';
import 'new_ticket_screen.dart';
import 'ticket_admin_dashboard_screen.dart';
import 'ticket_detail_screen.dart';

/// Avvik med synlig hub: KPI, hurtighandlinger og liste (ikke «gjemt» kontrollsenter).
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  TicketStatus? _filterStatus;

  List<Ticket> _tickets = const [];
  bool _isLoading = true;
  String? _error;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfileAndTickets();
  }

  Future<void> _loadProfileAndTickets() async {
    final p = await SupabaseService.fetchCurrentUserProfile();
    if (mounted) setState(() => _profile = p);
    await _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final cid =
          _profile?.companyId ?? await SupabaseService.getCurrentCompanyId();
      final tickets = cid != null
          ? await SupabaseService.fetchTickets(companyId: cid)
          : await SupabaseService.fetchTickets();
      setState(() {
        _tickets = tickets;
      });
    } catch (e) {
      setState(() {
        _error = 'Kunne ikke hente avvik fra Supabase.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _openNewTicket() {
    Navigator.of(context)
        .push<bool>(
      MaterialPageRoute(
        builder: (_) => const NewTicketScreen(),
      ),
    )
        .then((created) {
      if (created == true) {
        _loadTickets();
      }
    });
  }

  void _openControlCenter() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const TicketAdminDashboardScreen(),
      ),
    );
  }

  Color _sevColor(TicketSeverity s) {
    switch (s) {
      case TicketSeverity.lav:
        return DriftProTheme.severityLow;
      case TicketSeverity.middels:
        return DriftProTheme.severityMedium;
      case TicketSeverity.hoy:
        return DriftProTheme.severityHigh;
      case TicketSeverity.kritisk:
        return DriftProTheme.severityCritical;
    }
  }

  Color _statColor(TicketStatus s) {
    switch (s) {
      case TicketStatus.aapen:
        return DriftProTheme.info;
      case TicketStatus.underBehandling:
        return DriftProTheme.warning;
      case TicketStatus.tiltakUtfort:
        return DriftProTheme.success;
      case TicketStatus.lukket:
        return Colors.grey;
    }
  }

  IconData _statIcon(TicketStatus s) {
    switch (s) {
      case TicketStatus.aapen:
        return AppIcons.statusOpen;
      case TicketStatus.underBehandling:
        return AppIcons.statusInProgress;
      case TicketStatus.tiltakUtfort:
        return AppIcons.statusDone;
      case TicketStatus.lukket:
        return AppIcons.statusClosed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stats = TicketDashboardStats.fromTickets(_tickets);
    final coord = _profile?.canCoordinateTickets == true;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(AppStrings.navTickets),
            Text(
              'Spor hendelser · bilder · status',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
        actions: [
          if (coord)
            IconButton(
              icon: const Icon(Icons.dashboard_customize_outlined),
              tooltip: 'Kontrollsenter',
              onPressed: _openControlCenter,
            ),
          IconButton(icon: const Icon(AppIcons.search), onPressed: () {}),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewTicket,
        icon: const Icon(AppIcons.add),
        label: const Text(AppStrings.reportDeviation),
      ),
      body: RefreshIndicator(
        onRefresh: _loadTickets,
        color: DriftProTheme.primaryGreen,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _buildHubHeader(stats, isDark),
            ),
            SliverToBoxAdapter(
              child: _buildQuickActions(coord, isDark),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Filter',
                  style: DriftProTheme.labelSm.copyWith(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _chip('Alle', _filterStatus == null, () {
                      setState(() => _filterStatus = null);
                    }),
                    ...TicketStatus.values.map(
                      (s) => _chip(
                        s.label,
                        _filterStatus == s,
                        () => setState(() => _filterStatus = s),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: DriftProTheme.bodyMd,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else ..._buildTicketSlivers(stats, isDark, coord),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTicketSlivers(
    TicketDashboardStats stats,
    bool isDark,
    bool coord,
  ) {
    final filtered = _filterStatus == null
        ? _tickets
        : _tickets.where((t) => t.status == _filterStatus).toList();

    if (filtered.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _emptyState(stats, isDark, coord),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ticketCard(filtered[i], isDark),
            ),
            childCount: filtered.length,
          ),
        ),
      ),
    ];
  }

  Widget _buildHubHeader(TicketDashboardStats s, bool isDark) {
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF0D1B2A),
        const Color(0xFF1B263B),
        const Color(0xFFE65100),
      ],
      stops: const [0.0, 0.55, 1.0],
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE65100).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                ),
                child: const Icon(
                  Icons.shield_moon_outlined,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Avvik — operativ hub',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB74D).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Text(
                            '3.0',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Operativ sikkerhet · ${s.total} saker · live tall og filter',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _hubStat('Åpne', '${s.aapen}', Icons.flag_outlined),
              _hubStat('Under behandling', '${s.underBehandling}',
                  Icons.hourglass_top_rounded),
              _hubStat('Kritisk (åpen)', '${s.kritiskAapne}',
                  Icons.warning_amber_rounded),
              _hubStat('Forfalt frist', '${s.forfalt}', Icons.event_busy),
              _hubStat('Med bilder', '${s.medBilder}', Icons.photo_library_outlined),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bildeopplasting · statusløype · tildeling · kontrollsenter',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hubStat(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(bool coordinator, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _openNewTicket,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: DriftProTheme.primaryGreen,
            ),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text(
              'Meld nytt avvik',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          if (coordinator) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _openControlCenter,
              style: OutlinedButton.styleFrom(
                foregroundColor: DriftProTheme.primaryGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: DriftProTheme.primaryGreen, width: 1.4),
              ),
              icon: const Icon(Icons.analytics_outlined),
              label: const Text(
                'Åpne kontrollsenter (KPI, kø og saker)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (!coordinator)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Leder og HMS‑ansvarlige får ekstra verktøy i «Kontrollsenter».',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState(TicketDashboardStats s, bool isDark, bool coord) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Ingen avvik i denne filtervisningen',
            style: DriftProTheme.headingSm.copyWith(
              color: isDark ? Colors.white : Colors.grey[900],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            s.total == 0
                ? 'Start ved å melde en observasjon med tekst og bilder. Saken får automatisk status og havner i køen til leder.'
                : 'Prøv et annet filter, eller opprett et nytt avvik.',
            style: DriftProTheme.bodyMd.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[700],
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _featureChip(Icons.photo_camera_outlined, 'Bilder'),
              _featureChip(Icons.timeline, 'Statusløype'),
              _featureChip(Icons.person_search, 'Tildeling'),
              _featureChip(Icons.event_note, 'Frister'),
              if (coord) _featureChip(Icons.dashboard, 'KPI‑dash'),
            ],
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _openNewTicket,
            icon: const Icon(Icons.add),
            label: const Text('Meld første avvik'),
          ),
        ],
      ),
    );
  }

  Widget _featureChip(IconData icon, String text) {
    return Chip(
      avatar: Icon(icon, size: 18, color: DriftProTheme.primaryGreen),
      label: Text(text, style: const TextStyle(fontSize: 12)),
      side: BorderSide(color: Colors.grey.shade300),
      backgroundColor: Colors.white,
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? DriftProTheme.primaryGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(DriftProTheme.radiusRound),
            border: Border.all(
              color: selected ? DriftProTheme.primaryGreen : Colors.grey.shade300,
            ),
          ),
          child: Text(
            label,
            style: DriftProTheme.labelSm.copyWith(
              color: selected ? Colors.white : Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _ticketCard(Ticket t, bool isDark) {
    final sev = t.severity;
    final stat = t.status;
    final sc = _sevColor(sev);
    final stc = _statColor(stat);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(
          color: sev == TicketSeverity.kritisk
              ? sc.withValues(alpha: 0.35)
              : isDark
                  ? DriftProTheme.dividerDark
                  : Colors.grey.shade100,
        ),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context)
              .push(
            MaterialPageRoute(
              builder: (_) => TicketDetailScreen(
                ticket: t,
                coordinatorProfile: _profile,
              ),
            ),
          )
              .then((_) => _loadTickets());
        },
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _badge(sev.label, sc),
                  const SizedBox(width: 8),
                  _statusBadge(stat.label, stc, _statIcon(stat)),
                  const Spacer(),
                  if (t.ticketNumber != null)
                    Text(
                      '#${t.ticketNumber}',
                      style: DriftProTheme.caption.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                t.title,
                style: DriftProTheme.headingSm.copyWith(
                  color: isDark ? Colors.white : Colors.grey[900],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t.description,
                style: DriftProTheme.bodySm.copyWith(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(AppIcons.profile, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(
                    t.reporterName ?? 'Ukjent',
                    style: DriftProTheme.caption.copyWith(fontSize: 11),
                  ),
                  const SizedBox(width: 12),
                  Icon(AppIcons.category, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(
                    t.category ?? 'Uspesifisert',
                    style: DriftProTheme.caption.copyWith(fontSize: 11),
                  ),
                  const Spacer(),
                  if (t.createdAt != null)
                    Text(
                      t.createdAt!.toLocal().toIso8601String().split('T').first,
                      style: DriftProTheme.caption.copyWith(fontSize: 10),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusRound),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: DriftProTheme.labelSm.copyWith(
              color: color,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusRound),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: DriftProTheme.labelSm.copyWith(
              color: color,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
