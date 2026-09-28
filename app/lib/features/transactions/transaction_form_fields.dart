import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/category_icon.dart';
import '../../domain/models/account.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction_draft.dart';

enum RepeatMode { once, installments, recurring }

/// Todos os campos editáveis de uma movimentação. Usado no registro manual,
/// na edição e na tela de confirmação do áudio.
class TransactionFormFields extends StatefulWidget {
  const TransactionFormFields({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.accounts,
    required this.categories,
    this.errors = const {},
    this.allowRepeat = true,
  });

  final TransactionDraft draft;
  final ValueChanged<TransactionDraft> onChanged;
  final List<Account> accounts;
  final List<Category> categories;
  final Map<String, String> errors;
  final bool allowRepeat;

  @override
  State<TransactionFormFields> createState() => _TransactionFormFieldsState();
}

class _TransactionFormFieldsState extends State<TransactionFormFields> {
  late final TextEditingController _amount;
  late final TextEditingController _description;
  late final TextEditingController _notes;
  late final TextEditingController _installments;

  /// Rascunho mais recente. Guardado aqui para que dois eventos seguidos
  /// (antes de a tela reconstruir) não sobrescrevam um ao outro.
  late TransactionDraft _current = widget.draft;
  TransactionDraft get d => _current;

  @override
  void didUpdateWidget(covariant TransactionFormFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    _current = widget.draft;
  }

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: d.amountCents == null ? '' : Money.format(d.amountCents!).replaceFirst('R\$ ', ''),
    );
    _description = TextEditingController(text: d.description);
    _notes = TextEditingController(text: d.notes);
    _installments = TextEditingController(text: (d.installments ?? 2).toString());
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _notes.dispose();
    _installments.dispose();
    super.dispose();
  }

  void _emit(TransactionDraft next) {
    _current = next;
    widget.onChanged(next);
  }

  RepeatMode get _repeat => (d.installments ?? 1) > 1
      ? RepeatMode.installments
      : d.recurrence != null
      ? RepeatMode.recurring
      : RepeatMode.once;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.financeColors;
    final type = d.type;
    final kind = type == TransactionType.income ? CategoryKind.income : CategoryKind.expense;
    final categories = widget.categories.where((c) => c.kind == kind && (!c.archived || c.id == d.categoryId)).toList();
    final accounts = widget.accounts
        .where((a) => !a.archived || a.id == d.accountId || a.id == d.destinationAccountId)
        .toList();
    final amountColor = switch (type) {
      TransactionType.income => colors.income,
      TransactionType.expense => colors.expense,
      TransactionType.transfer => colors.transfer,
      null => theme.colorScheme.onSurface,
    };
    const gap = SizedBox(height: 16);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- tipo ----
        SegmentedButton<TransactionType>(
          key: const Key('field-type'),
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: TransactionType.expense,
              label: Text('Despesa'),
              icon: Icon(Icons.arrow_upward_rounded),
            ),
            ButtonSegment(
              value: TransactionType.income,
              label: Text('Receita'),
              icon: Icon(Icons.arrow_downward_rounded),
            ),
            ButtonSegment(
              value: TransactionType.transfer,
              label: Text('Transferir'),
              icon: Icon(Icons.swap_horiz_rounded),
            ),
          ],
          selected: {?type},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            final next = s.first;
            final keepCategory = widget.categories.any(
              (c) =>
                  c.id == d.categoryId &&
                  c.kind == (next == TransactionType.income ? CategoryKind.income : CategoryKind.expense),
            );
            _emit(
              d.copyWith(
                type: next,
                clearCategory: next == TransactionType.transfer || !keepCategory,
                clearDestination: next != TransactionType.transfer,
                clearInstallments: next != TransactionType.expense,
                clearRecurrence: next == TransactionType.transfer,
                clearPaymentMethod: next == TransactionType.transfer,
              ),
            );
          },
        ),
        if (widget.errors['type'] != null) _ErrorText(widget.errors['type']!),
        gap,

        // ---- valor ----
        TextField(
          key: const Key('field-amount'),
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: [CentsInputFormatter()],
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: amountColor),
          decoration: InputDecoration(
            labelText: 'Valor',
            prefixText: 'R\$ ',
            prefixStyle: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: amountColor),
            errorText: widget.errors['amount'],
          ),
          onChanged: (text) {
            final cents = text.isEmpty ? null : Money.parse(text);
            _emit(cents == null ? d.copyWith(clearAmount: true) : d.copyWith(amountCents: cents));
          },
        ),
        gap,

        // ---- descrição ----
        TextField(
          key: const Key('field-description'),
          controller: _description,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: 'Descrição',
            hintText: type == TransactionType.income ? 'Ex.: Salário' : 'Ex.: Almoço',
            errorText: widget.errors['description'],
            counterText: '',
          ),
          onChanged: (v) => _emit(d.copyWith(description: v)),
        ),
        gap,

        // ---- categoria ----
        if (type != TransactionType.transfer) ...[
          Text('Categoria', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in categories)
                ChoiceChip(
                  avatar: Icon(iconFor(c.icon), size: 18, color: colorFromHex(c.color)),
                  label: Text(c.name),
                  selected: c.id == d.categoryId,
                  onSelected: (sel) => _emit(sel ? d.copyWith(categoryId: c.id) : d.copyWith(clearCategory: true)),
                ),
            ],
          ),
          gap,
        ],

        // ---- data e contas ----
        _DateField(
          date: d.date,
          onChanged: (date) {
            final future = Dates.dateOnly(date).isAfter(Dates.today());
            _emit(d.copyWith(date: date, clearAlreadyPaid: future && d.alreadyPaid == true));
          },
          error: widget.errors['date'],
        ),
        gap,
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey('field-account-${d.accountId}'),
          initialValue: accounts.any((a) => a.id == d.accountId) ? d.accountId : null,
          decoration: InputDecoration(
            labelText: type == TransactionType.transfer ? 'Conta de origem' : 'Conta',
            errorText: widget.errors['account'],
          ),
          items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
          onChanged: (v) => _emit(d.copyWith(accountId: v)),
        ),
        if (type == TransactionType.transfer) ...[
          gap,
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey('field-destination-${d.destinationAccountId}'),
            initialValue: accounts.any((a) => a.id == d.destinationAccountId) ? d.destinationAccountId : null,
            decoration: InputDecoration(labelText: 'Conta de destino', errorText: widget.errors['destination']),
            items: [
              for (final a in accounts.where((a) => a.id != d.accountId))
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => _emit(d.copyWith(destinationAccountId: v)),
          ),
          const SizedBox(height: 6),
          Text(
            'Transferências entre suas contas não contam como receita nem despesa.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (type != TransactionType.transfer) ...[
          gap,
          DropdownButtonFormField<PaymentMethod?>(
            isExpanded: true,
            key: ValueKey('field-payment-${d.paymentMethod}'),
            initialValue: d.paymentMethod,
            decoration: const InputDecoration(labelText: 'Forma de pagamento'),
            items: [
              const DropdownMenuItem<PaymentMethod?>(value: null, child: Text('Não informada')),
              for (final p in PaymentMethod.values) DropdownMenuItem(value: p, child: Text(p.label)),
            ],
            onChanged: (v) => _emit(v == null ? d.copyWith(clearPaymentMethod: true) : d.copyWith(paymentMethod: v)),
          ),
        ],
        gap,

        // ---- situação ----
        SwitchListTile(
          key: const Key('field-paid'),
          contentPadding: EdgeInsets.zero,
          title: Text(type == TransactionType.income ? 'Já recebido' : 'Já pago'),
          subtitle: Text(
            d.isFuture
                ? 'Data futura: fica como compromisso e entra no saldo projetado.'
                : 'Desligue para registrar como pendente (conta a pagar/receber).',
          ),
          value: d.alreadyPaid ?? !d.isFuture,
          onChanged: d.isFuture ? null : (v) => _emit(d.copyWith(alreadyPaid: v)),
        ),
        if (widget.errors['status'] != null) _ErrorText(widget.errors['status']!),

        // ---- repetição ----
        if (widget.allowRepeat && type != TransactionType.transfer) ...[
          gap,
          Text('Repetição', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<RepeatMode>(
            key: const Key('field-repeat'),
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: RepeatMode.once, label: Text('Única')),
              if (type == TransactionType.expense || type == null)
                const ButtonSegment(value: RepeatMode.installments, label: Text('Parcelada')),
              const ButtonSegment(value: RepeatMode.recurring, label: Text('Recorrente')),
            ],
            selected: {_repeat},
            onSelectionChanged: (s) {
              switch (s.first) {
                case RepeatMode.once:
                  _emit(d.copyWith(clearInstallments: true, clearRecurrence: true));
                case RepeatMode.installments:
                  final n = int.tryParse(_installments.text) ?? 2;
                  _emit(d.copyWith(installments: n < 2 ? 2 : n, clearRecurrence: true));
                case RepeatMode.recurring:
                  _emit(d.copyWith(recurrence: const RecurrenceDraft(), clearInstallments: true));
              }
            },
          ),
          if (_repeat == RepeatMode.installments) ...[
            gap,
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    key: const Key('field-installments'),
                    controller: _installments,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                    decoration: InputDecoration(labelText: 'Parcelas', errorText: widget.errors['installments']),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null) _emit(d.copyWith(installments: n));
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: _InstallmentPreview(draft: d)),
              ],
            ),
          ],
          if (_repeat == RepeatMode.recurring) ...[
            gap,
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<RecurrenceFrequency>(
                    isExpanded: true,
                    initialValue: d.recurrence!.frequency,
                    decoration: const InputDecoration(labelText: 'Frequência'),
                    items: [
                      for (final f in RecurrenceFrequency.values) DropdownMenuItem(value: f, child: Text(f.label)),
                    ],
                    onChanged: (f) => _emit(
                      d.copyWith(
                        recurrence: RecurrenceDraft(frequency: f!, endDate: d.recurrence?.endDate),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: d.recurrence?.endDate ?? Dates.addMonths(d.date, 12),
                        firstDate: d.date,
                        lastDate: DateTime(2100),
                        helpText: 'Termina em',
                      );
                      if (picked != null) {
                        _emit(
                          d.copyWith(
                            recurrence: RecurrenceDraft(frequency: d.recurrence!.frequency, endDate: picked),
                          ),
                        );
                      }
                    },
                    child: Text(
                      d.recurrence?.endDate == null ? 'Sem data final' : 'Até ${Dates.format(d.recurrence!.endDate!)}',
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (widget.errors['repeat'] != null) _ErrorText(widget.errors['repeat']!),
        ],
        gap,

        // ---- observação ----
        TextField(
          key: const Key('field-notes'),
          controller: _notes,
          maxLines: 3,
          minLines: 1,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: 'Observação (opcional)',
            errorText: widget.errors['notes'],
            counterText: '',
          ),
          onChanged: (v) => _emit(d.copyWith(notes: v)),
        ),
      ],
    );
  }
}

class _InstallmentPreview extends StatelessWidget {
  const _InstallmentPreview({required this.draft});
  final TransactionDraft draft;

  @override
  Widget build(BuildContext context) {
    final parts = draft.installmentAmounts;
    if (parts.isEmpty) return const Text('Informe o valor total e o número de parcelas.');
    final first = parts.first;
    final other = parts.last;
    final text = first == other
        ? '${parts.length}x de ${Money.format(other)}'
        : '1x de ${Money.format(first)} + ${parts.length - 1}x de ${Money.format(other)}';
    return Text(
      '$text\nA primeira em ${Dates.format(draft.date)}; as demais, todo mês.',
      key: const Key('installment-preview'),
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onChanged, this.error});
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100, 12, 31),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Data',
          suffixIcon: const Icon(Icons.calendar_today_rounded),
          errorText: error,
        ),
        child: Text('${Dates.format(date)}  ·  ${Dates.relative(date)}'),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 12),
    child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
  );
}
