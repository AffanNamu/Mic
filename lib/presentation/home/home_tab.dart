import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../application/activity.dart';
import '../../application/providers.dart';
import '../../application/session_controller.dart';
import '../../core/format.dart';
import '../../core/theme/deen_theme.dart';
import '../../core/widgets/brand.dart';
import '../../domain/failures.dart';
import '../../domain/library/library.dart';
import '../../domain/song/song_template.dart';
import '../activity/activity_screen.dart';
import '../create_song/create_song_screen.dart';
import '../library/song_player_screen.dart';
import '../profile/profile_screen.dart';
import '../shared/dialogs.dart';
import '../shell/app_shell.dart';

/// Home: the way into everything, with the user's real recent songs and their
/// unfinished draft. Nothing on it is made up; where there is nothing, it says
/// so.
class HomeTab extends ConsumerWidget {
  const HomeTab({
    super.key,
    required this.onOpenCreate,
    required this.onSelectTab,
  });

  final Future<void> Function({CreateSection? section}) onOpenCreate;
  final ValueChanged<ShellTab> onSelectTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      // Clear of the status bar even where the platform reports no inset.
      minimum: const EdgeInsets.only(top: 12),
      child: ListView(
        key: const PageStorageKey('home-list'),
        padding: const EdgeInsets.fromLTRB(15, 0, 15, shellNavClearance),
        children: [
          const _Header(),
          const SizedBox(height: 11),
          _HeroCard(onCreate: () => onOpenCreate()),
          const SizedBox(height: 10),
          _Shortcuts(onOpenCreate: onOpenCreate, onSelectTab: onSelectTab),
          const SizedBox(height: 18),
          _RecentSongs(
            onSeeAll: () => onSelectTab(ShellTab.library),
            onCreate: () => onOpenCreate(),
          ),
          const SizedBox(height: 14),
          _QuickStart(onOpenCreate: onOpenCreate),
          _ContinueWork(onContinue: () => onOpenCreate()),
        ],
      ),
    );
  }
}

// --- Header -----------------------------------------------------------------

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unseen = ref.watch(unseenActivityProvider);
    final email = ref.watch(sessionProvider).value?.email;
    return Row(
      children: [
        const DeenAppIcon(size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: const DeenWordmark(fontSize: 22.3),
              ),
              const SizedBox(height: 3),
              ExcludeSemantics(
                child: Text(
                  'AI NASHEEDS FOR A BRIGHTER UMMAH',
                  style: DeenText.tagline.copyWith(fontSize: 8.1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        _RoundButton(
          semanticLabel: unseen > 0 ? 'Activity, $unseen new' : 'Activity',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ActivityScreen()),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const Icon(
                LucideIcons.bell,
                size: 18,
                color: DeenColors.textPrimary,
              ),
              if (unseen > 0)
                Positioned(
                  top: 1,
                  right: 1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF4D4D),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _RoundButton(
          size: 38,
          semanticLabel: 'Profile',
          ring: DeenColors.goldBorder,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
          ),
          child: email == null || email.isEmpty
              ? const Icon(LucideIcons.user, size: 18, color: DeenColors.gold)
              : Text(
                  email.characters.first.toUpperCase(),
                  style: DeenText.sheetTitle.copyWith(
                    color: DeenColors.gold,
                    fontSize: 16,
                  ),
                ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    this.size = 34,
    this.ring,
  });

  final Widget child;
  final VoidCallback onTap;
  final String semanticLabel;
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: const Color(0xFF0C181A),
        shape: CircleBorder(
          side: BorderSide(
            color: ring ?? DeenColors.border,
            width: ring == null ? 0.9 : 1.6,
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

// --- Hero -------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 186,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: DeenColors.goldBorder.withValues(alpha: 0.4),
          width: 0.8,
        ),
        color: const Color(0xFF030F0D),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 200,
              child: ExcludeSemantics(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    colors: [Colors.transparent, Colors.black],
                    stops: [0, 0.38],
                  ).createShader(rect),
                  child: Image.asset(
                    'assets/art/home_hero.webp',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      'TURN YOUR VOICE INTO',
                      style: DeenText.tagline.copyWith(
                        fontSize: 8.4,
                        letterSpacing: 1.9,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    header: true,
                    child: Text.rich(
                      const TextSpan(
                        children: [
                          TextSpan(text: 'Beautiful\n'),
                          TextSpan(
                            text: 'Islamic Songs',
                            style: TextStyle(color: DeenColors.gold),
                          ),
                        ],
                      ),
                      style: DeenText.screenTitle.copyWith(
                        fontSize: 27,
                        height: 1.12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      'Use your own voice with AI to create inspiring '
                      'nasheeds, duas and more.',
                      style: DeenText.screenSubtitle.copyWith(
                        fontSize: 10.2,
                        height: 1.42,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      _GoldPill(
                        label: 'Create a Song',
                        trailing: LucideIcons.arrowRight,
                        onTap: onCreate,
                      ),
                      const Spacer(),
                      _HowItWorks(),
                    ],
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

class _GoldPill extends StatelessWidget {
  const _GoldPill({required this.label, required this.onTap, this.trailing});

  final String label;
  final VoidCallback onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: DeenColors.goldBright,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: DeenText.authButton.copyWith(
                    color: DeenColors.onGold,
                    fontSize: 11.5,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 7),
                  Icon(trailing, size: 14, color: DeenColors.onGold),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The reference has a "Watch Demo" video here. There is no video, so this
/// opens the written steps instead and says so.
class _HowItWorks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'How it works. See the steps',
      excludeSemantics: true,
      onTap: () => _showHowItWorks(context),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showHowItWorks(context),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: DeenColors.goldBorder, width: 1.2),
                  color: const Color(0x66000000),
                ),
                child: const Icon(
                  LucideIcons.listChecks,
                  size: 14,
                  color: DeenColors.gold,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'How it works',
                    style: DeenText.cardTitle.copyWith(fontSize: 9.6),
                  ),
                  Text(
                    'See the steps',
                    style: DeenText.cardDescription.copyWith(fontSize: 8.2),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showHowItWorks(BuildContext context) {
  const steps = [
    (
      'Add your voice',
      'Record or upload a clear sample. You confirm it is yours, or that its '
          'owner agreed.',
    ),
    (
      'Write your lyrics',
      'Type, paste or import a text file in Hausa, Arabic or English. The '
          'music engine decides what it can sing, and the app checks first.',
    ),
    ('Choose a style', 'Pick the language, genre, mood and length.'),
    (
      'Generate',
      'An AI music engine makes the song. It can take a few minutes, and the '
          'finished song appears in your library with the engine’s name on it.',
    ),
  ];
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('How DeenVoice works', style: DeenText.sheetTitle),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: DeenColors.gold,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: DeenText.stepNumber.copyWith(
                            color: DeenColors.onGold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(steps[i].$1, style: DeenText.bodyStrong),
                          const SizedBox(height: 2),
                          Text(steps[i].$2, style: DeenText.body),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// --- Shortcuts --------------------------------------------------------------

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.onOpenCreate, required this.onSelectTab});

  final Future<void> Function({CreateSection? section}) onOpenCreate;
  final ValueChanged<ShellTab> onSelectTab;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _Tile(
        icon: LucideIcons.music,
        title: 'Create Song',
        subtitle: 'Start creating\nwith AI',
        accent: const Color(0xFF3DDC84),
        fill: const Color(0xFF0B2D22),
        edge: const Color(0xFF1B6B4A),
        onTap: () => onOpenCreate(),
      ),
      _Tile(
        icon: LucideIcons.mic,
        title: 'My Voice',
        subtitle: 'Record or upload\nyour voice',
        accent: DeenColors.purple,
        fill: const Color(0xFF191433),
        edge: const Color(0xFF433873),
        onTap: () => onSelectTab(ShellTab.myVoice),
      ),
      _Tile(
        icon: LucideIcons.fileText,
        title: 'Write Lyrics',
        // The reference promises AI help here. The lyrics assistant is not
        // connected, so the tile promises only what it does.
        subtitle: 'Write or import\nyour lyrics',
        accent: DeenColors.gold,
        titleColor: DeenColors.gold,
        fill: const Color(0xFF241E10),
        edge: const Color(0xFF65501F),
        onTap: () => onOpenCreate(section: CreateSection.lyrics),
      ),
      _Tile(
        icon: LucideIcons.library,
        title: 'My Library',
        subtitle: 'Your songs\nand projects',
        accent: const Color(0xFF4C9BFF),
        fill: const Color(0xFF0C2338),
        edge: const Color(0xFF235074),
        onTap: () => onSelectTab(ShellTab.library),
      ),
    ];
    Widget row(List<Widget> items) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: items[i]),
          ],
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 340
          ? row(tiles)
          : Column(
              children: [
                row(tiles.sublist(0, 2)),
                const SizedBox(height: 8),
                row(tiles.sublist(2)),
              ],
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.fill,
    required this.edge,
    required this.onTap,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color fill;
  final Color edge;
  final Color? titleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Semantics(
      button: true,
      label: '$title. ${subtitle.replaceAll('\n', ' ')}',
      excludeSemantics: true,
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: edge, width: 0.9),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [fill, Color.lerp(fill, DeenColors.background, 0.6)!],
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: accent,
                  shadows: [
                    Shadow(
                      color: accent.withValues(alpha: 0.6),
                      blurRadius: 10,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DeenText.sectionTitle.copyWith(
                    fontSize: 11,
                    color: titleColor ?? DeenColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: DeenText.cardDescription.copyWith(fontSize: 8.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Sections ---------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.hint,
    this.action,
    this.onAction,
  });

  final String title;
  final String? hint;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: DeenText.sectionTitle.copyWith(fontSize: 16),
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    hint!,
                    style: DeenText.screenSubtitle.copyWith(fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
          if (action != null)
            Semantics(
              button: true,
              label: '$action $title',
              excludeSemantics: true,
              onTap: onAction,
              child: InkWell(
                onTap: onAction,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Text(
                    action!,
                    style: DeenText.chipLabelGold.copyWith(fontSize: 10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DeenColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DeenColors.border, width: 0.75),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: DeenText.body.copyWith(fontSize: 10.2)),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 10),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

// --- Recent songs -----------------------------------------------------------

class _RecentSongs extends ConsumerWidget {
  const _RecentSongs({required this.onSeeAll, required this.onCreate});

  final VoidCallback onSeeAll;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(songLibraryProvider) != null;
    final songs = ref.watch(songsProvider);
    final jobs = ref.watch(recentJobsProvider).value ?? const <GenerationJob>[];
    final inProgress = jobs.where((j) => !j.status.isFinished).toList();

    Widget body;
    if (!connected) {
      body = const _Note(
        text:
            'Songs you make will appear here. This build isn’t connected to a '
            'DeenVoice service yet.',
      );
    } else {
      body = songs.when(
        loading: () => const SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => _Note(
          text: error is AppFailure
              ? error.message
              : 'Your songs couldn’t be loaded.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(songsProvider),
        ),
        data: (list) {
          if (list.isEmpty && inProgress.isEmpty) {
            return _Note(
              text: 'No songs yet. Your finished songs will appear here.',
              actionLabel: 'Create',
              onAction: onCreate,
            );
          }
          final recent = list.take(8).toList();
          return SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              children: [
                for (final j in inProgress) _JobCard(job: j),
                for (final s in recent) _SongCard(song: s),
              ],
            ),
          );
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Recent Songs',
          action: connected ? 'See All' : null,
          onAction: onSeeAll,
        ),
        body,
      ],
    );
  }
}

const _covers = [
  'assets/art/cover_1.webp',
  'assets/art/cover_2.webp',
  'assets/art/cover_3.webp',
];

/// A song has no cover of its own. One of three generic pictures is chosen by
/// the song's id so the same song always looks the same.
String coverFor(String songId) {
  var h = 0;
  for (final unit in songId.codeUnits) {
    h = (h * 31 + unit) & 0x7fffffff;
  }
  return _covers[h % _covers.length];
}

class _SongCard extends StatelessWidget {
  const _SongCard({required this.song});

  final SongRecord song;

  @override
  Widget build(BuildContext context) {
    final detail = [
      titleCase(song.language),
      if (song.duration != null) formatDuration(song.duration!),
    ].join(' · ');
    final radius = BorderRadius.circular(14);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Semantics(
        button: true,
        label: 'Open ${song.title}',
        excludeSemantics: true,
        child: SizedBox(
          width: 131,
          child: Material(
            color: DeenColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: const BorderSide(color: DeenColors.border, width: 0.8),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SongPlayerScreen(songId: song.id),
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      coverFor(song.id),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xCC00100E)],
                          stops: [0.4, 1],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0x99000000),
                            border: Border.all(
                              color: DeenColors.textPrimary,
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            LucideIcons.play,
                            size: 11,
                            color: DeenColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DeenText.cardTitle.copyWith(
                                  fontSize: 9.6,
                                ),
                              ),
                              Text(
                                detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DeenText.cardDescription.copyWith(
                                  fontSize: 8,
                                  color: DeenColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});

  final GenerationJob job;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Semantics(
        label: '${job.title}. ${job.stage}',
        excludeSemantics: true,
        child: Container(
          width: 131,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: DeenColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: DeenColors.goldBorder.withValues(alpha: 0.5),
              width: 0.9,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(LucideIcons.loader, size: 16, color: DeenColors.gold),
              const Spacer(),
              Text(
                job.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DeenText.cardTitle.copyWith(fontSize: 9.6),
              ),
              const SizedBox(height: 2),
              Text(
                job.stage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DeenText.cardDescription.copyWith(fontSize: 8),
              ),
              const SizedBox(height: 7),
              const LinearProgressIndicator(minHeight: 2.5),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Quick start ------------------------------------------------------------

class _QuickStart extends ConsumerWidget {
  const _QuickStart({required this.onOpenCreate});

  final Future<void> Function({CreateSection? section}) onOpenCreate;

  static const _art = {
    SongTemplate.hausaNasheed: 'assets/art/template_hausa.webp',
    SongTemplate.arabicNasheed: 'assets/art/template_arabic.webp',
    SongTemplate.englishNasheed: 'assets/art/template_english.webp',
    SongTemplate.mixedLanguage: 'assets/art/template_mixed.webp',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider).value;
    final draft = ref.watch(songDraftProvider).draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'Quick Start',
          hint: 'Choose a template or start from scratch',
        ),
        SizedBox(
          height: 108,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              for (final t in SongTemplate.values)
                _TemplateCard(
                  template: t,
                  art: _art[t]!,
                  selected:
                      draft.language == t.language && draft.genre == t.genre,
                  unsupportedBy:
                      caps != null &&
                          caps.engineName != null &&
                          !caps.languages.contains(t.language)
                      ? caps.engineName
                      : null,
                  onTap: () {
                    ref.read(songDraftProvider.notifier).applyTemplate(t);
                    onOpenCreate();
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

final _templateDetail = DeenText.cardDescription.copyWith(
  fontSize: 7.2,
  color: DeenColors.textMuted,
  height: 1.25,
);

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.art,
    required this.selected,
    required this.unsupportedBy,
    required this.onTap,
  });

  final SongTemplate template;
  final String art;
  final bool selected;

  /// The engine that cannot sing this template's language, if known.
  final String? unsupportedBy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = unsupportedBy == null;
    final radius = BorderRadius.circular(14);
    final detail = enabled
        ? template.subtitle
        : 'Not supported by $unsupportedBy';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: selected,
        label: '${template.label}. $detail',
        excludeSemantics: true,
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: SizedBox(
            width: 95,
            child: Material(
              color: DeenColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(
                  color: selected ? const Color(0xFF3DDC84) : DeenColors.border,
                  width: selected ? 1.3 : 0.8,
                ),
              ),
              child: InkWell(
                borderRadius: radius,
                onTap: enabled ? onTap : null,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(
                          art,
                          height: 56,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 7, 2, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  template.label,
                                  maxLines: 1,
                                  style: DeenText.cardTitle.copyWith(
                                    fontSize: 8.4,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              LucideIcons.circleChevronRight,
                              size: 13,
                              color: DeenColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 2, 2, 0),
                        child: enabled
                            ? FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  detail,
                                  maxLines: 1,
                                  style: _templateDetail,
                                ),
                              )
                            : Text(
                                detail,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: _templateDetail,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Continue your work -----------------------------------------------------

class _ContinueWork extends ConsumerWidget {
  const _ContinueWork({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(songDraftProvider);
    final draft = state.draft;
    if (draft.title.trim().isEmpty && draft.lyrics.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final title = draft.title.trim().isEmpty
        ? 'Untitled Song'
        : draft.title.trim();
    final when = state.editedAt;
    final now = ref.read(clockProvider)();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'Continue Your Work'),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            decoration: BoxDecoration(
              color: DeenColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DeenColors.border, width: 0.8),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B2D22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.music,
                    size: 20,
                    color: Color(0xFF3DDC84),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DeenText.bodyStrong,
                      ),
                      if (when != null)
                        Text(
                          'Last edited ${formatAgo(when, now)}',
                          style: DeenText.sectionHint,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _GoldPill(label: 'Continue', onTap: onContinue),
                PopupMenuButton<String>(
                  tooltip: 'Draft options',
                  icon: const Icon(
                    LucideIcons.ellipsisVertical,
                    size: 18,
                    color: DeenColors.textSecondary,
                  ),
                  onSelected: (value) async {
                    if (value != 'discard') return;
                    final ok = await confirmAction(
                      context,
                      title: 'Discard this draft?',
                      message:
                          'Your title, lyrics and choices for this song will '
                          'be deleted from this device.',
                      confirmLabel: 'Discard',
                      destructive: true,
                    );
                    if (ok) ref.read(songDraftProvider.notifier).discard();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'discard',
                      child: Text('Discard draft'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
