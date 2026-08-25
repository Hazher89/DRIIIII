import 'package:flutter/material.dart';

import '../../../core/config/driftpro_client.dart';
import '../../../core/layout/mobile_shell_scaffold.dart';

/// Portal-fane under [DriftProBrandedScaffold] — kompakt header på mobil, vanlig AppBar på web.
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
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? leading;
  final Color? backgroundColor;
  final Widget? floatingActionButton;

  bool get _hasChrome =>
      (title != null && title!.isNotEmpty) ||
      (actions != null && actions!.isNotEmpty) ||
      bottom != null ||
      leading != null;

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final effectiveLeading = leading ??
        (canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Tilbake',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null);

    if (DriftProClient.isMobile) {
      if (!_hasChrome && effectiveLeading == null) {
        return Scaffold(
          backgroundColor: backgroundColor,
          body: body,
          floatingActionButton: floatingActionButton,
        );
      }
      return MobileShellScaffold(
        backgroundColor: backgroundColor,
        title: title,
        actions: actions,
        bottom: bottom,
        leading: effectiveLeading,
        floatingActionButton: floatingActionButton,
        body: body,
      );
    }

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
