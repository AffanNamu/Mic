import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Advances time without waiting for animations to settle (a progress
/// indicator never does).
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await settle(tester);
}

/// The bottom bar's items (the last text with that label on screen).
Future<void> openTab(WidgetTester tester, String label) =>
    tapAndSettle(tester, find.text(label).last);

Future<void> openCreateFromHome(WidgetTester tester) =>
    tapAndSettle(tester, find.text('Create a Song'));

Future<void> openActivity(WidgetTester tester) =>
    tapAndSettle(tester, find.byIcon(LucideIcons.bell));

/// The avatar shows the email's initial.
Future<void> openProfile(WidgetTester tester, [String initial = 'A']) =>
    tapAndSettle(tester, find.text(initial).first);

/// Goes back the way a person does: the screen's own Back button.
Future<void> goBack(WidgetTester tester) => tapAndSettle(
  tester,
  find
      .byWidgetPredicate(
        (w) => w is BackButton || (w is Tooltip && w.message == 'Back'),
      )
      .first,
);
