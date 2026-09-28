import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/category_icon.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.transaction, this.onTap, this.trailing, this.showDate = true});
  final FinanceTransaction transaction;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final colors = context.financeColors;
    final theme = Theme.of(context);
    final (color, sign) = switch (t.type) {
      TransactionType.income => (colors.income, '+'),
      TransactionType.expense => (colors.expense, '-'),
      TransactionType.transfer => (colors.transfer, ''),
    };
    final subtitleParts = <String>[
      if (t.type == TransactionType.transfer)
        '${t.accountName ?? 'Conta'} para ${t.destinationAccountName ?? 'Conta'}'
      else ...[
        t.categoryName ?? 'Sem categoria',
        if (t.accountName != null) t.accountName!,
      ],
      if (showDate) Dates.relative(t.date),
    ];
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: t.type == TransactionType.transfer
          ? const CategoryAvatar(iconData: Icons.swap_horiz_rounded, color: '#2563EB')
          : CategoryAvatar(icon: t.categoryIcon, color: t.categoryColor),
      title: Row(
        children: [
          Flexible(
            child: Text(
              t.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (t.source == TransactionSource.audio) ...[
            const SizedBox(width: 6),
            Icon(Icons.mic_rounded, size: 14, color: theme.colorScheme.primary, semanticLabel: 'Registrado por áudio'),
          ],
        ],
      ),
      subtitle: Text(subtitleParts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing:
          trailing ??
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign${Money.format(t.amountCents)}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (t.isPending)
                Text(
                  t.type == TransactionType.income ? 'A receber' : 'A pagar',
                  style: theme.textTheme.labelSmall?.copyWith(color: colors.warning),
                ),
            ],
          ),
    );
  }
}
