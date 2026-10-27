import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../application/providers.dart';
import '../../application/recording_controller.dart';
import '../../core/theme/deen_theme.dart';
import '../../domain/playback/audio_player_port.dart';
import '../../domain/recording/voice_recorder.dart';
import '../library/song_player_screen.dart' show formatDuration;
import '../shared/routes.dart';

/// Records a voice sample with the microphone, lets the user listen to it, and
/// returns it. Pops with a [RecordedVoice], or null if the user leaves.
///
/// Nothing is uploaded here: the caller decides what to do with the audio
/// (the add-voice flow enrolls it after consent has been given).
class RecordVoiceScreen extends ConsumerWidget {
  const RecordVoiceScreen({super.key});

  static Future<RecordedVoice?> open(BuildContext context) =>
      Navigator.of(context).push<RecordedVoice>(
        DeenPageRoute(builder: (_) => const RecordVoiceScreen()),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recordingControllerProvider);
    final controller = ref.read(recordingControllerProvider.notifier);
    final limits = switch (state) {
      RecordingInProgress(:final limits) => limits,
      RecordingReview(:final limits) => limits,
      _ => RecordingLimits.fromSeconds(
        ref.watch(capabilitiesProvider).value?.voiceSampleSeconds,
      ),
    };
    final busy = state is RecordingInProgress || state is RecordingStarting;

    return PopScope(
      // Leaving mid-recording throws the audio away rather than leaving the
      // microphone open.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(controller.release());
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: DeenColors.background,
          title: Text('Record your voice', style: DeenText.sheetTitle),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _Guidance(limits: limits),
              const SizedBox(height: 28),
              switch (state) {
                RecordingIdle() => _Idle(onStart: controller.start),
                RecordingStarting() => const _Starting(),
                RecordingInProgress() => _Recording(
                  state: state,
                  onStop: controller.stop,
                ),
                RecordingReview() => _Review(
                  state: state,
                  onAgain: controller.discard,
                  onUse: () => Navigator.of(context).pop(state.voice),
                ),
                RecordingError(:final message) => _Failed(
                  message: message,
                  onRetry: controller.start,
                ),
              },
              const SizedBox(height: 28),
              if (!busy)
                Text(
                  'Your recording stays on this device until you choose to add '
                  'the voice. Nothing is sent when you record.',
                  style: DeenText.sectionHint,
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _seconds(Duration d) => '${d.inSeconds} seconds';

class _Guidance extends StatelessWidget {
  const _Guidance({required this.limits});

  final RecordingLimits limits;

  @override
  Widget build(BuildContext context) {
    final bullets = [
      'Find a quiet place. No music and no other voices.',
      'Sing or speak naturally, a little closer than you would to a friend.',
      'Record ${_seconds(limits.min)} to ${_seconds(limits.max)}.',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DeenColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DeenColors.border, width: 0.75),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            header: true,
            child: Text(
              'A clean sample works best',
              style: DeenText.bodyStrong,
            ),
          ),
          const SizedBox(height: 8),
          for (final b in bullets)
            Semantics(
              container: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ExcludeSemantics(
                      child: Padding(
                        padding: EdgeInsets.only(top: 5, right: 8),
                        child: Icon(
                          Icons.circle,
                          size: 5,
                          color: DeenColors.gold,
                        ),
                      ),
                    ),
                    Expanded(child: Text(b, style: DeenText.body)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // The circle and its label are one control, so tapping either works.
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [DeenColors.goldBright, DeenColors.goldDeep],
                  ),
                  boxShadow: [
                    BoxShadow(color: Color(0x55F8C264), blurRadius: 24),
                  ],
                ),
                child: Icon(icon, size: 36, color: DeenColors.onGold),
              ),
              const SizedBox(height: 12),
              Text(label, style: DeenText.bodyStrong),
            ],
          ),
        ),
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Center(
    child: _RoundButton(
      icon: LucideIcons.mic,
      label: 'Start recording',
      onPressed: onStart,
    ),
  );
}

class _Starting extends StatelessWidget {
  const _Starting();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      children: [
        const ExcludeSemantics(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          container: true,
          liveRegion: true,
          child: Text('Waiting for the microphone…', style: DeenText.body),
        ),
      ],
    ),
  );
}

class _Recording extends StatelessWidget {
  const _Recording({required this.state, required this.onStop});

  final RecordingInProgress state;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final fraction =
        state.elapsed.inMilliseconds / state.limits.max.inMilliseconds;
    final reachedMin = state.elapsed >= state.limits.min;
    return Column(
      children: [
        Semantics(
          container: true,
          label:
              'Recording. ${state.elapsed.inSeconds} of '
              '${state.limits.max.inSeconds} seconds.',
          excludeSemantics: true,
          child: Column(
            children: [
              Text(
                formatDuration(state.elapsed),
                style: DeenText.screenTitle.copyWith(fontSize: 40),
              ),
              const SizedBox(height: 4),
              Text(
                'of ${formatDuration(state.limits.max)} maximum',
                style: DeenText.sectionHint,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ExcludeSemantics(child: _LevelMeter(level: state.level)),
        const SizedBox(height: 14),
        // The timer above already says "N of M seconds"; a second, unlabelled
        // progress announcement would only add noise.
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: DeenColors.border,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          container: true,
          child: Text(
            reachedMin
                ? 'Long enough. Stop whenever you are done.'
                : 'Keep going until at least ${formatDuration(state.limits.min)}.',
            style: DeenText.sectionHint,
          ),
        ),
        const SizedBox(height: 22),
        _RoundButton(
          icon: LucideIcons.square,
          label: 'Stop recording',
          onPressed: onStop,
        ),
      ],
    );
  }
}

/// A row of bars lit according to the live microphone level.
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    const bars = 28;
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < bars; i++)
            Container(
              width: 5,
              height: 6 + 38 * level * (0.45 + 0.55 * math.sin(i * 0.9).abs()),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: Color.lerp(
                  DeenColors.borderStrong,
                  DeenColors.gold,
                  level,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({
    required this.state,
    required this.onAgain,
    required this.onUse,
  });

  final RecordingReview state;
  final VoidCallback onAgain;
  final VoidCallback onUse;

  String? get _problem => switch (state.problem) {
    RecordingProblem.tooShort =>
      'That was ${state.voice.duration.inSeconds} seconds. It needs to be at '
          'least ${state.limits.min.inSeconds}. Record it again.',
    RecordingProblem.silent =>
      'We barely heard anything. Check that your microphone is on and not '
          'muted, then record again.',
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Preview(voice: state.voice),
        if (problem != null) ...[
          const SizedBox(height: 12),
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(problem, style: DeenText.error),
          ),
        ] else ...[
          const SizedBox(height: 12),
          Semantics(
            container: true,
            child: Text(
              'Listen to it. If your voice is clear and nothing else is '
              'audible, use it.',
              style: DeenText.body,
            ),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: problem == null ? onUse : null,
          icon: const Icon(LucideIcons.check, size: 16),
          label: const Text('Use this recording'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onAgain,
          icon: const Icon(LucideIcons.rotateCcw, size: 16),
          label: const Text('Record again'),
        ),
      ],
    );
  }
}

/// Plays the fresh recording back from memory.
class _Preview extends ConsumerStatefulWidget {
  const _Preview({required this.voice});

  final RecordedVoice voice;

  @override
  ConsumerState<_Preview> createState() => _PreviewState();
}

class _PreviewState extends ConsumerState<_Preview> {
  AudioPlayerPort? _player;
  StreamSubscription<PlaybackState>? _sub;
  PlaybackState _state = const PlaybackState();
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final player = ref.read(audioPlayerFactoryProvider)();
    _player = player;
    _sub = player.states.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    try {
      await player.loadBytes(widget.voice.wav, mimeType: 'audio/wav');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The recording couldn’t be played back here.');
      }
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    final player = _player;
    if (player == null) return;
    if (_state.playing) {
      await player.pause();
    } else {
      if (_state.completed) await player.seek(Duration.zero);
      await player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.voice.duration;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DeenColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DeenColors.border, width: 0.75),
      ),
      child: Row(
        children: [
          IconButton.filled(
            tooltip: _state.playing ? 'Pause recording' : 'Play recording',
            onPressed: _state.loaded ? _toggle : null,
            icon: Icon(_state.playing ? LucideIcons.pause : LucideIcons.play),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your recording', style: DeenText.bodyStrong),
                Text(
                  _error ??
                      '${formatDuration(_state.position)} / ${formatDuration(total)}',
                  style: _error == null ? DeenText.sectionHint : DeenText.error,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const ExcludeSemantics(
        child: Icon(LucideIcons.micOff, size: 32, color: DeenColors.danger),
      ),
      const SizedBox(height: 10),
      Semantics(
        container: true,
        liveRegion: true,
        child: Text(message, style: DeenText.body, textAlign: TextAlign.center),
      ),
      const SizedBox(height: 14),
      FilledButton(onPressed: onRetry, child: const Text('Try again')),
    ],
  );
}
