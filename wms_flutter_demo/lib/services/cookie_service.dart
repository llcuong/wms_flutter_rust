// services/cookie_service.dart
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../config/constants/app_string.dart';

class CookieService {
  static final CookieService _instance = CookieService._internal();
  factory CookieService() => _instance;
  CookieService._internal();

  static CookieJar? _cookieJar;
  static Dio? _dio;

  static const String _warehouseKey = 'selected_warehouse';

  // Initialize cookie storage
  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _cookieJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/cookies'),
      ignoreExpires: true,
    );

    _dio = Dio();
    _dio!.interceptors.add(CookieManager(_cookieJar!));
  }

  // Set warehouse in cookie
  static Future<void> setWarehouse(String warehouseCode) async {
    if (_cookieJar == null) await init();

    final cookies = [
      Cookie(_warehouseKey, warehouseCode)
        ..path = '/'
        ..domain = 'localhost'
        ..httpOnly = false,
    ];

    await _cookieJar!.saveFromResponse(
      Uri.parse('${AppStrings.apiBaseUrl}/set-warehouse'),
      cookies,
    );
  }

  // Get warehouse from cookie
  static Future<String?> getWarehouse() async {
    if (_cookieJar == null) await init();

    final cookies = await _cookieJar!.loadForRequest(
      Uri.parse('${AppStrings.apiBaseUrl}/api/v2/baskets/batch'),
    );

    for (var cookie in cookies) {
      if (cookie.name == _warehouseKey) {
        return cookie.value;
      }
    }
    return 'GD';
  }

  // Clear warehouse cookie
  static Future<void> clearWarehouse() async {
    if (_cookieJar == null) await init();

    final expiredCookie = Cookie(_warehouseKey, '')
      ..path = '/'
      ..expires = DateTime.now().subtract(const Duration(days: 1));

    await _cookieJar!.saveFromResponse(
      Uri.parse('${AppStrings.apiBaseUrl}/clear-warehouse'),
      [expiredCookie],
    );
  }
}