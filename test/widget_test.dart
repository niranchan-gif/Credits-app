import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:credit/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('Credits home opens', (WidgetTester tester) async {
    await tester.pumpWidget(const LoanManagerApp());
    await tester.pump();

    expect(find.text('Credits'), findsOneWidget);
    expect(find.text('Loan Manager'), findsOneWidget);
  });
}
