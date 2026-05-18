import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import '../supabase_service.dart';
import 'absence_service.dart';

/// År-vindu: 5 år tilbake og 5 år frem (11 år totalt).
class VacationYearWindow {
  VacationYearWindow._();

  static const int yearsBack = 5;
  static const int yearsForward = 5;

  static int get currentYear => DateTime.now().year;

  static List<int> get years => List.generate(
        yearsBack + yearsForward + 1,
        (i) => currentYear - yearsBack + i,
      );

  static int get fromYear => currentYear - yearsBack;
  static int get toYear => currentYear + yearsForward;
}

class EmployeeVacationOverview {
  final UserProfile employee;
  final Map<int, AbsenceQuota> quotasByYear;

  const EmployeeVacationOverview({
    required this.employee,
    required this.quotasByYear,
  });

  AbsenceQuota? quotaFor(int year) => quotasByYear[year];

  int remainingFor(int year) => quotaFor(year)?.vacationDaysRemaining ?? 0;

  int carryoverEligibleFor(int year, int maxCarryover) {
    final q = quotaFor(year);
    if (q == null) return 0;
    return q.carryoverEligible(maxCarryover);
  }

  bool hasAllocationFor(int year) => quotaFor(year) != null;

  /// Estimert total neste år hvis [newAllocation] tildeles + overføring fra [year].
  int projectedNextYearTotal({
    required int year,
    required int newAllocation,
    required int maxCarryover,
  }) {
    final q = quotaFor(year);
    if (q == null) return newAllocation;
    return AbsenceService.projectedNextYearTotal(
      quota: q,
      newYearAllocation: newAllocation,
      maxCarryover: maxCarryover,
    );
  }
}

class VacationYearSummary {
  final int year;
  final int employeeCount;
  final int withAllocation;
  final int totalAllocated;
  final int totalUsed;
  final int totalRemaining;
  final int totalCarryoverEligible;

  const VacationYearSummary({
    required this.year,
    required this.employeeCount,
    required this.withAllocation,
    required this.totalAllocated,
    required this.totalUsed,
    required this.totalRemaining,
    required this.totalCarryoverEligible,
  });
}

enum VacationEmployeeFilter {
  all,
  hasRemaining,
  noAllocation,
  canCarryover,
}

class VacationAdminService {
  VacationAdminService._();

  static Future<List<EmployeeVacationOverview>> loadCompanyOverview({
    required String companyId,
    List<UserProfile>? employees,
  }) async {
    final staff = employees ??
        (await SupabaseService.fetchProfiles(companyId: companyId))
            .where((p) => !p.isPartnerPortalUser && p.isActive)
            .toList();

    final quotas = await SupabaseService.fetchAbsenceQuotasForCompanyRange(
      companyId: companyId,
      fromYear: VacationYearWindow.fromYear,
      toYear: VacationYearWindow.toYear,
    );

    final byUser = <String, Map<int, AbsenceQuota>>{};
    for (final q in quotas) {
      byUser.putIfAbsent(q.userId, () => {})[q.year] = q;
    }

    return staff
        .map(
          (e) => EmployeeVacationOverview(
            employee: e,
            quotasByYear: byUser[e.id] ?? {},
          ),
        )
        .toList()
      ..sort((a, b) => a.employee.fullName.compareTo(b.employee.fullName));
  }

  static VacationYearSummary summarizeYear({
    required List<EmployeeVacationOverview> overviews,
    required int year,
    required int maxCarryover,
  }) {
    var withAlloc = 0;
    var allocated = 0;
    var used = 0;
    var remaining = 0;
    var carryEligible = 0;

    for (final o in overviews) {
      final q = o.quotaFor(year);
      if (q == null) continue;
      withAlloc++;
      allocated += q.totalVacationDays;
      used += q.vacationDaysUsed;
      remaining += q.vacationDaysRemaining;
      carryEligible += o.carryoverEligibleFor(year, maxCarryover);
    }

    return VacationYearSummary(
      year: year,
      employeeCount: overviews.length,
      withAllocation: withAlloc,
      totalAllocated: allocated,
      totalUsed: used,
      totalRemaining: remaining,
      totalCarryoverEligible: carryEligible,
    );
  }

  static List<EmployeeVacationOverview> filterEmployees(
    List<EmployeeVacationOverview> list, {
    required VacationEmployeeFilter filter,
    required int year,
    required int maxCarryover,
    String search = '',
  }) {
    var result = list;
    if (search.trim().isNotEmpty) {
      final q = search.toLowerCase();
      result = result
          .where((o) => o.employee.fullName.toLowerCase().contains(q))
          .toList();
    }
    switch (filter) {
      case VacationEmployeeFilter.all:
        return result;
      case VacationEmployeeFilter.hasRemaining:
        return result.where((o) => o.remainingFor(year) > 0).toList();
      case VacationEmployeeFilter.noAllocation:
        return result.where((o) => !o.hasAllocationFor(year)).toList();
      case VacationEmployeeFilter.canCarryover:
        return result
            .where((o) => o.carryoverEligibleFor(year, maxCarryover) > 0)
            .toList();
    }
  }
}
