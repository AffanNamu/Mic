import '../../domain/failures.dart';
import 'api_client.dart';

/// Reading server JSON defensively: an unexpected shape becomes a clear
/// failure, never a crash or a silently invented value.
const _bad = ServiceFailure('DeenVoice sent a response we didn’t expect.');

Json asObject(Object? v) {
  if (v is Map) return v.cast<String, Object?>();
  throw _bad;
}

List<Object?> asList(Object? v) {
  if (v is List) return v;
  throw _bad;
}

String str(Json j, String key) {
  final v = j[key];
  if (v is String) return v;
  throw _bad;
}

String? strOrNull(Json j, String key) {
  final v = j[key];
  if (v == null) return null;
  if (v is String) return v;
  throw _bad;
}

int integer(Json j, String key) {
  final v = j[key];
  if (v is int) return v;
  if (v is num && v == v.roundToDouble()) return v.toInt();
  throw _bad;
}

bool flag(Json j, String key) => j[key] == true;

DateTime time(Json j, String key) {
  final v = j[key];
  if (v is String) {
    final parsed = DateTime.tryParse(v);
    if (parsed != null) return parsed.toUtc();
  }
  throw _bad;
}

DateTime? timeOrNull(Json j, String key) =>
    j[key] == null ? null : time(j, key);
