// Profile: the account, what the app is connected to, the legal pages, and
// signing out. It states what is true and does not offer what does not exist.
import 'package:deenvoice/data/local/memory_stores.dart';
import 'package:deenvoice/domain/generation/generation_capabilities.dart';
import 'package:deenvoice/domain/links.dart';
import 'package:deenvoice/domain/local/local_stores.dart';
import 'package:deenvoice/domain/song/song_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../support/fakes.dart';
import '../support/fakes_backend.dart';
import '../support/harness.dart';
import '../support/screen_helpers.dart';
import '../support/screen_rig.dart';

final _links = LegalLinks(
  terms: Uri.parse('https://example.org/terms'),
  privacy: Uri.parse('https://example.org/privacy'),
);

void main() {
  setUpAll(loadAppFonts);

  group('connected', () {
    testWidgets('shows the account, balance, engine and language', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: true);
      await openProfile(tester);
      expect(find.text('amina@example.com'), findsOneWidget);
      expect(find.text('120 credits available'), findsOneWidget);
      expect(find.text('Test Engine · available'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets(
      'credits open the credits sheet, which says buying is unavailable',
      (tester) async {
        await pumpScreens(tester, signedIn: true);
        await openProfile(tester);
        await tapAndSettle(tester, find.text('Credits'));
        expect(
          find.textContaining('available in this build yet'),
          findsOneWidget,
        );
      },
    );

    testWidgets('an engine that is unavailable says why', (tester) async {
      await pumpScreens(
        tester,
        signedIn: true,
        generation: FakeGenerationService(
          capabilities: const GenerationCapabilities(
            engineName: 'Test Engine',
            songTypes: {},
            languages: {},
            voiceConditioning: false,
            advancedOptionIds: {},
            unavailableReason: 'Its credentials were rejected.',
          ),
        ),
      );
      await openProfile(tester);
      expect(
        find.text(
          'Test Engine · unavailable right now. Its credentials were rejected.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no engine connected is stated, not hidden', (tester) async {
      await pumpScreens(
        tester,
        signedIn: true,
        generation: FakeGenerationService(
          capabilities: GenerationCapabilities.none,
        ),
      );
      await openProfile(tester);
      expect(find.text('No music engine is connected.'), findsOneWidget);
    });

    testWidgets('Manage voices and Language open their screens', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: true);
      await openProfile(tester);
      await tapAndSettle(tester, find.text('Language'));
      expect(find.text('App language'), findsOneWidget);
      await tester.tapAt(const Offset(10, 60));
      await settle(tester);
      await tapAndSettle(tester, find.text('Manage voices'));
      expect(find.text('Manage Voices'), findsWidgets);
    });
  });

  group('legal pages', () {
    testWidgets(
      'are marked "Not published yet" and are not buttons when the build has none',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpScreens(tester, signedIn: true);
        await openProfile(tester);
        expect(find.text('Not published yet'), findsNWidgets(2));
        expect(
          tester.getSemantics(
            find.bySemanticsLabel('Terms of Service. Not published yet'),
          ),
          isSemantics(isButton: false),
        );
        expect(
          tester.getSemantics(
            find.bySemanticsLabel('Privacy Policy. Not published yet'),
          ),
          isSemantics(isButton: false),
        );
        handle.dispose();
      },
    );

    testWidgets('open the real pages when the build supplies them', (
      tester,
    ) async {
      final opener = FakeLinkOpener();
      await pumpScreens(tester, signedIn: true, links: _links, opener: opener);
      await openProfile(tester);
      expect(find.text('Not published yet'), findsNothing);
      await tapAndSettle(tester, find.text('Terms of Service'));
      await tapAndSettle(tester, find.text('Privacy Policy'));
      expect(opener.opened, [_links.terms, _links.privacy]);
    });

    testWidgets('a page that cannot be opened says so', (tester) async {
      await pumpScreens(
        tester,
        signedIn: true,
        links: _links,
        opener: FakeLinkOpener(result: false),
      );
      await openProfile(tester);
      await tapAndSettle(tester, find.text('Terms of Service'));
      expect(find.text('That page couldn’t be opened.'), findsOneWidget);
    });
  });

  group('signing out', () {
    testWidgets('asks first, and Cancel keeps the user signed in', (
      tester,
    ) async {
      final auth = FakeAuthService();
      await pumpScreens(tester, signedIn: true, auth: auth);
      await openProfile(tester);
      await tapAndSettle(tester, find.text('Sign out'));
      expect(find.text('Sign out?'), findsOneWidget);
      expect(find.textContaining('removed from this device'), findsOneWidget);
      await tapAndSettle(tester, find.text('Cancel'));
      expect(auth.signOuts, 0);
      expect(find.text('amina@example.com'), findsOneWidget);
    });

    testWidgets(
      'confirming ends the session on the server, wipes the draft and lands on Welcome',
      (tester) async {
        final auth = FakeAuthService();
        final drafts = MemoryDraftStore(
          SavedDraft(
            draft: const SongDraft(title: 'Private'),
            savedAt: screenNow,
            ownerId: 'u',
          ),
        );
        await pumpScreens(tester, signedIn: true, auth: auth, drafts: drafts);
        await openProfile(tester);
        await tapAndSettle(tester, find.text('Sign out'));
        await tapAndSettle(tester, find.text('Sign out').last);
        expect(auth.signOuts, 1);
        expect(drafts.saved, isNull);
        expect(find.text('Welcome Back'), findsOneWidget);
        expect(find.text('amina@example.com'), findsNothing);
      },
    );
  });

  group('not connected', () {
    testWidgets('there is no account, and no way to sign out of one', (
      tester,
    ) async {
      await pumpProductionApp(tester, openCreate: false);
      await tapAndSettle(tester, find.byIcon(LucideIcons.user));
      expect(find.text('Not signed in'), findsOneWidget);
      expect(find.textContaining('so there is no account'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
    });
  });
}
