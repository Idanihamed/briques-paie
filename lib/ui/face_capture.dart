import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'glass.dart';

/// Ouvre la caméra et retourne [count] photos JPEG en base64 (ou null si annulé).
/// Les photos sont envoyées au serveur qui calcule la signature du visage puis les jette :
/// elles ne sont ni enregistrées sur l'appareil ni conservées.
Future<List<String>?> captureFaces(
  BuildContext context, {
  required String title,
  int count = 1,
  List<String> prompts = const [],
}) {
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FaceCaptureDialog(title: title, count: count, prompts: prompts),
  );
}

class _FaceCaptureDialog extends StatefulWidget {
  final String title;
  final int count;
  final List<String> prompts;
  const _FaceCaptureDialog({required this.title, required this.count, required this.prompts});

  @override
  State<_FaceCaptureDialog> createState() => _FaceCaptureDialogState();
}

class _FaceCaptureDialogState extends State<_FaceCaptureDialog> {
  CameraController? _controller;
  String? _error;
  bool _busy = false;
  final List<String> _shots = [];

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('noCamera', 'Aucune caméra détectée');
      final cam = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);

      // Certaines caméras refusent une résolution : on essaie des réglages de plus en plus simples.
      CameraException? last;
      for (final preset in [ResolutionPreset.medium, ResolutionPreset.low, ResolutionPreset.max]) {
        final c = CameraController(cam, preset, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
        try {
          await c.initialize();
          if (!mounted) {
            await c.dispose();
            return;
          }
          setState(() => _controller = c);
          return;
        } on CameraException catch (e) {
          last = e;
          await c.dispose();
          if (e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt') break;
        }
      }
      throw last ?? CameraException('unknown', 'Initialisation impossible');
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt'
            ? 'Accès à la caméra refusé. Autorisez la caméra dans le navigateur ou les paramètres.'
            : 'Caméra indisponible (${e.code}).');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Caméra indisponible (${e.runtimeType}).');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      _shots.add(base64Encode(await file.readAsBytes()));
      if (_shots.length >= widget.count) {
        if (mounted) Navigator.pop(context, _shots);
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'La capture a échoué. Réessayez.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final step = _shots.length;
    final prompt = widget.prompts.length > step ? widget.prompts[step] : 'Regardez la caméra, visage bien éclairé';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: GlassCard(
        radius: 28,
        padding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            if (widget.count > 1)
              Text('Photo ${step + 1} sur ${widget.count}', style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: errColor)),
                        ),
                      )
                    : _controller == null
                        ? const Center(child: CircularProgressIndicator())
                        : Stack(fit: StackFit.expand, children: [
                            // L'aperçu garde le vrai ratio de la caméra (portrait ou paysage), recadré pour remplir.
                            FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(
                                width: 100 * _controller!.value.aspectRatio,
                                height: 100,
                                child: CameraPreview(_controller!),
                              ),
                            ),
                            // Guide de cadrage
                            Center(
                              child: Container(
                                width: 190,
                                height: 250,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(120),
                                  border: Border.all(color: accentSoft.withValues(alpha: 0.9), width: 2.5),
                                ),
                              ),
                            ),
                          ]),
              ),
            ),
            const SizedBox(height: 12),
            Text(prompt, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GradientButton(
                  icon: Icons.camera_alt_rounded,
                  label: _busy ? 'Patientez…' : 'Capturer',
                                    onPressed: _controller == null || _busy || _error != null ? null : _shoot,
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
