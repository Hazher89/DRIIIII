import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/supabase_service.dart';
import '../../core/services/ticket_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ticket.dart';
import '../../models/user_profile.dart';
import 'ticket_detail_screen.dart';

/// Kontrollsenter for ledere/admin: oversikt, KPI og hurtigliste.
class TicketAdminDashboardScreen extends StatefulWidget {
  const TicketAdminDashboardScreen({super.key});

  @override
  State<TicketAdminDashboardScreen> createState() =>
      _TicketAdminDashboardScreenState();
}

class _TicketAdminDashboardScreenState extends State<TicketAdminDashboardScreen> {
  List<Ticket> _tickets = const [];
  bool _loading = true;
  String? _error;
  UserProfile? _profile;
  TicketSeverity? _sevFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      _profile = profile;
      final companyId = profile?.companyId ??
          await SupabaseService.getCurrentCompanyId();
      if (companyId == null) {
        throw StateError('Ingen bedrift');
      }
      final list =
          await SupabaseService.fetchTickets(companyId: companyId);
      if (!mounted) return;
      setState(() {
        _tickets = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  List<Ticket> get _filtered {
    if (_sevFilter == null) return _tickets;
    return _tickets.where((t) => t.severity == _sevFilter).toList();
  }

  List<Ticket> get _attention {
    final list = _filtered.where((t) => t.isOpen).toList();
    list.sort((a, b) {
      final sa = a.severity == TicketSeverity.kritisk ? 0 : 1;
      final sb = b.severity == TicketSeverity.kritisk ? 0 : 1;
      if (sa != sb) return sa.compareTo(sb);
      final da = a.createdAt ?? DateTime(1970);
      final db = b.createdAt ?? DateTime(1970);
      return da.compareTo(db);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stats = TicketDashboardStats.fromTickets(_tickets);

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Avvik — kontrollsenter'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: DriftProTheme.primaryGreen,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        sliver: SliverToBoxAdapter(
                          child: _buildHeader(stats),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(
                          child: _buildKpiGrid(stats, isDark),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            children: [
                              Text(
                                'Krever oppmerksomhet',
                                style: DriftProTheme.headingSm.copyWith(
                                  color: isDark
                                      ? Colors.white
                                      : Colors.grey[900],
                                ),
                              ),
                              const Spacer(),
                              _chip(
                                'Alle alvor',
                                _sevFilter == null,
                                () => setState(() => _sevFilter = null),
                              ),
                              const SizedBox(width: 6),
                              _chip(
                                'Kritisk',
                                _sevFilter == TicketSeverity.kritisk,
                                () => setState(
                                  () => _sevFilter = TicketSeverity.kritisk,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_attention.isEmpty)
                        const SliverFillRemaining(
                          child: Center(child: Text('Ingen åpne avvik.')),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _attentionTile(
                              _attention[i],
                              isDark,
                            ),
                            childCount: _attention.length.clamp(0, 50),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 80)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader(TicketDashboardStats s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Oversikt',
          style: DriftProTheme.headingMd,
        ),
        const SizedBox(height: 6),
        Text(
          '${s.total} registrerte saker · ${s.medBilder} med dokumentasjon',
          style: DriftProTheme.bodySm.copyWith(color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildKpiGrid(TicketDashboardStats s, bool isDark) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cross = w > 520 ? 3 : 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpiCard(
              'Åpen',
              '${s.aapen}',
              Icons.flag_outlined,
              DriftProTheme.info,
              isDark,
              cross,
              w,
            ),
            _kpiCard(
              'Under behandling',
              '${s.underBehandling}',
              Icons.hourglass_top_rounded,
              DriftProTheme.warning,
              isDark,
              cross,
              w,
            ),
            _kpiCard(
              'Kritiske (åpne)',
              '${s.kritiskAapne}',
              Icons.warning_amber_rounded,
              DriftProTheme.severityCritical,
              isDark,
              cross,
              w,
            ),
            _kpiCard(
              'Forfalt frist',
              '${s.forfalt}',
              Icons.event_busy,
              Colors.deepOrange,
              isDark,
              cross,
              w,
            ),
            _kpiCard(
              'Tiltak utført',
              '${s.tiltakUtfort}',
              Icons.task_alt,
              DriftProTheme.success,
              isDark,
              cross,
              w,
            ),
            _kpiCard(
              'Lukket',
              '${s.lukket}',
              Icons.lock_outline,
              Colors.grey,
              isDark,
              cross,
              w,
            ),
          ],
        );
      },
    );
  }

  double _cardWidth(int cross, double maxW) =>
      (maxW - (cross - 1) * 12) / cross;

  Widget _kpiCard(
    String title,
    String value,
    IconData icon,
    Color color,
    bool isDark,
    int cross,
    double maxW,
  ) {
    final width = _cardWidth(cross, maxW);
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? DriftProTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
          ),
          boxShadow: DriftProTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const Spacer(),
                Text(
                  value,
                  style: DriftProTheme.headingMd.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: DriftProTheme.caption.copyWith(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? DriftProTheme.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sel ? DriftProTheme.primaryGreen : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: sel ? Colors.white : Colors.grey[700],
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _attentionTile(Ticket t, bool isDark) {
    final dateFmt = DateFormat('dd.MM.yyyy');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: t.severity == TicketSeverity.kritisk
              ? DriftProTheme.severityCritical.withValues(alpha: 0.35)
              : Colors.grey.shade200,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TicketDetailScreen(
                ticket: t,
                coordinatorProfile: _profile,
              ),
            ),
          ).then((_) => _load());
        },
        leading: CircleAvatar(
          backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
          child: Text(
            t.ticketNumber != null ? '#${t.ticketNumber}' : '?',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: DriftProTheme.primaryGreen,
            ),
          ),
        ),
        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${t.status.label} · ${t.severity.label}'
          '${t.dueDate != null ? ' · frist ${dateFmt.format(t.dueDate!)}' : ''}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
