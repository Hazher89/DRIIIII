import 'sop_training_models.dart';
import 'training_library_service.dart';

/// Bakoverkompatibel SOP-laster — delegerer til [TrainingLibraryService].
class SopTrainingService {
  SopTrainingService._();

  static final SopTrainingService instance = SopTrainingService._();

  static const assetPath = 'assets/hms/sop_hub_driftsrutiner_v4_8.docx';

  SopTrainingDocument? _cached;

  static const suggestedQueries = TrainingLibraryService.suggestedQueries;

  Future<SopTrainingDocument> load({bool force = false}) async {
    if (_cached != null && !force) return _cached!;
    await TrainingLibraryService.instance.loadAll(force: force);
    final doc = TrainingLibraryService.instance.docById('sop_hub');
    if (doc == null) {
      throw StateError('SOP Hub mangler i opplæringsbiblioteket');
    }
    _cached = doc;
    return doc;
  }

  List<SopSearchHit> search(String query, {int limit = 30}) {
    if (query.trim().isEmpty) return const [];
    return TrainingLibraryService.instance.search(query, limit: limit);
  }

  List<SopTrainingEntry> relatedEntries(
    SopTrainingEntry entry, {
    int limit = 6,
  }) {
    return TrainingLibraryService.instance.relatedEntries(entry, limit: limit);
  }
}
