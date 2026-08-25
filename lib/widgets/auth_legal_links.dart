import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../screens/more/driftpro_platform_catalog.dart';
import '../screens/more/widgets/info_page_scaffold.dart';

/// Lenker til vilkår og personvern (norsk) — brukes før innlogging og i profil.
class AuthLegalLinks extends StatelessWidget {
  const AuthLegalLinks({
    super.key,
    this.compact = false,
    this.center = true,
  });

  final bool compact;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white54 : Colors.grey[700];
    final linkStyle = TextStyle(
      fontSize: compact ? 12 : 13,
      fontWeight: FontWeight.w600,
      color: DriftProTheme.primaryGreen,
      decoration: TextDecoration.underline,
      decorationColor: DriftProTheme.primaryGreen.withValues(alpha: 0.5),
    );

    final row = Wrap(
      alignment: center ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        TextButton(
          onPressed: () => launchInfoUrl(DriftProPlatformCatalog.termsOfUseUrl),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('Vilkår for bruk', style: linkStyle),
        ),
        Text('·', style: TextStyle(color: muted, fontSize: compact ? 12 : 13)),
        TextButton(
          onPressed: () =>
              launchInfoUrl(DriftProPlatformCatalog.privacyPolicyUrl),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('Personvernerklæring', style: linkStyle),
        ),
        Text('·', style: TextStyle(color: muted, fontSize: compact ? 12 : 13)),
        TextButton(
          onPressed: () => launchInfoUrl(DriftProPlatformCatalog.supportUrl),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('Support', style: linkStyle),
        ),
      ],
    );

    if (compact) return row;

    return Column(
      children: [
        Text(
          'Ved å logge inn godtar du vilkårene og personvernerklæringen.',
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: TextStyle(fontSize: 12, color: muted, height: 1.35),
        ),
        const SizedBox(height: 6),
        row,
      ],
    );
  }
}
