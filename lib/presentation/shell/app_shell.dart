import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../application/providers.dart';
import '../../core/theme/deen_theme.dart';
import '../../domain/library/library.dart';
import '../create_song/create_song_screen.dart';
import '../home/home_tab.dart';
import '../library/library_tab.dart';
import '../voices/my_voice_tab.dart';

enum ShellTab { home, myVoice, library }

/// What the signed-in user sees: Home, My Voice and Library behind a bottom
/// bar, with Create (the bar's "Create" and "+") opening full screen over it.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  ShellTab _tab = ShellTab.home;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void select(ShellTab tab) {
    if (tab != _tab) setState(() => _tab = tab);
  }

  Future<void> openCreate({CreateSection? section}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CreateSongScreen(initialSection: section),
        ),
      );

  /// While any job is unfinished keep asking; stop as soon as none is. This
  /// lives here, not in a tab, so the bell and the lists stay current wherever
  /// the user is.
  void _syncPolling(List<GenerationJob> jobs) {
    final active = jobs.any((j) => !j.status.isFinished);
    if (!active) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer.periodic(ref.read(jobPollIntervalProvider), (_) {
      ref.invalidate(recentJobsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(recentJobsProvider, (previous, next) {
      final jobs = next.value;
      if (jobs == null) return;
      _syncPolling(jobs);
      final before = previous?.value;
      final newlyDone =
          before != null &&
          before.any(
            (b) =>
                !b.status.isFinished &&
                jobs.any((j) => j.id == b.id && j.status.isFinished),
          );
      if (newlyDone) {
        ref.invalidate(songsProvider);
        ref.invalidate(creditBalanceProvider);
      }
    });

    // The system Back button on My Voice or Library goes to Home first; only
    // on Home does it leave the app.
    return PopScope(
      canPop: _tab == ShellTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) select(ShellTab.home);
      },
      child: Scaffold(
        extendBody: true,
        body: switch (_tab) {
          ShellTab.home => HomeTab(
            onOpenCreate: openCreate,
            onSelectTab: select,
          ),
          ShellTab.myVoice => const MyVoiceTab(),
          ShellTab.library => LibraryTab(onCreate: openCreate),
        },
        bottomNavigationBar: _NavBar(
          selected: _tab,
          onHome: () => select(ShellTab.home),
          onCreate: openCreate,
          onMyVoice: () => select(ShellTab.myVoice),
          onLibrary: () => select(ShellTab.library),
        ),
      ),
    );
  }
}

/// Room to leave at the bottom of a scrolling tab so its last item clears the
/// bar.
const double shellNavClearance = 108;

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.selected,
    required this.onHome,
    required this.onCreate,
    required this.onMyVoice,
    required this.onLibrary,
  });

  final ShellTab selected;
  final VoidCallback onHome;
  final VoidCallback onCreate;
  final VoidCallback onMyVoice;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xF2030F0D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: DeenColors.panelEdge, width: 0.8),
          left: BorderSide(color: DeenColors.panelEdge, width: 0.8),
          right: BorderSide(color: DeenColors.panelEdge, width: 0.8),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom > 0 ? bottom : 14),
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              _NavItem(
                icon: LucideIcons.house,
                label: 'Home',
                selected: selected == ShellTab.home,
                onTap: onHome,
              ),
              _NavItem(
                icon: LucideIcons.music,
                label: 'Create',
                selected: false,
                onTap: onCreate,
              ),
              Expanded(
                child: Center(child: _CreateButton(onTap: onCreate)),
              ),
              _NavItem(
                icon: LucideIcons.mic,
                label: 'My Voice',
                selected: selected == ShellTab.myVoice,
                onTap: onMyVoice,
              ),
              _NavItem(
                icon: LucideIcons.folder,
                label: 'Library',
                selected: selected == ShellTab.library,
                onTap: onLibrary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? DeenColors.gold : DeenColors.textSecondary;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                style: DeenText.cardTitle.copyWith(
                  color: color,
                  fontSize: 9.2,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Create a song',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 49,
          height: 49,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [DeenColors.goldBright, DeenColors.goldDeep],
            ),
            border: Border.all(color: Colors.black, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: DeenColors.gold.withValues(alpha: 0.35),
                blurRadius: 14,
              ),
            ],
          ),
          child: const Icon(
            LucideIcons.plus,
            size: 26,
            color: DeenColors.onGold,
          ),
        ),
      ),
    );
  }
}
