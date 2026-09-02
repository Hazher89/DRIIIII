import 'package:driftpro/core/services/assistant/assistant_route_intelligence.dart';
import 'package:driftpro/core/services/partner/mavi_unit_codes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts MAVI codes from natural language', () {
    expect(
      AssistantRouteIntelligence.extractMaviCode('hvor har M09 kjørt i det siste?'),
      MaviUnitCodes.normalize('M9'),
    );
    expect(
      AssistantRouteIntelligence.extractMaviCode('kunder for m08 siste uke'),
      MaviUnitCodes.normalize('M08'),
    );
    expect(
      AssistantRouteIntelligence.extractMaviCode('endre rute på NO_O_M0062'),
      MaviUnitCodes.normalize('M62'),
    );
    expect(AssistantRouteIntelligence.extractMaviCode('hvordan melder jeg avvik?'), isNull);
  });

  test('detects route-related questions', () {
    expect(
      AssistantRouteIntelligence.looksLikeRouteQuery(
        'hvor har M09 kjørt i det siste?',
      ),
      isTrue,
    );
    expect(
      AssistantRouteIntelligence.looksLikeRouteQuery(
        'hvor mange kunder har M08 hatt den siste uken?',
      ),
      isTrue,
    );
    expect(
      AssistantRouteIntelligence.looksLikeRouteQuery(
        'hvor mange ganger måtte vi endre rute på M62',
      ),
      isTrue,
    );
    expect(
      AssistantRouteIntelligence.looksLikeRouteQuery('M09'),
      isFalse,
    );
  });
}
