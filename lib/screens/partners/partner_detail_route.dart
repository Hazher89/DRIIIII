import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_paths.dart';
import '../../core/services/partner/partner_service.dart';
import 'partner_detail_screen.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// `/partners/bedrift/:partnerId` — delbar lenke til partnerdetalj.
class PartnerDetailRoute extends StatelessWidget {
  const PartnerDetailRoute({
    super.key,
    required this.partnerId,
    this.initialTab,
  });

  final String partnerId;
  final String? initialTab;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: PartnerService.fetchPartner(partnerId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: DriftProLoadingCenter());
        }
        final partner = snap.data;
        if (partner == null) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go(AppPaths.partners),
              ),
              title: const Text('Samarbeidspartner'),
            ),
            body: const Center(child: Text('Fant ikke samarbeidspartner.')),
          );
        }
        return PartnerDetailScreen(
          partner: partner,
          initialTab: initialTab,
        );
      },
    );
  }
}
