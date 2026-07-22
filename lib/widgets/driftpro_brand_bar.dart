import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/config/driftpro_client.dart';
import '../core/routing/app_paths.dart';
import '../core/theme/driftpro_theme_context.dart';
import 'driftpro_brand_logo.dart';

/// Kompakt merkevarelinje øverst på alle DriftPro-sider.
class DriftProBrandBar extends StatelessWidget {
  const DriftProBrandBar({super.key});

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;

    return Material(
      color: drift.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            DriftProClient.isMobile ? 12 : 16,
            DriftProClient.isMobile ? 4 : 4,
            DriftProClient.isMobile ? 12 : 16,
            DriftProClient.isMobile ? 6 : 6,
          ),
          decoration: BoxDecoration(
            color: drift.surface,
            border: Border(bottom: BorderSide(color: drift.borderSubtle)),
          ),
          child: Tooltip(
            message: 'Gå til dashboard',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.go(AppPaths.dashboard),
                borderRadius: BorderRadius.circular(10),
                mouseCursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: DriftProBrandLogo(
                    density: DriftProClient.isMobile
                        ? DriftProBrandDensity.compact
                        : DriftProBrandDensity.header,
                    showSubtitle: !DriftProClient.isMobile,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wrapper som legger merkevarelinjen over innholdet.
class DriftProBrandedScaffold extends StatelessWidget {
  const DriftProBrandedScaffold({
    super.key,
    required this.body,
    this.bottomNavigationBar,
    this.backgroundColor,
  });

  final Widget body;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final content = DriftProClient.isMobile
        ? MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: body,
          )
        : body;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          const DriftProBrandBar(),
          Expanded(child: content),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
