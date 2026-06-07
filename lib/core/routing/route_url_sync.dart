import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Synkroniserer fane-/tilstand med nettleser-URL (path + query).
abstract final class RouteUrlSync {
  static void goIfChanged(BuildContext context, String target) {
    if (!context.mounted) return;
    final router = GoRouter.of(context);
    if (router.state.uri.toString() != target) {
      router.go(target);
    }
  }

  static String build(String path, [Map<String, String?> query = const {}]) {
    final filtered = <String, String>{};
    for (final e in query.entries) {
      final v = e.value;
      if (v != null && v.isNotEmpty) filtered[e.key] = v;
    }
    return Uri(
      path: path,
      queryParameters: filtered.isEmpty ? null : filtered,
    ).toString();
  }

  static int indexForSlug(String? slug, List<String> slugs, {int fallback = 0}) {
    if (slug == null || slug.isEmpty) return fallback;
    final i = slugs.indexOf(slug);
    return i >= 0 ? i : fallback;
  }

  static String? slugForIndex(int index, List<String> slugs) {
    if (index < 0 || index >= slugs.length) return null;
    return slugs[index];
  }

  static void syncTab(
    BuildContext context, {
    required String basePath,
    required int index,
    required List<String> slugs,
    Map<String, String?> extraQuery = const {},
  }) {
    final tab = slugForIndex(index, slugs);
    final query = <String, String?>{...extraQuery, if (tab != null) 'tab': tab};
    goIfChanged(context, build(basePath, query));
  }
}
