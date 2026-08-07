/// MyÜzi app configuration.
class AppConfig {
  static const appName = 'MyÜzi';

  /// Canonical API / web host (no workers.dev).
  static const primaryBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://myuzi.uvmr.app',
  );

  static const apiCandidates = [primaryBaseUrl];

  static String webAccountUrlFor(String base) => '$base/account';
}
