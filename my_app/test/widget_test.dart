import 'package:flutter_test/flutter_test.dart';
// Double-check if your package name is exactly 'ai_assistant_app'
import 'package:ai_assistant_app/main.dart'; 

void main() {
  testWidgets('App starts with HomeScreen', (WidgetTester tester) async {
    // FIXED: Changed AIStudioApp() to MyApp() to match main.dart
    await tester.pumpWidget(const MyApp());
    expect(find.text('AI Studio'), findsOneWidget);
  });

  testWidgets('HomeScreen shows both tool cards', (WidgetTester tester) async {
    // FIXED: Changed AIStudioApp() to MyApp() to match main.dart
    await tester.pumpWidget(const MyApp());
    expect(find.text('Create Telegram Bot'), findsOneWidget);
    expect(find.text('Character Diagnosis'), findsOneWidget);
  });
}