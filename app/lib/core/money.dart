import 'package:flutter/services.dart';

/// Valores financeiros são sempre inteiros em centavos. Nunca usar double
/// para guardar ou somar dinheiro.
abstract final class Money {
  /// Limite aceito pelo banco: R$ 1 bilhão.
  static const int maxCents = 100000000000;

  /// 123456 → "R$ 1.234,56"
  static String format(int cents, {bool showSign = false}) {
    final negative = cents < 0;
    final abs = cents.abs();
    final reais = (abs ~/ 100).toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    final centavos = (abs % 100).toString().padLeft(2, '0');
    final sign = negative ? '-' : (showSign && cents > 0 ? '+' : '');
    return '${sign}R\$ $reais,$centavos';
  }

  /// "R$ 1.234,56" / "1234,56" / "1234.5" / "45" → centavos; inválido → null.
  static int? parse(String input) {
    var s = input.replaceAll(RegExp(r'[R$\s]'), '');
    if (s.isEmpty) return null;
    if (!RegExp(r'^\d+([.,]\d+)*$').hasMatch(s)) return null;
    String intPart = s;
    String decPart = '';
    final comma = s.lastIndexOf(',');
    if (comma >= 0) {
      intPart = s.substring(0, comma).replaceAll('.', '');
      decPart = s.substring(comma + 1);
      if (intPart.contains(',')) return null;
    } else if (s.contains('.')) {
      final groups = s.split('.');
      if (groups.skip(1).every((g) => g.length == 3)) {
        intPart = groups.join();
      } else if (groups.length == 2) {
        intPart = groups[0];
        decPart = groups[1];
      } else {
        return null;
      }
    }
    if (decPart.length > 2) return null;
    final value = BigInt.parse(intPart) * BigInt.from(100) + BigInt.parse('${decPart}00'.substring(0, 2));
    if (value > BigInt.from(maxCents)) return null;
    return value.toInt();
  }

  /// Converte reais (vindos da IA como número) em centavos sem erro de float.
  static int fromReais(num reais) => (reais * 100).round();

  /// Divide um total em parcelas; a diferença de centavos vai na primeira.
  /// Mesma regra de `public.installment_amount_cents` no banco.
  static List<int> splitInstallments(int totalCents, int count) {
    if (count < 1) throw ArgumentError.value(count, 'count');
    final base = totalCents ~/ count;
    final rest = totalCents - base * count;
    return List<int>.generate(count, (i) => i == 0 ? base + rest : base);
  }

  /// Percentual inteiro (arredondado) de [part] sobre [whole].
  static int percent(int part, int whole) => whole == 0 ? 0 : ((part * 100) / whole).round();
}

/// Campo de valor que digita como caixa registradora: "4" → 0,04,
/// "45" → 0,45, "4590" → 45,90.
class CentsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final trimmed = digits.length > 12 ? digits.substring(0, 12) : digits;
    final cents = int.parse(trimmed);
    final text = Money.format(cents).replaceFirst('R\$ ', '');
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
