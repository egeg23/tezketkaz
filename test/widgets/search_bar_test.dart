import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tezketkaz/widgets/search_bar.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(8), child: child)),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('debounces onChanged with 300ms timer', (tester) async {
    final values = <String>[];
    await tester.pumpWidget(_wrap(AppSearchBar(onChanged: values.add)));

    await tester.enterText(find.byType(TextField), 'a');
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.enterText(find.byType(TextField), 'abc');

    // Before the debounce fires, no callback should have run.
    await tester.pump(const Duration(milliseconds: 100));
    expect(values, isEmpty);

    // After 300ms (default debounce), only the latest value fires once.
    await tester.pump(const Duration(milliseconds: 300));
    expect(values, ['abc']);
  });

  testWidgets('respects custom debounce duration', (tester) async {
    final values = <String>[];
    await tester.pumpWidget(_wrap(AppSearchBar(
      debounce: const Duration(milliseconds: 50),
      onChanged: values.add,
    )));

    await tester.enterText(find.byType(TextField), 'x');
    await tester.pump(const Duration(milliseconds: 60));
    expect(values, ['x']);
  });

  testWidgets('clear button empties the field and emits empty change',
      (tester) async {
    final values = <String>[];
    await tester.pumpWidget(_wrap(AppSearchBar(onChanged: values.add)));

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump(const Duration(milliseconds: 350));
    expect(values.last, 'hello');

    final closeIcon = find.byIcon(Icons.close_rounded);
    expect(closeIcon, findsOneWidget);
    await tester.tap(closeIcon);
    await tester.pump();
    expect(values.last, '');
  });

  testWidgets('onSubmitted persists query into SharedPreferences', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final submitted = <String>[];
    await tester.pumpWidget(_wrap(AppSearchBar(onSubmitted: submitted.add)));

    await tester.enterText(find.byType(TextField), 'apple');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(submitted, ['apple']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('search.history'), contains('apple'));
  });
}
