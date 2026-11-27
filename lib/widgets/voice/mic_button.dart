import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../voice/voice_controller.dart';

/// The big round microphone button. While listening, a ring around it grows
/// and shrinks with the loudness of the voice.
class MicButton extends StatelessWidget {
  const MicButton({
    super.key,
    required this.state,
    required this.soundLevel,
    required this.onPressed,
  });

  final VoiceState state;
  final ValueListenable<double> soundLevel;
  final VoidCallback onPressed;

  static const double _size = 120;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final listening = state == VoiceState.listening;
    final busy = state == VoiceState.sending || state == VoiceState.initializing;

    final Color background = listening ? scheme.error : scheme.primary;
    final Color foreground = listening ? scheme.onError : scheme.onPrimary;

    return Semantics(
      button: true,
      label: listening ? 'Stop listening' : 'Start voice input',
      child: SizedBox(
        width: _size + 64,
        height: _size + 64,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: soundLevel,
              builder: (context, level, _) {
                final ring = listening ? _size + 16 + level * 48 : _size;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: ring,
                  height: ring,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: background.withValues(alpha: listening ? 0.18 : 0.0),
                  ),
                );
              },
            ),
            Material(
              color: busy ? scheme.surfaceContainerHighest : background,
              shape: const CircleBorder(),
              elevation: listening ? 6 : 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : onPressed,
                child: SizedBox(
                  width: _size,
                  height: _size,
                  child: Center(
                    child: busy
                        ? SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(strokeWidth: 3, color: scheme.primary),
                          )
                        : Icon(listening ? Icons.stop_rounded : Icons.mic, size: 52, color: foreground),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
