-- Editar e excluir recorrências.
insert into auth.users (id, email) values ('72000000-0000-0000-0000-000000000072', 'rec2@teste.com');
set role authenticated;
select set_config('request.jwt.claim.sub', '72000000-0000-0000-0000-000000000072', false);

do $$
declare
  cc uuid := (select id from public.accounts where name = 'Conta corrente');
  poup uuid := (select id from public.accounts where name = 'Poupança');
  r jsonb;
  rid uuid;
  start date := public.today_br() - 40;  -- começou no passado
begin
  r := public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
    'type', 'expense', 'amount_cents', 10000, 'description', 'Academia', 'account_id', cc,
    'transaction_date', start, 'recurring', jsonb_build_object('frequency', 'monthly')));
  rid := (r ->> 'recurring_id')::uuid;
  perform public.materialize_recurring(public.today_br() + 120);
  -- simula que a ocorrência passada foi paga
  update public.transactions set status = 'paid'
   where recurring_transaction_id = rid and transaction_date < public.today_br();

  -- Editar: novo valor, descrição, conta e a cada 2 meses
  perform public.update_recurring(rid, jsonb_build_object(
    'amount_cents', 12000, 'description', 'Academia Plus', 'account_id', poup, 'interval_count', 2));
  assert (select amount_cents = 12000 and interval_count = 2 and account_id = poup
            from public.recurring_transactions where id = rid), 'modelo atualizado';
  assert not exists (select 1 from public.transactions
                      where recurring_transaction_id = rid and status = 'pending' and amount_cents <> 12000),
    'previstos refeitos com o novo valor';
  assert exists (select 1 from public.transactions
                  where recurring_transaction_id = rid and status = 'pending' and description = 'Academia Plus'),
    'previstos com a nova descrição';
  assert (select count(*) from public.transactions
           where recurring_transaction_id = rid and status = 'paid' and amount_cents = 10000) >= 1,
    'pagos continuam como estavam';
  assert (select count(*) = count(distinct transaction_date) from public.transactions
           where recurring_transaction_id = rid), 'sem duplicar';

  -- Valor inválido
  begin
    perform public.update_recurring(rid, jsonb_build_object('amount_cents', 0));
    assert false, 'valor zero deveria falhar';
  exception when invalid_parameter_value then null; end;

  -- Excluir: some o modelo e os previstos; o histórico pago fica.
  perform public.delete_recurring(rid);
  assert not exists (select 1 from public.recurring_transactions where id = rid), 'modelo excluído';
  assert not exists (select 1 from public.transactions where description like 'Academia%' and status = 'pending'),
    'previstos excluídos';
  assert exists (select 1 from public.transactions where description = 'Academia' and status = 'paid'),
    'histórico pago mantido';
end $$;

-- Outro usuário não edita nem exclui a recorrência alheia.
reset role;
insert into auth.users (id, email) values ('73000000-0000-0000-0000-000000000073', 'intruso2@teste.com');
set role authenticated;
select set_config('request.jwt.claim.sub', '72000000-0000-0000-0000-000000000072', false);
create temp table alvo as select (public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
    'type', 'expense', 'amount_cents', 5000, 'description', 'Streaming',
    'account_id', (select id from public.accounts where name = 'Conta corrente'),
    'recurring', jsonb_build_object('frequency', 'monthly'))) ->> 'recurring_id')::uuid as id;
select set_config('request.jwt.claim.sub', '73000000-0000-0000-0000-000000000073', false);
do $$ begin
  begin
    perform public.delete_recurring((select id from alvo));
    assert false, 'não deveria excluir a recorrência de outra pessoa';
  exception when no_data_found then null; end;
  begin
    perform public.update_recurring((select id from alvo), '{"amount_cents": 1}');
    assert false, 'não deveria editar a recorrência de outra pessoa';
  exception when no_data_found then null; end;
end $$;
