import 'package:flutter_test/flutter_test.dart';
import 'package:meu_financeiro/domain/finance/reminders.dart';
import 'package:meu_financeiro/domain/models/enums.dart';
import 'package:meu_financeiro/domain/models/transaction.dart';

FinanceTransaction bill(
  String id,
  DateTime date, {
  TransactionType type = TransactionType.expense,
  bool pending = true,
}) => FinanceTransaction(
  id: id,
  type: type,
  status: pending ? TransactionStatus.pending : TransactionStatus.paid,
  amountCents: 18000,
  description: 'Conta $id',
  date: date,
  accountId: 'acc',
);

void main() {
  final today = DateTime(2026, 9, 28);

  test('avisa de 7 dias antes até depois do vencimento, do mais urgente ao menos', () {
    final list = buildReminders([
      bill('8dias', DateTime(2026, 10, 6)),
      bill('7dias', DateTime(2026, 10, 5)),
      bill('amanha', DateTime(2026, 9, 29)),
      bill('hoje', DateTime(2026, 9, 28)),
      bill('vencida', DateTime(2026, 9, 25)),
    ], today: today);
    expect(list.map((r) => r.transaction.id), ['vencida', 'hoje', 'amanha', '7dias']);
    expect(list.map((r) => r.dueLabel), ['Venceu há 3 dias', 'Vence hoje', 'Vence amanhã', 'Vence em 7 dias']);
    expect(list.first.level, ReminderLevel.overdue);
    expect(list[1].level, ReminderLevel.today);
    expect(list.last.level, ReminderLevel.upcoming);
  });

  test('receitas e contas já pagas não geram aviso', () {
    final list = buildReminders([
      bill('salario', DateTime(2026, 9, 30), type: TransactionType.income),
      bill('paga', DateTime(2026, 9, 30), pending: false),
    ], today: today);
    expect(list, isEmpty);
  });

  test('venceu ontem', () {
    expect(buildReminders([bill('x', DateTime(2026, 9, 27))], today: today).single.dueLabel, 'Venceu ontem');
  });
}
