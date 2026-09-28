import 'enums.dart';

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.initialBalanceCents = 0,
    this.balanceCents = 0,
    this.includeInBalance = true,
    this.archived = false,
  });

  final String id;
  final String name;
  final AccountType type;
  final int initialBalanceCents;
  final int balanceCents;
  final bool includeInBalance;
  final bool archived;

  /// Linha da view `account_balances`.
  factory Account.fromBalanceRow(Map<String, dynamic> j) => Account(
    id: j['account_id'] as String,
    name: j['name'] as String,
    type: AccountType.parse(j['type'] as String?),
    balanceCents: (j['balance_cents'] as num?)?.toInt() ?? 0,
    initialBalanceCents: (j['initial_balance_cents'] as num?)?.toInt() ?? 0,
    includeInBalance: j['include_in_balance'] as bool? ?? true,
    archived: j['archived'] as bool? ?? false,
  );

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    id: j['id'] as String,
    name: j['name'] as String,
    type: AccountType.parse(j['type'] as String?),
    initialBalanceCents: (j['initial_balance_cents'] as num?)?.toInt() ?? 0,
    includeInBalance: j['include_in_balance'] as bool? ?? true,
    archived: j['archived'] as bool? ?? false,
  );
}
