// services/server_config_service.dart
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage server configuration (IP and Port) for different warehouses
class ServerConfigService {
  static const String _keySelectedWarehouse = 'selected_warehouse';
  static const String _keyGdServerIp = 'gd_server_ip';
  static const String _keyGdServerPort = 'gd_server_port';
  static const String _keyLkServerIp = 'lk_server_ip';
  static const String _keyLkServerPort = 'lk_server_port';

  // Default values
  static const String defaultIp = '172.18.55.218';
  static const String defaultPort = '30040';
  static const String defaultGdIp = '172.18.55.218';
  static const String defaultGdPort = '30040';
  static const String defaultLkIp = '172.18.55.219';
  static const String defaultLkPort = '30041';

  // Cached values
  static String _cachedSelectedWarehouse = 'gd_factory';
  static String _cachedGdIp = defaultGdIp;
  static String _cachedGdPort = defaultGdPort;
  static String _cachedLkIp = defaultLkIp;
  static String _cachedLkPort = defaultLkPort;
  static bool _initialized = false;

  /// Initialize the service and load saved config
  static Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();

    // Load selected warehouse
    _cachedSelectedWarehouse = prefs.getString(_keySelectedWarehouse) ?? 'gd_factory';

    // Load GD server config
    _cachedGdIp = prefs.getString(_keyGdServerIp) ?? defaultGdIp;
    _cachedGdPort = prefs.getString(_keyGdServerPort) ?? defaultGdPort;

    // Load LK server config
    _cachedLkIp = prefs.getString(_keyLkServerIp) ?? defaultLkIp;
    _cachedLkPort = prefs.getString(_keyLkServerPort) ?? defaultLkPort;

    _initialized = true;
  }

  /// Get the current API base URL based on selected warehouse
  static String get apiBaseUrl {
    if (_cachedSelectedWarehouse == 'gd_factory') {
      return 'http://$_cachedGdIp:$_cachedGdPort';
    } else if (_cachedSelectedWarehouse == 'lk_factory') {
      return 'http://$_cachedLkIp:$_cachedLkPort';
    }
    return 'http://$_cachedGdIp:$_cachedGdPort';
  }

  /// Get the API base URL for a specific warehouse
  static String getApiBaseUrlForWarehouse(String warehouse) {
    if (warehouse == 'gd_factory') {
      return 'http://$_cachedGdIp:$_cachedGdPort';
    } else if (warehouse == 'lk_factory') {
      return 'http://$_cachedLkIp:$_cachedLkPort';
    }
    return 'http://$_cachedGdIp:$_cachedGdPort';
  }

  /// Get current server IP based on selected warehouse
  static String get serverIp {
    if (_cachedSelectedWarehouse == 'gd_factory') {
      return _cachedGdIp;
    } else if (_cachedSelectedWarehouse == 'lk_factory') {
      return _cachedLkIp;
    }
    return _cachedGdIp;
  }

  /// Get current server port based on selected warehouse
  static String get serverPort {
    if (_cachedSelectedWarehouse == 'gd_factory') {
      return _cachedGdPort;
    } else if (_cachedSelectedWarehouse == 'lk_factory') {
      return _cachedLkPort;
    }
    return _cachedGdPort;
  }

  /// Get GD server config
  static String get gdServerIp => _cachedGdIp;
  static String get gdServerPort => _cachedGdPort;

  /// Get LK server config
  static String get lkServerIp => _cachedLkIp;
  static String get lkServerPort => _cachedLkPort;

  /// Get selected warehouse
  static String get selectedWarehouse => _cachedSelectedWarehouse;

  /// Set selected warehouse
  static Future<void> setSelectedWarehouse(String warehouse) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedWarehouse, warehouse);
    _cachedSelectedWarehouse = warehouse;
  }

  /// Save GD server configuration
  static Future<bool> saveGdConfig(String ip, String port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyGdServerIp, ip);
      await prefs.setString(_keyGdServerPort, port);

      _cachedGdIp = ip;
      _cachedGdPort = port;

      return true;
    } catch (e) {
      print('Error saving GD server config: $e');
      return false;
    }
  }

  /// Save LK server configuration
  static Future<bool> saveLkConfig(String ip, String port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLkServerIp, ip);
      await prefs.setString(_keyLkServerPort, port);

      _cachedLkIp = ip;
      _cachedLkPort = port;

      return true;
    } catch (e) {
      print('Error saving LK server config: $e');
      return false;
    }
  }

  /// Reset all configurations to defaults
  static Future<bool> resetToDefault() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(_keyGdServerIp, defaultGdIp);
      await prefs.setString(_keyGdServerPort, defaultGdPort);
      await prefs.setString(_keyLkServerIp, defaultLkIp);
      await prefs.setString(_keyLkServerPort, defaultLkPort);

      _cachedGdIp = defaultGdIp;
      _cachedGdPort = defaultGdPort;
      _cachedLkIp = defaultLkIp;
      _cachedLkPort = defaultLkPort;

      return true;
    } catch (e) {
      print('Error resetting server config: $e');
      return false;
    }
  }
}