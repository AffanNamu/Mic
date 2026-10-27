import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../application/providers.dart';
import '../../application/session_controller.dart';
import '../../core/theme/deen_theme.dart';
import '../../domain/failures.dart';
import '../create_song/sheets/credits_sheet.dart';
import '../shared/dialogs.dart';
import '../shared/language_sheet.dart';
import '../voices/manage_voices_screen.dart';

/// Account and app information, and sign-out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: 'Sign out?',
      message:
          'You will need to sign in again. A draft you have not generated '
          'will be removed from this device.',
      confirmLabel: 'Sign out',
    );
    if (!ok || !context.mounted) return;
    // The profile is a pushed screen; return to the root first so signing out
    // lands on the welcome screen rather than behind this one.
    Navigator.of(context).popUntil((route) => route.isFirst);
    await ref.read(sessionProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final balance = ref.watch(creditBalanceProvider);
    final caps = ref.watch(capabilitiesProvider);
    final links = ref.watch(legalLinksProvider);
    final connected = ref.watch(apiBaseUrlProvider).isNotEmpty;

    Future<void> openLink(Uri? url) async {
      if (url == null) return;
      final ok = await ref.read(linkOpenerProvider).open(url);
      if (!ok && context.mounted) {
        showMessage(context, 'That page couldn’t be opened.');
      }
    }

    final engine = caps.when(
      data: (c) => c.engineName == null
          ? 'No music engine is connected.'
          : c.unavailableReason != null
          ? '${c.engineName} · unavailable right now. ${c.unavailableReason}'
          : '${c.engineName} · available',
      loading: () => 'Checking…',
      error: (e, _) =>
          e is AppFailure ? e.message : 'The engine couldn’t be checked.',
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: DeenColors.background,
        title: Text('Profile', style: DeenText.sheetTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Identity(email: session?.email, connected: connected),
          const SizedBox(height: 18),
          _Group(
            children: [
              _Item(
                icon: LucideIcons.zap,
                title: 'Credits',
                detail: balance.when(
                  data: (n) => '$n ${n == 1 ? 'credit' : 'credits'} available',
                  loading: () => 'Loading…',
                  error: (e, _) => e is AppFailure ? e.message : '–',
                ),
                onTap: () => showCreditsSheet(context),
              ),
              _Item(
                icon: LucideIcons.mic,
                title: 'Manage voices',
                detail: 'Your saved voices',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ManageVoicesScreen(),
                  ),
                ),
              ),
              _Item(
                icon: LucideIcons.sparkles,
                title: 'Music engine',
                detail: engine,
              ),
              _Item(
                icon: LucideIcons.globe,
                title: 'Language',
                detail: 'English',
                onTap: () => showLanguageSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Group(
            children: [
              _Item(
                icon: LucideIcons.fileText,
                title: 'Terms of Service',
                detail: links.terms == null ? 'Not published yet' : null,
                external: links.terms != null,
                onTap: links.terms == null ? null : () => openLink(links.terms),
              ),
              _Item(
                icon: LucideIcons.shield,
                title: 'Privacy Policy',
                detail: links.privacy == null ? 'Not published yet' : null,
                external: links.privacy != null,
                onTap: links.privacy == null
                    ? null
                    : () => openLink(links.privacy),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'DeenVoice makes songs with an AI music engine from your lyrics '
              'and a voice you are allowed to use. Each song in your library '
              'names the engine that made it.',
              style: DeenText.sectionHint,
            ),
          ),
          if (session != null) ...[
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: () => _signOut(context, ref),
              icon: const Icon(LucideIcons.logOut, size: 16),
              label: const Text('Sign out'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.email, required this.connected});

  final String? email;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final signedIn = email != null && email!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DeenColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DeenColors.border, width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0C181A),
              border: Border.all(color: DeenColors.goldBorder, width: 1.6),
            ),
            child: signedIn
                ? ExcludeSemantics(
                    child: Text(
                      email!.characters.first.toUpperCase(),
                      style: DeenText.sheetTitle.copyWith(
                        color: DeenColors.gold,
                        fontSize: 24,
                      ),
                    ),
                  )
                : const Icon(LucideIcons.user, color: DeenColors.gold),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signedIn ? email! : 'Not signed in',
                  style: DeenText.bodyStrong,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  signedIn
                      ? 'Your voices and songs are private to this account.'
                      : connected
                      ? 'Sign in to save songs and voices.'
                      : 'This build isn’t connected to a DeenVoice service, '
                            'so there is no account.',
                  style: DeenText.sectionHint,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: DeenColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: DeenColors.border, width: 0.8),
    ),
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            const Divider(height: 1, thickness: 0.6, color: DeenColors.border),
          children[i],
        ],
      ],
    ),
  );
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    this.detail,
    this.onTap,
    this.external = false,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? onTap;
  final bool external;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      enabled: onTap != null || detail != null,
      label: [title, ?detail].join('. '),
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 19, color: DeenColors.gold),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: DeenText.bodyStrong),
                    if (detail != null)
                      Text(detail!, style: DeenText.sectionHint),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  external
                      ? LucideIcons.externalLink
                      : LucideIcons.chevronRight,
                  size: 16,
                  color: DeenColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
