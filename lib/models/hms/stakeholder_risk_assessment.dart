import 'dart:convert';

class StakeholderRiskRow {
  final String id;
  final Map<String, String> cells;

  const StakeholderRiskRow({required this.id, required this.cells});

  StakeholderRiskRow copyWith({Map<String, String>? cells}) =>
      StakeholderRiskRow(id: id, cells: cells ?? Map<String, String>.from(this.cells));

  factory StakeholderRiskRow.fromJson(Map<String, dynamic> json) => StakeholderRiskRow(
        id: json['id'] as String,
        cells: (json['cells'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v?.toString() ?? ''),
        ),
      );

  Map<String, dynamic> toJson() => {'id': id, 'cells': cells};
}

class StakeholderRiskGroup {
  final String id;
  final String title;
  final List<StakeholderRiskRow> rows;

  const StakeholderRiskGroup({
    required this.id,
    required this.title,
    this.rows = const [],
  });

  StakeholderRiskGroup copyWith({
    String? title,
    List<StakeholderRiskRow>? rows,
  }) =>
      StakeholderRiskGroup(
        id: id,
        title: title ?? this.title,
        rows: rows ?? this.rows,
      );

  factory StakeholderRiskGroup.fromJson(Map<String, dynamic> json) =>
      StakeholderRiskGroup(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        rows: (json['rows'] as List<dynamic>? ?? [])
            .map((e) => StakeholderRiskRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'rows': rows.map((r) => r.toJson()).toList(),
      };
}

class StakeholderRiskSection {
  final String id;
  final String title;
  final String documentTitle;
  final String icon;
  final List<String> columnKeys;
  final Map<String, String> columnLabels;
  final List<String> numericKeys;
  final Map<String, String> riskFieldMap;
  final Map<String, String> residualFieldMap;
  final List<StakeholderRiskGroup> groups;
  final List<StakeholderRiskRow> rows;

  const StakeholderRiskSection({
    required this.id,
    required this.title,
    required this.documentTitle,
    this.icon = 'description',
    this.columnKeys = const [],
    this.columnLabels = const {},
    this.numericKeys = const [],
    this.riskFieldMap = const {},
    this.residualFieldMap = const {},
    this.groups = const [],
    this.rows = const [],
  });

  Iterable<StakeholderRiskRow> get allRows sync* {
    for (final g in groups) {
      yield* g.rows;
    }
    yield* rows;
  }

  StakeholderRiskSection copyWith({
    String? title,
    String? documentTitle,
    Map<String, String>? columnLabels,
    List<StakeholderRiskGroup>? groups,
    List<StakeholderRiskRow>? rows,
  }) =>
      StakeholderRiskSection(
        id: id,
        title: title ?? this.title,
        documentTitle: documentTitle ?? this.documentTitle,
        icon: icon,
        columnKeys: columnKeys,
        columnLabels: columnLabels ?? this.columnLabels,
        numericKeys: numericKeys,
        riskFieldMap: riskFieldMap,
        residualFieldMap: residualFieldMap,
        groups: groups ?? this.groups,
        rows: rows ?? this.rows,
      );

  factory StakeholderRiskSection.fromJson(Map<String, dynamic> json) =>
      StakeholderRiskSection(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        documentTitle: json['documentTitle'] as String? ?? '',
        icon: json['icon'] as String? ?? 'description',
        columnKeys: (json['columnKeys'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        columnLabels: (json['columnLabels'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
        numericKeys: (json['numericKeys'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        riskFieldMap: (json['riskFieldMap'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
        residualFieldMap: (json['residualFieldMap'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
        groups: (json['groups'] as List<dynamic>? ?? [])
            .map((e) => StakeholderRiskGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
        rows: (json['rows'] as List<dynamic>? ?? [])
            .map((e) => StakeholderRiskRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'documentTitle': documentTitle,
        'icon': icon,
        'columnKeys': columnKeys,
        'columnLabels': columnLabels,
        'numericKeys': numericKeys,
        'riskFieldMap': riskFieldMap,
        'residualFieldMap': residualFieldMap,
        'groups': groups.map((g) => g.toJson()).toList(),
        'rows': rows.map((r) => r.toJson()).toList(),
      };
}

class StakeholderRiskContent {
  final int templateVersion;
  final String sourceFile;
  final List<StakeholderRiskSection> sections;

  const StakeholderRiskContent({
    this.templateVersion = 1,
    this.sourceFile = '',
    this.sections = const [],
  });

  StakeholderRiskContent copyWith({List<StakeholderRiskSection>? sections}) =>
      StakeholderRiskContent(
        templateVersion: templateVersion,
        sourceFile: sourceFile,
        sections: sections ?? this.sections,
      );

  factory StakeholderRiskContent.fromJson(Map<String, dynamic> json) =>
      StakeholderRiskContent(
        templateVersion: json['templateVersion'] as int? ?? 1,
        sourceFile: json['sourceFile'] as String? ?? '',
        sections: (json['sections'] as List<dynamic>? ?? [])
            .map((e) => StakeholderRiskSection.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'templateVersion': templateVersion,
        'sourceFile': sourceFile,
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  StakeholderRiskSection? sectionById(String id) {
    for (final s in sections) {
      if (s.id == id) return s;
    }
    return null;
  }
}

class StakeholderRiskAssessment {
  final String id;
  final String companyId;
  final String createdBy;
  final String title;
  final int? assessmentYear;
  final String status;
  final StakeholderRiskContent content;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const StakeholderRiskAssessment({
    required this.id,
    required this.companyId,
    required this.createdBy,
    required this.title,
    this.assessmentYear,
    this.status = 'aktiv',
    required this.content,
    this.createdAt,
    this.updatedAt,
  });

  int get totalRows =>
      content.sections.fold(0, (sum, s) => sum + s.allRows.length);

  int get highRiskCount => content.sections.fold(0, (sum, s) {
        return sum +
            s.allRows.where((r) {
              final score = _rowRiskScore(s, r);
              return score != null && score >= 10;
            }).length;
      });

  int? _rowRiskScore(StakeholderRiskSection section, StakeholderRiskRow row) {
    final scoreKey = section.riskFieldMap['score'];
    if (scoreKey == null) return null;
    final raw = row.cells[scoreKey];
    if (raw != null && raw.trim().isNotEmpty) {
      return int.tryParse(raw.trim());
    }
    final pKey = section.riskFieldMap['probability'];
    final cKey = section.riskFieldMap['consequence'];
    if (pKey == null || cKey == null) return null;
    final p = int.tryParse(row.cells[pKey]?.trim() ?? '');
    final c = int.tryParse(row.cells[cKey]?.trim() ?? '');
    if (p == null || c == null) return null;
    return p * c;
  }

  factory StakeholderRiskAssessment.fromJson(Map<String, dynamic> json) =>
      StakeholderRiskAssessment(
        id: json['id'] as String,
        companyId: json['company_id'] as String,
        createdBy: json['created_by'] as String,
        title: json['title'] as String,
        assessmentYear: json['assessment_year'] as int?,
        status: json['status'] as String? ?? 'aktiv',
        content: StakeholderRiskContent.fromJson(
          json['content'] is String
              ? jsonDecode(json['content'] as String) as Map<String, dynamic>
              : json['content'] as Map<String, dynamic>,
        ),
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : null,
      );

  Map<String, dynamic> toInsertJson() => {
        'company_id': companyId,
        'created_by': createdBy,
        'title': title,
        'assessment_year': assessmentYear,
        'status': status,
        'content': content.toJson(),
      };

  Map<String, dynamic> toUpdateJson() => {
        'title': title,
        'assessment_year': assessmentYear,
        'status': status,
        'content': content.toJson(),
        'updated_at': DateTime.now().toIso8601String(),
      };

  StakeholderRiskAssessment copyWith({
    String? title,
    int? assessmentYear,
    String? status,
    StakeholderRiskContent? content,
  }) =>
      StakeholderRiskAssessment(
        id: id,
        companyId: companyId,
        createdBy: createdBy,
        title: title ?? this.title,
        assessmentYear: assessmentYear ?? this.assessmentYear,
        status: status ?? this.status,
        content: content ?? this.content,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
