import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'config/routes/app_router.dart';
import 'config/theme/app_theme.dart';
import 'config/localization/app_strings.dart';
import 'config/localization/localization_provider.dart';
import 'providers/former_master_data_provider.dart';
import 'services/server_config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ServerConfigService.init(); // Load saved server config
  await AppStrings.init(locale: 'vi');
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocalizationProvider()),
        ChangeNotifierProvider(create: (_) => FormerMasterDataProvider()),
      ],
      child: MaterialApp(
        title: 'WMS Flutter',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        initialRoute: AppRouter.home,
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
  }
}