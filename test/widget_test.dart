import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:credit/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Credits home opens', (WidgetTester tester) async {
    const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      secureStorageChannel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') {
          return null; // lock is not enabled
        }
        return null;
      },
    );

    await tester.pumpWidget(const LoanManagerApp());
    await tester.pumpAndSettle();

    expect(find.text('Credits Dashboard'), findsOneWidget);
    expect(find.text('Add Borrower'), findsOneWidget);
  });
}

