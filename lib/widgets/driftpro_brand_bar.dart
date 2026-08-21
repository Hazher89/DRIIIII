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
    final isMobile = DriftProClient.isMobile;

    return Material(
      color: drift.surface,
      clipBehavior: Clip.none,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            isMobile ? 12 : 14,
            isMobile ? 4 : 4,
            isMobile ? 12 : 14,
            isMobile ? 4 : 4,
          ),
          decoration: BoxDecoration(
            color: drift.surface,
            border: Border(bottom: BorderSide(color: drift.borderSubtle)),
          ),
          child: Tooltip(
            message: 'Gå til dashboard',
            child: Material(
              color: Colors.transparent,
              clipBehavior: Clip.none,
              child: InkWell(
                onTap: () => context.go(AppPaths.dashboard),
                borderRadius: BorderRadius.circular(8),
                mouseCursor: SystemMouseCursors.click,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: DriftProBrandLogo(
                    density: DriftProBrandDensity.bar,
                    showSubtitle: false,
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
