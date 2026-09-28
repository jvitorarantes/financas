import '../../core/dates.dart';
import '../models/enums.dart';
import '../models/transaction.dart';

/// Quantos dias antes do vencimento a conta começa a aparecer.
const reminderWindowDays = 7;

enum ReminderLevel { upcoming, today, overdue }

/// Aviso de conta a pagar: aparece de 7 dias antes até ser marcada como paga.
class BillReminder {
  const BillReminder({required this.transaction, required this.daysUntil});
  final FinanceTransaction transaction;

  /// Dias até o vencimento (0 = hoje, negativo = vencida).
  final int daysUntil;

  ReminderLevel get level => daysUntil < 0
      ? ReminderLevel.overdue
      : daysUntil == 0
      ? ReminderLevel.today
      : ReminderLevel.upcoming;

  String get dueLabel {
    if (daysUntil < -1) return 'Venceu há ${-daysUntil} dias';
    if (daysUntil == -1) return 'Venceu ontem';
    if (daysUntil == 0) return 'Vence hoje';
    if (daysUntil == 1) return 'Vence amanhã';
    return 'Vence em $daysUntil dias';
  }
}

/// Contas pendentes que vencem em até [window] dias ou já venceram, das mais
/// urgentes para as menos urgentes. Receitas e transferências não entram.
List<BillReminder> buildReminders(
  List<FinanceTransaction> pending, {
  required DateTime today,
  int window = reminderWindowDays,
}) {
  final day = Dates.dateOnly(today);
  final list = <BillReminder>[
    for (final t in pending)
      if (t.isPending && t.type == TransactionType.expense)
        BillReminder(transaction: t, daysUntil: Dates.dateOnly(t.date).difference(day).inDays),
  ]..removeWhere((r) => r.daysUntil > window);
  list.sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
  return list;
}
