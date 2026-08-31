import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_paths.dart';
import '../../core/services/partner/partner_service.dart';
import '../../models/partner/partner.dart';
import 'partner_detail_screen.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// `/partners/bedrift/:partnerId` — delbar lenke til partnerdetalj.
class PartnerDetailRoute extends StatefulWidget {
  const PartnerDetailRoute({
    super.key,
    required this.partnerId,
    this.initialTab,
  });

  final String partnerId;
  final String? initialTab;

  @override
  State<PartnerDetailRoute> createState() => _PartnerDetailRouteState();
}

class _PartnerDetailRouteState extends State<PartnerDetailRoute> {
  late final Future<Partner?> _partnerFuture;
  bool _redirectedMissing = false;

  @override
  void initState() {
    super.initState();
    _partnerFuture = PartnerService.fetchPartner(widget.partnerId);
  }

  void _redirectToPartnersList() {
    if (_redirectedMissing || !mounted) return;
    _redirectedMissing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(AppPaths.partnersPath(tab: 'bedrifter'));
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Partner?>(
      future: _partnerFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const DriftProLoadingPage();
        }
        final partner = snap.data;
        if (partner == null) {
          _redirectToPartnersList();
          return const DriftProLoadingPage();
        }
        return PartnerDetailScreen(
          partner: partner,
          initialTab: widget.initialTab,
        );
      },
    );
  }
}
