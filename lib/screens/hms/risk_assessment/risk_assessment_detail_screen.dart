import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/hms/hms_ecosystem_service.dart';
import '../../../core/services/hms/hms_pdf_generators.dart';
import '../../../core/services/supabase_service.dart';
import '../widgets/hms_pdf_export_button.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/risk_assessment.dart';
import '../../../models/risk_assessment_status.dart';
import '../../../models/user_profile.dart';
import '../widgets/hms_responsible_picker.dart';
import '../widgets/interactive_risk_matrix.dart';
import 'widgets/risk_assessment_attachments_panel.dart';
import 'widgets/risk_form_section.dart';
import '../../../models/ticket_assignee_options.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

class RiskAssessmentDetailScreen extends StatefulWidget {
  final RiskAssessment assessment;

  const RiskAssessmentDetailScreen({super.key, required this.assessment});

  @override
  State<RiskAssessmentDetailScreen> createState() =>
      _RiskAssessmentDetailScreenState();
}

class _RiskAssessmentDetailScreenState extends State<RiskAssessmentDetailScreen> {
  late RiskAssessment _ra;
  UserProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;

  int _initialP = 3;
  int _initialC = 3;
  int _residualP = 3;
  int _residualC = 3;
  String _status = RiskAssessmentStatuses.aktiv;
  String? _isoStandard;
  String? _responsibleId;
  TicketAssigneeOptions _assignees = const TicketAssigneeOptions();
  List<String> _imageUrls = [];
  List<RiskDocumentAttachment> _documents = [];
  DateTime? _deadline;
  DateTime? _reviewDate;

  final _titleController = TextEditingController();
  final _areaController = TextEditingController();
  final _locationDetailController = TextEditingController();
  final _activityProcessController = TextEditingController();
  final _descController = TextEditingController();
  final _hazardSourceController = TextEditingController();
  final _affectedPersonsController = TextEditingController();
  final _rootCauseController = TextEditingController();
  final _legalRefController = TextEditingController();
  final _evalMethodController = TextEditingController();
  final _existingMeasuresController = TextEditingController();
  final _proposedController = TextEditingController();
  final _residualMeasuresController = TextEditingController();
  final _treatmentNotesController = TextEditingController();
  final _reviewNotesController = TextEditingController();
  final _scenarioController = TextEditingController();

  static const _isoOptions = ['ISO 9001', 'ISO 14001', 'ISO 45001', 'ISO 9001/14001', 'Internkontroll'];

  bool get _canEdit =>
      _profile?.isAdmin == true ||
      _profile?.role == UserRole.leder ||
      _profile?.id == _ra.createdBy ||
      _profile?.id == _ra.responsiblePerson;

  @override
  void initState() {
    super.initState();
    _ra = widget.assessment;
    _syncFromRa();
    _load();
  }

  void _syncFromRa() {
    _initialP = _ra.initialProbability;
    _initialC = _ra.initialConsequence;
    _residualP = _ra.residualProbability;
    _residualC = _ra.residualConsequence;
    _status = _ra.status;
    _isoStandard = _ra.isoStandard;
    _responsibleId = _ra.responsiblePerson;
    _imageUrls = List.from(_ra.imageUrls);
    _documents = List.from(_ra.documentUrls);
    _deadline = _ra.deadline;
    _reviewDate = _ra.reviewDate;
    _titleController.text = _ra.title;
    _areaController.text = _ra.area ?? '';
    _locationDetailController.text = _ra.locationDetail ?? '';
    _activityProcessController.text = _ra.activityProcess ?? '';
    _descController.text = _ra.description ?? '';
    _hazardSourceController.text = _ra.hazardSource ?? '';
    _affectedPersonsController.text = _ra.affectedPersons ?? '';
    _rootCauseController.text = _ra.rootCause ?? '';
    _legalRefController.text = _ra.legalReference ?? '';
    _evalMethodController.text = _ra.evaluationMethod ?? '';
    _existingMeasuresController.text = _ra.existingMeasures ?? '';
    _proposedController.text = _ra.proposedMeasures ?? '';
    _residualMeasuresController.text = _ra.residualMeasures ?? '';
    _treatmentNotesController.text = _ra.treatmentNotes ?? '';
    _reviewNotesController.text = _ra.reviewNotes ?? '';
    _scenarioController.text = _ra.scenarioCategory ?? '';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _profile = await SupabaseService.fetchCurrentUserProfile();
      _assignees = await HmsResponsiblePicker.loadOptions();
      final fresh = await HmsEcosystemService.fetchRiskAssessmentById(_ra.id);
      if (fresh != null) {
        _ra = fresh;
        _syncFromRa();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save({bool markTreated = false}) async {
    if (!_canEdit) return;
    setState(() => _saving = true);
    try {
      final userId = _profile?.id;
      await HmsEcosystemService.updateRiskAssessment(_ra.id, {
        'title': _titleController.text.trim(),
        'area': _areaController.text.trim(),
        'location_detail': _locationDetailController.text.trim(),
        'activity_process': _activityProcessController.text.trim(),
        'description': _descController.text.trim(),
        'hazard_source': _hazardSourceController.text.trim(),
        'affected_persons': _affectedPersonsController.text.trim(),
        'root_cause': _rootCauseController.text.trim(),
        'legal_reference': _legalRefController.text.trim(),
        'evaluation_method': _evalMethodController.text.trim(),
        'existing_measures': _existingMeasuresController.text.trim(),
        'proposed_measures': _proposedController.text.trim(),
        'residual_measures': _residualMeasuresController.text.trim(),
        'treatment_notes': _treatmentNotesController.text.trim(),
        'review_notes': _reviewNotesController.text.trim(),
        'iso_standard': _isoStandard,
        'scenario_category': _scenarioController.text.trim(),
        'responsible_person': _responsibleId,
        'status': markTreated ? RiskAssessmentStatuses.behandlet : _status,
        'initial_probability': _initialP,
        'initial_consequence': _initialC,
        'residual_probability': _residualP,
        'residual_consequence': _residualC,
        'probability': _initialP,
        'consequence': _initialC,
        'image_urls': _imageUrls,
        'document_urls': _documents.map((d) => d.toJson()).toList(),
        'deadline': _deadline?.toIso8601String().split('T').first,
        'review_date': _reviewDate?.toIso8601String().split('T').first,
        if (markTreated && userId != null) ...{
          'treated_at': DateTime.now().toIso8601String(),
          'treated_by': userId,
        },
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(markTreated ? 'Markert som behandlet' : 'Lagret')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadFiles(List<PlatformFile> files, bool isImage) async {
    if (!_canEdit) return;
    setState(() => _uploading = true);
    try {
      for (final f in files) {
        if (f.bytes == null) continue;
        final url = await HmsEcosystemService.uploadRiskAssessmentFile(
          companyId: _ra.companyId,
          bytes: f.bytes!,
          fileName: f.name,
        );
        if (isImage) {
          _imageUrls.add(url);
        } else {
          _documents.add(RiskDocumentAttachment(
            url: url,
            fileName: f.name,
            uploadedAt: DateTime.now(),
          ));
        }
      }
      setState(() {});
      await _save();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _titleController,
      _areaController,
      _locationDetailController,
      _activityProcessController,
      _descController,
      _hazardSourceController,
      _affectedPersonsController,
      _rootCauseController,
      _legalRefController,
      _evalMethodController,
      _existingMeasuresController,
      _proposedController,
      _residualMeasuresController,
      _treatmentNotesController,
      _reviewNotesController,
      _scenarioController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(_ra.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          HmsPdfExportButton(
            fileName: 'ros_${_ra.id.substring(0, 8)}',
            onGenerate: () => HmsPdfGenerators.riskAssessment(_ra),
          ),
          if (_canEdit && !RiskAssessmentStatuses.isTreated(_status))
            TextButton(
              onPressed: _saving ? null : () => _save(markTreated: true),
              child: const Text('Behandlet'),
            ),
          if (_canEdit)
            IconButton(
              icon: _saving
                  ? SizedBox(width: 20, height: 20, child: DriftProLoadingIndicator(size: 20))
                  : const Icon(Icons.save_outlined),
              onPressed: _saving ? null : () => _save(),
            ),
        ],
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_ra.avvikBoosted) _buildAvvikBanner(),
                  _statusBanner(fmt),
                  RiskFormSection(
                    title: 'Identifikasjon',
                    icon: Icons.fact_check_outlined,
                    children: [
                      riskTextField(label: 'Tittel', controller: _titleController, readOnly: !_canEdit),
                      riskTextField(label: 'Område', controller: _areaController, readOnly: !_canEdit),
                      riskTextField(label: 'Sted', controller: _locationDetailController, readOnly: !_canEdit),
                      riskTextField(label: 'Prosess', controller: _activityProcessController, readOnly: !_canEdit),
                      riskDropdown<String?>(
                        label: 'ISO',
                        value: _isoStandard,
                        items: [null, ..._isoOptions],
                        labelBuilder: (v) => v ?? '—',
                        onChanged: (v) => setState(() => _isoStandard = v),
                        readOnly: !_canEdit,
                      ),
                      riskDropdown<String>(
                        label: 'Status',
                        value: _status,
                        items: RiskAssessmentStatuses.all,
                        labelBuilder: RiskAssessmentStatuses.label,
                        onChanged: (v) => setState(() => _status = v ?? _status),
                        readOnly: !_canEdit,
                      ),
                      if (_canEdit)
                        HmsResponsiblePicker(
                          selectedId: _responsibleId,
                          onChanged: (v) => setState(() => _responsibleId = v),
                          options: _assignees,
                        ),
                    ],
                  ),
                  RiskFormSection(
                    title: 'Fare og konsekvens',
                    icon: Icons.warning_amber_outlined,
                    children: [
                      riskTextField(label: 'Beskrivelse', controller: _descController, maxLines: 4, readOnly: !_canEdit),
                      riskTextField(label: 'Farekilde', controller: _hazardSourceController, maxLines: 2, readOnly: !_canEdit),
                      riskTextField(label: 'Berørte', controller: _affectedPersonsController, maxLines: 2, readOnly: !_canEdit),
                      riskTextField(label: 'Rotårsak', controller: _rootCauseController, maxLines: 2, readOnly: !_canEdit),
                      riskTextField(label: 'Lov/krav', controller: _legalRefController, maxLines: 2, readOnly: !_canEdit),
                      riskTextField(label: 'Metode', controller: _evalMethodController, readOnly: !_canEdit),
                    ],
                  ),
                  RiskFormSection(
                    title: 'Risikomatrise',
                    icon: Icons.grid_on,
                    children: [
                      DualRiskMatrixPanel(
                        initialP: _initialP,
                        initialC: _initialC,
                        residualP: _residualP,
                        residualC: _residualC,
                        readOnly: !_canEdit,
                        onInitialP: _canEdit ? (v) => setState(() => _initialP = v) : null,
                        onInitialC: _canEdit ? (v) => setState(() => _initialC = v) : null,
                        onResidualP: _canEdit ? (v) => setState(() => _residualP = v) : null,
                        onResidualC: _canEdit ? (v) => setState(() => _residualC = v) : null,
                      ),
                      const SizedBox(height: 12),
                      _comparisonSummary(),
                    ],
                  ),
                  RiskFormSection(
                    title: 'Tiltak',
                    icon: Icons.shield_outlined,
                    children: [
                      riskTextField(label: 'Eksisterende', controller: _existingMeasuresController, maxLines: 3, readOnly: !_canEdit),
                      riskTextField(label: 'Foreslåtte', controller: _proposedController, maxLines: 3, readOnly: !_canEdit),
                      riskTextField(label: 'Gjennomførte', controller: _residualMeasuresController, maxLines: 3, readOnly: !_canEdit),
                      riskTextField(label: 'Behandlingsnotat', controller: _treatmentNotesController, maxLines: 3, readOnly: !_canEdit),
                      riskTextField(label: 'Revisjonsnotat', controller: _reviewNotesController, maxLines: 3, readOnly: !_canEdit),
                    ],
                  ),
                  RiskFormSection(
                    title: 'Vedlegg',
                    icon: Icons.attach_file,
                    children: [
                      RiskAssessmentAttachmentsPanel(
                        imageUrls: _imageUrls,
                        documents: _documents,
                        readOnly: !_canEdit,
                        uploading: _uploading,
                        onUpload: _canEdit ? _uploadFiles : null,
                        onImagesChanged: _canEdit ? (v) => setState(() => _imageUrls = v) : null,
                        onDocumentsChanged: _canEdit ? (v) => setState(() => _documents = v) : null,
                      ),
                    ],
                  ),
                  if (_ra.treatedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Behandlet ${fmt.format(_ra.treatedAt!.toLocal())}',
                        style: DriftProTheme.caption,
                      ),
                    ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _statusBanner(DateFormat fmt) {
    final color = RiskAssessmentStatuses.chipColor(_status);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            RiskAssessmentStatuses.isTreated(_status) ? Icons.check_circle : Icons.pending_actions,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(RiskAssessmentStatuses.label(_status), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                if (_ra.responsiblePersonName != null)
                  Text('Ansvarlig: ${_ra.responsiblePersonName}', style: DriftProTheme.caption),
                if (_ra.deadline != null)
                  Text('Frist: ${fmt.format(_ra.deadline!)}', style: DriftProTheme.caption),
              ],
            ),
          ),
          if (_ra.attachmentCount > 0)
            Chip(
              label: Text('${_ra.attachmentCount} vedlegg'),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildAvvikBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DriftProTheme.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${_ra.avvikSignalCount} like avvik — revider analysen.',
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _comparisonSummary() {
    final initialScore = _initialP * _initialC;
    final residualScore = _residualP * _residualC;
    return Row(
      children: [
        Expanded(child: _scoreCol('Initial', initialScore, DriftProTheme.riskHigh)),
        const Icon(Icons.arrow_forward),
        Expanded(child: _scoreCol('Rest', residualScore, DriftProTheme.primaryGreen)),
      ],
    );
  }

  Widget _scoreCol(String label, int score, Color color) {
    return Column(
      children: [
        Text(label, style: DriftProTheme.labelSm),
        Text('$score', style: DriftProTheme.headingMd.copyWith(color: color)),
        Text(_ra.riskLevelForScore(score), style: DriftProTheme.caption),
      ],
    );
  }
}
