-- =============================================================================
-- Meu Financeiro — segurança: Row Level Security, permissões e cadastro
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Row Level Security: cada usuário só enxerga e altera as próprias linhas.
-- `(select auth.uid())` é avaliado uma vez por consulta (recomendação do
-- Supabase para desempenho de RLS).
-- -----------------------------------------------------------------------------
alter table public.users                  enable row level security;
alter table public.accounts               enable row level security;
alter table public.categories             enable row level security;
alter table public.transactions           enable row level security;
alter table public.budgets                enable row level security;
alter table public.recurring_transactions enable row level security;
alter table public.installments           enable row level security;
alter table public.financial_goals        enable row level security;
alter table public.audio_sessions         enable row level security;
alter table public.ai_insights            enable row level security;

-- users: lê e edita só o próprio perfil (a criação é feita pelo gatilho de cadastro).
create policy users_select_own on public.users
  for select to authenticated using (id = (select auth.uid()));
create policy users_update_own on public.users
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Tabelas com CRUD completo do dono.
do $$
declare
  t text;
begin
  foreach t in array array[
    'accounts', 'categories', 'transactions', 'budgets',
    'recurring_transactions', 'installments', 'financial_goals', 'audio_sessions'
  ] loop
    execute format(
      'create policy %1$s_select_own on public.%1$s for select to authenticated
         using (user_id = (select auth.uid()))', t);
    execute format(
      'create policy %1$s_insert_own on public.%1$s for insert to authenticated
         with check (user_id = (select auth.uid()))', t);
    execute format(
      'create policy %1$s_update_own on public.%1$s for update to authenticated
         using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
    execute format(
      'create policy %1$s_delete_own on public.%1$s for delete to authenticated
         using (user_id = (select auth.uid()))', t);
  end loop;
end $$;

-- ai_insights: o usuário lê e apaga; quem grava é o backend (service role).
create policy ai_insights_select_own on public.ai_insights
  for select to authenticated using (user_id = (select auth.uid()));
create policy ai_insights_delete_own on public.ai_insights
  for delete to authenticated using (user_id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- Permissões: visitantes (anon) não acessam nada.
-- -----------------------------------------------------------------------------
revoke all on all tables    in schema public from anon;
revoke all on all functions in schema public from anon, public;
revoke all on all sequences in schema public from anon;

grant usage on schema public to authenticated;
grant select, insert, update, delete on
  public.accounts, public.categories, public.transactions, public.budgets,
  public.recurring_transactions, public.installments, public.financial_goals,
  public.audio_sessions
  to authenticated;
grant select on public.users to authenticated;
grant select, delete on public.ai_insights to authenticated;

-- Colunas que o cliente nunca altera diretamente.
revoke update on public.users from authenticated;
grant update (full_name, currency) on public.users to authenticated;

-- -----------------------------------------------------------------------------
-- Cadastro: ao criar o usuário no Auth, cria perfil, contas e categorias padrão.
-- security definer porque roda no contexto do Auth, antes de existir sessão.
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.users (id, full_name)
  values (new.id, nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), ''));

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

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
