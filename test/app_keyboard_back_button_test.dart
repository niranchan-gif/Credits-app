import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit/widgets/app_keyboard/app_keyboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppKeyboard back button dismissal', () {
    testWidgets('closing keyboard on didPopRoute when keyboard is visible', (tester) async {
      final controller = AppKeyboardController.instance;
      final textController = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AppKeyboardOverlay(child: child!),
          home: Scaffold(
            body: TextField(
              controller: textController,
              focusNode: focusNode,
            ),
          ),
        ),
      );

      // 1. Initially keyboard is not visible
      expect(controller.isVisible, isFalse);

      // 2. Open keyboard
      controller.attach(controller: textController, focusNode: focusNode);
      expect(controller.isVisible, isTrue);

      // 3. Simulate Android system back button via WidgetsBinding.handlePopRoute()
      final handled = await WidgetsBinding.instance.handlePopRoute();

      // Must be handled (return true) so route doesn't pop
      expect(handled, isTrue);

      // Must close the keyboard
      expect(controller.isVisible, isFalse);

      // 4. If back button pressed again when keyboard is already closed:
      // It should not be handled by keyboard overlay
      // (Returns false from overlay, letting navigator handle it)
      final handledAgain = await WidgetsBinding.instance.handlePopRoute();
      // Because there are no more routes to pop in this single-screen test, it returns false
      expect(handledAgain, isFalse);
    });
  });
}
