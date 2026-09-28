-- =============================================================================
-- Meu Financeiro — esquema principal
--
-- Convenções:
--   * Toda chave primária é UUID.
--   * Valores financeiros são guardados em CENTAVOS (bigint), nunca em float.
--   * Toda linha pertence a um usuário (user_id) e é protegida por RLS
--     (veja 20260928000002_security.sql).
--   * Referências entre tabelas do usuário usam chave composta
--     (user_id, id). Assim o próprio banco impede que um lançamento aponte
--     para a conta ou categoria de outra pessoa, mesmo que alguém tente
--     forjar o UUID (chaves estrangeiras ignoram RLS, a chave composta não).
-- =============================================================================

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Tipos
-- -----------------------------------------------------------------------------
create type public.transaction_type as enum ('income', 'expense', 'transfer');
create type public.transaction_status as enum ('paid', 'pending');
create type public.transaction_source as enum ('manual', 'audio', 'recurring', 'installment');
create type public.category_kind as enum ('income', 'expense');
create type public.account_type as enum ('checking', 'savings', 'cash', 'credit_card', 'investment', 'other');
create type public.payment_method as enum ('cash', 'debit_card', 'credit_card', 'pix', 'bank_slip', 'bank_transfer', 'other');
create type public.recurrence_frequency as enum ('weekly', 'monthly', 'yearly');
create type public.audio_session_status as enum (
  'recording', 'uploading', 'transcribing', 'extracting', 'needs_review',
  'saving', 'completed', 'failed', 'cancelled'
);

-- -----------------------------------------------------------------------------
-- Utilitário: updated_at automático
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- -----------------------------------------------------------------------------
-- users (perfil público do usuário do Supabase Auth)
-- -----------------------------------------------------------------------------
create table public.users (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text check (char_length(full_name) <= 120),
  currency    char(3) not null default 'BRL',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger users_updated_at before update on public.users
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- accounts (conta corrente, poupança, carteira, cartão…)
-- -----------------------------------------------------------------------------
create table public.accounts (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null references public.users (id) on delete cascade,
  name                   text not null check (char_length(trim(name)) between 1 and 60),
  type                   public.account_type not null default 'checking',
  initial_balance_cents  bigint not null default 0
                         check (initial_balance_cents between -100000000000 and 100000000000),
  include_in_balance     boolean not null default true,
  archived               boolean not null default false,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (user_id, id)
);
create unique index accounts_user_name_uq on public.accounts (user_id, lower(name));
create trigger accounts_updated_at before update on public.accounts
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- categories (padrão + personalizadas)
-- -----------------------------------------------------------------------------
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users (id) on delete cascade,
  name        text not null check (char_length(trim(name)) between 1 and 40),
  kind        public.category_kind not null,
  icon        text not null default 'category',
  color       text not null default '#64748B' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  is_default  boolean not null default false,
  archived    boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, id)
);
create unique index categories_user_kind_name_uq on public.categories (user_id, kind, lower(name));
create trigger categories_updated_at before update on public.categories
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- recurring_transactions (modelo de receitas/despesas recorrentes)
-- -----------------------------------------------------------------------------
create table public.recurring_transactions (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.users (id) on delete cascade,
  type              public.transaction_type not null check (type in ('income', 'expense')),
  amount_cents      bigint not null check (amount_cents > 0 and amount_cents <= 100000000000),
  description       text not null check (char_length(trim(description)) between 1 and 120),
  category_id       uuid,
  account_id        uuid not null,
  payment_method    public.payment_method,
  frequency         public.recurrence_frequency not null default 'monthly',
  interval_count    smallint not null default 1 check (interval_count between 1 and 12),
  start_date        date not null,
  end_date          date check (end_date is null or end_date >= start_date),
  generated_until   date,
  active            boolean not null default true,
  notes             text check (char_length(notes) <= 500),
  idempotency_key   uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (user_id, id),
  foreign key (user_id, account_id)  references public.accounts (user_id, id),
  foreign key (user_id, category_id) references public.categories (user_id, id)
);
create index recurring_user_active_idx on public.recurring_transactions (user_id) where active;
create unique index recurring_idempotency_uq
  on public.recurring_transactions (user_id, idempotency_key) where idempotency_key is not null;
create trigger recurring_updated_at before update on public.recurring_transactions
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- installments (compra parcelada; cada parcela vira um lançamento)
-- -----------------------------------------------------------------------------
create table public.installments (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references public.users (id) on delete cascade,
  description         text not null check (char_length(trim(description)) between 1 and 120),
  total_amount_cents  bigint not null check (total_amount_cents > 0 and total_amount_cents <= 100000000000),
  installment_count   smallint not null check (installment_count between 2 and 120),
  first_due_date      date not null,
  category_id         uuid,
  account_id          uuid not null,
  payment_method      public.payment_method,
  idempotency_key     uuid,
  created_at          timestamptz not null default now(),
  unique (user_id, id),
  foreign key (user_id, account_id)  references public.accounts (user_id, id),
  foreign key (user_id, category_id) references public.categories (user_id, id)
);
create index installments_user_idx on public.installments (user_id);
create unique index installments_idempotency_uq
  on public.installments (user_id, idempotency_key) where idempotency_key is not null;

-- -----------------------------------------------------------------------------
-- audio_sessions (uma por gravação; o id é gerado no aparelho)
-- -----------------------------------------------------------------------------
create table public.audio_sessions (
  id              uuid primary key,
  user_id         uuid not null references public.users (id) on delete cascade,
  status          public.audio_session_status not null default 'recording',
  duration_ms     integer check (duration_ms between 0 and 60000),
  transcription   text check (char_length(transcription) <= 2000),
  extraction      jsonb,
  error_code      text,
  transaction_id  uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (user_id, id)
);
create index audio_sessions_user_created_idx on public.audio_sessions (user_id, created_at desc);
create trigger audio_sessions_updated_at before update on public.audio_sessions
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- transactions
-- -----------------------------------------------------------------------------
create table public.transactions (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null references public.users (id) on delete cascade,
  type                      public.transaction_type not null,
  status                    public.transaction_status not null default 'paid',
  amount_cents              bigint not null check (amount_cents > 0 and amount_cents <= 100000000000),
  description               text not null check (char_length(trim(description)) between 1 and 120),
  category_id               uuid,
  account_id                uuid not null,
  destination_account_id    uuid,
  transaction_date          date not null check (transaction_date between date '2000-01-01' and date '2100-12-31'),
  payment_method            public.payment_method,
  notes                     text check (char_length(notes) <= 500),
  source                    public.transaction_source not null default 'manual',
  transcription             text check (char_length(transcription) <= 2000),
  audio_session_id          uuid,
  recurring_transaction_id  uuid,
  installment_id            uuid,
  installment_number        smallint,
  idempotency_key           uuid,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),

  foreign key (user_id, account_id)             references public.accounts (user_id, id),
  foreign key (user_id, destination_account_id) references public.accounts (user_id, id),
  foreign key (user_id, category_id)            references public.categories (user_id, id),
  foreign key (user_id, audio_session_id)       references public.audio_sessions (user_id, id) on delete set null (audio_session_id),
  foreign key (user_id, recurring_transaction_id) references public.recurring_transactions (user_id, id) on delete set null (recurring_transaction_id),
  foreign key (user_id, installment_id)         references public.installments (user_id, id) on delete cascade,

  -- Regra 3: transferência entre contas próprias nunca é receita/despesa.
  constraint transfer_shape check (
    (type = 'transfer'
       and destination_account_id is not null
       and destination_account_id <> account_id
       and category_id is null)
    or
    (type <> 'transfer' and destination_account_id is null)
  ),
  constraint installment_shape check (
    (installment_id is null and installment_number is null)
    or (installment_id is not null and installment_number between 1 and 120)
  ),
  constraint audio_shape check (source <> 'audio' or transcription is not null)
);

-- Idempotência: a mesma chave nunca gera dois lançamentos.
create unique index transactions_idempotency_uq
  on public.transactions (user_id, idempotency_key) where idempotency_key is not null;
-- Uma sessão de áudio gera no máximo um lançamento "principal".
create unique index transactions_audio_session_uq
  on public.transactions (audio_session_id) where audio_session_id is not null and installment_number is null;
-- Uma ocorrência por data para cada recorrência.
create unique index transactions_recurring_occurrence_uq
  on public.transactions (recurring_transaction_id, transaction_date) where recurring_transaction_id is not null;
create unique index transactions_installment_number_uq
  on public.transactions (installment_id, installment_number) where installment_id is not null;

create index transactions_user_date_idx     on public.transactions (user_id, transaction_date desc);
create index transactions_user_status_idx   on public.transactions (user_id, status, transaction_date);
create index transactions_user_category_idx on public.transactions (user_id, category_id);
create index transactions_user_account_idx  on public.transactions (user_id, account_id);
create index transactions_user_dest_idx     on public.transactions (user_id, destination_account_id) where destination_account_id is not null;

create trigger transactions_updated_at before update on public.transactions
  for each row execute function public.set_updated_at();

alter table public.audio_sessions
  add foreign key (transaction_id) references public.transactions (id) on delete set null;

-- -----------------------------------------------------------------------------
-- budgets (limite mensal; month nulo = vale para todos os meses)
-- -----------------------------------------------------------------------------
create table public.budgets (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.users (id) on delete cascade,
  category_id   uuid,          -- nulo = orçamento mensal geral
  month         date check (month is null or extract(day from month) = 1),
  amount_cents  bigint not null check (amount_cents > 0 and amount_cents <= 100000000000),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  foreign key (user_id, category_id) references public.categories (user_id, id) on delete cascade,
  unique nulls not distinct (user_id, category_id, month)
);
create index budgets_user_idx on public.budgets (user_id);
create trigger budgets_updated_at before update on public.budgets
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- financial_goals
-- -----------------------------------------------------------------------------
create table public.financial_goals (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references public.users (id) on delete cascade,
  name                  text not null check (char_length(trim(name)) between 1 and 80),
  target_amount_cents   bigint not null check (target_amount_cents > 0 and target_amount_cents <= 100000000000),
  current_amount_cents  bigint not null default 0 check (current_amount_cents >= 0 and current_amount_cents <= 100000000000),
  target_date           date,
  icon                  text not null default 'savings',
  completed_at          timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index financial_goals_user_idx on public.financial_goals (user_id);
create trigger financial_goals_updated_at before update on public.financial_goals
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- ai_insights (análises geradas; sempre com os números usados)
-- -----------------------------------------------------------------------------
create table public.ai_insights (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users (id) on delete cascade,
  month       date not null check (extract(day from month) = 1),
  kind        text not null,
  severity    text not null default 'info' check (severity in ('info', 'warning', 'positive')),
  title       text not null,
  body        text not null,
  metrics     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index ai_insights_user_month_idx on public.ai_insights (user_id, month desc);
