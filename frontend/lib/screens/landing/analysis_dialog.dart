import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cacao/services/pick_image.dart';
import 'package:cacao/theme.dart';
import 'package:cacao/widgets/modal_frame.dart';

/// Landing-page demo of the analysis flow (simulated result).
class AnalysisDialog extends StatefulWidget {
  const AnalysisDialog({super.key});

  @override
  State<AnalysisDialog> createState() => _AnalysisDialogState();
}

class _AnalysisDialogState extends State<AnalysisDialog> {
  Uint8List? _bytes;
  bool _loading = false;
  bool _done = false;
  String _error = '';

  Future<void> _pick() async {
    try {
      // Same helper the signed-in upload screen uses, so this demo dialog
      // applies the jpg/png and 10 MB checks too.
      final picked = await pickCacaoImage(ImageSource.gallery);
      if (picked == null) return; // cancelled

      setState(() {
        _bytes = picked.bytes;
        _done = false;
        _error = '';
      });
    } on ImagePickException catch (error) {
      setState(() {
        _bytes = null;
        _done = false;
        _error = error.message;
      });
    } catch (_) {
      setState(() {
        _bytes = null;
        _done = false;
        _error = 'Could not read that image. Please try another one.';
      });
    }
  }

  Future<void> _run() async {
    if (_bytes == null) {
      return setState(() => _error = 'Please choose an image first.');
    }
    setState(() {
      _loading = true;
      _done = false;
      _error = '';
    });
    // Simulation only. The real call lives in the farmer upload screen.
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget tick(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('✓ $t', style: const TextStyle(fontSize: 13)),
    );

    return ModalFrame(
      maxWidth: 640,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CACAO ANALYSIS',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                letterSpacing: 2,
                color: AppColors.violet,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Analyze a cacao image',
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.brown800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Upload a clear image to simulate the CacaoGrade AI assessment.',
              style: TextStyle(color: AppColors.mutedBrown, fontSize: 13),
            ),
            const SizedBox(height: 18),
            InkWell(
              onTap: _pick,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF5FC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFC9A8F0),
                    width: 1.5,
                  ),
                ),
                child: _bytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _bytes!,
                          height: 180,
                          fit: BoxFit.contain,
                        ),
                      )
                    : const Column(
                        children: [
                          Icon(Icons.upload, size: 34, color: AppColors.violet),
                          SizedBox(height: 6),
                          Text(
                            'Tap to choose an image',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'JPG, PNG or WEBP',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.mutedBrown,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error,
                  style: const TextStyle(color: AppColors.red, fontSize: 12),
                ),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _run,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6D469B),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Analyze Image',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: AppColors.violet),
                      SizedBox(height: 10),
                      Text(
                        'AI is analyzing fermentation indicators...',
                        style: TextStyle(color: AppColors.mutedBrown),
                      ),
                    ],
                  ),
                ),
              ),
            if (_done)
              Container(
                margin: const EdgeInsets.only(top: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '✓ DEMO RESULT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Well-Fermented',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brown800,
                      ),
                    ),
                    const Text('Confidence: 94.8%'),
                    const Divider(height: 22),
                    const Text(
                      'Quality Assessment',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    tick('Good fermentation indicators'),
                    tick('Desirable color development'),
                    tick('Suitable for further drying and storage'),
                    const SizedBox(height: 8),
                    const Text(
                      'Recommendation',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Text(
                      'Continue proper drying and storage practices to maintain quality.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
