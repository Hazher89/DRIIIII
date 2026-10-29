import 'package:driftpro/core/services/partner/route_pdf_text_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parser Freight Order fra Trip Overview-topp', () {
    const text = '''
Trip Overview
Freight Order 6102948737
Resource ID
NO_O_M0089
Driver Name
mavi artis 089 089 mavi artis
''';
    expect(RoutePdfTextService.parseFreightOrder(text), '6102948737');
    expect(RoutePdfTextService.parseDriverName(text), 'Mavi Artis');
  });

  test('parser Freight Order med kolon', () {
    const text = 'Freight Order: 6123456789\nResource ID NO_O_M0001';
    expect(RoutePdfTextService.parseFreightOrder(text), '6123456789');
  });

  test('parser limt Syncfusion Trip Overview (FO + sjåfør)', () {
    const text =
        'Page 1 of 6Trip Overview Freight Order6102957822CarrierMavi Logistikk AS '
        'F60586102957822 Elkjøp Norge AS Nydalsveien 12B, 0484 Oslo '
        'Resource IDNO_O_M0096Driver NameAli 096 096 aliConsumed Weight656.02 KG '
        'Contact personHUB Oslo';
    expect(RoutePdfTextService.parseFreightOrder(text), '6102957822');
    expect(RoutePdfTextService.parseDriverName(text), 'Ali');
  });
}
