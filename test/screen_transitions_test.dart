import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit/widgets/smooth_animated_indexed_stack.dart';
import 'package:credit/utils/smooth_page_transition.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmoothAnimatedIndexedStack Tests', () {
    testWidgets('renders current index and transitions smoothly while keeping state', (tester) async {
      int testStateCounter = 0;

      final testWidget = StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: SmoothAnimatedIndexedStack(
                index: testStateCounter,
                duration: const Duration(milliseconds: 200),
                children: const [
                  Text('Screen 0: Home'),
                  Text('Screen 1: Reports'),
                  Text('Screen 2: Settings'),
                ],
              ),
              floatingActionButton: FloatingActionButton(
                onPressed: () {
                  setState(() {
                    testStateCounter = (testStateCounter + 1) % 3;
                  });
                },
                child: const Icon(Icons.navigate_next),
              ),
            ),
          );
        },
      );

      await tester.pumpWidget(testWidget);
      await tester.pumpAndSettle();

      // Screen 0 visible
      expect(find.text('Screen 0: Home'), findsOneWidget);

      // Tap next to transition to Screen 1
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(); // Start animation
      await tester.pump(const Duration(milliseconds: 100)); // Halfway through transition
      await tester.pumpAndSettle(); // Complete transition

      // Screen 1 visible
      expect(find.text('Screen 1: Reports'), findsOneWidget);

      // Tap next to transition to Screen 2
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Screen 2: Settings'), findsOneWidget);
    });
  });

  group('SmoothGlassPageTransitionsBuilder Tests', () {
    testWidgets('builds smooth route transition with glass background', (tester) async {
      const builder = SmoothGlassPageTransitionsBuilder();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: builder,
                TargetPlatform.windows: builder,
              },
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const Scaffold(
                        body: Text('Detail Screen Target'),
                      ),
                    ),
                  );
                },
                child: const Text('Open Detail'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Open Detail'), findsOneWidget);

      // Trigger navigation
      await tester.tap(find.text('Open Detail'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150)); // Midway in slide animation
      await tester.pumpAndSettle();

      expect(find.text('Detail Screen Target'), findsOneWidget);

      // Pop back
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      expect(find.text('Open Detail'), findsOneWidget);
    });
  });
}
