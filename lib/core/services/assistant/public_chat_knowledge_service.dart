import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../config/supabase_config.dart';
import '../supabase_service.dart';
import 'assistant_corpus.dart';

/// Én trenbar kunnskapsbit for CCC/butikk-chatten (/montering).
class PublicChatKnowledgeEntry {
  const PublicChatKnowledgeEntry({
    required this.id,
    required this.companyId,
    required this.kind,
    required this.title,
    required this.content,
    this.question,
    this.preferredAnswer,
    this.tags = const [],
    this.priority = 50,
    this.published = true,
    this.active = true,
    this.sourceFilename,
    this.storagePath,
    this.mimeType,
    this.byteSize,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String companyId;
  final String kind;
  final String title;
  final String content;
  final String? question;
  final String? preferredAnswer;
  final List<String> tags;
  final int priority;
  final bool published;
  final bool active;
  final String? sourceFilename;
  final String? storagePath;
  final String? mimeType;
  final int? byteSize;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PublicChatKnowledgeEntry.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    return PublicChatKnowledgeEntry(
      id: json['id'] as String,
      companyId: json['company_id'] as String? ?? '',
      kind: json['kind'] as String? ?? 'note',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      question: json['question'] as String?,
      preferredAnswer: json['preferred_answer'] as String?,
      tags: tagsRaw is List
          ? tagsRaw.map((e) => '$e').where((e) => e.isNotEmpty).toList()
          : const [],
      priority: (json['priority'] as num?)?.toInt() ?? 50,
      published: json['published'] as bool? ?? true,
      active: json['active'] as bool? ?? true,
      sourceFilename: json['source_filename'] as String?,
      storagePath: json['storage_path'] as String?,
      mimeType: json['mime_type'] as String?,
      byteSize: (json['byte_size'] as num?)?.toInt(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  String get kindLabel => switch (kind) {
        'document' => 'Dokument',
        'rule' => 'Regel / rutine',
        'qa' => 'Q&A-trening',
        'playbook' => 'Playbook',
        'tone' => 'Svarstil',
        _ => 'Notat',
      };

  KnowledgeChunk toChunk() {
    final bodyParts = <String>[];
    if (question != null && question!.trim().isNotEmpty) {
      bodyParts.add('Spørsmål: ${question!.trim()}');
    }
    final answer = preferredAnswer?.trim();
    if (answer != null && answer.isNotEmpty) {
      bodyParts.add(answer);
    } else if (content.trim().isNotEmpty) {
      bodyParts.add(content.trim());
    }
    return KnowledgeChunk(
      id: 'live.$id',
      source: KnowledgeSourceKind.liveTrain,
      title: title,
      body: bodyParts.join('\n\n'),
      tags: [
        ...tags,
        kind,
        if (question != null && question!.trim().isNotEmpty) 'qa',
        'live',
        'trained',
      ],
    );
  }
}

class PublicChatKnowledgeStats {
  const PublicChatKnowledgeStats({
    required this.total,
    required this.published,
    required this.documents,
    required this.qa,
    required this.rules,
  });

  final int total;
  final int published;
  final int documents;
  final int qa;
  final int rules;
}

/// Superadmin-lab for å mate CCC/butikk-chatten med live kunnskap.
class PublicChatKnowledgeService {
  PublicChatKnowledgeService._();
  static final PublicChatKnowledgeService instance =
      PublicChatKnowledgeService._();

  static const bucket = 'public-chat-knowledge';

  List<PublicChatKnowledgeEntry>? _publishedCache;
  DateTime? _publishedCacheAt;

  Future<List<PublicChatKnowledgeEntry>> listForCompany(String companyId) async {
    if (!SupabaseService.isConfigured) return const [];
    final data = await SupabaseService.client
        .from('public_chat_knowledge')
        .select()
        .eq('company_id', companyId)
        .order('priority', ascending: false)
        .order('updated_at', ascending: false);
    return (data as List)
        .map((e) => PublicChatKnowledgeEntry.fromJson(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList();
  }

  Future<PublicChatKnowledgeStats> statsFor(List<PublicChatKnowledgeEntry> rows) {
    return Future.value(
      PublicChatKnowledgeStats(
        total: rows.length,
        published: rows.where((e) => e.published && e.active).length,
        documents: rows.where((e) => e.kind == 'document').length,
        qa: rows.where((e) => e.kind == 'qa').length,
        rules: rows.where((e) => e.kind == 'rule' || e.kind == 'playbook').length,
      ),
    );
  }

  /// Brukes av offentlig /montering — kun publiserte bits.
  Future<List<PublicChatKnowledgeEntry>> listPublished({
    bool forceRefresh = false,
  }) async {
    if (!SupabaseConfig.isConfigured || !SupabaseService.isConfigured) {
      return const [];
    }
    final now = DateTime.now();
    if (!forceRefresh &&
        _publishedCache != null &&
        _publishedCacheAt != null &&
        now.difference(_publishedCacheAt!) < const Duration(minutes: 2)) {
      return _publishedCache!;
    }
    try {
      final data = await SupabaseService.client.rpc(
        'list_public_chat_knowledge_published',
        params: {'p_limit': 150},
      );
      final rows = (data as List)
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return PublicChatKnowledgeEntry(
              id: m['id'] as String,
              companyId: '',
              kind: m['kind'] as String? ?? 'note',
              title: m['title'] as String? ?? '',
              content: m['content'] as String? ?? '',
              question: m['question'] as String?,
              preferredAnswer: m['preferred_answer'] as String?,
              tags: m['tags'] is List
                  ? (m['tags'] as List).map((t) => '$t').toList()
                  : const [],
              priority: (m['priority'] as num?)?.toInt() ?? 50,
              updatedAt: m['updated_at'] != null
                  ? DateTime.tryParse(m['updated_at'].toString())
                  : null,
            );
          })
          .toList();
      _publishedCache = rows;
      _publishedCacheAt = now;
      return rows;
    } catch (_) {
      return _publishedCache ?? const [];
    }
  }

  Future<List<KnowledgeChunk>> publishedChunks({bool forceRefresh = false}) async {
    final rows = await listPublished(forceRefresh: forceRefresh);
    return [
      for (final r in rows)
        if (r.content.trim().isNotEmpty ||
            (r.preferredAnswer?.trim().isNotEmpty ?? false))
          r.toChunk(),
    ];
  }

  void invalidateCache() {
    _publishedCache = null;
    _publishedCacheAt = null;
  }

  Future<PublicChatKnowledgeEntry> upsert({
    String? id,
    required String companyId,
    required String kind,
    required String title,
    required String content,
    String? question,
    String? preferredAnswer,
    List<String> tags = const [],
    int priority = 50,
    bool published = true,
    bool active = true,
    String? sourceFilename,
    String? storagePath,
    String? mimeType,
    int? byteSize,
  }) async {
    final uid = SupabaseService.client.auth.currentUser?.id;
    final payload = <String, dynamic>{
      'company_id': companyId,
      'kind': kind,
      'title': title.trim(),
      'content': content.trim(),
      'question': question?.trim(),
      'preferred_answer': preferredAnswer?.trim(),
      'tags': tags,
      'priority': priority.clamp(0, 100),
      'published': published,
      'active': active,
      'source_filename': sourceFilename,
      'storage_path': storagePath,
      'mime_type': mimeType,
      'byte_size': byteSize,
      'updated_by': uid,
      if (id == null) 'created_by': uid,
    };

    final row = id == null
        ? await SupabaseService.client
            .from('public_chat_knowledge')
            .insert(payload)
            .select()
            .single()
        : await SupabaseService.client
            .from('public_chat_knowledge')
            .update(payload)
            .eq('id', id)
            .select()
            .single();

    invalidateCache();
    return PublicChatKnowledgeEntry.fromJson(
      Map<String, dynamic>.from(row as Map),
    );
  }

  Future<void> setActive({required String id, required bool active}) async {
    await SupabaseService.client.from('public_chat_knowledge').update({
      'active': active,
      'updated_by': SupabaseService.client.auth.currentUser?.id,
    }).eq('id', id);
    invalidateCache();
  }

  Future<void> setPublished({
    required String id,
    required bool published,
  }) async {
    await SupabaseService.client.from('public_chat_knowledge').update({
      'published': published,
      'updated_by': SupabaseService.client.auth.currentUser?.id,
    }).eq('id', id);
    invalidateCache();
  }

  Future<void> delete(String id, {String? storagePath}) async {
    if (storagePath != null && storagePath.isNotEmpty) {
      try {
        await SupabaseService.client.storage.from(bucket).remove([storagePath]);
      } catch (_) {}
    }
    await SupabaseService.client.from('public_chat_knowledge').delete().eq('id', id);
    invalidateCache();
  }

  Future<({String text, String? storagePath, String mime, int bytes})>
      ingestFile({
    required String companyId,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final lower = fileName.toLowerCase();
    String text;
    if (lower.endsWith('.pdf') || mimeType.contains('pdf')) {
      text = extractPdfText(bytes);
    } else {
      text = String.fromCharCodes(bytes);
    }
    text = _cleanExtracted(text);
    if (text.trim().length < 20) {
      throw Exception(
        'Fant for lite tekst i filen. Lim inn teksten manuelt, eller last opp en tekst-PDF.',
      );
    }

    String? path;
    try {
      final safe = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      path =
          '$companyId/${DateTime.now().millisecondsSinceEpoch}_$safe';
      await SupabaseService.client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
    } catch (_) {
      // Bucket kan mangle — lagre kun tekst i DB.
      path = null;
    }

    return (
      text: text.length > 180000 ? text.substring(0, 180000) : text,
      storagePath: path,
      mime: mimeType,
      bytes: bytes.length,
    );
  }

  static String extractPdfText(Uint8List bytes) {
    final doc = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(doc);
      return extractor.extractText();
    } finally {
      doc.dispose();
    }
  }

  static String _cleanExtracted(String raw) {
    return raw
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
