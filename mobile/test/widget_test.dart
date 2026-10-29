import 'package:flutter_test/flutter_test.dart';
import 'package:fast_cash/core/format.dart';

void main() {
  test('formate un numéro congolais et un montant', () {
    expect(formatPhone('+243810123456'), '+243 810 123 456');
    expect(formatMoney(100, 'USD'), '100 USD');
    expect(formatMoney(1500000, 'CDF'), '1 500 000 CDF');
  });
}
