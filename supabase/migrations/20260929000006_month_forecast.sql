-- =============================================================================
-- Despesas do mês incluem as previstas (pendentes) daquele mês.
--
--   month_expense_cents          = despesas pagas + previstas DO MÊS
--   month_expense_paid_cents     = só as pagas
--   month_expense_pending_cents  = só as previstas do mês (alerta de contas)
--   pending_expense_cents        = igual a month_expense_pending_cents
--   month_income_cents           = receitas recebidas (receita futura não é
--                                  dinheiro disponível)
--   month_income_pending_cents   = receitas previstas do mês
--   current_balance_cents        = só o que já foi pago/recebido
--   projected_balance_cents      = saldo atual − despesas ainda não pagas até o
--                                  fim do mês (inclui atrasadas de meses anteriores)
--
-- Orçamento e gastos por categoria também contam as previstas do mês.
-- =============================================================================

create or replace function public.dashboard_summary(p_month date default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_start date := date_trunc('month', coalesce(p_month, public.today_br()))::date;
  v_end   date := (date_trunc('month', coalesce(p_month, public.today_br())) + interval '1 month - 1 day')::date;
  v_balance bigint;
  v_income_paid bigint;
  v_income_pending bigint;
  v_expense_paid bigint;
  v_expense_pending bigint;
  v_unpaid_until_end bigint;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select coalesce(sum(balance_cents), 0) into v_balance
    from public.account_balances
   where user_id = v_uid and include_in_balance;

  select
    coalesce(sum(t.amount_cents) filter (where t.type = 'income'  and t.status = 'paid'), 0),
    coalesce(sum(t.amount_cents) filter (where t.type = 'income'  and t.status = 'pending'), 0),
    coalesce(sum(t.amount_cents) filter (where t.type = 'expense' and t.status = 'paid'), 0),
    coalesce(sum(t.amount_cents) filter (where t.type = 'expense' and t.status = 'pending'), 0)
    into v_income_paid, v_income_pending, v_expense_paid, v_expense_pending
    from public.transactions t
   where t.user_id = v_uid
     and t.transaction_date between v_start and v_end;

  select coalesce(sum(t.amount_cents), 0) into v_unpaid_until_end
    from public.transactions t
    join public.accounts a on a.id = t.account_id
   where t.user_id = v_uid and t.type = 'expense' and t.status = 'pending'
     and t.transaction_date <= v_end
     and a.include_in_balance;

  return jsonb_build_object(
    'month',                        v_start,
    'current_balance_cents',        v_balance,
    'month_income_cents',           v_income_paid,
    'month_income_pending_cents',   v_income_pending,
    'month_expense_cents',          v_expense_paid + v_expense_pending,
    'month_expense_paid_cents',     v_expense_paid,
    'month_expense_pending_cents',  v_expense_pending,
    'pending_expense_cents',        v_expense_pending,
    'pending_income_cents',         v_income_pending,
    'projected_balance_cents',      v_balance - v_unpaid_until_end
  );
end $$;

create or replace function public.spending_by_category(p_month date default null)
returns table (
  category_id uuid, name text, icon text, color text, total_cents bigint, tx_count bigint
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with bounds as (
    select date_trunc('month', coalesce(p_month, public.today_br()))::date as s,
           (date_trunc('month', coalesce(p_month, public.today_br())) + interval '1 month - 1 day')::date as e
  )
  select c.id, coalesce(c.name, 'Sem categoria'), coalesce(c.icon, 'category'),
         coalesce(c.color, '#94A3B8'), sum(t.amount_cents)::bigint, count(*)
    from public.transactions t
    cross join bounds b
    left join public.categories c on c.id = t.category_id
   where t.user_id = auth.uid()
     and t.type = 'expense'
     and t.transaction_date between b.s and b.e
   group by c.id, c.name, c.icon, c.color
   order by 5 desc
$$;

create or replace function public.budget_status(p_month date default null)
returns table (
  budget_id uuid, category_id uuid, category_name text, icon text, color text,
  limit_cents bigint, spent_cents bigint
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with bounds as (
    select date_trunc('month', coalesce(p_month, public.today_br()))::date as s,
           (date_trunc('month', coalesce(p_month, public.today_br())) + interval '1 month - 1 day')::date as e
  ),
  effective as (
    select distinct on (b.category_id) b.*
      from public.budgets b, bounds
     where b.user_id = auth.uid()
       and (b.month is null or b.month = bounds.s)
     order by b.category_id, b.month nulls last
  )
  select e.id, e.category_id, coalesce(c.name, 'Orçamento geral'),
         coalesce(c.icon, 'account_balance_wallet'), coalesce(c.color, '#2563EB'),
         e.amount_cents,
         coalesce((
           select sum(t.amount_cents) from public.transactions t, bounds
            where t.user_id = auth.uid() and t.type = 'expense'
              and t.transaction_date between bounds.s and bounds.e
              and (e.category_id is null or t.category_id = e.category_id)
         ), 0)::bigint
    from effective e
    left join public.categories c on c.id = e.category_id
   order by e.category_id nulls first, 3
$$;

revoke all on function public.dashboard_summary(date)    from public, anon;
revoke all on function public.spending_by_category(date) from public, anon;
revoke all on function public.budget_status(date)        from public, anon;
grant execute on function public.dashboard_summary(date)    to authenticated;
grant execute on function public.spending_by_category(date) to authenticated;
grant execute on function public.budget_status(date)        to authenticated;
