import 'dart:async';

import 'dart:async';

import '../../models/dashboard_stats.dart';
import '../../models/user_profile.dart';
import '../permissions/access_keys.dart';
import '../permissions/user_access.dart';
import 'chat/chat_unread_service.dart';
import 'chat/partner_chat_service.dart';
import 'hms/hms_service.dart';
import 'supabase_service.dart';

/// Badge-tall for bunnnavigasjon (MAVI / ansatte).
class NavBadgeCounts {
  const NavBadgeCounts({
    this.chat = 0,
    this.avvik = 0,
    this.fravaer = 0,
    this.hms = 0,
    this.more = 0,
  });

  final int chat;
  final int avvik;
  final int fravaer;
  final int hms;
  final int more;

  static const zero = NavBadgeCounts();

  int forAccess(String access) {
    switch (access) {
      case AccessKeys.partnersChat:
        return chat;
      case AccessKeys.avvik:
        return avvik;
      case AccessKeys.fravaer:
        return fravaer;
      case AccessKeys.hms:
        return hms;
      case AccessKeys.more:
        return more;
      default:
        return 0;
    }
  }
}

/// Partner-portal badge-tall.
class PartnerNavBadgeCounts {
  const PartnerNavBadgeCounts({
    this.chat = 0,
    this.routes = 0,
    this.documents = 0,
  });

  final int chat;
  final int routes;
  final int documents;

  static const zero = PartnerNavBadgeCounts();

  int forLabel(String label) {
    switch (label) {
      case 'Meldinger':
        return chat;
      case 'Ruter':
        return routes;
      case 'Dokumenter':
        return documents;
      default:
        return 0;
    }
  }
}

abstract final class NavBadgeService {
  static final _controller = StreamController<NavBadgeCounts>.broadcast();
  static NavBadgeCounts _last = NavBadgeCounts.zero;
  static Timer? _poll;
  static UserProfile? _profile;

  static Stream<NavBadgeCounts> get stream => _controller.stream;
  static NavBadgeCounts get last => _last;

  static void start(UserProfile profile) {
    _profile = profile;
    _poll?.cancel();
    unawaited(refresh());
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => unawaited(refresh()));
  }

  static void stop() {
    _poll?.cancel();
    _poll = null;
    _profile = null;
    _emit(NavBadgeCounts.zero);
  }

  static Future<void> refresh() async {
    final profile = _profile;
    if (profile == null) {
      _emit(NavBadgeCounts.zero);
      return;
    }
    try {
      final counts = await _fetch(profile);
      _emit(counts);
    } catch (_) {}
  }

  static void _emit(NavBadgeCounts counts) {
    if (counts.chat == _last.chat &&
        counts.avvik == _last.avvik &&
        counts.fravaer == _last.fravaer &&
        counts.hms == _last.hms &&
        counts.more == _last.more) {
      return;
    }
    _last = counts;
    if (!_controller.isClosed) _controller.add(counts);
  }

  static Future<NavBadgeCounts> _fetch(UserProfile profile) async {
    final access = profile.access;
    final companyId = profile.companyId;
    if (companyId == null || companyId.isEmpty) {
      return NavBadgeCounts(chat: ChatUnreadService.lastCount);
    }

    DashboardStats? stats;
    HmsDashboardStats? hmsStats;
    int pendingAbsence = 0;
    int myPendingAbsence = 0;
    int pendingUsers = 0;

    final futures = <Future<void>>[
      () async {
        try {
          final res = await SupabaseService.client.rpc<dynamic>(
            'get_dashboard_stats',
            params: {'p_company_id': companyId},
          );
          if (res is Map) {
            stats = DashboardStats.fromJson(Map<String, dynamic>.from(res));
          }
        } catch (_) {}
      }(),
      () async {
        if (!access.can(AccessKeys.fravaer)) return;
        try {
          final rows = await SupabaseService.client
              .from('absences')
              .select('id, user_id, status')
              .eq('company_id', companyId)
              .eq('status', 'ventende');
          final list = (rows as List).whereType<Map>();
          myPendingAbsence =
              list.where((r) => r['user_id'] == profile.id).length;
          if (access.canApproveLeave) {
            pendingAbsence = list
                .where((r) => r['user_id'] != profile.id)
                .length;
          }
        } catch (_) {}
      }(),
      () async {
        if (!profile.isSuperAdmin) return;
        try {
          final profiles = await SupabaseService.fetchProfiles(companyId: companyId);
          pendingUsers = profiles
              .where((u) => !u.isApproved && !u.isPartnerPortalUser)
              .length;
        } catch (_) {}
      }(),
      () async {
        if (!access.can(AccessKeys.hms)) return;
        try {
          hmsStats = await HmsService.loadDashboardStats(companyId);
        } catch (_) {}
      }(),
    ];

    int chat = ChatUnreadService.lastCount;
    if (access.canPartnersChat) {
      futures.add(() async {
        try {
          chat = await PartnerChatService.fetchTotalUnread();
        } catch (_) {}
      }());
    }

    await Future.wait(futures);

    final fravaer = access.canApproveLeave
        ? pendingAbsence
        : (access.can(AccessKeys.fravaer) ? myPendingAbsence : 0);

    final avvik = access.can(AccessKeys.avvik) ? (stats?.openTickets ?? 0) : 0;

    final hms = access.can(AccessKeys.hms) ? (hmsStats?.navBadgeTotal ?? 0) : 0;

    final more = pendingUsers +
        (access.can(AccessKeys.more) && (stats?.expiringDocuments ?? 0) > 0
            ? stats!.expiringDocuments
            : 0);

    return NavBadgeCounts(
      chat: chat,
      avvik: avvik,
      fravaer: fravaer,
      hms: hms,
      more: more,
    );
  }
}

abstract final class PartnerNavBadgeService {
  static final _controller = StreamController<PartnerNavBadgeCounts>.broadcast();
  static PartnerNavBadgeCounts _last = PartnerNavBadgeCounts.zero;
  static Timer? _poll;

  static Stream<PartnerNavBadgeCounts> get stream => _controller.stream;
  static PartnerNavBadgeCounts get last => _last;

  static void start({
    required String partnerId,
    String? partnerVehicleId,
    bool chatEnabled = true,
  }) {
    _poll?.cancel();
    _ctx = _PartnerCtx(partnerId: partnerId, vehicleId: partnerVehicleId, chat: chatEnabled);
    unawaited(refresh());
    _poll = Timer.periodic(const Duration(seconds: 50), (_) => unawaited(refresh()));
  }

  static void stop() {
    _poll?.cancel();
    _poll = null;
    _ctx = null;
    _emit(PartnerNavBadgeCounts.zero);
  }

  static _PartnerCtx? _ctx;

  static Future<void> refresh() async {
    final ctx = _ctx;
    if (ctx == null) {
      _emit(PartnerNavBadgeCounts.zero);
      return;
    }
    try {
      final counts = await _fetch(ctx);
      _emit(counts);
    } catch (_) {}
  }

  static void _emit(PartnerNavBadgeCounts counts) {
    if (counts.chat == _last.chat &&
        counts.routes == _last.routes &&
        counts.documents == _last.documents) {
      return;
    }
    _last = counts;
    if (!_controller.isClosed) _controller.add(counts);
  }

  static Future<PartnerNavBadgeCounts> _fetch(_PartnerCtx ctx) async {
    int chat = 0;
    int routes = 0;
    int documents = 0;

    final futures = <Future<void>>[
      () async {
        try {
          final list = await SupabaseService.client
              .from('partner_route_shares')
              .select('id, ack_status, notify_sent_at')
              .eq('partner_id', ctx.partnerId);
          for (final row in (list as List).whereType<Map>()) {
            final sent = row['notify_sent_at'];
            final ack = row['ack_status'] as String?;
            if (sent != null && ack == 'pending') routes++;
          }
        } catch (_) {}
      }(),
      () async {
        try {
          final docs = await SupabaseService.client
              .from('partner_documents')
              .select('id, created_at')
              .eq('partner_id', ctx.partnerId)
              .order('created_at', ascending: false)
              .limit(20);
          final weekAgo = DateTime.now().subtract(const Duration(days: 7));
          for (final row in (docs as List).whereType<Map>()) {
            final created = DateTime.tryParse('${row['created_at']}');
            if (created != null && created.isAfter(weekAgo)) documents++;
          }
        } catch (_) {}
      }(),
    ];

    if (ctx.chat) {
      futures.add(() async {
        try {
          chat = await PartnerChatService.fetchTotalUnread();
        } catch (_) {}
      }());
    }

    await Future.wait(futures);

    return PartnerNavBadgeCounts(
      chat: chat,
      routes: routes,
      documents: documents,
    );
  }
}

class _PartnerCtx {
  const _PartnerCtx({
    required this.partnerId,
    this.vehicleId,
    this.chat = true,
  });

  final String partnerId;
  final String? vehicleId;
  final bool chat;
}
