import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../domain/models/account.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction_draft.dart';
import '../transactions/transaction_form_fields.dart';
import 'audio_flow_controller.dart';

/// "Confira sua movimentação": nada é salvo antes de "Confirmar lançamento".
class AudioReviewPage extends ConsumerStatefulWidget {
  const AudioReviewPage({super.key});

  @override
  ConsumerState<AudioReviewPage> createState() => _AudioReviewPageState();
}

class _AudioReviewPageState extends ConsumerState<AudioReviewPage> {
  bool _editing = false;
  Map<String, String> _errors = const {};

  Future<void> _confirm() async {
    final errors = await ref.read(audioFlowProvider.notifier).confirm();
    if (!mounted) return;
    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _editing = true;
      });
      return;
    }
    final state = ref.read(audioFlowProvider);
    if (state.status == AudioFlowStatus.completed) {
      showMessage(context, 'Movimentação salva!');
      context.go('/');
    } else if (state.error != null) {
      showMessage(context, state.error!, error: true);
    }
  }

  Future<void> _cancel() async {
    await ref.read(audioFlowProvider.notifier).cancel();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(audioFlowProvider);
    final draft = state.draft;
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final saving = state.status == AudioFlowStatus.saving;
    final theme = Theme.of(context);

    if (draft == null ||
        !(state.status == AudioFlowStatus.needsReview || saving || state.status == AudioFlowStatus.completed)) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.mic_off_rounded,
          title: 'Nenhuma gravação para conferir.',
          action: FilledButton(onPressed: () => context.go('/'), child: const Text('Voltar ao início')),
        ),
      );
    }

    final questions = state.extraction?.questions ?? const <String>[];

    return PopScope(
      canPop: !saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && ref.read(audioFlowProvider).status == AudioFlowStatus.needsReview) {
          ref.read(audioFlowProvider.notifier).cancel();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Confira sua movimentação')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: ResponsiveCenter(
              maxWidth: 640,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---- transcrição ----
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.mic_rounded, size: 18, color: theme.colorScheme.primary),
                              const SizedBox(width: 6),
                              Text('Transcrição', style: theme.textTheme.labelLarge),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '"${state.transcription ?? draft.transcription ?? ''}"',
                            key: const Key('review-transcription'),
                            style: theme.textTheme.titleMedium?.copyWith(fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ---- perguntas de esclarecimento ----
                  if (questions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: context.financeColors.warning.withValues(alpha: 0.12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final q in questions)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.help_outline_rounded, size: 20, color: context.financeColors.warning),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(q, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text('Ajuste os campos abaixo antes de confirmar.', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (state.error != null) ...[
                    const SizedBox(height: 12),
                    Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  Text('Dados encontrados', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (_editing)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: TransactionFormFields(
                          draft: draft,
                          accounts: accounts,
                          categories: categories,
                          errors: _errors,
                          onChanged: (next) {
                            ref.read(audioFlowProvider.notifier).updateDraft(next);
                            if (_errors.isNotEmpty) setState(() => _errors = next.validate());
                          },
                        ),
                      ),
                    )
                  else
                    _Summary(
                      draft: draft,
                      accounts: accounts,
                      categories: categories,
                      onEdit: () => setState(() => _editing = true),
                    ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('review-confirm'),
                    onPressed: saving ? null : _confirm,
                    icon: saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Icon(Icons.check_rounded),
                    label: const Text('Confirmar lançamento'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('review-cancel'),
                          onPressed: saving ? null : _cancel,
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('review-edit'),
                          onPressed: saving ? null : () => setState(() => _editing = !_editing),
                          child: Text(_editing ? 'Ver resumo' : 'Editar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.draft, required this.accounts, required this.categories, required this.onEdit});
  final TransactionDraft draft;
  final List<Account> accounts;
  final List<Category> categories;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    String? accountName(String? id) => accounts.where((a) => a.id == id).firstOrNull?.name;
    final category = categories.where((c) => c.id == draft.categoryId).firstOrNull?.name;
    const missing = 'Não identificado — toque para informar';
    final installments = draft.installmentAmounts;
    final rows = <(String, String, bool)>[
      ('Tipo', draft.type?.label ?? missing, draft.type == null),
      ('Valor', draft.amountCents == null ? missing : Money.format(draft.amountCents!), draft.amountCents == null),
      ('Descrição', draft.description.trim().isEmpty ? missing : draft.description, draft.description.trim().isEmpty),
      if (draft.type != TransactionType.transfer) ('Categoria', category ?? 'Sem categoria', false),
      ('Data', Dates.format(draft.date), false),
      if (draft.type == TransactionType.transfer) ...[
        ('De', accountName(draft.accountId) ?? missing, draft.accountId == null),
        ('Para', accountName(draft.destinationAccountId) ?? missing, draft.destinationAccountId == null),
      ] else ...[
        ('Pagamento', draft.paymentMethod?.label ?? 'Não informado', false),
        ('Conta', accountName(draft.accountId) ?? missing, draft.accountId == null),
      ],
      if (installments.isNotEmpty) ('Parcelas', '${installments.length}x de ${Money.format(installments.last)}', false),
      if (draft.recurrence != null) ('Repetição', draft.recurrence!.frequency.label, false),
    ];
    final theme = Theme.of(context);
    return Card(
      child: Column(
        children: [
          for (final (label, value, isMissing) in rows)
            ListTile(
              dense: true,
              onTap: onEdit,
              title: Text(label, style: theme.textTheme.bodySmall),
              subtitle: Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isMissing ? theme.colorScheme.error : theme.colorScheme.onSurface,
                ),
              ),
              trailing: const Icon(Icons.edit_outlined, size: 18),
            ),
        ],
      ),
    );
  }
}
