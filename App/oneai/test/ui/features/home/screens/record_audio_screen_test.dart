import 'package:codebase_ai/ui/features/home/screens/record_audio_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Verify recording screen UI elements', (WidgetTester tester) async {
    // Build the widget
    await tester.pumpWidget(const MaterialApp(home: RecordAudioScreen()));

    // Verify the presence of key elements
    expect(find.text('One AI'), findsOneWidget);
    expect(find.byType(IconButton), findsOneWidget); // Close button

    // Test recording toggle functionality
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();

    // Verify UI elements after recording stopped
    expect(find.text('Recording continue'), findsOneWidget);

    // Verify presence of buttons
    expect(find.text('Prompt & Language'), findsOneWidget);
    expect(find.text('Transcribe & Summarize'), findsOneWidget);
  });
}
