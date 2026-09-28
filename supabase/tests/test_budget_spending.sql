-- Orçamento: geral + por categoria, override do mês e gastos por categoria.
insert into auth.users (id, email) values ('f0000000-0000-0000-0000-00000000000f', 'fer@teste.com');
set role authenticated;
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-00000000000f', false);

do $$
declare
  uid uuid := 'f0000000-0000-0000-0000-00000000000f';
  cc uuid := (select id from public.accounts where name = 'Conta corrente');
  alim uuid := (select id from public.categories where name = 'Alimentação');
  lazer uuid := (select id from public.categories where name = 'Lazer');
  b record;
begin
  insert into public.budgets (user_id, category_id, amount_cents) values
    (uid, null, 300000), (uid, alim, 100000), (uid, lazer, 40000);
  -- neste mês o lazer tem limite especial
  insert into public.budgets (user_id, category_id, month, amount_cents)
    values (uid, lazer, date_trunc('month', public.today_br())::date, 60000);

  perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
    'type', 'expense', 'amount_cents', 82000, 'description', 'Mercado', 'category_id', alim, 'account_id', cc));
  perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
    'type', 'expense', 'amount_cents', 15000, 'description', 'Cinema', 'category_id', lazer, 'account_id', cc));
  -- despesa prevista em outro mês não conta no orçamento deste mês
  perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
    'type', 'expense', 'amount_cents', 99900, 'description', 'Show', 'category_id', lazer, 'account_id', cc,
    'transaction_date', public.today_br() + 40));

  select * into b from public.budget_status() where category_id = alim;
  assert b.limit_cents = 100000 and b.spent_cents = 82000, 'alimentação 82%';
  select * into b from public.budget_status() where category_id = lazer;
  assert b.limit_cents = 60000 and b.spent_cents = 15000, 'override do mês vale';
  select * into b from public.budget_status() where category_id is null;
  assert b.limit_cents = 300000 and b.spent_cents = 97000, 'orçamento geral';

  -- prevista deste mês conta no orçamento e no gráfico
  if date_trunc('month', public.today_br()) = date_trunc('month', public.today_br() + 2) then
    perform public.create_transaction(jsonb_build_object('idempotency_key', gen_random_uuid(),
      'type', 'expense', 'amount_cents', 5000, 'description', 'Pizza prevista', 'category_id', alim, 'account_id', cc,
      'transaction_date', public.today_br() + 2));
    select * into b from public.budget_status() where category_id = alim;
    assert b.spent_cents = 87000, 'previsto do mês entra no orçamento';
    assert (select total_cents from public.spending_by_category() where category_id = alim) = 87000, 'e no gráfico';
    delete from public.transactions where description = 'Pizza prevista';
  end if;
  assert (select count(*) from public.budget_status()) = 3, 'um por categoria';

  assert (select total_cents from public.spending_by_category() where category_id = alim) = 82000, 'gasto alimentação';
  assert (select sum(total_cents) from public.spending_by_category()) = 97000, 'total gasto no mês';

  begin
    insert into public.budgets (user_id, category_id, amount_cents) values (uid, alim, 5000);
    assert false, 'orçamento duplicado deveria falhar';
  exception when unique_violation then null; end;
end $$;
