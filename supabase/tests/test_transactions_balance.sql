-- Receita, despesa, transferência, saldo atual, saldo projetado e idempotência.
insert into auth.users (id, email) values ('c0000000-0000-0000-0000-00000000000c', 'caio@teste.com');
set role authenticated;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-00000000000c', false);

create temp table ids as select
  (select id from public.accounts where name = 'Conta corrente') as cc,
  (select id from public.accounts where name = 'Poupança')       as poup,
  (select id from public.categories where name = 'Salário')      as salario,
  (select id from public.categories where name = 'Alimentação')  as alim,
  (select id from public.categories where name = 'Contas')       as contas;

do $$
declare
  ids record;
  r jsonb; r2 jsonb;
  k uuid := gen_random_uuid();
  s jsonb;
begin
  select * into ids from ids;

  -- Receita de R$ 3.200,00 hoje
  r := public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
    'type', 'income', 'amount_cents', 320000, 'description', 'Salário',
    'category_id', ids.salario, 'account_id', ids.cc));
  assert (r ->> 'created')::boolean, 'receita criada';

  -- Despesa de R$ 45,90 hoje, com a mesma chave enviada DUAS vezes (duplo toque)
  r  := public.create_transaction(jsonb_build_object('idempotency_key', k,
    'type', 'expense', 'amount_cents', 4590, 'description', 'Almoço',
    'category_id', ids.alim, 'account_id', ids.cc, 'payment_method', 'pix'));
  r2 := public.create_transaction(jsonb_build_object('idempotency_key', k,
    'type', 'expense', 'amount_cents', 4590, 'description', 'Almoço',
    'category_id', ids.alim, 'account_id', ids.cc, 'payment_method', 'pix'));
  assert (r ->> 'created')::boolean and not (r2 ->> 'created')::boolean, 'segunda chamada não cria';
  assert r ->> 'transaction_id' = r2 ->> 'transaction_id', 'devolve o mesmo lançamento';
  assert (select count(*) from public.transactions where description = 'Almoço') = 1, 'sem duplicidade';

  -- Transferência de R$ 200,00 da conta corrente para a poupança
  r := public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
    'type', 'transfer', 'amount_cents', 20000, 'description', 'Guardar',
    'account_id', ids.cc, 'destination_account_id', ids.poup,
    'category_id', ids.alim));  -- categoria é ignorada em transferência
  assert (select category_id is null from public.transactions where id = (r ->> 'transaction_id')::uuid),
    'transferência sem categoria';

  -- Conta futura de R$ 180,00 (energia) daqui a 5 dias → pendente
  r := public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
    'type', 'expense', 'amount_cents', 18000, 'description', 'Energia',
    'category_id', ids.contas, 'account_id', ids.cc,
    'transaction_date', public.today_br() + 5));
  assert (select status = 'pending' from public.transactions where id = (r ->> 'transaction_id')::uuid),
    'despesa futura fica pendente';

  -- Receita futura de R$ 1.000,00 → pendente, não é dinheiro disponível
  perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
    'type', 'income', 'amount_cents', 100000, 'description', 'Freela a receber',
    'account_id', ids.cc, 'transaction_date', public.today_br() + 3));

  -- Saldos por conta
  assert (select balance_cents from public.account_balances where account_id = ids.cc)
         = 320000 - 4590 - 20000, 'saldo da conta corrente';
  assert (select balance_cents from public.account_balances where account_id = ids.poup)
         = 20000, 'saldo da poupança';

  s := public.dashboard_summary();
  assert (s ->> 'current_balance_cents')::bigint = 320000 - 4590, 'saldo total: transferência soma zero, futuros fora';
  assert (s ->> 'month_income_cents')::bigint  = 320000, 'receitas do mês sem transferência nem futura';
  assert (s ->> 'month_expense_cents')::bigint = 4590,   'despesas do mês sem transferência nem futura';
  if date_trunc('month', public.today_br()) = date_trunc('month', public.today_br() + 5) then
    assert (s ->> 'pending_expense_cents')::bigint = 18000, 'contas futuras do mês';
    assert (s ->> 'projected_balance_cents')::bigint = 320000 - 4590 - 18000, 'saldo projetado';
    assert (s ->> 'pending_income_cents')::bigint = 100000, 'receita prevista informada à parte';
  end if;

  -- Validações
  begin
    perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
      'type', 'expense', 'amount_cents', 0, 'description', 'x', 'account_id', ids.cc));
    assert false, 'valor zero deveria falhar';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
      'type', 'expense', 'amount_cents', -500, 'description', 'x', 'account_id', ids.cc));
    assert false, 'valor negativo deveria falhar';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
      'type', 'expense', 'amount_cents', '12.5', 'description', 'x', 'account_id', ids.cc));
    assert false, 'valor fracionário em centavos deveria falhar';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.create_transaction(jsonb_build_object(
      'type', 'expense', 'amount_cents', 100, 'description', 'x', 'account_id', ids.cc));
    assert false, 'sem chave de idempotência deveria falhar';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
      'type', 'transfer', 'amount_cents', 100, 'description', 'x',
      'account_id', ids.cc, 'destination_account_id', ids.cc));
    assert false, 'transferência para a mesma conta deveria falhar';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
      'type', 'expense', 'amount_cents', 100, 'description', 'x', 'account_id', ids.cc,
      'transaction_date', public.today_br() + 10, 'status', 'paid'));
    assert false, 'despesa futura não pode estar paga';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
      'type', 'expense', 'amount_cents', 100, 'description', '   ', 'account_id', ids.cc));
    assert false, 'descrição vazia deveria falhar';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
      'type', 'expense', 'amount_cents', 100, 'description', 'áudio sem sessão',
      'account_id', ids.cc, 'source', 'audio'));
    assert false, 'áudio sem sessão deveria falhar';
  exception when invalid_parameter_value then null; end;

  -- Edição direta não pode transformar transferência em despesa sem ajustar os campos
  begin
    update public.transactions set type = 'expense' where description = 'Guardar';
    assert false, 'transferência mal formada deveria falhar';
  exception when check_violation then null; end;

  -- Pagar a conta de energia: sai do projetado e entra no saldo
  update public.transactions set status = 'paid', transaction_date = public.today_br()
   where description = 'Energia';
  s := public.dashboard_summary();
  assert (s ->> 'current_balance_cents')::bigint = 320000 - 4590 - 18000, 'conta paga reduz o saldo';
  assert (s ->> 'pending_expense_cents')::bigint = 0, 'nada pendente de despesa';
end $$;
