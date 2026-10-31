import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbx_app/services/tv_mode_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.mbx.stream/tv_mode'),
      (MethodCall call) async {
        if (call.method == 'isTvDevice') return false;
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.mbx.stream/tv_mode'),
      null,
    );
  });

  test('TvModeService preference changes and persists', () async {
    final service = TvModeService();
    await service.init();

    expect(service.preference, TvModePreference.auto);

    await service.setPreference(TvModePreference.tv);
    expect(service.preference, TvModePreference.tv);

    // Re-init with same prefs to verify persistence
    final prefs = await SharedPreferences.getInstance();
    final service2 = TvModeService();
    await service2.init(prefs);

    expect(service2.preference, TvModePreference.tv);
  });

  testWidgets('isTvMode respects forced tv and mobile modes', (tester) async {
    final service = TvModeService();
    await service.init();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            service.setPreference(TvModePreference.tv);
            expect(service.isTvMode(context), isTrue);

            service.setPreference(TvModePreference.mobile);
            expect(service.isTvMode(context), isFalse);

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
