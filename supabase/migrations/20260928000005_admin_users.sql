-- =============================================================================
-- Administração de usuários
--
-- * A PRIMEIRA conta criada no projeto vira administradora.
-- * Depois disso, o cadastro público deve ficar desligado no Supabase
--   (Authentication → Sign In / Providers → Allow new users to sign up) e as
--   contas são criadas pelo administrador na página "Administração" do app
--   (Edge Function admin-users, que usa a API administrativa do Supabase).
-- * Limite de contas no projeto (padrão 20), conferido no próprio banco:
--   update private.app_config set max_users = 30;
-- =============================================================================

alter table public.users add column if not exists is_admin boolean not null default false;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to service_role;

create table if not exists private.app_config (
  id         boolean primary key default true check (id),  -- linha única
  max_users  integer not null default 20 check (max_users > 0)
);
insert into private.app_config (id) values (true) on conflict do nothing;
grant select on private.app_config to service_role;

-- O app pergunta se ainda não existe nenhuma conta (para oferecer o cadastro
-- do administrador na primeira vez). Não revela mais nada.
create or replace function public.needs_setup()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select not exists (select 1 from auth.users)
$$;
revoke all on function public.needs_setup() from public;
grant execute on function public.needs_setup() to anon, authenticated;

-- Limite de contas: vale para qualquer forma de cadastro.
create or replace function public.enforce_user_limit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if (select count(*) from auth.users) >= (select max_users from private.app_config where id) then
    raise exception 'user_limit_reached' using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke all on function public.enforce_user_limit() from public, anon, authenticated;

drop trigger if exists before_auth_user_created on auth.users;
create trigger before_auth_user_created
  before insert on auth.users
  for each row execute function public.enforce_user_limit();

-- Cadastro: a primeira conta do projeto é a administradora.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.users (id, full_name, is_admin)
  values (
    new.id,
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), ''),
    not exists (select 1 from public.users)
  );

  insert into public.accounts (user_id, name, type) values
    (new.id, 'Conta corrente', 'checking'),
    (new.id, 'Poupança',       'savings'),
    (new.id, 'Carteira',       'cash');

  insert into public.categories (user_id, name, kind, icon, color, is_default) values
    (new.id, 'Alimentação',    'expense', 'restaurant',     '#F97316', true),
    (new.id, 'Moradia',        'expense', 'home',           '#8B5CF6', true),
    (new.id, 'Transporte',     'expense', 'directions_car', '#0EA5E9', true),
    (new.id, 'Saúde',          'expense', 'favorite',       '#EF4444', true),
    (new.id, 'Lazer',          'expense', 'celebration',    '#EC4899', true),
    (new.id, 'Compras',        'expense', 'shopping_bag',   '#F59E0B', true),
    (new.id, 'Educação',       'expense', 'school',         '#6366F1', true),
    (new.id, 'Contas',         'expense', 'receipt_long',   '#14B8A6', true),
    (new.id, 'Outros',         'expense', 'category',       '#64748B', true),
    (new.id, 'Salário',        'income',  'work',           '#16A34A', true),
    (new.id, 'Freelance',      'income',  'laptop',         '#22C55E', true),
    (new.id, 'Investimentos',  'income',  'trending_up',    '#10B981', true),
    (new.id, 'Outras receitas','income',  'payments',       '#84CC16', true);

  return new;
end $$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

-- Limite de contas para a Edge Function admin-users (o schema private não é
-- exposto pela API).
create or replace function public.admin_max_users()
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select max_users from private.app_config where id
$$;
revoke all on function public.admin_max_users() from public, anon, authenticated;
grant execute on function public.admin_max_users() to service_role;
