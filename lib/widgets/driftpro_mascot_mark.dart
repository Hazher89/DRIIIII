import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../core/config/driftpro_client.dart';
import '../core/constants/driftpro_brand.dart';

/// Porter Cat — poster alltid synlig, 3D fades inn (login + app-header).
class DriftProMascotMark extends StatefulWidget {
  const DriftProMascotMark({super.key, required this.size});

  final double size;

  static bool get isSupported =>
      DriftProClient.isWeb || DriftProClient.isMobile;

  @override
  State<DriftProMascotMark> createState() => _DriftProMascotMarkState();
}

class _DriftProMascotMarkState extends State<DriftProMascotMark> {
  bool _viewerReady = false;

  bool get _use3d => DriftProMascotMark.isSupported;

  @override
  void initState() {
    super.initState();
    // Fallback: iOS/WebView can sometimes miss the JS ready signal
    // (especially when rendered inside headers). If that happens,
    // we still want the 3D to appear smoothly.
    Future<void>.delayed(const Duration(milliseconds: 1800)).then((_) {
      if (mounted && !_viewerReady) {
        setState(() => _viewerReady = true);
      }
    });
  }

  @override
  void dispose() {
    // No-op: timer uses mounted check above.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.size;
    final h = widget.size * 1.5;

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          _PosterLayer(width: w, height: h, dimmed: _use3d && _viewerReady),
          if (_use3d)
            AnimatedOpacity(
              opacity: _viewerReady ? 1 : 0,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              child: IgnorePointer(
                child: _CatViewer3D(
                  onReady: () {
                    if (mounted && !_viewerReady) {
                      setState(() => _viewerReady = true);
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PosterLayer extends StatelessWidget {
  const _PosterLayer({
    required this.width,
    required this.height,
    required this.dimmed,
  });

  final double width;
  final double height;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: dimmed ? 0 : 1,
      duration: const Duration(milliseconds: 400),
      child: Image.asset(
        DriftProBrand.mascotPoster,
        width: width,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.pets_rounded,
          size: width * 0.7,
          color: const Color(0xFF1B5E20),
        ),
      ),
    );
  }
}

class _CatViewer3D extends StatelessWidget {
  const _CatViewer3D({required this.onReady});

  final VoidCallback onReady;

  @override
  Widget build(BuildContext context) {
    return ModelViewer(
      key: const ValueKey('porter-cat-3d-v7'),
      src: DriftProBrand.mascotGlb,
      alt: 'DriftPro Porter Cat',
      backgroundColor: const Color(0x00000000),
      loading: Loading.eager,
      // Reveal as soon as the model is ready (avoids stuck poster in headers).
      reveal: Reveal.auto,
      autoPlay: true,
      animationName: 'Armature|ArmatureAction',
      autoRotate: false,
      cameraControls: false,
      disableZoom: true,
      disablePan: true,
      disableTap: true,
      touchAction: TouchAction.none,
      interactionPrompt: InteractionPrompt.none,
      cameraOrbit: '0deg 75deg 3.2m',
      cameraTarget: '0m 0.02m -0.42m',
      fieldOfView: '42deg',
      shadowIntensity: 0,
      exposure: 1.35,
      environmentImage: 'neutral',
      debugLogging: kDebugMode,
      javascriptChannels: {
        JavascriptChannel(
          'DriftProMascot',
          onMessageReceived: (_) => onReady(),
        ),
      },
      relatedCss: '''
        :host, html, body {
          width: 100% !important;
          height: 100% !important;
          margin: 0 !important;
          padding: 0 !important;
          background: transparent !important;
          overflow: hidden !important;
          border: none !important;
        }
        model-viewer {
          width: 100% !important;
          height: 100% !important;
          background-color: transparent !important;
          --poster-color: transparent;
          --progress-bar-color: transparent;
          --progress-mask: transparent;
          pointer-events: none !important;
          overflow: hidden !important;
          border: none !important;
          outline: none !important;
          box-shadow: none !important;
        }
        .progress-bar,
        .slot.progress-bar,
        model-viewer::part(default-progress-bar) {
          display: none !important;
          opacity: 0 !important;
          height: 0 !important;
          visibility: hidden !important;
        }
      ''',
      relatedJs: r'''
        (function () {
          const mv = document.querySelector('model-viewer');
          if (!mv) return;
          const frame = () => {
            mv.cameraTarget = '0m 0.02m -0.42m';
            mv.cameraOrbit = '0deg 75deg 3.2m';
            mv.fieldOfView = '42deg';
            mv.exposure = 1.35;
            try { mv.play({ repetitions: Infinity }); } catch (e) {}
            try { DriftProMascot.postMessage('ready'); } catch (e) {}
          };
          mv.addEventListener('load', frame);
          mv.addEventListener('model-visibility', (ev) => {
            if (ev.detail && ev.detail.visible) frame();
          });
          if (mv.loaded) frame();
          setTimeout(frame, 2000);
        })();
      ''',
    );
  }
}

@Deprecated('Bruk DriftProMascotMark')
typedef DriftProCatMark = DriftProMascotMark;
