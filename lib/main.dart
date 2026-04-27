import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/loan_provider.dart';
import 'screens/home_screen.dart';
import 'screens/app_lock_wrapper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LoanManagerApp());
}

class LoanManagerApp extends StatelessWidget {
  const LoanManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LoanProvider(),
      child: MaterialApp(
        title: 'Credits',
        debugShowCheckedModeBanner: false,
        navigatorObservers: [routeObserver],
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF1E3A5F),
          useMaterial3: true,
        ),

        home: const AppLockWrapper(child: HomeScreen()),
      ),
    );
  }
}