import 'dart:async';

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
    // 2 min — Realtime/chat dekker det meste; full badge-poll er dyr på free-kvote.
    _poll = Timer.periodic(const Duration(seconds: 120), (_) => unawaited(refresh()));
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

    int pendingAbsence = 0;
    int myPendingAbsence = 0;
    int pendingUsers = 0;
    int avvik = 0;
    int hms = 0;

    final futures = <Future<void>>[
      () async {
        if (!access.can(AccessKeys.avvik)) return;
        try {
          // COUNT only — ikke last alle avvik-rader hvert poll.
          avvik = await SupabaseService.client
              .from('tickets')
              .count()
              .eq('company_id', companyId)
              .inFilter('status', const ['aapen', 'under_behandling'])
              .isFilter('deleted_at', null);
        } catch (_) {}
      }(),
      () async {
        if (!access.can(AccessKeys.fravaer)) return;
        try {
          if (access.canApproveLeave) {
            pendingAbsence = await SupabaseService.client
                .from('absences')
                .count()
                .eq('company_id', companyId)
                .eq('status', 'ventende')
                .neq('user_id', profile.id);
          } else {
            myPendingAbsence = await SupabaseService.client
                .from('absences')
                .count()
                .eq('company_id', companyId)
                .eq('status', 'ventende')
                .eq('user_id', profile.id);
          }
        } catch (_) {}
      }(),
      () async {
        if (!profile.isSuperAdmin) return;
        try {
          pendingUsers = await SupabaseService.client
              .from('profiles')
              .count()
              .eq('company_id', companyId)
              .eq('is_approved', false)
              .isFilter('partner_id', null);
        } catch (_) {}
      }(),
      () async {
        if (!access.can(AccessKeys.hms)) return;
        try {
          hms = await HmsService.loadNavBadgeTotal(profile);
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

    return NavBadgeCounts(
      chat: chat,
      avvik: avvik,
      fravaer: fravaer,
      hms: hms,
      more: pendingUsers,
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
    _poll = Timer.periodic(const Duration(seconds: 120), (_) => unawaited(refresh()));
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
          routes = await SupabaseService.client
              .from('partner_route_shares')
              .count()
              .eq('partner_id', ctx.partnerId)
              .eq('ack_status', 'pending')
              .not('notify_sent_at', 'is', null);
        } catch (_) {}
      }(),
      () async {
        try {
          final weekAgo =
              DateTime.now().toUtc().subtract(const Duration(days: 7));
          documents = await SupabaseService.client
              .from('partner_documents')
              .count()
              .eq('partner_id', ctx.partnerId)
              .gte('created_at', weekAgo.toIso8601String());
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
