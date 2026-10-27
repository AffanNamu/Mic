// Test doubles for the backend-facing services. They live only under test/ and
// exercise the app's own behaviour (screens, state, error handling). They are
// not evidence that any backend or provider works.
import 'dart:async';

import 'package:deenvoice/domain/auth/auth.dart';
import 'package:deenvoice/domain/failures.dart';
import 'package:deenvoice/domain/library/library.dart';
import 'package:deenvoice/domain/playback/audio_player_port.dart';
import 'package:deenvoice/domain/services.dart';
import 'package:deenvoice/domain/voice/consent.dart';

class FakeAuthService implements AuthService {
  FakeAuthService({this.failure});

  AppFailure? failure;
  final calls = <String>[];
  var signOuts = 0;

  AuthSession session(String email) => AuthSession(
    token: 'token-for-$email',
    userId: 'user-$email',
    email: email,
    expiresAt: DateTime.utc(2030),
  );

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
  }) async {
    calls.add('register:$email');
    if (failure != null) throw failure!;
    return session(email);
  }

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    calls.add('signIn:$email');
    if (failure != null) throw failure!;
    return session(email);
  }

  @override
  Future<void> signOut() async => signOuts++;
}

class FakeConsentSource implements ConsentSource {
  FakeConsentSource({this.failure});

  AppFailure? failure;

  static const own =
      'SERVER WORDING (own): I agree to the server-owned statement.';
  static const authorized =
      'SERVER WORDING (authorized): permission was given.';

  @override
  Future<ConsentStatements> statements() async {
    if (failure != null) throw failure!;
    return const ConsentStatements(
      version: 'v7',
      texts: {
        VoiceOwnership.ownVoice: own,
        VoiceOwnership.authorizedByOwner: authorized,
      },
    );
  }
}

class FakeGenerationJobs implements GenerationJobs {
  /// The server's state over time. `job()` always returns `script[step]`; a
  /// test moves time forward by setting [step].
  List<GenerationJob> script = [];
  int step = 0;
  List<GenerationJob> recentJobs = [];
  Object? error;
  final cancelled = <String>[];
  var polls = 0;

  @override
  Future<GenerationJob> job(String jobId) async {
    polls++;
    if (error != null) throw error!;
    return script[step.clamp(0, script.length - 1)];
  }

  @override
  Future<List<GenerationJob>> recent() async => [...recentJobs];

  @override
  Future<GenerationJob> cancel(String jobId) async {
    cancelled.add(jobId);
    final j = script.first;
    return GenerationJob(
      id: j.id,
      status: JobStatus.cancelled,
      stage: 'Cancelled',
      title: j.title,
      credits: j.credits,
      createdAt: j.createdAt,
    );
  }
}

GenerationJob job(
  JobStatus status, {
  String id = 'job-1',
  String stage = '',
  String title = 'Ya Rabbi',
  String? songId,
  String? failureMessage,
}) => GenerationJob(
  id: id,
  status: status,
  stage: stage.isEmpty ? status.name : stage,
  title: title,
  credits: 1,
  createdAt: DateTime.utc(2026, 10, 26, 9),
  songId: songId,
  failureCode: failureMessage == null ? null : 'failed',
  failureMessage: failureMessage,
);

class FakeSongLibrary implements SongLibrary {
  FakeSongLibrary(List<SongRecord> songs) : songs = [...songs];

  final List<SongRecord> songs;
  AppFailure? audioFailure;
  final audioRequests = <String>[];

  @override
  Future<List<SongRecord>> list() async => [...songs];

  @override
  Future<SongRecord> rename(String songId, String title) async {
    final i = songs.indexWhere((s) => s.id == songId);
    final old = songs[i];
    songs[i] = SongRecord(
      id: old.id,
      title: title,
      lyrics: old.lyrics,
      language: old.language,
      provider: old.provider,
      createdAt: old.createdAt,
      voiceName: old.voiceName,
      duration: old.duration,
    );
    return songs[i];
  }

  @override
  Future<void> delete(String songId) async =>
      songs.removeWhere((s) => s.id == songId);

  @override
  Future<SignedAudio> audio(String songId) async {
    audioRequests.add(songId);
    if (audioFailure != null) throw audioFailure!;
    return SignedAudio(
      url: Uri.parse(
        'https://api.example.test/media/songs/$songId?exp=1&sig=s',
      ),
      expiresAt: DateTime.utc(2030),
    );
  }
}

SongRecord song({
  String id = 'song-1',
  String title = 'Ya Rabbi',
  String lyrics = 'Ya Rabbi, ka yi mana jagora',
  String provider = 'mureka',
  String? voiceName = 'My Voice',
  Duration? duration = const Duration(minutes: 3, seconds: 5),
}) => SongRecord(
  id: id,
  title: title,
  lyrics: lyrics,
  language: 'english',
  provider: provider,
  createdAt: DateTime.utc(2026, 10, 26, 9),
  voiceName: voiceName,
  duration: duration,
);

class FakeAudioPlayer implements AudioPlayerPort {
  final _controller = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState();
  Uri? loaded;
  Object? loadError;
  final events = <String>[];
  var disposed = false;

  void emit(PlaybackState s) {
    _state = s;
    _controller.add(s);
  }

  @override
  Stream<PlaybackState> get states => _controller.stream;

  @override
  Future<void> load(Uri url) async {
    if (loadError != null) throw loadError!;
    loaded = url;
    events.add('load');
    emit(
      _state.copyWith(
        loaded: true,
        duration: const Duration(minutes: 3, seconds: 5),
      ),
    );
  }

  @override
  Future<void> play() async {
    events.add('play');
    emit(_state.copyWith(playing: true));
  }

  @override
  Future<void> pause() async {
    events.add('pause');
    emit(_state.copyWith(playing: false));
  }

  @override
  Future<void> seek(Duration position) async {
    events.add('seek:${position.inSeconds}');
    emit(_state.copyWith(position: position));
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }
}
