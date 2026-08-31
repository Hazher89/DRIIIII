import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/user_profile.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/partner_ui.dart';
import 'owner_portal_deductions_page.dart';
import 'owner_portal_inspections_page.dart';
import 'owner_portal_meetings_page.dart';
import 'owner_portal_staff_page.dart';
import 'owner_portal_summary_page.dart';
import 'owner_portal_timesheet_page.dart';
import 'owner_portal_vehicle_rental_page.dart';

/// Ryddig hub for sekundære eier-funksjoner (holder bunnmeny enkel).
/// Chat ligger i portaldock når den er på (styrt live av superadmin).
class OwnerPortalMorePage extends StatelessWidget {
  const OwnerPortalMorePage({
    super.key,
    required this.partner,
    required this.profile,
    this.workforceEnabled = false,
  });

  final Partner partner;
  final UserProfile profile;
  final bool workforceEnabled;

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  List<_MoreItem> _items() => [
        _MoreItem(
          icon: Icons.summarize_outlined,
          title: 'Oppsummering',
          subtitle: 'Økonomi, arkiv og total per måned',
          page: OwnerPortalSummaryPage(partner: partner),
        ),
        _MoreItem(
          icon: Icons.gavel_rounded,
          title: 'Trekk',
          subtitle: 'Saker, begrunnelse og bevis',
          page: OwnerPortalDeductionsPage(partner: partner),
        ),
        _MoreItem(
          icon: Icons.car_rental_outlined,
          title: 'Utleie',
          subtitle: 'Lån og utlån av kjøretøy',
          page: OwnerPortalVehicleRentalPage(partner: partner),
        ),
        _MoreItem(
          icon: Icons.event_note_outlined,
          title: 'Møter & revisjon',
          subtitle: 'Kommende og tidligere møter',
          page: OwnerPortalMeetingsPage(partner: partner),
        ),
        _MoreItem(
          icon: Icons.fact_check_outlined,
          title: 'Bilkontroll',
          subtitle: 'Kontroller og status',
          page: OwnerPortalInspectionsPage(partner: partner),
        ),
        if (workforceEnabled) ...[
          _MoreItem(
            icon: Icons.groups_outlined,
            title: 'Ansatte',
            subtitle: 'Registrer ansatte og lag innlogging',
            page: OwnerPortalStaffPage(partner: partner),
          ),
          _MoreItem(
            icon: Icons.schedule_outlined,
            title: 'Timeliste & timerbank',
            subtitle: 'Full oversikt, på jobb nå, Excel og logg',
            page: OwnerPortalTimesheetPage(partner: partner),
          ),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final muted = PartnerUi.mutedText(context);
    final items = _items();

    return PartnerPortalPageShell(
      title: 'Mer',
      body: RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: CircleAvatar(
                    backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                    child: Icon(item.icon, color: DriftProTheme.primaryGreen),
                  ),
                  title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(item.subtitle, style: TextStyle(fontSize: 12, color: muted)),
                  trailing: Icon(Icons.chevron_right, color: muted),
                  onTap: () => _open(context, item.page),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.page,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget page;
}
