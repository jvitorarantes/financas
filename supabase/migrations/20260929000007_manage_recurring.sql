-- =============================================================================
-- Gerenciar recorrências (aba "Recorrentes"): editar e excluir.
--
-- Editar muda o modelo e REFAZ só os lançamentos previstos de hoje em diante;
-- o que já foi pago (e previstos atrasados) fica como está.
-- Excluir apaga o modelo e os previstos de hoje em diante; o histórico pago
-- continua nas movimentações (sem vínculo com a recorrência).
-- =============================================================================

create or replace function public.update_recurring(p_id uuid, payload jsonb)
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_today date := public.today_br();
  r       public.recurring_transactions;
  v_amount bigint;
  v_description text;
  v_interval int;
  v_frequency public.recurrence_frequency;
  v_end date;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into r from public.recurring_transactions where id = p_id and user_id = v_uid;
  if not found then
    raise exception 'recurring_not_found' using errcode = 'P0002';
  end if;

  begin
    v_amount      := coalesce((payload ->> 'amount_cents')::bigint, r.amount_cents);
    v_description := coalesce(nullif(trim(payload ->> 'description'), ''), r.description);
    v_frequency   := coalesce(nullif(payload ->> 'frequency', ''), r.frequency::text)::public.recurrence_frequency;
    v_interval    := coalesce((payload ->> 'interval_count')::int, r.interval_count);
    v_end         := case when payload ? 'end_date' then nullif(payload ->> 'end_date', '')::date else r.end_date end;
  exception when others then
    raise exception 'invalid_payload' using errcode = '22023';
  end;

  if v_amount <= 0 or v_amount > 100000000000 then
    raise exception 'invalid_amount' using errcode = '22023';
  end if;
  if v_interval < 1 or v_interval > 12 then
    raise exception 'invalid_interval' using errcode = '22023';
  end if;
  if v_end is not null and v_end < r.start_date then
    raise exception 'invalid_end_date' using errcode = '22023';
  end if;

  update public.recurring_transactions set
    amount_cents   = v_amount,
    description    = v_description,
    category_id    = case when payload ? 'category_id' then nullif(payload ->> 'category_id', '')::uuid else category_id end,
    account_id     = coalesce(nullif(payload ->> 'account_id', '')::uuid, account_id),
    payment_method = case when payload ? 'payment_method'
                          then nullif(payload ->> 'payment_method', '')::public.payment_method
                          else payment_method end,
    frequency      = v_frequency,
    interval_count = v_interval,
    end_date       = v_end,
    generated_until = v_today - 1
  where id = p_id;

  -- Refaz os previstos a partir de hoje com os novos dados.
  delete from public.transactions
   where recurring_transaction_id = p_id and status = 'pending' and transaction_date >= v_today;

  if r.active then
    perform public.materialize_recurring(greatest(v_today + 62, coalesce(r.generated_until, v_today)));
  end if;
end $$;

create or replace function public.delete_recurring(p_id uuid)
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not exists (select 1 from public.recurring_transactions where id = p_id and user_id = v_uid) then
    raise exception 'recurring_not_found' using errcode = 'P0002';
  end if;
  delete from public.transactions
   where recurring_transaction_id = p_id and status = 'pending' and transaction_date >= public.today_br();
  delete from public.recurring_transactions where id = p_id;
end $$;

revoke all on function public.update_recurring(uuid, jsonb) from public, anon;
revoke all on function public.delete_recurring(uuid)        from public, anon;
grant execute on function public.update_recurring(uuid, jsonb) to authenticated;
grant execute on function public.delete_recurring(uuid)        to authenticated;
