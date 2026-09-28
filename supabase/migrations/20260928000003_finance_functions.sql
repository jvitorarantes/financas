-- =============================================================================
-- Meu Financeiro — regras financeiras no banco
--
-- Todas as funções chamadas pelo app são SECURITY INVOKER: rodam com as
-- permissões do usuário logado, então o RLS continua valendo dentro delas.
-- =============================================================================

-- Data de "hoje" no fuso do Brasil (o servidor roda em UTC).
create or replace function public.today_br()
returns date language sql stable as $$
  select (now() at time zone 'America/Sao_Paulo')::date
$$;

-- -----------------------------------------------------------------------------
-- Divisão de parcelas em centavos.
-- A soma das parcelas é SEMPRE igual ao total; a diferença de arredondamento
-- vai para a primeira parcela (ex.: R$ 100,00 em 3x = 33,34 + 33,33 + 33,33).
-- -----------------------------------------------------------------------------
create or replace function public.installment_amount_cents(
  p_total_cents bigint, p_count int, p_number int
) returns bigint language sql immutable as $$
  select (p_total_cents / p_count)
       + case when p_number = 1 then p_total_cents % p_count else 0 end
$$;

-- Data da n-ésima ocorrência (n começa em 0), sempre calculada a partir da data
-- inicial para não acumular deslocamento (31/01 → 28/02 → 31/03).
create or replace function public.occurrence_date(
  p_start date, p_frequency public.recurrence_frequency, p_interval int, p_n int
) returns date language sql immutable as $$
  select case p_frequency
    when 'weekly'  then p_start + (p_n * p_interval * 7)
    when 'monthly' then (p_start + make_interval(months => p_n * p_interval))::date
    when 'yearly'  then (p_start + make_interval(years  => p_n * p_interval))::date
  end
$$;

-- -----------------------------------------------------------------------------
-- create_transaction: único ponto de criação usado pelo app (manual e áudio).
--
-- payload (jsonb):
--   idempotency_key  uuid  obrigatório — a mesma chave nunca cria duas vezes
--   type             income | expense | transfer
--   amount_cents     inteiro > 0
--   description, category_id, account_id, destination_account_id,
--   transaction_date (YYYY-MM-DD), payment_method, notes,
--   status           paid | pending (opcional; padrão: pending se a data é futura)
--   installments     inteiro >= 2 (opcional, só despesa)
--   recurring        { frequency, interval_count, end_date } (opcional)
--   source           manual | audio
--   transcription, audio_session_id (quando source = audio)
--
-- Retorna { transaction_id, installment_id, recurring_id, created }.
-- `created = false` significa que a chave já tinha sido usada: nada foi
-- duplicado e o lançamento existente é devolvido.
-- -----------------------------------------------------------------------------
create or replace function public.create_transaction(payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid          uuid := auth.uid();
  v_key          uuid;
  v_type         public.transaction_type;
  v_amount       bigint;
  v_description  text;
  v_category     uuid;
  v_account      uuid;
  v_destination  uuid;
  v_date         date;
  v_method       public.payment_method;
  v_notes        text;
  v_status       public.transaction_status;
  v_source       public.transaction_source;
  v_transcription text;
  v_audio        uuid;
  v_installments int;
  v_recurring    jsonb;
  v_tx_id        uuid;
  v_inst_id      uuid;
  v_rec_id       uuid;
  v_today        date := public.today_br();
  v_due          date;
  i              int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  -- ---- leitura e validação ------------------------------------------------
  begin
    v_key         := (payload ->> 'idempotency_key')::uuid;
    v_type        := (payload ->> 'type')::public.transaction_type;
    v_amount      := (payload ->> 'amount_cents')::bigint;
    v_description := nullif(trim(payload ->> 'description'), '');
    v_category    := nullif(payload ->> 'category_id', '')::uuid;
    v_account     := (payload ->> 'account_id')::uuid;
    v_destination := nullif(payload ->> 'destination_account_id', '')::uuid;
    v_date        := coalesce((payload ->> 'transaction_date')::date, v_today);
    v_method      := nullif(payload ->> 'payment_method', '')::public.payment_method;
    v_notes       := nullif(trim(payload ->> 'notes'), '');
    v_source      := coalesce(nullif(payload ->> 'source', ''), 'manual')::public.transaction_source;
    v_transcription := nullif(trim(payload ->> 'transcription'), '');
    v_audio       := nullif(payload ->> 'audio_session_id', '')::uuid;
    v_installments := coalesce((payload ->> 'installments')::int, 1);
    v_recurring   := payload -> 'recurring';
    v_status      := nullif(payload ->> 'status', '')::public.transaction_status;
  exception when others then
    raise exception 'invalid_payload' using errcode = '22023';
  end;

  if v_key is null then
    raise exception 'missing_idempotency_key' using errcode = '22023';
  end if;
  if v_type is null or v_amount is null or v_amount <= 0 or v_amount > 100000000000 then
    raise exception 'invalid_amount' using errcode = '22023';
  end if;
  if v_description is null then
    raise exception 'missing_description' using errcode = '22023';
  end if;
  if v_account is null then
    raise exception 'missing_account' using errcode = '22023';
  end if;
  if v_source not in ('manual', 'audio') then
    raise exception 'invalid_source' using errcode = '22023';
  end if;
  if v_source = 'audio' and (v_audio is null or v_transcription is null) then
    raise exception 'missing_audio_session' using errcode = '22023';
  end if;
  if v_type = 'transfer' then
    if v_destination is null or v_destination = v_account then
      raise exception 'invalid_transfer_accounts' using errcode = '22023';
    end if;
    if v_installments > 1 or (v_recurring is not null and jsonb_typeof(v_recurring) = 'object') then
      raise exception 'transfer_cannot_repeat' using errcode = '22023';
    end if;
    v_category := null;
  else
    v_destination := null;
  end if;
  if v_installments < 1 or v_installments > 120 then
    raise exception 'invalid_installments' using errcode = '22023';
  end if;
  if v_installments > 1 and v_type <> 'expense' then
    raise exception 'installments_only_for_expense' using errcode = '22023';
  end if;
  if v_installments > 1 and v_recurring is not null and jsonb_typeof(v_recurring) = 'object' then
    raise exception 'installments_and_recurring' using errcode = '22023';
  end if;

  -- Regras 4 e 5: data futura é compromisso (pending), não dinheiro realizado.
  if v_status is null then
    v_status := case when v_date > v_today then 'pending' else 'paid' end;
  elsif v_status = 'paid' and v_date > v_today then
    raise exception 'future_transaction_cannot_be_paid' using errcode = '22023';
  end if;

  -- ---- idempotência: chave já usada? devolve o que existe -------------------
  select t.id into v_tx_id from public.transactions t
   where t.user_id = v_uid and t.idempotency_key = v_key;
  if found then
    return jsonb_build_object('transaction_id', v_tx_id, 'created', false);
  end if;
  select ins.id into v_inst_id from public.installments ins
   where ins.user_id = v_uid and ins.idempotency_key = v_key;
  if found then
    return jsonb_build_object('installment_id', v_inst_id, 'created', false,
      'transaction_id', (select id from public.transactions
                          where installment_id = v_inst_id and installment_number = 1));
  end if;

  -- ---- compra parcelada ------------------------------------------------------
  if v_installments > 1 then
    insert into public.installments
      (user_id, description, total_amount_cents, installment_count, first_due_date,
       category_id, account_id, payment_method, idempotency_key)
    values
      (v_uid, v_description, v_amount, v_installments, v_date,
       v_category, v_account, v_method, v_key)
    on conflict (user_id, idempotency_key) where idempotency_key is not null do nothing
    returning id into v_inst_id;

    if v_inst_id is null then  -- outra chamada concorrente venceu
      select id into v_inst_id from public.installments
       where user_id = v_uid and idempotency_key = v_key;
      return jsonb_build_object('installment_id', v_inst_id, 'created', false,
        'transaction_id', (select id from public.transactions
                            where installment_id = v_inst_id and installment_number = 1));
    end if;

    for i in 1..v_installments loop
      v_due := public.occurrence_date(v_date, 'monthly', 1, i - 1);
      insert into public.transactions
        (user_id, type, status, amount_cents, description, category_id, account_id,
         transaction_date, payment_method, notes, source, transcription,
         audio_session_id, installment_id, installment_number)
      values
        (v_uid, 'expense',
         case when i = 1 then v_status
              when v_due > v_today then 'pending'
              else v_status end,
         public.installment_amount_cents(v_amount, v_installments, i),
         format('%s (%s/%s)', v_description, i, v_installments),
         v_category, v_account, v_due, v_method, v_notes,
         case when v_source = 'audio' then 'audio' else 'installment' end::public.transaction_source,
         v_transcription, v_audio, v_inst_id, i)
      returning id into v_rec_id;  -- reaproveita variável só para capturar a 1ª
      if i = 1 then v_tx_id := v_rec_id; end if;
    end loop;
    v_rec_id := null;

  -- ---- lançamento simples (com ou sem recorrência) ---------------------------
  else
    if v_recurring is not null and jsonb_typeof(v_recurring) = 'object' then
      if v_type = 'transfer' then
        raise exception 'transfer_cannot_repeat' using errcode = '22023';
      end if;
      insert into public.recurring_transactions
        (user_id, type, amount_cents, description, category_id, account_id, payment_method,
         frequency, interval_count, start_date, end_date, generated_until, notes, idempotency_key)
      values
        (v_uid, v_type, v_amount, v_description, v_category, v_account, v_method,
         coalesce(nullif(v_recurring ->> 'frequency', ''), 'monthly')::public.recurrence_frequency,
         coalesce((v_recurring ->> 'interval_count')::int, 1),
         v_date,
         nullif(v_recurring ->> 'end_date', '')::date,
         v_date, v_notes, v_key)
      on conflict (user_id, idempotency_key) where idempotency_key is not null do nothing
      returning id into v_rec_id;
      if v_rec_id is null then
        select r.id, t.id into v_rec_id, v_tx_id
          from public.recurring_transactions r
          left join public.transactions t on t.recurring_transaction_id = r.id and t.transaction_date = r.start_date
         where r.user_id = v_uid and r.idempotency_key = v_key;
        return jsonb_build_object('transaction_id', v_tx_id, 'recurring_id', v_rec_id, 'created', false);
      end if;
    end if;

    insert into public.transactions
      (user_id, type, status, amount_cents, description, category_id, account_id,
       destination_account_id, transaction_date, payment_method, notes, source,
       transcription, audio_session_id, recurring_transaction_id, idempotency_key)
    values
      (v_uid, v_type, v_status, v_amount, v_description, v_category, v_account,
       v_destination, v_date, v_method, v_notes, v_source,
       v_transcription, v_audio, v_rec_id, v_key)
    on conflict (user_id, idempotency_key) where idempotency_key is not null do nothing
    returning id into v_tx_id;

    if v_tx_id is null then
      select id into v_tx_id from public.transactions
       where user_id = v_uid and idempotency_key = v_key;
      return jsonb_build_object('transaction_id', v_tx_id, 'created', false);
    end if;
  end if;

  -- ---- sessão de áudio concluída ---------------------------------------------
  if v_audio is not null then
    update public.audio_sessions
       set status = 'completed', transaction_id = v_tx_id, error_code = null
     where id = v_audio and user_id = v_uid;
  end if;

  if v_rec_id is not null then
    perform public.materialize_recurring(v_today + 62);
  end if;

  return jsonb_build_object(
    'transaction_id', v_tx_id,
    'installment_id', v_inst_id,
    'recurring_id',   v_rec_id,
    'created',        true
  );
end $$;

-- -----------------------------------------------------------------------------
-- materialize_recurring: cria as ocorrências futuras das recorrências ativas
-- até p_until como lançamentos PENDENTES (o usuário marca como pago depois).
-- Idempotente: pode ser chamada quantas vezes quiser.
-- -----------------------------------------------------------------------------
create or replace function public.materialize_recurring(p_until date default null)
returns integer
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_until date := coalesce(p_until, public.today_br() + 62);
  r       record;
  n       int;
  d       date;
  created int := 0;
  inserted int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_until > public.today_br() + 400 then
    v_until := public.today_br() + 400;   -- limite de segurança
  end if;

  for r in
    select * from public.recurring_transactions
     where user_id = v_uid and active
       and (generated_until is null or generated_until < v_until)
       and (end_date is null or generated_until is null or generated_until < end_date)
  loop
    n := 0;
    loop
      d := public.occurrence_date(r.start_date, r.frequency, r.interval_count, n);
      exit when d > v_until or (r.end_date is not null and d > r.end_date) or n > 520;
      if r.generated_until is null or d > r.generated_until then
        insert into public.transactions
          (user_id, type, status, amount_cents, description, category_id, account_id,
           transaction_date, payment_method, notes, source, recurring_transaction_id)
        values
          (v_uid, r.type, 'pending', r.amount_cents, r.description, r.category_id,
           r.account_id, d, r.payment_method, r.notes, 'recurring', r.id)
        on conflict (recurring_transaction_id, transaction_date)
          where recurring_transaction_id is not null do nothing;
        get diagnostics inserted = row_count;
        created := created + inserted;
      end if;
      n := n + 1;
    end loop;

    update public.recurring_transactions
       set generated_until = least(v_until, coalesce(end_date, v_until))
     where id = r.id;
  end loop;

  return created;
end $$;

-- -----------------------------------------------------------------------------
-- Saldos por conta. Só lançamentos PAGOS entram no saldo atual.
-- Transferência: sai da conta de origem e entra na de destino (soma zero).
-- -----------------------------------------------------------------------------
create or replace view public.account_balances
with (security_invoker = true) as
select
  a.id   as account_id,
  a.user_id,
  a.name,
  a.type,
  a.include_in_balance,
  a.archived,
  a.initial_balance_cents
    + coalesce((
        select sum(case
                 when t.type = 'income'   and t.account_id = a.id             then  t.amount_cents
                 when t.type = 'expense'  and t.account_id = a.id             then -t.amount_cents
                 when t.type = 'transfer' and t.account_id = a.id             then -t.amount_cents
                 when t.type = 'transfer' and t.destination_account_id = a.id then  t.amount_cents
                 else 0 end)
          from public.transactions t
         where t.user_id = a.user_id
           and t.status = 'paid'
           and (t.account_id = a.id or t.destination_account_id = a.id)
      ), 0) as balance_cents
from public.accounts a;

grant select on public.account_balances to authenticated;

-- -----------------------------------------------------------------------------
-- dashboard_summary: números da tela inicial para um mês.
--
--   current_balance_cents   = soma dos saldos (só contas "incluir no saldo")
--   month_income_cents      = receitas PAGAS no mês
--   month_expense_cents     = despesas PAGAS no mês
--   pending_expense_cents   = despesas pendentes até o fim do mês (inclui atrasadas)
--   pending_income_cents    = receitas previstas até o fim do mês (NÃO somam no saldo)
--   projected_balance_cents = saldo atual − despesas pendentes até o fim do mês
--
-- Transferências nunca entram em receitas/despesas.
-- -----------------------------------------------------------------------------
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
  v_income  bigint;
  v_expense bigint;
  v_pending_exp bigint;
  v_pending_inc bigint;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select coalesce(sum(balance_cents), 0) into v_balance
    from public.account_balances
   where user_id = v_uid and include_in_balance;

  select
    coalesce(sum(amount_cents) filter (where type = 'income'  and status = 'paid'), 0),
    coalesce(sum(amount_cents) filter (where type = 'expense' and status = 'paid'), 0)
    into v_income, v_expense
    from public.transactions
   where user_id = v_uid and transaction_date between v_start and v_end;

  select
    coalesce(sum(t.amount_cents) filter (where t.type = 'expense'), 0),
    coalesce(sum(t.amount_cents) filter (where t.type = 'income'), 0)
    into v_pending_exp, v_pending_inc
    from public.transactions t
    join public.accounts a on a.id = t.account_id
   where t.user_id = v_uid and t.status = 'pending'
     and t.transaction_date <= v_end
     and a.include_in_balance;

  return jsonb_build_object(
    'month',                   v_start,
    'current_balance_cents',   v_balance,
    'month_income_cents',      v_income,
    'month_expense_cents',     v_expense,
    'pending_expense_cents',   v_pending_exp,
    'pending_income_cents',    v_pending_inc,
    'projected_balance_cents', v_balance - v_pending_exp
  );
end $$;

-- -----------------------------------------------------------------------------
-- Gastos pagos por categoria no mês (para gráfico, orçamento e análises).
-- -----------------------------------------------------------------------------
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
     and t.type = 'expense' and t.status = 'paid'
     and t.transaction_date between b.s and b.e
   group by c.id, c.name, c.icon, c.color
   order by 5 desc
$$;

-- -----------------------------------------------------------------------------
-- Situação dos orçamentos no mês. Um orçamento específico do mês substitui o
-- orçamento padrão (month nulo) da mesma categoria.
-- -----------------------------------------------------------------------------
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
            where t.user_id = auth.uid() and t.type = 'expense' and t.status = 'paid'
              and t.transaction_date between bounds.s and bounds.e
              and (e.category_id is null or t.category_id = e.category_id)
         ), 0)::bigint
    from effective e
    left join public.categories c on c.id = e.category_id
   order by e.category_id nulls first, 3
$$;

-- -----------------------------------------------------------------------------
-- Totais pagos por mês e categoria (base das análises com IA).
-- -----------------------------------------------------------------------------
create or replace function public.monthly_category_totals(p_from date, p_to date)
returns table (month date, type public.transaction_type, category_id uuid, category_name text, total_cents bigint, tx_count bigint)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select date_trunc('month', t.transaction_date)::date, t.type, t.category_id,
         coalesce(c.name, 'Sem categoria'), sum(t.amount_cents)::bigint, count(*)
    from public.transactions t
    left join public.categories c on c.id = t.category_id
   where t.user_id = auth.uid()
     and t.status = 'paid' and t.type in ('income', 'expense')
     and t.transaction_date between p_from and p_to
   group by 1, 2, 3, 4
   order by 1, 2, 5 desc
$$;

-- -----------------------------------------------------------------------------
-- Permissões das funções: só usuários logados executam.
-- -----------------------------------------------------------------------------
revoke all on function public.today_br()                                         from public, anon;
revoke all on function public.installment_amount_cents(bigint, int, int)          from public, anon;
revoke all on function public.occurrence_date(date, public.recurrence_frequency, int, int) from public, anon;
revoke all on function public.create_transaction(jsonb)                           from public, anon;
revoke all on function public.materialize_recurring(date)                         from public, anon;
revoke all on function public.dashboard_summary(date)                             from public, anon;
revoke all on function public.spending_by_category(date)                          from public, anon;
revoke all on function public.budget_status(date)                                 from public, anon;
revoke all on function public.monthly_category_totals(date, date)                 from public, anon;

grant execute on function public.today_br()                                        to authenticated;
grant execute on function public.installment_amount_cents(bigint, int, int)         to authenticated;
grant execute on function public.occurrence_date(date, public.recurrence_frequency, int, int) to authenticated;
grant execute on function public.create_transaction(jsonb)                          to authenticated;
grant execute on function public.materialize_recurring(date)                        to authenticated;
grant execute on function public.dashboard_summary(date)                            to authenticated;
grant execute on function public.spending_by_category(date)                         to authenticated;
grant execute on function public.budget_status(date)                                to authenticated;
grant execute on function public.monthly_category_totals(date, date)                to authenticated;
