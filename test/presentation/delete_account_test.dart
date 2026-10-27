// Deleting an account, from Profile. The server is a test double; these tests
// prove what the app asks, shows and clears, not what the backend deletes (its
// own suite scans the whole database for that).
import 'dart:async';

import 'package:deenvoice/application/session_controller.dart';
import 'package:deenvoice/data/api/session_store.dart';
import 'package:deenvoice/data/local/memory_stores.dart';
import 'package:deenvoice/domain/auth/auth.dart';
import 'package:deenvoice/domain/failures.dart';
import 'package:deenvoice/domain/local/local_stores.dart';
import 'package:deenvoice/domain/song/song_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../support/fakes_backend.dart';
import '../support/harness.dart';
import '../support/screen_helpers.dart';
import '../support/screen_rig.dart';

Future<void> openDelete(WidgetTester tester) async {
  await openProfile(tester);
  await tester.ensureVisible(find.text('Delete account'));
  await tapAndSettle(tester, find.text('Delete account'));
}

/// The form is longer than the screen: scroll to a control before using it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tapAndSettle(tester, finder);
}

Finder passwordField() => find.widgetWithText(TextField, 'Your password');

FilledButton deleteButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, 'Delete my account'),
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('is offered on Profile only when there is an account', (
    tester,
  ) async {
    await pumpScreens(tester, signedIn: true);
    await openProfile(tester);
    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets('with no backend there is no account to delete', (tester) async {
    await pumpProductionApp(tester, openCreate: false);
    await tapAndSettle(tester, find.byIcon(LucideIcons.user));
    expect(find.text('Delete account'), findsNothing);
  });

  testWidgets(
    'says what is deleted, what is kept and what the provider may keep',
    (tester) async {
      await pumpScreens(tester, signedIn: true);
      await openDelete(tester);
      expect(find.textContaining('This can’t be undone'), findsOneWidget);
      expect(find.text('What is deleted'), findsOneWidget);
      expect(
        find.textContaining('Your voice recordings, here and'),
        findsOneWidget,
      );
      expect(find.text('What we keep'), findsOneWidget);
      expect(find.textContaining('without your IP address'), findsOneWidget);
      expect(find.text('What the music provider may keep'), findsOneWidget);
      expect(
        find.textContaining('Some providers can’t do this automatically'),
        findsOneWidget,
      );
    },
  );

  testWidgets('cannot be sent without a password, and the password is hidden', (
    tester,
  ) async {
    final account = FakeAccountService();
    await pumpScreens(tester, signedIn: true, account: account);
    await openDelete(tester);
    expect(deleteButton(tester).onPressed, isNull);
    expect(tester.widget<TextField>(passwordField()).obscureText, isTrue);
    await tester.enterText(passwordField(), 'hunter2 hunter2');
    await tester.pump();
    expect(deleteButton(tester).onPressed, isNotNull);
    expect(account.passwords, isEmpty);
  });

  testWidgets(
    'a wrong password is explained here; nothing is deleted and the user stays signed in',
    (tester) async {
      final account = FakeAccountService()
        ..failure = const ServiceFailure('That password isn’t right.');
      final store = MemorySessionStore(
        AuthSession(
          token: 't',
          userId: 'u',
          email: 'amina@example.com',
          expiresAt: DateTime.utc(2030),
        ),
      );
      await pumpScreens(
        tester,
        signedIn: true,
        account: account,
        sessionStore: store,
      );
      await openDelete(tester);
      await tester.enterText(passwordField(), 'not it, sorry');
      await tapVisible(tester, find.text('Delete my account'));
      expect(find.text('That password isn’t right.'), findsOneWidget);
      expect(find.text('Delete account'), findsWidgets);
      expect(find.text('Welcome Back'), findsNothing);
      expect((await store.read())?.email, 'amina@example.com');
      expect(
        deleteButton(tester).onPressed,
        isNotNull,
        reason: 'it can be tried again',
      );
    },
  );

  testWidgets('a song still being made, or no connection, is said plainly', (
    tester,
  ) async {
    final account = FakeAccountService()
      ..failure = const ServiceFailure(
        'A song is still being made. Wait for it to finish, then delete your account.',
      );
    await pumpScreens(tester, signedIn: true, account: account);
    await openDelete(tester);
    await tester.enterText(passwordField(), 'hunter2 hunter2');
    await tapVisible(tester, find.text('Delete my account'));
    expect(find.textContaining('A song is still being made'), findsOneWidget);

    account.failure = const ConnectionFailure();
    await tapVisible(tester, find.text('Delete my account'));
    expect(find.textContaining('Couldn’t reach DeenVoice'), findsOneWidget);

    account.failure = StateError('something unexpected');
    await tapVisible(tester, find.text('Delete my account'));
    expect(
      find.text('Something went wrong. Your account was not deleted.'),
      findsOneWidget,
    );
  });

  testWidgets('while it runs the controls are locked and say so', (
    tester,
  ) async {
    final account = FakeAccountService()..gate = Completer<void>();
    await pumpScreens(tester, signedIn: true, account: account);
    await openDelete(tester);
    await tester.enterText(passwordField(), 'hunter2 hunter2');
    await tester.ensureVisible(find.text('Delete my account'));
    await tester.pump();
    await tester.tap(find.text('Delete my account'));
    await settle(tester, 3);
    expect(find.text('Deleting…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Deleting…'))
          .onPressed,
      isNull,
    );
    expect(tester.widget<TextField>(passwordField()).enabled, isFalse);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Keep my account'),
          )
          .onPressed,
      isNull,
    );
    expect(account.passwords, [
      'hunter2 hunter2',
    ], reason: 'one request, not one per frame');
    account.gate!.complete();
    await settle(tester);
  });

  testWidgets('keeping the account just goes back', (tester) async {
    final account = FakeAccountService();
    await pumpScreens(tester, signedIn: true, account: account);
    await openDelete(tester);
    await tapVisible(tester, find.text('Keep my account'));
    expect(find.text('amina@example.com'), findsOneWidget);
    expect(account.passwords, isEmpty);
  });

  testWidgets(
    'success shows what the server did, then wipes this device and shows Welcome',
    (tester) async {
      final account = FakeAccountService();
      final store = MemorySessionStore(
        AuthSession(
          token: 't',
          userId: 'u',
          email: 'amina@example.com',
          expiresAt: DateTime.utc(2030),
        ),
      );
      final drafts = MemoryDraftStore(
        SavedDraft(
          draft: const SongDraft(title: 'Private'),
          savedAt: screenNow,
          ownerId: 'u',
        ),
      );
      final activity = MemoryActivityStore();
      await activity.markSeen('u', screenNow);
      await pumpScreens(
        tester,
        signedIn: true,
        account: account,
        sessionStore: store,
        drafts: drafts,
        activityStore: activity,
      );
      await openDelete(tester);
      await tester.enterText(passwordField(), 'hunter2 hunter2');
      await tapVisible(tester, find.text('Delete my account'));

      // The server's own account of what happened is shown before anything closes.
      expect(find.text('Your account was deleted'), findsOneWidget);
      expect(
        find.textContaining(
          'could not delete its copy of your voice recordings',
        ),
        findsOneWidget,
      );
      expect(
        find.text('A record that credits were granted and used.'),
        findsOneWidget,
      );
      expect(
        (await store.read()),
        isNotNull,
        reason: 'still signed in until the person has read it',
      );

      await tapAndSettle(tester, find.text('OK'));
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(
        find.text('Delete account'),
        findsNothing,
        reason: 'every screen they had open is closed',
      );
      expect(await store.read(), isNull);
      expect(drafts.saved, isNull);
      expect(await activity.lastSeen('u'), isNull);
      expect(account.passwords, ['hunter2 hunter2']);
    },
  );

  testWidgets(
    'ending the session closes every screen that was open over Home',
    (tester) async {
      // Not only deletion: a session the server ended while Create was open.
      final store = MemorySessionStore(
        AuthSession(
          token: 't',
          userId: 'u',
          email: 'amina@example.com',
          expiresAt: DateTime.utc(2030),
        ),
      );
      await pumpScreens(tester, signedIn: true, sessionStore: store);
      await openCreateFromHome(tester);
      expect(find.text('Generate Song'), findsWidgets);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      await container.read(sessionProvider.notifier).expire();
      await settle(tester);
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Generate Song'), findsNothing);
    },
  );
}
