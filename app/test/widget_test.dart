import 'package:flutter_test/flutter_test.dart';
import 'package:mbx_app/main.dart';

void main() {
  testWidgets('MBXApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MBXApp());
    expect(find.byType(MBXApp), findsOneWidget);
  });
}
