import 'package:flutter/material.dart';

import '../../../core/config/driftpro_client.dart';
import '../../../core/layout/mobile_shell_scaffold.dart';

/// Portal-fane under [DriftProBrandedScaffold].
///
/// På mobil: ingen tittel-/refresh-/logout-header — kun innhold (+ valgfri
/// kompakt tilbake-knapp når siden er pushet). Bruk pull-to-refresh i body.
class PartnerPortalPageShell extends StatelessWidget {
  const PartnerPortalPageShell({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.bottom,
    this.leading,
    this.backgroundColor,
    this.floatingActionButton,
    this.hideMobileChrome = true,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? leading;
  final Color? backgroundColor;
  final Widget? floatingActionButton;

  /// Når true (standard): skjuler tittel/actions på mobil — unngår dobbel tekst
  /// under statusbar. Tilbake-knapp vises kun hvis [leading] er satt eller
  /// siden kan poppes.
  final bool hideMobileChrome;

  bool get _hasChrome =>
      (title != null && title!.isNotEmpty) ||
      (actions != null && actions!.isNotEmpty) ||
      bottom != null ||
      leading != null;

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;

    if (DriftProClient.isMobile) {
      final showBack = leading != null || (canPop && hideMobileChrome);
      final back = leading ??
          (showBack
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Tilbake',
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null);

      Widget mobileBody(Widget child) {
        // Faner under DriftProBrandBar har removeTop — SafeArea gir 0 ekstra der.
        // Pushede sider (Ansatte, Timer …) får riktig avstand under statusbar.
        return SafeArea(
          bottom: false,
          child: child,
        );
      }

      // Ren body uten titteltekst/refresh/logout — kun valgfri tilbake-rad.
      if (hideMobileChrome) {
        return Scaffold(
          backgroundColor: backgroundColor,
          body: mobileBody(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (back != null)
                  SizedBox(
                    height: 44,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: back,
                    ),
                  ),
                ?bottom,
                Expanded(child: body),
              ],
            ),
          ),
          floatingActionButton: floatingActionButton,
        );
      }

      if (!_hasChrome && back == null) {
        return Scaffold(
          backgroundColor: backgroundColor,
          body: mobileBody(body),
          floatingActionButton: floatingActionButton,
        );
      }

      return MobileShellScaffold(
        backgroundColor: backgroundColor,
        title: title,
        actions: actions,
        bottom: bottom,
        leading: back,
        floatingActionButton: floatingActionButton,
        body: mobileBody(body),
      );
    }

    final effectiveLeading = leading ??
        (canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Tilbake',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _hasChrome || effectiveLeading != null
          ? AppBar(
              backgroundColor: backgroundColor,
              surfaceTintColor: Colors.transparent,
              leading: effectiveLeading,
              automaticallyImplyLeading: effectiveLeading == null,
              title: title != null ? Text(title!) : null,
              actions: actions,
              bottom: bottom,
            )
          : null,
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}
