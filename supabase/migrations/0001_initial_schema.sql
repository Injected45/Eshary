-- 0001_initial_schema.sql
-- Initial schema for شركة الرحالة financial operations app.
-- Mirrors localStorage `rahala_db_v21` shape from project_web.html.

begin;

-- =========================================================================
-- Enums
-- =========================================================================

create type transfer_status as enum ('daily', 'archived');
create type currency_buy_status as enum ('pending', 'daily', 'archived');

-- =========================================================================
-- profiles
-- =========================================================================

create table profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now()
);

-- =========================================================================
-- companies (the user's own companies — "my company" in the source UI)
-- =========================================================================

create table companies (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references profiles (id) on delete cascade,
  name        text not null,
  start_ref   text not null,
  created_at  timestamptz not null default now()
);

create index companies_owner_id_idx on companies (owner_id);

-- =========================================================================
-- exchanges (exchange offices nested under each company in source JSON)
-- ownership is derived through companies.owner_id (no direct owner_id column,
-- to keep a single source of truth for nested ownership).
-- =========================================================================

create table exchanges (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies (id) on delete cascade,
  name        text not null,
  balance     numeric(14,2) not null default 0,
  our_code    text,
  created_at  timestamptz not null default now()
);

create index exchanges_company_id_idx on exchanges (company_id);

-- =========================================================================
-- clients (counterparties when buying USD)
-- =========================================================================

create table clients (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references profiles (id) on delete cascade,
  name        text not null,
  company     text,
  code        text,
  created_at  timestamptz not null default now()
);

create index clients_owner_id_idx on clients (owner_id);

-- =========================================================================
-- transfers (outgoing USD transfers — "dailyTransfers" + "globalSold")
-- =========================================================================

create table transfers (
  id                              uuid primary key default gen_random_uuid(),
  owner_id                        uuid not null references profiles (id) on delete cascade,
  company_id                      uuid not null references companies (id) on delete restrict,
  exchange_id                     uuid not null references exchanges (id) on delete restrict,
  beneficiary_name                text not null,
  beneficiary_account_company     text,
  beneficiary_code                text,
  amount                          numeric(14,2) not null check (amount > 0),
  reference                       text not null,
  status                          transfer_status not null default 'daily',
  created_at                      timestamptz not null default now(),
  archived_at                     timestamptz
);

create index transfers_owner_id_idx on transfers (owner_id);
create index transfers_status_idx   on transfers (status);

-- =========================================================================
-- currency_buys (incoming USD purchases — "dailyBuy" + "currencyPending"
-- + "globalBought")
-- =========================================================================

create table currency_buys (
  id                       uuid primary key default gen_random_uuid(),
  owner_id                 uuid not null references profiles (id) on delete cascade,
  my_company_id            uuid not null references companies (id) on delete restrict,
  exchange_id              uuid not null references exchanges (id) on delete restrict,
  client_id                uuid references clients (id) on delete set null,
  client_from_account      text,
  usd_amount               numeric(14,2) not null check (usd_amount > 0),
  rate                     numeric(10,4) not null check (rate > 0),
  lyd_amount               numeric(14,2) not null check (lyd_amount >= 0),
  status                   currency_buy_status not null default 'daily',
  created_at               timestamptz not null default now(),
  archived_at              timestamptz
);

create index currency_buys_owner_id_idx on currency_buys (owner_id);
create index currency_buys_status_idx   on currency_buys (status);

commit;
