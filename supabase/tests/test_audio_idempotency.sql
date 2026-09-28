-- Sessão de áudio: confirmar duas vezes não duplica; sessão fica concluída.
insert into auth.users (id, email) values ('d0000000-0000-0000-0000-00000000000d', 'duda@teste.com');
set role authenticated;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-00000000000d', false);

insert into public.audio_sessions (id, user_id, status, duration_ms, transcription)
values ('5e550000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-00000000000d',
        'needs_review', 4200, 'Gastei 85 reais de gasolina hoje no cartão.');

do $$
declare
  p jsonb;
  r1 jsonb; r2 jsonb;
begin
  p := jsonb_build_object(
    'idempotency_key', '5e550000-0000-0000-0000-000000000001',
    'audio_session_id', '5e550000-0000-0000-0000-000000000001',
    'source', 'audio', 'transcription', 'Gastei 85 reais de gasolina hoje no cartão.',
    'type', 'expense', 'amount_cents', 8500, 'description', 'Gasolina',
    'category_id', (select id from public.categories where name = 'Transporte'),
    'account_id', (select id from public.accounts where name = 'Conta corrente'),
    'payment_method', 'credit_card');
  r1 := public.create_transaction(p);
  r2 := public.create_transaction(p);
  assert (r1 ->> 'created')::boolean and not (r2 ->> 'created')::boolean, 'duplo toque';
  assert (select count(*) from public.transactions) = 1, 'um único lançamento';
  assert (select source = 'audio' and transcription is not null from public.transactions), 'origem áudio';
  assert (select status = 'completed' and transaction_id = (r1 ->> 'transaction_id')::uuid
            from public.audio_sessions), 'sessão concluída e ligada ao lançamento';

  -- Mesmo com outra chave, a sessão de áudio não gera um segundo lançamento.
  begin
    perform public.create_transaction(p || jsonb_build_object('idempotency_key', gen_random_uuid()));
    assert false, 'segunda gravação da mesma sessão deveria falhar';
  exception when unique_violation then null; end;
end $$;
