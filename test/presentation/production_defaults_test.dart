import 'dart:typed_data';

import 'package:deenvoice/app/app.dart';
import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/domain/services.dart';
import 'package:deenvoice/domain/song/song_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// The app exactly as shipped: no backend, no provider. Every control must
/// either work locally or say plainly what is missing. Nothing may pretend.
void main() {
  setUpAll(loadAppFonts);

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(DeenVoiceApp)));

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('shows no invented data', (tester) async {
    await pumpProductionApp(tester);

    expect(find.text('– Credits'), findsOneWidget);
    expect(find.text('120 Credits'), findsNothing);
    // Only the add card; no fictional voices.
    expect(find.text('Add New Voice'), findsOneWidget);
    expect(find.text('My Voice'), findsNothing);
    expect(find.text('Sister Aisha'), findsNothing);
    expect(find.text('Studio Voice'), findsNothing);
    expect(find.textContaining('You have no saved voices yet'), findsOneWidget);
  });

  testWidgets('Generate on an empty form explains what is missing', (
    tester,
  ) async {
    await pumpProductionApp(tester);

    await tapVisible(tester, find.text('Generate Song'));

    expect(find.text('Give your song a title.'), findsWidgets);
    expect(find.text('Add lyrics, or use Write with AI.'), findsWidgets);
    expect(
      find.text('Choose a voice, or add one with Add New Voice.'),
      findsWidgets,
    );
    expect(find.text('Your song is in the queue'), findsNothing);
  });

  testWidgets('a complete request is refused: no engine is connected', (
    tester,
  ) async {
    await pumpProductionApp(tester);
    container(tester).read(songDraftProvider.notifier)
      ..setType(SongType.instrumental)
      ..setTitle('Ambient');
    await tester.pump();

    await tapVisible(tester, find.text('Generate Song'));

    expect(
      find.textContaining('no generation engine is connected'),
      findsOneWidget,
    );
    expect(find.text('Your song is in the queue'), findsNothing);
    expect(find.textContaining('Job '), findsNothing);
  });

  testWidgets('Write with AI says the assistant is not connected', (
    tester,
  ) async {
    await pumpProductionApp(tester);

    await tapVisible(tester, find.text('Write with AI'));
    await tester.enterText(
      find.widgetWithText(TextField, 'What is the song about?'),
      'gratitude',
    );
    await tester.tap(find.text('Write lyrics'));
    await tester.pumpAndSettle();

    expect(
      find.text('The lyrics assistant is not connected in this build yet.'),
      findsOneWidget,
    );
    expect(container(tester).read(songDraftProvider).draft.lyrics, isEmpty);
  });

  testWidgets('AI Improve says the assistant is not connected', (tester) async {
    await pumpProductionApp(tester);
    await tester.enterText(
      find.byKey(const ValueKey('lyrics-field')),
      'Ya Rabbi',
    );

    await tapVisible(tester, find.text('AI Improve'));

    expect(
      find.text('The lyrics assistant is not connected in this build yet.'),
      findsOneWidget,
    );
    expect(
      container(tester).read(songDraftProvider).draft.lyrics,
      'Ya Rabbi',
      reason: 'the user’s text is never changed by a failed assistant call',
    );
  });

  testWidgets('credits sheet reports the missing billing service', (
    tester,
  ) async {
    await pumpProductionApp(tester);

    await tester.tap(find.text('– Credits'));
    await tester.pumpAndSettle();

    expect(
      find.text('Your credit balance is not connected in this build yet.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Buying more credits isn’t available'),
      findsOneWidget,
    );
  });

  testWidgets('voice enrollment reports the missing service after consent', (
    tester,
  ) async {
    await pumpProductionApp(
      tester,
      audioPicker: FakeAudioFilePicker(
        PickedAudio(fileName: 'me.wav', bytes: Uint8List.fromList([1, 2, 3])),
      ),
    );

    await tapVisible(tester, find.text('Add New Voice'));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload a recording'));
    await tester.pumpAndSettle();

    expect(
      find.text('Voice enrollment is not connected in this build yet.'),
      findsOneWidget,
    );
  });

  testWidgets('Manage Voices shows an honest empty state', (tester) async {
    await pumpProductionApp(tester);

    await tapVisible(tester, find.text('Manage Voices'));

    expect(find.text('Manage Voices'), findsWidgets);
    expect(
      find.textContaining('You have no saved voices yet. Add a recording'),
      findsOneWidget,
    );
  });

  testWidgets('Advanced Options are disabled and explain why', (tester) async {
    await pumpProductionApp(tester);

    await tapVisible(tester, find.text('Advanced Options'));

    expect(find.textContaining('No engine is connected yet'), findsOneWidget);
    expect(find.text('Unavailable'), findsNWidgets(4));
    await tester.tap(find.text('Low'));
    await tester.pumpAndSettle();
    expect(container(tester).read(songDraftProvider).draft.advanced, isEmpty);
  });
}
