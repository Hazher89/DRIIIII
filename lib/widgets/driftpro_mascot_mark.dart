import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../core/config/driftpro_client.dart';
import '../core/constants/driftpro_brand.dart';

/// Dansende maskot i logoen. Bevegelsene byttes i tilfeldig rekkefølge.
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
          if (_use3d)
            AnimatedOpacity(
              opacity: _viewerReady ? 1 : 0,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOut,
              child: IgnorePointer(
                child: _DancerViewer3D(
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

class _DancerViewer3D extends StatelessWidget {
  const _DancerViewer3D({required this.onReady});

  final VoidCallback onReady;

  @override
  Widget build(BuildContext context) {
    return ModelViewer(
      key: const ValueKey('driftpro-dancer-v1'),
      src: DriftProBrand.mascotGlb,
      alt: 'DriftPro',
      backgroundColor: const Color(0x00000000),
      loading: Loading.eager,
      // Reveal as soon as the model is ready (avoids stuck poster in headers).
      reveal: Reveal.auto,
      autoPlay: true,
      autoRotate: false,
      cameraControls: false,
      disableZoom: true,
      disablePan: true,
      disableTap: true,
      touchAction: TouchAction.none,
      interactionPrompt: InteractionPrompt.none,
      cameraOrbit: '0deg 75deg 4.6m',
      cameraTarget: '0m 0.95m 0m',
      fieldOfView: '26deg',
      shadowIntensity: 0,
      exposure: 1.55,
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
          let order = [];
          let cursor = 0;
          let last = '';
          let started = false;

          const shuffle = (list) => {
            const a = list.slice();
            for (let i = a.length - 1; i > 0; i--) {
              const j = Math.floor(Math.random() * (i + 1));
              const t = a[i];
              a[i] = a[j];
              a[j] = t;
            }
            if (a.length > 1 && a[0] === last) {
              a.push(a.shift());
            }
            return a;
          };

          const nextClip = () => {
            const all = mv.availableAnimations || [];
            if (!all.length) return '';
            if (!order.length || cursor >= order.length) {
              order = shuffle(all);
              cursor = 0;
            }
            const name = order[cursor++];
            last = name;
            return name;
          };

          const playNext = () => {
            const name = nextClip();
            if (!name) return;
            mv.animationCrossfadeDuration = 0.7;
            mv.animationName = name;
            try { mv.play({ repetitions: 1 }); } catch (e) {}
          };

          const frame = () => {
            mv.exposure = 1.55;
            mv.fieldOfView = '26deg';
            mv.cameraTarget = '0m 0.95m 0m';
            mv.cameraOrbit = '0deg 75deg 4.6m';
            if (!started) {
              started = true;
              playNext();
            }
            try { DriftProMascot.postMessage('ready'); } catch (e) {}
          };

          mv.addEventListener('finished', playNext);
          mv.addEventListener('load', frame);
          mv.addEventListener('model-visibility', (ev) => {
            if (ev.detail && ev.detail.visible) frame();
          });
          if (mv.loaded) frame();
          setTimeout(frame, 1200);
        })();
      ''',
    );
  }
}

@Deprecated('Bruk DriftProMascotMark')
typedef DriftProCatMark = DriftProMascotMark;
