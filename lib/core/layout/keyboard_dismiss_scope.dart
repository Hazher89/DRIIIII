import 'package:flutter/material.dart';

/// Global tastatur-håndtering uten synlig toolbar.
///
/// • Trykk på tom plass (bakgrunn, dialog-tittel, lister) lukker tastaturet.
/// • Scroll/drag i lister lukker tastaturet.
class KeyboardDismissScope extends StatelessWidget {
  const KeyboardDismissScope({super.key, required this.child});

  final Widget child;

  static void dismiss() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus.hasFocus) {
      focus.unfocus();
    }
  }

  /// Bruk rundt [AlertDialog] / [Dialog] for trykk-utenfor i modaler.
  static Widget wrapDialog(Widget dialog) {
    return GestureDetector(
      onTap: dismiss,
      behavior: HitTestBehavior.translucent,
      child: dialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (notification.dragDetails != null) dismiss();
        return false;
      },
      child: GestureDetector(
        onTap: dismiss,
        behavior: HitTestBehavior.translucent,
        child: child,
      ),
    );
  }
}
