-- Recorrência aparece prevista nos meses seguintes, no dia certo.
insert into auth.users (id, email) values ('71000000-0000-0000-0000-000000000071', 'rec@teste.com');
set role authenticated;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000071', false);

do $$
declare
  cc uuid := (select id from public.accounts where name = 'Conta corrente');
  r jsonb;
  start date := date_trunc('month', public.today_br())::date + 9;  -- dia 10 deste mês
  far date := (date_trunc('month', public.today_br()) + interval '5 months')::date;
begin
  r := public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
    'type', 'expense', 'amount_cents', 150000, 'description', 'Aluguel', 'account_id', cc,
    'transaction_date', start, 'recurring', jsonb_build_object('frequency', 'monthly')));

  -- Mês seguinte já tem a ocorrência prevista no dia 10.
  assert exists (select 1 from public.transactions
                  where recurring_transaction_id = (r ->> 'recurring_id')::uuid
                    and transaction_date = (start + interval '1 month')::date
                    and status = 'pending'), 'próximo mês previsto no dia 10';

  -- Ao abrir um mês distante, o app pede para gerar até o fim dele.
  perform public.materialize_recurring((far + interval '1 month - 1 day')::date);
  assert exists (select 1 from public.transactions
                  where recurring_transaction_id = (r ->> 'recurring_id')::uuid
                    and transaction_date = far + 9 and status = 'pending'), 'mês distante previsto';
  assert (select count(*) = count(distinct transaction_date) from public.transactions
           where recurring_transaction_id = (r ->> 'recurring_id')::uuid), 'sem duplicar';

  -- Previsto conta no saldo projetado daquele mês, não no saldo atual.
  assert (public.dashboard_summary(far) ->> 'pending_expense_cents')::bigint >= 150000, 'projetado do mês distante';
end $$;

-- A cada 3 meses durante 12 meses: 4 lançamentos, nas datas certas.
do $$
declare
  cc uuid := (select id from public.accounts where name = 'Conta corrente');
  start date := date_trunc('month', public.today_br())::date + 4;  -- dia 5
  r jsonb;
begin
  r := public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
    'type', 'expense', 'amount_cents', 30000, 'description', 'Seguro', 'account_id', cc,
    'transaction_date', start,
    'recurring', jsonb_build_object('frequency', 'monthly', 'interval_count', 3,
                                    'end_date', (start + interval '12 months' - interval '1 day')::date)));
  perform public.materialize_recurring(public.today_br() + 400);
  assert (select array_agg(transaction_date order by transaction_date) from public.transactions
           where recurring_transaction_id = (r ->> 'recurring_id')::uuid)
         = array[start, (start + interval '3 months')::date, (start + interval '6 months')::date,
                 (start + interval '9 months')::date], 'trimestral por 12 meses';

  begin
    perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
      'type', 'expense', 'amount_cents', 100, 'description', 'x', 'account_id', cc,
      'recurring', jsonb_build_object('frequency', 'monthly', 'interval_count', 13)));
    assert false, 'intervalo acima de 12 deveria falhar';
  exception when check_violation then null; end;
end $$;
