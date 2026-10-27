import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../application/providers.dart';
import '../../../core/theme/deen_theme.dart';
import '../../../domain/failures.dart';
import '../../../domain/services.dart';
import '../../../domain/voice/consent.dart';
import '../../shared/dialogs.dart';
import '../../voices/record_voice_screen.dart';

/// Voice enrollment entry point: captures explicit consent, then uploads an
/// authorized recording. In-app recording needs microphone support that is not
/// built yet, so it is offered as unavailable rather than faked.
Future<void> showAddVoiceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _AddVoiceSheet(),
  );
}

class _AddVoiceSheet extends ConsumerStatefulWidget {
  const _AddVoiceSheet();

  @override
  ConsumerState<_AddVoiceSheet> createState() => _AddVoiceSheetState();
}

class _AddVoiceSheetState extends ConsumerState<_AddVoiceSheet> {
  final _name = TextEditingController(text: 'My Voice');
  final _authorizedBy = TextEditingController();
  VoiceOwnership _ownership = VoiceOwnership.ownVoice;
  bool _consent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _authorizedBy.dispose();
    super.dispose();
  }

  bool get _needsOwnerName => _ownership == VoiceOwnership.authorizedByOwner;

  bool get _canSubmit =>
      _consent &&
      _name.text.trim().isNotEmpty &&
      (!_needsOwnerName || _authorizedBy.text.trim().isNotEmpty) &&
      !_busy;

  /// Picks a file, or records one in the app, then enrolls it.
  Future<void> _upload() => _enroll(() async {
    final picked = await ref.read(audioFilePickerProvider).pickAudio();
    return picked == null
        ? null
        : (fileName: picked.fileName, bytes: picked.bytes);
  });

  Future<void> _record() => _enroll(() async {
    final voice = await RecordVoiceScreen.open(context);
    return voice == null ? null : (fileName: voice.fileName, bytes: voice.wav);
  });

  /// [source] returns the audio to enroll, or null if the user backed out.
  /// Consent has already been given on this sheet either way.
  Future<void> _enroll(
    Future<({String fileName, Uint8List bytes})?> Function() source,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final statements = ref.read(consentStatementsProvider).value;
      final audio = await source();
      if (audio == null || !mounted) return;
      await ref
          .read(voiceRepositoryProvider)
          .enrollVoice(
            VoiceEnrollment(
              displayName: _name.text.trim(),
              fileName: audio.fileName,
              audio: audio.bytes,
              consent: VoiceConsent(
                ownership: _ownership,
                acceptedAt: DateTime.now().toUtc(),
                statementVersion: statements?.version,
                authorizedBy: _needsOwnerName
                    ? _authorizedBy.text.trim()
                    : null,
              ),
            ),
          );
      ref.invalidate(voicesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(
        context,
        'Voice submitted. We’ll let you know when it’s ready.',
      );
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The server's own wording when a backend is connected (it records a hash
  /// of exactly this text); otherwise the local wording, which records no
  /// version and cannot be submitted to a backend.
  String _consentText(AsyncValue<ConsentStatements?> statements) {
    final server = statements.value?.textFor(_ownership);
    if (server != null) return server;
    return _ownership == VoiceOwnership.ownVoice
        ? 'This is my voice, and I agree to DeenVoice processing '
              'this recording to create a voice profile. I can '
              'revoke this and delete the voice at any time.'
        : 'The speaker has given me explicit permission to create '
              'and use a voice profile from this recording. I can '
              'revoke this and delete the voice at any time.';
  }

  @override
  Widget build(BuildContext context) {
    final statements = ref.watch(consentStatementsProvider);
    final statementsFailed = statements.hasError;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text('Add New Voice', style: DeenText.sheetTitle),
              ),
              const SizedBox(height: 6),
              Text(
                'A voice profile lets DeenVoice sing your lyrics in a real '
                'person’s voice. Only add a voice you are allowed to use.',
                style: DeenText.body,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
                style: DeenText.input,
                decoration: const InputDecoration(
                  labelText: 'Voice name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<VoiceOwnership>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: VoiceOwnership.ownVoice,
                    label: Text('My own voice'),
                  ),
                  ButtonSegment(
                    value: VoiceOwnership.authorizedByOwner,
                    label: Text('Someone who allowed me'),
                  ),
                ],
                selected: {_ownership},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() => _ownership = s.first),
              ),
              if (_needsOwnerName) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _authorizedBy,
                  enabled: !_busy,
                  onChanged: (_) => setState(() {}),
                  style: DeenText.input,
                  decoration: const InputDecoration(
                    labelText: 'Whose voice is this?',
                    helperText: 'Their name, as they gave permission.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _consent,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _consent = v ?? false),
                title: Text(_consentText(statements), style: DeenText.body),
              ),
              if (statementsFailed) ...[
                const SizedBox(height: 6),
                Text(
                  'The consent statement couldn’t be loaded, so a voice '
                  'can’t be added right now.',
                  style: DeenText.error,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: DeenText.error),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed:
                    _canSubmit && !statementsFailed && !statements.isLoading
                    ? _upload
                    : null,
                icon: const Icon(LucideIcons.upload, size: 16),
                label: Text(_busy ? 'Uploading…' : 'Upload a recording'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed:
                    _canSubmit && !statementsFailed && !statements.isLoading
                    ? _record
                    : null,
                icon: const Icon(LucideIcons.mic, size: 16),
                label: const Text('Record now'),
              ),
              const SizedBox(height: 6),
              Text(
                'Record in the app, or upload a clear, quiet recording. You '
                'can listen to a recording before it is used.',
                style: DeenText.sectionHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
