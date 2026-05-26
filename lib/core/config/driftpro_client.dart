import 'package:flutter/foundation.dart';

import '../constants/app_strings.dart';
import 'supabase_config.dart';

/// Hvilken klientflate som kjører appen.
enum DriftProClientSurface {
  /// driftpro.no / nettleser
  web,

  /// Installérbar Mac/PC-programvare (egen app, samme backend)
  desktop,

  /// Mobil (iOS/Android) — fremtidig sjåfør-app m.m.
  mobile,
}

/// Klient-identitet: separat installérbar desktop vs web, men én Supabase-kjerne.
class DriftProClient {
  DriftProClient._();

  static bool _routeDispatchProduct = false;

  /// Kalles fra [main_dispatch.dart] — Mac/PC kun ruteplanlegging.
  static void useRouteDispatchProduct() => _routeDispatchProduct = true;

  static bool get isRouteDispatchProduct => _routeDispatchProduct;

  static DriftProClientSurface get surface {
    if (kIsWeb) return DriftProClientSurface.web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return DriftProClientSurface.desktop;
      case TargetPlatform.iOS:
      case TargetPlatform.android:
        return DriftProClientSurface.mobile;
      default:
        return DriftProClientSurface.web;
    }
  }

  static bool get isDesktop => surface == DriftProClientSurface.desktop;
  static bool get isWeb => surface == DriftProClientSurface.web;
  static bool get isMobile => surface == DriftProClientSurface.mobile;

  /// Vist navn — ruteplan-klient på Mac/PC, ellers DriftPro web/mobil.
  static String get displayName {
    if (isRouteDispatchProduct) return 'DriftPro Ruteplan';
    if (isDesktop) return 'DriftPro Dispatch';
    return AppStrings.appName;
  }

  static String get tagline {
    if (isRouteDispatchProduct) {
      return 'Last-mile for Elkjøp — erstatter SAP og TransFleet · data fra DriftPro';
    }
    if (isDesktop) return 'Ruteplanlegging & flåte — koblet til DriftPro';
    return AppStrings.appTagline;
  }

  /// All data og innlogging går via samme Supabase-prosjekt som driftpro.no.
  static String get supabaseUrl => SupabaseConfig.url;

  static bool get usesSharedBackend => SupabaseConfig.isConfigured;

  static bool get isConfigured => SupabaseConfig.isConfigured;
}
