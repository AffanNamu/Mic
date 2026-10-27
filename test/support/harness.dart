import 'dart:io';
import 'dart:ui' as ui;

import 'package:deenvoice/app/app.dart';
import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/application/recording_controller.dart';
import 'package:deenvoice/data/local/memory_stores.dart';
import 'package:deenvoice/domain/local/local_stores.dart';
import 'package:deenvoice/domain/services.dart';
import 'package:deenvoice/presentation/create_song/create_song_screen.dart';
import 'package:deenvoice/presentation/create_song/widgets/voice_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'fakes_backend.dart';

/// The reference frame: 852 × 1846 px at 2x.
const referenceLogicalSize = Size(426, 923);
const referencePixelRatio = 2.0;

/// Loads the bundled fonts so tests render real glyphs instead of boxes.
Future<void> loadAppFonts() async {
  Future<void> load(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await load('Inter', ['assets/fonts/Inter.ttf']);
  await load('PlayfairDisplay', [
    'assets/fonts/PlayfairDisplay.ttf',
    'assets/fonts/PlayfairDisplay-Italic.ttf',
  ]);
  await load('NotoNaskhArabic', ['assets/fonts/NotoNaskhArabic.ttf']);
  await load('packages/lucide_icons_flutter/Lucide', [
    'packages/lucide_icons_flutter/assets/lucide.ttf',
  ]);
  // `Icons.*` glyphs (for example the Apple mark on the welcome screen).
  try {
    await load('MaterialIcons', ['fonts/MaterialIcons-Regular.otf']);
  } catch (_) {
    // Not bundled in this test environment: icons render as boxes, nothing else.
  }
  for (final weight in [300, 500]) {
    await load('packages/lucide_icons_flutter/Lucide$weight', [
      'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w$weight.ttf',
    ]);
  }
}

/// On-device state held in memory, so no test touches the platform's
/// key-value store (its plugin is absent under `flutter test`). Onboarding is
/// already complete unless a test says otherwise.
List<Override> localStoreOverrides({
  OnboardingStore? onboarding,
  DraftStore? drafts,
  ActivityStore? activity,
}) => [
  onboardingStoreProvider.overrideWithValue(
    onboarding ?? MemoryOnboardingStore(completed: true),
  ),
  draftStoreProvider.overrideWithValue(drafts ?? MemoryDraftStore()),
  activityStoreProvider.overrideWithValue(activity ?? MemoryActivityStore()),
];

class TestEnv {
  TestEnv({
    VoiceRepository? voices,
    CreditsRepository? credits,
    LyricsAssistant? lyrics,
    SongGenerationService? generation,
    TextFilePicker? textPicker,
    AudioFilePicker? audioPicker,
    this.recorder,
    this.useReferenceAvatars = false,
  }) : voices = voices ?? FakeVoiceRepository(const []),
       credits = credits ?? FakeCreditsRepository(0),
       lyrics = lyrics ?? FakeLyricsAssistant(),
       generation = generation ?? FakeGenerationService(),
       textPicker = textPicker ?? FakeTextFilePicker(null),
       audioPicker = audioPicker ?? FakeAudioFilePicker(null);

  final VoiceRepository voices;
  final CreditsRepository credits;
  final LyricsAssistant lyrics;
  final SongGenerationService generation;
  final TextFilePicker textPicker;
  final AudioFilePicker audioPicker;
  final bool useReferenceAvatars;

  /// When set, in-app recording uses this microphone and a fake audio player.
  final FakeVoiceRecorder? recorder;

  List<Override> get overrides => [
    ...localStoreOverrides(),
    if (recorder != null) ...[
      voiceRecorderFactoryProvider.overrideWithValue(() => recorder!),
      audioPlayerFactoryProvider.overrideWithValue(FakeAudioPlayer.new),
    ],
    voiceRepositoryProvider.overrideWithValue(voices),
    creditsRepositoryProvider.overrideWithValue(credits),
    lyricsAssistantProvider.overrideWithValue(lyrics),
    songGenerationServiceProvider.overrideWithValue(generation),
    textFilePickerProvider.overrideWithValue(textPicker),
    audioFilePickerProvider.overrideWithValue(audioPicker),
    if (useReferenceAvatars)
      voiceAvatarImageProvider.overrideWithValue(
        (url) => FileImage(
          File(
            url == 'avatar-a'
                ? 'test/fixtures/avatars/reference_avatar_a.png'
                : 'test/fixtures/avatars/reference_avatar_b.png',
          ),
        ),
      ),
  ];
}

/// Pumps the real app at the reference size with [env]'s services.
Future<void> pumpApp(
  WidgetTester tester,
  TestEnv env, {
  Size size = referenceLogicalSize,
  double pixelRatio = referencePixelRatio,
}) async {
  tester.view.physicalSize = size * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: env.overrides,
      child: const RepaintBoundary(
        key: ValueKey('app-root'),
        child: DeenVoiceApp(home: CreateSongScreen()),
      ),
    ),
  );
  await tester.runAsync(() async {
    final context = tester.element(find.byType(DeenVoiceApp));
    await precacheImage(
      const AssetImage('assets/art/masjid_header.webp'),
      context,
    );
    if (env.useReferenceAvatars) {
      for (final name in ['a', 'b']) {
        await precacheImage(
          FileImage(File('test/fixtures/avatars/reference_avatar_$name.png')),
          context,
        );
      }
    }
  });
  await tester.pumpAndSettle();
}

/// Writes the rendered app to [path] as a PNG.
Future<void> savePng(WidgetTester tester, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('app-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: referencePixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path)..createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// Pumps the app exactly as shipped (every backend service unconfigured), from
/// launch, and opens Create Song the way a user does: from Home. Only the
/// platform file pickers are replaced, because their plugins cannot run in a
/// widget test.
Future<void> pumpProductionApp(
  WidgetTester tester, {
  TextFilePicker? textPicker,
  AudioFilePicker? audioPicker,
  Size size = referenceLogicalSize,
  bool openCreate = true,
  OnboardingStore? onboarding,
}) async {
  tester.view.physicalSize = size * referencePixelRatio;
  tester.view.devicePixelRatio = referencePixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ...localStoreOverrides(onboarding: onboarding),
        if (textPicker != null)
          textFilePickerProvider.overrideWithValue(textPicker),
        if (audioPicker != null)
          audioFilePickerProvider.overrideWithValue(audioPicker),
      ],
      child: const DeenVoiceApp(),
    ),
  );
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage('assets/art/masjid_header.webp'),
      tester.element(find.byType(DeenVoiceApp)),
    );
  });
  await tester.pumpAndSettle();
  if (openCreate) {
    await tester.tap(find.text('Create a Song'));
    await tester.pumpAndSettle();
  }
}
