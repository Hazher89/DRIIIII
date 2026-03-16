class WhistleblowingReport {
  final String id;
  final String companyId;
  final String title;
  final String description;
  final List<String> imageUrls;
  final DateTime? createdAt;

  const WhistleblowingReport({
    required this.id,
    required this.companyId,
    required this.title,
    required this.description,
    this.imageUrls = const [],
    this.createdAt,
  });

  factory WhistleblowingReport.fromJson(Map<String, dynamic> json) {
    return WhistleblowingReport(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'company_id': companyId,
    'title': title,
    'description': description,
    'image_urls': imageUrls,
  };
}
