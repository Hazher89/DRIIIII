import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../models/survey/survey.dart';

class SurveyPublishView extends StatelessWidget {
  final Survey survey;
  const SurveyPublishView({super.key, required this.survey});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final publicLink = 'https://driftpro.no/s/${survey.id}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Inngangspunkt for spørreundersøkelse',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('15 svar', style: TextStyle(color: Colors.grey, fontSize: 18)),
              const SizedBox(height: 30),
              Row(
                children: [
                   _buildActionButton('Administrer varsler', Icons.notifications_outlined, Colors.amber),
                   const SizedBox(width: 12),
                   _buildActionButton('Velg en målgruppe', Icons.people_outline, Colors.amber),
                   const Spacer(),
                   _buildActionButton('Legg til nytt inngangspunkt', Icons.add, DriftProTheme.primaryGreen, solid: true),
                ],
              ),
              const SizedBox(height: 30),
              // Table Header
              _buildTableHeader(isDark),
              // Table Row
              _buildTableRow(isDark, publicLink),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, {bool solid = false}) {
    return ElevatedButton.icon(
      onPressed: () {},
      icon: Icon(icon, size: 18, color: solid ? Colors.white : color),
      label: Text(label, style: TextStyle(color: solid ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: solid ? color : color.withOpacity(0.1),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  Widget _buildTableHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.arrow_downward, size: 14, color: Colors.grey),
          const SizedBox(width: 40),
          const Expanded(flex: 3, child: Text('Inngangspunktets navn', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          _buildSmallHeader('Status'),
          _buildSmallHeader('Svar'),
          _buildSmallHeader('Endringsdato'),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildSmallHeader(String text) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const Icon(Icons.arrow_downward, size: 12, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildTableRow(bool isDark, String link) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        border: Border(
          bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!),
          left: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!),
          right: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.link, color: DriftProTheme.primaryGreen, size: 20),
          const SizedBox(width: 40),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Web Link 1', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      color: Colors.grey[100],
                      child: Text(link, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: link));
                      },
                      child: const Text('Kopier nettadresse', style: TextStyle(color: Colors.blue, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Opprettet 12/2/2022', style: TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: const Text('Åpent', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            ),
          ),
          const Expanded(child: Text('15', textAlign: TextAlign.center)),
          const Expanded(child: Text('12/4/2022', textAlign: TextAlign.center)),
          IconButton(icon: const Icon(Icons.more_horiz), onPressed: () {}),
        ],
      ),
    );
  }
}
