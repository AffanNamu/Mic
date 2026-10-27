import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/generation_controller.dart';
import '../../application/providers.dart';
import '../../core/theme/deen_theme.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/section_header.dart';
import '../../domain/song/song_validation.dart';
import '../shared/dialogs.dart';
import '../voices/manage_voices_screen.dart';
import 'sheets/add_voice_sheet.dart';
import 'sheets/credits_sheet.dart';
import 'sheets/generation_result_sheet.dart';
import 'sheets/job_progress_sheet.dart';
import 'widgets/advanced_options_panel.dart';
import 'widgets/create_song_header.dart';
import 'widgets/generate_button.dart';
import 'widgets/lyrics_section.dart';
import 'widgets/song_details_form.dart';
import 'widgets/song_type_selector.dart';
import 'widgets/voice_selector.dart';

/// Where Create Song should open scrolled to, when not at the top.
enum CreateSection { lyrics, voice }

/// Step 1–4 of making a song: type, voice, lyrics, details, then Generate.
class CreateSongScreen extends ConsumerStatefulWidget {
  const CreateSongScreen({super.key, this.initialSection});

  final CreateSection? initialSection;

  @override
  ConsumerState<CreateSongScreen> createState() => _CreateSongScreenState();
}

class _CreateSongScreenState extends ConsumerState<CreateSongScreen> {
  final _typeKey = GlobalKey();
  final _voiceKey = GlobalKey();
  final _lyricsKey = GlobalKey();
  final _detailsKey = GlobalKey();
  final _generateKey = GlobalKey();

  /// Inline errors only appear once the user has tried to generate.
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    final section = widget.initialSection;
    if (section != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollTo(section == CreateSection.lyrics ? _lyricsKey : _voiceKey);
        }
      });
    }
  }

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.04,
    );
  }

  void _onStepTap(SongStep step) => _scrollTo(switch (step) {
    SongStep.details => _typeKey,
    SongStep.lyrics => _lyricsKey,
    SongStep.voiceStyle => _voiceKey,
    SongStep.generate => _generateKey,
  });

  void _onGenerate() {
    setState(() => _attempted = true);
    ref.read(generationControllerProvider.notifier).submit();
  }

  void _onGenerationChanged(
    GenerationUiState? previous,
    GenerationUiState next,
  ) {
    switch (next) {
      case GenerationRejected(:final problem):
        _showProblem(problem);
        ref.read(generationControllerProvider.notifier).dismiss();
      case GenerationAccepted(:final receipt):
        ref.read(generationControllerProvider.notifier).dismiss();
        // With a backend connected the sheet follows the real job; without
        // one (tests) it only reports the receipt.
        if (ref.read(generationJobsProvider) != null) {
          showJobProgressSheet(context, receipt);
        } else {
          showGenerationAcceptedSheet(context, receipt);
        }
      case GenerationIdle() || GenerationSubmitting():
        break;
    }
  }

  void _showProblem(GenerationProblem problem) {
    switch (problem) {
      case InvalidDraft(:final issues):
        final first = issues.first;
        _scrollTo(switch (first.field) {
          DraftField.title => _detailsKey,
          DraftField.lyrics => _lyricsKey,
          DraftField.voice => _voiceKey,
          DraftField.engine => _generateKey,
        });
        showMessage(context, first.message);
      case EngineUnavailable():
        showMessage(
          context,
          'Song generation isn’t available yet because no generation engine '
          'is connected. Your settings are kept.',
        );
      case CreditsUnverified(:final message):
        showMessage(context, 'Couldn’t check your credits. $message');
      case InsufficientCredits(:final balance, :final required):
        showMessage(
          context,
          'You need $required ${required == 1 ? 'credit' : 'credits'} but have '
          '$balance.',
        );
        showCreditsSheet(context);
      case SubmitFailed(:final message):
        showMessage(context, message);
    }
  }

  String? _issue(List<DraftIssue> issues, DraftField field) {
    if (!_attempted) return null;
    return issues.where((i) => i.field == field).firstOrNull?.message;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(generationControllerProvider, _onGenerationChanged);
    final issues = ref.watch(draftIssuesProvider);
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: DeenColors.background,
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CreateSongHeader(
              onBack: () => Navigator.of(context).maybePop(),
              onCreditsTap: () => showCreditsSheet(context),
              onStepTap: _onStepTap,
            ),
            _Panel(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 11, 13, 20.5 + safeBottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KeyedSubtree(
                      key: _typeKey,
                      child: const SectionHeader(
                        title: 'Song Type',
                        hint: 'Select the type of song you want to create',
                      ),
                    ),
                    const SizedBox(height: 8.9),
                    const SongTypeSelector(),
                    const SizedBox(height: 12.5),
                    const _Divider(),
                    const SizedBox(height: 6.5),
                    KeyedSubtree(
                      key: _voiceKey,
                      child: SectionHeader(
                        title: 'Choose Voice',
                        titleShift: -2.5,
                        hint: 'Use your own voice or select a saved voice profile',
                        trailing: PillButton(
                          label: 'Manage Voices',
                          textStyle: DeenText.chipLabelGold.copyWith(
                            fontSize: 8.6,
                          ),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ManageVoicesScreen(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6.5),
                    VoiceSelector(onAddVoice: () => showAddVoiceSheet(context)),
                    if (_issue(issues, DraftField.voice) case final error?)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(error, style: DeenText.error),
                      ),
                    const SizedBox(height: 17.5),
                    KeyedSubtree(
                      key: _lyricsKey,
                      child: LyricsSection(
                        errorText: _issue(issues, DraftField.lyrics),
                      ),
                    ),
                    const SizedBox(height: 17.5),
                    KeyedSubtree(
                      key: _detailsKey,
                      child: SongDetailsForm(
                        titleError: _issue(issues, DraftField.title),
                      ),
                    ),
                    const SizedBox(height: 13.5),
                    const AdvancedOptionsPanel(),
                    const SizedBox(height: 13),
                    KeyedSubtree(
                      key: _generateKey,
                      child: GenerateButton(onPressed: _onGenerate),
                    ),
                    if (_issue(issues, DraftField.engine) case final error?)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(error, style: DeenText.error),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rounded content sheet below the header, with its faint top edge.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: DeenColors.panel),
        child: Stack(
          children: [
            child,
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 0.75,
              child: ColoredBox(color: DeenColors.panelEdge),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 0.5, child: ColoredBox(color: Color(0x14FFFFFF)));
}
