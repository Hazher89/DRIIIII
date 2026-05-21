import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('utf8 mojibake repareres til norske tegn', () {
    const broken = 'milliarder Ã¥ rutte med: â\x80\x93 Det verste';
    final fixed = utf8.decode(latin1.encode(broken), allowMalformed: true);
    expect(fixed, contains('å'));
    expect(fixed, isNot(contains('Ã¥')));
  });
}
