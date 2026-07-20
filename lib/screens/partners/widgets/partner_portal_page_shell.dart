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
    if (DriftProClient.isMobile) {
      if (!_hasChrome) {
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
        leading: leading,
        floatingActionButton: floatingActionButton,
        body: body,
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _hasChrome
          ? AppBar(
              backgroundColor: backgroundColor,
              surfaceTintColor: Colors.transparent,
              leading: leading,
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
