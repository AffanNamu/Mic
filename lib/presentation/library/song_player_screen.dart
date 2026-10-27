import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../application/providers.dart';
import '../../core/format.dart';
import '../../core/text_direction.dart';
import '../../core/theme/deen_theme.dart';
import '../../domain/failures.dart';
import '../../domain/library/library.dart';
import '../../domain/playback/audio_player_port.dart';
import '../shared/dialogs.dart';

String providerLabel(String id) => switch (id) {
  'mureka' => 'Mureka',
  _ => id,
};

/// Plays a saved song through a short-lived signed link, with its lyrics.
class SongPlayerScreen extends ConsumerStatefulWidget {
  const SongPlayerScreen({required this.songId, super.key});

  final String songId;

  @override
  ConsumerState<SongPlayerScreen> createState() => _SongPlayerScreenState();
}

class _SongPlayerScreenState extends ConsumerState<SongPlayerScreen> {
  AudioPlayerPort? _player;
  StreamSubscription<PlaybackState>? _sub;
  PlaybackState _state = const PlaybackState();
  String? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final library = ref.read(songLibraryProvider);
    if (library == null) {
      setState(() {
        _loading = false;
        _loadError = 'The song library isn’t connected.';
      });
      return;
    }
    try {
      final signed = await library.audio(widget.songId);
      final player = _player ?? ref.read(audioPlayerFactoryProvider)();
      if (!mounted) {
        unawaited(player.dispose());
        return;
      }
      if (_player == null) {
        _player = player;
        _sub = player.states.listen((s) {
          if (mounted) setState(() => _state = s);
        });
      }
      await player.load(signed.url);
      if (mounted) setState(() => _loading = false);
    } on AppFailure catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'This song couldn’t be opened. Try again.';
        });
      }
    }
  }

  Future<void> _rename(SongRecord song) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: song.title),
    );
    if (title == null || title.isEmpty || title == song.title || !mounted) {
      return;
    }
    try {
      await ref.read(songLibraryProvider)!.rename(song.id, title);
      ref.invalidate(songsProvider);
    } on AppFailure catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _delete(SongRecord song) async {
    final ok = await confirmAction(
      context,
      title: 'Delete “${song.title}”?',
      message:
          'The song and its audio are removed from your account. This '
          'can’t be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(songLibraryProvider)!.delete(song.id);
      ref.invalidate(songsProvider);
      if (mounted) Navigator.of(context).pop();
    } on AppFailure catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(songsProvider);
    final song = songs.value?.where((s) => s.id == widget.songId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: DeenColors.background,
        title: Text(song?.title ?? 'Song', style: DeenText.sheetTitle),
        actions: [
          if (song != null) ...[
            IconButton(
              tooltip: 'Rename',
              icon: const Icon(LucideIcons.pencil),
              onPressed: () => _rename(song),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(LucideIcons.trash2),
              onPressed: () => _delete(song),
            ),
          ],
        ],
      ),
      body: song == null
          ? Center(
              child: songs.isLoading
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        songs.hasError
                            ? 'Your songs couldn’t be loaded.'
                            : 'This song is no longer in your library.',
                        style: DeenText.body,
                        textAlign: TextAlign.center,
                      ),
                    ),
            )
          : _body(song),
    );
  }

  Widget _body(SongRecord song) {
    final duration = _state.duration ?? song.duration;
    final max = duration?.inMilliseconds.toDouble() ?? 0;
    final pos = _state.position.inMilliseconds
        .toDouble()
        .clamp(0, max > 0 ? max : 0)
        .toDouble();
    final facts = [
      if (song.voiceName != null) 'Voice: ${song.voiceName}',
      song.language,
      'Made with ${providerLabel(song.provider)}',
    ].join(' · ');
    final lyricsDirection = detectTextDirection(song.lyrics);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(song.title, style: DeenText.screenTitle),
        const SizedBox(height: 6),
        Text(facts, style: DeenText.body),
        const SizedBox(height: 22),
        if (_loadError != null) ...[
          Text(_loadError!, style: DeenText.error),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _open,
              child: const Text('Try again'),
            ),
          ),
        ] else ...[
          Row(
            children: [
              IconButton.filled(
                tooltip: _state.playing ? 'Pause' : 'Play',
                iconSize: 30,
                onPressed: _loading || !_state.loaded
                    ? null
                    : () => _state.playing
                          ? _player!.pause()
                          : _playFromStartIfDone(),
                icon: Icon(
                  _loading || _state.buffering
                      ? LucideIcons.loader
                      : (_state.playing ? LucideIcons.pause : LucideIcons.play),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: pos,
                  max: max > 0 ? max : 1,
                  onChanged: max > 0
                      ? (v) => _player?.seek(Duration(milliseconds: v.round()))
                      : null,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Text(
              '${formatDuration(_state.position)} / '
              '${duration == null ? '–:––' : formatDuration(duration)}',
              style: DeenText.counter,
            ),
          ),
          if (_state.error != null) ...[
            const SizedBox(height: 8),
            Text(_state.error!, style: DeenText.error),
          ],
        ],
        const SizedBox(height: 26),
        Text('Lyrics', style: DeenText.sectionTitle),
        const SizedBox(height: 8),
        Directionality(
          textDirection: lyricsDirection ?? TextDirection.ltr,
          // SelectionArea + Text (not SelectableText): the lyrics stay
          // selectable and are exposed to screen readers.
          child: SelectionArea(child: Text(song.lyrics, style: DeenText.input)),
        ),
      ],
    );
  }

  Future<void> _playFromStartIfDone() async {
    final player = _player!;
    if (_state.completed) await player.seek(Duration.zero);
    await player.play();
  }
}

/// Owns its text controller so it is disposed only after the dialog has fully
/// left the screen (disposing it right after `showDialog` returns would break
/// the closing animation).
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DeenColors.panel,
      title: Text('Rename song', style: DeenText.sheetTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        style: DeenText.input,
        decoration: const InputDecoration(labelText: 'Title'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
