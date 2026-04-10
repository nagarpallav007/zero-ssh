import 'package:flutter_test/flutter_test.dart';

import 'package:zerossh/main.dart';

void main() {
  testWidgets('ZeroSSH app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ZeroSSHApp());
    expect(find.byType(ZeroSSHApp), findsOneWidget);
  });
}
