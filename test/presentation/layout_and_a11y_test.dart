import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:deenvoice/app/app.dart';
import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/core/theme/deen_theme.dart';
import 'package:deenvoice/presentation/create_song/create_song_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  TestEnv populated() => TestEnv(
    voices: FakeVoiceRepository(const [
      readyOwnVoice,
      readyAuthorizedVoice,
      readySystemVoice,
    ]),
    credits: FakeCreditsRepository(120),
  );

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(DeenVoiceApp)));

  group('layout', () {
    const sizes = {
      'iPhone SE (320x568)': Size(320, 568),
      'small Android (360x640)': Size(360, 640),
      'iPhone 15 (393x852)': Size(393, 852),
      'reference (426x923)': Size(426, 923),
      'tablet portrait (768x1024)': Size(768, 1024),
      'landscape phone (844x390)': Size(844, 390),
    };

    for (final entry in sizes.entries) {
      testWidgets('populated screen has no overflow on ${entry.key}', (
        tester,
      ) async {
        await pumpApp(tester, populated(), size: entry.value);
        expect(tester.takeException(), isNull);

        // Everything is reachable by scrolling, including the primary action.
        await tester.ensureVisible(find.text('Generate Song'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final bottom = tester.getBottomLeft(find.text('Generate Song')).dy;
        expect(bottom, lessThanOrEqualTo(entry.value.height + 1));
      });

      testWidgets('shipped (empty) screen has no overflow on ${entry.key}', (
        tester,
      ) async {
        await pumpProductionApp(tester, size: entry.value);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Generate Song'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('large system text is honoured up to 1.3x without overflow', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, populated());
      expect(tester.takeException(), isNull);

      for (final label in ['Full Song', 'Nasheed Style', 'Add New Voice']) {
        await tester.ensureVisible(find.text(label));
        expect(tester.takeException(), isNull, reason: label);
      }
    });

    testWidgets('extreme text sizes are capped, not allowed to break layout', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, populated(), size: const Size(360, 640));
      expect(tester.takeException(), isNull);

      final scaler = MediaQuery.textScalerOf(
        tester.element(find.byType(CreateSongScreen)),
      );
      expect(scaler.scale(10), closeTo(13, 0.01));
    });

    testWidgets('the screen is built from widgets, not a flattened image', (
      tester,
    ) async {
      await pumpApp(tester, populated());

      // The only bundled image on the screen is the masjid artwork.
      final bundled = tester
          .widgetList<Image>(find.byType(Image))
          .map((i) => i.image)
          .whereType<AssetImage>()
          .map((i) => i.assetName)
          .toList();
      expect(bundled, ['assets/art/masjid_header.webp']);

      for (final label in [
        'Create Song',
        'Song Type',
        'Choose Voice',
        'Song Lyrics',
        'Song Details',
        'Advanced Options',
        'Generate Song',
      ]) {
        expect(find.textContaining(label), findsWidgets, reason: label);
      }
      expect(find.byType(TextField), findsNWidgets(2));
    });
  });

  group('accessibility semantics', () {
    testWidgets('primary controls are labelled and announced as buttons', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, populated());

      for (final label in [
        'Back',
        '120 credits available. Open credits.',
        'Generate Song. Costs 1 credit.',
        'Add New Voice. Record or upload.',
        'Manage Voices',
        'Write with AI',
        'Import Text',
        'AI Improve',
      ]) {
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        expect(node.flagsCollection.isButton, isTrue, reason: label);
      }
      handle.dispose();
    });

    testWidgets('selection state is exposed for cards', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, populated());

      SemanticsNode node(String label) =>
          tester.getSemantics(find.bySemanticsLabel(label));
      expect(
        node('Full Song. Complete song with vocals & music')
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        node('Vocal Only. Only vocals (Your voice)').flagsCollection.isSelected,
        Tristate.isFalse,
      );
      expect(
        node('My Voice. Personal voice.').flagsCollection.isSelected,
        Tristate.isTrue,
      );
      handle.dispose();
    });

    testWidgets('text fields have accessible names', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, populated());
      expect(find.bySemanticsLabel('Song lyrics'), findsOneWidget);
      expect(find.bySemanticsLabel('Song title'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('section titles are headers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, populated());
      final node = tester.getSemantics(find.bySemanticsLabel('Song Type'));
      expect(node.flagsCollection.isHeader, isTrue);
      handle.dispose();
    });

    testWidgets('body text meets contrast on the dark surfaces', (
      tester,
    ) async {
      // WCAG AA is 4.5:1 for body text. Muted/placeholder greys are the
      // weakest colours in the design, so they are checked explicitly.
      double lum(Color c) {
        double ch(double v) => v <= 0.03928
            ? v / 12.92
            : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
        return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
      }

      double ratio(Color a, Color b) {
        final l1 = lum(a), l2 = lum(b);
        return (l1 > l2 ? l1 + .05 : l2 + .05) /
            (l1 > l2 ? l2 + .05 : l1 + .05);
      }

      for (final fg in [
        DeenColors.textPrimary,
        DeenColors.textSecondary,
        DeenColors.textMuted,
        DeenColors.placeholder,
        DeenColors.gold,
      ]) {
        expect(
          ratio(fg, DeenColors.panel),
          greaterThanOrEqualTo(4.5),
          reason: '$fg on panel',
        );
        expect(
          ratio(fg, DeenColors.surfaceRaised),
          greaterThanOrEqualTo(4.5),
          reason: '$fg on input fill',
        );
      }
      expect(ratio(DeenColors.onGold, DeenColors.goldDeep), greaterThan(4.5));
    });
  });

  group('step indicator', () {
    testWidgets('advances with real progress', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, populated());

      expect(
        find.bySemanticsLabel('Step 1, Song Details, current step'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Step 2, Lyrics, not started'),
        findsOneWidget,
      );

      container(tester).read(songDraftProvider.notifier).setTitle('Ya Rabbi');
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Step 1, Song Details, completed'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Step 2, Lyrics, current step'),
        findsOneWidget,
      );

      container(tester)
          .read(songDraftProvider.notifier)
          .setLyrics('Ya Rabbi, ka yi mana jagora');
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Step 4, Generate, current step'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('tapping a step scrolls its section into view', (tester) async {
      await pumpApp(tester, populated(), size: const Size(360, 640));
      final generate = find.text('Generate Song');
      expect(tester.getTopLeft(generate).dy, greaterThan(640));

      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(generate).dy, lessThan(640));
      expect(tester.getTopLeft(generate).dy, greaterThan(0));
    });
  });

  group('back navigation', () {
    Future<void> pumpPushed(WidgetTester tester) async {
      tester.view.physicalSize = referenceLogicalSize * referencePixelRatio;
      tester.view.devicePixelRatio = referencePixelRatio;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: populated().overrides,
          child: MaterialApp(
            theme: buildDeenTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CreateSongScreen(),
                      ),
                    ),
                    child: const Text('Open creator'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open creator'));
      await tester.pumpAndSettle();
    }

    testWidgets('Back returns to the previous screen', (tester) async {
      await pumpPushed(tester);
      expect(find.text('Open creator'), findsNothing);

      await tester.tap(find.byIcon(LucideIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.text('Open creator'), findsOneWidget);
      expect(find.byType(CreateSongScreen), findsNothing);
    });

    testWidgets('Back on the root screen is harmless', (tester) async {
      await pumpApp(tester, populated());
      await tester.tap(find.byIcon(LucideIcons.arrowLeft));
      await tester.pumpAndSettle();
      expect(find.byType(CreateSongScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Manage Voices pushes a screen that pops back', (tester) async {
      await pumpApp(tester, populated());
      await tester.ensureVisible(find.text('Manage Voices'));
      await tester.tap(find.text('Manage Voices'));
      await tester.pumpAndSettle();
      expect(find.text('Your voice · Personal voice'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Choose Voice'), findsOneWidget);
    });
  });
}
