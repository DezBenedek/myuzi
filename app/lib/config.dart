/// MyÜzi app configuration.
class AppConfig {
  static const appName = 'MyÜzi';
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://myuzi.dezso.hu',
  );
  static const webAccountUrl = '$apiBaseUrl/account';
}
