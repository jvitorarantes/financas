import 'package:flutter_test/flutter_test.dart';
import 'package:meu_financeiro/core/money.dart';

void main() {
  group('Money.format', () {
    test('formata em reais com separadores brasileiros', () {
      expect(Money.format(0), 'R\$ 0,00');
      expect(Money.format(5), 'R\$ 0,05');
      expect(Money.format(4590), 'R\$ 45,90');
      expect(Money.format(320000), 'R\$ 3.200,00');
      expect(Money.format(123456789), 'R\$ 1.234.567,89');
      expect(Money.format(-8500), '-R\$ 85,00');
      expect(Money.format(8500, showSign: true), '+R\$ 85,00');
    });
  });

  group('Money.parse', () {
    test('entende formatos comuns', () {
      expect(Money.parse('R\$ 1.234,56'), 123456);
      expect(Money.parse('45'), 4500);
      expect(Money.parse('45,9'), 4590);
      expect(Money.parse('0,01'), 1);
      expect(Money.parse('3.200'), 320000);
      expect(Money.parse('12.5'), 1250);
    });

    test('recusa entradas inválidas', () {
      expect(Money.parse(''), isNull);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse('1,234'), isNull);
      expect(Money.parse('-5'), isNull);
      expect(Money.parse('99999999999999'), isNull, reason: 'acima de R\$ 1 bilhão');
    });

    test('não sofre com imprecisão de ponto flutuante', () {
      // 0,1 + 0,2 em double = 0,30000000000000004; em centavos é exato.
      expect(Money.parse('0,10')! + Money.parse('0,20')!, 30);
      expect(Money.fromReais(19.99), 1999);
      var total = 0;
      for (var i = 0; i < 1000; i++) {
        total += Money.parse('0,10')!;
      }
      expect(total, 10000);
    });
  });

  group('parcelas', () {
    test('TV de R\$ 2.400 em 12x = 12 de R\$ 200', () {
      expect(Money.splitInstallments(240000, 12), List.filled(12, 20000));
    });

    test('diferença de centavos vai na primeira (igual ao banco)', () {
      expect(Money.splitInstallments(10000, 3), [3334, 3333, 3333]);
      final parts = Money.splitInstallments(99999, 7);
      expect(parts.reduce((a, b) => a + b), 99999);
      expect(parts.skip(1).toSet(), {14285});
    });

    test('número inválido de parcelas', () {
      expect(() => Money.splitInstallments(100, 0), throwsArgumentError);
    });
  });

  test('percentual', () {
    expect(Money.percent(82000, 100000), 82);
    expect(Money.percent(1, 3), 33);
    expect(Money.percent(5, 0), 0);
  });

  test('campo de valor digita como caixa registradora', () {
    final f = CentsInputFormatter();
    TextEditingValue type(String text) => f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text));
    expect(type('4').text, '0,04');
    expect(type('4590').text, '45,90');
    expect(type('240000').text, '2.400,00');
    expect(type('').text, '');
  });
}
