import 'package:flutter/foundation.dart';

/// Opens a web page outside the app.
abstract interface class LinkOpener {
  /// Whether the page could be opened.
  Future<bool> open(Uri url);
}

/// Where the Terms of Service and Privacy Policy live. Supplied by the build
/// (`--dart-define=TERMS_URL=…`, `--dart-define=PRIVACY_URL=…`); the app never
/// invents a document it cannot show.
@immutable
class LegalLinks {
  const LegalLinks({this.terms, this.privacy});

  final Uri? terms;
  final Uri? privacy;

  bool get hasBoth => terms != null && privacy != null;
  bool get hasAny => terms != null || privacy != null;
}

/// An `http(s)` URL with a host, or null. Anything else (empty, `javascript:`,
/// a relative path) is not a page this app will offer to open.
Uri? parseWebUrl(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  return uri;
}
