import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'auth_legal_links.dart';
import 'driftpro_brand_logo.dart';

/// Én samlet innloggingsflate: gradient + merkevare + innhold (uten separat banner).
class AuthScreenShell extends StatelessWidget {
  const AuthScreenShell({
    super.key,
    required this.child,
    this.showBack = false,
    this.onBack,
    this.showLegalFooter = true,
    this.maxWidth = 440,
  });

  final Widget child;
  final bool showBack;
  final VoidCallback? onBack;
  final bool showLegalFooter;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPad = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [
                    Color(0xFF03080F),
                    Color(0xFF0A192F),
                    Color(0xFF112240),
                  ]
                : const [
                    Color(0xFFE8F5E9),
                    Color(0xFFC8E6C9),
                    Color(0xFFA5D6A7),
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              if (showBack)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                    tooltip: 'Tilbake',
                  ),
                ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      showBack ? 4 : 24 + (topPad > 0 ? 0 : 8),
                      24,
                      24,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Column(
                        children: [
                          DriftProBrandLogo(
                            density: DriftProBrandDensity.comfortable,
                            showSubtitle: true,
                            alignment: Alignment.center,
                          ),
                          const SizedBox(height: 28),
                          child,
                          if (showLegalFooter) ...[
                            const SizedBox(height: 28),
                            const AuthLegalLinks(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Diskret tekststil for hjelpetekst på innlogging.
TextStyle authMutedStyle(BuildContext context, {double size = 13}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return TextStyle(
    fontSize: size,
    height: 1.35,
    color: isDark ? Colors.white60 : Colors.grey[700],
  );
}

TextStyle authTitleStyle(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return DriftProTheme.headingMd.copyWith(
    color: isDark ? Colors.white : Colors.grey[900],
  );
}
