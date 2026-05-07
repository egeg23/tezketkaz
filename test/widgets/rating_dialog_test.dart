import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tezketkaz/widgets/rating_dialog.dart';

Widget _hostApp({required Future<RatingResult?> Function(BuildContext) launch,
    required void Function(RatingResult?) onClose}) {
  return MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final res = await launch(ctx);
              onClose(res);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('submits selected star rating + comment', (tester) async {
    RatingResult? captured;
    await tester.pumpWidget(_hostApp(
      launch: (ctx) => RatingDialog.show(
        ctx,
        title: 'Rate the shop',
        allowPhotos: false,
      ),
      onClose: (r) => captured = r,
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tap the 4th star (index 3 in the icon list).
    final stars = find.byIcon(Icons.star_outline_rounded);
    expect(stars, findsNWidgets(5));
    await tester.tap(stars.at(3));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.text('Yuborish'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.rating, 4);
    expect(captured!.text, 'Hello');
  });

  testWidgets('Yuborish disabled until a star is tapped', (tester) async {
    await tester.pumpWidget(_hostApp(
      launch: (ctx) =>
          RatingDialog.show(ctx, title: 'Rate', allowPhotos: false),
      onClose: (_) {},
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final submit = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Yuborish'),
    );
    expect(submit.onPressed, isNull);

    // Tap a star — now the button should be enabled.
    await tester.tap(find.byIcon(Icons.star_outline_rounded).first);
    await tester.pump();
    final enabled = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Yuborish'),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('Bekor qilish closes with null', (tester) async {
    RatingResult? captured = const RatingResult(rating: 1);
    await tester.pumpWidget(_hostApp(
      launch: (ctx) =>
          RatingDialog.show(ctx, title: 'Rate', allowPhotos: false),
      onClose: (r) => captured = r,
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bekor qilish'));
    await tester.pumpAndSettle();

    expect(captured, isNull);
  });
}
