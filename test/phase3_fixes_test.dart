import 'package:eshary/features/clients/domain/client.dart';
import 'package:eshary/features/exchange_rates/domain/exchange_rates.dart';
import 'package:eshary/shared/formatters.dart';
import 'package:eshary/shared/request_id.dart';
import 'package:flutter_test/flutter_test.dart';

// Phase 3 review fixes (2026-10-29).
void main() {
  group('tryParseMoney: an unreadable entry is not a zero', () {
    test('numbers, Arabic digits and a typed zero', () {
      expect(tryParseMoney('1500.5'), 1500.5);
      expect(tryParseMoney('١٥٠٠'), 1500);
      expect(tryParseMoney('0'), 0);
      expect(tryParseMoney('0.00'), 0);
    });
    test('empty or letters: null', () {
      expect(tryParseMoney(''), isNull);
      expect(tryParseMoney('  '), isNull);
      expect(tryParseMoney('abc'), isNull);
      expect(tryParseMoney('-50'), isNull);
    });
    test('a statement balance may be below zero', () {
      expect(tryParseMoney('-50', negative: true), -50);
      expect(tryParseMoney('−12.5', negative: true), -12.5);
      expect(tryParseMoney('-', negative: true), isNull);
    });
  });

  group('RequestIdKeeper', () {
    test('the same values keep the id; others or done() start anew', () {
      final k = RequestIdKeeper();
      final a = k.idFor(['in', 'cash', 100.0, null]);
      expect(k.idFor(['in', 'cash', 100.0, null]), a);
      final b = k.idFor(['in', 'cash', 200.0, null]);
      expect(b, isNot(a));
      k.done();
      expect(k.idFor(['in', 'cash', 200.0, null]), isNot(b));
    });
  });

  group('ExchangeRates.fromJson', () {
    test('a bank rate sent as null stays null (not the cash rate)', () {
      final r = ExchangeRates.fromJson({
        'sell': 7.2,
        'buy': 7.0,
        'sell_cash': 7.2,
        'buy_cash': 7.0,
        'sell_bank': null,
        'buy_bank': null,
        'can_edit_sell': true,
        'can_edit_buy': true,
      });
      expect(r.lastFor(sell: true, book: 'cash'), 7.2);
      expect(r.lastFor(sell: true, book: 'bank'), isNull);
      expect(r.lastFor(sell: false, book: 'bank'), isNull);
    });
    test('a database before 0093 (one rate per kind) gives it to both', () {
      final r = ExchangeRates.fromJson({'sell': 7.2, 'buy': 7.0});
      expect(r.lastFor(sell: true, book: 'bank'), 7.2);
      expect(r.lastFor(sell: false, book: 'bank'), 7.0);
    });
  });

  test('a sender is the same sender after the list is read again', () {
    Client c() => Client.fromJson({
          'id': 'c1',
          'owner_id': 'u1',
          'name': 'محمد',
          'company': 'أنزار',
          'code': '1',
          'created_at': '2026-10-01T00:00:00Z',
        });
    expect(c(), c());
    expect([c()].contains(c()), isTrue);
    expect(c().hashCode, c().hashCode);
  });
}
