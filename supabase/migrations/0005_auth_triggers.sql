-- 0005_auth_triggers.sql
-- Auto-provision a `profiles` row whenever a new auth.users row is created.
-- Replaces the client-side upsert previously done in AuthRepository.signUp,
-- which only fired on the email/password path. This trigger covers every
-- auth flow Supabase supports (email, OAuth, magic link, etc).

begin;

create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

commit;
