-- Primeira conta é administradora; as demais não. Limite de contas.
do $$ begin
  -- Os testes anteriores já criaram contas; a primeira delas é a admin.
  assert (select count(*) from public.users where is_admin) = 1, 'exatamente um administrador';
  assert (select is_admin from public.users u join auth.users a on a.id = u.id
           order by a.ctid limit 1), 'a primeira conta é a administradora';
  assert public.needs_setup() = false, 'já existem contas';
end $$;

insert into auth.users (id, email) values ('90000000-0000-0000-0000-000000000009', 'nova@teste.com');
do $$ begin
  assert (select not is_admin from public.users where id = '90000000-0000-0000-0000-000000000009'), 'nova conta não é admin';
end $$;

-- Usuário comum não consegue se promover a administrador.
set role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000009', false);
do $$ begin
  begin
    update public.users set is_admin = true where id = '90000000-0000-0000-0000-000000000009';
    assert false, 'não deveria poder virar admin';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

-- Limite de contas.
update private.app_config set max_users = (select count(*) from auth.users);
do $$ begin
  begin
    insert into auth.users (email) values ('excedente@teste.com');
    assert false, 'acima do limite deveria falhar';
  exception when raise_exception then null; end;
end $$;
update private.app_config set max_users = 1000;

-- Visitante só descobre se precisa configurar; não lê a configuração.
set role anon;
do $$ begin
  assert public.needs_setup() = false;
  begin
    perform * from private.app_config;
    assert false, 'anon não deveria ler a configuração';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

do $$ begin
  assert public.admin_max_users() = 1000;
end $$;
set role authenticated;
do $$ begin
  begin
    perform public.admin_max_users();
    assert false, 'usuário comum não deveria executar admin_max_users';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
