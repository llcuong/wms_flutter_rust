import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage server configuration (IP and Port)
class ServerConfigService {
  static const String _keyServerIp = 'server_ip';
  static const String _keyServerPort = 'server_port';
  
  // Default values
  static const String defaultIp = '172.18.55.215';
  static const String defaultPort = '40000';
  
  // Cached values
  static String _cachedIp = defaultIp;
  static String _cachedPort = defaultPort;
  static bool _initialized = false;

  /// Initialize the service and load saved config
  static Future<void> init() async {
    if (_initialized) return;
    
    final prefs = await SharedPreferences.getInstance();
    _cachedIp = prefs.getString(_keyServerIp) ?? defaultIp;
    _cachedPort = prefs.getString(_keyServerPort) ?? defaultPort;
    _initialized = true;
  }

  /// Get the current API base URL
  static String get apiBaseUrl => 'http://$_cachedIp:$_cachedPort';

  /// Get current server IP
  static String get serverIp => _cachedIp;

  /// Get current server port
  static String get serverPort => _cachedPort;

  /// Save server configuration
  static Future<bool> saveConfig(String ip, String port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyServerIp, ip);
      await prefs.setString(_keyServerPort, port);
      
      // Update cached values
      _cachedIp = ip;
      _cachedPort = port;
      
      return true;
    } catch (e) {
      print('Error saving server config: $e');
      return false;
    }
  }

  /// Reset to default configuration
  static Future<bool> resetToDefault() async {
    return await saveConfig(defaultIp, defaultPort);
  }
}
