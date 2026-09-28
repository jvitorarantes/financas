-- Segurança entre usuários: RLS, chaves compostas e anon sem acesso.
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-00000000000a', 'ana@teste.com'),
  ('b0000000-0000-0000-0000-00000000000b', 'bia@teste.com');

-- Cadastro criou perfil, 3 contas e 13 categorias para cada um.
do $$ begin
  assert (select count(*) from public.users where id in ('a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b')) = 2, 'perfis criados';
  assert (select count(*) from public.accounts where user_id = 'a0000000-0000-0000-0000-00000000000a') = 3, 'contas padrão';
  assert (select count(*) from public.categories where user_id = 'a0000000-0000-0000-0000-00000000000a') = 13, 'categorias padrão';
end $$;

-- Bia cria uma despesa.
set role authenticated;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-00000000000b', false);
select public.create_transaction(jsonb_build_object(
  'idempotency_key', gen_random_uuid(), 'type', 'expense', 'amount_cents', 5000,
  'description', 'Segredo da Bia',
  'account_id', (select id from public.accounts where name = 'Conta corrente')));

-- Ana não vê nada da Bia.
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-00000000000a', false);
do $$
declare
  n int;
begin
  assert (select count(*) from public.transactions) = 0, 'Ana não vê lançamentos da Bia';
  assert (select count(*) from public.accounts) = 3, 'Ana vê só as próprias contas';
  assert (select count(*) from public.users) = 1, 'Ana vê só o próprio perfil';
  assert (select count(*) from public.account_balances) = 3, 'saldos só das próprias contas';

  update public.transactions set amount_cents = 1 where description = 'Segredo da Bia';
  get diagnostics n = row_count;
  assert n = 0, 'Ana não altera lançamento da Bia';

  delete from public.transactions where description = 'Segredo da Bia';
  get diagnostics n = row_count;
  assert n = 0, 'Ana não apaga lançamento da Bia';
end $$;

-- Ana não consegue gravar linha em nome da Bia.
do $$ begin
  begin
    insert into public.financial_goals (user_id, name, target_amount_cents)
    values ('b0000000-0000-0000-0000-00000000000b', 'invasão', 100);
    assert false, 'insert com user_id alheio deveria falhar';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Ana não consegue usar a conta da Bia num lançamento (chave composta).
reset role;
create temp table bia_account as
  select id from public.accounts where user_id = 'b0000000-0000-0000-0000-00000000000b' limit 1;
grant select on bia_account to authenticated;
set role authenticated;
do $$ begin
  begin
    perform public.create_transaction(jsonb_build_object(
      'idempotency_key', gen_random_uuid(), 'type', 'expense', 'amount_cents', 100,
      'description', 'usar conta alheia', 'account_id', (select id from bia_account)));
    assert false, 'lançamento em conta alheia deveria falhar';
  exception when foreign_key_violation then null;
  end;
end $$;

-- Ana não transfere para a conta da Bia.
do $$ begin
  begin
    perform public.create_transaction(jsonb_build_object(
      'idempotency_key', gen_random_uuid(), 'type', 'transfer', 'amount_cents', 100,
      'description', 'desvio', 'account_id', (select id from public.accounts where name = 'Conta corrente'),
      'destination_account_id', (select id from bia_account)));
    assert false, 'transferência para conta alheia deveria falhar';
  exception when foreign_key_violation then null;
  end;
end $$;

-- Visitante (anon) não lê nada nem executa funções.
reset role;
set role anon;
do $$ begin
  begin
    perform count(*) from public.transactions;
    assert false, 'anon não deveria ler transactions';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.dashboard_summary();
    assert false, 'anon não deveria executar dashboard_summary';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Sem login, as funções recusam.
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '', false);
do $$ begin
  begin
    perform public.create_transaction('{}'::jsonb);
    assert false, 'sem login deveria falhar';
  exception when invalid_authorization_specification then null;
  end;
end $$;
