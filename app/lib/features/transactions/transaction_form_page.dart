import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/transactions_repository.dart';
import '../../domain/models/account.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction.dart';
import '../../domain/models/transaction_draft.dart';
import 'transaction_form_fields.dart';

/// Tela "Nova movimentação" (e edição de uma existente).
class TransactionFormPage extends ConsumerStatefulWidget {
  const TransactionFormPage({super.key, this.initialType = TransactionType.expense, this.existing});
  final TransactionType initialType;
  final FinanceTransaction? existing;

  @override
  ConsumerState<TransactionFormPage> createState() => _TransactionFormPageState();
}

class _TransactionFormPageState extends ConsumerState<TransactionFormPage> {
  late TransactionDraft _draft;
  Map<String, String> _errors = const {};
  bool _saving = false;
  bool _submitted = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _draft = e == null
        ? TransactionDraft(idempotencyKey: const Uuid().v4(), type: widget.initialType, date: Dates.today())
        : TransactionDraft(
            idempotencyKey: e.id,
            type: e.type,
            amountCents: e.amountCents,
            description: e.description,
            categoryId: e.categoryId,
            accountId: e.accountId,
            destinationAccountId: e.destinationAccountId,
            date: e.date,
            paymentMethod: e.paymentMethod,
            notes: e.notes ?? '',
            alreadyPaid: !e.isPending,
          );
  }

  void _defaultAccount(List<Account> accounts) {
    if (_draft.accountId != null || accounts.isEmpty) return;
    final preferred = accounts.where((a) => a.type == AccountType.checking).firstOrNull ?? accounts.first;
    _draft = _draft.copyWith(accountId: preferred.id);
  }

  Future<void> _save() async {
    if (_saving) return; // evita duplo toque
    final errors = _draft.validate();
    setState(() {
      _submitted = true;
      _errors = errors;
    });
    if (errors.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(transactionsRepositoryProvider);
      if (_editing) {
        await repo.update(widget.existing!.id, _draft);
      } else {
        await repo.create(_draft);
      }
      ref.read(financeRevisionProvider.notifier).bump();
      if (!mounted) return;
      showMessage(context, _editing ? 'Movimentação atualizada.' : 'Movimentação salva.');
      context.pop();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final t = widget.existing!;
    final repo = ref.read(transactionsRepositoryProvider);
    var deleteAll = false;
    if (t.installmentId != null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Excluir parcela'),
          content: const Text('Deseja excluir só esta parcela ou a compra parcelada inteira?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(c, 'one'), child: const Text('Só esta')),
            FilledButton(onPressed: () => Navigator.pop(c, 'all'), child: const Text('Todas as parcelas')),
          ],
        ),
      );
      if (choice == null) return;
      deleteAll = choice == 'all';
    } else {
      if (!mounted) return;
      final ok = await confirmDialog(
        context,
        title: 'Excluir movimentação',
        message: 'Esta ação não pode ser desfeita.',
        confirmLabel: 'Excluir',
        destructive: true,
      );
      if (!ok) return;
    }
    try {
      if (deleteAll) {
        await repo.deleteInstallmentPlan(t.installmentId!);
      } else {
        await repo.delete(t.id);
      }
      ref.read(financeRevisionProvider.notifier).bump();
      if (!mounted) return;
      showMessage(context, 'Movimentação excluída.');
      context.pop();
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final categories = ref.watch(categoriesProvider);
    final title = _editing ? 'Editar movimentação' : 'Nova movimentação';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_editing)
            IconButton(tooltip: 'Excluir', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: AsyncView(
        value: accounts,
        onRetry: () => ref.invalidate(accountsProvider),
        data: (accountList) => AsyncView(
          value: categories,
          onRetry: () => ref.invalidate(categoriesProvider),
          data: (categoryList) {
            _defaultAccount(accountList.where((a) => !a.archived).toList());
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: ResponsiveCenter(
                  maxWidth: 640,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.existing?.transcription != null) ...[
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.mic_rounded),
                            title: const Text('Registrado por áudio'),
                            subtitle: Text('"${widget.existing!.transcription}"'),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TransactionFormFields(
                        draft: _draft,
                        accounts: accountList,
                        categories: categoryList,
                        errors: _submitted ? _errors : const {},
                        allowRepeat: !_editing,
                        onChanged: (next) => setState(() {
                          _draft = next;
                          if (_submitted) _errors = next.validate();
                        }),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('save-transaction'),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                            : Text(_editing ? 'Salvar alterações' : 'Salvar movimentação'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
