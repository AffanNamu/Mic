import '../song/song_draft.dart';

/// Client-side estimate of what a generation costs, used to pre-check the
/// balance and label the Generate button.
///
/// The reference design prices a generation at one credit. The server is the
/// source of truth and may charge differently; this must be replaced by a
/// server-provided quote once billing exists.
int estimateCredits(SongDraft draft) => 1;
