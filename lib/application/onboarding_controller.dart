import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Whether the first-run introduction has been seen. Loading until the device
/// has been asked, so the app never flashes the wrong screen.
final onboardingCompletedProvider =
    AsyncNotifierProvider<OnboardingController, bool>(OnboardingController.new);

class OnboardingController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.read(onboardingStoreProvider).isCompleted();

  Future<void> complete() async {
    await ref.read(onboardingStoreProvider).markCompleted();
    state = const AsyncData(true);
  }
}
