import 'package:flutter/material.dart';

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
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          decoration: BoxDecoration(
            color: drift.surface,
            border: Border(bottom: BorderSide(color: drift.borderSubtle)),
          ),
          child: const DriftProBrandLogo(
            density: DriftProBrandDensity.compact,
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
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          const DriftProBrandBar(),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
