import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tezketkaz/widgets/time_slot_picker.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(height: 100, child: child)),
    );

void main() {
  testWidgets('builds 30-minute slots aligned to next half-hour', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(_wrap(TimeSlotPicker(
      onSelected: (d) => picked = d,
    )));
    await tester.pumpAndSettle();

    // ListView.separated wraps each slot — there should be at least one.
    expect(find.byType(InkWell), findsWidgets);

    // All visible slot timestamps must be aligned to whole/half hours.
    final labels = tester
        .widgetList<Text>(find.descendant(
          of: find.byType(InkWell),
          matching: find.byType(Text),
        ))
        .map((t) => t.data ?? '')
        .toList();
    for (final l in labels) {
      // Format is HH:mm or "Ert. HH:mm".
      final hhmm = l.replaceAll('Ert. ', '');
      final parts = hhmm.split(':');
      expect(parts, hasLength(2));
      final mm = int.parse(parts[1]);
      expect(mm == 0 || mm == 30, true,
          reason: 'Slot label "$l" not aligned to 30-min boundary');
    }

    // Tapping the first chip fires onSelected with a future timestamp.
    await tester.tap(find.byType(InkWell).first);
    expect(picked, isNotNull);
    expect(picked!.isAfter(DateTime.now()), true);
  });

  testWidgets('shows empty placeholder when working hours have already ended',
      (tester) async {
    // Working window 00:00-00:01 is essentially closed all day.
    await tester.pumpWidget(_wrap(TimeSlotPicker(
      workingHours: '00:00-00:01',
      onSelected: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(find.text("Bo'sh slot yo'q"), findsOneWidget);
  });

  testWidgets('respects working-hours window when generating slots',
      (tester) async {
    await tester.pumpWidget(_wrap(TimeSlotPicker(
      workingHours: '09:00-22:00',
      onSelected: (_) {},
    )));
    await tester.pumpAndSettle();

    // No slot label should sit outside 09:00-22:00 (and we treat the upper
    // bound as exclusive, so 22:00 and later are not shown).
    final labels = tester
        .widgetList<Text>(find.descendant(
          of: find.byType(InkWell),
          matching: find.byType(Text),
        ))
        .map((t) => (t.data ?? '').replaceAll('Ert. ', ''))
        .where((s) => s.contains(':'))
        .toList();
    for (final l in labels) {
      final parts = l.split(':');
      final h = int.parse(parts[0]);
      expect(h >= 9 && h < 22, true,
          reason: 'Slot label "$l" outside working window');
    }
  });
}
