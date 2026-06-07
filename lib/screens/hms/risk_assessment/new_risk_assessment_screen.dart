import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/hms/hms_templates.dart';
import '../../../core/services/hms/hms_ecosystem_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/risk_assessment.dart';
import '../../../models/risk_assessment_status.dart';
import '../widgets/hms_responsible_picker.dart';
import '../widgets/interactive_risk_matrix.dart';
import 'widgets/risk_assessment_attachments_panel.dart';
import 'widgets/risk_form_section.dart';
import '../../../models/ticket_assignee_options.dart';

class NewRiskAssessmentScreen extends StatefulWidget {
  final HmsRiskTemplate? template;
  final int? initialProbability;
  final int? initialConsequence;

  const NewRiskAssessmentScreen({
    super.key,
    this.template,
    this.initialProbability,
    this.initialConsequence,
  });

  @override
  State<NewRiskAssessmentScreen> createState() => _NewRiskAssessmentScreenState();
}

class _NewRiskAssessmentScreenState extends State<NewRiskAssessmentScreen> {
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
  final _measuresController = TextEditingController();
  final _residualMeasuresController = TextEditingController();
  final _treatmentNotesController = TextEditingController();
  final _reviewNotesController = TextEditingController();
  final _scenarioController = TextEditingController();

  late int _probability;
  late int _consequence;
  late int _residualProbability;
  late int _residualConsequence;
  String _status = RiskAssessmentStatuses.aktiv;
  String? _isoStandard;
  DateTime? _deadline;
  DateTime? _reviewDate;

  bool _isSubmitting = false;
  bool _uploading = false;
  bool _loadingResponsible = true;
  String? _responsibleId;
  TicketAssigneeOptions _assignees = const TicketAssigneeOptions();
  List<String> _imageUrls = [];
  List<RiskDocumentAttachment> _documents = [];

  static const _isoOptions = ['ISO 9001', 'ISO 14001', 'ISO 45001', 'ISO 9001/14001', 'Internkontroll'];

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    _probability = widget.initialProbability ?? t?.probability ?? 3;
    _consequence = widget.initialConsequence ?? t?.consequence ?? 3;
    _residualProbability = _probability > 1 ? _probability - 1 : 1;
    _residualConsequence = _consequence > 1 ? _consequence - 1 : 1;
    if (t != null) {
      _titleController.text = t.title;
      _areaController.text = t.area;
      _descController.text = t.description;
      _existingMeasuresController.text = t.existingMeasures;
      _measuresController.text = t.proposedMeasures;
      _scenarioController.text = t.id;
    }
    _loadResponsibleOptions();
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
      _measuresController,
      _residualMeasuresController,
      _treatmentNotesController,
      _reviewNotesController,
      _scenarioController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadResponsibleOptions() async {
    setState(() => _loadingResponsible = true);
    try {
      final options = await HmsResponsiblePicker.loadOptions();
      if (!mounted) return;
      setState(() {
        _assignees = options;
        _responsibleId ??= options.defaultAssigneeId;
        _loadingResponsible = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingResponsible = false);
    }
  }

  Future<void> _pickDate({required bool deadline}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      if (deadline) {
        _deadline = picked;
      } else {
        _reviewDate = picked;
      }
    });
  }

  Future<void> _uploadFiles(List<PlatformFile> files, bool isImage) async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId == null) return;
    setState(() => _uploading = true);
    try {
      for (final f in files) {
        if (f.bytes == null) continue;
        final url = await HmsEcosystemService.uploadRiskAssessmentFile(
          companyId: companyId,
          bytes: f.bytes!,
          fileName: f.name,
        );
        if (isImage) {
          _imageUrls.add(url);
        } else {
          _documents.add(RiskDocumentAttachment(
            url: url,
            fileName: f.name,
            mimeType: _mimeForName(f.name),
            uploadedAt: DateTime.now(),
          ));
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opplasting feilet: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String? _mimeForName(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'txt' => 'text/plain',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final score = _probability * _consequence;

    return Scaffold(
      appBar: AppBar(title: const Text('Ny risikoanalyse')),
      bottomNavigationBar: _buildBottomBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            RiskFormSection(
              title: 'Identifikasjon',
              subtitle: 'Hva vurderes, hvor og i hvilket system',
              icon: Icons.fact_check_outlined,
              children: [
                riskTextField(label: 'Tittel *', controller: _titleController, hint: 'F.eks. Arbeid i høyden'),
                riskTextField(label: 'Område / avdeling', controller: _areaController),
                riskTextField(label: 'Nøyaktig sted', controller: _locationDetailController, hint: 'Bygg, hall, adresse'),
                riskTextField(label: 'Aktivitet / prosess', controller: _activityProcessController),
                riskTextField(label: 'Scenario / kategori', controller: _scenarioController, hint: 'F.eks. transport, kjemikalier'),
                riskDropdown<String?>(
                  label: 'ISO / styringssystem',
                  value: _isoStandard,
                  items: [null, ..._isoOptions],
                  labelBuilder: (v) => v ?? 'Velg standard',
                  onChanged: (v) => setState(() => _isoStandard = v),
                ),
                riskDropdown<String>(
                  label: 'Status',
                  value: _status,
                  items: RiskAssessmentStatuses.all,
                  labelBuilder: RiskAssessmentStatuses.label,
                  onChanged: (v) => setState(() => _status = v ?? RiskAssessmentStatuses.aktiv),
                ),
                HmsResponsiblePicker(
                  selectedId: _responsibleId,
                  onChanged: (v) => setState(() => _responsibleId = v),
                  options: _assignees,
                  loading: _loadingResponsible,
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(deadline: true),
                        icon: const Icon(Icons.event),
                        label: Text(_deadline == null
                            ? 'Frist'
                            : 'Frist: ${_deadline!.day}.${_deadline!.month}.${_deadline!.year}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(deadline: false),
                        icon: const Icon(Icons.update),
                        label: Text(_reviewDate == null
                            ? 'Revisjonsdato'
                            : 'Revisjon: ${_reviewDate!.day}.${_reviewDate!.month}.${_reviewDate!.year}'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            RiskFormSection(
              title: 'Fare og konsekvens',
              subtitle: 'Beskriv faremoment, berørte parter og lovgrunnlag',
              icon: Icons.warning_amber_outlined,
              children: [
                riskTextField(label: 'Faremoment / beskrivelse *', controller: _descController, maxLines: 4),
                riskTextField(label: 'Farekilde', controller: _hazardSourceController, maxLines: 2),
                riskTextField(label: 'Berørte personer / grupper', controller: _affectedPersonsController, maxLines: 2),
                riskTextField(label: 'Rotårsak (hvis kjent)', controller: _rootCauseController, maxLines: 2),
                riskTextField(label: 'Lov / forskrift / krav', controller: _legalRefController, maxLines: 2),
                riskTextField(
                  label: 'Vurderingsmetode',
                  controller: _evalMethodController,
                  hint: 'F.eks. 5×5 matrise, FMEA, ROS-workshop',
                ),
              ],
            ),
            RiskFormSection(
              title: 'Risikomatrise (5×5)',
              subtitle: 'Initial risiko vs. rest-risiko etter tiltak',
              icon: Icons.grid_on,
              children: [
                DualRiskMatrixPanel(
                  initialP: _probability,
                  initialC: _consequence,
                  residualP: _residualProbability,
                  residualC: _residualConsequence,
                  onInitialP: (v) => setState(() => _probability = v),
                  onInitialC: (v) => setState(() => _consequence = v),
                  onResidualP: (v) => setState(() => _residualProbability = v),
                  onResidualC: (v) => setState(() => _residualConsequence = v),
                ),
                const SizedBox(height: 12),
                _scoreBadge(score),
              ],
            ),
            RiskFormSection(
              title: 'Tiltak og oppfølging',
              subtitle: 'Eksisterende, planlagte og gjennomførte tiltak',
              icon: Icons.shield_outlined,
              children: [
                riskTextField(label: 'Eksisterende tiltak', controller: _existingMeasuresController, maxLines: 3),
                riskTextField(label: 'Foreslåtte tiltak', controller: _measuresController, maxLines: 3),
                riskTextField(label: 'Gjennomførte tiltak (rest)', controller: _residualMeasuresController, maxLines: 3),
                riskTextField(label: 'Behandlingsnotat', controller: _treatmentNotesController, maxLines: 3),
                riskTextField(label: 'Revisjonsnotat / oppfølging', controller: _reviewNotesController, maxLines: 3),
              ],
            ),
            RiskFormSection(
              title: 'Vedlegg',
              subtitle: 'Bilder og dokumenter knyttet til analysen',
              icon: Icons.attach_file,
              children: [
                RiskAssessmentAttachmentsPanel(
                  imageUrls: _imageUrls,
                  documents: _documents,
                  uploading: _uploading,
                  onUpload: _uploadFiles,
                  onImagesChanged: (v) => setState(() => _imageUrls = v),
                  onDocumentsChanged: (v) => setState(() => _documents = v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _scoreBadge(int score) {
    Color color;
    String label;
    if (score <= 4) {
      color = DriftProTheme.riskLow;
      label = 'Lav risiko';
    } else if (score <= 9) {
      color = DriftProTheme.riskMedium;
      label = 'Middels risiko';
    } else if (score <= 14) {
      color = DriftProTheme.riskHigh;
      label = 'Høy risiko';
    } else {
      color = DriftProTheme.riskCritical;
      label = 'Kritisk risiko';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: color, child: Text('$score', style: const TextStyle(color: Colors.white))),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          if (score >= 15) ...[
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Verneombud varsles', style: TextStyle(fontSize: 11, color: DriftProTheme.error)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _isSubmitting ? null : _save,
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
          child: _isSubmitting
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Lagre risikoanalyse'),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tittel er påkrevd')),
      );
      return;
    }
    if (_responsibleId == null || _responsibleId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg ansvarlig')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      if (profile == null) return;

      final ra = RiskAssessment(
        id: const Uuid().v4(),
        companyId: profile.companyId!,
        departmentId: profile.departmentId,
        createdBy: profile.id,
        title: _titleController.text.trim(),
        area: _areaController.text.trim().isEmpty ? null : _areaController.text.trim(),
        locationDetail: _locationDetailController.text.trim().isEmpty ? null : _locationDetailController.text.trim(),
        activityProcess: _activityProcessController.text.trim().isEmpty ? null : _activityProcessController.text.trim(),
        description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
        hazardSource: _hazardSourceController.text.trim().isEmpty ? null : _hazardSourceController.text.trim(),
        affectedPersons: _affectedPersonsController.text.trim().isEmpty ? null : _affectedPersonsController.text.trim(),
        rootCause: _rootCauseController.text.trim().isEmpty ? null : _rootCauseController.text.trim(),
        legalReference: _legalRefController.text.trim().isEmpty ? null : _legalRefController.text.trim(),
        evaluationMethod: _evalMethodController.text.trim().isEmpty ? null : _evalMethodController.text.trim(),
        existingMeasures: _existingMeasuresController.text.trim().isEmpty ? null : _existingMeasuresController.text.trim(),
        proposedMeasures: _measuresController.text.trim().isEmpty ? null : _measuresController.text.trim(),
        residualMeasures: _residualMeasuresController.text.trim().isEmpty ? null : _residualMeasuresController.text.trim(),
        treatmentNotes: _treatmentNotesController.text.trim().isEmpty ? null : _treatmentNotesController.text.trim(),
        reviewNotes: _reviewNotesController.text.trim().isEmpty ? null : _reviewNotesController.text.trim(),
        isoStandard: _isoStandard,
        scenarioCategory: _scenarioController.text.trim().isEmpty ? null : _scenarioController.text.trim(),
        probability: _probability,
        consequence: _consequence,
        initialProbability: _probability,
        initialConsequence: _consequence,
        residualProbability: _residualProbability,
        residualConsequence: _residualConsequence,
        responsiblePerson: _responsibleId,
        imageUrls: _imageUrls,
        documentUrls: _documents,
        status: _status,
        deadline: _deadline,
        reviewDate: _reviewDate,
        templateKey: widget.template?.id,
      );

      await SupabaseService.createRiskAssessment(ra);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Risikoanalyse lagret')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
