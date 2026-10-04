import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hmu_driver/src/features/shared/presentation/splash_screen.dart';

void main() {
  testWidgets('splash screen shows progress indicator', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
