import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Haptic feedback for varsler og viktige hendelser (iOS + Android).
abstract final class HapticFeedbackService {
  static void selection() {
    if (kIsWeb) return;
    HapticFeedback.selectionClick();
  }

  static void light() {
    if (kIsWeb) return;
    HapticFeedback.lightImpact();
  }

  static void medium() {
    if (kIsWeb) return;
    HapticFeedback.mediumImpact();
  }

  /// Varsel mottatt — merkbart men ikke aggressivt.
  static void notification() {
    if (kIsWeb) return;
    HapticFeedback.mediumImpact();
  }

  static void success() {
    if (kIsWeb) return;
    HapticFeedback.heavyImpact();
  }

  static void error() {
    if (kIsWeb) return;
    HapticFeedback.vibrate();
  }
}
