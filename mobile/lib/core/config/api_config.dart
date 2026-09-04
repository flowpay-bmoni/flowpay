/// Central API configuration for FlowPay mobile app.
/// Connects to the live production/sandbox backend hosted on Render.
class ApiConfig {
  /// Live production backend URL
  static const String liveBackendUrl = 'https://flowpay-k2wn.onrender.com';

  /// Resolves the base URL, allowing override via dart-define `--dart-define=FLOWPAY_API_URL=...`
  static String get baseUrl {
    const envUrl = String.fromEnvironment('FLOWPAY_API_URL');
    if (envUrl.isNotEmpty) return envUrl;
    return liveBackendUrl;
  }
}
