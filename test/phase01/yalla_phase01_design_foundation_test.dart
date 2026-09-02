import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/design/yalla_breakpoints.dart';
import 'package:yalla_accounts/core/design/yalla_design_tokens.dart';

void main() {
  group('P01 mobile design foundation', () {
    test('uses the approved device breakpoints', () {
      expect(
        YallaBreakpoints.deviceClassFor(0),
        YallaDeviceClass.phone,
      );
      expect(
        YallaBreakpoints.deviceClassFor(599.99),
        YallaDeviceClass.phone,
      );
      expect(
        YallaBreakpoints.deviceClassFor(600),
        YallaDeviceClass.tablet,
      );
      expect(
        YallaBreakpoints.deviceClassFor(1023.99),
        YallaDeviceClass.tablet,
      );
      expect(
        YallaBreakpoints.deviceClassFor(1024),
        YallaDeviceClass.desktop,
      );
    });

    test('keeps interactive targets accessible', () {
      expect(YallaDimensions.minTouchTarget, greaterThanOrEqualTo(48));
      expect(
        YallaDimensions.primaryButtonHeight,
        greaterThanOrEqualTo(YallaDimensions.minTouchTarget),
      );
    });

    test('uses the approved responsive page padding', () {
      expect(YallaPageInsets.forWidth(390).horizontal, 32);
      expect(YallaPageInsets.forWidth(800).horizontal, 48);
      expect(YallaPageInsets.forWidth(1440).horizontal, 64);
    });
  });
}
