/// Errors the UI can present to a user. Provider- and transport-specific
/// exceptions are translated into these at the data boundary.
sealed class AppFailure implements Exception {
  const AppFailure(this.message);

  /// Safe to show to users.
  final String message;

  @override
  String toString() => message;
}

/// The capability exists in the product, but no backend/provider has been
/// connected to it in this build.
final class ServiceNotConfigured extends AppFailure {
  const ServiceNotConfigured(this.service)
    : super('$service is not connected in this build yet.');

  final String service;
}

/// A connected service rejected or failed the request.
final class ServiceFailure extends AppFailure {
  const ServiceFailure(super.message);
}
