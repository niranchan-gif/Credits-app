import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit/widgets/rocket_update_header.dart';

void main() {
  testWidgets('RocketUpdateHeader renders idle state in dark mode without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RocketUpdateHeader(
            isDownloading: false,
            downloadProgress: 0.0,
            isLaunching: false,
            isDark: true,
          ),
        ),
      ),
    );

    // Pump a few frames to verify continuous smoke and hover animations
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(RocketUpdateHeader), findsOneWidget);
  });

  testWidgets('RocketUpdateHeader renders downloading throttle state in light mode', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RocketUpdateHeader(
            isDownloading: true,
            downloadProgress: 0.65,
            isLaunching: false,
            isDark: false,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(RocketUpdateHeader), findsOneWidget);
  });

  testWidgets('RocketUpdateHeader renders liftoff and flight exhaust contrail', (tester) async {
    bool launched = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RocketUpdateHeader(
            isDownloading: false,
            downloadProgress: 1.0,
            isLaunching: true,
            isDark: true,
            onLaunchComplete: () {
              launched = true;
            },
          ),
        ),
      ),
    );

    // Initial pad rumble / ignition surge
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(RocketUpdateHeader), findsOneWidget);

    // Supersonic liftoff & billowing smoke contrail
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byType(RocketUpdateHeader), findsOneWidget);

    // Final ascent to completion
    await tester.pump(const Duration(milliseconds: 1500));
    expect(launched, isTrue);
  });
}
