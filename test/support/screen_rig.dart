import 'package:deenvoice/app/app.dart';
import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/data/api/session_store.dart';
import 'package:deenvoice/data/local/memory_stores.dart';
import 'package:deenvoice/domain/auth/auth.dart';
import 'package:deenvoice/domain/library/library.dart';
import 'package:deenvoice/domain/links.dart';
import 'package:deenvoice/domain/local/local_stores.dart';
import 'package:deenvoice/domain/voice/voice_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'fakes_backend.dart';
import 'harness.dart';

/// The whole launch flow with a connected backend made of test doubles, on a
/// phone-shaped view with a status bar and a home indicator (as in the design
/// references). Used by the render and screen tests. The data is test data
/// that reproduces the reference frames; the shipped app shows only real data.
final screenNow = DateTime.utc(2026, 10, 27, 12);

Future<void> pumpScreens(
  WidgetTester tester, {
  required bool signedIn,
  bool onboarded = true,
  OnboardingStore? onboardingStore,
  ActivityStore? activityStore,
  LegalLinks? links,
  LinkOpener? opener,
  List<VoiceProfile> voices = const [readyOwnVoice],
  FakeVoiceRepository? voiceRepo,
  FakeGenerationService? generation,
  FakeAuthService? auth,
  FakeAccountService? account,
  MemorySessionStore? sessionStore,
  DraftStore? drafts,
  List<SongRecord> songs = const [],
  SongLibrary? library,
  List<GenerationJob> jobs = const [],
  FakeGenerationJobs? jobsFake,
  Size size = referenceLogicalSize,
}) async {
  tester.view.physicalSize = size * referencePixelRatio;
  tester.view.devicePixelRatio = referencePixelRatio;
  // The reference was captured on a phone with a status bar and a home
  // indicator.
  tester.view.padding = const FakeViewPadding(top: 88, bottom: 68);
  tester.view.viewPadding = const FakeViewPadding(top: 88, bottom: 68);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ...localStoreOverrides(
          drafts: drafts,
          onboarding:
              onboardingStore ?? MemoryOnboardingStore(completed: onboarded),
          activity: activityStore,
        ),
        if (links != null) legalLinksProvider.overrideWithValue(links),
        if (opener != null) linkOpenerProvider.overrideWithValue(opener),
        apiBaseUrlProvider.overrideWithValue('https://api.example.test'),
        clockProvider.overrideWithValue(() => screenNow),
        accountServiceProvider.overrideWithValue(
          account ?? FakeAccountService(),
        ),
        sessionStoreProvider.overrideWithValue(
          sessionStore ??
              MemorySessionStore(
                signedIn
                    ? AuthSession(
                        token: 't',
                        userId: 'u',
                        email: 'amina@example.com',
                        expiresAt: DateTime.utc(2030),
                      )
                    : null,
              ),
        ),
        songLibraryProvider.overrideWithValue(
          library ?? FakeSongLibrary(songs),
        ),
        generationJobsProvider.overrideWithValue(
          jobsFake ?? (FakeGenerationJobs()..recentJobs = jobs),
        ),
        creditsRepositoryProvider.overrideWithValue(FakeCreditsRepository(120)),
        authServiceProvider.overrideWithValue(auth ?? FakeAuthService()),
        consentSourceProvider.overrideWithValue(FakeConsentSource()),
        songGenerationServiceProvider.overrideWithValue(
          generation ?? FakeGenerationService(),
        ),
        voiceRepositoryProvider.overrideWithValue(
          voiceRepo ?? FakeVoiceRepository(voices),
        ),
      ],
      child: const RepaintBoundary(
        key: ValueKey('app-root'),
        child: DeenVoiceApp(),
      ),
    ),
  );
  await tester.runAsync(() async {
    final context = tester.element(find.byType(DeenVoiceApp));
    for (final a in [
      'assets/art/login_hero.webp',
      'assets/art/home_hero.webp',
      'assets/art/cover_1.webp',
      'assets/art/cover_2.webp',
      'assets/art/cover_3.webp',
      'assets/art/template_hausa.webp',
      'assets/art/template_arabic.webp',
      'assets/art/template_english.webp',
      'assets/art/template_mixed.webp',
      'assets/brand/deenvoice_icon_384.webp',
    ]) {
      await precacheImage(AssetImage(a), context);
    }
  });
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}
