import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ai_access.dart';
import '../../core/claude_api.dart';
import '../../core/database.dart';
import '../../core/theme.dart';

/// Photo-based AI condition grader.
///
/// Flow:
/// 1. User picks/takes a photo of the sleeve and (optionally) the vinyl surface.
/// 2. We send to Claude vision via the Vercel proxy.
/// 3. Reveal the rating with breakdown + red flags.
/// 4. Optionally apply the rating to the record's `condition` field.
class ConditionGraderScreen extends StatefulWidget {
  final String recordId;
  final String? albumTitle;
  final String? artist;

  const ConditionGraderScreen({
    super.key,
    required this.recordId,
    this.albumTitle,
    this.artist,
  });

  @override
  State<ConditionGraderScreen> createState() => _ConditionGraderScreenState();
}

class _ConditionGraderScreenState extends State<ConditionGraderScreen> {
  final ImagePicker _picker = ImagePicker();

  File? _frontImage;
  File? _backImage;
  bool _grading = false;
  String? _error;
  ConditionGrade? _result;
  bool _applied = false;

  Future<void> _pickImage({required bool isFront, required ImageSource src}) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: src,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      setState(() {
        if (isFront) {
          _frontImage = File(file.path);
        } else {
          _backImage = File(file.path);
        }
        _result = null;
        _applied = false;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not load image: $e');
    }
  }

  Future<void> _grade() async {
    if (_frontImage == null) return;
    setState(() {
      _grading = true;
      _error = null;
      _result = null;
    });

    try {
      final grade = await ClaudeApi.instance.gradeCondition(
        frontImage: _frontImage!,
        backImage: _backImage,
        albumTitle: widget.albumTitle,
        artist: widget.artist,
      );
      await AiAccess.recordConditionUse();
      await AppDatabase.saveAiCondition(
        widget.recordId,
        jsonEncode(grade.toJson()),
        _frontImage!.path,
      );
      if (!mounted) return;
      setState(() {
        _result = grade;
        _grading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _grading = false;
        _error = 'Grading failed: $e';
      });
    }
  }

  Future<void> _applyToRecord() async {
    final grade = _result;
    if (grade == null) return;
    try {
      await AppDatabase.updateRecord(widget.recordId, {
        'condition': grade.rating,
      });
      if (!mounted) return;
      setState(() => _applied = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: SpinnerTheme.green,
          duration: const Duration(seconds: 2),
          content: Text(
            'Condition updated to ${grade.rating}',
            style: SpinnerTheme.nunito(
              size: 13, weight: FontWeight.w600, color: SpinnerTheme.white),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: SpinnerTheme.red,
          content: Text('Could not save: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      appBar: AppBar(
        backgroundColor: SpinnerTheme.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: SpinnerTheme.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'AI Condition Check',
          style: SpinnerTheme.nunito(
            size: 18, weight: FontWeight.w700, color: SpinnerTheme.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIntro(),
            const SizedBox(height: 16),
            _buildPhotoSlot(
              label: 'Sleeve / front photo',
              subtitle: 'Required',
              file: _frontImage,
              isFront: true,
            ),
            const SizedBox(height: 12),
            _buildPhotoSlot(
              label: 'Vinyl surface',
              subtitle: 'Optional — improves vinyl grade',
              file: _backImage,
              isFront: false,
            ),
            const SizedBox(height: 20),
            _buildGradeButton(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _buildError(_error!),
            ],
            if (_result != null) ...[
              const SizedBox(height: 24),
              _buildResultCard(_result!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SpinnerTheme.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.accent.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, color: SpinnerTheme.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Take a clear, well-lit photo. AI returns a Goldmine grade '
              '(M / NM / VG+ / VG / G+) with confidence and red flags.',
              style: SpinnerTheme.nunito(
                size: 13, color: SpinnerTheme.greyLight, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSlot({
    required String label,
    required String subtitle,
    required File? file,
    required bool isFront,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: SpinnerTheme.nunito(
                  size: 14, weight: FontWeight.w700, color: SpinnerTheme.white)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: SpinnerTheme.nunito(size: 12, color: SpinnerTheme.grey)),
          const SizedBox(height: 12),
          if (file != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(file, width: double.infinity, height: 200, fit: BoxFit.cover),
            )
          else
            Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                color: SpinnerTheme.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SpinnerTheme.border),
              ),
              child: Center(
                child: Icon(Icons.image_outlined,
                    size: 36, color: SpinnerTheme.grey),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(isFront: isFront, src: ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: Text(file == null ? 'Camera' : 'Retake',
                      style: SpinnerTheme.nunito(size: 13, weight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SpinnerTheme.accent,
                    side: BorderSide(color: SpinnerTheme.accent.withOpacity(0.6)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(isFront: isFront, src: ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text('Gallery',
                      style: SpinnerTheme.nunito(size: 13, weight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SpinnerTheme.greyLight,
                    side: BorderSide(color: SpinnerTheme.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGradeButton() {
    final canGrade = _frontImage != null && !_grading;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: canGrade ? _grade : null,
        style: FilledButton.styleFrom(
          backgroundColor: SpinnerTheme.accent,
          foregroundColor: SpinnerTheme.white,
          disabledBackgroundColor: SpinnerTheme.accent.withOpacity(0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: _grading
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.auto_awesome, size: 18),
        label: Text(
          _grading ? 'Analyzing…' : 'Grade Condition',
          style: SpinnerTheme.nunito(
            size: 15, weight: FontWeight.w700, color: SpinnerTheme.white),
        ),
      ),
    );
  }

  Widget _buildError(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SpinnerTheme.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SpinnerTheme.red.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: SpinnerTheme.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(ConditionGrade grade) {
    final color = _colorForRating(grade.rating);
    final pct = (grade.confidence * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.6)),
                ),
                child: Text(
                  grade.rating,
                  style: SpinnerTheme.nunito(
                    size: 24, weight: FontWeight.w800, color: color),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Grade',
                      style: SpinnerTheme.nunito(
                          size: 12, color: SpinnerTheme.grey)),
                  Text('$pct% confidence',
                      style: SpinnerTheme.nunito(
                          size: 14,
                          weight: FontWeight.w600,
                          color: SpinnerTheme.white)),
                ],
              ),
            ],
          ),
          if (grade.sleeve != null || grade.vinyl != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (grade.sleeve != null)
                  Expanded(child: _miniGrade('Sleeve', grade.sleeve!)),
                if (grade.sleeve != null && grade.vinyl != null)
                  const SizedBox(width: 8),
                if (grade.vinyl != null)
                  Expanded(child: _miniGrade('Vinyl', grade.vinyl!)),
              ],
            ),
          ],
          if (grade.notes != null && grade.notes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(grade.notes!,
                style: SpinnerTheme.nunito(
                    size: 13, color: SpinnerTheme.greyLight, height: 1.45)),
          ],
          if (grade.redFlags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SpinnerTheme.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SpinnerTheme.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: SpinnerTheme.red, size: 16),
                      const SizedBox(width: 6),
                      Text('Red flags',
                          style: SpinnerTheme.nunito(
                              size: 12,
                              weight: FontWeight.w700,
                              color: SpinnerTheme.red)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...grade.redFlags.map((f) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('• $f',
                            style: SpinnerTheme.nunito(
                                size: 12, color: SpinnerTheme.greyLight)),
                      )),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _applied ? null : _applyToRecord,
              style: FilledButton.styleFrom(
                backgroundColor:
                    _applied ? SpinnerTheme.green : SpinnerTheme.accent,
                disabledBackgroundColor: SpinnerTheme.green,
                foregroundColor: SpinnerTheme.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(
                  _applied ? Icons.check_circle : Icons.save_outlined,
                  size: 16),
              label: Text(
                _applied ? 'Saved to record' : 'Apply ${grade.rating} to record',
                style: SpinnerTheme.nunito(
                    size: 14, weight: FontWeight.w700, color: SpinnerTheme.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniGrade(String label, String rating) {
    final color = _colorForRating(rating);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: SpinnerTheme.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Row(
        children: [
          Text(label,
              style: SpinnerTheme.nunito(size: 12, color: SpinnerTheme.grey)),
          const Spacer(),
          Text(rating,
              style: SpinnerTheme.nunito(
                  size: 14, weight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Color _colorForRating(String r) {
    switch (r.toUpperCase()) {
      case 'M':
      case 'NM':
        return SpinnerTheme.green;
      case 'VG+':
        return SpinnerTheme.accent;
      case 'VG':
        return SpinnerTheme.amber;
      case 'G+':
      case 'G':
        return SpinnerTheme.red;
      default:
        return SpinnerTheme.greyLight;
    }
  }
}
