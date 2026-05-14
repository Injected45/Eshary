-- 0027_enable_realtime.sql
-- Adds the workflow tables to Supabase's `supabase_realtime` publication
-- so postgres_changes events fire on INSERT/UPDATE/DELETE. Without this,
-- the realtime_sync_provider in the Flutter app receives no events.
--
-- Side effect: every row change on these tables is streamed to subscribed
-- clients, gated by their JWT's RLS access. Admins see their data; an
-- employee's anonymous JWT sees only what their SELECT policies allow.
-- This means cross-tenant leakage is not possible via realtime.

begin;

-- alter publication is idempotent when wrapped in a do-block that
-- swallows the "already member of publication" error.
do $$
begin
  alter publication supabase_realtime add table transfers;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table currency_buys;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table exchanges;
exception when duplicate_object then null;
end $$;

commit;
