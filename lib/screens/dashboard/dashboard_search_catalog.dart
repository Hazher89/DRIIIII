import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_icons.dart';
import '../../core/routing/app_paths.dart';
import '../../core/permissions/access_keys.dart';
import '../../core/permissions/permission_gate.dart';
import '../../core/permissions/user_access.dart';
import '../../models/absence.dart';
import '../../models/ticket.dart';
import '../../models/user_profile.dart';
import '../admin/access_control_screen.dart';
import '../admin/kiosk_settings_screen.dart';
import '../departments/departments_screen.dart';
import '../employees/employee_hub_screen.dart';
import '../employees/employee_personal_folder_screen.dart';
import '../employees/employees_screen.dart';
import '../more/help_support_screen.dart';
import '../more/organization_chart_screen.dart';
import '../more/privacy_screen.dart';
import '../more/whistleblowing_screen.dart';
import '../online/online_presence_screen.dart';
import '../profile/notifications_hub_screen.dart';
import '../profile/profile_screen.dart';
enum DashboardSearchKind { module, action, liveData }

class DashboardSearchItem {
  final String id;
  final String title;
  final String subtitle;
  final List<String> keywords;
  final IconData icon;
  final String category;
  final String accessKey;
  final DashboardSearchKind kind;
  final void Function(BuildContext context, NavigateByAccess? go) navigate;

  const DashboardSearchItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.keywords,
    required this.icon,
    required this.category,
    required this.accessKey,
    required this.kind,
    required this.navigate,
  });

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      title,
      subtitle,
      category,
      ...keywords,
    ].join(' ').toLowerCase();
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }
}

/// Kun moduler og funksjoner brukeren faktisk har tilgang til.
class DashboardSearchCatalog {
  DashboardSearchCatalog._();

  static List<DashboardSearchItem> modulesAndActions({
    required UserProfile profile,
    required UserAccess access,
  }) {
    final items = <DashboardSearchItem>[];
    void add(DashboardSearchItem item) {
      if (!access.can(item.accessKey)) return;
      items.add(item);
    }

    void shell(
      String id,
      String title,
      String subtitle,
      IconData icon,
      String accessKey,
      List<String> keywords,
    ) {
      add(DashboardSearchItem(
        id: id,
        title: title,
        subtitle: subtitle,
        keywords: keywords,
        icon: icon,
        category: 'Hovedmoduler',
        accessKey: accessKey,
        kind: DashboardSearchKind.module,
        navigate: (_, go) => go?.call(accessKey),
      ));
    }

    shell('dash', 'Dashboard', 'Oversikt og snarveier', AppIcons.dashboard,
        AccessKeys.dashboard, ['forside', 'hjem', 'start']);
    shell('surveys', 'Undersøkelser', 'Svar og deltak', AppIcons.survey,
        AccessKeys.surveys, ['spørreundersøkelse', 'skjema']);
    shell('fravaer', 'Fravær & ferie', 'Søk ferie og fravær', AppIcons.absence,
        AccessKeys.fravaer, ['ferie', 'syk', 'egenmelding', 'permisjon']);
    shell('avvik', 'Avvik', 'Melde og følge opp avvik', AppIcons.ticket,
        AccessKeys.avvik, ['hendelse', 'rapport', 'ticket']);
    shell('hms', 'HMS', 'Helse, miljø og sikkerhet', AppIcons.hms,
        AccessKeys.hms, ['sikkerhet', 'risiko', 'sja']);
    shell('partners', 'Samarbeidspartnere', 'Partnere og ruter', Icons.handshake_outlined,
        AccessKeys.partners, ['partner', 'rute', 'logistikk', 'bot', 'trekk', 'bøtel']);
    add(DashboardSearchItem(
      id: 'partners_bot_trekk',
      title: 'Bot/Trekk',
      subtitle: 'Registrer trekk og bevis mot partnere',
      keywords: ['bot', 'trekk', 'bøtel', 'trekk', 'partner'],
      icon: Icons.gavel_rounded,
      category: 'Samarbeidspartnere',
      accessKey: AccessKeys.partners,
      kind: DashboardSearchKind.module,
      navigate: (ctx, _) => ctx.go(AppPaths.partnersPath(tab: 'bot-trekk')),
    ));
    shell('more', 'Mer', 'Innstillinger og administrasjon', AppIcons.more,
        AccessKeys.more, ['meny', 'innstillinger']);

    void push(
      String id,
      String title,
      String subtitle,
      IconData icon,
      String accessKey,
      List<String> keywords,
      String category,
      Widget Function() screen,
    ) {
      add(DashboardSearchItem(
        id: id,
        title: title,
        subtitle: subtitle,
        keywords: keywords,
        icon: icon,
        category: category,
        accessKey: accessKey,
        kind: DashboardSearchKind.module,
        navigate: (ctx, _) {
          Navigator.of(ctx).push(
            guardedMaterialRoute(
              profile: profile,
              accessKey: accessKey,
              child: screen(),
            ),
          );
        },
      ));
    }

    push('avdelinger', 'Avdelinger', 'Struktur og ledere', AppIcons.department,
        AccessKeys.avdelinger, ['avdeling', 'team', 'organisasjon'], 'Administrasjon',
        () => const DepartmentsScreen());
    push('ansatte', 'Ansatte', 'Brukere og tilganger', AppIcons.employees,
        AccessKeys.ansatte, ['personal', 'brukere'], 'Administrasjon',
        () => const EmployeesScreen());
    push('orgkart', 'Organisasjonskart', 'Vis hierarki', Icons.account_tree_outlined,
        AccessKeys.ansatte, ['organisasjon', 'struktur'], 'Administrasjon',
        () => const OrganizationChartScreen());
    push('personalmappe', 'Personalmappe', 'Dokumenter og filer', AppIcons.folder,
        AccessKeys.personalmappe, ['dms', 'dokument', 'mappe'], 'Dokumenter',
        () => const EmployeePersonalFolderScreen());
    push('varsler', 'Varsler', 'Innboks og hendelser', AppIcons.notification,
        AccessKeys.varsler, ['varsel', 'melding'], 'Konto',
        () => const NotificationsHubScreen());
    push('profil', 'Min profil', 'Konto og personopplysninger', AppIcons.profile,
        AccessKeys.profil, ['meg', 'konto', 'bruker'], 'Konto',
        () => const ProfileScreen());
    push('tilgang', 'Tilgangskontroll', 'Roller og rettigheter',
        Icons.lock_person_outlined, AccessKeys.tilgangskontroll,
        ['tilgang', 'rolle', 'rettighet'], 'Administrasjon',
        () => const AccessControlScreen());
    push('godkjenning', 'Brukergodkjenning', 'Godkjenn nye ansatte',
        Icons.how_to_reg_outlined, AccessKeys.brukergodkjenning,
        ['ny bruker', 'venter'], 'Administrasjon',
        () => const EmployeeHubScreen());
    push('kiosk', 'Infoskjerm', 'Oppsett for felles skjerm',
        Icons.display_settings_outlined, AccessKeys.kiosk,
        ['skjerm', 'wallboard'], 'Administrasjon',
        () => const KioskSettingsScreen());
    push('whistle', 'Anonym anmeldelse', 'Varsle uønsket atferd',
        Icons.record_voice_over_outlined, AccessKeys.whistleblowing,
        ['varsling', 'anonym'], 'HMS',
        () => const WhistleblowingScreen());
    push('hjelp', 'Hjelp & støtte', 'Kontakt og veiledning',
        Icons.help_outline_rounded, AccessKeys.more,
        ['support', 'hjelp'], 'Konto',
        () => const HelpSupportScreen());
    push('personvern', 'Personvern', 'GDPR og databehandling',
        Icons.privacy_tip_outlined, AccessKeys.more,
        ['gdpr', 'privacy'], 'Konto',
        () => const PrivacyScreen());

    if (access.canFravaer) {
      add(DashboardSearchItem(
        id: 'fravaer_ny',
        title: 'Ny fraværsregistrering',
        subtitle: 'Registrer ferie eller fravær',
        keywords: ['ny', 'søknad', 'ferie', 'fravær'],
        icon: Icons.event_available_outlined,
        category: 'Handlinger',
        accessKey: AccessKeys.fravaer,
        kind: DashboardSearchKind.action,
        navigate: (_, go) => go?.call(AccessKeys.fravaer),
      ));
    }
    if (access.canApproveLeave) {
      add(DashboardSearchItem(
        id: 'fravaer_godkjenn',
        title: 'Godkjenn fravær',
        subtitle: 'Ventende søknader i teamet',
        keywords: ['godkjenne', 'venter', 'leder'],
        icon: Icons.fact_check_outlined,
        category: 'Handlinger',
        accessKey: AccessKeys.fravaerGodkjenn,
        kind: DashboardSearchKind.action,
        navigate: (_, go) => go?.call(AccessKeys.fravaer),
      ));
    }
    if (access.canVacationAdmin) {
      add(DashboardSearchItem(
        id: 'ferie_admin',
        title: 'Ferieadministrasjon',
        subtitle: 'Del ut feriedager',
        keywords: ['ferie', 'kvote', 'admin'],
        icon: Icons.beach_access_outlined,
        category: 'Handlinger',
        accessKey: AccessKeys.ferieAdmin,
        kind: DashboardSearchKind.action,
        navigate: (_, go) => go?.call(AccessKeys.fravaer),
      ));
    }
    if (access.canAvvik) {
      add(DashboardSearchItem(
        id: 'avvik_ny',
        title: 'Meld nytt avvik',
        subtitle: 'Opprett avvikssak',
        keywords: ['ny', 'melde', 'hendelse'],
        icon: AppIcons.newTicket,
        category: 'Handlinger',
        accessKey: AccessKeys.avvik,
        kind: DashboardSearchKind.action,
        navigate: (_, go) => go?.call(AccessKeys.avvik),
      ));
    }

    final hmsActions = <(String, String, String, IconData, String, List<String>)>[
      ('hms_risiko', 'Risikovurdering', 'ROS og tiltak', AppIcons.riskAssessment,
          AccessKeys.hmsRisikovurdering, ['ros', 'risiko']),
      ('hms_sja', 'SJA', 'Sikker jobbanalyse', AppIcons.sja, AccessKeys.hmsSja, ['jobbanalyse']),
      ('hms_runde', 'Sikkerhetsrunder', 'Planlagte runder', AppIcons.safetyRound,
          AccessKeys.hmsSikkerhetsrunde, ['vernerunde']),
      ('hms_matrise', 'Risikomatrise', 'Matrise og nivåer', AppIcons.riskMatrix,
          AccessKeys.hmsRisikomatrise, ['matrise']),
      ('hms_utstyr', 'Maskiner & utstyr', 'Utstyrsoversikt', Icons.precision_manufacturing_outlined,
          AccessKeys.hmsUtstyr, ['maskin', 'utstyr']),
      ('hms_kompetanse', 'Kompetanse', 'Kurs og sertifikater', Icons.school_outlined,
          AccessKeys.hmsKompetanse, ['kurs']),
      ('hms_opplaering', 'Opplæring', 'Hub Driftsrutiner SOP', Icons.menu_book_rounded,
          AccessKeys.hms, ['sop', 'hubanero', 'opplæring', 'driftsrutiner']),
      ('hms_dok', 'HMS-dokumenter', 'Dokumentbibliotek', AppIcons.document,
          AccessKeys.hmsDokumenter, ['dokument']),
    ];
    for (final h in hmsActions) {
      if (!access.can(h.$5)) continue;
      add(DashboardSearchItem(
        id: h.$1,
        title: h.$2,
        subtitle: h.$3,
        keywords: h.$6,
        icon: h.$4,
        category: 'HMS',
        accessKey: h.$5,
        kind: DashboardSearchKind.module,
        navigate: (ctx, go) {
          if (h.$1 == 'hms_opplaering') {
            ctx.push(AppPaths.hmsOpplaering);
            return;
          }
          go?.call(AccessKeys.hms);
        },
      ));
    }

    if (access.canFravaer || access.canEmployeesList) {
      add(DashboardSearchItem(
        id: 'online',
        title: 'Hvem er på jobb',
        subtitle: 'Live oversikt og tilstedeværelse',
        keywords: ['på jobb', 'innstemplt', 'nærvær', 'online'],
        icon: Icons.apartment_rounded,
        category: 'Oversikt',
        accessKey: access.canFravaer ? AccessKeys.fravaer : AccessKeys.ansatte,
        kind: DashboardSearchKind.module,
        navigate: (ctx, _) {
          Navigator.of(ctx).push(
            MaterialPageRoute(builder: (_) => const OnlinePresenceScreen()),
          );
        },
      ));
    }

    return items;
  }

  static List<DashboardSearchItem> liveDataHits({
    required String query,
    required UserAccess access,
    required UserProfile profile,
    required List<Ticket> tickets,
    required List<Absence> absences,
    required NavigateByAccess? go,
  }) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];

    final hits = <DashboardSearchItem>[];

    if (access.canAvvik) {
      final digits = q.replaceAll('#', '');
      final numberQuery = int.tryParse(digits);
      for (final t in tickets.take(40)) {
        final title = t.title.toLowerCase();
        final matchesNumber = numberQuery != null &&
            t.ticketNumber != null &&
            t.ticketNumber == numberQuery;
        final matchesTitle = title.contains(q);
        if (!matchesNumber && !matchesTitle) continue;
        final idLabel =
            t.ticketNumber != null ? 'Avvik #${t.ticketNumber}' : t.title;
        hits.add(DashboardSearchItem(
          id: 'ticket_${t.id}',
          title: idLabel,
          subtitle: '${t.title} · ${t.severity.label} · ${t.status.label}',
          keywords: t.ticketNumber != null ? ['#${t.ticketNumber}'] : const [],
          icon: AppIcons.ticket,
          category: 'Dine data · avvik',
          accessKey: AccessKeys.avvik,
          kind: DashboardSearchKind.liveData,
          navigate: (_, g) => g?.call(AccessKeys.avvik),
        ));
      }
    }

    if (access.canFravaer) {
      for (final a in absences.take(30)) {
        final who = (a.userName ?? '').toLowerCase();
        final type = a.type.label.toLowerCase();
        if (!who.contains(q) && !type.contains(q)) continue;
        hits.add(DashboardSearchItem(
          id: 'absence_${a.id}',
          title: '${a.type.label}${a.userName != null ? ' · ${a.userName}' : ''}',
          subtitle: a.status.label,
          keywords: const [],
          icon: AppIcons.absence,
          category: 'Dine data · fravær',
          accessKey: AccessKeys.fravaer,
          kind: DashboardSearchKind.liveData,
          navigate: (_, g) => g?.call(AccessKeys.fravaer),
        ));
      }
    }

    return hits.take(8).toList();
  }

  static List<DashboardSearchItem> search({
    required UserProfile profile,
    required UserAccess access,
    required String query,
    List<Ticket> tickets = const [],
    List<Absence> absences = const [],
    NavigateByAccess? go,
  }) {
    final base = modulesAndActions(profile: profile, access: access);
    final staticHits = base.where((i) => i.matches(query)).toList();
    final live = liveDataHits(
      query: query,
      access: access,
      profile: profile,
      tickets: tickets,
      absences: absences,
      go: go,
    );
    return [...staticHits, ...live];
  }
}
