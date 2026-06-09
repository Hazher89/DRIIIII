import 'package:flutter/material.dart';

class TimeWorkType {
  const TimeWorkType({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
    required this.category,
    this.payrollCode,
    required this.colorHex,
    this.isDefaultPunch = false,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String companyId;
  final String code;
  final String name;
  final String category;
  final String? payrollCode;
  final String colorHex;
  final bool isDefaultPunch;
  final bool isActive;
  final int sortOrder;

  String get label => '$code $name';

  Color get color {
    final hex = colorHex.replaceFirst('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return const Color(0xFF0D9488);
  }

  factory TimeWorkType.fromJson(Map<String, dynamic> json) {
    return TimeWorkType(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? 'shift',
      payrollCode: json['payroll_code'] as String?,
      colorHex: json['color_hex'] as String? ?? '#0D9488',
      isDefaultPunch: json['is_default_punch'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}
