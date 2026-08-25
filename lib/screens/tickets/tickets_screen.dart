import 'package:flutter/material.dart';
import '../../core/case_trace/case_trace.dart';
import '../../core/case_trace/case_trace_chip.dart';
import '../../core/config/driftpro_client.dart';
import '../../core/layout/mobile_layout.dart';
import '../../core/layout/mobile_shell_scaffold.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/build_info.dart';
import '../../core/permissions/access_keys.dart';
import '../../core/permissions/permission_gate.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/ticket_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ticket.dart';
import '../../models/user_profile.dart';
import 'new_ticket_screen.dart';
import 'ticket_admin_dashboard_screen.dart';
import 'ticket_detail_screen.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Avvik med synlig hub: KPI, hurtighandlinger og liste (ikke «gjemt» kontrollsenter).
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  TicketStatus? _filterStatus;
  bool _showDeleted = false;
  final _searchController = TextEditingController();

  List<Ticket> _tickets = const [];
  bool _isLoading = true;
  String? _error;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfileAndTickets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(Ticket t) {
    return CaseTrace.matchesQuery(
      query: _searchController.text,
      traceRef: t.displayTraceRef,
      id: t.id,
      title: t.title,
      ticketNumber: t.ticketNumber,
    ) ||
        t.description.toLowerCase().contains(_searchController.text.trim().toLowerCase()) ||
        (t.reporterName ?? '').toLowerCase().contains(_searchController.text.trim().toLowerCase()) ||
        (t.assigneeName ?? '').toLowerCase().contains(_searchController.text.trim().toLowerCase()) ||
        (t.category ?? '').toLowerCase().contains(_searchController.text.trim().toLowerCase());
  }

  Future<void> _loadProfileAndTickets() async {
    final p = await SupabaseService.fetchEffectiveUserProfile();
    if (mounted) setState(() => _profile = p);
    await _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile = _profile;
      if (profile == null) {
        throw StateError('Fant ikke brukerprofil.');
      }
      final scoped = _showDeleted && profile.isAdmin
          ? await SupabaseService.fetchScopedTicketsIncludingDeleted(profile: profile)
          : await SupabaseService.fetchScopedTickets(profile: profile);
      setState(() {
        _tickets = scoped;
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
    ).then((_) => _loadTickets());
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
    final coord = _profile?.role == UserRole.leder || _profile?.isAdmin == true;
    final ticketAdmin = _profile?.isAdmin == true;

    return PermissionGuard(
      profile: _profile,
      accessKey: AccessKeys.avvik,
      child: MobileShellScaffold(
        title: AppStrings.navTickets,
        hideMobileTitleBar: DriftProClient.isMobile,
        actions: [
          if ((coord || ticketAdmin) && !DriftProClient.isMobile)
            IconButton(
              icon: const Icon(Icons.dashboard_customize_outlined),
              tooltip: 'Kontrollsenter',
              onPressed: _openControlCenter,
            ),
        ],
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
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
            if (!DriftProClient.isMobile)
              SliverToBoxAdapter(
                child: _buildQuickActions(coord, isDark),
              ),
            if (!DriftProClient.isMobile)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText:
                          'Søk på avvik-ID (#123), tittel eller beskrivelse…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  DriftProClient.isMobile ? 'Mine / åpne avvik' : 'Filter',
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
                    if (_profile?.isAdmin == true && !DriftProClient.isMobile)
                      _chip(
                        'Slettet',
                        _showDeleted,
                        () {
                          setState(() => _showDeleted = !_showDeleted);
                          _loadTickets();
                        },
                      ),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                child: const DriftProLoadingCenter(),
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
    ),
    );
  }

  List<Widget> _buildTicketSlivers(
    TicketDashboardStats stats,
    bool isDark,
    bool coord,
  ) {
    final filtered = _tickets
        .where((t) => _showDeleted ? t.isDeleted : !t.isDeleted)
        .where((t) => _filterStatus == null || t.status == _filterStatus)
        .where(_matchesSearch)
        .toList();

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
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          100 + MobileLayout.shellBottomInset(context),
        ),
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
    if (DriftProClient.isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Meld og følg opp avvik', style: DriftProTheme.headingSm),
            const SizedBox(height: 4),
            Text(
              s.aapen > 0
                  ? '${s.aapen} åpne · trykk under for å melde nytt'
                  : 'Ingen åpne avvik — meld når noe skjer',
              style: DriftProTheme.bodySm,
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Avvikssenter', style: DriftProTheme.headingSm),
          const SizedBox(height: 4),
          Text(
            'Smart oversikt med status, alvorlighet og neste handling.',
            style: DriftProTheme.bodySm,
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 12),
          Text(
            'Bygg: ${BuildInfo.clientTag}',
            style: TextStyle(
              color: isDark ? Colors.white60 : Colors.grey[600],
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hubStat(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: DriftProTheme.primaryGreen, size: 16),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: DriftProTheme.primaryGreen,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[700],
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
    if (DriftProClient.isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _openNewTicket,
            style: FilledButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.add_alert_outlined),
            label: const Text(AppStrings.reportDeviation),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _openNewTicket,
              icon: const Icon(Icons.add),
              label: const Text('Nytt avvik'),
            ),
          ),
          if (coordinator) ...[
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openControlCenter,
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('Kontrollsenter'),
              ),
            ),
          ],
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
            _searchController.text.trim().isNotEmpty
                ? 'Ingen treff på søket'
                : 'Ingen avvik i denne filtervisningen',
            style: DriftProTheme.headingSm.copyWith(
              color: isDark ? Colors.white : Colors.grey[900],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            _searchController.text.trim().isNotEmpty
                ? 'Prøv avvik-ID (f.eks. #42), tittel eller beskrivelse.'
                : DriftProClient.isMobile
                    ? 'Bruk «Meld avvik» nede til høyre for å registrere.'
                    : s.total == 0
                        ? 'Start ved å melde en observasjon med tekst og bilder. Saken får automatisk avvik-ID og havner hos valgt leder.'
                        : 'Prøv et annet filter, eller opprett et nytt avvik.',
            style: DriftProTheme.bodyMd.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[700],
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          if (!DriftProClient.isMobile) ...[
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
        border: Border.all(color: sev == TicketSeverity.kritisk ? sc.withValues(alpha: 0.4) : Colors.grey.shade200),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: InkWell(
        onTap: () {
          try {
            Navigator.of(context)
                .push(
              MaterialPageRoute(
                builder: (_) => TicketDetailScreen(
                  ticket: t,
                  coordinatorProfile: _profile,
                ),
              ),
            )
                .then((_) {
              if (mounted) _loadTickets();
            });
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Kunne ikke åpne avvik: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 4,
                width: 80,
                decoration: BoxDecoration(
                  color: sc,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _badge(sev.label, sc),
                  const SizedBox(width: 8),
                  _statusBadge(stat.label, stc, _statIcon(stat)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: CaseTraceChip(
                        traceRef: t.displayTraceRef,
                        id: t.id,
                        compact: true,
                      ),
                    ),
                  ),
                ],
              ),
              if (t.isDeleted) ...[
                const SizedBox(height: 6),
                Text(
                  'Slettet — sporings-ID beholdes permanent',
                  style: DriftProTheme.caption.copyWith(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
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
