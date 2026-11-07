// The Validation & assumptions page (the top bar's shield button, and Learn's
// "Can I trust these numbers?"): Escape closes it, as it closes the app's
// sheets and dialogs; only its Back button did (1.13.4 review, a11y).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/validation_page.dart';
import 'package:polar_horizon/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // opened as the shell's shield button opens it
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('opener'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ValidationPage())),
            child: const Text('Validation & assumptions'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('opener')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ValidationPage), findsOneWidget);
  }

  Future<void> closed(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ValidationPage), findsNothing);
    expect(find.byKey(const ValueKey('opener')), findsOneWidget);
  }

  testWidgets('Escape closes the page right after it opens', (tester) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await closed(tester);
  });

  testWidgets('Escape closes it with the focus on its Back button', (tester) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<BackButton>(), isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await closed(tester);
  });
}
