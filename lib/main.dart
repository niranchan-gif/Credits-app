import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'database/db_helper.dart';
import 'services/notification_service.dart';
import 'services/auto_backup_manager.dart';
import 'providers/loan_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/app_lock_wrapper.dart';
import 'screens/main_navigation_screen.dart';
import 'utils/app_theme.dart';

final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('Startup: Launching app in local offline-first mode...');
  
  // Repair database if needed before providers initialize
  try {
    await DBHelper().repairDatabaseIfNeeded();
  } catch (e) {
    debugPrint('Startup: repairDatabaseIfNeeded failed: $e');
  }

  // Initialize local Notification Service
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('Startup: Notification init failed: $e');
  }

  // Start background AutoBackupManager
  try {
    AutoBackupManager().start();
  } catch (e) {
    debugPrint('Startup: AutoBackupManager failed to start: $e');
  }

  runApp(const LoanManagerApp());
}

class LoanManagerApp extends StatelessWidget {
  const LoanManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LoanProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Credits',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            navigatorObservers: [routeObserver],
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const AppLockWrapper(
              child: MainNavigationScreen(),
            ),
          );
        },
      ),
    );
  }
}
