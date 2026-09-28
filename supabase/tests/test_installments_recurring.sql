-- Parcelamento e recorrência.
insert into auth.users (id, email) values ('e0000000-0000-0000-0000-00000000000e', 'edu@teste.com');
set role authenticated;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-00000000000e', false);

do $$
declare
  cc uuid := (select id from public.accounts where name = 'Conta corrente');
  k uuid := gen_random_uuid();
  r jsonb; r2 jsonb;
  inst uuid;
  s jsonb;
begin
  -- Divisão em centavos: soma sempre fecha
  assert public.installment_amount_cents(240000, 12, 1) = 20000, 'TV: parcela 1';
  assert public.installment_amount_cents(240000, 12, 12) = 20000, 'TV: parcela 12';
  assert public.installment_amount_cents(10000, 3, 1) = 3334, '100/3 primeira';
  assert public.installment_amount_cents(10000, 3, 2) = 3333, '100/3 segunda';
  assert (select sum(public.installment_amount_cents(99999, 7, n)) from generate_series(1, 7) n) = 99999,
    'soma das parcelas = total';

  -- Datas mensais sem deslocamento
  assert public.occurrence_date('2026-01-31', 'monthly', 1, 1) = '2026-02-28', '31/01 → 28/02';
  assert public.occurrence_date('2026-01-31', 'monthly', 1, 2) = '2026-03-31', '31/01 → 31/03';
  assert public.occurrence_date('2026-01-01', 'weekly', 2, 3) = '2026-02-12', 'quinzenal';

  -- TV de R$ 2.400,00 em 12x hoje (duplo toque)
  r := public.create_transaction(jsonb_build_object('idempotency_key', k,
    'type', 'expense', 'amount_cents', 240000, 'description', 'Televisão',
    'account_id', cc, 'payment_method', 'credit_card', 'installments', 12));
  r2 := public.create_transaction(jsonb_build_object('idempotency_key', k,
    'type', 'expense', 'amount_cents', 240000, 'description', 'Televisão',
    'account_id', cc, 'payment_method', 'credit_card', 'installments', 12));
  inst := (r ->> 'installment_id')::uuid;
  assert not (r2 ->> 'created')::boolean and (r2 ->> 'installment_id')::uuid = inst, 'parcelamento idempotente';
  assert (select count(*) from public.installments) = 1, 'um parcelamento';
  assert (select count(*) from public.transactions where installment_id = inst) = 12, '12 parcelas';
  assert (select sum(amount_cents) from public.transactions where installment_id = inst) = 240000, 'soma = total';
  assert (select count(*) from public.transactions where installment_id = inst and status = 'paid') = 1,
    'só a primeira parcela (hoje) é realizada';
  assert (select count(*) from public.transactions where installment_id = inst and status = 'pending') = 11,
    '11 parcelas futuras pendentes';
  assert (select description from public.transactions where installment_id = inst and installment_number = 12)
    = 'Televisão (12/12)', 'descrição numerada';
  assert (select transaction_date from public.transactions where installment_id = inst and installment_number = 2)
    = public.occurrence_date(public.today_br(), 'monthly', 1, 1), 'vencimento mensal';

  s := public.dashboard_summary();
  assert (s ->> 'month_expense_cents')::bigint = 20000, 'mês conta só a parcela realizada';
  assert (s ->> 'current_balance_cents')::bigint = -20000, 'saldo desconta só a parcela paga';

  begin
    perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
      'type', 'income', 'amount_cents', 1000, 'description', 'x', 'account_id', cc, 'installments', 3));
    assert false, 'receita parcelada deveria falhar';
  exception when invalid_parameter_value then null; end;

  -- Aluguel mensal recorrente de R$ 1.500,00 começando hoje
  r := public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
    'type', 'expense', 'amount_cents', 150000, 'description', 'Aluguel', 'account_id', cc,
    'recurring', jsonb_build_object('frequency', 'monthly')));
  assert (r ->> 'recurring_id') is not null, 'recorrência criada';
  assert (select count(*) from public.transactions
           where recurring_transaction_id = (r ->> 'recurring_id')::uuid and status = 'paid') = 1,
    'primeira ocorrência (hoje) realizada';
  assert (select count(*) from public.transactions
           where recurring_transaction_id = (r ->> 'recurring_id')::uuid and status = 'pending') >= 2,
    'próximas ocorrências geradas como pendentes';

  -- Gerar de novo não duplica
  perform public.materialize_recurring(public.today_br() + 62);
  perform public.materialize_recurring(public.today_br() + 62);
  assert (select count(*) = count(distinct transaction_date) from public.transactions
           where recurring_transaction_id = (r ->> 'recurring_id')::uuid), 'sem ocorrência duplicada';

  -- Recorrência com data final respeita o fim
  r := public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
    'type', 'income', 'amount_cents', 50000, 'description', 'Bolsa', 'account_id', cc,
    'recurring', jsonb_build_object('frequency', 'monthly', 'end_date', public.today_br() + 40)));
  assert (select max(transaction_date) from public.transactions
           where recurring_transaction_id = (r ->> 'recurring_id')::uuid) <= public.today_br() + 40,
    'não passa da data final';

  begin
    perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
      'type', 'expense', 'amount_cents', 1000, 'description', 'x', 'account_id', cc,
      'installments', 3, 'recurring', jsonb_build_object('frequency', 'monthly')));
    assert false, 'parcelado e recorrente ao mesmo tempo deveria falhar';
  exception when invalid_parameter_value then null; end;
end $$;
