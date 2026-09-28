enum TransactionType {
  income('income', 'Receita'),
  expense('expense', 'Despesa'),
  transfer('transfer', 'Transferência');

  const TransactionType(this.value, this.label);
  final String value;
  final String label;

  static TransactionType? tryParse(String? v) => values.where((e) => e.value == v).firstOrNull;
}

enum TransactionStatus {
  paid('paid', 'Pago'),
  pending('pending', 'Pendente');

  const TransactionStatus(this.value, this.label);
  final String value;
  final String label;

  static TransactionStatus parse(String? v) => values.where((e) => e.value == v).firstOrNull ?? paid;
}

enum TransactionSource {
  manual('manual', 'Manual'),
  audio('audio', 'Áudio'),
  recurring('recurring', 'Recorrência'),
  installment('installment', 'Parcela');

  const TransactionSource(this.value, this.label);
  final String value;
  final String label;

  static TransactionSource parse(String? v) => values.where((e) => e.value == v).firstOrNull ?? manual;
}

enum PaymentMethod {
  cash('cash', 'Dinheiro'),
  debitCard('debit_card', 'Cartão de débito'),
  creditCard('credit_card', 'Cartão de crédito'),
  pix('pix', 'Pix'),
  bankSlip('bank_slip', 'Boleto'),
  bankTransfer('bank_transfer', 'Transferência bancária'),
  other('other', 'Outro');

  const PaymentMethod(this.value, this.label);
  final String value;
  final String label;

  static PaymentMethod? tryParse(String? v) => values.where((e) => e.value == v).firstOrNull;
}

enum AccountType {
  checking('checking', 'Conta corrente'),
  savings('savings', 'Poupança'),
  cash('cash', 'Dinheiro'),
  creditCard('credit_card', 'Cartão de crédito'),
  investment('investment', 'Investimento'),
  other('other', 'Outra');

  const AccountType(this.value, this.label);
  final String value;
  final String label;

  static AccountType parse(String? v) => values.where((e) => e.value == v).firstOrNull ?? other;
}

enum CategoryKind {
  income('income', 'Receita'),
  expense('expense', 'Despesa');

  const CategoryKind(this.value, this.label);
  final String value;
  final String label;

  static CategoryKind parse(String? v) => values.where((e) => e.value == v).firstOrNull ?? expense;
}

enum RecurrenceFrequency {
  weekly('weekly', 'Semanal'),
  monthly('monthly', 'Mensal'),
  yearly('yearly', 'Anual');

  const RecurrenceFrequency(this.value, this.label);
  final String value;
  final String label;

  static RecurrenceFrequency parse(String? v) => values.where((e) => e.value == v).firstOrNull ?? monthly;
}
