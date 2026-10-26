import 'package:flutter/foundation.dart';

/// Whose voice this is and how it came to be available.
enum VoiceKind {
  /// Recorded or uploaded by the signed-in user as their own voice.
  own,

  /// Another person's voice the user has explicit permission to use.
  authorized,

  /// A voice supplied by the platform or a provider (not a person's clone).
  system,
}

enum VoiceStatus { enrolling, ready, failed, revoked }

enum VoicePresentation { female, male }

/// A reusable voice resource. Instances come from a [VoiceRepository]; the app
/// never fabricates them.
@immutable
class VoiceProfile {
  const VoiceProfile({
    required this.id,
    required this.displayName,
    required this.kind,
    required this.status,
    required this.supportsSinging,
    this.presentation,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final VoiceKind kind;
  final VoiceStatus status;

  /// True only when a connected provider has verified that this profile can
  /// drive voice-conditioned singing. Speech-only clones are `false`.
  final bool supportsSinging;
  final VoicePresentation? presentation;
  final String? avatarUrl;

  /// Whether the profile can be chosen for a song right now.
  bool get isSelectable => status == VoiceStatus.ready && supportsSinging;

  /// Short descriptor shown under the name.
  String get subtitle {
    switch (status) {
      case VoiceStatus.enrolling:
        return 'Processing…';
      case VoiceStatus.failed:
        return 'Enrollment failed';
      case VoiceStatus.revoked:
        return 'Permission revoked';
      case VoiceStatus.ready:
        if (!supportsSinging) return 'Speech only';
        return switch (kind) {
          VoiceKind.own => 'Personal voice',
          VoiceKind.authorized => switch (presentation) {
            VoicePresentation.female => 'Female voice',
            VoicePresentation.male => 'Male voice',
            null => 'Authorized voice',
          },
          VoiceKind.system => 'AI generated',
        };
    }
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceProfile &&
      other.id == id &&
      other.displayName == displayName &&
      other.kind == kind &&
      other.status == status &&
      other.supportsSinging == supportsSinging &&
      other.presentation == presentation &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    kind,
    status,
    supportsSinging,
    presentation,
    avatarUrl,
  );
}
