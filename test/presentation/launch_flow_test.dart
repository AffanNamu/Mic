// The first things a person sees: the introduction, the welcome screen, and the
// choice between them and the app. Services are test doubles; these tests
// prove the app's behaviour, not any backend's.
import 'package:deenvoice/data/local/memory_stores.dart';
import 'package:deenvoice/domain/links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes_backend.dart';
import '../support/harness.dart';
import '../support/screen_rig.dart';

class _BrokenOnboardingStore extends MemoryOnboardingStore {
  @override
  Future<bool> isCompleted() async => throw StateError('storage unavailable');
}

Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  setUpAll(loadAppFonts);

  group('introduction', () {
    testWidgets('a first launch shows it, one page at a time', (tester) async {
      await pumpScreens(tester, signedIn: false, onboarded: false);
      expect(find.text('Songs in your own voice'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Welcome Back'), findsNothing);

      await tester.tap(find.text('Next'));
      await settle(tester);
      expect(find.text('Only voices you may use'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await settle(tester);
      expect(find.text('Hausa, Arabic and English'), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });

    testWidgets('what it says is true of the app: no promise of a result', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: false, onboarded: false);
      expect(find.textContaining('AI music engine'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await settle(tester);
      expect(find.textContaining('you confirm it is yours'), findsOneWidget);
      expect(
        find.textContaining('may keep its own copy'),
        findsOneWidget,
        reason: 'the provider-copy limit is disclosed up front',
      );
      await tester.tap(find.text('Next'));
      await settle(tester);
      expect(
        find.textContaining('depends on the music engine'),
        findsOneWidget,
        reason: 'language support is the engine\'s, and the app checks first',
      );
    });

    testWidgets('Get started records that it was seen and moves on', (
      tester,
    ) async {
      final store = MemoryOnboardingStore();
      await pumpScreens(tester, signedIn: false, onboardingStore: store);
      await tester.tap(find.text('Next'));
      await settle(tester);
      await tester.tap(find.text('Next'));
      await settle(tester);
      await tester.tap(find.text('Get started'));
      await settle(tester);
      expect(store.completed, isTrue);
      expect(find.text('Welcome Back'), findsOneWidget);
    });

    testWidgets('Skip does the same from the first page', (tester) async {
      final store = MemoryOnboardingStore();
      await pumpScreens(tester, signedIn: false, onboardingStore: store);
      await tester.tap(find.text('Skip'));
      await settle(tester);
      expect(store.completed, isTrue);
      expect(find.text('Welcome Back'), findsOneWidget);
    });

    testWidgets('Skip is not offered on the last page', (tester) async {
      await pumpScreens(tester, signedIn: false, onboarded: false);
      await tester.tap(find.text('Next'));
      await settle(tester);
      await tester.tap(find.text('Next'));
      await settle(tester);
      final skip = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Skip'),
      );
      expect(skip.onPressed, isNull);
    });

    testWidgets('once seen it is not shown again', (tester) async {
      await pumpScreens(
        tester,
        signedIn: false,
        onboardingStore: MemoryOnboardingStore(completed: true),
      );
      expect(find.text('Songs in your own voice'), findsNothing);
      expect(find.text('Welcome Back'), findsOneWidget);
    });

    testWidgets('the page number is announced to assistive technology', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpScreens(tester, signedIn: false, onboarded: false);
      expect(find.bySemanticsLabel('Page 1 of 3'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await settle(tester);
      expect(find.bySemanticsLabel('Page 2 of 3'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('if the device cannot say whether it was seen, the app opens', (
      tester,
    ) async {
      await pumpScreens(
        tester,
        signedIn: false,
        onboardingStore: _BrokenOnboardingStore(),
      );
      expect(find.text('Songs in your own voice'), findsNothing);
      expect(find.text('Welcome Back'), findsOneWidget);
    });
  });

  group('which screen opens', () {
    testWidgets('connected and signed out: the welcome screen', (tester) async {
      await pumpScreens(tester, signedIn: false);
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Create a Song'), findsNothing);
    });

    testWidgets('connected and signed in: Home', (tester) async {
      await pumpScreens(tester, signedIn: true);
      expect(find.text('Create a Song'), findsOneWidget);
      expect(find.text('Welcome Back'), findsNothing);
    });

    testWidgets(
      'no backend: straight to Home, and it says nothing is connected',
      (tester) async {
        await pumpProductionApp(tester, openCreate: false);
        expect(find.text('Create a Song'), findsOneWidget);
        expect(find.text('Welcome Back'), findsNothing);
        expect(find.textContaining('isn’t connected'), findsWidgets);
      },
    );

    testWidgets('no backend, first launch: the introduction, then Home', (
      tester,
    ) async {
      await pumpProductionApp(
        tester,
        openCreate: false,
        onboarding: MemoryOnboardingStore(),
      );
      expect(find.text('Songs in your own voice'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await settle(tester);
      expect(find.text('Create a Song'), findsOneWidget);
    });
  });

  group('welcome', () {
    testWidgets(
      'Google and Apple are shown but are not available, and say so',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpScreens(tester, signedIn: false);
        expect(
          find.bySemanticsLabel('Continue with Google, not available yet'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Continue with Apple, not available yet'),
          findsOneWidget,
        );
        expect(
          tester.getSemantics(
            find.bySemanticsLabel('Continue with Google, not available yet'),
          ),
          isSemantics(isButton: true, isEnabled: false),
        );
        expect(
          find.textContaining('Google and Apple sign-in aren’t available yet'),
          findsOneWidget,
        );
        // Tapping them changes nothing.
        await tester.tap(find.text('Continue with Google'));
        await settle(tester);
        expect(find.text('Welcome Back'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('email is the way in, and Back returns to the choices', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: false);
      await tester.tap(find.text('Continue with Email'));
      await settle(tester);
      expect(find.text('Sign in with email'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);

      await tester.tap(find.text('Create a new account'));
      await settle(tester);
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('At least 10 characters'), findsOneWidget);

      await tester.tap(find.text('Other ways to continue'));
      await settle(tester);
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Continue with Email'), findsOneWidget);
    });

    testWidgets('with no Terms or Privacy page it does not claim agreement', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: false);
      expect(
        find.textContaining('aren’t published for this build yet'),
        findsOneWidget,
      );
      expect(find.textContaining('you agree to our'), findsNothing);
    });

    testWidgets('one page without the other is still not agreement', (
      tester,
    ) async {
      await pumpScreens(
        tester,
        signedIn: false,
        links: LegalLinks(terms: Uri.parse('https://example.org/terms')),
      );
      expect(find.textContaining('you agree to our'), findsNothing);
      expect(
        find.textContaining('aren’t published for this build yet'),
        findsOneWidget,
      );
    });

    testWidgets('with both pages the links open them', (tester) async {
      final opener = FakeLinkOpener();
      await pumpScreens(
        tester,
        signedIn: false,
        opener: opener,
        links: LegalLinks(
          terms: Uri.parse('https://example.org/terms'),
          privacy: Uri.parse('https://example.org/privacy'),
        ),
      );
      expect(find.textContaining('you agree to our'), findsOneWidget);
      await tester.tapOnText(find.textRange.ofSubstring('Terms of Service'));
      await tester.tapOnText(find.textRange.ofSubstring('Privacy Policy'));
      expect(opener.opened, [
        Uri.parse('https://example.org/terms'),
        Uri.parse('https://example.org/privacy'),
      ]);
    });

    testWidgets('a page that cannot be opened says so', (tester) async {
      final opener = FakeLinkOpener(result: false);
      await pumpScreens(
        tester,
        signedIn: false,
        opener: opener,
        links: LegalLinks(
          terms: Uri.parse('https://example.org/terms'),
          privacy: Uri.parse('https://example.org/privacy'),
        ),
      );
      await tester.tapOnText(find.textRange.ofSubstring('Terms of Service'));
      await settle(tester, 4);
      expect(find.text('That page couldn’t be opened.'), findsOneWidget);
    });

    testWidgets('the language control says English is the only language', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: false);
      await tester.tap(find.text('English'));
      await settle(tester);
      expect(find.text('App language'), findsOneWidget);
      expect(find.textContaining('only available in English'), findsOneWidget);
    });

    testWidgets('the email form fits above the keyboard', (tester) async {
      await pumpScreens(tester, signedIn: false);
      await tester.tap(find.text('Continue with Email'));
      await settle(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    });
  });
}
