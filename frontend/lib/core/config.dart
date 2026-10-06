/// App-wide configuration.
///
/// The API address is injected at build/run time:
///   flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
/// Android emulator -> http://10.0.2.2:8080 (the host machine).
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  /// How often live data (queue position, queue lists) is re-fetched.
  static const Duration pollInterval = Duration(seconds: 5);
}
