import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/local/local_stores.dart';
import '../../domain/song/draft_codec.dart';

/// On-device storage in the platform key-value store (browser local storage on
/// web). Nothing here is secret: a flag, a draft the user typed, and a
/// timestamp. Reads never throw: unreadable data means "nothing stored".

class PreferencesOnboardingStore implements OnboardingStore {
  const PreferencesOnboardingStore();

  static const _key = 'deenvoice.onboarding.v1';

  @override
  Future<bool> isCompleted() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> markCompleted() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, true);
    } catch (_) {
      // Seeing the introduction again next launch is harmless.
    }
  }
}

class PreferencesDraftStore implements DraftStore {
  const PreferencesDraftStore();

  static const _key = 'deenvoice.draft.v1';

  @override
  Future<SavedDraft?> read() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final draft = DraftCodec.decode(json['draft']);
      final savedAt = DateTime.tryParse('${json['savedAt']}');
      if (draft == null || savedAt == null) return null;
      final owner = json['ownerId'];
      return SavedDraft(
        draft: draft,
        savedAt: savedAt.toUtc(),
        ownerId: owner is String ? owner : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(SavedDraft draft) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode({
          'draft': DraftCodec.encode(draft.draft),
          'savedAt': draft.savedAt.toUtc().toIso8601String(),
          'ownerId': draft.ownerId,
        }),
      );
    } catch (_) {
      // A draft that could not be saved is lost on restart, nothing worse.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {}
  }
}

class PreferencesActivityStore implements ActivityStore {
  const PreferencesActivityStore();

  static const _prefix = 'deenvoice.activity.seen.v1.';

  static String _key(String? owner) => '$_prefix${owner ?? 'local'}';

  @override
  Future<DateTime?> lastSeen(String? ownerId) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        _key(ownerId),
      );
      return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> markSeen(String? ownerId, DateTime when) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key(ownerId),
        when.toUtc().toIso8601String(),
      );
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}
