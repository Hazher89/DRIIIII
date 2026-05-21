import 'package:flutter/material.dart';

import '../core/services/storage/company_file_storage.dart';

/// Bilde fra Supabase-URL eller Dropbox-referanse (`dropbox://...`).
class ResolvedStorageImage extends StatelessWidget {
  final String storageRef;
  final double? width;
  final double? height;
  final BoxFit fit;

  const ResolvedStorageImage({
    super.key,
    required this.storageRef,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: CompanyFileStorage.resolveDisplayUrl(storageRef),
      builder: (context, snap) {
        if (snap.hasError) {
          return SizedBox(
            width: width,
            height: height,
            child: const Icon(Icons.broken_image_outlined),
          );
        }
        final url = snap.data;
        if (url == null || snap.connectionState != ConnectionState.done) {
          return SizedBox(
            width: width,
            height: height,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return Image.network(
          url,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
        );
      },
    );
  }
}
