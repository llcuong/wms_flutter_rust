import 'package:flutter/material.dart';
import '../../screens/empty_former_stock_in_screen.dart';
import '../../screens/empty_former_stock_out_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/former_stock_in_screen.dart';
import '../../screens/former_stock_out_screen.dart';
import '../../screens/former_master_data_screen.dart';
import '../../screens/rfid_test_screen.dart';

class AppRouter {
  static const String home = '/';
  static const String formerStockIn = '/former-stock-in';
  static const String formerStockOut = '/former-stock-out';
  static const String emptyFormerStockIn = '/empty-former-stock-in';
  static const String emptyFormerStockOut = '/empty-former-stock-out';
  static const String formerMasterData = '/former-master-data';
  static const String rfidTest = '/rfid-test';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case formerStockIn:
        return MaterialPageRoute(builder: (_) => const FormerStockInScreen());
      case formerStockOut:
        return MaterialPageRoute(builder: (_) => const FormerStockOutScreen());
      case emptyFormerStockIn:
        return MaterialPageRoute(builder: (_) => const EmptyFormerStockInScreen());
      case emptyFormerStockOut:
        return MaterialPageRoute(builder: (_) => const EmptyFormerStockOutScreen());
      case formerMasterData:
        return MaterialPageRoute(builder: (_) => const FormerMasterDataScreen());
      case rfidTest:
        return MaterialPageRoute(builder: (_) => const RfidTestScreen());
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${settings.name}'),
            ),
          ),
        );
    }
  }
}