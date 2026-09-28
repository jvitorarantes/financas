import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/transactions_repository.dart';
import '../../domain/finance/reminders.dart';

Color _levelColor(BuildContext context, ReminderLevel level) {
  final colors = context.financeColors;
  return switch (level) {
    ReminderLevel.overdue => colors.expense,
    ReminderLevel.today => colors.warning,
    ReminderLevel.upcoming => colors.transfer,
  };
}

Future<void> _markPaid(BuildContext context, WidgetRef ref, BillReminder r) async {
  final today = Dates.today();
  final t = r.transaction;
  try {
    // Pago agora: se a conta era futura, a data vira hoje; se venceu, mantém o vencimento.
    await ref.read(transactionsRepositoryProvider).markPaid(t.id, on: t.date.isAfter(today) ? today : t.date);
    ref.read(financeRevisionProvider.notifier).bump();
    if (context.mounted) showMessage(context, '"${t.description}" marcada como paga.');
  } catch (e) {
    if (context.mounted) showFailure(context, e);
  }
}

/// Sino com o número de contas a vencer/vencidas.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(billRemindersProvider).value?.length ?? 0;
    return IconButton(
      key: const Key('notification-bell'),
      tooltip: count == 0 ? 'Notificações' : '$count conta(s) para pagar',
      onPressed: () => showRemindersSheet(context),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: Icon(count > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded),
      ),
    );
  }
}

Future<void> showRemindersSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useRootNavigator: true, // abre por cima da barra inferior e do botão "+"
  builder: (_) => const _RemindersSheet(),
);

class _RemindersSheet extends ConsumerWidget {
  const _RemindersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(billRemindersProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Notificações',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Contas que vencem nos próximos $reminderWindowDays dias ou já venceram. '
                'O aviso continua até você marcar como paga.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: AsyncView<List<BillReminder>>(
                  value: reminders,
                  onRetry: () => ref.invalidate(billRemindersProvider),
                  data: (list) => list.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('Nenhuma conta para os próximos dias. 🎉', textAlign: TextAlign.center),
                        )
                      : ListView(shrinkWrap: true, children: [for (final r in list) ReminderTile(reminder: r)]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReminderTile extends ConsumerStatefulWidget {
  const ReminderTile({super.key, required this.reminder});
  final BillReminder reminder;

  @override
  ConsumerState<ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends ConsumerState<ReminderTile> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.reminder;
    final t = r.transaction;
    final color = _levelColor(context, r.level);
    return Card(
      color: color.withValues(alpha: 0.08),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Icon(
              r.level == ReminderLevel.overdue ? Icons.error_rounded : Icons.notifications_active_rounded,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.description, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${r.dueLabel} · ${Dates.format(t.date)} · ${Money.format(t.amountCents)}',
                    style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              key: ValueKey('reminder-paid-${t.id}'),
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      await _markPaid(context, ref, r);
                      if (mounted) setState(() => _saving = false);
                    },
              child: const Text('Já paguei'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avisos no topo do Dashboard (até 3; o resto fica no sino).
class RemindersBanner extends ConsumerWidget {
  const RemindersBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(billRemindersProvider).value ?? const <BillReminder>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final shown = list.take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in shown) ReminderTile(reminder: r),
          if (list.length > shown.length)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => showRemindersSheet(context),
                child: Text('Ver todas (${list.length})'),
              ),
            ),
        ],
      ),
    );
  }
}
