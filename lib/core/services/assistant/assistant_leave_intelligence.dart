import 'package:intl/intl.dart';

import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import '../../constants/leave_rules.dart';
import '../absence/employee_leave_stats.dart';
import '../supabase_service.dart';
import 'assistant_access_policy.dart';
import 'assistant_corpus.dart';
import 'assistant_memory_service.dart';

/// Live fravær/ferie-svar med streng GDPR-sjekk.
class AssistantLeaveIntelligence {
  AssistantLeaveIntelligence._();

  static bool looksLikeLeaveQuery(String query) {
    final q = query.toLowerCase();
    return q.contains('ferie') ||
        q.contains('fravær') ||
        q.contains('fravaer') ||
        q.contains('egenmelding') ||
        q.contains('sykt barn') ||
        q.contains('sykmelding') ||
        q.contains('permisjon') ||
        q.contains('saldo') ||
        q.contains('kvote') ||
        (q.contains('dager') &&
            (q.contains('igjen') || q.contains('brukt') || q.contains('hatt')));
  }

  static Future<String?> tryAnswer(String query) async {
    if (!looksLikeLeaveQuery(query)) return null;

    final viewer = await SupabaseService.fetchCurrentUserProfile();
    if (viewer == null || viewer.companyId == null) {
      return 'Du må være innlogget for at jeg skal kunne svare på fravær.';
    }

    final companyId = viewer.companyId!;
    final year = DateTime.now().year;
    final selfAsk = _asksAboutSelf(query);

    UserProfile? subject;
    if (selfAsk) {
      subject = viewer;
    } else {
      subject = await _resolveEmployee(query, companyId);
      if (subject == null) {
        // Leave-ish but no name — maybe general rules; let FAQ handle.
        if (_hasPersonHint(query)) {
          return 'Jeg fant ingen ansatt som matcher navnet i spørsmålet. '
              'Prøv fullt navn, f.eks. «Hvor mye ferie har Kari Nordmann igjen?»';
        }
        return null;
      }
    }

    final access = await AssistantAccessPolicy.canViewEmployeeLeave(
      viewer: viewer,
      subject: subject,
    );
    if (!access.allowed) {
      return access.reason ??
          AssistantAccessDecision.denyOutOfDepartment.reason;
    }

    final absences = await SupabaseService.fetchAbsences(
      companyId: companyId,
      userId: subject.id,
    );
    final quota = await SupabaseService.fetchAbsenceQuota(
      userId: subject.id,
      year: year,
    );
    final company = await _companySettings(companyId);

    final stats = EmployeeLeaveSnapshot.compute(
      employee: subject,
      employeeAbsences: absences,
      quota: quota,
      company: company,
      referenceDate: DateTime.now(),
    );

    final pending = absences
        .where((a) => a.status == AbsenceStatus.ventende)
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final recent = [...absences]
      ..sort((a, b) => b.startDate.compareTo(a.startDate));

    final who = selfAsk ? 'Du' : subject.fullName;
    final df = DateFormat('dd.MM.yyyy');
    final buf = StringBuffer();

    buf.writeln(
      '$who — fraværsoversikt $year'
      '${subject.employeeNumber != null ? ' (nr ${subject.employeeNumber})' : ''}:',
    );
    buf.writeln();
    buf.writeln(
      '• Ferie: ${stats.ferieRemaining} dager igjen '
      '(${stats.ferieUsed} brukt av ${stats.ferieTotal})',
    );
    buf.writeln(
      '• Egenmelding: ${stats.egenDaysTotal} d / ${stats.egenTilfeller} tilfeller '
      '(maks ${stats.egenMax} d · ${stats.egenTilfellerMax} tilf. i perioden '
      '${stats.periodUsage.window.formatRange()})',
    );
    buf.writeln(
      '• Sykt barn: ${stats.syktDays} av ${stats.syktMax} dager '
      '(${stats.periodUsage.window.basisLabel})',
    );
    buf.writeln(
      '• Fravær YTD: ${stats.absenceRatePercent().round()}% av virkedager · '
      'totalt ${stats.totalFravaerDager} fraværsdager',
    );

    if (pending.isNotEmpty) {
      buf.writeln();
      buf.writeln('Ventende søknader (${pending.length}):');
      for (final a in pending.take(5)) {
        buf.writeln(
          '• ${a.type.label}: ${df.format(a.startDate)}–${df.format(a.endDate)}',
        );
      }
    }

    if (recent.isNotEmpty) {
      buf.writeln();
      buf.writeln('Siste registreringer:');
      for (final a in recent.take(5)) {
        buf.writeln(
          '• ${a.type.label} · ${df.format(a.startDate)}–${df.format(a.endDate)} · ${a.status.label}',
        );
      }
    }

    if (subject.hireDate == null) {
      buf.writeln();
      buf.writeln(
        'Merk: ansettelsesdato mangler — egenmelding/sykt barn bruker kalenderår.',
      );
    }

    final answer = buf.toString().trim();
    await AssistantMemoryService.remember(
      companyId: companyId,
      kind: 'leave_fact',
      content: answer,
      subjectKey: 'user:${subject.id}',
      subjectUserId: subject.id,
      visibility: selfAsk
          ? 'self'
          : (await AssistantAccessPolicy.tierFor(viewer)) ==
                  AssistantAccessTier.principal
              ? 'principals'
              : 'department:${subject.departmentId ?? 'unknown'}',
      sourceQuery: query,
    );
    return answer;
  }

  static bool _asksAboutSelf(String query) {
    final q = query.toLowerCase();
    return q.contains('jeg') ||
        q.contains('meg') ||
        q.contains('min ') ||
        q.contains('mitt ') ||
        q.contains('mine ') ||
        q.contains('har jeg') ||
        q.contains('egne');
  }

  static bool _hasPersonHint(String query) {
    final q = query.toLowerCase();
    return q.contains(' for ') ||
        q.contains(' til ') ||
        q.contains('om ') ||
        RegExp(r'\b[A-ZÆØÅ][a-zæøå]+\b').hasMatch(query);
  }

  static Future<UserProfile?> _resolveEmployee(
    String query,
    String companyId,
  ) async {
    final profiles = await SupabaseService.fetchMaviEmployees(
      companyId: companyId,
      requireActive: false,
      requireApproved: false,
    );
    if (profiles.isEmpty) return null;

    final q = query.toLowerCase();
    // Prefer longer name matches.
    UserProfile? best;
    var bestScore = 0;
    for (final p in profiles) {
      final name = p.fullName.trim().toLowerCase();
      if (name.length < 2) continue;
      var score = 0;
      if (q.contains(name)) {
        score = name.length + 20;
      } else {
        final parts = name.split(RegExp(r'\s+')).where((s) => s.length >= 3);
        var hits = 0;
        for (final part in parts) {
          if (q.contains(part)) hits++;
        }
        if (hits >= 2) {
          score = hits * 8 + name.length;
        } else if (hits == 1 && parts.length == 1) {
          score = 6;
        }
      }
      final en = p.employeeNumber?.trim();
      if (en != null &&
          en.isNotEmpty &&
          (q.contains('nr $en') ||
              q.contains('#$en') ||
              RegExp('\\b$en\\b').hasMatch(q))) {
        score += 40;
      }
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }
    if (bestScore < 6) return null;
    return best;
  }

  static Future<CompanyLeaveSettings> _companySettings(String companyId) async {
    try {
      return await SupabaseService.fetchCompanyLeaveSettings(companyId);
    } catch (_) {
      return const CompanyLeaveSettings();
    }
  }

  static List<KnowledgeChunk> faqHints() => const [
        KnowledgeChunk(
          id: 'faq:leave-live-gdpr',
          source: KnowledgeSourceKind.help,
          title: 'Spør om ferie og fravær (med personvern)',
          body:
              'Du kan spørre:\n'
              '• «Hvor mye ferie har jeg igjen?»\n'
              '• «Hvor mange egenmeldingsdager har Kari?»\n'
              '• «Vis fravær for ansatt nr 113»\n\n'
              'GDPR: Avdelingsledere ser kun ansatte i egen avdeling. '
              'Tommy, Nico og Hazher kan spørre om alle. '
              'Andre ansatte ser kun egne tall.',
          routePath: '/fravaer',
          tags: [
            'ferie',
            'fravær',
            'egenmelding',
            'gdpr',
            'avdelingsleder',
            'saldo',
          ],
        ),
      ];
}
