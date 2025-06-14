import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyn_prototype/main.dart';

void main() {
  testWidgets('Audyn app renders HomeScreen and search button',
          (WidgetTester tester) async {
        await tester.pumpWidget(const AudynApp());

        // Look for the "Search Music" button on HomeScreen
        expect(find.text('Search Music'), findsOneWidget);
        expect(find.byType(ElevatedButton), findsOneWidget);
      });
}
