import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/transactions_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction.dart';
import 'transaction_tile.dart';

/// Filtros da lista (período padrão: mês atual).
class TransactionFilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() {
    final today = Dates.today();
    return TransactionFilter(from: Dates.firstOfMonth(today), to: Dates.lastOfMonth(today));
  }

  void update(TransactionFilter f) => state = f;

  /// Anda um mês para frente/trás (a partir do mês do período atual).
  void shiftMonth(int delta) {
    final base = Dates.firstOfMonth(state.from ?? Dates.today());
    final month = DateTime(base.year, base.month + delta);
    state = state.copyWith(from: month, to: Dates.lastOfMonth(month));
  }
}

final transactionFilterProvider = NotifierProvider<TransactionFilterNotifier, TransactionFilter>(
  TransactionFilterNotifier.new,
);

final transactionListProvider = FutureProvider<List<FinanceTransaction>>((ref) async {
  ref.watch(financeRevisionProvider);
  final filter = ref.watch(transactionFilterProvider);
  if (filter.to != null) await ref.watch(recurringUntilProvider(Dates.lastOfMonth(filter.to!)).future);
  return ref.watch(transactionsRepositoryProvider).list(filter, limit: 300);
});

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final f = ref.read(transactionFilterProvider);
      ref.read(transactionFilterProvider.notifier).update(f.copyWith(search: v));
    });
  }

  Future<void> _pickPeriod() async {
    final f = ref.read(transactionFilterProvider);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: f.from != null && f.to != null ? DateTimeRange(start: f.from!, end: f.to!) : null,
    );
    if (range != null) {
      ref.read(transactionFilterProvider.notifier).update(f.copyWith(from: range.start, to: range.end));
    }
  }

  Future<void> _delete(FinanceTransaction t) async {
    final ok = await confirmDialog(
      context,
      title: 'Excluir movimentação',
      message: 'Excluir "${t.description}" de ${Money.format(t.amountCents)}?',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(transactionsRepositoryProvider).delete(t.id);
      ref.read(financeRevisionProvider.notifier).bump();
      if (mounted) showMessage(context, 'Movimentação excluída.');
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(transactionFilterProvider);
    final list = ref.watch(transactionListProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final notifier = ref.read(transactionFilterProvider.notifier);

    String periodLabel() {
      if (filter.from == null || filter.to == null) return 'Todo o período';
      final f = filter.from!;
      final t = filter.to!;
      if (f == Dates.firstOfMonth(f) && t == Dates.lastOfMonth(f)) return Dates.monthLabel(f);
      return '${Dates.format(f)} – ${Dates.format(t)}';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimentações'),
        actions: [
          IconButton(
            key: const Key('month-previous'),
            tooltip: 'Mês anterior',
            onPressed: () => notifier.shiftMonth(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            key: const Key('month-next'),
            tooltip: 'Próximo mês',
            onPressed: () => notifier.shiftMonth(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ResponsiveCenter(
        maxWidth: 900,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('search-transactions'),
                controller: _search,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                  hintText: 'Pesquisar descrição',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.date_range_rounded, size: 18),
                    label: Text(periodLabel()),
                    onPressed: _pickPeriod,
                  ),
                  const SizedBox(width: 8),
                  _MenuChip<TransactionType>(
                    label: filter.type?.label ?? 'Tipo',
                    selected: filter.type != null,
                    options: {for (final t in TransactionType.values) t: t.label},
                    onSelected: (t) =>
                        notifier.update(t == null ? filter.copyWith(clearType: true) : filter.copyWith(type: t)),
                  ),
                  const SizedBox(width: 8),
                  _MenuChip<String>(
                    label: categories.where((c) => c.id == filter.categoryId).firstOrNull?.name ?? 'Categoria',
                    selected: filter.categoryId != null,
                    options: {for (final c in categories.where((c) => !c.archived)) c.id: c.name},
                    onSelected: (id) => notifier.update(
                      id == null ? filter.copyWith(clearCategory: true) : filter.copyWith(categoryId: id),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MenuChip<String>(
                    label: accounts.where((a) => a.id == filter.accountId).firstOrNull?.name ?? 'Conta',
                    selected: filter.accountId != null,
                    options: {for (final a in accounts) a.id: a.name},
                    onSelected: (id) => notifier.update(
                      id == null ? filter.copyWith(clearAccount: true) : filter.copyWith(accountId: id),
                    ),
                  ),
                  if (filter.hasFilters) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        _search.clear();
                        notifier.update(TransactionFilter(from: filter.from, to: filter.to));
                      },
                      child: const Text('Limpar filtros'),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: AsyncView<List<FinanceTransaction>>(
                value: list,
                onRetry: () => ref.invalidate(transactionListProvider),
                data: (items) {
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: filter.hasFilters
                          ? 'Nada encontrado com esses filtros.'
                          : 'Nenhuma movimentação no período.',
                      message: 'Use o botão "+" ou grave um áudio para registrar.',
                    );
                  }
                  final income = items
                      .where((t) => t.type == TransactionType.income && !t.isPending)
                      .fold<int>(0, (s, t) => s + t.amountCents);
                  final expense = items
                      .where((t) => t.type == TransactionType.expense && !t.isPending)
                      .fold<int>(0, (s, t) => s + t.amountCents);
                  final forecast = items.where((t) => t.isPending).fold<int>(0, (s, t) => s + t.signedCents);
                  final forecastCount = items.where((t) => t.isPending).length;
                  // Agrupa por dia.
                  final groups = <DateTime, List<FinanceTransaction>>{};
                  for (final t in items) {
                    groups.putIfAbsent(t.date, () => []).add(t);
                  }
                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(transactionListProvider),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _Total(label: 'Receitas', cents: income),
                                ),
                                Expanded(
                                  child: _Total(label: 'Despesas', cents: -expense),
                                ),
                                Expanded(
                                  child: _Total(label: 'Resultado', cents: income - expense),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (forecastCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Card(
                              child: ListTile(
                                key: const Key('forecast-summary'),
                                leading: const Icon(Icons.event_repeat_rounded),
                                title: Text('$forecastCount lançamento(s) previsto(s) no período'),
                                subtitle: const Text('Ainda não pagos/recebidos: não entram nos totais acima.'),
                                trailing: MoneyText(
                                  forecast,
                                  colored: true,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        for (final entry in groups.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                            child: Text(Dates.relative(entry.key), style: Theme.of(context).textTheme.labelLarge),
                          ),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Column(
                                children: [
                                  for (final t in entry.value)
                                    Dismissible(
                                      key: ValueKey(t.id),
                                      direction: DismissDirection.endToStart,
                                      confirmDismiss: (_) async {
                                        await _delete(t);
                                        return false;
                                      },
                                      background: Container(
                                        alignment: Alignment.centerRight,
                                        padding: const EdgeInsets.only(right: 16),
                                        child: Icon(
                                          Icons.delete_outline_rounded,
                                          color: Theme.of(context).colorScheme.error,
                                        ),
                                      ),
                                      child: TransactionTile(
                                        transaction: t,
                                        showDate: false,
                                        onTap: () => context.push('/transactions/edit', extra: t),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.cents});
  final String label;
  final int cents;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 2),
      FittedBox(
        child: MoneyText(cents, colored: true, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    ],
  );
}

class _MenuChip<T> extends StatelessWidget {
  const _MenuChip({required this.label, required this.selected, required this.options, required this.onSelected});
  final String label;
  final bool selected;
  final Map<T, String> options;
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      onSelected: (v) => onSelected(v == _clear ? null : v as T),
      itemBuilder: (_) => [
        const PopupMenuItem(value: _clear, child: Text('Todos')),
        for (final e in options.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: Chip(
        label: Text(label),
        avatar: selected ? const Icon(Icons.check_rounded, size: 18) : null,
        deleteIcon: const Icon(Icons.arrow_drop_down_rounded),
        onDeleted: null,
        backgroundColor: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
      ),
    );
  }
}

const _clear = Object();
