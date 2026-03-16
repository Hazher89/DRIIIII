import 'package:flutter/material.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ticket.dart';
import 'new_ticket_screen.dart';
import 'ticket_detail_screen.dart';
import '../common/placeholder_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final tickets = await SupabaseService.fetchTickets();
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

  Color _sevColor(TicketSeverity s) {
    switch (s) {
      case TicketSeverity.lav: return DriftProTheme.severityLow;
      case TicketSeverity.middels: return DriftProTheme.severityMedium;
      case TicketSeverity.hoy: return DriftProTheme.severityHigh;
      case TicketSeverity.kritisk: return DriftProTheme.severityCritical;
    }
  }

  Color _statColor(TicketStatus s) {
    switch (s) {
      case TicketStatus.aapen: return DriftProTheme.info;
      case TicketStatus.underBehandling: return DriftProTheme.warning;
      case TicketStatus.tiltakUtfort: return DriftProTheme.success;
      case TicketStatus.lukket: return Colors.grey;
    }
  }

  IconData _statIcon(TicketStatus s) {
    switch (s) {
      case TicketStatus.aapen: return AppIcons.statusOpen;
      case TicketStatus.underBehandling: return AppIcons.statusInProgress;
      case TicketStatus.tiltakUtfort: return AppIcons.statusDone;
      case TicketStatus.lukket: return AppIcons.statusClosed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text(AppStrings.navTickets),
        actions: [
          IconButton(icon: const Icon(AppIcons.search), onPressed: () {}),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
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
        },
        icon: const Icon(AppIcons.add),
        label: const Text(AppStrings.reportDeviation),
      ),
      body: Column(
        children: [
          // Filter chips
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _chip('Alle', _filterStatus == null, () {
                  setState(() => _filterStatus = null);
                }),
                ...TicketStatus.values.map((s) => _chip(
                  s.label, _filterStatus == s,
                  () => setState(() => _filterStatus = s),
                )),
              ],
            ),
          ),
          // Ticket list
          Expanded(
            child: _buildTicketBody(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketBody(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: DriftProTheme.bodyMd,
          textAlign: TextAlign.center,
        ),
      );
    }

    final filtered = _filterStatus == null
        ? _tickets
        : _tickets.where((t) => t.status == _filterStatus).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'Ingen avvik funnet.',
          style: DriftProTheme.bodyMd.copyWith(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTickets,
      color: DriftProTheme.primaryGreen,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        itemCount: filtered.length,
        itemBuilder: (ctx, i) => _ticketCard(filtered[i], isDark),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? DriftProTheme.primaryGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(DriftProTheme.radiusRound),
            border: Border.all(
              color: selected ? DriftProTheme.primaryGreen : Colors.grey.shade300,
            ),
          ),
          child: Text(label, style: DriftProTheme.labelSm.copyWith(
            color: selected ? Colors.white : Colors.grey[600], fontSize: 12,
          )),
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(
          color: sev == TicketSeverity.kritisk
              ? sc.withOpacity(0.3)
              : isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
        ),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TicketDetailScreen(ticket: t),
            ),
          ).then((_) => _loadTickets());
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
                        fontWeight: FontWeight.w700,
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
                    style:
                        DriftProTheme.caption.copyWith(fontSize: 11),
                  ),
                  const SizedBox(width: 12),
                  Icon(AppIcons.category, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(
                    t.category ?? 'Uspesifisert',
                    style:
                        DriftProTheme.caption.copyWith(fontSize: 11),
                  ),
                  const Spacer(),
                  if (t.createdAt != null)
                    Text(
                      t.createdAt!.toLocal().toIso8601String().split('T').first,
                      style:
                          DriftProTheme.caption.copyWith(fontSize: 10),
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
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusRound),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(
          color: color, shape: BoxShape.circle,
        )),
        const SizedBox(width: 6),
        Text(label, style: DriftProTheme.labelSm.copyWith(color: color, fontSize: 10)),
      ]),
    );
  }

  Widget _statusBadge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusRound),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: DriftProTheme.labelSm.copyWith(color: color, fontSize: 10)),
      ]),
    );
  }
}
