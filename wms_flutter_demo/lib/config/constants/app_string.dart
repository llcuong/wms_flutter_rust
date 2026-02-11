import '../../services/server_config_service.dart';

class AppStrings {
  static const String appName = 'WMS Flutter';
  
  // API - Dynamic URL from ServerConfigService
  static String get apiBaseUrl => ServerConfigService.apiBaseUrl;
  static const String uhfBasketApi = '/wh_former/uhf/basket';
  
  // Navigation
  static const String home = 'Home';
  static const String formerStockIn = 'Former Stock In';
  static const String formerStockOut = 'Former Stock Out';
  static const String rfidTest = 'RFID Test';
  
  // Common
  static const String save = 'Save';
  static const String cancel = 'Cancel';
  static const String delete = 'Delete';
  static const String edit = 'Edit';
  static const String add = 'Add';
  static const String search = 'Search';
  static const String filter = 'Filter';
}