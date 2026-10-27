import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../application/session_controller.dart';
import '../../core/theme/deen_theme.dart';
import '../../domain/auth/auth.dart';
import '../../domain/failures.dart';

/// Deleting the account, after saying exactly what that removes, what the
/// service keeps and what the music provider may still hold. Asks for the
/// password again, so being signed in on a borrowed phone is not enough.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = ref.read(sessionProvider.notifier);
    AccountDeletion result;
    try {
      result = await session.deleteAccount(_password.text);
    } on AppFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Something went wrong. Your account was not deleted.';
        });
      }
      return;
    }
    if (!mounted) return;
    // It is gone on the server. Say what that meant before leaving.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DeletedDialog(result: result),
    );
    // Forgetting the session closes every screen and shows the welcome screen.
    await session.finishAccountDeletion();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: DeenColors.background,
        title: Text('Delete account', style: DeenText.sheetTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DeenColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: DeenColors.danger.withValues(alpha: 0.5),
                width: 0.9,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  LucideIcons.triangleAlert,
                  size: 20,
                  color: DeenColors.danger,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This can’t be undone. Your songs and voices can’t be '
                    'brought back.',
                    style: DeenText.bodyStrong,
                  ),
                ),
              ],
            ),
          ),
          const _Section(
            title: 'What is deleted',
            lines: [
              'Your email address and password.',
              'Your voice recordings, here and, where the music provider '
                  'allows it, at the provider.',
              'Your songs, their lyrics and titles.',
              'Your draft and settings on this device.',
            ],
          ),
          const _Section(
            title: 'What we keep',
            lines: [
              'A record that credits were granted and used, under an '
                  'anonymous id, with no name, email or recording.',
              'A record that consent was given for each voice (the wording '
                  'version, its hash and the time), without your IP address, '
                  'device details or the speaker’s name.',
              'A log of account events under the same anonymous id.',
            ],
          ),
          const _Section(
            title: 'What the music provider may keep',
            lines: [
              'We ask the provider to delete each recording. Some providers '
                  'can’t do this automatically. If yours can’t, we tell you '
                  'afterwards, and its copy stays under its own terms until '
                  'you ask the provider to remove it.',
            ],
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _delete(),
            style: DeenText.input,
            decoration: const InputDecoration(
              labelText: 'Your password',
              helperText: 'Enter it again to confirm.',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(_error!, style: DeenText.error),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _busy || _password.text.isEmpty ? null : _delete,
              style: FilledButton.styleFrom(
                backgroundColor: DeenColors.danger,
                foregroundColor: DeenColors.onGold,
              ),
              child: Text(_busy ? 'Deleting…' : 'Delete my account'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Keep my account'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: DeenText.sectionTitle),
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExcludeSemantics(
                    child: Padding(
                      padding: EdgeInsets.only(top: 6, right: 10),
                      child: Icon(
                        Icons.circle,
                        size: 5,
                        color: DeenColors.gold,
                      ),
                    ),
                  ),
                  Expanded(child: Text(line, style: DeenText.body)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DeletedDialog extends StatelessWidget {
  const _DeletedDialog({required this.result});

  final AccountDeletion result;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DeenColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: DeenColors.panelEdge),
      ),
      title: Text('Your account was deleted', style: DeenText.sheetTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.disclosure, style: DeenText.body),
            if (result.kept.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Kept', style: DeenText.bodyStrong),
              const SizedBox(height: 6),
              for (final k in result.kept)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(k, style: DeenText.sectionHint),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
